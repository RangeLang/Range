<script lang="ts">
  import { onMount } from "svelte";

  const text = "Range";
  const anchorX = 0.59;
  const anchorY = 0.5;
  const reanchorDelay = 1000;

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

  let distortionCenter = anchorX;
  let distortionVerticalCenter = anchorY;
  let targetDistortionCenter = anchorX;
  let targetDistortionVerticalCenter = anchorY;
  let pointerRenderFrame: number | null = null;
  let pointerAnimationTime = 0;
  let pointerInside = false;
  let idleTimeout: ReturnType<typeof setTimeout> | null = null;
  let reanchorTimeout: ReturnType<typeof setTimeout> | null = null;
  let reanchorStartedAt = 0;
  let reanchorStartX = anchorX;
  let reanchorStartY = anchorY;
  let reanchoring = false;
  let pointerVelocityX = 0;
  let pointerVelocityY = 0;
  let lastPointerX = anchorX;
  let lastPointerY = anchorY;
  let lastPointerTime = 0;

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
    uniform vec3 uRevealColor;
    uniform vec3 uOutwardOklch[3];

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

    vec3 oklchToSrgb(vec3 color) {
      float labA = color.y * cos(color.z);
      float labB = color.y * sin(color.z);
      float lPrime = color.x + 0.3963377774 * labA + 0.2158037573 * labB;
      float mPrime = color.x - 0.1055613458 * labA - 0.0638541728 * labB;
      float sPrime = color.x - 0.0894841775 * labA - 1.2914855480 * labB;
      float l = lPrime * lPrime * lPrime;
      float m = mPrime * mPrime * mPrime;
      float s = sPrime * sPrime * sPrime;
      vec3 linear = vec3(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
      );
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
      float contentX = (vUv.x - uContentRect.x) / uContentRect.z;
      float focus = focusEnvelope(contentX);
      float base = glyphMask(vUv);

      // Group(.outward) {
      //   Red -> Green -> Blue
      // }
      float redMask = warpedMask(vUv, 3.0, 0.4, 1.0, 0.22);
      float greenMask = warpedMask(vUv, 2.4, 0.36, 1.0, 0.22);
      float blueMask = warpedMask(vUv, 1.8, 0.32, 1.0, 0.22);
      float redOutside = max(0.0, redMask - base);
      float greenOutside = max(0.0, greenMask - base);
      float blueOutside = max(0.0, blueMask - base);
      vec4 outward = vec4(0.0);
      outward = over(
        outward,
        vec4(oklchToSrgb(uOutwardOklch[0]), redOutside * focus * 0.9)
      );
      outward = over(
        outward,
        vec4(oklchToSrgb(uOutwardOklch[1]), greenOutside * focus * 0.9)
      );
      outward = over(
        outward,
        vec4(oklchToSrgb(uOutwardOklch[2]), blueOutside * focus * 0.9)
      );

      if (uPass == 0) {
        outputColor = vec4(outward.rgb * outward.a, outward.a);
        return;
      }

      vec4 blurredPremultiplied = texture(uOutwardBlur, vUv);
      vec4 blurredOutward = vec4(
        blurredPremultiplied.rgb /
          max(blurredPremultiplied.a, 0.00001),
        blurredPremultiplied.a
      );

      // Two-tone base: pitch black by default, charcoal at the reveal.
      vec3 glyphColor = mix(
        uCharcoalColor,
        uRevealColor,
        focus
      );
      vec4 glyph = over(blurredOutward, vec4(glyphColor, base));

      outputColor = vec4(clamp(glyph.rgb, 0.0, 1.0) * glyph.a, glyph.a);
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
      revealColor: gl.getUniformLocation(program, "uRevealColor"),
      outwardOklch: gl.getUniformLocation(program, "uOutwardOklch"),
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
    if (!gl) return;
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
    if (
      gl.checkFramebufferStatus(gl.FRAMEBUFFER) !==
      gl.FRAMEBUFFER_COMPLETE
    ) {
      throw new Error("Range title blur framebuffer is incomplete.");
    }
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

    const bounds = titleElement.getBoundingClientRect();
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
    ).letterSpacing = style.letterSpacing;

    const metrics = sourceContext.measureText(text);
    const inkHeight =
      metrics.actualBoundingBoxAscent + metrics.actualBoundingBoxDescent;
    const inkTop = verticalOverscan + (height - inkHeight) / 2;
    const baseline = inkTop + metrics.actualBoundingBoxAscent;
    const textX = horizontalOverscan;
    sourceContext.fillText(text, textX, baseline);

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
    configureRenderTarget(
      outwardTextureA,
      outwardFramebufferA,
      canvas.width,
      canvas.height,
    );
    configureRenderTarget(
      outwardTextureB,
      outwardFramebufferB,
      canvas.width,
      canvas.height,
    );
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);

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
    gl.uniform3f(uniformLocations.charcoalColor, 0, 0, 0);
    gl.uniform3f(uniformLocations.revealColor, 0.24, 0.25, 0.27);
    gl.uniform3fv(
      uniformLocations.outwardOklch,
      new Float32Array([
        0.9, 0.31, 0.4886922,
        0.93, 0.3, 2.5307274,
        0.88, 0.29, 4.4505896,
      ]),
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
      !outwardFramebufferB
    ) return;
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(0, 0, 0, 0);

    // Render the unblurred outward RGB group into texture A.
    gl.bindFramebuffer(gl.FRAMEBUFFER, outwardFramebufferA);
    gl.useProgram(program);
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
    const blurScales = [0.9, 1.1, 1.3, 1.5];
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

  const animatePointer = (timestamp: number) => {
    const elapsed = pointerAnimationTime
      ? Math.min(64, timestamp - pointerAnimationTime)
      : 16;
    pointerAnimationTime = timestamp;

    if (reanchoring) {
      const progress = Math.min(1, (timestamp - reanchorStartedAt) / 3000);
      const weightedProgress = 1 - Math.pow(1 - progress, 3);
      distortionCenter =
        reanchorStartX +
        (targetDistortionCenter - reanchorStartX) * weightedProgress;
      distortionVerticalCenter =
        reanchorStartY +
        (targetDistortionVerticalCenter - reanchorStartY) * weightedProgress;
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

    renderCanvas();
    const unsettled =
      reanchoring ||
      Math.abs(targetDistortionCenter - distortionCenter) > 0.0005 ||
      Math.abs(
        targetDistortionVerticalCenter - distortionVerticalCenter,
      ) > 0.0005;

    if (unsettled) {
      pointerRenderFrame = requestAnimationFrame(animatePointer);
    } else {
      distortionCenter = targetDistortionCenter;
      distortionVerticalCenter = targetDistortionVerticalCenter;
      renderCanvas();
      pointerRenderFrame = null;
      pointerAnimationTime = 0;
    }
  };

  const startPointerAnimation = () => {
    if (pointerRenderFrame === null) {
      pointerAnimationTime = 0;
      pointerRenderFrame = requestAnimationFrame(animatePointer);
    }
  };

  const beginReanchor = () => {
    reanchorStartX = distortionCenter;
    reanchorStartY = distortionVerticalCenter;
    reanchorStartedAt = performance.now();
    reanchoring = true;
    targetDistortionCenter = anchorX;
    targetDistortionVerticalCenter = anchorY;
    reanchorTimeout = null;
    startPointerAnimation();
  };

  const scheduleIdleReanchor = () => {
    if (idleTimeout !== null) clearTimeout(idleTimeout);
    idleTimeout = setTimeout(() => {
      idleTimeout = null;
      pointerInside = false;
      beginReanchor();
    }, reanchorDelay);
  };

  const trackPointer = (event: PointerEvent) => {
    const bounds = titleElement.getBoundingClientRect();
    if (idleTimeout !== null) {
      clearTimeout(idleTimeout);
      idleTimeout = null;
    }
    if (reanchorTimeout !== null) {
      clearTimeout(reanchorTimeout);
      reanchorTimeout = null;
    }
    reanchoring = false;
    const wasInside = pointerInside;
    pointerInside = true;
    const nextX = Math.max(
      0,
      Math.min(1, (event.clientX - bounds.left) / bounds.width),
    );
    const nextY = Math.max(
      0,
      Math.min(1, event.clientY / Math.max(1, window.innerHeight)),
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
    scheduleIdleReanchor();
  };

  const stopTrackingPointer = () => {
    if (!pointerInside && reanchorTimeout !== null) return;
    if (idleTimeout !== null) {
      clearTimeout(idleTimeout);
      idleTimeout = null;
    }
    pointerInside = false;
    const coastX = Math.max(-0.12, Math.min(0.12, pointerVelocityX * 140));
    const coastY = Math.max(-0.1, Math.min(0.1, pointerVelocityY * 140));
    targetDistortionCenter = Math.max(
      0.03,
      Math.min(0.97, targetDistortionCenter + coastX),
    );
    targetDistortionVerticalCenter = Math.max(
      0,
      Math.min(1, targetDistortionVerticalCenter + coastY),
    );
    startPointerAnimation();
    if (reanchorTimeout !== null) clearTimeout(reanchorTimeout);
    reanchorTimeout = setTimeout(beginReanchor, reanchorDelay);
  };

  const handlePointerWindowExit = (event: PointerEvent) => {
    if (event.relatedTarget === null) stopTrackingPointer();
  };

  onMount(() => {
    let active = true;
    try {
      gl = canvas.getContext("webgl2", {
        alpha: true,
        antialias: true,
        premultipliedAlpha: true,
        powerPreference: "high-performance",
      });
      if (!gl) throw new Error("WebGL 2 is unavailable.");
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
      console.error("Range title renderer could not initialize.", error);
      return;
    }

    window.addEventListener("pointermove", trackPointer, { passive: true });
    window.addEventListener("pointerout", handlePointerWindowExit);
    window.addEventListener("blur", stopTrackingPointer);

    const renderWhenReady = async () => {
      await document.fonts.ready;
      if (active) rebuildGlyphTexture();
    };
    void renderWhenReady();

    const resizeObserver = new ResizeObserver(rebuildGlyphTexture);
    resizeObserver.observe(titleElement);

    return () => {
      active = false;
      resizeObserver.disconnect();
      if (pointerRenderFrame !== null) {
        cancelAnimationFrame(pointerRenderFrame);
      }
      if (reanchorTimeout !== null) clearTimeout(reanchorTimeout);
      if (idleTimeout !== null) clearTimeout(idleTimeout);
      window.removeEventListener("pointermove", trackPointer);
      window.removeEventListener("pointerout", handlePointerWindowExit);
      window.removeEventListener("blur", stopTrackingPointer);
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
</script>

<span
  class="rangeTitleWord"
  class:canvasReady
  bind:this={titleElement}
>
  <span class="rangeTitleMeasure">{text}</span>
  <canvas
    class="rangeTitleCanvas"
    bind:this={canvas}
    aria-hidden="true"
  ></canvas>
</span>

<style>
  .rangeTitleWord {
    position: relative;
    isolation: isolate;
    overflow: visible;
    touch-action: none;
    transform: translateX(var(--range-title-ink-shift, 0px));
  }

  .rangeTitleMeasure {
    display: block;
  }

  .canvasReady .rangeTitleMeasure {
    color: transparent;
  }

  .rangeTitleCanvas {
    position: absolute;
    display: block;
    pointer-events: none;
  }
</style>
