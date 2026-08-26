<script lang="ts">
  import { onMount } from "svelte";

  let canvas: HTMLCanvasElement;
  let stage: HTMLElement;
  let webglAvailable = $state(true);

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
      uniform vec2 u_pointer;
      uniform float u_time;

      const float PI = 3.14159265359;

      vec2 tunnelPath(float depth) {
        return vec2(
          sin(depth * 0.21) * 0.34 + sin(depth * 0.071 + 1.7) * 0.22,
          cos(depth * 0.17 + 0.8) * 0.28 + sin(depth * 0.093) * 0.18
        );
      }

      float hash(vec3 point) {
        point = fract(point * 0.1031);
        point += dot(point, point.yzx + 33.33);
        return fract((point.x + point.y) * point.z);
      }

      vec3 wavelength(float value) {
        vec3 nearColor = vec3(0.12, 0.72, 1.0);
        vec3 middleColor = vec3(0.48, 0.18, 1.0);
        vec3 farColor = vec3(1.0, 0.12, 0.54);
        return value < 0.5
          ? mix(nearColor, middleColor, value * 2.0)
          : mix(middleColor, farColor, (value - 0.5) * 2.0);
      }

      void main() {
        vec2 resolution = max(u_resolution, vec2(1.0));
        vec2 uv = (gl_FragCoord.xy * 2.0 - resolution) / resolution.y;

        float travel = u_time * 1.08;
        vec2 cameraCenter = tunnelPath(travel);
        vec2 pathAhead = tunnelPath(travel + 0.45) - cameraCenter;
        vec3 forward = normalize(vec3(
          pathAhead + vec2(u_pointer.x, -u_pointer.y) * 0.34,
          0.45
        ));
        vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
        vec3 up = normalize(cross(forward, right));
        vec3 rayOrigin = vec3(cameraCenter, travel);
        vec3 rayDirection = normalize(
          forward * 1.28 + right * uv.x + up * uv.y
        );

        vec3 color = vec3(0.0);
        float transmission = 1.0;
        float distanceAlongRay = 0.08;

        for (int stepIndex = 0; stepIndex < 64; stepIndex += 1) {
          vec3 point = rayOrigin + rayDirection * distanceAlongRay;
          vec2 relative = point.xy - tunnelPath(point.z);
          float angle = atan(relative.y, relative.x);
          float radius = length(relative);
          float tunnelRadius = 1.18
            + sin(point.z * 0.31) * 0.065
            + sin(point.z * 0.087 + 2.0) * 0.04;
          float wallDistance = abs(radius - tunnelRadius);

          float wallVolume = exp(-wallDistance * 24.0);
          float depthBand = pow(
            0.5 + 0.5 * cos(point.z * 5.6 + sin(angle * 3.0) * 0.55),
            9.0
          );
          float spiral = pow(
            0.5 + 0.5 * cos(angle * 9.0 - point.z * 2.15),
            18.0
          );
          float interference = 0.18 + depthBand * 0.68 + spiral * 0.34;
          float grain = hash(floor(point * vec3(38.0, 38.0, 8.0)));
          float particles = smoothstep(0.988, 1.0, grain)
            * exp(-wallDistance * 7.0);
          float density = wallVolume * interference * 0.72 + particles * 0.82;

          float spectralPhase = fract(
            point.z * 0.047 + angle / (PI * 2.0) + u_time * 0.025
          );
          vec3 emission = wavelength(spectralPhase);
          emission = mix(emission, vec3(0.7, 0.94, 1.0), depthBand * 0.36);
          emission *= density * (1.35 + particles * 2.8);

          float stepLength = 0.145 + distanceAlongRay * 0.0025;
          color += transmission * emission * stepLength;
          transmission *= exp(-density * stepLength * 0.82);
          if (transmission < 0.012) break;
          distanceAlongRay += stepLength;
        }

        float centerDepth = exp(-dot(uv, uv) * 0.6);
        color += wavelength(fract(u_time * 0.018)) * centerDepth * 0.012;
        color = color / (1.0 + color * 0.72);
        color = pow(max(color, vec3(0.0)), vec3(0.72));

        float vignette = 1.0 - smoothstep(0.72, 1.52, length(uv));
        color *= 0.18 + vignette * 0.82;
        gl_FragColor = vec4(color, 1.0);
      }
    `;

    function compile(type: number, source: string) {
      const shader = gl.createShader(type);
      if (!shader) throw new Error("Unable to create tunnel shader.");
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        throw new Error(gl.getShaderInfoLog(shader) ?? "Shader compilation failed.");
      }
      return shader;
    }

    let program: WebGLProgram;
    try {
      const vertex = compile(gl.VERTEX_SHADER, vertexSource);
      const fragment = compile(gl.FRAGMENT_SHADER, fragmentSource);
      const createdProgram = gl.createProgram();
      if (!createdProgram) throw new Error("Unable to create tunnel program.");
      gl.attachShader(createdProgram, vertex);
      gl.attachShader(createdProgram, fragment);
      gl.linkProgram(createdProgram);
      if (!gl.getProgramParameter(createdProgram, gl.LINK_STATUS)) {
        throw new Error(gl.getProgramInfoLog(createdProgram) ?? "Shader link failed.");
      }
      program = createdProgram;
      gl.deleteShader(vertex);
      gl.deleteShader(fragment);
    } catch (error) {
      console.error(error);
      webglAvailable = false;
      return;
    }

    const position = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, position);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
      gl.STATIC_DRAW,
    );

    const positionLocation = gl.getAttribLocation(program, "a_position");
    const resolutionLocation = gl.getUniformLocation(program, "u_resolution");
    const pointerLocation = gl.getUniformLocation(program, "u_pointer");
    const timeLocation = gl.getUniformLocation(program, "u_time");
    const startedAt = performance.now();
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let pointerTargetX = 0;
    let pointerTargetY = 0;
    let pointerX = 0;
    let pointerY = 0;
    let frame: number | undefined;
    let lastRenderedAt = 0;

    function render(now: number) {
      frame = undefined;
      if (document.hidden) {
        frame = requestAnimationFrame(render);
        return;
      }

      pointerX += (pointerTargetX - pointerX) * 0.085;
      pointerY += (pointerTargetY - pointerY) * 0.085;
      const density = Math.min(window.devicePixelRatio || 1, 1.25);
      const width = Math.max(1, Math.round(canvas.clientWidth * density));
      const height = Math.max(1, Math.round(canvas.clientHeight * density));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }

      if (now - lastRenderedAt >= 1_000 / 45) {
        lastRenderedAt = now;
        gl.viewport(0, 0, width, height);
        gl.useProgram(program);
        gl.enableVertexAttribArray(positionLocation);
        gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);
        gl.uniform2f(resolutionLocation, width, height);
        gl.uniform2f(pointerLocation, pointerX, pointerY);
        gl.uniform1f(timeLocation, reducedMotion ? 0 : (now - startedAt) / 1_000);
        gl.drawArrays(gl.TRIANGLES, 0, 6);
      }
      frame = requestAnimationFrame(render);
    }

    function handlePointer(event: PointerEvent) {
      const bounds = stage.getBoundingClientRect();
      pointerTargetX = Math.max(
        -1,
        Math.min(1, ((event.clientX - bounds.left) / bounds.width) * 2 - 1),
      );
      pointerTargetY = Math.max(
        -1,
        Math.min(1, ((event.clientY - bounds.top) / bounds.height) * 2 - 1),
      );
    }

    function centerPointer() {
      pointerTargetX = 0;
      pointerTargetY = 0;
    }

    stage.addEventListener("pointermove", handlePointer);
    stage.addEventListener("pointerleave", centerPointer);
    frame = requestAnimationFrame(render);

    return () => {
      stage.removeEventListener("pointermove", handlePointer);
      stage.removeEventListener("pointerleave", centerPointer);
      if (frame !== undefined) cancelAnimationFrame(frame);
      gl.deleteBuffer(position);
      gl.deleteProgram(program);
    };
  });
</script>

<svelte:head>
  <title>Volumetric tunnel — Range preview</title>
  <meta name="robots" content="noindex, nofollow" />
</svelte:head>

<main
  class="tunnelStage"
  bind:this={stage}
  aria-label="Pointer-steered volumetric tunnel"
>
  <canvas bind:this={canvas} aria-hidden="true"></canvas>

  {#if !webglAvailable}
    <p>This study needs WebGL.</p>
  {/if}
</main>

<style>
  :global(body) {
    overflow: hidden;
    background: oklch(2% 0.012 255);
  }

  .tunnelStage {
    position: relative;
    width: 100%;
    height: 100svh;
    overflow: hidden;
    overscroll-behavior: none;
    background: oklch(2% 0.012 255);
  }

  canvas {
    display: block;
    width: 100%;
    height: 100%;
  }

  p {
    position: absolute;
    inset: 50% auto auto 50%;
    margin: 0;
    color: oklch(94% 0.02 240);
    transform: translate(-50%, -50%);
  }
</style>
