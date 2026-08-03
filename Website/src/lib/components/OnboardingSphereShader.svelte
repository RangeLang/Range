<script lang="ts">
  import { onMount } from "svelte";

  let {
    pointerX = 0,
    pointerY = 0,
    concreteness = 0,
    compact = false,
    timeOrigin = 0,
    fisheyeAmount = 1,
    distortionAmount = 1,
    glitterAmount = 1,
    fieldBrightness = 1,
    fullBleed = false,
    emptiness = 0,
    emptinessFeather = 0.045,
    twinkleAmount = 0,
    dissolveAmount = 0,
    fieldOpacity = 1,
    whiteoutAmount = 0,
  }: {
    pointerX?: number;
    pointerY?: number;
    concreteness?: number;
    compact?: boolean;
    timeOrigin?: number;
    fisheyeAmount?: number;
    distortionAmount?: number;
    glitterAmount?: number;
    fieldBrightness?: number;
    fullBleed?: boolean;
    emptiness?: number;
    emptinessFeather?: number;
    twinkleAmount?: number;
    dissolveAmount?: number;
    fieldOpacity?: number;
    whiteoutAmount?: number;
  } = $props();

  let canvas: HTMLCanvasElement;
  let invalidateRender: (() => void) | undefined;

  // A still sky should be a still GPU surface. Prop-driven transitions invalidate
  // one frame; only the deliberately animated twinkle keeps a render loop alive.
  $effect(() => {
    void pointerX;
    void pointerY;
    void concreteness;
    void compact;
    void timeOrigin;
    void fisheyeAmount;
    void distortionAmount;
    void glitterAmount;
    void fieldBrightness;
    void fullBleed;
    void emptiness;
    void emptinessFeather;
    void twinkleAmount;
    void dissolveAmount;
    void fieldOpacity;
    void whiteoutAmount;
    invalidateRender?.();
  });
  const vertexSource = `
    attribute vec2 a_position;

    void main() {
      gl_Position = vec4(a_position, 0.0, 1.0);
    }
  `;

  const fragmentSource = `
    precision highp float;

    uniform vec2 u_resolution;
    uniform vec2 u_viewport_resolution;
    uniform vec2 u_field_origin;
    uniform float u_time;
    uniform float u_concreteness;
    uniform float u_fisheye_amount;
    uniform float u_distortion_amount;
    uniform float u_glitter_amount;
    uniform float u_field_brightness;
    uniform float u_full_bleed;
    uniform float u_emptiness;
    uniform float u_emptiness_feather;
    uniform float u_twinkle_amount;
    uniform float u_dissolve_amount;
    uniform float u_field_opacity;
    uniform float u_whiteout_amount;

    float hash12(vec2 point) {
      vec3 point3 = fract(vec3(point.xyx) * 0.1031);
      point3 += dot(point3, point3.yzx + 33.33);
      return fract((point3.x + point3.y) * point3.z);
    }

    float valueNoise(vec2 point) {
      vec2 cell = floor(point);
      vec2 local = smoothstep(0.0, 1.0, fract(point));
      float lower = mix(hash12(cell), hash12(cell + vec2(1.0, 0.0)), local.x);
      float upper = mix(hash12(cell + vec2(0.0, 1.0)), hash12(cell + 1.0), local.x);
      return mix(lower, upper, local.y);
    }

    float glitter(vec2 point, float scale, float cutoff) {
      vec2 cell = floor(point * scale);
      vec2 local = fract(point * scale) - 0.5;
      vec2 sparkle = vec2(
        hash12(cell + vec2(4.1, 8.7)),
        hash12(cell + vec2(15.3, 2.6))
      ) - 0.5;
      float size = mix(26.0, 58.0, hash12(cell + 21.4));
      float enabled = smoothstep(
        cutoff,
        cutoff + 0.08,
        hash12(cell + vec2(31.2, 17.8))
      );
      return exp(-length(local - sparkle) * size) * enabled;
    }

    void main() {
      vec2 uv = gl_FragCoord.xy / max(u_resolution, vec2(1.0));
      vec2 point = uv * 2.0 - 1.0;
      point.x *= u_resolution.x / max(u_resolution.y, 1.0);
      vec2 fieldUv = (gl_FragCoord.xy + u_field_origin)
        / max(u_viewport_resolution, vec2(1.0));
      vec2 fieldPoint = fieldUv * 2.0 - 1.0;
      fieldPoint.x *= u_viewport_resolution.x / max(u_viewport_resolution.y, 1.0);

      float concreteness = clamp(u_concreteness, 0.0, 1.0);
      float sphereScale = 1.0;
      vec2 spherePoint = point / sphereScale;
      float radialSquared = dot(spherePoint, spherePoint);
      float radialDistance = sqrt(radialSquared);
      // Resolve the circular coverage in this same fragment pass. A small
      // resolution-derived feather is stable while the canvas is resizing and
      // avoids resampling an opaque square through a separate CSS clip.
      float edgeFeather = 5.0 / max(min(u_resolution.x, u_resolution.y), 1.0);
      float sphereAlpha = u_full_bleed > 0.5
        ? 1.0
        : 1.0 - smoothstep(1.0 - edgeFeather, 1.0, radialDistance);

      vec3 background = vec3(0.0);

      if (radialSquared < 1.0 || u_full_bleed > 0.5) {
        float surfaceZ = sqrt(max(0.0, 1.0 - radialSquared));
        // This normal is already unit length, and the light vector is normalized
        // ahead of time. Avoiding two per-pixel normalize calls matters at 70vh.
        vec3 normal = vec3(spherePoint, surfaceZ);
        vec3 lightDirection = vec3(-0.286, 0.350, 0.892);
        float diffuse = max(dot(normal, lightDirection), 0.0);
        float ambient = 0.26 + surfaceZ * 0.34;
        float fisheyeStrength = clamp(
          max(u_fisheye_amount, u_distortion_amount),
          0.0,
          1.5
        );
        float lensCurve = 1.8 + fisheyeStrength * 0.9;
        float lensMix = smoothstep(0.0, 1.5, fisheyeStrength);
        float fisheyeRadius = mix(
          radialDistance,
          atan(radialDistance * lensCurve) / atan(lensCurve),
          lensMix
        );
        vec2 fisheyePoint = radialDistance > 0.0001
          ? spherePoint * (fisheyeRadius / radialDistance)
          : spherePoint;
        // Field coordinates are viewport-anchored, so scale the lens displacement
        // by the sphere's real viewport coverage as it grows.
        float sphereCoverage = max(
          u_resolution.x / max(u_viewport_resolution.x, 1.0),
          u_resolution.y / max(u_viewport_resolution.y, 1.0)
        );
        float fisheyeScale = min(2.0, sphereCoverage);
        vec2 underPoint = fieldPoint
          + (fisheyePoint - spherePoint)
            * (0.45 + clamp(u_distortion_amount, 0.0, 1.0) * 0.35)
            * fisheyeScale;
        float grain = valueNoise(underPoint * 4.5 + vec2(u_time * 0.012));
        float facets = 0.5 + 0.5 * sin(
          underPoint.x * 8.0 + underPoint.y * 6.0 + surfaceZ * 9.0
        );
        float coarseGlitter = glitter(
          underPoint * 1.2 + vec2(u_time * 0.012, -u_time * 0.008),
          14.0,
          mix(0.78, 0.67, concreteness)
        );
        float fineGlitter = glitter(
          underPoint * 2.0 + vec2(-u_time * 0.02, u_time * 0.014),
          28.0,
          mix(0.91, 0.82, concreteness)
        );
        float shimmer = mix(
          1.0,
          0.78 + 0.22 * sin(
            u_time * 0.18 + hash12(floor(underPoint * 28.0)) * 6.2831
          ),
          clamp(u_twinkle_amount, 0.0, 1.0)
        );

        vec3 fieldDeep = vec3(0.024, 0.035, 0.072);
        vec3 fieldLight = vec3(0.036, 0.052, 0.102);
        vec3 fieldAccent = vec3(0.68, 0.8, 1.0);
        vec3 abstractSurface = mix(
          fieldDeep,
          fieldLight,
          0.38 + surfaceZ * 0.08
        );
        abstractSurface += (grain - 0.5) * vec3(0.08, 0.12, 0.22) * 0.025;

        vec3 concreteSurface = mix(
          vec3(0.09, 0.12, 0.17),
          vec3(0.31, 0.36, 0.43),
          ambient * 0.52 + diffuse * 0.48
        );
        concreteSurface += vec3(0.075, 0.095, 0.13) * facets * 0.22;
        concreteSurface += (grain - 0.5) * 0.045;

        vec3 surface = mix(abstractSurface, concreteSurface, concreteness);
        surface *= u_field_brightness;
        vec3 baseSurface = surface;
        float glitterWeight = mix(1.14, 0.76, concreteness);
        vec3 coarseStars = vec3(0.78, 0.88, 1.0)
          * coarseGlitter
          * shimmer
          * glitterWeight
          * u_glitter_amount;
        vec3 fineStars = fieldAccent
          * fineGlitter
          * (0.34 + concreteness * 0.3)
          * u_glitter_amount;
        vec3 darkSkyWithStars = baseSurface + coarseStars + fineStars;
        float starMask = clamp(
          coarseGlitter * shimmer * glitterWeight
            + fineGlitter * (0.34 + concreteness * 0.3),
          0.0,
          1.0
        ) * clamp(u_glitter_amount, 0.0, 1.0);
        // Whiteout follows the field's own luminance. Highlights and stars
        // clear first; each darker band receives proportionally more delay,
        // while the shared smooth ramp still converges to exact white.
        float whiteout = clamp(u_whiteout_amount, 0.0, 1.0);
        float luminance = dot(baseSurface, vec3(0.2126, 0.7152, 0.0722));
        float darknessDelay = clamp(1.0 - luminance, 0.0, 1.0) * 0.38;
        float localWhiteout = smoothstep(
          darknessDelay,
          min(1.0, darknessDelay + 0.62),
          whiteout
        );
        vec3 whiteSkyWithStars = mix(
          vec3(1.0),
          vec3(0.48, 0.67, 0.94),
          starMask * 0.72
        );
        background = mix(darkSkyWithStars, whiteSkyWithStars, localWhiteout);
      }

      float emptinessAlpha = u_emptiness <= 0.0001
        ? 1.0
        : smoothstep(
            max(0.0, clamp(u_emptiness, 0.0, 1.0) - max(u_emptiness_feather, 0.0001)),
            clamp(u_emptiness, 0.0, 1.0),
            length(spherePoint)
          );
      float dissolve = clamp(u_dissolve_amount, 0.0, 1.0);
      float dissolveAlpha = 1.0;
      if (dissolve > 0.0001) {
        dissolveAlpha = (1.0 - dissolve) * (1.0 - smoothstep(
          1.0 - dissolve - 0.12,
          1.0 - dissolve + 0.12,
          valueNoise(fieldPoint * 12.0 + vec2(3.7, 8.1))
        ));
      }
      float alpha = sphereAlpha
        * emptinessAlpha
        * dissolveAlpha
        * clamp(u_field_opacity, 0.0, 1.0);
      gl_FragColor = vec4(background * alpha, alpha);
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
      alpha: true,
      premultipliedAlpha: true,
      antialias: false,
      depth: false,
      stencil: false,
      preserveDrawingBuffer: false,
      desynchronized: true,
      powerPreference: "high-performance",
    });
    if (!context) return;

    const vertexShader = createShader(
      context,
      context.VERTEX_SHADER,
      vertexSource,
    );
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
    const viewportResolutionLocation = context.getUniformLocation(
      program,
      "u_viewport_resolution",
    );
    const fieldOriginLocation = context.getUniformLocation(program, "u_field_origin");
    const timeLocation = context.getUniformLocation(program, "u_time");
    const concretenessLocation = context.getUniformLocation(
      program,
      "u_concreteness",
    );
    const fisheyeLocation = context.getUniformLocation(
      program,
      "u_fisheye_amount",
    );
    const distortionLocation = context.getUniformLocation(
      program,
      "u_distortion_amount",
    );
    const glitterLocation = context.getUniformLocation(
      program,
      "u_glitter_amount",
    );
    const brightnessLocation = context.getUniformLocation(
      program,
      "u_field_brightness",
    );
    const fullBleedLocation = context.getUniformLocation(program, "u_full_bleed");
    const emptinessLocation = context.getUniformLocation(program, "u_emptiness");
    const emptinessFeatherLocation = context.getUniformLocation(
      program,
      "u_emptiness_feather",
    );
    const twinkleLocation = context.getUniformLocation(program, "u_twinkle_amount");
    const dissolveLocation = context.getUniformLocation(program, "u_dissolve_amount");
    const fieldOpacityLocation = context.getUniformLocation(program, "u_field_opacity");
    const whiteoutLocation = context.getUniformLocation(program, "u_whiteout_amount");
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let frame = 0;
    let visible = true;
    const startedAt = timeOrigin || performance.now();
    let density = 1;
    let viewportWidth = 1;
    let viewportHeight = 1;
    let fieldOriginX = 0;
    let fieldOriginY = 0;
    let layoutDirty = true;

    const measure = () => {
      // One physical sample per CSS pixel cuts Retina fill-rate by up to 75%.
      density = 1;
      const width = Math.max(1, Math.round(canvas.clientWidth * density));
      const height = Math.max(1, Math.round(canvas.clientHeight * density));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
      viewportWidth = (window.visualViewport?.width ?? window.innerWidth) * density;
      viewportHeight = (window.visualViewport?.height ?? window.innerHeight) * density;
      const canvasBounds = canvas.getBoundingClientRect();
      fieldOriginX = canvasBounds.left * density;
      fieldOriginY = viewportHeight - canvasBounds.bottom * density;
      layoutDirty = false;
    };

    const draw = (now: number) => {
      if (layoutDirty) measure();
      const time = reducedMotion.matches ? 0 : (now - startedAt) / 1000;
      context.viewport(0, 0, canvas.width, canvas.height);
      context.useProgram(program);
      context.bindBuffer(context.ARRAY_BUFFER, positionBuffer);
      context.enableVertexAttribArray(positionLocation);
      context.vertexAttribPointer(positionLocation, 2, context.FLOAT, false, 0, 0);
      context.uniform2f(resolutionLocation, canvas.width, canvas.height);
      context.uniform2f(viewportResolutionLocation, viewportWidth, viewportHeight);
      context.uniform2f(fieldOriginLocation, fieldOriginX, fieldOriginY);
      context.uniform1f(timeLocation, time);
      context.uniform1f(concretenessLocation, concreteness);
      context.uniform1f(fisheyeLocation, fisheyeAmount);
      context.uniform1f(distortionLocation, distortionAmount);
      context.uniform1f(glitterLocation, glitterAmount);
      context.uniform1f(brightnessLocation, fieldBrightness);
      context.uniform1f(fullBleedLocation, fullBleed ? 1 : 0);
      context.uniform1f(emptinessLocation, emptiness);
      context.uniform1f(emptinessFeatherLocation, emptinessFeather);
      context.uniform1f(twinkleLocation, twinkleAmount);
      context.uniform1f(dissolveLocation, dissolveAmount);
      context.uniform1f(fieldOpacityLocation, fieldOpacity);
      context.uniform1f(whiteoutLocation, whiteoutAmount);
      context.drawArrays(context.TRIANGLES, 0, 6);
      canvas.dataset.rendered = "true";
      canvas.parentElement?.setAttribute("data-shader-rendered", "true");
    };

    const render = (now: number) => {
      frame = 0;
      if (!visible || document.hidden) return;
      draw(now);
      if (!reducedMotion.matches && twinkleAmount > 0.0001) {
        frame = requestAnimationFrame(render);
      }
    };

    const schedule = (requiresMeasure = false) => {
      if (requiresMeasure) layoutDirty = true;
      // One pending animation frame is the complete render queue for this canvas.
      if (frame) return;
      if (visible && !document.hidden) frame = requestAnimationFrame(render);
    };
    invalidateRender = () => schedule();

    const resizeObserver = new ResizeObserver(() => schedule(true));
    const visibilityObserver = new IntersectionObserver(
      ([entry]) => {
        visible = entry?.isIntersecting ?? false;
        schedule(true);
      },
      { rootMargin: "120px" },
    );
    const handleReducedMotion = () => schedule();
    const handleVisibility = () => schedule(true);
    const handleViewport = () => schedule(true);
    resizeObserver.observe(canvas);
    visibilityObserver.observe(canvas);
    reducedMotion.addEventListener("change", handleReducedMotion);
    document.addEventListener("visibilitychange", handleVisibility);
    window.visualViewport?.addEventListener("resize", handleViewport);
    window.visualViewport?.addEventListener("scroll", handleViewport);
    schedule(true);

    return () => {
      if (frame) cancelAnimationFrame(frame);
      resizeObserver.disconnect();
      visibilityObserver.disconnect();
      invalidateRender = undefined;
      reducedMotion.removeEventListener("change", handleReducedMotion);
      document.removeEventListener("visibilitychange", handleVisibility);
      window.visualViewport?.removeEventListener("resize", handleViewport);
      window.visualViewport?.removeEventListener("scroll", handleViewport);
      context.deleteBuffer(positionBuffer);
      context.deleteProgram(program);
      context.deleteShader(vertexShader);
      context.deleteShader(fragmentShader);
    };
  });
</script>

<canvas
  class="onboardingSphereShader"
  class:compact
  aria-hidden="true"
  data-shader="onboarding-sphere"
  data-concreteness={concreteness.toFixed(2)}
  bind:this={canvas}
></canvas>

<style>
  .onboardingSphereShader {
    display: block;
    width: 100%;
    height: 100%;
    background: transparent;
  }
</style>
