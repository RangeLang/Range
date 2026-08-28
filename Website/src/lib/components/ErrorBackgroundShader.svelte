<script lang="ts">
  import { onMount } from "svelte";

  let { trigger = 0 }: { trigger?: number } = $props();

  let canvas: HTMLCanvasElement;
  let canvasReady = $state(false);
  let gl: WebGL2RenderingContext | null = null;
  let program: WebGLProgram | null = null;
  let resolutionLocation: WebGLUniformLocation | null = null;
  let progressLocation: WebGLUniformLocation | null = null;
  let directionLocation: WebGLUniformLocation | null = null;
  let sweepProgress = 1;
  let sweepDirection = 1;
  let sweepStartedAt = 0;
  let sweepFrame: number | null = null;
  let pendingSweep = false;
  let lastTrigger = 0;
  let active = false;

  const vertexShaderSource = `#version 300 es
    precision highp float;

    const vec2 positions[3] = vec2[3](
      vec2(-1.0, -1.0),
      vec2(3.0, -1.0),
      vec2(-1.0, 3.0)
    );

    out vec2 vUv;

    void main() {
      vec2 position = positions[gl_VertexID];
      vUv = position * 0.5 + 0.5;
      gl_Position = vec4(position, 0.0, 1.0);
    }
  `;

  const fragmentShaderSource = `#version 300 es
    precision highp float;

    uniform vec2 uResolution;
    uniform float uProgress;
    uniform float uDirection;

    in vec2 vUv;
    out vec4 outputColor;

    float hash21(vec2 value) {
      vec3 mixed = fract(vec3(value.xyx) * vec3(123.34, 456.21, 345.45));
      mixed += dot(mixed, mixed.yzx + 34.345);
      return fract((mixed.x + mixed.y) * mixed.z);
    }

    float starLayer(vec2 uv, float scale, float threshold) {
      float aspect = uResolution.x / max(uResolution.y, 1.0);
      vec2 grid = vec2(uv.x * aspect, uv.y) * scale;
      vec2 cell = floor(grid);
      vec2 point = vec2(
        hash21(cell + vec2(1.7, 9.2)),
        hash21(cell + vec2(8.3, 2.8))
      );
      float seed = hash21(cell + 4.7);
      float distanceToStar = length(fract(grid) - point);
      float core = 1.0 - smoothstep(0.012, 0.055, distanceToStar);
      float halo = 1.0 - smoothstep(0.035, 0.14, distanceToStar);
      return step(threshold, seed) * (core + halo * 0.22) *
        mix(0.42, 1.0, seed);
    }

    vec3 backgroundAt(vec2 uv) {
      vec3 color = vec3(0.0015, 0.003, 0.009);
      float centerNebula = exp(
        -dot(
          (uv - vec2(0.5, 0.48)) / vec2(0.48, 0.38),
          (uv - vec2(0.5, 0.48)) / vec2(0.48, 0.38)
        ) * 2.1
      );
      float blueNebula = exp(
        -dot(
          (uv - vec2(0.72, 0.72)) / vec2(0.34, 0.28),
          (uv - vec2(0.72, 0.72)) / vec2(0.34, 0.28)
        ) * 2.5
      );
      color += vec3(0.012, 0.028, 0.055) * centerNebula;
      color += vec3(0.008, 0.022, 0.048) * blueNebula;
      float stars =
        starLayer(uv, 46.0, 0.965) +
        starLayer(uv + vec2(0.173, 0.311), 79.0, 0.988) * 0.55;
      color += vec3(0.72, 0.82, 1.0) * stars * 0.46;
      return color;
    }

    void main() {
      float aspect = uResolution.x / max(uResolution.y, 1.0);
      float directionalProgress = uDirection > 0.0
        ? uProgress
        : 1.0 - uProgress;
      vec2 lensCenter = vec2(
        mix(-0.2, 1.2, directionalProgress),
        0.5
      );
      vec2 metricOffset = vec2(
        (vUv.x - lensCenter.x) * aspect,
        vUv.y - lensCenter.y
      );
      float radius = length(metricOffset);
      float lens = 1.0 - smoothstep(0.045, 0.21, radius);
      vec2 warpedMetric = metricOffset * (1.0 + lens * lens * 0.2);
      vec2 warpedUv = lensCenter + vec2(
        warpedMetric.x / aspect,
        warpedMetric.y
      );

      vec3 color = backgroundAt(warpedUv);
      float core = 1.0 - smoothstep(0.032, 0.056, radius);
      color *= 1.0 - core * 0.96;

      float angle = atan(metricOffset.y, metricOffset.x);
      float photonRing = exp(-pow((radius - 0.069) / 0.011, 2.0));
      float arc = photonRing * (
        0.34 + 0.66 * pow(0.5 + 0.5 * sin(angle * 2.0 - 0.7), 2.0)
      );
      vec3 coolLight = vec3(0.33, 0.62, 1.0);
      vec3 amberLight = vec3(1.0, 0.48, 0.13);
      vec3 ringColor = mix(
        coolLight,
        amberLight,
        0.5 + 0.5 * sin(angle - 0.35)
      );
      color += ringColor * arc * 0.24;

      float outerCaustic = exp(-pow((radius - 0.145) / 0.024, 2.0));
      color += vec3(0.18, 0.3, 0.52) * outerCaustic * lens * 0.055;

      vec2 fieldPosition = (vUv - vec2(0.5)) / vec2(0.58, 0.54);
      float fieldMask = exp(-dot(fieldPosition, fieldPosition) * 1.35);
      float edgeMask =
        smoothstep(0.0, 0.1, vUv.x) *
        smoothstep(0.0, 0.1, 1.0 - vUv.x) *
        smoothstep(0.0, 0.12, vUv.y) *
        smoothstep(0.0, 0.12, 1.0 - vUv.y);
      float alpha = clamp(fieldMask * edgeMask * 0.78 + arc * 0.16, 0.0, 0.86);
      outputColor = vec4(color * alpha, alpha);
    }
  `;

  function compileShader(type: number, source: string) {
    if (!gl) throw new Error("WebGL is unavailable.");
    const shader = gl.createShader(type);
    if (!shader) throw new Error("Unable to create background shader.");
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const message = gl.getShaderInfoLog(shader) ?? "Unknown shader error.";
      gl.deleteShader(shader);
      throw new Error(message);
    }
    return shader;
  }

  function createProgram() {
    if (!gl) throw new Error("WebGL is unavailable.");
    const vertexShader = compileShader(gl.VERTEX_SHADER, vertexShaderSource);
    const fragmentShader = compileShader(gl.FRAGMENT_SHADER, fragmentShaderSource);
    const nextProgram = gl.createProgram();
    if (!nextProgram) throw new Error("Unable to create background program.");
    gl.attachShader(nextProgram, vertexShader);
    gl.attachShader(nextProgram, fragmentShader);
    gl.linkProgram(nextProgram);
    gl.deleteShader(vertexShader);
    gl.deleteShader(fragmentShader);
    if (!gl.getProgramParameter(nextProgram, gl.LINK_STATUS)) {
      const message = gl.getProgramInfoLog(nextProgram) ?? "Unknown program error.";
      gl.deleteProgram(nextProgram);
      throw new Error(message);
    }
    return nextProgram;
  }

  function render() {
    if (!gl || !program || !active || canvas.width <= 0 || canvas.height <= 0) return;
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.useProgram(program);
    gl.uniform2f(resolutionLocation, canvas.width, canvas.height);
    gl.uniform1f(progressLocation, sweepProgress);
    gl.uniform1f(directionLocation, sweepDirection);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  function resize() {
    const density = Math.min(2, window.devicePixelRatio || 1);
    const width = Math.max(1, Math.round(canvas.clientWidth * density));
    const height = Math.max(1, Math.round(canvas.clientHeight * density));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    render();
  }

  function animateSweep(timestamp: number) {
    if (!active) {
      sweepFrame = null;
      return;
    }
    sweepProgress = Math.min(1, (timestamp - sweepStartedAt) / 820);
    render();
    if (sweepProgress < 1) {
      sweepFrame = requestAnimationFrame(animateSweep);
    } else {
      sweepFrame = null;
    }
  }

  function requestSweep() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    if (!active || !canvasReady) {
      pendingSweep = true;
      return;
    }
    pendingSweep = false;
    if (sweepFrame !== null) cancelAnimationFrame(sweepFrame);
    sweepProgress = 0;
    sweepStartedAt = performance.now();
    sweepFrame = requestAnimationFrame(animateSweep);
  }

  onMount(() => {
    active = true;
    try {
      gl = canvas.getContext("webgl2", {
        alpha: true,
        antialias: false,
        premultipliedAlpha: true,
        powerPreference: "high-performance",
      });
      if (!gl) throw new Error("WebGL 2 is unavailable.");
      program = createProgram();
      resolutionLocation = gl.getUniformLocation(program, "uResolution");
      progressLocation = gl.getUniformLocation(program, "uProgress");
      directionLocation = gl.getUniformLocation(program, "uDirection");
      canvasReady = true;
      resize();
      if (pendingSweep) requestSweep();
    } catch (error) {
      active = false;
      console.error("Error background shader could not initialize.", error);
    }

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(canvas);

    return () => {
      active = false;
      resizeObserver.disconnect();
      if (sweepFrame !== null) cancelAnimationFrame(sweepFrame);
      if (gl && program) gl.deleteProgram(program);
    };
  });

  $effect(() => {
    const nextTrigger = trigger;
    if (nextTrigger <= 0 || nextTrigger === lastTrigger) return;
    lastTrigger = nextTrigger;
    sweepDirection = nextTrigger % 2 === 1 ? 1 : -1;
    requestSweep();
  });
</script>

<canvas
  class="backgroundShader"
  class:canvasReady
  bind:this={canvas}
  data-error-background-shader
  aria-hidden="true"
></canvas>

<style>
  .backgroundShader {
    position: absolute;
    z-index: -1;
    inset: -34% -12%;
    width: auto;
    height: auto;
    display: block;
    opacity: 0;
    transition: opacity 240ms ease;
  }

  .backgroundShader.canvasReady {
    opacity: 1;
  }
</style>
