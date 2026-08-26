import { createRangeMarks } from "./range-scale-math.js?profile=hover-log-origin-v1";
import { createScaleClickerSound } from "./range-audio-effects.js?profile=audio-effects-v2";

const defaults = {
  endpointGap: 8,
  endpointGapEnd: 16,
  divisionBase: 3,
  divisionLevels: 3,
  markLength: 5,
  markThickness: 0.25,
};

function finiteAttribute(element, name, fallback) {
  const value = Number(element.getAttribute(name));
  return Number.isFinite(value) ? value : fallback;
}

class RangeScale extends HTMLElement {
  static observedAttributes = [
    "endpoint-gap",
    "endpoint-gap-end",
    "division-base",
    "division-levels",
    "mark-length",
    "mark-thickness",
    "orientation",
    "rest-position",
  ];

  #audioContext;
  #audioRequestIndex = 0;
  #canvas;
  #context;
  #colorProbe;
  #focusPosition = 0;
  #focusTarget = 0;
  #focusVelocity = 0;
  #hasHoverSample = false;
  #isHovered = false;
  #lastDetentIndex = 0;
  #lastHoverTime = 0;
  #lastHoverY = 0;
  #lastMotionTime = 0;
  #lastPointerSpeed = 0;
  #motionFrame;
  #resizeObserver;
  #soundRoute;
  #scaleClickerSound;

  #handlePointerEnter = (event) => {
    const bounds = this.getBoundingClientRect();
    this.#hasHoverSample = true;
    this.#lastHoverTime = event.timeStamp;
    this.#lastHoverY = this.#pointerCoordinate(event);
    this.#focusVelocity = 0;
    if (bounds.height > 0) {
      const position = this.#pointerPosition(event, bounds);
      this.#lastDetentIndex = this.#detentIndexFor(position);
    }
    void this.#primeAudio();
  };

  #handlePointerMove = async (event) => {
    const bounds = this.getBoundingClientRect();
    if (bounds.height <= 0) return;
    this.#isHovered = true;
    this.#focusTarget = this.#pointerPosition(event, bounds);
    this.#startMotion();

    const audioReady = this.#primeAudio();
    if (!this.#hasHoverSample) {
      this.#hasHoverSample = true;
      this.#lastHoverY = event.clientY;
      await audioReady;
      return;
    }
    const pointerCoordinate = this.#pointerCoordinate(event);
    const delta = pointerCoordinate - this.#lastHoverY;
    const elapsed = Math.max(8, event.timeStamp - this.#lastHoverTime);
    const pointerSpeed = Math.abs(delta) / elapsed;
    this.#lastPointerSpeed = pointerSpeed;
    this.#lastHoverTime = event.timeStamp;
    this.#lastHoverY = pointerCoordinate;
    const audioRequestIndex = ++this.#audioRequestIndex;
    await audioReady;
    if (audioRequestIndex !== this.#audioRequestIndex) return;
    this.#playRenderedDetent();
  };

  #handlePointerDown = async () => {
    await this.#primeAudio();
    this.#scaleClickerSound?.play(0.18);
  };

  #handlePointerLeave = () => {
    this.#isHovered = false;
    this.#focusTarget = this.#restPosition();
    this.#focusVelocity = 0;
    this.#hasHoverSample = false;
    this.#audioRequestIndex += 1;
    this.#startMotion();
  };

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
  }

  connectedCallback() {
    this.#focusPosition = this.#restPosition();
    this.#focusTarget = this.#restPosition();
    this.#focusVelocity = 0;
    this.#align();
    this.#render();
    this.addEventListener("pointerenter", this.#handlePointerEnter);
    this.addEventListener("pointermove", this.#handlePointerMove);
    this.addEventListener("pointerdown", this.#handlePointerDown);
    this.addEventListener("pointerleave", this.#handlePointerLeave);
    this.#resizeObserver = new ResizeObserver(() => this.#align());
    if (this.hasAttribute("standalone")) this.#resizeObserver.observe(this);
    const sequence = this.parentElement;
    const zero = sequence?.querySelector("[data-scale-zero]");
    const end = sequence?.querySelector("[data-scale-end]");
    const zeroGlyph = zero?.parentElement?.querySelector(".rangeWord");
    const endGlyph = end?.parentElement?.querySelector(".rangeTitleMeasure");
    if (sequence) this.#resizeObserver.observe(sequence);
    if (zero) this.#resizeObserver.observe(zero);
    if (end) this.#resizeObserver.observe(end);
    if (zeroGlyph) this.#resizeObserver.observe(zeroGlyph);
    if (endGlyph) this.#resizeObserver.observe(endGlyph);
    document.fonts.ready.then(() => this.#align());
  }

  disconnectedCallback() {
    this.removeEventListener("pointerenter", this.#handlePointerEnter);
    this.removeEventListener("pointermove", this.#handlePointerMove);
    this.removeEventListener("pointerdown", this.#handlePointerDown);
    this.removeEventListener("pointerleave", this.#handlePointerLeave);
    this.#cancelMotion();
    this.#scaleClickerSound?.dispose();
    this.#soundRoute?.dispose();
    this.#audioContext = undefined;
    this.#soundRoute = undefined;
    this.#scaleClickerSound = undefined;
    this.#resizeObserver?.disconnect();
  }

  attributeChangedCallback() {
    if (!this.isConnected) return;
    this.#render();
    this.#align();
  }

  #config() {
    return {
      endpointGap: Math.max(0, finiteAttribute(this, "endpoint-gap", defaults.endpointGap)),
      endpointGapEnd: Math.max(0, finiteAttribute(this, "endpoint-gap-end", defaults.endpointGapEnd)),
      divisionBase: Math.max(2, Math.round(finiteAttribute(this, "division-base", defaults.divisionBase))),
      divisionLevels: Math.min(6, Math.max(1, Math.round(finiteAttribute(this, "division-levels", defaults.divisionLevels)))),
      markLength: Math.max(1, finiteAttribute(this, "mark-length", defaults.markLength)),
      markThickness: Math.max(0.1, finiteAttribute(this, "mark-thickness", defaults.markThickness)),
    };
  }

  #restPosition() {
    return Math.min(1, Math.max(0, finiteAttribute(this, "rest-position", 0)));
  }

  #isHorizontal() {
    return this.getAttribute("orientation") === "horizontal";
  }

  #pointerCoordinate(event) {
    return this.#isHorizontal() ? event.clientX : event.clientY;
  }

  #pointerPosition(event, bounds) {
    const pointerOffset = this.#isHorizontal()
      ? event.clientX - bounds.left
      : event.clientY - bounds.top;
    const extent = this.#isHorizontal() ? bounds.width : bounds.height;
    const position = Math.min(
      1,
      Math.max(0, pointerOffset / extent),
    );
    return this.hasAttribute("reversed") ? 1 - position : position;
  }

  #detentIndexFor(position, focusPosition = this.#focusPosition) {
    const marks = createRangeMarks({
      ...this.#config(),
      focusPosition,
    });
    let closestIndex = 0;
    let closestDistance = Number.POSITIVE_INFINITY;
    for (let index = 0; index < marks.length; index += 1) {
      const distance = Math.abs(marks[index].position - position);
      if (distance >= closestDistance) continue;
      closestDistance = distance;
      closestIndex = index;
    }
    return closestIndex;
  }

  #playRenderedDetent() {
    if (!this.#isHovered || this.#audioContext?.state !== "running") return;
    const detentIndex = this.#detentIndexFor(
      this.#focusTarget,
      this.#focusPosition,
    );
    if (detentIndex === this.#lastDetentIndex) return;
    this.#lastDetentIndex = detentIndex;
    this.#scaleClickerSound?.play(this.#lastPointerSpeed);
  }

  #render() {
    const config = this.#config();
    const marks = createRangeMarks({
      ...config,
      focusPosition: this.#focusPosition,
    });
    if (!this.#canvas) {
      this.shadowRoot.innerHTML = `<style>:host{display:block;position:absolute;width:48px;pointer-events:auto;cursor:ns-resize}:host([standalone]){position:relative;width:20px;height:28px;contain:layout paint}:host([standalone][orientation="horizontal"]){width:44px;height:14px;cursor:ew-resize}canvas{display:block;width:100%;height:100%}.colorProbe{position:absolute;width:1px;height:1px;opacity:0;pointer-events:none}</style><canvas role="presentation"></canvas><span class="colorProbe" aria-hidden="true"></span>`;
      this.#canvas = this.shadowRoot.querySelector("canvas");
      this.#context = this.#canvas?.getContext("2d");
      this.#colorProbe = this.shadowRoot.querySelector(".colorProbe");
    }
    if (!this.#canvas || !this.#context) return;

    const bounds = this.getBoundingClientRect();
    const width = Math.max(1, bounds.width);
    const height = Math.max(1, bounds.height);
    const pixelRatio = Math.min(8, Math.max(1, globalThis.devicePixelRatio || 1));
    this.#canvas.width = Math.ceil(width * pixelRatio);
    this.#canvas.height = Math.ceil(height * pixelRatio);
    this.#canvas.style.width = `${width}px`;
    this.#canvas.style.height = `${height}px`;
    this.#context.setTransform(1, 0, 0, 1, 0, 0);
    this.#context.clearRect(0, 0, this.#canvas.width, this.#canvas.height);

    const styles = getComputedStyle(this);
    const ink = styles.getPropertyValue("--ink").trim() || "oklch(0.21 0.018 255)";
    if (this.#colorProbe) this.#colorProbe.style.background = ink;
    const color = this.#colorProbe
      ? getComputedStyle(this.#colorProbe).backgroundColor
      : ink;
    const deviceWidth = this.#canvas.width;
    const deviceHeight = this.#canvas.height;
    const horizontal = this.#isHorizontal();
    for (const mark of marks) {
      this.#context.fillStyle = color;
      const markWidth = horizontal
        ? config.markThickness * pixelRatio
        : Math.max(1, Math.round(config.markLength * pixelRatio));
      const markHeight = horizontal
        ? Math.max(1, Math.round(config.markLength * pixelRatio))
        : config.markThickness * pixelRatio;
      const x = horizontal
        ? mark.position * (deviceWidth - markWidth)
        : 0;
      const y = horizontal
        ? (deviceHeight - markHeight) / 2
        : mark.position * (deviceHeight - markHeight);
      this.#context.fillRect(x, y, markWidth, markHeight);
    }
  }

  async #primeAudio() {
    const soundManager = globalThis.__rangeSoundManager;
    if (!soundManager) return;
    const audio = await soundManager.resume();
    if (!audio) return;
    if (this.#audioContext !== audio || !this.#scaleClickerSound) {
      this.#audioContext = audio;
      this.#soundRoute?.dispose();
      this.#soundRoute = soundManager.register("range-scale");
      if (!this.#soundRoute) return;
      this.#scaleClickerSound = createScaleClickerSound(
        audio,
        this.#soundRoute.input,
      );
    }
  }

  #startMotion() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#focusPosition = this.#focusTarget;
      this.#focusVelocity = 0;
      this.#render();
      return;
    }
    if (this.#motionFrame !== undefined) return;
    this.#lastMotionTime = 0;
    this.#motionFrame = requestAnimationFrame((time) => this.#animateMotion(time));
  }

  #cancelMotion() {
    if (this.#motionFrame === undefined) return;
    cancelAnimationFrame(this.#motionFrame);
    this.#motionFrame = undefined;
  }

  #animateMotion(time) {
    const elapsed = this.#lastMotionTime === 0
      ? 1 / 60
      : (time - this.#lastMotionTime) / 1000;
    const deltaTime = Math.min(1 / 30, Math.max(1 / 240, elapsed));
    this.#lastMotionTime = time;

    const spring = this.#isHovered ? 240 : 200;
    const damping = this.#isHovered ? 36 : 32;
    const acceleration = spring * (this.#focusTarget - this.#focusPosition)
      - damping * this.#focusVelocity;
    this.#focusVelocity += acceleration * deltaTime;
    this.#focusPosition = Math.min(
      1,
      Math.max(0, this.#focusPosition + this.#focusVelocity * deltaTime),
    );
    this.#render();
    this.#playRenderedDetent();

    if (
      Math.abs(this.#focusTarget - this.#focusPosition) < 0.0001
      && Math.abs(this.#focusVelocity) < 0.0001
    ) {
      this.#focusPosition = this.#focusTarget;
      this.#focusVelocity = 0;
      this.#motionFrame = undefined;
      this.#render();
      return;
    }

    this.#motionFrame = requestAnimationFrame((nextTime) => this.#animateMotion(nextTime));
  }

  #align() {
    if (this.hasAttribute("standalone")) {
      this.#render();
      return;
    }
    const sequence = this.parentElement;
    const zero = sequence?.querySelector("[data-scale-zero]");
    const end = sequence?.querySelector("[data-scale-end]");
    if (!sequence || !zero || !end) return;
    const zeroGlyph = zero.parentElement?.querySelector(".rangeWord");
    const endGlyph = end.parentElement?.querySelector(".rangeTitleMeasure");

    const config = this.#config();
    const sequenceRect = sequence.getBoundingClientRect();
    const zeroRect = zero.getBoundingClientRect();
    const endRect = end.getBoundingClientRect();
    const startStem = this.#measureLeadingStem(zeroGlyph);
    const endStem = this.#measureLeadingStem(endGlyph);
    const startX = startStem?.left
      ?? zeroRect.left + zeroRect.width / 2;
    const measuredEndX = endStem?.left
      ?? endRect.left + endRect.width / 2;
    const renderedTitleShift = Number.parseFloat(
      getComputedStyle(sequence).getPropertyValue("--range-title-ink-shift"),
    ) || 0;
    const rawEndX = measuredEndX - renderedTitleShift;
    const titleInkShift = startX - rawEndX;
    sequence.style.setProperty(
      "--range-title-ink-shift",
      `${titleInkShift}px`,
    );
    const localStartX = startX - sequenceRect.left;
    const startY = zeroRect.bottom - sequenceRect.top + config.endpointGap;
    const endY = endRect.top - sequenceRect.top - config.endpointGapEnd;

    this.style.left = `${localStartX}px`;
    this.style.top = `${startY}px`;
    this.style.width = `${Math.max(1, config.markLength)}px`;
    this.style.height = `${Math.max(1, endY - startY)}px`;
    this.#render();
  }

  #measureLeadingStem(element) {
    if (!(element instanceof Element)) return undefined;
    const styles = getComputedStyle(element);
    const fontSize = Number.parseFloat(styles.fontSize);
    if (!Number.isFinite(fontSize) || fontSize <= 0) return undefined;
    const scale = 4;
    const canvas = document.createElement("canvas");
    canvas.width = Math.ceil(fontSize * 2 * scale);
    canvas.height = Math.ceil(fontSize * 1.5 * scale);
    const probe = canvas.getContext("2d", { willReadFrequently: true });
    if (!probe) return undefined;
    probe.scale(scale, scale);
    probe.font = [
      styles.fontStyle,
      styles.fontWeight,
      styles.fontSize,
      styles.fontFamily,
    ].join(" ");
    probe.textBaseline = "alphabetic";
    const metrics = probe.measureText("R");
    const padding = fontSize * 0.25;
    const drawX = padding + Math.max(0, metrics.actualBoundingBoxLeft || 0);
    const top = padding;
    const baseline = top + metrics.actualBoundingBoxAscent;
    probe.fillStyle = "black";
    probe.fillText("R", drawX, baseline);

    const pixels = probe.getImageData(
      0,
      0,
      canvas.width,
      canvas.height,
    ).data;
    const firstRuns = [];
    const firstRow = Math.max(
      0,
      Math.floor((top + metrics.actualBoundingBoxAscent * 0.15) * scale),
    );
    const lastRow = Math.min(
      canvas.height - 1,
      Math.ceil((top + metrics.actualBoundingBoxAscent * 0.85) * scale),
    );
    for (let y = firstRow; y <= lastRow; y += 1) {
      let start = -1;
      let end = -1;
      for (let x = 0; x < canvas.width; x += 1) {
        const alpha = pixels[(y * canvas.width + x) * 4 + 3];
        if (alpha >= 64 && start < 0) start = x;
        if (start >= 0 && alpha < 64) {
          end = x;
          break;
        }
      }
      if (start >= 0 && end > start) {
        firstRuns.push({ start, width: end - start });
      }
    }
    if (firstRuns.length === 0) return undefined;
    firstRuns.sort((left, right) => left.width - right.width);
    const stem = firstRuns[Math.floor(firstRuns.length * 0.2)];
    return {
      left:
        element.getBoundingClientRect().left +
        stem.start / scale -
        drawX,
      width: stem.width / scale,
    };
  }
}

if (!customElements.get("range-scale")) {
  customElements.define("range-scale", RangeScale);
}
