<script lang="ts">
  import { onMount } from "svelte";

  let canvas: HTMLCanvasElement;
  let stage: HTMLElement;
  let phase = $state(0);
  let showEncoding = $state(false);
  let looping = $state(false);
  let webglAvailable = $state(true);
  let requestRender = $state<() => void>(() => {});
  let toggleLoop = $state<() => void>(() => {});

  const frameCount = 24;
  const stripeWidth = 1;

  let visibleFrame = $derived(
    ((Math.round(-phase) % frameCount) + frameCount) % frameCount + 1,
  );

  $effect(() => {
    void showEncoding;
    requestRender();
  });

  onMount(() => {
    const context = canvas.getContext("webgl", {
      alpha: false,
      antialias: false,
      depth: false,
      powerPreference: "high-performance",
    });

    if (!context) {
      webglAvailable = false;
      return;
    }
    const gl = context;

    const vertexSource = `
      attribute vec2 a_position;

      void main() {
        gl_Position = vec4(a_position, 0.0, 1.0);
      }
    `;

    const fragmentSource = `
      precision highp float;

      uniform vec2 u_resolution;
      uniform float u_phase;
      uniform float u_frame_count;
      uniform float u_stripe_width;
      uniform float u_show_encoding;

      const float PI = 3.14159265359;

      mat2 rotate(float angle) {
        float cosine = cos(angle);
        float sine = sin(angle);
        return mat2(cosine, -sine, sine, cosine);
      }

      void main() {
        vec2 resolution = max(u_resolution, vec2(1.0));
        vec2 uv = (gl_FragCoord.xy * 2.0 - resolution) / resolution.y;

        // Every neighboring horizontal stripe contains a different complete
        // rotation frame. Step the encoded image beneath a screen-fixed gate;
        // this preserves relative scanimation motion without moving the line
        // lattice—and therefore the apparent cube—up and down.
        float stripe = floor(gl_FragCoord.y / u_stripe_width) - u_phase;
        float encodedFrame = mod(stripe, u_frame_count);
        float angle = encodedFrame / u_frame_count * PI * 2.0;

        // Use a centered orthographic camera. Perspective made the nearer side
        // occupy more screen space and shifted the silhouette laterally even
        // though the cube's mathematical center never moved.
        vec3 rayOrigin = vec3(uv * 1.5, 4.2);
        vec3 rayDirection = vec3(0.0, 0.0, -1.0);

        // Restore the original face-led anchor: turn around the cube's vertical
        // axis, then retain a fixed upward tilt so its top face stays present.
        rayOrigin.xz = rotate(-angle) * rayOrigin.xz;
        rayDirection.xz = rotate(-angle) * rayDirection.xz;
        rayOrigin.yz = rotate(-0.43) * rayOrigin.yz;
        rayDirection.yz = rotate(-0.43) * rayDirection.yz;

        vec3 inverseDirection = 1.0 / rayDirection;
        vec3 nearDistance = (-vec3(0.82) - rayOrigin) * inverseDirection;
        vec3 farDistance = (vec3(0.82) - rayOrigin) * inverseDirection;
        vec3 minimumDistance = min(nearDistance, farDistance);
        vec3 maximumDistance = max(nearDistance, farDistance);
        float entry = max(max(minimumDistance.x, minimumDistance.y), minimumDistance.z);
        float exit = min(min(maximumDistance.x, maximumDistance.y), maximumDistance.z);

        // Keep the encoded source binary: white object on black stock. Shape
        // changes come only from the cube silhouette, not face shading.
        vec3 color = vec3(0.0);
        if (exit >= max(entry, 0.0)) {
          color = vec3(1.0);
        }

        // One screen-fixed transparent slit per frame group selects the source
        // frame translated beneath it.
        float barrierPosition = mod(
          gl_FragCoord.y / u_stripe_width,
          u_frame_count
        );
        // Use nearly the complete source row for the gate opening. Going wider
        // would cross into the neighboring encoded frame.
        float slit = 1.0 - step(0.98, barrierPosition);
        float barrier = 1.0 - slit;
        barrier *= 1.0 - u_show_encoding;

        vec3 barrierColor = vec3(0.0);
        color = mix(color, barrierColor, barrier);

        // A faint separator remains visible when the barrier is lifted so the
        // twenty-four-frame interlacing can be inspected directly.
        float stripeEdge = smoothstep(
          0.84,
          1.0,
          fract(gl_FragCoord.y / u_stripe_width)
        );
        color = mix(color, vec3(0.02), stripeEdge * u_show_encoding * 0.2);

        gl_FragColor = vec4(color, 1.0);
      }
    `;

    function compile(type: number, source: string) {
      const shader = gl.createShader(type);
      if (!shader) throw new Error("Unable to create scanimation shader.");
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        throw new Error(gl.getShaderInfoLog(shader) ?? "Shader compilation failed.");
      }
      return shader;
    }

    let program: WebGLProgram;
    try {
      const vertex = compile(context.VERTEX_SHADER, vertexSource);
      const fragment = compile(context.FRAGMENT_SHADER, fragmentSource);
      const createdProgram = context.createProgram();
      if (!createdProgram) throw new Error("Unable to create scanimation program.");
      context.attachShader(createdProgram, vertex);
      context.attachShader(createdProgram, fragment);
      context.linkProgram(createdProgram);
      if (!context.getProgramParameter(createdProgram, context.LINK_STATUS)) {
        throw new Error(context.getProgramInfoLog(createdProgram) ?? "Shader link failed.");
      }
      program = createdProgram;
      context.deleteShader(vertex);
      context.deleteShader(fragment);
    } catch (error) {
      console.error(error);
      webglAvailable = false;
      return;
    }

    const position = context.createBuffer();
    context.bindBuffer(context.ARRAY_BUFFER, position);
    context.bufferData(
      context.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
      context.STATIC_DRAW,
    );

    const positionLocation = context.getAttribLocation(program, "a_position");
    const resolutionLocation = context.getUniformLocation(program, "u_resolution");
    const phaseLocation = context.getUniformLocation(program, "u_phase");
    const frameCountLocation = context.getUniformLocation(program, "u_frame_count");
    const stripeWidthLocation = context.getUniformLocation(program, "u_stripe_width");
    const showEncodingLocation = context.getUniformLocation(program, "u_show_encoding");
    let renderFrame: number | undefined;
    let wheelDistance = 0;
    let lastWheelDirection = 0;
    let lastAdvanceAt = Number.NEGATIVE_INFINITY;
    let loopTimer: number | undefined;
    let nextLoopAt = 0;
    const minimumFrameInterval = 1_000 / 24;
    const wheelStepDistance = 48;

    function render() {
      renderFrame = undefined;
      const density = Math.min(window.devicePixelRatio || 1, 2);
      const width = Math.max(1, Math.round(canvas.clientWidth * density));
      const height = Math.max(1, Math.round(canvas.clientHeight * density));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }

      gl.viewport(0, 0, width, height);
      gl.useProgram(program);
      gl.enableVertexAttribArray(positionLocation);
      gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);
      gl.uniform2f(resolutionLocation, width, height);
      gl.uniform1f(phaseLocation, phase);
      gl.uniform1f(frameCountLocation, frameCount);
      gl.uniform1f(stripeWidthLocation, stripeWidth * density);
      gl.uniform1f(showEncodingLocation, showEncoding ? 1 : 0);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    }

    requestRender = function requestScanimationRender() {
      if (renderFrame === undefined) renderFrame = requestAnimationFrame(render);
    };

    function advanceFrame(direction: number) {
      const now = performance.now();
      if (now - lastAdvanceAt < minimumFrameInterval) return false;
      phase = ((phase + direction) % frameCount + frameCount) % frameCount;
      lastAdvanceAt = now;
      requestRender();
      return true;
    }

    function scheduleLoopFrame() {
      if (!looping || loopTimer !== undefined) return;
      const delay = Math.max(0, nextLoopAt - performance.now());
      loopTimer = window.setTimeout(() => {
        loopTimer = undefined;
        if (!looping) return;
        phase = ((phase - 1) % frameCount + frameCount) % frameCount;
        lastAdvanceAt = performance.now();
        requestRender();
        nextLoopAt += minimumFrameInterval;
        if (nextLoopAt < performance.now()) {
          nextLoopAt = performance.now() + minimumFrameInterval;
        }
        scheduleLoopFrame();
      }, delay);
    }

    toggleLoop = () => {
      looping = !looping;
      wheelDistance = 0;
      if (looping) {
        nextLoopAt = performance.now() + minimumFrameInterval;
        scheduleLoopFrame();
      } else if (loopTimer !== undefined) {
        clearTimeout(loopTimer);
        loopTimer = undefined;
      }
    };

    function handleWheel(event: WheelEvent) {
      event.preventDefault();
      if (looping) return;
      let dominantDelta = Math.abs(event.deltaY) >= Math.abs(event.deltaX)
        ? event.deltaY
        : event.deltaX;
      if (event.deltaMode === WheelEvent.DOM_DELTA_LINE) dominantDelta *= 16;
      if (event.deltaMode === WheelEvent.DOM_DELTA_PAGE) {
        dominantDelta *= window.innerHeight;
      }
      const direction = Math.sign(dominantDelta);
      if (direction === 0) return;
      if (direction !== lastWheelDirection) wheelDistance = 0;
      lastWheelDirection = direction;
      wheelDistance += dominantDelta;
      wheelDistance = Math.max(
        -wheelStepDistance * 4,
        Math.min(wheelStepDistance * 4, wheelDistance),
      );
      if (Math.abs(wheelDistance) < wheelStepDistance) return;
      if (advanceFrame(direction)) {
        wheelDistance -= direction * wheelStepDistance;
      }
    }

    function handleKey(event: KeyboardEvent) {
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      event.preventDefault();
      if (looping) return;
      advanceFrame(event.key === "ArrowRight" ? 1 : -1);
    }

    const resizeObserver = new ResizeObserver(requestRender);
    resizeObserver.observe(canvas);
    stage.addEventListener("wheel", handleWheel, { passive: false });
    window.addEventListener("keydown", handleKey);
    requestRender();

    return () => {
      resizeObserver.disconnect();
      stage.removeEventListener("wheel", handleWheel);
      window.removeEventListener("keydown", handleKey);
      if (renderFrame !== undefined) cancelAnimationFrame(renderFrame);
      if (loopTimer !== undefined) clearTimeout(loopTimer);
      context.deleteBuffer(position);
      context.deleteProgram(program);
    };
  });
</script>

<svelte:head>
  <title>Scanimation cube — Range preview</title>
  <meta name="robots" content="noindex, nofollow" />
</svelte:head>

<main
  class="scanimationStage"
  bind:this={stage}
  aria-label="Scroll to rotate the scanimation cube"
>
  <canvas bind:this={canvas} aria-hidden="true"></canvas>

  <div class="interface">
    <div class="readout" aria-live="polite">
      <span>frame</span>
      <strong>{visibleFrame} / {frameCount}</strong>
    </div>

    <div class="controls">
      <button
        type="button"
        class:active={looping}
        aria-pressed={looping}
        onclick={toggleLoop}
      >
        {looping ? "Stop loop" : "Loop"}
      </button>

      <button
        type="button"
        class:active={showEncoding}
        aria-pressed={showEncoding}
        onclick={() => showEncoding = !showEncoding}
      >
        {showEncoding ? "Lower barrier" : "Lift barrier"}
      </button>
    </div>
  </div>

  {#if !webglAvailable}
    <p class="webglError">This study needs WebGL.</p>
  {/if}
</main>

<style>
  :global(body) {
    overflow: hidden;
    background: oklch(14% 0.01 45);
  }

  .scanimationStage {
    position: relative;
    width: 100%;
    height: 100svh;
    overflow: hidden;
    outline: none;
    overscroll-behavior: none;
    color: oklch(96% 0.012 70);
    background: oklch(14% 0.01 45);
  }

  canvas {
    display: block;
    width: 100%;
    height: 100%;
  }

  .interface {
    position: absolute;
    inset: 0;
    display: grid;
    grid-template-columns: 1fr auto;
    grid-template-rows: 1fr auto;
    align-items: end;
    gap: 20px;
    padding: clamp(20px, 4vw, 56px);
    pointer-events: none;
  }

  .readout span {
    margin: 0 0 8px;
    color: oklch(75% 0.018 65);
    font-family: var(--font-geist-mono, monospace);
    font-size: 11px;
    letter-spacing: 0.16em;
    text-transform: uppercase;
  }

  .readout {
    grid-column: 2;
    grid-row: 1;
    justify-self: end;
    text-align: right;
  }

  .readout strong {
    display: block;
    font-family: var(--font-geist-mono, monospace);
    font-size: 14px;
    font-weight: 500;
    letter-spacing: 0.04em;
  }

  .controls {
    grid-column: 2;
    grid-row: 2;
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    pointer-events: auto;
  }

  button {
    min-width: 126px;
    border: 1px solid oklch(76% 0.02 65 / 42%);
    border-radius: 999px;
    padding: 10px 15px;
    pointer-events: auto;
    color: oklch(96% 0.012 70);
    background: oklch(14% 0.01 45 / 72%);
    backdrop-filter: blur(12px);
    font: inherit;
    font-size: 13px;
    cursor: pointer;
  }

  button:hover,
  button:focus-visible,
  button.active {
    color: oklch(17% 0.012 45);
    background: oklch(96% 0.012 70);
  }

  .webglError {
    position: absolute;
    inset: 50% auto auto 50%;
    margin: 0;
    transform: translate(-50%, -50%);
  }

  @media (max-width: 620px) {
    .interface {
      grid-template-columns: 1fr auto;
      padding: 20px;
    }

    .readout {
      align-self: start;
    }
  }
</style>
