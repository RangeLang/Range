<script lang="ts">
  import { getContext, onMount } from "svelte";
  import {
    createDeepAcidWow,
  } from "$lib/audio/deep-acid-wow";
  import {
    RANGE_SOUND_MANAGER_CONTEXT,
    type RangeSoundManager,
    type RangeSoundRoute,
  } from "$lib/audio/sound-manager";
  import {
    RANGE_LAYOUT_TRACKER_CONTEXT,
    type RangeLayoutRect,
    type RangeLayoutSnapshot,
    type RangeLayoutTracker,
  } from "$lib/layout/layout-tracker";
  import {
    hasCompleteFramebuffer,
    hasDrawableWebGLSurface,
  } from "$lib/rendering/webgl-lifecycle";

  let {
    text = "Range",
    base = "dark",
    colors = "spectrum",
    transpose = 0,
    hdr = false,
    effect: visualEffect = "interactive",
    layout = "natural",
    sound = true,
    trigger = 0,
  }: {
    text?: string;
    base?: "dark" | "white";
    colors?: "spectrum" | "warm-light";
    transpose?: number;
    hdr?: boolean;
    effect?: "interactive" | "radiate" | "dam-sweep";
    layout?: "natural" | "error-status";
    sound?: boolean;
    trigger?: number;
  } = $props();
  const anchorX = 0.59;
  const anchorY = 0.5;
  const reanchorDuration = 1200;
  const pointerStopDelay = 1000;
  const soundFalloffScale = 1.15;
  const soundFalloffPadding = 80;
  const soundIdleWait = 600;
  const soundFalloffDuration = 1200;
  const soundMotionVolumeDuration = 60;
  const shaderWordmarkPrefix = "Ra";
  const shaderWordmarkSuffix = "nge";
  const radians = (degrees: number) => (degrees * Math.PI) / 180;
  // Wide-gamut basis colors expressed in OKLCH. The blue is pulled inward
  // from the P3 boundary so it reads as radiant color rather than neon.
  const outwardPaletteOklch = new Float32Array([
    0.73, 0.27, radians(20),
    0.848829, 0.368528, radians(145.645),
    0.62, 0.22, radians(280),
  ]);
  const warmLightPaletteOklch = new Float32Array([
    0.86, 0.12, radians(52),
    0.94, 0.1, radians(76),
    0.985, 0.008, radians(82),
  ]);
  const warmHdrPaletteOklch = new Float32Array([
    0.86, 0.22, radians(52),
    0.95, 0.18, radians(76),
    0.995, 0.015, radians(82),
  ]);
  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );
  const layoutTracker = getContext<RangeLayoutTracker | undefined>(
    RANGE_LAYOUT_TRACKER_CONTEXT,
  );

  let titleElement: HTMLSpanElement;
  let canvas: HTMLCanvasElement;
  let canvasReady = $state(false);

  let gl: WebGL2RenderingContext | null = null;
  let program: WebGLProgram | null = null;
  let blurProgram: WebGLProgram | null = null;
  let glyphTexture: WebGLTexture | null = null;
  let outwardTextureA: WebGLTexture | null = null;
  let outwardTextureB: WebGLTexture | null = null;
  let outwardFramebufferA: WebGLFramebuffer | null = null;
  let outwardFramebufferB: WebGLFramebuffer | null = null;
  let glyphSource: HTMLCanvasElement | null = null;
  let uniformLocations: Record<string, WebGLUniformLocation | null> = {};
  let blurUniformLocations: Record<string, WebGLUniformLocation | null> = {};
  let usesDisplayP3 = false;
  let titleAudioContext: AudioContext | null = null;
  let titleSoundRoute: RangeSoundRoute | null = null;
  let titleSound: ReturnType<typeof createDeepAcidWow> | null = null;

  let distortionCenter = anchorX;
  let distortionVerticalCenter = anchorY;
  let targetDistortionCenter = anchorX;
  let targetDistortionVerticalCenter = anchorY;
  let pointerRenderFrame: number | null = null;
  let radiateRenderFrame: number | null = null;
  let radiateStartedAt = 0;
  let lastRadiateFrame = -Infinity;
  let radiateTime = 0;
  let sweepProgress = 1;
  let sweepDirection = 1;
  let sweepRenderFrame: number | null = null;
  let sweepStartedAt = 0;
  let sweepRequested = false;
  let lastSweepTrigger = 0;
  let pointerAnimationTime = 0;
  let pointerInside = false;
  let soundProximity = 0;
  let lastPointerClientX = 0;
  let lastPointerClientY = 0;
  let idleTimeout: ReturnType<typeof setTimeout> | null = null;
  let reanchorTimeout: ReturnType<typeof setTimeout> | null = null;
  let reanchorStartedAt = 0;
  let reanchorStartX = anchorX;
  let reanchorStartY = anchorY;
  let reanchorStartVelocityX = 0;
  let reanchorStartVelocityY = 0;
  let reanchoring = false;
  let distortionVelocityX = 0;
  let distortionVelocityY = 0;
  let pointerVelocityX = 0;
  let pointerVelocityY = 0;
  let lastPointerX = anchorX;
  let lastPointerY = anchorY;
  let lastPointerTime = 0;
  let rendererActive = false;
  let contextLost = false;

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

    uniform sampler2D uGlyph;
    uniform sampler2D uOutwardBlur;
    uniform int uPass;
    uniform vec4 uContentRect;
    uniform vec2 uInkY;
    uniform float uAnchorX;
    uniform float uPointerY;
    uniform vec3 uCharcoalColor;
    uniform vec3 uOutwardOklch[3];
    uniform int uDisplayP3;
    uniform int uWarmOnly;
    uniform int uRadiate;
    uniform int uSweep;
    uniform float uSweepProgress;
    uniform float uSweepDirection;
    uniform float uTime;

    in vec2 vUv;
    out vec4 outputColor;

    float sourceField(float position) {
      float broad = sin(position * 7.3 + 0.55) * 0.5;
      float middle = sin(position * 16.7 - 0.8) * 0.32;
      float fine = sin(position * 34.1 + 1.7) * 0.18;
      return (broad + middle + fine + 1.0) * 0.5;
    }

    float focusEnvelope(float position) {
      float distance = position - uAnchorX;
      float width = 0.24;
      return exp(-(distance * distance) / (2.0 * width * width));
    }

    float glyphMask(vec2 uv) {
      return texture(uGlyph, uv).a;
    }

    float sweptGlyphMask(vec2 uv, float progress) {
      float directionalProgress = uSweepDirection > 0.0
        ? progress
        : 1.0 - progress;
      float sweepCenter = mix(-0.2, 1.2, directionalProgress);
      vec2 lensCenter = vec2(
        uContentRect.x + sweepCenter * uContentRect.z,
        uInkY.x + 0.5 * uInkY.y
      );
      vec2 textureDimensions = vec2(textureSize(uGlyph, 0));
      vec2 pixelOffset = (uv - lensCenter) * textureDimensions;
      float inkPixels = uInkY.y * textureDimensions.y;
      float lensRadius = max(1.0, inkPixels * 0.62);
      float radius = length(pixelOffset) / lensRadius;
      float lens = 1.0 - smoothstep(0.0, 1.0, radius);
      float magnification = 1.0 + lens * 0.075;
      vec2 source = lensCenter + (uv - lensCenter) * magnification;
      return glyphMask(source);
    }

    float sweptOuterStroke(vec2 uv, float progress, float center) {
      vec2 texel = 1.0 / vec2(textureSize(uGlyph, 0));
      float expanded = center;
      for (int sampleIndex = 0; sampleIndex < 8; sampleIndex += 1) {
        float angle = float(sampleIndex) * 0.7853981634;
        vec2 direction = vec2(cos(angle), sin(angle));
        expanded = max(
          expanded,
          sweptGlyphMask(uv + direction * texel * 4.0, progress)
        );
      }
      return max(0.0, expanded - center);
    }

    float radiatingGlyphMask(vec2 uv, float radius, float pulse) {
      vec2 textureDimensions = vec2(textureSize(uGlyph, 0));
      vec2 texel = 1.0 / textureDimensions;
      float inkPixels = uInkY.y * textureDimensions.y;
      float breathingRadius = radius * mix(0.72, 1.0, pulse);
      float expanded = glyphMask(uv);
      for (int sampleIndex = 0; sampleIndex < 12; sampleIndex += 1) {
        float angle = float(sampleIndex) * 0.5235987756;
        vec2 direction = vec2(cos(angle), sin(angle));
        expanded = max(
          expanded,
          glyphMask(
            uv + direction * inkPixels * breathingRadius * texel
          )
        );
      }
      return expanded;
    }

    float innerGlyphEdgeMask(vec2 uv, float center) {
      vec2 texel = 1.0 / vec2(textureSize(uGlyph, 0));
      vec2 radius = texel * 3.0;
      float surrounding = (
        glyphMask(uv + vec2(radius.x, 0.0)) +
        glyphMask(uv - vec2(radius.x, 0.0)) +
        glyphMask(uv + vec2(0.0, radius.y)) +
        glyphMask(uv - vec2(0.0, radius.y))
      ) * 0.25;
      return center * clamp(1.0 - surrounding, 0.0, 1.0);
    }

    float warpedMask(
      vec2 uv,
      float intensity,
      float distortionLimit,
      float direction,
      float horizontalDistance
    ) {
      float contentX = (uv.x - uContentRect.x) / uContentRect.z;
      float focus = focusEnvelope(contentX);
      float distortion = focus * intensity *
        (0.04 + sourceField(contentX) * 0.08);
      float bounded = min(distortionLimit, distortion);

      float polarity = clamp(
        (contentX - uAnchorX) / 0.22,
        -1.0,
        1.0
      );
      float averageHalfGlyph = uContentRect.z / 10.0;
      float sourceX = uv.x -
        polarity *
        bounded *
        averageHalfGlyph *
        horizontalDistance *
        direction;

      float pointerY = clamp(uPointerY, 0.0, 1.0);
      float softenedY = 0.5 + (pointerY - 0.5) * 0.35;
      float pivotY = uInkY.x + (1.0 - softenedY) * uInkY.y;
      float stretch = 1.0 + direction * bounded;
      float sourceY = pivotY + (uv.y - pivotY) / stretch;

      return glyphMask(vec2(sourceX, sourceY));
    }

    vec4 over(vec4 under, vec4 upper) {
      float alpha = upper.a + under.a * (1.0 - upper.a);
      vec3 color = (
        upper.rgb * upper.a +
        under.rgb * under.a * (1.0 - upper.a)
      ) / max(alpha, 0.00001);
      return vec4(color, alpha);
    }

    vec3 oklchToOutput(vec3 color) {
      float labA = color.y * cos(color.z);
      float labB = color.y * sin(color.z);
      float lPrime = color.x + 0.3963377774 * labA + 0.2158037573 * labB;
      float mPrime = color.x - 0.1055613458 * labA - 0.0638541728 * labB;
      float sPrime = color.x - 0.0894841775 * labA - 1.2914855480 * labB;
      float l = lPrime * lPrime * lPrime;
      float m = mPrime * mPrime * mPrime;
      float s = sPrime * sPrime * sPrime;
      vec3 linear;
      if (uDisplayP3 == 1) {
        vec3 xyz = vec3(
          1.2268798734 * l - 0.5578149966 * m - 0.2813910502 * s,
          -0.0405757452 * l + 1.1122868294 * m - 0.0717110667 * s,
          -0.0763729497 * l - 0.4214933240 * m + 1.5869240244 * s
        );
        linear = vec3(
          2.4934969119 * xyz.x - 0.9313836179 * xyz.y - 0.4027107845 * xyz.z,
          -0.8294889696 * xyz.x + 1.7626640603 * xyz.y + 0.0236246858 * xyz.z,
          0.0358458302 * xyz.x - 0.0761723893 * xyz.y + 0.9568845240 * xyz.z
        );
      } else {
        linear = vec3(
          4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
          -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
          -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        );
      }
      vec3 low = linear * 12.92;
      vec3 high =
        1.055 *
        pow(max(linear, vec3(0.0)), vec3(1.0 / 2.4)) -
        0.055;
      return clamp(
        mix(high, low, lessThanEqual(linear, vec3(0.0031308))),
        0.0,
        1.0
      );
    }

    void main() {
      if (uSweep == 1) {
        float sweptBase = sweptGlyphMask(vUv, uSweepProgress);
        if (uPass == 0) {
          outputColor = vec4(0.0);
        } else {
          float directionalProgress = uSweepDirection > 0.0
            ? uSweepProgress
            : 1.0 - uSweepProgress;
          float sweepCenter = mix(-0.2, 1.2, directionalProgress);
          float contentX = (vUv.x - uContentRect.x) / uContentRect.z;
          float fieldDistance = (contentX - sweepCenter) / 0.18;
          float field = exp(-fieldDistance * fieldDistance);
          float outerStroke = sweptOuterStroke(
            vUv,
            uSweepProgress,
            sweptBase
          );
          float strokeAlpha = outerStroke * mix(0.12, 0.46, field);
          vec3 coolEdge = vec3(0.52, 0.72, 1.0);
          vec3 warmEdge = vec3(1.0, 0.62, 0.28);
          vec3 edgeColor = mix(
            coolEdge,
            warmEdge,
            smoothstep(-0.3, 0.3, contentX - sweepCenter)
          );
          float alpha = max(sweptBase, strokeAlpha);
          vec3 premultiplied =
            uCharcoalColor * sweptBase +
            edgeColor * strokeAlpha * (1.0 - sweptBase);
          outputColor = vec4(premultiplied, alpha);
        }
        return;
      }

      float contentX = (vUv.x - uContentRect.x) / uContentRect.z;
      float rawPulse = 0.5 + 0.5 * sin(uTime * 0.9);
      float pulse = rawPulse * rawPulse * (3.0 - 2.0 * rawPulse);
      float focus = uRadiate == 1
        ? mix(0.72, 1.0, pulse)
        : focusEnvelope(contentX);
      float base = glyphMask(vUv);

      // Group(.outward) {
      //   Red -> Green -> Blue
      // }
      float redMask = uRadiate == 1
        ? radiatingGlyphMask(vUv, 0.072, pulse)
        : warpedMask(vUv, 3.0, 0.4, 1.0, 0.22);
      float greenMask = uRadiate == 1
        ? radiatingGlyphMask(vUv, 0.045, pulse)
        : warpedMask(vUv, 2.15, 0.36, 1.0, 0.22);
      float blueMask = uRadiate == 1
        ? radiatingGlyphMask(vUv, 0.022, pulse)
        : warpedMask(vUv, 1.3, 0.32, 1.0, 0.22);
      float redOutside = max(0.0, redMask - base);
      float greenOutside = max(0.0, greenMask - base);
      float blueOutside = max(0.0, blueMask - base);
      // Give every basis color its own shell. The Gaussian blur creates the
      // yellow and cyan transitions without turning the whole blue shell cyan.
      float redBand = max(0.0, redOutside - greenOutside);
      float greenBand = max(0.0, greenOutside - blueOutside);
      float channelOpacity = 0.95;
      float channelAlpha = max(
        redBand,
        max(greenBand, blueOutside)
      );
      vec3 channelColor =
        oklchToOutput(uOutwardOklch[0]) * redBand +
        oklchToOutput(uOutwardOklch[1]) * greenBand +
        oklchToOutput(uOutwardOklch[2]) * blueOutside;
      vec3 outwardColor = clamp(
        channelColor / max(channelAlpha, 0.00001),
        0.0,
        1.0
      );
      vec4 outward = vec4(
        outwardColor,
        channelAlpha * focus * channelOpacity
      );

      if (uPass == 0) {
        outputColor = vec4(outward.rgb * outward.a, outward.a);
        return;
      }

      vec4 blurredPremultiplied = texture(uOutwardBlur, vUv);
      vec3 blurredOutwardColor = blurredPremultiplied.rgb /
        max(blurredPremultiplied.a, 0.00001);
      vec4 blurredOutward = vec4(
        blurredOutwardColor,
        blurredPremultiplied.a
      );
      // Three independent layers: outward color, black glyph, then a white
      // mask made from the blurred color intersecting the glyph's inside edge.
      vec4 glyph = over(
        blurredOutward,
        vec4(uCharcoalColor, base)
      );
      float whiteInnerOpacity = 0.68;
      float whiteInnerAnchor = smoothstep(
        0.0,
        0.22,
        blurredPremultiplied.a
      );
      float whiteInnerMask =
        innerGlyphEdgeMask(vUv, base) *
        whiteInnerAnchor *
        whiteInnerOpacity;
      vec4 illuminatedGlyph = over(
        glyph,
        vec4(vec3(1.0), whiteInnerMask)
      );
      vec4 composition = illuminatedGlyph;

      if (uWarmOnly == 1) {
        float glowEnergy = clamp(blurredPremultiplied.a * 2.15, 0.0, 1.0);
        vec3 amber = vec3(1.0, 0.24, 0.008);
        vec3 gold = vec3(1.0, 0.7, 0.08);
        vec3 warmWhite = vec3(1.0, 0.99, 0.94);
        vec3 emittedLight = mix(
          amber,
          gold,
          smoothstep(0.04, 0.58, glowEnergy)
        );
        emittedLight = mix(
          emittedLight,
          warmWhite,
          smoothstep(0.5, 0.96, glowEnergy)
        );
        composition.rgb = mix(
          emittedLight,
          uCharcoalColor,
          smoothstep(0.04, 0.82, base)
        );
        float softGlow = pow(
          clamp(blurredPremultiplied.a, 0.0, 1.0),
          0.72
        ) * 0.86 * (uRadiate == 1 ? mix(0.76, 1.0, pulse) : 1.0);
        composition.a = max(base, softGlow);
      }

      outputColor = vec4(
        clamp(composition.rgb, 0.0, 1.0) * composition.a,
        composition.a
      );
    }
  `;

  const blurFragmentShaderSource = `#version 300 es
    precision highp float;

    uniform sampler2D uSource;
    uniform vec2 uDirection;

    in vec2 vUv;
    out vec4 outputColor;

    void main() {
      vec4 color = texture(uSource, vUv) * 0.2270270270;
      color += texture(
        uSource,
        vUv + uDirection * 1.3846153846
      ) * 0.3162162162;
      color += texture(
        uSource,
        vUv - uDirection * 1.3846153846
      ) * 0.3162162162;
      color += texture(
        uSource,
        vUv + uDirection * 3.2307692308
      ) * 0.0702702703;
      color += texture(
        uSource,
        vUv - uDirection * 3.2307692308
      ) * 0.0702702703;
      outputColor = color;
    }
  `;

  const compileShader = (
    context: WebGL2RenderingContext,
    type: number,
    source: string,
  ) => {
    const shader = context.createShader(type);
    if (!shader) throw new Error("Unable to create Range title shader.");
    context.shaderSource(shader, source);
    context.compileShader(shader);
    if (!context.getShaderParameter(shader, context.COMPILE_STATUS)) {
      const message = context.getShaderInfoLog(shader) ?? "Unknown shader error.";
      context.deleteShader(shader);
      throw new Error(message);
    }
    return shader;
  };

  const createProgram = (
    context: WebGL2RenderingContext,
    fragmentSource = fragmentShaderSource,
  ) => {
    const vertexShader = compileShader(
      context,
      context.VERTEX_SHADER,
      vertexShaderSource,
    );
    const fragmentShader = compileShader(
      context,
      context.FRAGMENT_SHADER,
      fragmentSource,
    );
    const nextProgram = context.createProgram();
    if (!nextProgram) throw new Error("Unable to create Range title program.");
    context.attachShader(nextProgram, vertexShader);
    context.attachShader(nextProgram, fragmentShader);
    context.linkProgram(nextProgram);
    context.deleteShader(vertexShader);
    context.deleteShader(fragmentShader);
    if (!context.getProgramParameter(nextProgram, context.LINK_STATUS)) {
      const message =
        context.getProgramInfoLog(nextProgram) ?? "Unknown program error.";
      context.deleteProgram(nextProgram);
      throw new Error(message);
    }
    return nextProgram;
  };

  const cacheUniformLocations = () => {
    if (!gl || !program || !blurProgram) return;
    uniformLocations = {
      glyph: gl.getUniformLocation(program, "uGlyph"),
      outwardBlur: gl.getUniformLocation(program, "uOutwardBlur"),
      pass: gl.getUniformLocation(program, "uPass"),
      contentRect: gl.getUniformLocation(program, "uContentRect"),
      inkY: gl.getUniformLocation(program, "uInkY"),
      anchorX: gl.getUniformLocation(program, "uAnchorX"),
      pointerY: gl.getUniformLocation(program, "uPointerY"),
      charcoalColor: gl.getUniformLocation(program, "uCharcoalColor"),
      outwardOklch: gl.getUniformLocation(program, "uOutwardOklch"),
      displayP3: gl.getUniformLocation(program, "uDisplayP3"),
      warmOnly: gl.getUniformLocation(program, "uWarmOnly"),
      radiate: gl.getUniformLocation(program, "uRadiate"),
      sweep: gl.getUniformLocation(program, "uSweep"),
      sweepProgress: gl.getUniformLocation(program, "uSweepProgress"),
      sweepDirection: gl.getUniformLocation(program, "uSweepDirection"),
      time: gl.getUniformLocation(program, "uTime"),
    };
    blurUniformLocations = {
      source: gl.getUniformLocation(blurProgram, "uSource"),
      direction: gl.getUniformLocation(blurProgram, "uDirection"),
    };
  };

  const configureRenderTarget = (
    texture: WebGLTexture,
    framebuffer: WebGLFramebuffer,
    width: number,
    height: number,
  ) => {
    if (!gl || !rendererActive || contextLost || width <= 0 || height <= 0) {
      return false;
    }
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RGBA8,
      width,
      height,
      0,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      null,
    );
    gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
    gl.framebufferTexture2D(
      gl.FRAMEBUFFER,
      gl.COLOR_ATTACHMENT0,
      gl.TEXTURE_2D,
      texture,
      0,
    );
    return hasCompleteFramebuffer(gl, framebuffer);
  };

  const rebuildGlyphTexture = () => {
    if (
      !gl ||
      !program ||
      !glyphTexture ||
      !glyphSource ||
      !outwardTextureA ||
      !outwardTextureB ||
      !outwardFramebufferA ||
      !outwardFramebufferB
    ) return;

    const bounds = layoutTracker?.query(() => titleElement)?.rect
      ?? titleElement.getBoundingClientRect();
    const width = bounds.width;
    const height = bounds.height;
    if (width <= 0 || height <= 0) return;

    const style = getComputedStyle(titleElement);
    const fontSize = parseFloat(style.fontSize);
    const horizontalOverscan = Math.ceil(fontSize * 0.18);
    const verticalOverscan =
      Math.ceil(height * 0.32) + Math.ceil(fontSize * 0.06);
    const renderWidth = width + horizontalOverscan * 2;
    const renderHeight = height + verticalOverscan * 2;
    const density = Math.min(window.devicePixelRatio || 1, 2);

    canvas.width = Math.max(1, Math.round(renderWidth * density));
    canvas.height = Math.max(1, Math.round(renderHeight * density));
    canvas.style.width = `${renderWidth}px`;
    canvas.style.height = `${renderHeight}px`;
    canvas.style.left = `${-horizontalOverscan}px`;
    canvas.style.top = `${-verticalOverscan}px`;

    glyphSource.width = canvas.width;
    glyphSource.height = canvas.height;
    const sourceContext = glyphSource.getContext("2d");
    if (!sourceContext) return;
    sourceContext.setTransform(density, 0, 0, density, 0, 0);
    sourceContext.clearRect(0, 0, renderWidth, renderHeight);
    sourceContext.fillStyle = "white";
    sourceContext.font =
      `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    sourceContext.textBaseline = "alphabetic";
    (
      sourceContext as CanvasRenderingContext2D & { letterSpacing: string }
    ).letterSpacing = layout === "error-status" ? "0px" : style.letterSpacing;

    const metrics = sourceContext.measureText(text);
    const inkHeight =
      metrics.actualBoundingBoxAscent + metrics.actualBoundingBoxDescent;
    const inkTop = verticalOverscan + (height - inkHeight) / 2;
    const baseline = inkTop + metrics.actualBoundingBoxAscent;
    const textX = horizontalOverscan;
    if (layout === "error-status" && text.length === 3) {
      let glyphX = textX;
      for (const [index, glyph] of [...text].entries()) {
        if (index === 1) glyphX -= fontSize * 0.27;
        else if (index > 1) glyphX -= fontSize * 0.25;
        sourceContext.fillText(glyph, glyphX, baseline);
        glyphX += sourceContext.measureText(glyph).width;
      }
    } else if (text === shaderWordmarkPrefix + shaderWordmarkSuffix) {
      const prefixMetrics = sourceContext.measureText(shaderWordmarkPrefix);
      const suffixMetrics = sourceContext.measureText(shaderWordmarkSuffix);
      const joinedSuffixX =
        textX
        + prefixMetrics.actualBoundingBoxRight
        + suffixMetrics.actualBoundingBoxLeft;
      sourceContext.fillText(shaderWordmarkPrefix, textX, baseline);
      sourceContext.fillText(shaderWordmarkSuffix, joinedSuffixX, baseline);
    } else {
      sourceContext.fillText(text, textX, baseline);
    }

    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, glyphTexture);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RGBA,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      glyphSource,
    );
    const firstTargetReady = configureRenderTarget(
      outwardTextureA,
      outwardFramebufferA,
      canvas.width,
      canvas.height,
    );
    const secondTargetReady = configureRenderTarget(
      outwardTextureB,
      outwardFramebufferB,
      canvas.width,
      canvas.height,
    );
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    if (!firstTargetReady || !secondTargetReady) return;

    gl.useProgram(program);
    gl.uniform1i(uniformLocations.glyph, 0);
    gl.uniform1i(uniformLocations.outwardBlur, 1);
    gl.uniform4f(
      uniformLocations.contentRect,
      horizontalOverscan / renderWidth,
      verticalOverscan / renderHeight,
      width / renderWidth,
      height / renderHeight,
    );
    gl.uniform2f(
      uniformLocations.inkY,
      (renderHeight - inkTop - inkHeight) / renderHeight,
      inkHeight / renderHeight,
    );
    const baseChannel = base === "white" ? 1 : 0;
    gl.uniform3f(
      uniformLocations.charcoalColor,
      baseChannel,
      baseChannel,
      baseChannel,
    );
    gl.uniform3fv(
      uniformLocations.outwardOklch,
      hdr
        ? warmHdrPaletteOklch
        : colors === "warm-light"
          ? warmLightPaletteOklch
          : outwardPaletteOklch,
    );
    gl.uniform1i(uniformLocations.displayP3, usesDisplayP3 ? 1 : 0);
    gl.uniform1i(
      uniformLocations.warmOnly,
      colors === "warm-light" ? 1 : 0,
    );
    if (blurProgram) {
      gl.useProgram(blurProgram);
      gl.uniform1i(blurUniformLocations.source, 0);
    }

    renderCanvas();
    canvasReady = true;
  };

  const renderCanvas = () => {
    if (
      !gl ||
      !program ||
      !blurProgram ||
      !glyphTexture ||
      !outwardTextureA ||
      !outwardTextureB ||
      !outwardFramebufferA ||
      !outwardFramebufferB ||
      !rendererActive ||
      contextLost ||
      !hasDrawableWebGLSurface(canvas, gl)
    ) return;
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(0, 0, 0, 0);

    // Render the unblurred outward RGB group into texture A.
    gl.bindFramebuffer(gl.FRAMEBUFFER, outwardFramebufferA);
    gl.useProgram(program);
    gl.uniform1i(
      uniformLocations.radiate,
      visualEffect === "radiate" ? 1 : 0,
    );
    gl.uniform1i(
      uniformLocations.sweep,
      visualEffect === "dam-sweep" ? 1 : 0,
    );
    gl.uniform1f(uniformLocations.sweepProgress, sweepProgress);
    gl.uniform1f(uniformLocations.sweepDirection, sweepDirection);
    gl.uniform1f(uniformLocations.time, radiateTime);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, glyphTexture);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, outwardTextureB);
    gl.uniform1f(uniformLocations.anchorX, distortionCenter);
    gl.uniform1f(
      uniformLocations.pointerY,
      distortionVerticalCenter,
    );
    gl.uniform1i(uniformLocations.pass, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    // Several narrow separable passes converge to a smooth Gaussian without
    // exposing the sparse sampling lattice of one oversized kernel.
    gl.useProgram(blurProgram);
    const blurScales = hdr
      ? [1.1, 1.5, 2.0, 2.6, 3.2]
      : [0.9, 1.1, 1.3, 1.5];
    for (const blurScale of blurScales) {
      // Horizontal Gaussian pass: A -> B.
      gl.bindFramebuffer(gl.FRAMEBUFFER, outwardFramebufferB);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, outwardTextureA);
      gl.uniform2f(
        blurUniformLocations.direction,
        blurScale / canvas.width,
        0,
      );
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLES, 0, 3);

      // Vertical Gaussian pass: B -> A.
      gl.bindFramebuffer(gl.FRAMEBUFFER, outwardFramebufferA);
      gl.bindTexture(gl.TEXTURE_2D, outwardTextureB);
      gl.uniform2f(
        blurUniformLocations.direction,
        0,
        blurScale / canvas.height,
      );
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    // Composite the blurred group beneath the sharp base and inward group.
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.useProgram(program);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, glyphTexture);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, outwardTextureA);
    gl.uniform1i(uniformLocations.pass, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  };

  const animateRadiation = (timestamp: number) => {
    if (!rendererActive || contextLost || visualEffect !== "radiate") {
      radiateRenderFrame = null;
      return;
    }
    if (!radiateStartedAt) radiateStartedAt = timestamp;
    if (timestamp - lastRadiateFrame >= 1_000 / 24) {
      radiateTime = (timestamp - radiateStartedAt) / 1_000;
      renderCanvas();
      lastRadiateFrame = timestamp;
    }
    if (rendererActive && !contextLost) {
      radiateRenderFrame = requestAnimationFrame(animateRadiation);
    }
  };

  const startRadiating = () => {
    if (
      !rendererActive
      || contextLost
      || radiateRenderFrame !== null
      || visualEffect !== "radiate"
    ) return;
    radiateStartedAt = 0;
    lastRadiateFrame = -Infinity;
    radiateRenderFrame = requestAnimationFrame(animateRadiation);
  };

  const animateSweep = (timestamp: number) => {
    if (!rendererActive || contextLost || visualEffect !== "dam-sweep") {
      sweepRenderFrame = null;
      return;
    }
    sweepProgress = Math.min(1, (timestamp - sweepStartedAt) / 820);
    renderCanvas();
    if (sweepProgress < 1) {
      sweepRenderFrame = requestAnimationFrame(animateSweep);
    } else {
      sweepRenderFrame = null;
    }
  };

  const requestSweep = () => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    if (!rendererActive || contextLost || !canvasReady) {
      sweepRequested = true;
      return;
    }
    sweepRequested = false;
    if (sweepRenderFrame !== null) cancelAnimationFrame(sweepRenderFrame);
    sweepProgress = 0;
    sweepStartedAt = performance.now();
    sweepRenderFrame = requestAnimationFrame(animateSweep);
  };

  const updateTitleSound = (titleLayout?: RangeLayoutSnapshot) => {
    if (titleAudioContext?.state !== "running") return;
    const displacement = Math.min(
      1,
      Math.abs(distortionCenter - anchorX) / Math.max(anchorX, 1 - anchorX),
    );
    const shaderSpeed = Math.min(
      1,
      Math.hypot(distortionVelocityX, distortionVelocityY) * 900,
    );
    titleSound?.shape(
      displacement,
      shaderSpeed,
      distortionVerticalCenter,
    );
    updateSoundProximity(titleLayout?.rect);
    titleSound?.volume(soundProximity, soundMotionVolumeDuration / 1000);
    titleSound?.sustain(1);
  };

  const animatePointer = (timestamp: number) => {
    if (!rendererActive || contextLost) {
      pointerRenderFrame = null;
      return;
    }
    const elapsed = pointerAnimationTime
      ? Math.min(64, timestamp - pointerAnimationTime)
      : 16;
    pointerAnimationTime = timestamp;
    const previousCenter = distortionCenter;
    const previousVerticalCenter = distortionVerticalCenter;

    if (reanchoring) {
      const progress = Math.min(
        1,
        (timestamp - reanchorStartedAt) / reanchorDuration,
      );
      const progressSquared = progress * progress;
      const progressCubed = progressSquared * progress;
      const startWeight = 2 * progressCubed - 3 * progressSquared + 1;
      const velocityWeight =
        progressCubed - 2 * progressSquared + progress;
      const targetWeight = -2 * progressCubed + 3 * progressSquared;
      distortionCenter =
        reanchorStartX * startWeight +
        reanchorStartVelocityX * reanchorDuration * velocityWeight +
        targetDistortionCenter * targetWeight;
      distortionVerticalCenter =
        reanchorStartY * startWeight +
        reanchorStartVelocityY * reanchorDuration * velocityWeight +
        targetDistortionVerticalCenter * targetWeight;
      if (progress >= 1) reanchoring = false;
    } else {
      const horizontalResponse = pointerInside ? 280 : 360;
      const verticalResponse = pointerInside ? 720 : 900;
      const horizontalAmount = 1 - Math.exp(-elapsed / horizontalResponse);
      const verticalAmount = 1 - Math.exp(-elapsed / verticalResponse);
      distortionCenter +=
        (targetDistortionCenter - distortionCenter) * horizontalAmount;
      distortionVerticalCenter +=
        (targetDistortionVerticalCenter - distortionVerticalCenter) *
        verticalAmount;
    }

    const frameVelocityX = (distortionCenter - previousCenter) / elapsed;
    const frameVelocityY =
      (distortionVerticalCenter - previousVerticalCenter) / elapsed;
    const velocityBlend = reanchoring ? 1 : 0.35;
    distortionVelocityX +=
      (frameVelocityX - distortionVelocityX) * velocityBlend;
    distortionVelocityY +=
      (frameVelocityY - distortionVelocityY) * velocityBlend;

    updateTitleSound();
    renderCanvas();
    const unsettled =
      reanchoring ||
      Math.abs(targetDistortionCenter - distortionCenter) > 0.0005 ||
      Math.abs(
        targetDistortionVerticalCenter - distortionVerticalCenter,
      ) > 0.0005;

    if (unsettled) {
      if (rendererActive && !contextLost) {
        pointerRenderFrame = requestAnimationFrame(animatePointer);
      }
    } else {
      distortionCenter = targetDistortionCenter;
      distortionVerticalCenter = targetDistortionVerticalCenter;
      renderCanvas();
      pointerRenderFrame = null;
      pointerAnimationTime = 0;
      distortionVelocityX = 0;
      distortionVelocityY = 0;
      updateTitleSound();
    }
  };

  const startPointerAnimation = () => {
    if (rendererActive && !contextLost && pointerRenderFrame === null) {
      pointerAnimationTime = 0;
      pointerRenderFrame = requestAnimationFrame(animatePointer);
    }
  };

  const beginReanchor = () => {
    reanchorStartX = distortionCenter;
    reanchorStartY = distortionVerticalCenter;
    reanchorStartVelocityX = distortionVelocityX;
    reanchorStartVelocityY = distortionVelocityY;
    reanchorStartedAt = performance.now();
    reanchoring = true;
    targetDistortionCenter = anchorX;
    targetDistortionVerticalCenter = anchorY;
    startPointerAnimation();
  };

  const beginIdleFade = () => {
    pointerInside = false;
    soundProximity = 0;
    titleSound?.idleFade(0, soundFalloffDuration / 1000);
    beginReanchor();
  };

  const schedulePointerStop = () => {
    if (idleTimeout !== null) clearTimeout(idleTimeout);
    if (reanchorTimeout !== null) clearTimeout(reanchorTimeout);
    reanchorTimeout = null;
    idleTimeout = setTimeout(() => {
      idleTimeout = null;
      reanchorTimeout = setTimeout(() => {
        reanchorTimeout = null;
        beginIdleFade();
      }, soundIdleWait);
    }, pointerStopDelay);
  };

  const updateSoundProximity = (trackedTitleBounds?: RangeLayoutRect) => {
    const titleBounds = trackedTitleBounds
      ?? layoutTracker?.query(() => titleElement)?.rect
      ?? titleElement.getBoundingClientRect();
    const viewportWidth = window.visualViewport?.width ?? window.innerWidth;
    const viewportHeight = window.visualViewport?.height ?? window.innerHeight;
    if (
      titleBounds.right <= 0
      || titleBounds.bottom <= 0
      || titleBounds.left >= viewportWidth
      || titleBounds.top >= viewportHeight
    ) {
      soundProximity = 0;
      return;
    }
    const followPixelX = titleBounds.left + distortionCenter * titleBounds.width;
    const followPixelY =
      titleBounds.top + distortionVerticalCenter * titleBounds.height;
    const falloffRadiusX = titleBounds.width * 0.5 + soundFalloffPadding;
    const falloffRadiusY = titleBounds.height * 0.5 + soundFalloffPadding;
    const normalizedDistance = Math.hypot(
      (lastPointerClientX - followPixelX) / Math.max(1, falloffRadiusX),
      (lastPointerClientY - followPixelY) / Math.max(1, falloffRadiusY),
    );
    const normalized = Math.max(
      0,
      Math.min(1, 1 - normalizedDistance / soundFalloffScale),
    );
    soundProximity = normalized * normalized * normalized * (
      normalized * (normalized * 6 - 15) + 10
    );
  };

  const trackPointer = (event: PointerEvent) => {
    lastPointerClientX = event.clientX;
    lastPointerClientY = event.clientY;
    updateSoundProximity();
    const bounds = layoutTracker?.query(() => titleElement)?.rect
      ?? titleElement.getBoundingClientRect();
    if (idleTimeout !== null) {
      clearTimeout(idleTimeout);
      idleTimeout = null;
    }
    if (reanchorTimeout !== null) {
      clearTimeout(reanchorTimeout);
      reanchorTimeout = null;
    }
    titleSound?.idleFade(1, soundMotionVolumeDuration / 1000);
    reanchoring = false;
    const wasInside = pointerInside;
    pointerInside = true;
    const nextX = Math.max(
      0,
      Math.min(1, (event.clientX - bounds.left) / bounds.width),
    );
    const nextY = Math.max(
      0,
      Math.min(1, (event.clientY - bounds.top) / Math.max(1, bounds.height)),
    );
    const now = performance.now();

    if (wasInside && lastPointerTime > 0) {
      const elapsed = Math.max(1, now - lastPointerTime);
      const velocityBlend = 0.28;
      pointerVelocityX +=
        ((nextX - lastPointerX) / elapsed - pointerVelocityX) *
        velocityBlend;
      pointerVelocityY +=
        ((nextY - lastPointerY) / elapsed - pointerVelocityY) *
        velocityBlend;
    } else {
      pointerVelocityX = 0;
      pointerVelocityY = 0;
    }

    lastPointerX = nextX;
    lastPointerY = nextY;
    lastPointerTime = now;
    targetDistortionCenter = nextX;
    targetDistortionVerticalCenter = nextY;
    startPointerAnimation();
    schedulePointerStop();
  };

  const stopTrackingPointer = () => {
    if (idleTimeout !== null) {
      clearTimeout(idleTimeout);
      idleTimeout = null;
    }
    beginIdleFade();
  };

  const handlePointerWindowExit = (event: PointerEvent) => {
    if (event.relatedTarget === null) stopTrackingPointer();
  };

  const primeTitleSound = async (event: PointerEvent) => {
    if (!sound) return;
    const audio = await soundManager?.resume();
    if (!audio || !soundManager) return;
    soundManager.setEnabled(true);
    if (!titleAudioContext) {
      titleAudioContext = audio;
      titleSoundRoute = soundManager.register("range-title") ?? null;
      if (!titleSoundRoute) return;
      titleSound = createDeepAcidWow(audio, titleSoundRoute.input, {
        transposeSemitones: transpose,
      });
    }
    if (titleAudioContext.state === "suspended") {
      await titleAudioContext.resume();
    }
    trackPointer(event);
    updateTitleSound();
  };

  onMount(() => {
    let active = true;
    rendererActive = true;
    contextLost = false;
    try {
      gl = canvas.getContext("webgl2", {
        alpha: true,
        antialias: true,
        premultipliedAlpha: true,
        powerPreference: "high-performance",
      });
      if (!gl) throw new Error("WebGL 2 is unavailable.");
      try {
        gl.drawingBufferColorSpace = "display-p3";
      } catch {
        // Older browsers retain their default sRGB drawing buffer.
      }
      usesDisplayP3 = gl.drawingBufferColorSpace === "display-p3";
      gl.disable(gl.BLEND);
      gl.disable(gl.DITHER);
      program = createProgram(gl);
      blurProgram = createProgram(gl, blurFragmentShaderSource);
      glyphTexture = gl.createTexture();
      outwardTextureA = gl.createTexture();
      outwardTextureB = gl.createTexture();
      outwardFramebufferA = gl.createFramebuffer();
      outwardFramebufferB = gl.createFramebuffer();
      if (
        !glyphTexture ||
        !outwardTextureA ||
        !outwardTextureB ||
        !outwardFramebufferA ||
        !outwardFramebufferB
      ) {
        throw new Error("Unable to allocate Range title render targets.");
      }
      glyphSource = document.createElement("canvas");
      cacheUniformLocations();
    } catch (error) {
      rendererActive = false;
      console.error("Range title renderer could not initialize.", error);
      return;
    }

    window.addEventListener("pointermove", trackPointer, { passive: true });
    window.addEventListener("pointerout", handlePointerWindowExit);
    window.addEventListener("blur", stopTrackingPointer);
    const stopTrackingTitleLayout = layoutTracker?.observe(
      () => titleElement,
      (snapshot) => {
        updateTitleSound(snapshot);
      },
    );
    if (sound) titleElement.addEventListener("pointerdown", primeTitleSound);
    const handleContextLost = () => {
      contextLost = true;
      canvasReady = false;
      if (pointerRenderFrame !== null) cancelAnimationFrame(pointerRenderFrame);
      if (radiateRenderFrame !== null) cancelAnimationFrame(radiateRenderFrame);
      if (sweepRenderFrame !== null) cancelAnimationFrame(sweepRenderFrame);
      pointerRenderFrame = null;
      radiateRenderFrame = null;
      sweepRenderFrame = null;
    };
    canvas.addEventListener("webglcontextlost", handleContextLost);

    let resizeObserver: ResizeObserver | undefined;
    const renderWhenReady = async () => {
      await Promise.all([
        document.fonts.load('500 1em "Geist"'),
        document.fonts.load('500 1em "Geist Mono"'),
      ]);
      await document.fonts.ready;
      await new Promise<void>((resolve) => {
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
      });
      if (!active) return;
      rebuildGlyphTexture();
      resizeObserver = new ResizeObserver(rebuildGlyphTexture);
      resizeObserver.observe(titleElement);
      if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
        startRadiating();
        if (sweepRequested) requestSweep();
      }
    };
    void renderWhenReady();

    return () => {
      active = false;
      rendererActive = false;
      resizeObserver?.disconnect();
      if (pointerRenderFrame !== null) {
        cancelAnimationFrame(pointerRenderFrame);
      }
      if (radiateRenderFrame !== null) {
        cancelAnimationFrame(radiateRenderFrame);
      }
      if (sweepRenderFrame !== null) {
        cancelAnimationFrame(sweepRenderFrame);
      }
      if (idleTimeout !== null) clearTimeout(idleTimeout);
      if (reanchorTimeout !== null) clearTimeout(reanchorTimeout);
      window.removeEventListener("pointermove", trackPointer);
      window.removeEventListener("pointerout", handlePointerWindowExit);
      window.removeEventListener("blur", stopTrackingPointer);
      stopTrackingTitleLayout?.();
      if (sound) titleElement.removeEventListener("pointerdown", primeTitleSound);
      canvas.removeEventListener("webglcontextlost", handleContextLost);
      titleSound?.dispose();
      titleSoundRoute?.dispose();
      titleSound = null;
      titleSoundRoute = null;
      titleAudioContext = null;
      if (gl && glyphTexture) gl.deleteTexture(glyphTexture);
      if (gl && outwardTextureA) gl.deleteTexture(outwardTextureA);
      if (gl && outwardTextureB) gl.deleteTexture(outwardTextureB);
      if (gl && outwardFramebufferA) {
        gl.deleteFramebuffer(outwardFramebufferA);
      }
      if (gl && outwardFramebufferB) {
        gl.deleteFramebuffer(outwardFramebufferB);
      }
      if (gl && program) gl.deleteProgram(program);
      if (gl && blurProgram) gl.deleteProgram(blurProgram);
    };
  });

  $effect(() => {
    const nextTrigger = trigger;
    if (
      visualEffect !== "dam-sweep"
      || nextTrigger <= 0
      || nextTrigger === lastSweepTrigger
    ) return;
    lastSweepTrigger = nextTrigger;
    sweepDirection = nextTrigger % 2 === 1 ? 1 : -1;
    requestSweep();
  });
</script>

<span
  class="rangeTitleWord"
  data-range-layout="range-title"
  class:canvasReady
  class:hdr
  class:darkBase={base === "dark"}
  bind:this={titleElement}
>
  {#if layout === "error-status"}
    <span class="rangeTitleMeasure errorStatusMeasure" aria-hidden="true">
      {#each [...text] as glyph}
        <span class="errorStatusDigit">{glyph}</span>
      {/each}
    </span>
  {:else}
    <span class="rangeTitleMeasure">{text}</span>
  {/if}
  <canvas
    class="rangeTitleCanvas"
    data-range-layout="range-title-canvas"
    bind:this={canvas}
    aria-hidden="true"
  ></canvas>
</span>

<style>
  .rangeTitleWord {
    position: relative;
    width: fit-content;
    display: block;
    isolation: isolate;
    overflow: visible;
    touch-action: none;
    transform: translateX(var(--range-title-ink-shift, 0px));
  }

  .rangeTitleMeasure {
    display: block;
  }

  .errorStatusMeasure {
    display: inline-flex;
    align-items: center;
    letter-spacing: 0;
    user-select: none;
    -webkit-user-select: none;
  }

  .errorStatusDigit {
    position: relative;
    display: block;
  }

  .errorStatusDigit + .errorStatusDigit {
    margin-left: -0.25em;
  }

  .errorStatusDigit:first-child + .errorStatusDigit {
    margin-left: -0.27em;
  }

  .darkBase .rangeTitleMeasure {
    color: oklch(0.12 0.012 255);
  }

  .canvasReady .rangeTitleMeasure {
    color: transparent;
  }

  .rangeTitleCanvas {
    position: absolute;
    display: block;
    pointer-events: none;
  }

  .hdr .rangeTitleCanvas {
    filter: brightness(1.04);
  }

  @media (dynamic-range: high) {
    .hdr .rangeTitleCanvas {
      filter: brightness(1.12);
    }
  }
</style>
