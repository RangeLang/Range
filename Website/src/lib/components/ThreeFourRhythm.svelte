<script lang="ts">
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

  type FigureAudioPhase = "before" | "entering" | "centered" | "passed";

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
  };

  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
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
  const enumCases = ["north", "east", "south", "west"] as const;
  let playing = $state(true);
  let audioEnabled = $state(false);
  let step = $state(-1);
  let rhythmTick = 0;
  let triangleBeat = $state(-1);
  let squareBeat = $state(-1);
  let enumPulse = $state(-1);
  let enumCaseBeat = $state(-1);
  let introMix = $state<IntroMixSettings>({ ...DEFAULT_INTRO_MIX });
  let nextStepAt = 0;
  let rhythmClockStartedAt = 0;
  let loopTimer: number | undefined;
  let audioContext: AudioContext | undefined;
  let audioRoute: RangeSoundRoute | undefined;
  let triangleBuffer: AudioBuffer | undefined;
  let blockBuffer: AudioBuffer | undefined;
  let masterGain: GainNode | undefined;
  let masterDryGain: GainNode | undefined;
  let masterLimiter: DynamicsCompressorNode | undefined;
  let masterReverb: ConvolverNode | undefined;
  let masterReverbWet: GainNode | undefined;
  let enumReverbSend: GainNode | undefined;
  let scoreGain: GainNode | undefined;
  const voiceBuses = new Map<IntroMixChannel, GainNode>();
  let rhythmElement: HTMLDivElement;
  let shaderCanvas: HTMLCanvasElement;
  let identityTrack: HTMLDivElement;
  let identityFigure: HTMLElement;
  let triangleStage: HTMLDivElement;
  let triangleFigure: HTMLElement;
  let enumFigure: HTMLElement;
  let squareStage: HTMLDivElement;
  let squareFigure: HTMLElement;
  let startShaderAnimation = () => {};
  let stopShaderAnimation = () => {};
  const activeOscillators = new Set<OscillatorNode>();
  const figureAudioStates = new WeakMap<HTMLElement, FigureAudioState>();

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
      !masterReverb ||
      !masterReverbWet ||
      !scoreGain
    ) {
      masterGain = audioContext.createGain();
      masterDryGain = audioContext.createGain();
      masterLimiter = audioContext.createDynamicsCompressor();
      masterReverb = audioContext.createConvolver();
      masterReverbWet = audioContext.createGain();
      enumReverbSend = audioContext.createGain();
      scoreGain = audioContext.createGain();
      masterGain.gain.setValueAtTime(
        introMix.master,
        audioContext.currentTime,
      );
      scoreGain.gain.setValueAtTime(
        audioEnabled ? 1 : 0.0001,
        audioContext.currentTime,
      );
      masterDryGain.gain.setValueAtTime(0.96, audioContext.currentTime);
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

      scoreGain.connect(masterGain);
      masterGain.connect(masterDryGain).connect(masterLimiter);
      masterGain
        .connect(masterReverb)
        .connect(masterReverbWet)
        .connect(masterLimiter);
      enumReverbSend.connect(masterReverb);
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

  function voiceOutput(channel: IntroMixChannel) {
    const master = masterOutput();
    if (!master || !audioContext) return;
    const destination = channel === "keyboard" ? master : scoreGain;
    if (!destination) return;

    let bus = voiceBuses.get(channel);
    if (!bus) {
      bus = audioContext.createGain();
      bus.gain.setValueAtTime(mixLevel(channel), audioContext.currentTime);
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
      bus.gain.setTargetAtTime(mixLevel(channel), now, 0.025);
    }
  }

  function setScoreGain(level: number) {
    if (!audioContext || !scoreGain) return;
    scoreGain.gain.setTargetAtTime(level, audioContext.currentTime, 0.012);
  }

  function playTone(
    channel: IntroMixChannel,
    frequency: number,
    type: OscillatorType,
    volume: number,
    duration = 0.22,
  ) {
    if (!audioEnabled || !audioContext || volume <= 0.0005) return;
    const destination = voiceOutput(channel);
    if (!destination) return;

    const now = audioContext.currentTime;
    const oscillator = audioContext.createOscillator();
    const filter = audioContext.createBiquadFilter();
    const gain = audioContext.createGain();
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
    oscillator.connect(filter);
    filter.connect(gain);
    gain.connect(destination);
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
    const rect = glyph.getBoundingClientRect();
    const distancePastCenter = window.innerHeight * 0.5 - (rect.top + rect.height * 0.5);
    const height = rect.height;
    const entryStartDistance = -(window.innerHeight + height) * 0.5;
    const centerRadius = Math.max(18, height * 0.14);
    return {
      distancePastCenter,
      height,
      entryStartDistance,
      centerRadius,
      progress: smoothRange(entryStartDistance, centerRadius, distancePastCenter),
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
          phase: "before",
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
  }

  function playTrianglePercussion(
    volumeScale: number,
    channel: IntroMixChannel = "forms",
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
    strike.buffer = triangleBuffer;
    highpass.type = "highpass";
    highpass.frequency.setValueAtTime(1800 * pitchRatio, now);
    highpass.Q.setValueAtTime(0.18, now);
    lowpass.type = "lowpass";
    lowpass.frequency.setValueAtTime(6200 * pitchRatio, now);
    lowpass.frequency.setTargetAtTime(3400 * pitchRatio, now + 0.008, 0.045);
    lowpass.Q.setValueAtTime(0.18, now);
    gain.gain.setValueAtTime(0.2 * volumeScale, now);
    strike.connect(highpass).connect(lowpass).connect(gain).connect(destination);
    strike.start(now);
  }

  function pulseTriangle(beat: number) {
    triangleBeat = beat;
    playTrianglePercussion(centeredRhythmVolume(triangleFigure));
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
    playTrianglePercussion(volume * 0.56, "enums");
    playEnumTailBend(volume);
  }

  function playEnumTailBend(volumeScale: number) {
    if (!audioEnabled || !audioContext || volumeScale <= 0.01) return;
    const destination = voiceOutput("enums");
    if (!destination) return;

    const startAt = audioContext.currentTime + 0.024;
    const pitchRatio = pitchRatioFor("enums");
    const oscillator = audioContext.createOscillator();
    const filter = audioContext.createBiquadFilter();
    const gain = audioContext.createGain();
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
    oscillator.connect(filter).connect(gain).connect(destination);
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

    strike.connect(bodyFilter).connect(bodyGain).connect(destination);
    strike.connect(knockFilter).connect(knockGain).connect(destination);
    strike.start(now);
    strike.stop(now + 0.065);
  }

  function pulseSquare(beat: number) {
    squareBeat = beat;
    playSquarePercussion(beat, centeredRhythmVolume(squareFigure));
  }

  function pulseLine(side: "identity" | "value") {
    playTone(
      "identity",
      (side === "identity" ? 55 : 82.4069) * pitchRatioFor("identity"),
      "sine",
      0.16 * centeredRhythmVolume(identityFigure),
      2.1,
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
    if (step % 6 === 0) pulseLine(step === 0 ? "identity" : "value");

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
    clearEnumVisuals();
    stopShaderAnimation();
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

  async function toggleAudio() {
    if (audioEnabled) {
      audioEnabled = false;
      soundManager?.setEnabled(false);
      setScoreGain(0.0001);
      return;
    }

    if (!(await ensureAudioRoute()) || !audioContext || !soundManager) return;
    audioEnabled = true;
    soundManager.setEnabled(true);
    trackFigureAudioStates();
    setScoreGain(1);
    syncMixGains();
  }

  onMount(() => {
    trackFigureAudioStates();
    window.addEventListener("scroll", trackFigureAudioStates, { passive: true });
    window.addEventListener("resize", trackFigureAudioStates);
    return () => {
      window.removeEventListener("scroll", trackFigureAudioStates);
      window.removeEventListener("resize", trackFigureAudioStates);
    };
  });

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
      const rootRect = rhythmElement.getBoundingClientRect();
      const targetRect = target.getBoundingClientRect();
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
    startRhythm();
    return stopRhythm;
  });

  onDestroy(() => {
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
    masterGain?.disconnect();
    masterDryGain?.disconnect();
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

  <div class="rhythmAudioControl">
    <button
      type="button"
      class="volumeButton"
      class:audioEnabled
      aria-label={audioEnabled ? "Mute rhythm" : "Enable rhythm sound"}
      aria-pressed={audioEnabled}
      onclick={toggleAudio}
      title={audioEnabled ? "Mute rhythm" : "Enable rhythm sound"}
    >
      <svg class="volumeIcon" viewBox="0 0 20 20" aria-hidden="true">
        <path d="M3 8h3l4-3v10l-4-3H3z"></path>
        {#if audioEnabled}
          <path class="volumeWave" d="M13 7.2c1.6 1.5 1.6 4.1 0 5.6"></path>
          <path class="volumeWave" d="M15.4 5c2.8 2.7 2.8 7.3 0 10"></path>
        {:else}
          <path class="volumeWave" d="m13 8 4 4m0-4-4 4"></path>
        {/if}
      </svg>
    </button>
  </div>

  <figure class="lineFigure" bind:this={identityFigure}>
    <div
      class="identityRelation"
      aria-label="Identity is connected to value"
    >
      <div class="identityExpression">
        <span>identity</span><span aria-hidden="true">:</span><span>value</span>
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
      <span>3 abstraction forms</span>
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
    transform: translateX(0.08em);
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
    position: sticky;
    z-index: 4;
    top: 20px;
    height: 0;
    display: flex;
    justify-content: flex-end;
    padding-right: 20px;
    pointer-events: none;
  }

  .volumeButton {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    min-height: 32px;
    padding: 0;
    border: 0;
    border-radius: 50%;
    background: color-mix(in oklch, white, var(--range) 5%);
    color: color-mix(in oklch, var(--range), transparent 28%);
    cursor: pointer;
    pointer-events: auto;
    box-shadow: 0 4px 18px color-mix(in oklch, var(--range), transparent 86%);
  }

  .volumeButton:hover,
  .volumeButton:focus-visible,
  .volumeButton.audioEnabled {
    background: color-mix(in oklch, white, var(--range) 12%);
    color: var(--range);
    outline: none;
  }

  .volumeButton:focus-visible {
    box-shadow: 0 0 0 3px color-mix(in oklch, var(--range), transparent 76%);
  }

  .volumeIcon {
    width: 17px;
    height: 17px;
    fill: currentColor;
  }

  .volumeWave {
    fill: none;
    stroke: currentColor;
    stroke-width: 1.35;
    stroke-linecap: round;
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
    color: var(--ink);
    font-family: var(--font-geist-mono), monospace;
    font-size: clamp(18px, 2.4vw, 24px);
    font-weight: 520;
    letter-spacing: -0.035em;
    line-height: 1;
  }

  .identityExpression span:first-child {
    color: color-mix(in oklch, var(--ink), var(--range) 22%);
  }

  .identityExpression span:last-child {
    color: var(--range);
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
