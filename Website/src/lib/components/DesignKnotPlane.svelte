<script lang="ts">
  import { getContext, onMount } from "svelte";
  import { highlightRange } from "$lib/benchmarks";
  import {
    RANGE_RHYTHM_SUBDIVISION_MS,
    RANGE_SOUND_MANAGER_CONTEXT,
    type RangeSoundManager,
  } from "$lib/audio/sound-manager";
  import mainSource from "../../../../Language/Core/Macros/Main.range?raw";

  let viewport: HTMLDivElement;
  let sourceLayer: HTMLPreElement;
  let renderCanvas: HTMLCanvasElement;
  let sourceCanvas: HTMLCanvasElement;
  let soundControl: HTMLDivElement;
  let soundEnabled = $state(false);
  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );
  const indexedSource = highlightRange(
    mainSource,
    new Set(["let", "if", "return", "function"]),
  );

  onMount(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const soundRoute = soundManager?.register("design-knot-keywords", 1);
    viewport
      .closest("range-essay-page")
      ?.querySelector<HTMLElement>("[data-range-hero-overlay]")
      ?.append(soundControl);
    const unsubscribeSound = soundManager?.subscribe((enabled) => {
      soundEnabled = enabled;
    });
    let frame = 0;
    let anchors: HTMLElement[] = [];
    let syntaxTokens: HTMLElement[] = [];
    let targets: { x: number; y: number }[] = [];
    let step = 0;
    let moving = false;
    let phaseFrame = 0;
    let playedStep = -1;
    let rhythmStep = 0;
    let measuredWidth = 0;
    let measuredHeight = 0;
    let nextRenderedAt = 0;
    let nextRhythmAt = 0;
    let refreshSpotlight = true;
    let renderContext: WebGLRenderingContext | null = null;
    let sourceContext: CanvasRenderingContext2D | null = null;
    let lensProgram: WebGLProgram | null = null;
    let lensTexture: WebGLTexture | null = null;

    const resumeAudio = () => {
      if (soundManager?.isEnabled()) void soundManager.resume();
    };
    window.addEventListener("pointerdown", resumeAudio, { passive: true });
    window.addEventListener("keydown", resumeAudio);

    const measure = () => {
      const previousWidth = measuredWidth;
      const previousHeight = measuredHeight;
      measuredWidth = viewport.clientWidth;
      measuredHeight = viewport.clientHeight;
      anchors = Array.from(
        sourceLayer.querySelectorAll<HTMLElement>("[data-keyword-index]"),
      );
      syntaxTokens = Array.from(
        sourceLayer.querySelectorAll<HTMLElement>(".token"),
      );
      const sourceLeft = sourceLayer.offsetParent instanceof HTMLElement
        ? sourceLayer.offsetParent.offsetLeft + sourceLayer.offsetLeft
        : sourceLayer.offsetLeft;
      const sourceTop = sourceLayer.offsetParent instanceof HTMLElement
        ? sourceLayer.offsetParent.offsetTop + sourceLayer.offsetTop
        : sourceLayer.offsetTop;
      targets = anchors.map((anchor) => ({
        x: measuredWidth / 2 - (sourceLeft + anchor.offsetLeft + anchor.offsetWidth / 2),
        y: measuredHeight / 2 - (sourceTop + anchor.offsetTop + anchor.offsetHeight / 2),
      }));
      if (previousWidth && previousHeight) {
        moving = false;
        phaseFrame = 0;
        refreshSpotlight = true;
      }
      const pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
      const canvasWidth = renderCanvas.parentElement?.clientWidth ?? measuredWidth;
      const canvasHeight = renderCanvas.parentElement?.clientHeight ?? measuredHeight;
      renderCanvas.width = Math.round(canvasWidth * pixelRatio);
      renderCanvas.height = Math.round(canvasHeight * pixelRatio);
      renderCanvas.style.width = `${canvasWidth}px`;
      renderCanvas.style.height = `${canvasHeight}px`;
      renderContext ??= renderCanvas.getContext("webgl", {
        alpha: true,
        antialias: false,
      });
      const gl = renderContext;
      if (gl && !lensProgram) {
        const compileShader = (type: number, source: string) => {
          const shader = gl.createShader(type)!;
          gl.shaderSource(shader, source);
          gl.compileShader(shader);
          return shader;
        };
        lensProgram = gl.createProgram()!;
        gl.attachShader(lensProgram, compileShader(gl.VERTEX_SHADER, `
          attribute vec2 position;
          varying vec2 uv;
          void main() {
            uv = position * 0.5 + 0.5;
            gl_Position = vec4(position, 0.0, 1.0);
          }
        `));
        gl.attachShader(lensProgram, compileShader(gl.FRAGMENT_SHADER, `
          precision highp float;
          uniform sampler2D image;
          uniform vec2 resolution;
          uniform float lensAmount;
          varying vec2 uv;
          void main() {
            vec2 centered = (uv - 0.5) * resolution;
            float radius = length(centered) / (length(resolution * 0.5) * 1.04);
            float falloff = smoothstep(0.96, 0.0, radius);
            float magnification = 1.0 + lensAmount * falloff;
            vec2 sampleUv = 0.5 + centered / magnification / resolution;
            vec2 edgeDistance = min(uv, 1.0 - uv);
            vec2 edgeFade = smoothstep(vec2(0.0), vec2(0.32, 0.4), edgeDistance);
            vec4 color = texture2D(image, sampleUv);
            color.a *= edgeFade.x * edgeFade.y;
            gl_FragColor = color;
          }
        `));
        gl.linkProgram(lensProgram);
        const vertices = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, vertices);
        gl.bufferData(
          gl.ARRAY_BUFFER,
          new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
          gl.STATIC_DRAW,
        );
        const position = gl.getAttribLocation(lensProgram, "position");
        gl.enableVertexAttribArray(position);
        gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
        lensTexture = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, lensTexture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      }
      gl?.viewport(0, 0, renderCanvas.width, renderCanvas.height);
      sourceCanvas.width = renderCanvas.width;
      sourceCanvas.height = renderCanvas.height;
      sourceContext = sourceCanvas.getContext("2d");
      sourceContext?.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    };

    const rhythm = [
      { hold: 18, speed: 0.82, lens: 0.2, tone: 0.82 },
      { hold: 10, speed: 0.94, lens: 0.22, tone: 0.9 },
      { hold: 14, speed: 1.02, lens: 0.24, tone: 0.96 },
      { hold: 34, speed: 0.76, lens: 0.21, tone: 0.86 },
      { hold: 8, speed: 1.08, lens: 0.25, tone: 1.04 },
      { hold: 16, speed: 0.92, lens: 0.27, tone: 0.94 },
      { hold: 7, speed: 1.18, lens: 0.29, tone: 1.12 },
      { hold: 28, speed: 0.84, lens: 0.25, tone: 0.9 },
      { hold: 6, speed: 1.24, lens: 0.3, tone: 1.16 },
      { hold: 9, speed: 1.16, lens: 0.32, tone: 1.08 },
      { hold: 6, speed: 1.3, lens: 0.34, tone: 1.2 },
      { hold: 20, speed: 0.96, lens: 0.3, tone: 1 },
      { hold: 12, speed: 1.08, lens: 0.28, tone: 1.06 },
      { hold: 15, speed: 0.98, lens: 0.26, tone: 0.98 },
      { hold: 20, speed: 0.9, lens: 0.23, tone: 0.9 },
      { hold: 41, speed: 0.72, lens: 0.2, tone: 0.8 },
    ] as const;
    const rhythmAt = (index: number) => rhythm[index % rhythm.length];
    const frameDuration = 1_000 / 24;
    const rhythmDuration = RANGE_RHYTHM_SUBDIVISION_MS * 12;
    const movementFramesForDistance = (distance: number, speed: number) => Math.min(
      40,
      Math.max(8, Math.round(distance / (620 * speed) * 24)),
    );
    const smootherstep = (value: number) =>
      value * value * value * (value * (value * 6 - 15) + 10);
    const drawSource = (x: number, y: number) => {
      if (!renderContext || !sourceContext) return;
      const context = sourceContext;
      const sourceStyle = getComputedStyle(sourceLayer);
      const fontSize = Number.parseFloat(sourceStyle.fontSize);
      const sourceLeft = sourceLayer.offsetParent instanceof HTMLElement
        ? sourceLayer.offsetParent.offsetLeft + sourceLayer.offsetLeft
        : sourceLayer.offsetLeft;
      const sourceTop = sourceLayer.offsetParent instanceof HTMLElement
        ? sourceLayer.offsetParent.offsetTop + sourceLayer.offsetTop
        : sourceLayer.offsetTop;
      context.clearRect(0, 0, renderCanvas.clientWidth, renderCanvas.clientHeight);
      context.font = `${sourceStyle.fontWeight} ${fontSize}px ${sourceStyle.fontFamily}`;
      context.textBaseline = "top";

      const walker = document.createTreeWalker(sourceLayer, NodeFilter.SHOW_TEXT);
      while (walker.nextNode()) {
        const node = walker.currentNode as Text;
        if (!node.data) continue;
        const range = document.createRange();
        range.selectNodeContents(node);
        const rectangles = Array.from(range.getClientRects());
        const color = node.parentElement?.closest<HTMLElement>(".token")
          ? getComputedStyle(node.parentElement.closest<HTMLElement>(".token")!).color
          : sourceStyle.color;
        context.fillStyle = color;
        const lines = node.data.split("\n");
        for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
          const text = lines[lineIndex];
          const rectangle = rectangles[lineIndex] ?? rectangles[0];
          if (!rectangle || !text) continue;
          const sourceRectangle = sourceLayer.getBoundingClientRect();
          const drawX = sourceLayer.offsetLeft + rectangle.left - sourceRectangle.left + x;
          const drawY = sourceLayer.offsetTop + rectangle.top - sourceRectangle.top + y;
          context.fillText(text, drawX, drawY, rectangle.width || undefined);
        }
      }
      const gl = renderContext;
      if (!gl || !lensProgram || !lensTexture) return;
      gl.useProgram(lensProgram);
      gl.bindTexture(gl.TEXTURE_2D, lensTexture);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, 1);
      gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGBA,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        sourceCanvas,
      );
      gl.uniform2f(
        gl.getUniformLocation(lensProgram, "resolution"),
        renderCanvas.clientWidth,
        renderCanvas.clientHeight,
      );
      gl.uniform1f(
        gl.getUniformLocation(lensProgram, "lensAmount"),
        rhythmAt(rhythmStep).lens,
      );
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    };
    const playBlock = (index: number, rhythmIndex = rhythmStep) => {
      if (
        index === playedStep
        || !soundRoute
        || !soundManager?.isEnabled()
      ) return;
      playedStep = index;
      const audio = soundRoute.audioContext;
      const now = audio.currentTime;
      const sub = audio.createOscillator();
      const harmonic = audio.createOscillator();
      const subGain = audio.createGain();
      const harmonicGain = audio.createGain();
      const lowpass = audio.createBiquadFilter();
      const pattern = rhythmAt(rhythmIndex);
      const bassScale = [43.65, 49.11, 52.38, 58.2, 65.48, 73.31, 77.6];
      const score = [0, 3, 1, 4, 2, 5, 3, 6, 0, 4, 1, 5, 2, 4, 1, 0];
      const baseFrequency = bassScale[score[rhythmIndex % score.length]];
      sub.type = "sine";
      harmonic.type = "triangle";
      sub.frequency.setValueAtTime(baseFrequency, now);
      harmonic.frequency.setValueAtTime(baseFrequency * 2.01, now);
      lowpass.type = "lowpass";
      lowpass.frequency.setValueAtTime(420, now);
      lowpass.frequency.exponentialRampToValueAtTime(210, now + 0.34);
      lowpass.Q.setValueAtTime(0.7, now);
      subGain.gain.setValueAtTime(0.0001, now);
      subGain.gain.linearRampToValueAtTime(0.26, now + 0.07);
      subGain.gain.exponentialRampToValueAtTime(0.09, now + 0.28);
      subGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.62);
      harmonicGain.gain.setValueAtTime(0.0001, now);
      harmonicGain.gain.linearRampToValueAtTime(0.045, now + 0.025);
      harmonicGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.18);
      sub.connect(lowpass).connect(subGain).connect(soundRoute.input);
      harmonic.connect(harmonicGain).connect(soundRoute.input);
      sub.start(now);
      harmonic.start(now);
      sub.stop(now + 0.64);
      harmonic.stop(now + 0.2);
    };
    const render = (now: number) => {
      if (!reducedMotion.matches && now < nextRenderedAt) {
        frame = requestAnimationFrame(render);
        return;
      }
      if (!reducedMotion.matches) {
        if (nextRenderedAt === 0) nextRenderedAt = now;
        do nextRenderedAt += frameDuration;
        while (nextRenderedAt <= now);
      }
      if (targets.length === 0) return;
      if (!reducedMotion.matches && now >= nextRhythmAt) {
        if (nextRhythmAt === 0) nextRhythmAt = now;
        do nextRhythmAt += rhythmDuration;
        while (nextRhythmAt <= now);
        rhythmStep = (rhythmStep + 1) % rhythm.length;
        playBlock(step, rhythmStep);
        soundManager?.publishRhythmBeat({
          step: rhythmStep,
          tick: rhythmStep * 12,
          audioTime: soundRoute?.audioContext.currentTime,
        });
      }
      const pattern = rhythmAt(rhythmStep);
      if (!moving && phaseFrame >= pattern.hold) {
        moving = true;
        phaseFrame = 0;
      }

      let nextStep = (step + 1) % targets.length;
      let current = targets[step];
      let next = targets[nextStep];
      let distance = Math.hypot(next.x - current.x, next.y - current.y);
      let movementFrames = movementFramesForDistance(distance, pattern.speed);
      if (moving && phaseFrame >= movementFrames) {
        step = nextStep;
        moving = false;
        phaseFrame = 0;
        nextStep = (step + 1) % targets.length;
        current = targets[step];
        next = targets[nextStep];
        distance = Math.hypot(next.x - current.x, next.y - current.y);
        movementFrames = movementFramesForDistance(
          distance,
          rhythmAt(rhythmStep).speed,
        );
      }
      const movement = moving
        ? smootherstep(phaseFrame / movementFrames)
        : 0;
      const x = current.x + (next.x - current.x) * movement;
      const y = current.y + (next.y - current.y) * movement;
      sourceLayer.style.transform = `translate3d(${x}px, ${y}px, 0)`;
      const viewportCenterX = viewport.clientWidth / 2;
      const viewportCenterY = viewport.clientHeight / 2;
      const halfWidth = viewport.clientWidth / 2;
      const halfHeight = viewport.clientHeight / 2;
      const sourceLeft = sourceLayer.offsetParent instanceof HTMLElement
        ? sourceLayer.offsetParent.offsetLeft + sourceLayer.offsetLeft
        : sourceLayer.offsetLeft;
      const sourceTop = sourceLayer.offsetParent instanceof HTMLElement
        ? sourceLayer.offsetParent.offsetTop + sourceLayer.offsetTop
        : sourceLayer.offsetTop;
      if (moving || refreshSpotlight) {
        for (const token of syntaxTokens) {
          const tokenX = sourceLeft + token.offsetLeft + token.offsetWidth / 2 + x;
          const tokenY = sourceTop + token.offsetTop + token.offsetHeight / 2 + y;
          const normalizedX = (tokenX - viewportCenterX) / halfWidth;
          const normalizedY = (tokenY - viewportCenterY) / halfHeight;
          const spotlightDistance = Math.hypot(normalizedX, normalizedY);
          const proximity = smootherstep(Math.max(0, 1 - spotlightDistance));
          token.style.setProperty("--syntax-proximity", proximity.toFixed(4));
        }
        refreshSpotlight = false;
      }
      drawSource(x, y);
      phaseFrame += 1;
      if (!reducedMotion.matches) frame = requestAnimationFrame(render);
    };

    const resizeObserver = new ResizeObserver(() => {
      measure();
      if (reducedMotion.matches) render(performance.now());
    });
    resizeObserver.observe(viewport);
    document.fonts.ready.then(() => {
      measure();
      playBlock(0);
      frame = requestAnimationFrame(render);
    });
    return () => {
      if (frame) cancelAnimationFrame(frame);
      resizeObserver.disconnect();
      unsubscribeSound?.();
      window.removeEventListener("pointerdown", resumeAudio);
      window.removeEventListener("keydown", resumeAudio);
      soundRoute?.dispose();
    };
  });

  async function toggleSound() {
    if (!soundManager) return;
    if (soundManager.isEnabled()) {
      soundManager.setEnabled(false);
      return;
    }
    const audio = await soundManager.resume();
    if (audio) soundManager.setEnabled(true);
  }
</script>

<div class="soundControl" bind:this={soundControl}>
  <button
    type="button"
    class:enabled={soundEnabled}
    aria-label={soundEnabled ? "Turn off article sound" : "Turn on article sound"}
    aria-pressed={soundEnabled}
    onclick={toggleSound}
    title={soundEnabled ? "Sound off" : "Sound on"}
  >
    <span aria-hidden="true"></span>
  </button>
</div>

<figure class="knotPlane">
  <div class="codeViewport" bind:this={viewport}>
    <div class="codeMask">
      <canvas class="renderCanvas" bind:this={renderCanvas} aria-hidden="true"></canvas>
      <canvas class="sourceCanvas" bind:this={sourceCanvas} aria-hidden="true"></canvas>
      <pre class="sourceLayer language-range" bind:this={sourceLayer}><code>{@html indexedSource}</code></pre>
    </div>
  </div>
  <figcaption>
    The control point, an entry point,<br />
    indexed by the flow that they shape.
  </figcaption>
</figure>

<style>
  .knotPlane {
    position: relative;
    margin: 42px 0 0;
  }

  .soundControl {
    display: flex;
    pointer-events: none;
  }

  .soundControl button {
    position: relative;
    overflow: hidden;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    min-width: 36px;
    min-height: 36px;
    padding: 0;
    border: 1px solid color-mix(in oklch, var(--range), transparent 70%);
    border-radius: 999px;
    background: var(--range);
    cursor: pointer;
    pointer-events: auto;
  }

  .soundControl button::before {
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background: color-mix(in oklch, white, transparent 4%);
    content: "";
    transform: scaleX(0);
    transform-origin: left center;
    transition: transform 520ms cubic-bezier(0.16, 1, 0.3, 1);
  }

  .soundControl button.enabled::before {
    transform: scaleX(1);
  }

  .soundControl button:focus-visible {
    outline: 2px solid var(--range);
    outline-offset: 3px;
  }

  .soundControl span {
    position: relative;
    z-index: 1;
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: white;
    transition:
      background 420ms cubic-bezier(0.22, 0.61, 0.36, 1),
      border-radius 420ms cubic-bezier(0.22, 0.61, 0.36, 1);
  }

  .soundControl button.enabled span {
    border-radius: 1px;
    background: var(--range);
  }

  .codeViewport {
    position: relative;
    z-index: 0;
    width: 100%;
    height: clamp(300px, 54vw, 470px);
    overflow: visible;
  }

  .codeMask {
    position: absolute;
    z-index: 0;
    inset: -12% -8%;
    overflow: hidden;
    background: radial-gradient(
      ellipse at center,
      white 0%,
      white 64%,
      color-mix(in oklch, white, transparent 22%) 84%,
      transparent 100%
    );
    perspective: 1100px;
  }

  .sourceLayer {
    position: absolute;
    z-index: 1;
    top: 12%;
    left: 8%;
    min-width: max-content;
    margin: 0;
    color: oklch(0.2 0.018 255);
    font-family: var(--font-geist-mono), monospace;
    font-size: clamp(16px, 2.6vw, 24px);
    font-weight: 480;
    line-height: 1.72;
    white-space: pre;
    opacity: 0;
    pointer-events: none;
  }

  .renderCanvas {
    position: absolute;
    z-index: 1;
    inset: 0;
    display: block;
    pointer-events: none;
  }

  .sourceCanvas {
    display: none;
  }


  .sourceLayer.language-range :global(.token.keyword[data-keyword-index]) {
    --syntax-color: oklch(0.56 0.2 var(--range-hue));
  }

  .sourceLayer.language-range :global(.token.keyword) {
    --syntax-color: oklch(0.56 0.2 var(--range-hue));
  }

  .sourceLayer.language-range :global(.token.macro) {
    --syntax-color: oklch(0.63 0.19 315);
  }

  .sourceLayer.language-range :global(.token.splice) {
    --syntax-color: oklch(0.62 0.18 290);
  }

  .sourceLayer.language-range :global(.token.property) {
    --syntax-color: oklch(0.51 0.11 190);
  }

  .sourceLayer.language-range :global(.token.type),
  .sourceLayer.language-range :global(.token.type-declaration) {
    --syntax-color: oklch(0.55 0.16 190);
  }

  .sourceLayer.language-range :global(.token.number) {
    --syntax-color: #1c00cf;
  }

  .sourceLayer.language-range :global(.token.comment) {
    --syntax-color: #5d6c79;
  }

  .sourceLayer.language-range :global(.token.punctuation) {
    --syntax-color: #8a8f98;
  }

  .sourceLayer.language-range :global(.token.brace) {
    --syntax-color: #565d66;
  }

  .sourceLayer.language-range :global(.token) {
    --syntax-color: #000000d9;
    color: color-mix(
      in oklch,
      color-mix(in oklch, var(--syntax-color), white 64%),
      var(--syntax-color) calc(18% + var(--syntax-proximity, 0) * 82%)
    ) !important;
  }

  figcaption {
    position: relative;
    z-index: 2;
    margin: 12px 6px 0;
    color: oklch(0.38 0.018 255);
    font-size: 13px;
    line-height: 1.5;
  }
</style>
