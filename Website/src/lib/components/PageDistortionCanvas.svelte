<script lang="ts">
  import { onMount, type Snippet } from "svelte";

  let { children }: { children: Snippet } = $props();
  const layoutSubtreeAttribute = {
    layoutsubtree: "",
  } as Record<string, string>;

  type HTMLCanvasElementWithHTML = HTMLCanvasElement & {
    layoutSubtree: boolean;
    requestPaint: () => void;
    onpaint: ((event: Event) => void) | null;
  };

  type WebGL2WithHTML = WebGL2RenderingContext & {
    texElementImage2D: (
      target: number,
      internalFormat: number,
      element: Element,
      config?: { width?: number; height?: number },
    ) => void;
  };

  let supported = $state(false);
  let canvas = $state<HTMLCanvasElement>();
  let content = $state<HTMLDivElement>();

  const vertexSource = `#version 300 es
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

  const fragmentSource = `#version 300 es
    precision highp float;

    uniform sampler2D uPage;
    uniform float uPageHeight;
    uniform float uViewportHeight;
    uniform float uScrollY;
    uniform float uTime;

    in vec2 vUv;
    out vec4 outputColor;

    vec3 overPaper(vec4 color) {
      return mix(vec3(1.0), color.rgb, color.a);
    }

    void main() {
      float pageY = (1.0 - vUv.y) * uPageHeight;
      float viewportY = pageY - uScrollY;
      float edgeSize = clamp(uViewportHeight * 0.16, 72.0, 156.0);
      float topEdge = 1.0 - smoothstep(0.0, edgeSize, viewportY);
      float bottomEdge = smoothstep(
        uViewportHeight - edgeSize,
        uViewportHeight,
        viewportY
      );

      float topAvailable = smoothstep(0.0, edgeSize, uScrollY);
      float bottomAvailable = smoothstep(
        0.0,
        edgeSize,
        uPageHeight - uViewportHeight - uScrollY
      );
      topEdge *= topAvailable;
      bottomEdge *= bottomAvailable;

      float edge = max(topEdge, bottomEdge);
      float direction = bottomEdge - topEdge;
      float pageWave =
        sin(pageY * 0.052 + uScrollY * 0.021 + uTime * 0.35) * 0.62 +
        sin(pageY * 0.019 - uScrollY * 0.013) * 0.38;
      float taper = edge * edge * (3.0 - 2.0 * edge);

      vec2 sampleUv = vUv;
      sampleUv.x += direction * pageWave * taper * 0.016;
      sampleUv.y += direction * taper * (0.005 + abs(pageWave) * 0.004);

      vec2 chromaticOffset = vec2(direction * taper * 0.0025, 0.0);
      vec3 redSample = overPaper(texture(
        uPage,
        clamp(sampleUv + chromaticOffset, vec2(0.0), vec2(1.0))
      ));
      vec3 greenSample = overPaper(texture(
        uPage,
        clamp(sampleUv, vec2(0.0), vec2(1.0))
      ));
      vec3 blueSample = overPaper(texture(
        uPage,
        clamp(sampleUv - chromaticOffset, vec2(0.0), vec2(1.0))
      ));
      outputColor = vec4(redSample.r, greenSample.g, blueSample.b, 1.0);
    }
  `;

  const compileShader = (
    gl: WebGL2RenderingContext,
    type: number,
    source: string,
  ) => {
    const shader = gl.createShader(type);
    if (!shader) throw new Error("Unable to create page distortion shader.");
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const message = gl.getShaderInfoLog(shader) ?? "Unknown shader error.";
      gl.deleteShader(shader);
      throw new Error(message);
    }
    return shader;
  };

  onMount(() => {
    const probeCanvas = document.createElement("canvas");
    const probe = probeCanvas.getContext("webgl2") as WebGL2WithHTML | null;
    supported =
      typeof probe?.texElementImage2D === "function" &&
      "requestPaint" in probeCanvas;
    if (!supported) return;

    let disposed = false;
    let cleanupRenderer = () => {};

    requestAnimationFrame(() => {
      if (disposed || !canvas || !content) return;
      const canvasElement = canvas;
      const contentElement = content;
      const htmlCanvas = canvasElement as HTMLCanvasElementWithHTML;
      const gl = canvasElement.getContext("webgl2", {
        alpha: false,
        antialias: false,
        powerPreference: "high-performance",
      }) as WebGL2WithHTML | null;
      if (!gl) return;

      const vertexShader = compileShader(gl, gl.VERTEX_SHADER, vertexSource);
      const fragmentShader = compileShader(
        gl,
        gl.FRAGMENT_SHADER,
        fragmentSource,
      );
      const program = gl.createProgram();
      const texture = gl.createTexture();
      if (!program || !texture) return;
      gl.attachShader(program, vertexShader);
      gl.attachShader(program, fragmentShader);
      gl.linkProgram(program);
      gl.deleteShader(vertexShader);
      gl.deleteShader(fragmentShader);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;

      const pageLocation = gl.getUniformLocation(program, "uPage");
      const pageHeightLocation = gl.getUniformLocation(program, "uPageHeight");
      const viewportHeightLocation = gl.getUniformLocation(
        program,
        "uViewportHeight",
      );
      const scrollLocation = gl.getUniformLocation(program, "uScrollY");
      const timeLocation = gl.getUniformLocation(program, "uTime");
      let textureReady = false;
      let renderFrame = 0;
      let pageHeight = Math.max(1, contentElement.scrollHeight);

      gl.useProgram(program);
      gl.uniform1i(pageLocation, 0);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);

      const render = (timestamp = performance.now()) => {
        renderFrame = 0;
        if (!textureReady) return;
        gl.viewport(0, 0, canvasElement.width, canvasElement.height);
        gl.useProgram(program);
        gl.uniform1f(pageHeightLocation, pageHeight);
        gl.uniform1f(viewportHeightLocation, window.innerHeight);
        gl.uniform1f(scrollLocation, window.scrollY);
        gl.uniform1f(timeLocation, timestamp / 1000);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      };

      const scheduleRender = () => {
        if (!renderFrame) renderFrame = requestAnimationFrame(render);
      };

      const resize = () => {
        const cssWidth = Math.max(1, contentElement.offsetWidth);
        pageHeight = Math.max(1, contentElement.scrollHeight);
        const maxTextureSize = gl.getParameter(gl.MAX_TEXTURE_SIZE) as number;
        const density = Math.max(
          1,
          Math.min(
            window.devicePixelRatio || 1,
            1.5,
            maxTextureSize / cssWidth,
            maxTextureSize / pageHeight,
          ),
        );
        canvasElement.style.height = `${pageHeight}px`;
        canvasElement.width = Math.max(1, Math.round(cssWidth * density));
        canvasElement.height = Math.max(1, Math.round(pageHeight * density));
        htmlCanvas.requestPaint();
      };

      htmlCanvas.onpaint = () => {
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texElementImage2D(gl.TEXTURE_2D, gl.RGBA8, contentElement, {
          width: canvasElement.width,
          height: canvasElement.height,
        });
        textureReady = true;
        scheduleRender();
      };

      const resizeObserver = new ResizeObserver(resize);
      resizeObserver.observe(contentElement);
      window.addEventListener("scroll", scheduleRender, { passive: true });
      window.addEventListener("resize", resize);
      resize();

      cleanupRenderer = () => {
        resizeObserver.disconnect();
        window.removeEventListener("scroll", scheduleRender);
        window.removeEventListener("resize", resize);
        if (renderFrame) cancelAnimationFrame(renderFrame);
        htmlCanvas.onpaint = null;
        gl.deleteTexture(texture);
        gl.deleteProgram(program);
      };
    });

    return () => {
      disposed = true;
      cleanupRenderer();
    };
  });
</script>

{#if supported}
  <canvas
    class="pageDistortionCanvas"
    {...layoutSubtreeAttribute}
    bind:this={canvas}
  >
    <div class="pageDistortionContent" bind:this={content}>
      {@render children()}
    </div>
  </canvas>
{:else}
  <div class="pageDistortionFallback">
    {@render children()}
  </div>
{/if}

<style>
  .pageDistortionFallback {
    display: contents;
  }

  .pageDistortionCanvas {
    width: 100%;
    min-height: 100vh;
    display: block;
    background: var(--paper);
  }

  .pageDistortionContent {
    width: 100%;
    min-height: 100vh;
  }
</style>
