<script lang="ts">
  import { onMount } from "svelte";

  let {
    palette = 0,
    topAligned = false,
    offsetX = 0,
    offsetY = 0,
  }: {
    palette?: number;
    topAligned?: boolean;
    offsetX?: number;
    offsetY?: number;
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
    uniform float u_rotation_time;
    uniform float u_palette;
    uniform float u_top_aligned;
    uniform vec2 u_offset;

    float hash(vec2 point) {
      point = fract(point * vec2(123.34, 456.21));
      point += dot(point, point + 45.32);
      return fract(point.x * point.y);
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

    float glow(vec2 point, vec2 center, float radius) {
      float distanceFromCenter = distance(point, center);
      return exp(-max(distanceFromCenter - radius, 0.0) * 8.0);
    }

    vec4 renderedSphere(
      vec2 point,
      vec2 center,
      float radius,
      float materialMix,
      float phase,
      float time
    ) {
      vec2 local = (point - center) / radius;
      float radial = length(local);
      float mask = 1.0 - smoothstep(0.94, 1.04, radial);
      float surfaceZ = sqrt(max(0.0, 1.0 - dot(local, local)));
      vec3 normal = normalize(vec3(local, surfaceZ));
      vec3 light = normalize(vec3(-0.62, 0.78, 0.92));
      vec3 view = vec3(0.0, 0.0, 1.0);

      float diffuse = 0.5 + 0.5 * dot(normal, light);
      float longitude = atan(local.y, local.x);
      float materialTime = time * 0.018;
      float warpedBands = 0.5 + 0.5 * sin(
        local.x * 5.4
        + local.y * 3.2
        + surfaceZ * 7.0
        + sin(longitude * 3.0 + phase) * 1.25
        + phase
        + materialTime
      );
      float crossBands = 0.5 + 0.5 * sin(
        longitude * 4.0
        - radial * 8.0
        + warpedBands * 2.4
        - materialTime * 0.72
      );
      float colorWarp = warpedBands * 0.68 + crossBands * 0.32;

      float lightness = mix(0.68, 0.98, diffuse);
      lightness += (colorWarp - 0.5) * 0.08;
      vec3 gold = oklch(
        clamp(lightness, 0.62, 0.99),
        mix(0.08, 0.17, colorWarp),
        84.0
      );
      vec3 slate = oklch(
        clamp(lightness - 0.025, 0.58, 0.96),
        mix(0.025, 0.065, crossBands),
        252.0
      );
      float material = clamp(
        materialMix + (colorWarp - 0.5) * 0.72,
        0.0,
        1.0
      );
      vec3 color = mix(gold, slate, material);

      float rim = pow(1.0 - surfaceZ, 2.2);
      vec3 rimColor = mix(
        oklch(0.91, 0.13, 84.0),
        oklch(0.86, 0.055, 252.0),
        materialMix
      );
      color = mix(color, rimColor, rim * 0.5);

      vec3 halfVector = normalize(light + view);
      float facingLight = max(dot(normal, halfVector), 0.0);
      float broadExposure = pow(facingLight, 7.0);
      float hotSpot = pow(facingLight, 52.0);
      vec3 highlight = oklch(0.995, 0.018, 88.0);
      color += highlight * broadExposure * 0.3;
      color = mix(color, highlight, hotSpot * 0.96);

      float innerHaze = pow(max(surfaceZ, 0.0), 0.55);
      color += mix(
        oklch(0.88, 0.08, 84.0),
        oklch(0.82, 0.035, 252.0),
        materialMix
      ) * innerHaze * 0.11;
      return vec4(clamp(color, 0.0, 1.0), mask);
    }

    float rays(
      vec2 point,
      vec2 center,
      float radius,
      float count,
      float phase
    ) {
      vec2 offset = point - center;
      float distanceFromCenter = length(offset);
      float angle = atan(offset.y, offset.x);
      float beam = pow(0.5 + 0.5 * cos(angle * count + phase), 24.0);
      float outside = smoothstep(radius + 0.01, radius + 0.055, distanceFromCenter);
      float reach = 1.0 - smoothstep(radius + 0.08, radius + 0.72, distanceFromCenter);
      float haze = exp(-distanceFromCenter * 0.85);
      return beam * outside * reach * haze;
    }

    float rayParity(
      vec2 point,
      vec2 center,
      float count,
      float phase
    ) {
      float angle = atan(point.y - center.y, point.x - center.x);
      float rayIndex = floor((angle * count + phase + 3.14159265) / 6.2831853);
      return mod(rayIndex, 2.0);
    }

    vec3 sphereRayColor(float materialMix, float lighter) {
      vec3 gold = oklch(0.92, 0.11, 84.0);
      vec3 slate = oklch(0.89, 0.055, 252.0);
      vec3 accent = mix(gold, slate, materialMix);
      vec3 whiteTintedAccent = mix(accent, vec3(1.0), 0.58);
      return mix(whiteTintedAccent, accent, lighter);
    }

    void main() {
      vec2 uv = gl_FragCoord.xy / u_resolution.xy;
      float aspect = u_resolution.x / max(u_resolution.y, 1.0);
      vec2 point = vec2(uv.x * aspect, uv.y);
      float time = u_time;
      float paletteVariation = fract(u_palette * 0.61803398875);

      vec2 first = vec2(
        aspect * (0.68 + u_offset.x),
        mix(0.58, 0.73, u_top_aligned) + u_offset.y + sin(time * 0.17) * 0.018
      );
      vec2 second = vec2(
        aspect * (0.58 + u_offset.x),
        mix(0.2, 0.57, u_top_aligned) + u_offset.y + sin(time * 0.11) * 0.014
      );
      float firstGlow = glow(point, first, 0.16);
      float secondGlow = glow(point, second, 0.09);
      float cloud = firstGlow * 0.48 + secondGlow * 0.34;
      cloud += (hash(floor(gl_FragCoord.xy * 0.45)) - 0.5) * 0.028;

      vec3 color = mix(
        oklch(0.965, 0.007, 252.0),
        oklch(0.92, 0.07, 84.0),
        smoothstep(0.12, 0.94, cloud)
      );

      float goldBloom =
        exp(-distance(point, first + vec2(-0.035, 0.045)) * 14.0);
      float slateBloom =
        exp(-distance(point, second + vec2(-0.018, 0.025)) * 22.0);
      vec3 whiteBloom = oklch(0.99, 0.0, 0.0);
      color += whiteBloom * goldBloom * 0.24;
      color += whiteBloom * slateBloom * 0.2;

      float rotationClock = u_rotation_time * 0.1;
      float firstPhase = 0.4 - rotationClock * 19.0;
      float secondPhase = 3.1 + rotationClock * 0.7 * 13.0;
      float firstLines = rays(point, first, 0.16, 19.0, firstPhase);
      float secondLines = rays(point, second, 0.09, 13.0, secondPhase);
      float syncopatedPhase = rotationClock * 12.5;
      float alternatingWave = sin(syncopatedPhase);
      float raySwap = 0.5 + 0.32 * alternatingWave;
      float firstParity = rayParity(point, first, 19.0, firstPhase);
      float secondParity = rayParity(point, second, 13.0, secondPhase);
      vec3 firstLineColor = sphereRayColor(
        0.28,
        mix(raySwap, 1.0 - raySwap, firstParity)
      );
      vec3 secondLineColor = sphereRayColor(
        0.92,
        mix(raySwap, 1.0 - raySwap, secondParity)
      );
      color = mix(
        color,
        firstLineColor,
        min(firstLines * 0.52, 0.6)
      );
      color = mix(
        color,
        secondLineColor,
        min(secondLines * 0.52, 0.6)
      );

      vec4 firstSphere = renderedSphere(
        point,
        first,
        0.16,
        0.28,
        0.4,
        time
      );
      vec4 secondSphere = renderedSphere(
        point,
        second,
        0.09,
        0.92,
        4.2,
        time
      );
      color = mix(color, firstSphere.rgb, firstSphere.a);
      color = mix(color, secondSphere.rgb, secondSphere.a);

      float vignette = 1.0 - smoothstep(0.18, 0.95, distance(uv, vec2(0.5)));
      color *= 0.94 + vignette * 0.06;

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
    const rotationTimeLocation = context.getUniformLocation(
      program,
      "u_rotation_time",
    );
    const paletteLocation = context.getUniformLocation(program, "u_palette");
    const topAlignedLocation = context.getUniformLocation(
      program,
      "u_top_aligned",
    );
    const offsetLocation = context.getUniformLocation(program, "u_offset");
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let frame = 0;
    let start = performance.now();
    let lastFrameTime = start;
    let lastScrollSampleTime = start;
    let lastScrollInputTime = start;
    let lastScrollY = window.scrollY;
    let scrollImpulse = 0;
    let scrollBlend = 0;
    let rotationTime = 0;

    const onScroll = () => {
      const now = performance.now();
      const elapsed = Math.max(now - lastScrollSampleTime, 16);
      const distance = Math.abs(window.scrollY - lastScrollY);
      const velocity = distance / elapsed;
      scrollImpulse = Math.min(velocity / 1.1, 1);
      lastScrollSampleTime = now;
      lastScrollInputTime = now;
      lastScrollY = window.scrollY;
    };

    const onWheel = (event: WheelEvent) => {
      const unit = event.deltaMode === 1
        ? 16
        : event.deltaMode === 2
          ? window.innerHeight
          : 1;
      const nativeMomentum = Math.min(Math.abs(event.deltaY * unit) / 90, 1);
      scrollImpulse = Math.max(nativeMomentum, scrollImpulse * 0.55);
      lastScrollInputTime = performance.now();
    };

    const resize = () => {
      const density = Math.min(window.devicePixelRatio || 1, 2);
      const width = Math.max(1, Math.round(canvas.clientWidth * density));
      const height = Math.max(1, Math.round(canvas.clientHeight * density));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
    };

    const render = (now: number) => {
      resize();
      const time = reducedMotion.matches ? 0 : (now - start) / 1000;
      const deltaTime = Math.min(Math.max((now - lastFrameTime) / 1000, 0), 0.05);
      lastFrameTime = now;
      const isScrolling = now - lastScrollInputTime < 72;
      const scrollTarget = isScrolling ? scrollImpulse : 0;
      const easing = 1.0 - Math.exp(
        -deltaTime * (scrollTarget > scrollBlend ? 12.0 : 8.0),
      );
      scrollBlend += (scrollTarget - scrollBlend) * easing;
      rotationTime += deltaTime * (0.5 + scrollBlend * 6.5);
      context.viewport(0, 0, canvas.width, canvas.height);
      context.useProgram(program);
      context.bindBuffer(context.ARRAY_BUFFER, positionBuffer);
      context.enableVertexAttribArray(positionLocation);
      context.vertexAttribPointer(positionLocation, 2, context.FLOAT, false, 0, 0);
      context.uniform2f(resolutionLocation, canvas.width, canvas.height);
      context.uniform1f(timeLocation, time);
      context.uniform1f(rotationTimeLocation, rotationTime);
      context.uniform1f(paletteLocation, palette);
      context.uniform1f(topAlignedLocation, topAligned ? 1 : 0);
      context.uniform2f(offsetLocation, offsetX, offsetY);
      context.drawArrays(context.TRIANGLES, 0, 6);
      canvas.dataset.rendered = "true";

      if (!reducedMotion.matches) {
        frame = window.requestAnimationFrame(render);
      }
    };

    const restart = () => {
      if (frame) window.cancelAnimationFrame(frame);
      frame = 0;
      start = performance.now();
      lastFrameTime = start;
      frame = window.requestAnimationFrame(render);
    };

    const observer = new ResizeObserver(restart);
    observer.observe(canvas);
    reducedMotion.addEventListener("change", restart);
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("wheel", onWheel, { passive: true });
    frame = window.requestAnimationFrame(render);

    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      observer.disconnect();
      reducedMotion.removeEventListener("change", restart);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("wheel", onWheel);
      context.deleteBuffer(positionBuffer);
      context.deleteProgram(program);
      context.deleteShader(vertexShader);
      context.deleteShader(fragmentShader);
    };
  });
</script>

<canvas
  class="sphereLineShader"
  aria-hidden="true"
  data-palette={palette}
  data-shader="sphere-lines"
  data-top-aligned={topAligned ? "" : undefined}
  style={`--palette-hue: ${paletteHue}`}
  bind:this={canvas}
></canvas>

<style>
  .sphereLineShader {
    width: 100%;
    height: 100%;
    display: block;
    background: oklch(0.8 0.16 var(--palette-hue));
  }
</style>
