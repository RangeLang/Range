<script lang="ts">
  import { dev } from "$app/environment";
  import { getContext, onDestroy, onMount } from "svelte";
  import type { Snippet } from "svelte";
  import {
    DEFAULT_INTRO_MIX,
    type IntroMixChannel,
    type IntroMixSettings,
  } from "$lib/audio/intro-mix";
  import {
    RANGE_SOUND_MANAGER_CONTEXT,
    RANGE_RHYTHM_SUBDIVISION_MS,
    type RangeSoundManager,
    type RangeSoundRoute,
  } from "$lib/audio/sound-manager";
  import {
    RANGE_LAYOUT_TRACKER_CONTEXT,
    type RangeLayoutTracker,
  } from "$lib/layout/layout-tracker";

  type FigureAudioPhase = "before" | "entering" | "centered" | "passed";
  type TransportState = "stopped" | "starting" | "running";

  type FigureAudioState = {
    phase: FigureAudioPhase;
    lastDistance: number;
  };

  type FigureScrollPosition = {
    distancePastCenter: number;
    height: number;
    entryStartDistance: number;
    centerRadius: number;
    progress: number;
    audioExitGain: number;
  };

  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );
  const layoutTracker = getContext<RangeLayoutTracker | undefined>(
    RANGE_LAYOUT_TRACKER_CONTEXT,
  );

  let {
    functionIntro,
    functionCode,
    bindingIntro,
    bindingCode,
    bindingDetail,
    identityIntro,
    identityDetail,
  }: {
    functionIntro: Snippet;
    functionCode: Snippet;
    bindingIntro: Snippet;
    bindingCode: Snippet;
    bindingDetail: Snippet;
    identityIntro: Snippet;
    identityDetail: Snippet;
  } = $props();

  const subdivisionMilliseconds = RANGE_RHYTHM_SUBDIVISION_MS;
  const identityValuePan = {
    identity: -0.46,
    value: 0.46,
  } as const;
  const trianglePanDepth = 0.68;
  const trianglePanStep = Math.PI / 12;
  const squareBeatPan = [-0.12, 0.12, 0.12, -0.12] as const;
  const enumCases = ["north", "east", "south", "west"] as const;
  let playing = $state(false);
  let audioEnabled = $state(false);
  let transportState = $state<TransportState>("stopped");
  let autoScrolling = $state(false);
  let autoScrollFrame: number | undefined;
  let nextAutoScrollTick = 0;
  let autoScrollAnchor: Element | undefined;
  let autoScrollAnchorPasses = 0;
  let step = $state(-1);
  let rhythmTick = 0;
  let triangleBeat = $state(-1);
  let trianglePanPhase = -Math.PI / 2;
  let squareBeat = $state(-1);
  let enumPulse = $state(-1);
  let enumCaseBeat = $state(-1);
  let introMix = $state<IntroMixSettings>({ ...DEFAULT_INTRO_MIX });
  let nextStepAt = 0;
  let rhythmClockStartedAt = 0;
  let environmentLayerPresence = 0;
  let macroLayerPresence = 0;
  let loopTimer: number | undefined;
  let audioContext: AudioContext | undefined;
  let audioRoute: RangeSoundRoute | undefined;
  let triangleBuffer: AudioBuffer | undefined;
  let blockBuffer: AudioBuffer | undefined;
  let masterGain: GainNode | undefined;
  let masterDryGain: GainNode | undefined;
  let masterLimiter: DynamicsCompressorNode | undefined;
  let masterReverbCenter: GainNode | undefined;
  let masterReverb: ConvolverNode | undefined;
  let masterReverbWet: GainNode | undefined;
  let enumReverbSend: GainNode | undefined;
  let scoreGain: GainNode | undefined;
  let scoreEnvironmentFilter: BiquadFilterNode | undefined;
  const voiceBuses = new Map<IntroMixChannel, GainNode>();
  const transportLayerLevels = new Map<IntroMixChannel, number>();
  let transportRestoreGeneration = 0;
  let dwellTarget: Element | undefined;
  let dwellTimer: number | undefined;
  let dwellPatternIndex = 0;
  let rhythmElement: HTMLDivElement;
  let shaderCanvas: HTMLCanvasElement;
  let identityTrack: HTMLDivElement;
  let identityFigure: HTMLElement;
  let rhythmAudioControl: HTMLDivElement;
  let triangleStage: HTMLDivElement;
  let triangleFigure: HTMLElement;
  let enumFigure: HTMLElement;
  let squareStage: HTMLDivElement;
  let squareFigure: HTMLElement;
  let startShaderAnimation = () => {};
  let stopShaderAnimation = () => {};
  const activeOscillators = new Set<OscillatorNode>();
  const figureAudioStates = new WeakMap<HTMLElement, FigureAudioState>();

  const dwellSelectors = [
    ".identityExpression",
    ".triangleLabel",
    ".enumCase",
    ".squareLabel",
  ];

  function playDwellPattern() {
    if (!audioEnabled || !playing) return;
    const roots = [261.63, 293.66, 329.63, 392, 440, 493.88];
    const root = roots[dwellPatternIndex % roots.length];
    const complement = roots[(dwellPatternIndex + 2) % roots.length];
    dwellPatternIndex += 1;
    playTone(
      "identity",
      root,
      "sine",
      0.032,
      0.34,
      identityValuePan.identity,
    );
    window.setTimeout(() => {
      if (audioEnabled && playing) {
        playTone(
          "identity",
          complement,
          "triangle",
          0.026,
          0.3,
          identityValuePan.value,
        );
      }
    }, 145);
  }

  function trackNodeDwell(event: PointerEvent) {
    if (!audioEnabled || !playing) return;
    const pointX = event.clientX;
    const pointY = event.clientY;
    let closest: Element | undefined;
    let closestDistance = 86;
    for (const selector of dwellSelectors) {
      for (const candidate of document.querySelectorAll(selector)) {
        const rect = candidate.getBoundingClientRect();
        const distance = Math.hypot(
          pointX - (rect.left + rect.width / 2),
          pointY - (rect.top + rect.height / 2),
        );
        if (distance < closestDistance) {
          closest = candidate;
          closestDistance = distance;
        }
      }
    }
    if (closest === dwellTarget) return;
    window.clearTimeout(dwellTimer);
    dwellTarget = closest;
    if (!closest) return;
    dwellTimer = window.setTimeout(playDwellPattern, 720);
  }

  const vertexSource = `
    attribute vec2 a_position;

    void main() {
      gl_Position = vec4(a_position, 0.0, 1.0);
    }
  `;

  const fragmentSource = `
    precision highp float;

    uniform vec2 u_resolution;
    uniform vec2 u_origin;
    uniform float u_time;
    uniform float u_shape;
    uniform vec3 u_accent;

    vec2 segmentInfo(vec2 point, vec2 start, vec2 end, float offset) {
      vec2 edge = end - start;
      float edgeLength = length(edge);
      float projection = clamp(
        dot(point - start, edge) / max(dot(edge, edge), 0.0001),
        0.0,
        1.0
      );
      return vec2(
        length(point - (start + edge * projection)),
        offset + edgeLength * projection
      );
    }

    void chooseClosest(inout vec2 closest, vec2 candidate) {
      if (candidate.x < closest.x) closest = candidate;
    }

    float cyclicDistance(float first, float second, float period) {
      float direct = abs(first - second);
      return min(direct, period - direct);
    }

    vec3 srgbToLinear(vec3 color) {
      vec3 low = color / 12.92;
      vec3 high = pow((color + 0.055) / 1.055, vec3(2.4));
      return mix(low, high, step(vec3(0.04045), color));
    }

    vec3 linearToSrgb(vec3 color) {
      color = max(color, vec3(0.0));
      vec3 low = color * 12.92;
      vec3 high = 1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055;
      return mix(low, high, step(vec3(0.0031308), color));
    }

    vec3 linearRgbToOklab(vec3 color) {
      float l = dot(color, vec3(0.4122214708, 0.5363325363, 0.0514459929));
      float m = dot(color, vec3(0.2119034982, 0.6806995451, 0.1073969566));
      float s = dot(color, vec3(0.0883024619, 0.2817188376, 0.6299787005));
      vec3 root = pow(max(vec3(l, m, s), vec3(0.0)), vec3(1.0 / 3.0));
      return vec3(
        dot(root, vec3(0.2104542553, 0.7936177850, -0.0040720468)),
        dot(root, vec3(1.9779984951, -2.4285922050, 0.4505937099)),
        dot(root, vec3(0.0259040371, 0.7827717662, -0.8086757660))
      );
    }

    vec3 oklabToLinearRgb(vec3 color) {
      float l = color.x + 0.3963377774 * color.y + 0.2158037573 * color.z;
      float m = color.x - 0.1055613458 * color.y - 0.0638541728 * color.z;
      float s = color.x - 0.0894841775 * color.y - 1.2914855480 * color.z;
      vec3 cube = vec3(l * l * l, m * m * m, s * s * s);
      return vec3(
        dot(cube, vec3(4.0767416621, -3.3077115913, 0.2309699292)),
        dot(cube, vec3(-1.2684380046, 2.6097574011, -0.3413193965)),
        dot(cube, vec3(-0.0041960863, -0.7034186147, 1.7076147010))
      );
    }

    vec3 whiteToAccentOklch(vec3 accent, float amount) {
      vec3 accentLab = linearRgbToOklab(srgbToLinear(accent));
      float hue = atan(accentLab.z, accentLab.y);
      float chroma = length(accentLab.yz);
      vec3 mixedLch = vec3(
        mix(1.0, accentLab.x, amount),
        chroma * amount,
        hue
      );
      vec3 mixedLab = vec3(
        mixedLch.x,
        mixedLch.y * cos(mixedLch.z),
        mixedLch.y * sin(mixedLch.z)
      );
      return linearToSrgb(oklabToLinearRgb(mixedLab));
    }

    void main() {
      vec2 localFragment = gl_FragCoord.xy - u_origin;
      vec2 point = vec2(localFragment.x, u_resolution.y - localFragment.y);
      vec2 closest = vec2(100000.0, 0.0);
      float perimeter = 1.0;
      float head = 0.0;
      float lineValueX = 0.0;
      float nearestVertexDistance = 0.0;
      float edgeSpan = 1.0;

      if (u_shape < 0.5) {
        vec2 start = vec2(8.0, u_resolution.y * 0.5);
        vec2 end = vec2(u_resolution.x - 8.0, u_resolution.y * 0.5);
        perimeter = length(end - start);
        closest = segmentInfo(point, start, end, 0.0);

        float cycle = mod(u_time, 1.8) / 0.9;
        float progress = cycle < 1.0 ? cycle : 2.0 - cycle;
        head = progress * perimeter;
        lineValueX = mix(start.x, end.x, progress);
        nearestVertexDistance = min(head, perimeter - head);
        edgeSpan = perimeter;
      } else if (u_shape < 1.5) {
        float scale = min(u_resolution.x / 320.0, u_resolution.y / 255.0);
        vec2 inset = (u_resolution - vec2(320.0, 255.0) * scale) * 0.5;
        vec2 a = inset + vec2(160.0, 35.0) * scale;
        vec2 b = inset + vec2(270.0, 225.5255888) * scale;
        vec2 c = inset + vec2(50.0, 225.5255888) * scale;
        float ab = length(b - a);
        float bc = length(c - b);
        float ca = length(a - c);
        perimeter = ab + bc + ca;
        closest = segmentInfo(point, a, b, 0.0);
        chooseClosest(closest, segmentInfo(point, b, c, ab));
        chooseClosest(closest, segmentInfo(point, c, a, ab + bc));
        edgeSpan = perimeter / 3.0;
        float circuitProgress = fract(u_time / 1.8);
        float edgePosition = circuitProgress * 3.0;
        float edgeIndex = floor(edgePosition);
        float edgeProgress = fract(edgePosition);
        float easedEdgeProgress = edgeProgress * edgeProgress *
          (3.0 - 2.0 * edgeProgress);
        head = (edgeIndex + easedEdgeProgress) * edgeSpan;
        nearestVertexDistance = min(
          cyclicDistance(head, 0.0, perimeter),
          min(
            cyclicDistance(head, ab, perimeter),
            cyclicDistance(head, ab + bc, perimeter)
          )
        );
      } else {
        float scale = min(u_resolution.x / 320.0, u_resolution.y / 260.0);
        vec2 inset = (u_resolution - vec2(320.0, 260.0) * scale) * 0.5;
        vec2 a = inset + vec2(60.0, 30.0) * scale;
        vec2 b = inset + vec2(260.0, 30.0) * scale;
        vec2 c = inset + vec2(260.0, 230.0) * scale;
        vec2 d = inset + vec2(60.0, 230.0) * scale;
        float ab = length(b - a);
        float bc = length(c - b);
        float cd = length(d - c);
        float da = length(a - d);
        perimeter = ab + bc + cd + da;
        closest = segmentInfo(point, a, b, 0.0);
        chooseClosest(closest, segmentInfo(point, b, c, ab));
        chooseClosest(closest, segmentInfo(point, c, d, ab + bc));
        chooseClosest(closest, segmentInfo(point, d, a, ab + bc + cd));
        edgeSpan = perimeter / 4.0;
        float circuitProgress = fract(u_time / 1.8);
        float edgePosition = circuitProgress * 4.0;
        float edgeIndex = floor(edgePosition);
        float edgeProgress = fract(edgePosition);
        float easedEdgeProgress = edgeProgress * edgeProgress *
          (3.0 - 2.0 * edgeProgress);
        head = (edgeIndex + easedEdgeProgress) * edgeSpan;
        nearestVertexDistance = min(
          min(
            cyclicDistance(head, 0.0, perimeter),
            cyclicDistance(head, ab, perimeter)
          ),
          min(
            cyclicDistance(head, ab + bc, perimeter),
            cyclicDistance(head, ab + bc + cd, perimeter)
          )
        );
      }

      vec3 color;
      float alpha;

      float pathDistance = abs(closest.y - head);
      if (u_shape >= 0.5) {
        pathDistance = min(pathDistance, perimeter - pathDistance);
      }
      float vertexProximity = 1.0 - smoothstep(
        0.0,
        edgeSpan * 0.42,
        nearestVertexDistance
      );
      float vertexEase = vertexProximity * vertexProximity *
        (3.0 - 2.0 * vertexProximity);
      float bloomScale = mix(0.52, 1.7, vertexEase);
      float valueRadius = (u_shape < 0.5
        ? max(u_resolution.x * 0.24, 1.0)
        : max(perimeter * 0.18, 1.0)) * bloomScale;
      float valueDistance = smoothstep(
        0.0,
        valueRadius,
        u_shape < 0.5
          ? abs(point.x - lineValueX)
          : pathDistance
      );
      color = whiteToAccentOklch(u_accent, valueDistance);
      alpha = 1.0 - smoothstep(1.7, 2.7, closest.x);

      if (u_shape < 0.5) {
        float halfHeight = u_resolution.y * 0.5;
        vec2 capsuleStart = vec2(halfHeight, halfHeight);
        vec2 capsuleEnd = vec2(
          u_resolution.x - halfHeight,
          halfHeight
        );
        float capsuleDistance = segmentInfo(
          point,
          capsuleStart,
          capsuleEnd,
          0.0
        ).x;
        float capsuleAlpha = 1.0 - smoothstep(
          max(halfHeight - 1.0, 0.0),
          halfHeight,
          capsuleDistance
        );
        alpha = capsuleAlpha;
      }

      gl_FragColor = vec4(color, alpha);
    }
  `;

  function createShader(
    context: WebGLRenderingContext,
    type: number,
    source: string,
  ) {
    const shader = context.createShader(type);
    if (!shader) return;
    context.shaderSource(shader, source);
    context.compileShader(shader);
    if (!context.getShaderParameter(shader, context.COMPILE_STATUS)) {
      context.deleteShader(shader);
      return;
    }
    return shader;
  }

  function masterOutput() {
    if (!audioContext) return;

    if (
      !masterGain ||
      !masterDryGain ||
      !masterLimiter ||
      !masterReverbCenter ||
      !masterReverb ||
      !masterReverbWet ||
      !scoreGain ||
      !scoreEnvironmentFilter
    ) {
      masterGain = audioContext.createGain();
      masterDryGain = audioContext.createGain();
      masterLimiter = audioContext.createDynamicsCompressor();
      masterReverbCenter = audioContext.createGain();
      masterReverb = audioContext.createConvolver();
      masterReverbWet = audioContext.createGain();
      enumReverbSend = audioContext.createGain();
      scoreGain = audioContext.createGain();
      scoreEnvironmentFilter = audioContext.createBiquadFilter();
      masterGain.gain.setValueAtTime(
        introMix.master,
        audioContext.currentTime,
      );
      scoreGain.gain.setValueAtTime(
        audioEnabled ? scoreLevelForEnvironment() : 0.0001,
        audioContext.currentTime,
      );
      scoreEnvironmentFilter.type = "lowpass";
      scoreEnvironmentFilter.frequency.setValueAtTime(
        environmentEqCutoff(),
        audioContext.currentTime,
      );
      scoreEnvironmentFilter.Q.setValueAtTime(
        0.42 + environmentLayerPresence * 0.38,
        audioContext.currentTime,
      );
      masterDryGain.gain.setValueAtTime(0.96, audioContext.currentTime);
      masterReverbCenter.channelCount = 1;
      masterReverbCenter.channelCountMode = "explicit";
      masterReverbCenter.channelInterpretation = "speakers";
      masterReverbWet.gain.setValueAtTime(0.32, audioContext.currentTime);
      enumReverbSend.gain.setValueAtTime(0.78, audioContext.currentTime);
      masterLimiter.threshold.setValueAtTime(-16, audioContext.currentTime);
      masterLimiter.knee.setValueAtTime(12, audioContext.currentTime);
      masterLimiter.ratio.setValueAtTime(2.5, audioContext.currentTime);
      masterLimiter.attack.setValueAtTime(0.012, audioContext.currentTime);
      masterLimiter.release.setValueAtTime(0.18, audioContext.currentTime);

      const impulseLength = Math.round(audioContext.sampleRate * 2.4);
      const impulse = audioContext.createBuffer(
        2,
        impulseLength,
        audioContext.sampleRate,
      );
      let seed = 0x4f1bbcdc;
      for (let channelIndex = 0; channelIndex < impulse.numberOfChannels; channelIndex += 1) {
        const channel = impulse.getChannelData(channelIndex);
        for (let index = 0; index < channel.length; index += 1) {
          seed = (seed * 1664525 + 1013904223) >>> 0;
          const noise = seed / 2147483648 - 1;
          const progress = index / Math.max(1, channel.length - 1);
          channel[index] = noise * Math.pow(1 - progress, 2.3) * 0.25;
        }
      }
      masterReverb.buffer = impulse;

      scoreGain.connect(scoreEnvironmentFilter).connect(masterGain);
      masterGain.connect(masterDryGain).connect(masterLimiter);
      masterGain
        .connect(masterReverbCenter)
        .connect(masterReverb)
        .connect(masterReverbWet)
        .connect(masterLimiter);
      enumReverbSend.connect(masterReverbCenter);
      if (audioRoute) masterLimiter.connect(audioRoute.input);
    }

    return masterGain;
  }

  function mixLevel(channel: IntroMixChannel) {
    return introMix[channel];
  }

  function pitchRatioFor(channel: IntroMixChannel) {
    void channel;
    return Math.pow(2, introMix.transpose / 12);
  }

  function identityLayerLevel() {
    const macroSidechain = Math.max(0.28, 1 - macroLayerPresence * 0.72);
    const environmentDissolve = Math.max(
      0.025,
      Math.pow(1 - environmentLayerPresence, 2.4),
    );
    return macroSidechain * environmentDissolve;
  }

  function propertiesLayerLevel() {
    return Math.max(
      0.015,
      Math.pow(1 - environmentLayerPresence, 3.2),
    );
  }

  function channelLayerLevel(channel: IntroMixChannel) {
    if (channel === "identity") return identityLayerLevel();
    if (channel === "properties") return propertiesLayerLevel();
    return 1;
  }

  function updateIdentityLayer(timeConstant: number) {
    if (!audioEnabled || !audioContext) return;
    const identityBus = voiceBuses.get("identity");
    if (!identityBus) return;
    identityBus.gain.cancelScheduledValues(audioContext.currentTime);
    identityBus.gain.setTargetAtTime(
      mixLevel("identity")
        * identityLayerLevel()
        * (transportLayerLevels.get("identity") ?? 1),
      audioContext.currentTime,
      timeConstant,
    );
  }

  function updatePropertiesLayer(timeConstant: number) {
    if (!audioEnabled || !audioContext) return;
    const propertiesBus = voiceBuses.get("properties");
    if (!propertiesBus) return;
    propertiesBus.gain.cancelScheduledValues(audioContext.currentTime);
    propertiesBus.gain.setTargetAtTime(
      mixLevel("properties")
        * propertiesLayerLevel()
        * (transportLayerLevels.get("properties") ?? 1),
      audioContext.currentTime,
      timeConstant,
    );
  }

  function voiceOutput(channel: IntroMixChannel) {
    const master = masterOutput();
    if (!master || !audioContext) return;
    const destination = channel === "keyboard" ? master : scoreGain;
    if (!destination) return;

    let bus = voiceBuses.get(channel);
    if (!bus) {
      bus = audioContext.createGain();
      bus.gain.setValueAtTime(
        mixLevel(channel)
          * channelLayerLevel(channel)
          * (transportLayerLevels.get(channel) ?? 1),
        audioContext.currentTime,
      );
      bus.connect(destination);
      if (channel === "enums" && enumReverbSend) {
        bus.connect(enumReverbSend);
      }
      voiceBuses.set(channel, bus);
    }
    return bus;
  }

  function syncMixGains() {
    if (!audioContext) return;
    const now = audioContext.currentTime;
    masterGain?.gain.setTargetAtTime(introMix.master, now, 0.025);
    for (const [channel, bus] of voiceBuses) {
      bus.gain.setTargetAtTime(
        mixLevel(channel)
          * channelLayerLevel(channel)
          * (transportLayerLevels.get(channel) ?? 1),
        now,
        0.025,
      );
    }
  }

  function setScoreGain(level: number, timeConstant = 0.012) {
    if (!audioContext || !scoreGain) return;
    scoreGain.gain.setTargetAtTime(
      level,
      audioContext.currentTime,
      timeConstant,
    );
  }

  function scoreLevelForEnvironment() {
    return Math.max(0.62, 1 - environmentLayerPresence * 0.38);
  }

  function environmentEqCutoff() {
    const openCutoff = 16_000;
    const closedCutoff = 620;
    return openCutoff * Math.pow(
      closedCutoff / openCutoff,
      environmentLayerPresence,
    );
  }

  function setEnvironmentScoreTreatment(timeConstant = 0.58) {
    if (!audioContext) return;
    setScoreGain(scoreLevelForEnvironment(), timeConstant);
    scoreEnvironmentFilter?.frequency.setTargetAtTime(
      environmentEqCutoff(),
      audioContext.currentTime,
      timeConstant,
    );
    scoreEnvironmentFilter?.Q.setTargetAtTime(
      0.42 + environmentLayerPresence * 0.38,
      audioContext.currentTime,
      timeConstant,
    );
  }

  function playTone(
    channel: IntroMixChannel,
    frequency: number,
    type: OscillatorType,
    volume: number,
    duration = 0.22,
    pan = 0,
    panEnd = pan,
    panDuration = duration,
  ) {
    if (!audioEnabled || !audioContext || volume <= 0.0005) return;
    const destination = voiceOutput(channel);
    if (!destination) return;

    const now = audioContext.currentTime;
    const oscillator = audioContext.createOscillator();
    const filter = audioContext.createBiquadFilter();
    const gain = audioContext.createGain();
    const stereo = audioContext.createStereoPanner();
    const peakVolume = Math.max(0.0001, volume);
    const velocity = Math.max(0, Math.min(1, volume / 0.16));
    const noteDuration = Math.max(0.05, duration * (0.7 + Math.sqrt(velocity) * 0.3));
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, now);
    filter.type = "lowpass";
    filter.frequency.setValueAtTime(Math.max(420, frequency * 3.25), now);
    filter.Q.setValueAtTime(0.55, now);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(peakVolume, now + 0.024);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + noteDuration - 0.01);
    const startPan = Math.max(-1, Math.min(1, pan));
    const endPan = Math.max(-1, Math.min(1, panEnd));
    stereo.pan.setValueAtTime(startPan, now);
    if (endPan !== startPan) {
      stereo.pan.linearRampToValueAtTime(
        endPan,
        now + Math.min(noteDuration, Math.max(0.05, panDuration)),
      );
    }
    oscillator.connect(filter);
    filter.connect(gain);
    gain.connect(stereo).connect(destination);
    activeOscillators.add(oscillator);
    oscillator.onended = () => activeOscillators.delete(oscillator);
    oscillator.start(now);
    oscillator.stop(now + noteDuration);
  }

  function smoothRange(start: number, end: number, value: number) {
    if (end <= start) return value >= end ? 1 : 0;
    const progress = Math.max(0, Math.min(1, (value - start) / (end - start)));
    return progress * progress * (3 - 2 * progress);
  }

  function centeredRhythmVolume(target: HTMLElement) {
    trackFigureAudioStates();
    const position = figureScrollPosition(target);
    const { distancePastCenter, height, entryStartDistance, centerRadius } = position;
    const peakLevel = 0.92;
    const backgroundLevel = 0.48;
    const phase = figureAudioStates.get(target)?.phase ?? "before";

    if (phase === "before") return 0;
    if (phase === "entering") {
      return smoothRange(entryStartDistance, -centerRadius, distancePastCenter)
        * peakLevel;
    }
    if (phase === "centered") return peakLevel;

    const normalizationDistance = Math.max(
      window.innerHeight * 0.42,
      height * 0.75,
    );
    const centeredProximity = 1 - smoothRange(
      centerRadius,
      normalizationDistance,
      Math.abs(distancePastCenter),
    );
    return backgroundLevel + (peakLevel - backgroundLevel) * centeredProximity;
  }

  function figureScrollPosition(target: HTMLElement): FigureScrollPosition {
    const glyph = target.querySelector<HTMLElement>(
      ".identityExpression, .shapeStage, .enumStage",
    ) ?? target;
    const rect = layoutTracker?.locate(glyph).rect
      ?? glyph.getBoundingClientRect();
    const distancePastCenter = window.innerHeight * 0.5 - (rect.top + rect.height * 0.5);
    const height = rect.height;
    const entryStartDistance = -(window.innerHeight + height) * 0.5;
    const centerRadius = Math.max(18, height * 0.14);
    const exitEndDistance = Math.max(window.innerHeight * 0.25, height * 0.65);
    return {
      distancePastCenter,
      height,
      entryStartDistance,
      centerRadius,
      progress: smoothRange(entryStartDistance, centerRadius, distancePastCenter),
      audioExitGain: 1 - smoothRange(
        centerRadius,
        exitEndDistance,
        distancePastCenter,
      ),
    };
  }

  function phaseForFigurePosition(position: FigureScrollPosition): FigureAudioPhase {
    if (position.distancePastCenter < position.entryStartDistance) return "before";
    if (position.distancePastCenter < -position.centerRadius) return "entering";
    if (position.distancePastCenter <= position.centerRadius) return "centered";
    return "passed";
  }

  function exposeFigureScrollPosition(
    target: HTMLElement,
    state: FigureAudioState,
    position: FigureScrollPosition,
  ) {
    target.dataset.scrollPhase = state.phase;
    target.style.setProperty("--scroll-progress", position.progress.toFixed(4));
    target.style.setProperty(
      "--scroll-distance",
      `${position.distancePastCenter.toFixed(1)}px`,
    );
  }

  function trackFigureAudioStates() {
    for (const target of [
      identityFigure,
      triangleFigure,
      enumFigure,
      squareFigure,
    ]) {
      if (!target) continue;
      const position = figureScrollPosition(target);
      const { distancePastCenter, entryStartDistance, centerRadius } = position;
      const state = figureAudioStates.get(target);

      if (!state) {
        const initialState = {
          phase: phaseForFigurePosition(position),
          lastDistance: distancePastCenter,
        } satisfies FigureAudioState;
        figureAudioStates.set(target, initialState);
        exposeFigureScrollPosition(target, initialState, position);
        continue;
      }

      const movingDown = distancePastCenter > state.lastDistance + 0.5;
      const movingUp = distancePastCenter < state.lastDistance - 0.5;

      if (state.phase === "before" && movingDown && distancePastCenter >= entryStartDistance) {
        state.phase = phaseForFigurePosition(position);
      } else if (state.phase === "entering") {
        if (movingDown && distancePastCenter >= -centerRadius) {
          state.phase = phaseForFigurePosition(position);
        } else if (movingUp && distancePastCenter < entryStartDistance) {
          state.phase = "before";
        }
      } else if (state.phase === "centered") {
        if (movingDown && distancePastCenter > centerRadius) {
          state.phase = "passed";
        } else if (movingUp && distancePastCenter < -centerRadius) {
          state.phase = "entering";
        }
      } else if (state.phase === "passed" && movingUp) {
        state.phase = phaseForFigurePosition(position);
      }

      state.lastDistance = distancePastCenter;
      exposeFigureScrollPosition(target, state, position);
    }
    stopShaderAnimation();
    updatePropertiesLayer(0.025);
  }

  function playTrianglePercussion(
    volumeScale: number,
    channel: IntroMixChannel = "forms",
    pan = 0,
  ) {
    if (!audioEnabled || !audioContext || volumeScale <= 0.01) return;
    const destination = voiceOutput(channel);
    if (!destination) return;

    const now = audioContext.currentTime;
    const pitchRatio = pitchRatioFor(channel);
    triangleBuffer ??= (() => {
      const duration = 0.22;
      const length = Math.max(
        1,
        Math.round(audioContext.sampleRate * duration),
      );
      const buffer = audioContext.createBuffer(
        1,
        length,
        audioContext.sampleRate,
      );
      const samples = buffer.getChannelData(0);
      let seed = 0x6d2b79f5;
      let previousNoise = 0;

      for (let index = 0; index < length; index += 1) {
        const time = index / audioContext.sampleRate;
        const attack = Math.min(1, time / 0.0015);
        seed = (seed * 1664525 + 1013904223) >>> 0;
        const noise = seed / 2147483648 - 1;
        const brightNoise = noise - previousNoise * 0.82;
        const envelope = Math.exp(-time * 24);
        samples[index] = brightNoise * envelope * attack * 0.22;
        previousNoise = noise;
      }
      return buffer;
    })();

    const strike = audioContext.createBufferSource();
    const highpass = audioContext.createBiquadFilter();
    const lowpass = audioContext.createBiquadFilter();
    const gain = audioContext.createGain();
    const stereo = audioContext.createStereoPanner();
    strike.buffer = triangleBuffer;
    highpass.type = "highpass";
    highpass.frequency.setValueAtTime(1800 * pitchRatio, now);
    highpass.Q.setValueAtTime(0.18, now);
    lowpass.type = "lowpass";
    lowpass.frequency.setValueAtTime(6200 * pitchRatio, now);
    lowpass.frequency.setTargetAtTime(3400 * pitchRatio, now + 0.008, 0.045);
    lowpass.Q.setValueAtTime(0.18, now);
    gain.gain.setValueAtTime(0.2 * volumeScale, now);
    stereo.pan.setValueAtTime(Math.max(-1, Math.min(1, pan)), now);
    strike
      .connect(highpass)
      .connect(lowpass)
      .connect(gain)
      .connect(stereo)
      .connect(destination);
    strike.start(now);
  }

  function pulseTriangle(beat: number) {
    triangleBeat = beat;
    const pan = Math.sin(trianglePanPhase) * trianglePanDepth;
    trianglePanPhase = (trianglePanPhase + trianglePanStep) % (Math.PI * 2);
    playTrianglePercussion(
      centeredRhythmVolume(triangleFigure),
      "forms",
      pan,
    );
  }

  function nextEnumCase() {
    if (enumCases.length < 2) return 0;
    if (enumCaseBeat < 0) return Math.floor(Math.random() * enumCases.length);
    const previous = enumCaseBeat;
    const offset = 1 + Math.floor(Math.random() * (enumCases.length - 1));
    return (previous + offset) % enumCases.length;
  }

  function pulseEnumSplit() {
    enumPulse = enumPulse === 0 ? 1 : 0;
    enumCaseBeat = nextEnumCase();
    const volume = centeredRhythmVolume(enumFigure);
    const pan = Math.random() * 1.7 - 0.85;
    playTrianglePercussion(volume * 0.56, "enums", pan);
    playEnumTailBend(volume, pan);
  }

  function playEnumTailBend(volumeScale: number, pan: number) {
    if (!audioEnabled || !audioContext || volumeScale <= 0.01) return;
    const destination = voiceOutput("enums");
    if (!destination) return;

    const startAt = audioContext.currentTime + 0.024;
    const pitchRatio = pitchRatioFor("enums");
    const oscillator = audioContext.createOscillator();
    const filter = audioContext.createBiquadFilter();
    const gain = audioContext.createGain();
    const stereo = audioContext.createStereoPanner();
    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(278 * pitchRatio, startAt);
    oscillator.frequency.exponentialRampToValueAtTime(
      278 * Math.pow(2, -1 / 12) * pitchRatio,
      startAt + 0.34,
    );
    filter.type = "lowpass";
    filter.frequency.setValueAtTime(1_050 * pitchRatio, startAt);
    filter.Q.setValueAtTime(0.55, startAt);
    gain.gain.setValueAtTime(0.0001, startAt);
    gain.gain.linearRampToValueAtTime(0.026 * volumeScale, startAt + 0.045);
    gain.gain.exponentialRampToValueAtTime(0.0001, startAt + 0.38);
    stereo.pan.setValueAtTime(Math.max(-1, Math.min(1, pan)), startAt);
    oscillator.connect(filter).connect(gain).connect(stereo).connect(destination);
    activeOscillators.add(oscillator);
    oscillator.onended = () => activeOscillators.delete(oscillator);
    oscillator.start(startAt);
    oscillator.stop(startAt + 0.4);
  }

  function clearEnumVisuals() {
    enumPulse = -1;
    enumCaseBeat = -1;
  }

  function playSquarePercussion(
    beat: number,
    volumeScale: number,
    pan: number,
  ) {
    if (!audioEnabled || !audioContext || volumeScale <= 0.01) return;
    const destination = voiceOutput("properties");
    if (!destination) return;

    const now = audioContext.currentTime;
    blockBuffer ??= (() => {
      const length = Math.max(
        1,
        Math.round(audioContext.sampleRate * 0.032),
      );
      const buffer = audioContext.createBuffer(
        1,
        length,
        audioContext.sampleRate,
      );
      const samples = buffer.getChannelData(0);
      let seed = 0x2c9277b5;
      for (let index = 0; index < length; index += 1) {
        seed = (seed * 1664525 + 1013904223) >>> 0;
        const noise = seed / 2147483648 - 1;
        const progress = index / Math.max(1, length - 1);
        samples[index] = noise * Math.pow(1 - progress, 4.8);
      }
      return buffer;
    })();

    const strike = audioContext.createBufferSource();
    const bodyFilter = audioContext.createBiquadFilter();
    const knockFilter = audioContext.createBiquadFilter();
    const bodyGain = audioContext.createGain();
    const knockGain = audioContext.createGain();
    const stereo = audioContext.createStereoPanner();
    const baseFrequency = (340 + (beat % 2) * 22) * pitchRatioFor("properties");

    strike.buffer = blockBuffer;
    bodyFilter.type = "bandpass";
    bodyFilter.frequency.setValueAtTime(baseFrequency, now);
    bodyFilter.Q.setValueAtTime(4.2, now);
    knockFilter.type = "bandpass";
    knockFilter.frequency.setValueAtTime(baseFrequency * 2.35, now);
    knockFilter.Q.setValueAtTime(5.8, now);

    bodyGain.gain.setValueAtTime(0.0001, now);
    bodyGain.gain.linearRampToValueAtTime(0.46 * volumeScale, now + 0.0015);
    bodyGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.062);
    knockGain.gain.setValueAtTime(0.0001, now);
    knockGain.gain.linearRampToValueAtTime(0.24 * volumeScale, now + 0.001);
    knockGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.038);
    stereo.pan.setValueAtTime(Math.max(-1, Math.min(1, pan)), now);

    bodyGain.connect(stereo);
    knockGain.connect(stereo);
    stereo.connect(destination);
    strike.connect(bodyFilter).connect(bodyGain);
    strike.connect(knockFilter).connect(knockGain);
    strike.start(now);
    strike.stop(now + 0.065);
  }

  function pulseSquare(beat: number) {
    squareBeat = beat;
    if (propertiesLayerLevel() <= 0.001) return;
    const pan = squareBeatPan[beat % squareBeatPan.length] ?? 0;
    playSquarePercussion(beat, centeredRhythmVolume(squareFigure), pan);
  }

  function pulseLine(side: "identity" | "value") {
    const panStart = identityValuePan[side];
    playTone(
      "identity",
      (side === "identity" ? 82.4069 : 55) * pitchRatioFor("identity"),
      "sine",
      0.16 * centeredRhythmVolume(identityFigure),
      2.1,
      panStart,
      side === "identity" ? identityValuePan.value : panStart,
      subdivisionMilliseconds * 6 / 1_000,
    );
  }

  function playStep() {
    if (!playing) return;

    const now = performance.now();
    if (nextStepAt < now - subdivisionMilliseconds) {
      nextStepAt = now;
    }

    step = (step + 1) % 12;
    rhythmTick += 1;
    soundManager?.publishRhythmBeat?.({
      step,
      tick: rhythmTick,
      audioTime: audioContext?.currentTime,
    });

    // Three accents divide the shared 12-step cycle into groups of four.
    if (step % 4 === 0) pulseTriangle(step / 4);

    // Four accents divide the same cycle into groups of three.
    if (step % 3 === 0) pulseSquare(step / 3);

    // Identity and value alternate across the same shared cycle.
    if (step % 6 === 0) {
      pulseLine(step === 0 ? "identity" : "value");
      if (autoScrolling && rhythmTick >= nextAutoScrollTick) {
        advanceAutoScroll();
        nextAutoScrollTick = rhythmTick + 24;
      }
    }

    // Enum makes one split at the midpoint of each two-loop phrase.
    if (rhythmTick % 24 === 13) {
      pulseEnumSplit();
    }

    nextStepAt += subdivisionMilliseconds;
    loopTimer = window.setTimeout(
      playStep,
      Math.max(0, nextStepAt - now),
    );
  }

  function startRhythm() {
    playing = true;
    step = -1;
    rhythmTick = 0;
    trianglePanPhase = -Math.PI / 2;
    rhythmClockStartedAt = performance.now();
    nextStepAt = rhythmClockStartedAt;
    startShaderAnimation();
    playStep();
  }

  function stopRhythm() {
    playing = false;
    if (typeof window !== "undefined") {
      window.clearTimeout(loopTimer);
    }
    loopTimer = undefined;
    step = -1;
    triangleBeat = -1;
    squareBeat = -1;
    enumPulse = -1;
    enumCaseBeat = -1;
    clearEnumVisuals();
    stopShaderAnimation();
  }

  const figureChannels = () => [
    [identityFigure, "identity"],
    [triangleFigure, "forms"],
    [enumFigure, "enums"],
    [squareFigure, "properties"],
  ] as const;

  function setTransportLayerLevel(
    channel: IntroMixChannel,
    level: number,
    timeConstant = 0.2,
  ) {
    transportLayerLevels.set(channel, level);
    const bus = voiceBuses.get(channel);
    if (!bus || !audioContext) return;
    bus.gain.cancelScheduledValues(audioContext.currentTime);
    bus.gain.setTargetAtTime(
      mixLevel(channel) * channelLayerLevel(channel) * level,
      audioContext.currentTime,
      timeConstant,
    );
  }

  function stopTransport() {
    transportRestoreGeneration += 1;
    transportState = "stopped";
    audioEnabled = false;
    window.clearTimeout(dwellTimer);
    dwellTimer = undefined;
    dwellTarget = undefined;
    soundManager?.setEnabled(false);
    setScoreGain(0.0001, 0.08);
    stopRhythm();
  }

  async function startTransport() {
    if (transportState !== "stopped") return;
    transportState = "starting";
    const generation = ++transportRestoreGeneration;
    if (!(await ensureAudioRoute()) || !audioContext || !soundManager) {
      if (generation === transportRestoreGeneration) transportState = "stopped";
      return;
    }
    if (generation !== transportRestoreGeneration || transportState === "stopped") return;

    trackFigureAudioStates();
    const encountered = figureChannels().filter(([figure]) =>
      figure && figureAudioStates.get(figure)?.phase !== "before"
    );
    for (const [, channel] of figureChannels()) {
      setTransportLayerLevel(channel, encountered.some(([, active]) => active === channel) ? 0 : 1);
    }

    audioEnabled = true;
    soundManager.setEnabled(true);
    setEnvironmentScoreTreatment(0.12);
    startRhythm();

    for (const [, channel] of encountered) {
      await new Promise<void>((resolve) => window.setTimeout(resolve, 190));
      if (generation !== transportRestoreGeneration || !audioEnabled) return;
      setTransportLayerLevel(channel, 1, 0.24);
    }
    if (generation !== transportRestoreGeneration || !audioEnabled) return;
    transportState = "running";
  }

  async function ensureAudioRoute() {
    const context = await soundManager?.resume();
    if (!context || !soundManager) return false;
    audioContext = context;
    audioRoute ??= soundManager.register("range-rhythm", 1.2);
    if (!audioRoute) return false;
    masterOutput();
    return true;
  }

  function toggleTransport() {
    if (transportState === "stopped") void startTransport();
    else stopTransport();
  }

  function stopAutoScroll() {
    autoScrolling = false;
    nextAutoScrollTick = 0;
    autoScrollAnchor = undefined;
    autoScrollAnchorPasses = 0;
    if (autoScrollFrame !== undefined) {
      window.cancelAnimationFrame(autoScrollFrame);
      autoScrollFrame = undefined;
    }
  }

  function autoScrollTargets() {
    if (!rhythmElement) return [];
    const rhythmSelectors = [
      ".lineFigure",
      ".triangleFigure",
      ".enumFigure",
      ".squareFigure",
    ].join(",");
    const targets: Element[] = [
      ...rhythmElement.querySelectorAll<HTMLElement>(rhythmSelectors),
    ];
    const macroCloud = document.querySelector<HTMLElement>(
      '[data-range-layout="macro-cloud"]',
    );
    if (macroCloud) targets.push(macroCloud);
    const environment = macroCloud?.querySelector<SVGGraphicsElement>(
      '[aria-label="Environment"]',
    );
    if (environment) targets.push(environment);
    const maximumScroll = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
    return targets
      .map((element) => {
        const bounds = element.getBoundingClientRect();
        const macroGraphic = element === macroCloud
          ? macroCloud.querySelector<SVGGraphicsElement>(".macroCloudGraphic")
          : undefined;
        const macroBounds = macroGraphic?.getBoundingClientRect();
        const target = macroBounds
          ? window.scrollY + macroBounds.top + macroBounds.height * (237 / 1_180) - window.innerHeight * 0.5
          : window.scrollY + bounds.top + bounds.height * 0.5 - window.innerHeight * 0.5;
        return {
          element,
          position: Math.min(maximumScroll, Math.max(0, target)),
        };
      })
      .filter(({ position }, index, targets) => (
        index === 0 || Math.abs(position - targets[index - 1].position) > 24
      ));
  }

  function autoScrollPassesFor(element: Element) {
    const macroCloud = document.querySelector('[data-range-layout="macro-cloud"]');
    if (
      element === triangleFigure
      || element === enumFigure
      || element === squareFigure
      || element === macroCloud
    ) return 2;
    return 1;
  }

  function animateAutoScroll(target: number) {
    if (autoScrollFrame !== undefined) window.cancelAnimationFrame(autoScrollFrame);
    const start = window.scrollY;
    const distance = target - start;
    const startedAt = performance.now();
    // Travel continuously for two complete Identity -> Value phrases.
    const duration = subdivisionMilliseconds * 24;

    const render = (timestamp: number) => {
      if (!autoScrolling) return;
      const progress = Math.min(1, (timestamp - startedAt) / duration);
      // Keep a small non-zero velocity at each centered figure, then accelerate
      // through the open distance before easing into the next sound anchor.
      const eased = progress - 0.82 * Math.sin(progress * Math.PI * 2) / (Math.PI * 2);
      window.scrollTo(0, start + distance * eased);
      if (progress < 1) {
        autoScrollFrame = window.requestAnimationFrame(render);
      } else {
        autoScrollFrame = undefined;
        window.scrollTo(0, target);
      }
    };
    autoScrollFrame = window.requestAnimationFrame(render);
  }

  function advanceAutoScroll() {
    const maximumScroll = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
    if (window.scrollY >= maximumScroll - 1) {
      stopAutoScroll();
      return;
    }
    const targets = autoScrollTargets();
    const centeredTarget = targets.find(({ element }) => element === autoScrollAnchor);
    const centeredPasses = autoScrollAnchor
      ? autoScrollPassesFor(autoScrollAnchor)
      : 1;
    if (centeredTarget && autoScrollAnchorPasses < centeredPasses) {
      autoScrollAnchorPasses += 1;
      const centeredDrift = autoScrollAnchorPasses % 2 === 0 ? 10 : -10;
      animateAutoScroll(centeredTarget.position + centeredDrift);
      return;
    }

    const nextTarget = targets.find(({ position }) => position > window.scrollY + 40);
    if (nextTarget === undefined) {
      stopAutoScroll();
      return;
    }
    autoScrollAnchor = nextTarget.element;
    autoScrollAnchorPasses = 1;
    animateAutoScroll(nextTarget.position);
  }

  function toggleAutoScroll() {
    if (autoScrolling) {
      stopAutoScroll();
      return;
    }
    autoScrolling = true;
    nextAutoScrollTick = rhythmTick + 24;
    advanceAutoScroll();
  }

  onMount(() => {
    trackFigureAudioStates();
    window.addEventListener("pointermove", trackNodeDwell, { passive: true });
    const stopTrackingLayout = layoutTracker?.observe(
      '[data-range-layout="range-rhythm"]',
      trackFigureAudioStates,
    );
    return () => {
      window.removeEventListener("pointermove", trackNodeDwell);
      window.clearTimeout(dwellTimer);
      stopTrackingLayout?.();
    };
  });

  onMount(() => soundManager?.subscribeLayerPresence?.(
    "environment",
    (presence) => {
      environmentLayerPresence = presence;
      if (audioEnabled) {
        setEnvironmentScoreTreatment(0.9);
        updateIdentityLayer(1.15);
        updatePropertiesLayer(0.9);
      }
    },
  ));

  onMount(() => soundManager?.subscribeLayerPresence?.(
    "macros",
    (presence) => {
      const wasPresent = macroLayerPresence;
      macroLayerPresence = presence;
      updateIdentityLayer(presence > wasPresent ? 0.018 : 0.24);
    },
  ));

  onMount(() => {
    if (
      !shaderCanvas ||
      !rhythmElement ||
      !identityTrack ||
      !triangleStage
    ) {
      return;
    }

    const context = shaderCanvas.getContext("webgl", {
      alpha: true,
      antialias: false,
      premultipliedAlpha: true,
      powerPreference: "high-performance",
    });
    if (!context) return;

    const vertexShader = createShader(context, context.VERTEX_SHADER, vertexSource);
    const fragmentShader = createShader(
      context,
      context.FRAGMENT_SHADER,
      fragmentSource,
    );
    if (!vertexShader || !fragmentShader) return;

    const program = context.createProgram();
    if (!program) return;
    context.attachShader(program, vertexShader);
    context.attachShader(program, fragmentShader);
    context.linkProgram(program);
    if (!context.getProgramParameter(program, context.LINK_STATUS)) return;

    const positionBuffer = context.createBuffer();
    context.bindBuffer(context.ARRAY_BUFFER, positionBuffer);
    context.bufferData(
      context.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
      context.STATIC_DRAW,
    );

    const positionLocation = context.getAttribLocation(program, "a_position");
    const resolutionLocation = context.getUniformLocation(program, "u_resolution");
    const originLocation = context.getUniformLocation(program, "u_origin");
    const timeLocation = context.getUniformLocation(program, "u_time");
    const shapeLocation = context.getUniformLocation(program, "u_shape");
    const accentLocation = context.getUniformLocation(program, "u_accent");
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let frame = 0;
    let startedAt = rhythmClockStartedAt;

    const readAccent = () => {
      const colorElement = document.createElement("span");
      colorElement.style.color = "var(--range)";
      colorElement.style.display = "none";
      rhythmElement.append(colorElement);
      const resolvedColor = getComputedStyle(colorElement).color;
      colorElement.remove();

      const colorProbe = document.createElement("canvas");
      colorProbe.width = 1;
      colorProbe.height = 1;
      const colorContext = colorProbe.getContext("2d", { willReadFrequently: true });
      if (!colorContext) return [0.05, 0.55, 1] as const;
      colorContext.fillStyle = resolvedColor;
      colorContext.fillRect(0, 0, 1, 1);
      const [red, green, blue] = colorContext.getImageData(0, 0, 1, 1).data;
      return [red / 255, green / 255, blue / 255] as const;
    };
    const accent = readAccent();

    const resize = () => {
      const density = Math.min(window.devicePixelRatio || 1, 1.25);
      const width = Math.max(1, Math.round(rhythmElement.clientWidth * density));
      const height = Math.max(1, Math.round(rhythmElement.clientHeight * density));
      if (shaderCanvas.width !== width || shaderCanvas.height !== height) {
        shaderCanvas.width = width;
        shaderCanvas.height = height;
      }
      return density;
    };

    const drawTarget = (
      target: HTMLElement,
      shape: number,
      time: number,
      density: number,
    ) => {
      const rootRect = layoutTracker?.query('[data-range-layout="range-rhythm"]')?.rect
        ?? rhythmElement.getBoundingClientRect();
      const targetRect = layoutTracker?.locate(target).rect
        ?? target.getBoundingClientRect();
      const x = Math.round((targetRect.left - rootRect.left) * density);
      const y = Math.round(
        (rootRect.bottom - targetRect.bottom) * density,
      );
      const width = Math.max(1, Math.round(targetRect.width * density));
      const height = Math.max(1, Math.round(targetRect.height * density));

      context.viewport(x, y, width, height);
      context.scissor(x, y, width, height);
      context.uniform2f(resolutionLocation, width, height);
      context.uniform2f(originLocation, x, y);
      context.uniform1f(timeLocation, time);
      context.uniform1f(shapeLocation, shape);
      context.drawArrays(context.TRIANGLES, 0, 6);
    };

    const render = (now: number) => {
      if (
        !shaderCanvas ||
        !rhythmElement ||
        !identityTrack ||
        !triangleStage ||
        !squareStage
      ) {
        frame = 0;
        return;
      }

      const density = resize();
      const time = (now - startedAt) / 1000;

      context.useProgram(program);
      context.bindBuffer(context.ARRAY_BUFFER, positionBuffer);
      context.enableVertexAttribArray(positionLocation);
      context.vertexAttribPointer(positionLocation, 2, context.FLOAT, false, 0, 0);
      context.uniform3f(accentLocation, accent[0], accent[1], accent[2]);
      context.enable(context.SCISSOR_TEST);
      context.scissor(0, 0, shaderCanvas.width, shaderCanvas.height);
      context.clearColor(0, 0, 0, 0);
      context.clear(context.COLOR_BUFFER_BIT);

      drawTarget(identityTrack, 0, time, density);
      drawTarget(triangleStage, 1, time, density);
      drawTarget(squareStage, 2, time, density);
      shaderCanvas.dataset.rendered = "true";
      shaderCanvas.dataset.sharedPaths = "3";

      if (playing && !reducedMotion.matches) {
        frame = window.requestAnimationFrame(render);
      } else {
        frame = 0;
      }
    };

    const redraw = () => {
      if (frame) window.cancelAnimationFrame(frame);
      frame = window.requestAnimationFrame(render);
    };

    startShaderAnimation = () => {
      startedAt = rhythmClockStartedAt;
      redraw();
    };
    stopShaderAnimation = redraw;

    const observer = new ResizeObserver(redraw);
    observer.observe(rhythmElement);
    reducedMotion.addEventListener("change", redraw);
    redraw();

    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      startShaderAnimation = () => {};
      stopShaderAnimation = () => {};
      observer.disconnect();
      reducedMotion.removeEventListener("change", redraw);
      context.deleteBuffer(positionBuffer);
      context.deleteProgram(program);
      context.deleteShader(vertexShader);
      context.deleteShader(fragmentShader);
    };
  });

  onMount(() => {
    rhythmElement
      .closest("range-essay-page")
      ?.querySelector<HTMLElement>("[data-range-hero-overlay]")
      ?.append(rhythmAudioControl);
    stopTransport();
    startRhythm();
    const unsubscribeSound = soundManager?.subscribe((enabled) => {
      if (enabled && transportState === "stopped") void startTransport();
    });
    return () => {
      unsubscribeSound?.();
      stopRhythm();
    };
  });

  onDestroy(() => {
    stopAutoScroll();
    soundManager?.setEnabled(false);
    clearEnumVisuals();
    for (const oscillator of activeOscillators) {
      try {
        oscillator.stop();
      } catch {
        // The oscillator may already have completed.
      }
    }
    activeOscillators.clear();
    for (const bus of voiceBuses.values()) bus.disconnect();
    voiceBuses.clear();
    scoreGain?.disconnect();
    scoreEnvironmentFilter?.disconnect();
    masterGain?.disconnect();
    masterDryGain?.disconnect();
    masterReverbCenter?.disconnect();
    masterReverb?.disconnect();
    masterReverbWet?.disconnect();
    enumReverbSend?.disconnect();
    masterLimiter?.disconnect();
    audioRoute?.dispose();
    audioRoute = undefined;
  });
</script>

<div
  bind:this={rhythmElement}
  class="rhythm"
  data-range-layout="range-rhythm"
  class:playing
  data-playing={playing}
  data-step={step}
  data-triangle-beat={triangleBeat}
  data-square-beat={squareBeat}
>
  <canvas
    class="pathRhythmShader"
    aria-hidden="true"
    data-shader="path-rhythm"
    bind:this={shaderCanvas}
  ></canvas>

  <div class="identityIntro">
    {@render identityIntro()}
  </div>

  <div class="rhythmAudioControl" bind:this={rhythmAudioControl}>
    {#if dev}
      <button
        type="button"
        class="autoScrollButton"
        class:autoScrollRunning={autoScrolling}
        aria-label={autoScrolling ? "Stop automatic scrolling" : "Start automatic scrolling"}
        aria-pressed={autoScrolling}
        onclick={toggleAutoScroll}
      >
        {autoScrolling ? "Stop auto" : "Auto-scroll"}
      </button>
    {/if}
    <button
      type="button"
      class="transportButton"
      class:transportRunning={transportState !== "stopped"}
      aria-label={transportState === "stopped" ? "Start article sound and motion" : "Stop article sound and motion"}
      aria-pressed={transportState !== "stopped"}
      onclick={toggleTransport}
      title={transportState === "stopped" ? "Start" : "Stop"}
    >
      <span class="transportGlyph" aria-hidden="true"></span>
    </button>
  </div>

  <figure class="lineFigure" bind:this={identityFigure}>
    <div
      class="identityRelation"
      aria-label="Identity to Value"
    >
      <div class="identityExpression">
        <span>Identity</span><span aria-hidden="true">:</span><span>Value</span>
      </div>
    </div>
    <div
      class="identityValueTrack"
      aria-hidden="true"
      bind:this={identityTrack}
    ></div>
  </figure>

  <div class="identityDetail">
    {@render identityDetail()}
  </div>

  <div class="functionIntro">
    {@render functionIntro()}
  </div>

  <figure
    class="shapeFigure triangleFigure"
    aria-label="Construct, enum, and function"
    bind:this={triangleFigure}
  >
    <div class="figureHeader">
      <span>3 concrete substrate forms</span>
    </div>

    <div class="shapeStage" bind:this={triangleStage}>
      <svg viewBox="0 0 320 255" aria-hidden="true">
        <text
          class="shapeLabel triangleLabel triangleLabel0"
          x="160"
          y="17"
          text-anchor="middle"
        >Construct</text>
        <text
          class="shapeLabel triangleLabel triangleLabel1"
          x="292"
          y="247"
          text-anchor="end"
        >Enum</text>
        <text
          class="shapeLabel triangleLabel triangleLabel2"
          x="28"
          y="247"
        >Function</text>
      </svg>
    </div>
  </figure>

  <div class="functionCode">
    {@render functionCode()}
  </div>

  <figure
    class="enumFigure"
    aria-label="A Direction enum with four alternative cases"
    bind:this={enumFigure}
  >
    <div class="enumStage">
      <div
        class="enumDeclaration"
        class:enumPulseFirst={enumPulse === 0}
        class:enumPulseSecond={enumPulse === 1}
      >
        <div class="enumLine enumHeader">
          <span class="enumKeyword">enum</span> Direction {"{"}
        </div>
        {#each enumCases as caseName, index}
          <div
            class="enumLine enumCase"
            class:activeEnumCase={enumCaseBeat === index}
          >
            <span class="enumCaseKeyword">case</span> {caseName}
          </div>
        {/each}
        <div class="enumLine">{"}"}</div>
      </div>
    </div>
  </figure>

  <div class="bindingIntro">
    {@render bindingIntro()}
  </div>

  <div class="bindingCode">
    {@render bindingCode()}
  </div>

  <div class="bindingDetail">
    {@render bindingDetail()}
  </div>

  <figure
    class="shapeFigure squareFigure"
    aria-label="Let, state, binding, and derived rhythm"
    bind:this={squareFigure}
  >
    <div class="shapeStage squareStage" bind:this={squareStage}>
      <svg viewBox="0 0 320 260" aria-hidden="true">
        <text
          class="shapeLabel squareLabel"
          class:activeSquareLabel={squareBeat === 0}
          x="42"
          y="18"
        >Let</text>
        <text
          class="shapeLabel squareLabel"
          class:activeSquareLabel={squareBeat === 1}
          x="278"
          y="18"
          text-anchor="end"
        >State</text>
        <text
          class="shapeLabel squareLabel"
          class:activeSquareLabel={squareBeat === 2}
          x="278"
          y="254"
          text-anchor="end"
        >Binding</text>
        <text
          class="shapeLabel squareLabel"
          class:activeSquareLabel={squareBeat === 3}
          x="42"
          y="254"
        >Derived</text>
      </svg>
    </div>
  </figure>

</div>

<style>
  .rhythm {
    position: relative;
  }

  .rhythm > :not(.pathRhythmShader) {
    position: relative;
    z-index: 1;
  }

  .pathRhythmShader {
    position: absolute;
    z-index: 2;
    inset: 0;
    display: block;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }

  .shapeFigure {
    margin: 30px 0 38px;
  }

  .identityDetail + .functionIntro {
    margin-top: 20px;
  }

  .bindingCode :global(range-code-block) {
    margin-top: 30px;
  }

  .functionCode :global(range-code-block) {
    margin-top: 30px;
  }

  .enumFigure {
    position: relative;
    z-index: 3;
    display: grid;
    width: 100vw;
    min-height: min(80svh, 720px);
    margin: 42px calc(50% - 50vw) 62px;
    padding: 32px clamp(28px, 10vw, 176px);
    place-items: center;
  }

  .enumStage {
    width: fit-content;
    max-width: 100%;
  }

  .enumDeclaration {
    display: grid;
    gap: 0.16em;
    font-family: var(--font-geist-mono), monospace;
    font-size: clamp(24px, min(4.4vw, 7.2svh), 68px);
    font-weight: 500;
    letter-spacing: -0.07em;
    line-height: 1.15;
    color: var(--ink);
    transform-origin: 0 50%;
  }

  .enumKeyword,
  .enumCaseKeyword {
    color: var(--range);
  }

  .enumLine {
    min-width: 0;
  }

  .enumCase {
    padding-left: 1.7ch;
    transition:
      color 160ms ease,
      text-shadow 160ms ease,
      transform 160ms cubic-bezier(0.22, 1, 0.36, 1);
  }

  .enumCase.activeEnumCase {
    color: var(--range);
    transform: translateX(0.5em);
  }

  .figureHeader {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    min-height: 32px;
    color: color-mix(in oklch, var(--ink), transparent 38%);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .rhythm > .rhythmAudioControl {
    display: none;
  }

  .rhythmAudioControl {
    display: flex;
    align-items: center;
    gap: 8px;
    pointer-events: none;
  }

  .autoScrollButton {
    min-height: 36px;
    padding: 0 14px;
    border: 1px solid color-mix(in oklch, var(--ink), transparent 78%);
    border-radius: 999px;
    background: color-mix(in oklch, var(--paper), transparent 6%);
    color: color-mix(in oklch, var(--ink), transparent 18%);
    font-family: var(--font-geist-mono), monospace;
    font-size: 11px;
    letter-spacing: 0.035em;
    cursor: pointer;
    pointer-events: auto;
  }

  .autoScrollButton:hover,
  .autoScrollButton:focus-visible,
  .autoScrollButton.autoScrollRunning {
    border-color: color-mix(in oklch, var(--range), transparent 48%);
    color: var(--range);
    outline: none;
  }

  .transportButton {
    position: relative;
    overflow: hidden;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    min-width: 36px;
    max-width: 36px;
    flex: 0 0 36px;
    min-height: 36px;
    padding: 0;
    border: 1px solid color-mix(in oklch, var(--range), transparent 70%);
    border-radius: 999px;
    background: var(--range);
    color: white;
    font-family: var(--font-geist-mono), monospace;
    font-size: 11px;
    letter-spacing: 0.045em;
    cursor: pointer;
    pointer-events: auto;
    box-shadow: none;
    transition:
      color 420ms cubic-bezier(0.22, 0.61, 0.36, 1),
      border-color 420ms cubic-bezier(0.22, 0.61, 0.36, 1),
      box-shadow 420ms cubic-bezier(0.22, 0.61, 0.36, 1);
  }

  .transportButton::before {
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background: color-mix(in oklch, white, transparent 4%);
    content: "";
    transform: scaleX(0);
    transform-origin: left center;
    transition: transform 520ms cubic-bezier(0.16, 1, 0.3, 1);
  }

  .transportButton > span {
    position: relative;
    z-index: 1;
  }

  .transportButton:hover {
    box-shadow: none;
  }

  .transportButton:focus-visible,
  .transportButton.transportRunning {
    border-color: color-mix(in oklch, var(--range), transparent 62%);
    outline: none;
  }

  .transportButton.transportRunning {
    color: color-mix(in oklch, var(--ink), transparent 12%);
  }

  .transportButton.transportRunning::before {
    transform: scaleX(1);
  }

  .transportButton:focus-visible {
    box-shadow: none;
  }

  .transportGlyph {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: white;
    box-shadow: none;
    transition:
      background 420ms cubic-bezier(0.22, 0.61, 0.36, 1),
      border-radius 420ms cubic-bezier(0.22, 0.61, 0.36, 1),
      box-shadow 420ms cubic-bezier(0.22, 0.61, 0.36, 1);
  }

  .transportButton.transportRunning .transportGlyph {
    border-radius: 1px;
    background: var(--range);
    box-shadow: none;
  }

  .shapeStage {
    width: min(100%, 420px);
    margin: 22px auto 0;
  }

  svg {
    display: block;
    width: 100%;
    overflow: visible;
  }

  svg .shapeLabel {
    fill: color-mix(in oklch, var(--ink), transparent 48%);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }

  .rhythm.playing .shapeLabel {
    animation: corner-label-bloom 1.8s linear infinite;
  }

  .rhythm.playing .triangleLabel1 {
    animation-delay: 0.6s;
  }

  .rhythm.playing .triangleLabel2 {
    animation-delay: 1.2s;
  }

  .squareLabel {
    transition: fill 180ms linear;
  }

  .squareLabel.activeSquareLabel {
    fill: var(--range);
  }

  .lineFigure {
    position: relative;
    display: grid;
    gap: 56px;
    margin: 30px 0 38px;
    padding: 40px 20px;
  }

  .identityRelation {
    position: relative;
  }

  .identityExpression {
    position: relative;
    z-index: 1;
    display: flex;
    justify-content: center;
    gap: 0.34em;
    color: var(--range);
    font-family: var(--font-geist-mono), monospace;
    font-size: clamp(18px, 2.4vw, 24px);
    font-weight: 520;
    letter-spacing: -0.035em;
    line-height: 1;
  }

  .identityValueTrack {
    position: relative;
    width: calc(100% - 10px);
    height: 4px;
    margin: 0 5px;
  }

  @keyframes corner-label-bloom {
    0%,
    9% {
      fill: var(--range);
    }

    14%,
    100% {
      fill: color-mix(in oklch, var(--ink), transparent 48%);
    }
  }

  @media (max-width: 520px) {
    .shapeFigure {
      margin-right: -4px;
      margin-left: -4px;
    }

    .figureHeader {
      align-items: flex-start;
    }

    .enumFigure {
      min-height: 70svh;
      margin-top: 28px;
      margin-bottom: 44px;
      padding: 32px 22px;
    }

    .enumDeclaration {
      font-size: clamp(22px, min(8.6vw, 6.4svh), 42px);
      letter-spacing: -0.075em;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .enumCase {
      transition: none;
    }
  }
</style>
