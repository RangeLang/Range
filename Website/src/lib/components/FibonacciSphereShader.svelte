<script lang="ts">
  import { onMount } from "svelte";

  let {
    showSphere = true,
    chalky = false,
    sphereScale = 1,
    starScale = 1,
    skySpheres = false,
    fadeToPaper = true,
    vivid = false,
  }: {
    showSphere?: boolean;
    chalky?: boolean;
    sphereScale?: number;
    starScale?: number;
    skySpheres?: boolean;
    fadeToPaper?: boolean;
    vivid?: boolean;
  } = $props();
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
    uniform float u_show_sphere;
    uniform float u_chalky;
    uniform float u_sphere_scale;
    uniform float u_star_scale;
    uniform float u_sky_spheres;
    uniform float u_fade_to_paper;
    uniform float u_vivid;

    float hash12(vec2 point) {
      vec3 point3 = fract(vec3(point.xyx) * 0.1031);
      point3 += dot(point3, point3.yzx + 33.33);
      return fract((point3.x + point3.y) * point3.z);
    }

    vec2 hash22(vec2 point) {
      float value = hash12(point);
      return fract(vec2(value, value * 1.61803398875 + 0.173));
    }

    float starField(vec2 pixel) {
      vec2 cell = floor(pixel / 34.0);
      vec2 local = fract(pixel / 34.0) - 0.5;
      vec2 starPosition = hash22(cell) - 0.5;
      float brightness = step(0.91, hash12(cell + 13.7));
      float twinkle = 0.72 + hash12(cell + 8.4) * 0.28;
      float star = exp(-length(local - starPosition) * 72.0 / u_star_scale);
      return star * brightness * twinkle;
    }

    vec3 positionedSkySpheres(vec2 pixel) {
      vec3 result = vec3(0.0);

      for (int offsetY = -1; offsetY <= 1; offsetY += 1) {
        for (int offsetX = -1; offsetX <= 1; offsetX += 1) {
          vec2 cell = floor(pixel / 34.0)
            + vec2(float(offsetX), float(offsetY));
          float brightness = step(0.91, hash12(cell + 13.7));
          if (brightness > 0.5) {
            vec2 sphereCenter = (cell + hash22(cell)) * 34.0;
            float radius = 1.8 + u_star_scale * 0.6;
            vec2 spherePoint = (pixel - sphereCenter) / radius;
            float radialSquared = dot(spherePoint, spherePoint);
            if (radialSquared < 1.0) {
              float surfaceZ = sqrt(max(0.0, 1.0 - radialSquared));
              vec3 normal = normalize(vec3(spherePoint, surfaceZ));
              vec3 lightDirection = normalize(vec3(-0.55, 0.72, 0.92));
              float diffuse = max(dot(normal, lightDirection), 0.0);
              float rim = pow(1.0 - surfaceZ, 1.8);
              vec3 sphere = mix(
                vec3(0.42, 0.44, 0.48),
                vec3(1.0),
                0.42 + diffuse * 0.58
              );
              sphere += vec3(0.12) * rim;
              float mask = 1.0 - smoothstep(0.94, 1.0, radialSquared);
              result = mix(result, sphere, mask);
            }
          }
        }
      }

      return result;
    }

    void main() {
      vec2 uv = gl_FragCoord.xy / u_resolution.xy;
      vec2 point = uv * 2.0 - 1.0;
      point.x *= u_resolution.x / max(u_resolution.y, 1.0);

      float time = u_time;
      vec2 sphereCenter = vec2(
        0.34 + sin(time * 0.19) * 0.055,
        0.04 + cos(time * 0.16) * 0.045
      );
      float radius = 0.49 * u_sphere_scale;
      vec2 spherePoint = (point - sphereCenter) / radius;
      float radialSquared = dot(spherePoint, spherePoint);

      vec3 vividSpace = mix(
        vec3(0.004, 0.007, 0.014),
        vec3(0.018, 0.021, 0.027),
        smoothstep(0.08, 0.92, uv.x)
      );
      vec3 darkSpace = mix(
        vec3(0.018, 0.022, 0.033),
        vividSpace,
        u_vivid
      );
      float chalkGrain = hash12(gl_FragCoord.xy * 0.42 + floor(time * 2.0));
      float haze = u_show_sphere > 0.5
        ? exp(-length(point - sphereCenter) * 1.4)
        : 0.0;
      darkSpace += vec3(0.018, 0.026, 0.05) * haze;
      vec3 scene = darkSpace;
      if (u_sky_spheres > 0.5) {
        scene += positionedSkySpheres(gl_FragCoord.xy);
      } else {
        float stars = starField(gl_FragCoord.xy);
        vec3 starColor = mix(
          vec3(1.0),
          vec3(1.0, 0.72, 0.28),
          u_vivid * (0.35 + hash12(floor(gl_FragCoord.xy / 34.0)) * 0.4)
        );
        scene += starColor * stars;
      }
      if (u_show_sphere > 0.5 && radialSquared < 1.0) {
        float surfaceZ = sqrt(max(0.0, 1.0 - radialSquared));
        vec3 normal = normalize(vec3(spherePoint, surfaceZ));
        vec3 lightDirection = normalize(vec3(-0.62, 0.76, 0.95));
        float diffuse = max(dot(normal, lightDirection), 0.0);
        float fresnel = pow(1.0 - surfaceZ, 2.15);
        float innerShadow = smoothstep(0.12, 0.96, fresnel);
        float softCore = pow(max(surfaceZ, 0.0), 0.72);

        vec3 darkSphere = mix(
          vec3(0.035, 0.055, 0.095),
          vec3(0.13, 0.22, 0.36),
          softCore * (0.52 + diffuse * 0.48)
        );
        darkSphere *= 1.0 - innerShadow * 0.58;
        darkSphere += vec3(0.035, 0.045, 0.07)
          * (1.0 - innerShadow)
          * diffuse
          * 0.32;
        vec3 chalkSphere = mix(
          vec3(0.78, 0.8, 0.84),
          vec3(1.0, 1.0, 1.0),
          softCore * (0.52 + diffuse * 0.48)
        );
        chalkSphere += (chalkGrain - 0.5) * 0.08;
        vec3 sphere = mix(darkSphere, chalkSphere, u_chalky);

        float sphereMask = 1.0 - smoothstep(0.99, 1.0, radialSquared);
        scene = mix(scene, sphere, sphereMask);
      }

      float halo = exp(-abs(length(spherePoint) - 1.0) * 32.0);
      scene += vec3(0.035, 0.05, 0.085) * halo * 0.11 * u_show_sphere;

      vec2 fieldPoint = vec2(
        (1.0 - uv.x) / 1.16,
        (1.0 - uv.y) / 1.4
      );
      float darkField = 1.0 - smoothstep(0.18, 0.92, length(fieldPoint));
      vec3 paperFade = mix(vec3(1.0), scene, darkField);
      vec3 color = mix(scene, paperFade, u_fade_to_paper);

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
    if (vivid) {
      try {
        context.drawingBufferColorSpace = "display-p3";
      } catch {
        // Older browsers retain their default sRGB drawing buffer.
      }
    }

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
    const showSphereLocation = context.getUniformLocation(program, "u_show_sphere");
    const chalkyLocation = context.getUniformLocation(program, "u_chalky");
    const sphereScaleLocation = context.getUniformLocation(program, "u_sphere_scale");
    const starScaleLocation = context.getUniformLocation(program, "u_star_scale");
    const skySpheresLocation = context.getUniformLocation(program, "u_sky_spheres");
    const fadeToPaperLocation = context.getUniformLocation(
      program,
      "u_fade_to_paper",
    );
    const vividLocation = context.getUniformLocation(program, "u_vivid");
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
      context.uniform1f(showSphereLocation, showSphere ? 1 : 0);
      context.uniform1f(chalkyLocation, chalky ? 1 : 0);
      context.uniform1f(sphereScaleLocation, sphereScale);
      context.uniform1f(starScaleLocation, starScale);
      context.uniform1f(skySpheresLocation, skySpheres ? 1 : 0);
      context.uniform1f(fadeToPaperLocation, fadeToPaper ? 1 : 0);
      context.uniform1f(vividLocation, vivid ? 1 : 0);
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
  class="fibonacciSphereShader"
  aria-hidden="true"
  data-shader="fibonacci-sphere"
  bind:this={canvas}
></canvas>

<style>
  .fibonacciSphereShader {
    display: block;
    width: 100%;
    height: 100%;
    background: oklch(0.16 0.025 255);
  }
</style>
