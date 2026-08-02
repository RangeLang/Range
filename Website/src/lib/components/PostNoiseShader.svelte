<script lang="ts">
  import { getContext, onMount } from "svelte";
  import {
    RANGE_LAYOUT_TRACKER_CONTEXT,
    type RangeLayoutTracker,
  } from "$lib/layout/layout-tracker";
  import {
    measurePostContrast,
    type PostContrastPalette,
  } from "$lib/post-contrast";

  const layoutTracker = getContext<RangeLayoutTracker | undefined>(
    RANGE_LAYOUT_TRACKER_CONTEXT,
  );

  let {
    palette = 0,
    palettes = [],
    still = false,
    active = true,
    maxFps = 60,
    densityLimit = 2,
    measure = true,
    shared = false,
    oncontrast,
  }: {
    palette?: number;
    palettes?: number[];
    still?: boolean;
    active?: boolean;
    maxFps?: number;
    densityLimit?: number;
    measure?: boolean;
    shared?: boolean;
    oncontrast?: (palette: PostContrastPalette) => void;
  } = $props();

  let canvas: HTMLCanvasElement;
  let requestRender = $state<() => void>(() => {});
  let paletteHue = $derived((22 + palette * 137.507764) % 360);

  $effect(() => {
    palette;
    active;
    still;
    requestRender();
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
    uniform vec2 u_origin;
    uniform float u_time;
    uniform float u_palette;
    uniform float u_shared;
    uniform float u_card_count;
    uniform vec4 u_card_rects[8];
    uniform float u_card_palettes[8];

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
      vec2 localOrigin = u_origin;
      vec2 localResolution = u_resolution;
      float localPalette = u_palette;

      if (u_shared > 0.5) {
        bool insideCard = false;
        for (int cardIndex = 0; cardIndex < 8; cardIndex += 1) {
          if (float(cardIndex) < u_card_count) {
            vec4 cardRect = u_card_rects[cardIndex];
            bool inside =
              gl_FragCoord.x >= cardRect.x
              && gl_FragCoord.x <= cardRect.x + cardRect.z
              && gl_FragCoord.y >= cardRect.y
              && gl_FragCoord.y <= cardRect.y + cardRect.w;
            if (inside) {
              localOrigin = cardRect.xy;
              localResolution = cardRect.zw;
              localPalette = u_card_palettes[cardIndex];
              insideCard = true;
            }
          }
        }
        if (!insideCard) discard;
      }

      vec2 fragmentPoint = gl_FragCoord.xy - localOrigin;
      float cardEdgeAlpha = 1.0;
      if (u_shared > 0.5) {
        float edgeDistance = min(
          min(fragmentPoint.x, localResolution.x - fragmentPoint.x),
          min(fragmentPoint.y, localResolution.y - fragmentPoint.y)
        );
        cardEdgeAlpha = smoothstep(0.0, 1.0, edgeDistance);
      }

      vec2 cardUv = fragmentPoint / localResolution.xy;
      // Keep every procedural layer on one strip-wide coordinate plane.
      // A non-shared shader retains its original card-local coordinates.
      vec2 surfacePoint =
        u_shared > 0.5
          ? gl_FragCoord.xy
          : fragmentPoint;
      vec2 field =
        surfacePoint / max(localResolution.y, 1.0);
      float time = u_time;

      float cloudScale = 0.72;
      vec2 flowDirection = vec2(0.0406, 0.0322);
      vec2 animationOrigin = vec2(7.4, 12.6);
      vec2 largeFlow = flowDirection * time;
      vec2 cloudField =
        field * cloudScale + animationOrigin;
      float warpStrength = 0.98;
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
        cloudField * 1.29
          - largeFlow * 0.5
          + vec2(hills * 1.3, -hills * 0.8)
      );
      float fineClouds = fbm(
        cloudField * 2.78
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

      float baseHue = 22.0 + localPalette * 137.507764;
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

      float edgeShade =
        1.0
        - smoothstep(0.15, 0.82, distance(cardUv, vec2(0.5)));
      color *= 0.94 + edgeShade * 0.06;

      // Preserve the original two-device-pixel grain size while letting a
      // grain fleck continue naturally through neighboring card cutouts.
      vec2 grainCell = floor(surfacePoint * 0.5);
      float grainFrame = floor(time * 8.0);
      vec3 grain = vec3(
        hash(grainCell + grainFrame * 17.0),
        hash(grainCell.yx + grainFrame * 29.0),
        hash(grainCell + vec2(41.0, 73.0) + grainFrame * 11.0)
      );
      vec3 paletteGrain = mix(color, color.gbr, grain);
      color = mix(color, paletteGrain, 0.055);
      color += (grain - 0.5) * (0.008 + color * 0.008);

      gl_FragColor = vec4(color, cardEdgeAlpha);
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
      alpha: shared,
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
    const originLocation = context.getUniformLocation(program, "u_origin");
    const timeLocation = context.getUniformLocation(program, "u_time");
    const paletteLocation = context.getUniformLocation(program, "u_palette");
    const sharedLocation = context.getUniformLocation(program, "u_shared");
    const cardCountLocation = context.getUniformLocation(
      program,
      "u_card_count",
    );
    const cardRectsLocation = context.getUniformLocation(
      program,
      "u_card_rects[0]",
    );
    const cardPalettesLocation = context.getUniformLocation(
      program,
      "u_card_palettes[0]",
    );
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sampleFramebuffer = measure ? context.createFramebuffer() : null;
    const sampleTexture = measure ? context.createTexture() : null;
    let frame = 0;
    let start = performance.now();
    let lastDraw = -Infinity;
    let lastMeasurement = -Infinity;
    let sampleWidth = 0;
    let sampleHeight = 0;
    let intersecting = false;
    let renderedFrames = 0;

    const resize = () => {
      const density = Math.min(
        window.devicePixelRatio || 1,
        Math.max(1, densityLimit),
      );
      const parent = shared ? canvas.parentElement : null;
      const cssWidth = parent?.scrollWidth ?? canvas.clientWidth;
      const cssHeight = parent?.scrollHeight ?? canvas.clientHeight;
      if (shared) {
        canvas.style.width = `${cssWidth}px`;
        canvas.style.height = `${cssHeight}px`;
      }
      const width = Math.max(1, Math.round(cssWidth * density));
      const height = Math.max(1, Math.round(cssHeight * density));
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
      return density;
    };

    const draw = (
      width: number,
      height: number,
      time: number,
      framebuffer: WebGLFramebuffer | null,
      paletteValue = palette,
      originX = 0,
      originY = 0,
    ) => {
      context.bindFramebuffer(context.FRAMEBUFFER, framebuffer);
      context.viewport(0, 0, width, height);
      context.useProgram(program);
      context.bindBuffer(context.ARRAY_BUFFER, positionBuffer);
      context.enableVertexAttribArray(positionLocation);
      context.vertexAttribPointer(positionLocation, 2, context.FLOAT, false, 0, 0);
      context.uniform2f(resolutionLocation, width, height);
      context.uniform2f(originLocation, originX, originY);
      context.uniform1f(timeLocation, time);
      context.uniform1f(paletteLocation, paletteValue);
      context.uniform1f(sharedLocation, 0);
      context.drawArrays(context.TRIANGLES, 0, 6);
    };

    const drawSharedCards = (time: number, density: number) => {
      const parent = canvas.parentElement;
      if (!parent) return;
      const cards = Array.from(
        parent.querySelectorAll<HTMLElement>(".latestPost"),
      );
      context.bindFramebuffer(context.FRAMEBUFFER, null);
      context.viewport(0, 0, canvas.width, canvas.height);
      context.clearColor(0, 0, 0, 0);
      context.clear(context.COLOR_BUFFER_BIT);
      let drawnCards = 0;
      const cardRects = new Float32Array(8 * 4);
      const cardPalettes = new Float32Array(8);

      for (let index = 0; index < cards.length; index += 1) {
        const card = cards[index];
        if (!card) continue;
        const visibleRect = layoutTracker?.locate(card).rect
          ?? card.getBoundingClientRect();
        if (
          visibleRect.bottom <= 0 ||
          visibleRect.top >= window.innerHeight ||
          visibleRect.right <= 0 ||
          visibleRect.left >= window.innerWidth
        ) {
          continue;
        }

        const x = Math.round(card.offsetLeft * density);
        const width = Math.max(1, Math.round(card.offsetWidth * density));
        const height = Math.max(1, Math.round(card.offsetHeight * density));
        const y = canvas.height
          - Math.round((card.offsetTop + card.offsetHeight) * density);
        const rectOffset = drawnCards * 4;
        cardRects[rectOffset] = x;
        cardRects[rectOffset + 1] = y;
        cardRects[rectOffset + 2] = width;
        cardRects[rectOffset + 3] = height;
        cardPalettes[drawnCards] = palettes[index] ?? palette;
        drawnCards += 1;
      }

      context.useProgram(program);
      context.bindBuffer(context.ARRAY_BUFFER, positionBuffer);
      context.enableVertexAttribArray(positionLocation);
      context.vertexAttribPointer(positionLocation, 2, context.FLOAT, false, 0, 0);
      context.uniform2f(resolutionLocation, canvas.width, canvas.height);
      context.uniform2f(originLocation, 0, 0);
      context.uniform1f(timeLocation, time);
      context.uniform1f(paletteLocation, palette);
      context.uniform1f(sharedLocation, 1);
      context.uniform1f(cardCountLocation, drawnCards);
      context.uniform4fv(cardRectsLocation, cardRects);
      context.uniform1fv(cardPalettesLocation, cardPalettes);
      context.drawArrays(context.TRIANGLES, 0, 6);

      canvas.dataset.drawnCards = String(drawnCards);
      if (drawnCards > 0) parent.dataset.shaderRendered = "";
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
      frame = 0;
      if (!intersecting || document.hidden) return;

      const shouldAnimate = !still && active && !reducedMotion.matches;
      const frameInterval = 1000 / Math.max(1, maxFps);
      if (shouldAnimate && now - lastDraw < frameInterval) {
        frame = window.requestAnimationFrame(render);
        return;
      }

      const density = resize();
      const time = still || reducedMotion.matches ? 0 : (now - start) / 1000;
      if (shared) drawSharedCards(time, density);
      else draw(canvas.width, canvas.height, time, null);

      if (measure && lastMeasurement === -Infinity) {
        measureContrast(time);
        lastMeasurement = now;
        context.bindFramebuffer(context.FRAMEBUFFER, null);
      }
      canvas.dataset.rendered = "true";
      renderedFrames += 1;
      canvas.dataset.frameCount = String(renderedFrames);
      lastDraw = now;

      if (shouldAnimate) {
        frame = window.requestAnimationFrame(render);
      }
    };

    const cancelFrame = () => {
      if (!frame) return;
      window.cancelAnimationFrame(frame);
      frame = 0;
    };

    const scheduleRender = () => {
      if (frame || !intersecting || document.hidden) return;
      frame = window.requestAnimationFrame(render);
    };

    const restart = () => {
      cancelFrame();
      start = performance.now();
      lastDraw = -Infinity;
      scheduleRender();
    };

    const resizeObserver = new ResizeObserver(scheduleRender);
    const intersectionObserver = new IntersectionObserver(([entry]) => {
      intersecting = entry?.isIntersecting ?? false;
      if (intersecting) scheduleRender();
      else cancelFrame();
    });
    const handleVisibilityChange = () => {
      if (document.hidden) cancelFrame();
      else restart();
    };
    resizeObserver.observe(canvas);
    intersectionObserver.observe(canvas);
    reducedMotion.addEventListener("change", restart);
    document.addEventListener("visibilitychange", handleVisibilityChange);
    const stopTrackingLayout = layoutTracker?.observe(canvas, scheduleRender);
    requestRender = scheduleRender;

    return () => {
      cancelFrame();
      requestRender = () => {};
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      reducedMotion.removeEventListener("change", restart);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      stopTrackingLayout?.();
      if (shared && canvas.parentElement) {
        delete canvas.parentElement.dataset.shaderRendered;
      }
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
  class:latestPostShader={shared}
  aria-hidden="true"
  data-palette={palette}
  data-active={active ? "" : undefined}
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

  .postShader.latestPostShader {
    background: transparent;
  }
</style>
