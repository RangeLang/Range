<script lang="ts">
  import { onDestroy, onMount } from "svelte";
  import type { Snippet } from "svelte";

  let {
    abstractionIntro,
    abstractionCode,
    bindingIntro,
    bindingCode,
    bindingDetail,
    identityIntro,
    identityDetail,
  }: {
    abstractionIntro: Snippet;
    abstractionCode: Snippet;
    bindingIntro: Snippet;
    bindingCode: Snippet;
    bindingDetail: Snippet;
    identityIntro: Snippet;
    identityDetail: Snippet;
  } = $props();

  const subdivisionMilliseconds = 150;
  const enabledMasterLevel = 0.85;
  let playing = $state(true);
  let audioEnabled = $state(false);
  let step = $state(-1);
  let triangleBeat = $state(-1);
  let squareBeat = $state(-1);
  let nextStepAt = 0;
  let loopTimer: number | undefined;
  let audioContext: AudioContext | undefined;
  let clickBuffer: AudioBuffer | undefined;
  let masterGain: GainNode | undefined;
  let masterDryGain: GainNode | undefined;
  let masterLimiter: DynamicsCompressorNode | undefined;
  let masterReverb: ConvolverNode | undefined;
  let masterReverbWet: GainNode | undefined;
  let rhythmElement: HTMLDivElement;
  let shaderCanvas: HTMLCanvasElement;
  let identityTrack: HTMLDivElement;
  let identityFigure: HTMLElement;
  let triangleStage: HTMLDivElement;
  let triangleFigure: HTMLElement;
  let squareStage: HTMLDivElement;
  let squareFigure: HTMLElement;
  let startShaderAnimation = () => {};
  let stopShaderAnimation = () => {};
  const activeOscillators = new Set<OscillatorNode>();

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

      if (u_shape < 0.5) {
        vec2 start = vec2(8.0, u_resolution.y * 0.5);
        vec2 end = vec2(u_resolution.x - 8.0, u_resolution.y * 0.5);
        perimeter = length(end - start);
        closest = segmentInfo(point, start, end, 0.0);

        float cycle = mod(u_time, 1.8) / 0.9;
        float progress = cycle < 1.0 ? cycle : 2.0 - cycle;
        head = progress * perimeter;
        lineValueX = mix(start.x, end.x, progress);
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
        head = fract(u_time / 1.8) * perimeter;
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
        head = fract(u_time / 1.8) * perimeter;
      }

      vec3 color;
      float alpha;

      float pathDistance = abs(closest.y - head);
      if (u_shape >= 0.5) {
        pathDistance = min(pathDistance, perimeter - pathDistance);
      }
      float valueRadius = u_shape < 0.5
        ? max(u_resolution.x * 0.24, 1.0)
        : max(perimeter * 0.18, 1.0);
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
      !masterReverbWet
    ) {
      masterGain = audioContext.createGain();
      masterDryGain = audioContext.createGain();
      masterLimiter = audioContext.createDynamicsCompressor();
      masterReverb = audioContext.createConvolver();
      masterReverbWet = audioContext.createGain();
      masterGain.gain.setValueAtTime(
        enabledMasterLevel,
        audioContext.currentTime,
      );
      masterDryGain.gain.setValueAtTime(0.94, audioContext.currentTime);
      masterReverbWet.gain.setValueAtTime(0.12, audioContext.currentTime);
      masterLimiter.threshold.setValueAtTime(-12, audioContext.currentTime);
      masterLimiter.knee.setValueAtTime(10, audioContext.currentTime);
      masterLimiter.ratio.setValueAtTime(4, audioContext.currentTime);
      masterLimiter.attack.setValueAtTime(0.006, audioContext.currentTime);
      masterLimiter.release.setValueAtTime(0.12, audioContext.currentTime);

      const impulseLength = Math.round(audioContext.sampleRate * 0.72);
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
          channel[index] = noise * Math.pow(1 - progress, 3.4) * 0.36;
        }
      }
      masterReverb.buffer = impulse;

      masterGain.connect(masterDryGain).connect(masterLimiter);
      masterGain
        .connect(masterReverb)
        .connect(masterReverbWet)
        .connect(masterLimiter);
      masterLimiter.connect(audioContext.destination);
    }

    return masterGain;
  }

  function playTone(
    frequency: number,
    type: OscillatorType,
    volume: number,
    duration = 0.14,
  ) {
    if (!audioEnabled || !audioContext) return;
    const destination = masterOutput();
    if (!destination) return;

    const now = audioContext.currentTime;
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();
    const peakVolume = Math.max(0.0001, volume);
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, now);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(peakVolume, now + 0.012);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + duration - 0.01);
    oscillator.connect(gain);
    gain.connect(destination);
    activeOscillators.add(oscillator);
    oscillator.onended = () => activeOscillators.delete(oscillator);
    oscillator.start(now);
    oscillator.stop(now + duration);
  }

  function smoothRange(start: number, end: number, value: number) {
    if (end <= start) return value >= end ? 1 : 0;
    const progress = Math.max(0, Math.min(1, (value - start) / (end - start)));
    return progress * progress * (3 - 2 * progress);
  }

  function centeredRhythmVolume(target: HTMLElement) {
    const figures = [identityFigure, triangleFigure, squareFigure];
    const targetIndex = figures.indexOf(target);
    if (targetIndex < 0) return 0;

    const scrollPosition = window.scrollY;
    const viewportAnchor = scrollPosition + window.innerHeight * 0.5;
    const centers = figures.map((figure) => {
      const rect = figure.getBoundingClientRect();
      return rect.top + scrollPosition + rect.height * 0.5;
    });
    const targetCenter = centers[targetIndex];
    const previousCenter = targetIndex > 0
      ? centers[targetIndex - 1]
      : targetCenter - window.innerHeight * 0.72;

    if (viewportAnchor < targetCenter) {
      return smoothRange(
        previousCenter,
        targetCenter,
        viewportAnchor,
      ) * 0.8;
    }

    for (
      let stageIndex = targetIndex;
      stageIndex < centers.length - 1;
      stageIndex += 1
    ) {
      const nextCenter = centers[stageIndex + 1];
      if (viewportAnchor <= nextCenter) {
        const passedFigures = stageIndex - targetIndex;
        const startLevel = Math.max(0.2, Math.pow(0.45, passedFigures));
        const endLevel = Math.max(0.2, Math.pow(0.45, passedFigures + 1));
        const progress = smoothRange(
          centers[stageIndex],
          nextCenter,
          viewportAnchor,
        );
        return (startLevel + (endLevel - startLevel) * progress) * 0.8;
      }
    }

    const passedFigures = centers.length - 1 - targetIndex;
    const retainedLevel = Math.max(0.2, Math.pow(0.45, passedFigures));
    const finalCenter = centers.at(-1) ?? targetCenter;
    const tail = 1 - smoothRange(
      finalCenter,
      finalCenter + window.innerHeight * 1.1,
      viewportAnchor,
    );
    return retainedLevel * tail * 0.8;
  }

  function pulseTriangle(beat: number) {
    triangleBeat = beat;
    playTone(
      220,
      "triangle",
      0.09 * centeredRhythmVolume(triangleFigure),
    );
  }

  function playSquarePercussion(volumeScale: number) {
    if (!audioEnabled || !audioContext) return;
    const destination = masterOutput();
    if (!destination) return;

    const now = audioContext.currentTime;
    clickBuffer ??= (() => {
      const length = Math.max(
        1,
        Math.round(audioContext.sampleRate * 0.006),
      );
      const buffer = audioContext.createBuffer(
        1,
        length,
        audioContext.sampleRate,
      );
      const samples = buffer.getChannelData(0);
      let seed = 0x72e5a91d;
      for (let index = 0; index < length; index += 1) {
        seed = (seed * 1664525 + 1013904223) >>> 0;
        const noise = seed / 2147483648 - 1;
        samples[index] = noise * (1 - index / length);
      }
      return buffer;
    })();

    const click = audioContext.createBufferSource();
    const clickHighpass = audioContext.createBiquadFilter();
    const clickGain = audioContext.createGain();
    click.buffer = clickBuffer;
    clickHighpass.type = "bandpass";
    clickHighpass.frequency.setValueAtTime(620, now);
    clickHighpass.Q.setValueAtTime(0.65, now);
    clickGain.gain.setValueAtTime(0.0001, now);
    clickGain.gain.linearRampToValueAtTime(
      Math.max(0.0001, 0.16 * volumeScale),
      now + 0.001,
    );
    clickGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.006);
    click.connect(clickHighpass);
    clickHighpass.connect(clickGain);
    clickGain.connect(destination);
    click.start(now);

    const resonances = [
      { frequency: 461.75, volume: 0.14, duration: 0.042 },
      { frequency: 740.75, volume: 0.08, duration: 0.034 },
    ];

    for (const resonance of resonances) {
      const oscillator = audioContext.createOscillator();
      const gain = audioContext.createGain();

      oscillator.type = "sine";
      oscillator.frequency.setValueAtTime(resonance.frequency, now);
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.linearRampToValueAtTime(
        Math.max(0.0001, resonance.volume * volumeScale),
        now + 0.0015,
      );
      gain.gain.exponentialRampToValueAtTime(
        0.0001,
        now + resonance.duration,
      );

      oscillator.connect(gain);
      gain.connect(destination);
      activeOscillators.add(oscillator);
      oscillator.onended = () => activeOscillators.delete(oscillator);
      oscillator.start(now);
      oscillator.stop(now + resonance.duration + 0.003);
    }
  }

  function pulseSquare(beat: number) {
    squareBeat = beat;
    playSquarePercussion(centeredRhythmVolume(squareFigure));
  }

  function pulseLine(side: "identity" | "value") {
    playTone(
      side === "identity" ? 27.5 : 41.2034,
      "sine",
      0.11 * centeredRhythmVolume(identityFigure),
      0.34,
    );
  }

  function playStep() {
    if (!playing) return;

    const now = performance.now();
    if (nextStepAt < now - subdivisionMilliseconds) {
      nextStepAt = now;
    }

    step = (step + 1) % 12;

    // Three accents divide the shared 12-step cycle into groups of four.
    if (step % 4 === 0) pulseTriangle(step / 4);

    // Four accents divide the same cycle into groups of three.
    if (step % 3 === 0) pulseSquare(step / 3);

    // Identity and value alternate across the same shared cycle.
    if (step % 6 === 0) pulseLine(step === 0 ? "identity" : "value");

    nextStepAt += subdivisionMilliseconds;
    loopTimer = window.setTimeout(
      playStep,
      Math.max(0, nextStepAt - now),
    );
  }

  function startRhythm() {
    playing = true;
    step = -1;
    nextStepAt = performance.now();
    startShaderAnimation();
    playStep();
  }

  function stopRhythm() {
    playing = false;
    if (typeof window !== "undefined") {
      window.clearTimeout(loopTimer);
    }
    loopTimer = undefined;
    stopShaderAnimation();
  }

  async function toggleAudio() {
    if (audioEnabled) {
      audioEnabled = false;
      if (audioContext && masterGain) {
        masterGain.gain.setTargetAtTime(
          0.0001,
          audioContext.currentTime,
          0.01,
        );
      }
      return;
    }

    audioContext ??= new AudioContext();
    if (audioContext.state === "suspended") await audioContext.resume();
    audioEnabled = true;

    const output = masterOutput();
    if (output) {
      output.gain.cancelScheduledValues(audioContext.currentTime);
      output.gain.setTargetAtTime(
        enabledMasterLevel,
        audioContext.currentTime,
        0.01,
      );
    }
  }

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
    let startedAt = performance.now();

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
      startedAt = performance.now();
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
    for (const oscillator of activeOscillators) oscillator.stop();
    activeOscillators.clear();
    void audioContext?.close();
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
      <svg
        class="volumeIcon"
        viewBox="0 0 20 20"
        aria-hidden="true"
      >
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

  <div class="abstractionIntro">
    {@render abstractionIntro()}
  </div>

  <figure
    class="shapeFigure triangleFigure"
    aria-label="Constructs, enums, and macros"
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
        >Constructs</text>
        <text
          class="shapeLabel triangleLabel triangleLabel1"
          x="292"
          y="247"
          text-anchor="end"
        >Enums</text>
        <text
          class="shapeLabel triangleLabel triangleLabel2"
          x="28"
          y="247"
        >Macros</text>
      </svg>
    </div>
  </figure>

  <div class="abstractionCode">
    {@render abstractionCode()}
  </div>

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

  .identityDetail + .abstractionIntro {
    margin-top: 20px;
  }

  .bindingCode :global(range-code-block) {
    margin-top: 30px;
  }

  .abstractionCode :global(range-code-block) {
    margin-top: 30px;
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

    .volumeButton {
      flex: 0 0 auto;
    }
  }
</style>
