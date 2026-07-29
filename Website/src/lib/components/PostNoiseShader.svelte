<script lang="ts">
  import { onMount } from "svelte";
  import {
    measurePostContrast,
    type PostContrastPalette,
  } from "$lib/post-contrast";

  let {
    palette = 0,
    still = false,
    oncontrast,
  }: {
    palette?: number;
    still?: boolean;
    oncontrast?: (palette: PostContrastPalette) => void;
  } = $props();

  let canvas: HTMLCanvasElement;
  let paletteHue = $derived((22 + palette * 137.507764) % 360);

  const vertexSource = `
    attribute vec2 a_position;

    void main() {
      gl_Position = vec4(a_position, 0.0, 1.0);
    }
  `;

  const fragmentSource = `
    precision highp float;

    uniform vec2 u_resolution;
    uniform float u_time;
    uniform float u_palette;

    float hash(vec2 point) {
      point = fract(point * vec2(123.34, 456.21));
      point += dot(point, point + 45.32);
      return fract(point.x * point.y);
    }

    float noise(vec2 point) {
      vec2 cell = floor(point);
      vec2 local = fract(point);
      local = local * local * (3.0 - 2.0 * local);

      float a = hash(cell);
      float b = hash(cell + vec2(1.0, 0.0));
      float c = hash(cell + vec2(0.0, 1.0));
      float d = hash(cell + vec2(1.0, 1.0));

      return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
    }

    float fbm(vec2 point) {
      float value = 0.0;
      float amplitude = 0.54;
      mat2 turn = mat2(0.8, -0.6, 0.6, 0.8);

      for (int octave = 0; octave < 5; octave += 1) {
        value += amplitude * noise(point);
        point = turn * point * 2.03 + vec2(13.1, 7.7);
        amplitude *= 0.5;
      }

      return value;
    }

    vec3 oklabToLinearSrgb(vec3 color) {
      float lRoot = color.x + 0.3963377774 * color.y + 0.2158037573 * color.z;
      float mRoot = color.x - 0.1055613458 * color.y - 0.0638541728 * color.z;
      float sRoot = color.x - 0.0894841775 * color.y - 1.2914855480 * color.z;
      float l = lRoot * lRoot * lRoot;
      float m = mRoot * mRoot * mRoot;
      float s = sRoot * sRoot * sRoot;

      return vec3(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
      );
    }

    vec3 linearToSrgb(vec3 color) {
      color = max(color, vec3(0.0));
      vec3 lower = 12.92 * color;
      vec3 upper = 1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055;
      return mix(lower, upper, step(vec3(0.0031308), color));
    }

    vec3 oklch(float lightness, float chroma, float hueDegrees) {
      float hue = radians(hueDegrees);
      vec3 lab = vec3(
        lightness,
        chroma * cos(hue),
        chroma * sin(hue)
      );
      return clamp(linearToSrgb(oklabToLinearSrgb(lab)), 0.0, 1.0);
    }

    void main() {
      vec2 uv = gl_FragCoord.xy / u_resolution.xy;
      float aspect = u_resolution.x / max(u_resolution.y, 1.0);
      vec2 field = vec2(uv.x * aspect, uv.y);
      float time = u_time;

      float palettePhase = fract(u_palette * 0.61803398875);
      float paletteAngle = palettePhase * 6.28318530718;
      float cloudScale = mix(0.58, 0.84, palettePhase);
      vec2 flowDirection = vec2(
        cos(paletteAngle),
        sin(paletteAngle)
      ) * 0.052;
      vec2 paletteOrigin = vec2(
        hash(vec2(u_palette + 1.7, 4.1)),
        hash(vec2(8.3, u_palette + 2.9))
      ) * 18.0;
      vec2 largeFlow = flowDirection * time;
      vec2 cloudField =
        field * cloudScale + paletteOrigin;
      float warpStrength = mix(
        0.74,
        1.22,
        hash(vec2(u_palette + 5.3, 9.7))
      );
      float horizontalWarp = fbm(
        cloudField * 0.72 - largeFlow * 0.36 + vec2(3.1, 8.2)
      );
      float verticalWarp = fbm(
        cloudField * 0.94 + largeFlow * 0.22 + vec2(-5.2, 2.7)
      );
      vec2 cloudWarp = vec2(horizontalWarp, verticalWarp) - 0.5;
      float hills = fbm(
        cloudField
          + largeFlow
          + cloudWarp * warpStrength
      );
      float folding = fbm(
        cloudField * mix(1.08, 1.5, palettePhase)
          - largeFlow * 0.5
          + vec2(hills * 1.3, -hills * 0.8)
      );
      float fineClouds = fbm(
        cloudField * mix(2.45, 3.1, palettePhase)
          + largeFlow * 0.18
          + cloudWarp * 0.32
          + vec2(17.2, -9.4)
      );
      float cloudValue =
        hills * 0.64
        + folding * 0.38
        + (fineClouds - 0.5) * 0.16;
      float mapped = smoothstep(0.18, 0.84, cloudValue);
      mapped = smoothstep(0.08, 0.92, mapped);

      float ridge = 1.0 - abs(fineClouds * 2.0 - 1.0);
      ridge = smoothstep(0.58, 0.94, ridge) * (0.35 + folding * 0.65);

      float baseHue = 22.0 + u_palette * 137.507764;
      float hue = baseHue + mix(-38.0, 54.0, mapped) + ridge * 12.0;
      float lightness = mix(0.61, 0.89, mapped) + ridge * 0.025;
      float chroma =
        mix(0.175, 0.235, 0.28 + mapped * 0.72)
        + ridge * 0.012;
      vec3 color = oklch(lightness, chroma, hue);
      vec3 ridgeColor = oklch(
        min(lightness + 0.035, 0.94),
        chroma * 0.82,
        baseHue + 156.0
      );
      color = mix(color, ridgeColor, ridge * 0.13);

      color = (color - 0.5) * 1.075 + 0.5;

      float edgeShade = 1.0 - smoothstep(0.15, 0.82, distance(uv, vec2(0.5)));
      color *= 0.94 + edgeShade * 0.06;

      vec2 grainCell = floor(gl_FragCoord.xy * 0.5);
      float grainFrame = floor(time * 8.0);
      vec3 grain = vec3(
        hash(grainCell + grainFrame * 17.0),
        hash(grainCell.yx + grainFrame * 29.0),
        hash(grainCell + vec2(41.0, 73.0) + grainFrame * 11.0)
      );
      vec3 paletteGrain = mix(color, color.gbr, grain);
      color = mix(color, paletteGrain, 0.055);
      color += (grain - 0.5) * (0.008 + color * 0.008);

      gl_FragColor = vec4(color, 1.0);
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

  onMount(() => {
    const context = canvas.getContext("webgl", {
      alpha: false,
      antialias: false,
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
    const timeLocation = context.getUniformLocation(program, "u_time");
    const paletteLocation = context.getUniformLocation(program, "u_palette");
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sampleFramebuffer = context.createFramebuffer();
    const sampleTexture = context.createTexture();
    let frame = 0;
    let start = performance.now();
    let lastMeasurement = -Infinity;
    let sampleWidth = 0;
    let sampleHeight = 0;

    const resize = () => {
      const density = Math.min(window.devicePixelRatio || 1, 2);
      const width = Math.max(1, Math.round(canvas.clientWidth * density));
      const height = Math.max(1, Math.round(canvas.clientHeight * density));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
    };

    const draw = (
      width: number,
      height: number,
      time: number,
      framebuffer: WebGLFramebuffer | null,
    ) => {
      context.bindFramebuffer(context.FRAMEBUFFER, framebuffer);
      context.viewport(0, 0, width, height);
      context.useProgram(program);
      context.bindBuffer(context.ARRAY_BUFFER, positionBuffer);
      context.enableVertexAttribArray(positionLocation);
      context.vertexAttribPointer(positionLocation, 2, context.FLOAT, false, 0, 0);
      context.uniform2f(resolutionLocation, width, height);
      context.uniform1f(timeLocation, time);
      context.uniform1f(paletteLocation, palette);
      context.drawArrays(context.TRIANGLES, 0, 6);
    };

    const measureContrast = (time: number) => {
      if (!sampleFramebuffer || !sampleTexture) return;
      const nextWidth = 32;
      const nextHeight = Math.max(
        8,
        Math.min(32, Math.round(nextWidth * (canvas.height / canvas.width))),
      );

      if (sampleWidth !== nextWidth || sampleHeight !== nextHeight) {
        sampleWidth = nextWidth;
        sampleHeight = nextHeight;
        context.bindTexture(context.TEXTURE_2D, sampleTexture);
        context.texParameteri(
          context.TEXTURE_2D,
          context.TEXTURE_MIN_FILTER,
          context.NEAREST,
        );
        context.texParameteri(
          context.TEXTURE_2D,
          context.TEXTURE_MAG_FILTER,
          context.NEAREST,
        );
        context.texParameteri(
          context.TEXTURE_2D,
          context.TEXTURE_WRAP_S,
          context.CLAMP_TO_EDGE,
        );
        context.texParameteri(
          context.TEXTURE_2D,
          context.TEXTURE_WRAP_T,
          context.CLAMP_TO_EDGE,
        );
        context.texImage2D(
          context.TEXTURE_2D,
          0,
          context.RGBA,
          sampleWidth,
          sampleHeight,
          0,
          context.RGBA,
          context.UNSIGNED_BYTE,
          null,
        );
        context.bindFramebuffer(context.FRAMEBUFFER, sampleFramebuffer);
        context.framebufferTexture2D(
          context.FRAMEBUFFER,
          context.COLOR_ATTACHMENT0,
          context.TEXTURE_2D,
          sampleTexture,
          0,
        );
      }

      draw(sampleWidth, sampleHeight, time, sampleFramebuffer);
      const pixels = new Uint8Array(sampleWidth * sampleHeight * 4);
      context.readPixels(
        0,
        0,
        sampleWidth,
        sampleHeight,
        context.RGBA,
        context.UNSIGNED_BYTE,
        pixels,
      );
      oncontrast?.(measurePostContrast(pixels, sampleWidth, sampleHeight));
    };

    const render = (now: number) => {
      resize();
      const time = still || reducedMotion.matches ? 0 : (now - start) / 1000;
      draw(canvas.width, canvas.height, time, null);

      if (now - lastMeasurement >= 125) {
        measureContrast(time);
        lastMeasurement = now;
        context.bindFramebuffer(context.FRAMEBUFFER, null);
      }
      canvas.dataset.rendered = "true";

      if (!still && !reducedMotion.matches) {
        frame = window.requestAnimationFrame(render);
      }
    };

    const restart = () => {
      if (frame) window.cancelAnimationFrame(frame);
      frame = 0;
      start = performance.now();
      frame = window.requestAnimationFrame(render);
    };

    const observer = new ResizeObserver(restart);
    observer.observe(canvas);
    reducedMotion.addEventListener("change", restart);
    frame = window.requestAnimationFrame(render);

    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      observer.disconnect();
      reducedMotion.removeEventListener("change", restart);
      context.deleteFramebuffer(sampleFramebuffer);
      context.deleteTexture(sampleTexture);
      context.deleteBuffer(positionBuffer);
      context.deleteProgram(program);
      context.deleteShader(vertexShader);
      context.deleteShader(fragmentShader);
    };
  });
</script>

<canvas
  class="postShader"
  aria-hidden="true"
  data-palette={palette}
  style={`--palette-hue: ${paletteHue}`}
  bind:this={canvas}
></canvas>

<style>
  .postShader {
    width: 100%;
    height: 100%;
    display: block;
    background: oklch(0.8 0.16 var(--palette-hue));
  }
</style>
