<script lang="ts">
  import { onMount } from "svelte";

  let { compact = false }: { compact?: boolean } = $props();

  let canvas: HTMLCanvasElement;

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
    uniform float u_compact;

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

    float distanceToSegment(vec2 point, vec2 start, vec2 end) {
      vec2 segment = end - start;
      float progress = clamp(
        dot(point - start, segment) / max(dot(segment, segment), 0.00001),
        0.0,
        1.0
      );
      return distance(point, start + segment * progress);
    }

    float dotMask(vec2 point, vec2 center, float radius) {
      return 1.0 - smoothstep(radius - 0.004, radius + 0.004, distance(point, center));
    }

    float dotGlow(vec2 point, vec2 center, float radius) {
      return exp(-max(distance(point, center) - radius, 0.0) * 18.0);
    }

    void main() {
      vec2 uv = gl_FragCoord.xy / u_resolution.xy;
      float aspect = u_resolution.x / max(u_resolution.y, 1.0);
      vec2 point = vec2(uv.x * aspect, uv.y);
      float time = u_time;
      float originPosition = mix(0.4, 0.42, u_compact);
      float rolePosition = mix(0.54, 0.5, u_compact);
      float destinationPosition = mix(0.68, 0.6, u_compact);

      vec2 origin = vec2(
        aspect * originPosition,
        0.68 + sin(time * 0.22) * 0.018
      );
      vec2 role = vec2(
        aspect * rolePosition,
        0.48 + cos(time * 0.18) * 0.015
      );
      vec2 destination = vec2(
        aspect * destinationPosition,
        0.66 + sin(time * 0.16 + 1.7) * 0.02
      );

      float firstRelationship = 1.0 - smoothstep(
        0.004,
        0.012,
        distanceToSegment(point, origin, role)
      );
      float secondRelationship = 1.0 - smoothstep(
        0.004,
        0.012,
        distanceToSegment(point, role, destination)
      );
      float relationship = max(firstRelationship, secondRelationship);
      float relationshipPhase = 0.76 + 0.24 * sin(
        point.x * 34.0 + point.y * 21.0 - time * 0.7
      );

      float originDot = dotMask(point, origin, 0.052);
      float roleDot = dotMask(point, role, 0.044);
      float destinationDot = dotMask(point, destination, 0.052);

      float originGlow = dotGlow(point, origin, 0.052);
      float roleGlow = dotGlow(point, role, 0.044);
      float destinationGlow = dotGlow(point, destination, 0.052);

      vec3 paper = oklch(0.985, 0.008, 274.0);
      vec3 atmosphere = oklch(0.91, 0.075, 284.0);
      float field = smoothstep(0.96, 0.04, distance(uv, vec2(0.72, 0.56)));
      vec3 color = mix(paper, atmosphere, field * 0.34);

      vec3 relationshipColor = oklch(0.62, 0.18, 286.0);
      color = mix(
        color,
        relationshipColor,
        relationship * relationshipPhase * 0.76
      );

      vec3 originColor = oklch(0.69, 0.22, 22.0);
      vec3 roleColor = oklch(0.66, 0.23, 292.0);
      vec3 destinationColor = oklch(0.73, 0.18, 207.0);
      color += originColor * originGlow * 0.11;
      color += roleColor * roleGlow * 0.12;
      color += destinationColor * destinationGlow * 0.11;
      color = mix(color, originColor, originDot);
      color = mix(color, roleColor, roleDot);
      color = mix(color, destinationColor, destinationDot);

      float originHighlight = dotMask(
        point,
        origin + vec2(-0.016, 0.018),
        0.009
      );
      float roleHighlight = dotMask(
        point,
        role + vec2(-0.013, 0.015),
        0.007
      );
      float destinationHighlight = dotMask(
        point,
        destination + vec2(-0.016, 0.018),
        0.009
      );
      vec3 highlight = oklch(0.985, 0.025, 90.0);
      color = mix(color, highlight, originHighlight * 0.84);
      color = mix(color, highlight, roleHighlight * 0.84);
      color = mix(color, highlight, destinationHighlight * 0.84);

      float vignette = 1.0 - smoothstep(0.18, 0.96, distance(uv, vec2(0.5)));
      color *= 0.965 + vignette * 0.035;

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
    const compactLocation = context.getUniformLocation(program, "u_compact");
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let frame = 0;
    let visible = true;
    let lastFrame = -Infinity;
    const startedAt = performance.now();

    const resize = () => {
      const density = Math.min(window.devicePixelRatio || 1, 1.25);
      const width = Math.max(1, Math.round(canvas.clientWidth * density));
      const height = Math.max(1, Math.round(canvas.clientHeight * density));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
    };

    const draw = (now: number) => {
      resize();
      const time = reducedMotion.matches ? 0 : (now - startedAt) / 1000;
      context.viewport(0, 0, canvas.width, canvas.height);
      context.useProgram(program);
      context.bindBuffer(context.ARRAY_BUFFER, positionBuffer);
      context.enableVertexAttribArray(positionLocation);
      context.vertexAttribPointer(positionLocation, 2, context.FLOAT, false, 0, 0);
      context.uniform2f(resolutionLocation, canvas.width, canvas.height);
      context.uniform1f(timeLocation, time);
      context.uniform1f(compactLocation, compact ? 1 : 0);
      context.drawArrays(context.TRIANGLES, 0, 6);
      canvas.dataset.rendered = "true";
    };

    const render = (now: number) => {
      frame = 0;
      if (!visible || document.hidden) return;
      if (lastFrame === -Infinity || now - lastFrame >= 1000 / 30) {
        draw(now);
        lastFrame = now;
      }
      if (!reducedMotion.matches) frame = requestAnimationFrame(render);
    };

    const schedule = () => {
      if (frame) cancelAnimationFrame(frame);
      frame = 0;
      lastFrame = -Infinity;
      if (visible && !document.hidden) frame = requestAnimationFrame(render);
    };

    const resizeObserver = new ResizeObserver(schedule);
    const visibilityObserver = new IntersectionObserver(
      ([entry]) => {
        visible = entry?.isIntersecting ?? false;
        schedule();
      },
      { rootMargin: "120px" },
    );
    resizeObserver.observe(canvas);
    visibilityObserver.observe(canvas);
    reducedMotion.addEventListener("change", schedule);
    document.addEventListener("visibilitychange", schedule);
    schedule();

    return () => {
      if (frame) cancelAnimationFrame(frame);
      resizeObserver.disconnect();
      visibilityObserver.disconnect();
      reducedMotion.removeEventListener("change", schedule);
      document.removeEventListener("visibilitychange", schedule);
      context.deleteBuffer(positionBuffer);
      context.deleteProgram(program);
      context.deleteShader(vertexShader);
      context.deleteShader(fragmentShader);
    };
  });
</script>

<canvas
  class="relationshipDotsShader"
  aria-hidden="true"
  data-shader="relationship-dots"
  data-dot-count="3"
  data-compact={compact ? "" : undefined}
  bind:this={canvas}
></canvas>

<style>
  .relationshipDotsShader {
    display: block;
    width: 100%;
    height: 100%;
    background: oklch(0.96 0.04 284);
  }
</style>
