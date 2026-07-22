import { createRangeMarks, snapScalePosition } from "./range-scale-math.js?profile=width-pinch-v1";

const defaults = {
  endpointGap: 8,
  endpointGapEnd: 16,
  divisionBase: 3,
  divisionLevels: 3,
  markLength: 5,
  markThickness: 0.25,
  pinch: 0.27,
  pinchFalloff: 0.16,
  pinchStrength: 0.9,
  snapHysteresis: 0.08,
  snapToMarks: true,
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
    "pinch",
    "pinch-falloff",
    "pinch-strength",
    "snap-hysteresis",
    "snap-to-marks",
  ];

  #activePinch;
  #canvas;
  #context;
  #colorProbe;
  #isPointerActive = false;
  #lastMotionTime = 0;
  #motionFrame;
  #motionTarget;
  #motionVelocity = 0;
  #resizeObserver;
  #snappedIndex;

  #setPointerTarget = (event) => {
    const bounds = this.getBoundingClientRect();
    if (bounds.height <= 0) return;

    const position = (event.clientY - bounds.top) / bounds.height;
    this.#isPointerActive = true;
    this.#motionTarget = this.#snapTarget(Math.min(1, Math.max(0, position)));
    this.#startMotion();
  };

  #handlePointerLeave = () => {
    this.#isPointerActive = false;
    this.#snappedIndex = undefined;
    this.#motionTarget = this.#snapTarget(this.#config().pinch, false);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#activePinch = this.#motionTarget;
      this.#render();
      return;
    }

    this.#startMotion();
  };

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
  }

  connectedCallback() {
    this.#snappedIndex = undefined;
    this.#activePinch = this.#snapTarget(this.#config().pinch, false);
    this.#motionTarget = this.#activePinch;
    this.#align();
    this.#render();
    this.addEventListener("pointerenter", this.#setPointerTarget);
    this.addEventListener("pointermove", this.#setPointerTarget);
    this.addEventListener("pointerleave", this.#handlePointerLeave);
    this.#resizeObserver = new ResizeObserver(() => this.#align());
    const sequence = this.parentElement;
    const zero = sequence?.querySelector("[data-scale-zero]");
    const end = sequence?.querySelector("[data-scale-end]");
    if (sequence) this.#resizeObserver.observe(sequence);
    if (zero) this.#resizeObserver.observe(zero);
    if (end) this.#resizeObserver.observe(end);
    document.fonts.ready.then(() => this.#align());
    this.#align();
  }

  disconnectedCallback() {
    this.removeEventListener("pointerenter", this.#setPointerTarget);
    this.removeEventListener("pointermove", this.#setPointerTarget);
    this.removeEventListener("pointerleave", this.#handlePointerLeave);
    this.#cancelMotion();
    this.#resizeObserver?.disconnect();
  }

  attributeChangedCallback() {
    if (!this.isConnected) return;
    this.#snappedIndex = undefined;
    this.#activePinch = this.#snapTarget(this.#config().pinch, false);
    this.#motionTarget = this.#activePinch;
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
      pinch: Math.min(1, Math.max(0, finiteAttribute(this, "pinch", defaults.pinch))),
      pinchFalloff: Math.max(0.000001, finiteAttribute(this, "pinch-falloff", defaults.pinchFalloff)),
      pinchStrength: Math.min(0.999999, Math.max(0, finiteAttribute(this, "pinch-strength", defaults.pinchStrength))),
      snapHysteresis: Math.min(0.499999, Math.max(0, finiteAttribute(this, "snap-hysteresis", defaults.snapHysteresis))),
      snapToMarks: this.getAttribute("snap-to-marks") !== "false",
    };
  }

  #snapTarget(position, preserveIndex = true) {
    const config = this.#config();
    if (!config.snapToMarks) return position;
    const snapped = snapScalePosition(position, {
      divisionBase: config.divisionBase,
      divisionLevels: config.divisionLevels,
      hysteresis: config.snapHysteresis,
      previousIndex: preserveIndex ? this.#snappedIndex : undefined,
    });
    this.#snappedIndex = snapped.index;
    return snapped.position;
  }

  #render() {
    const config = this.#config();
    const marks = createRangeMarks({ ...config, pinch: this.#activePinch ?? config.pinch });
    if (!this.#canvas) {
      this.shadowRoot.innerHTML = `<style>:host{display:block;position:absolute;width:48px;pointer-events:auto;transform:translateX(-50%)}canvas{display:block;width:100%;height:100%}.colorProbe{position:absolute;width:1px;height:1px;opacity:0;pointer-events:none}</style><canvas role="presentation"></canvas><span class="colorProbe" aria-hidden="true"></span>`;
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
    for (const mark of marks) {
      if (this.#colorProbe) this.#colorProbe.style.background = ink;
      this.#context.strokeStyle = this.#colorProbe
        ? getComputedStyle(this.#colorProbe).backgroundColor
        : ink;
      this.#context.fillStyle = this.#context.strokeStyle;
      const deviceWidth = this.#canvas.width;
      const deviceHeight = this.#canvas.height;
      const markWidth = Math.max(1, Math.round(config.markLength * mark.width * pixelRatio));
      const markHeight = config.markThickness * pixelRatio;
      const x = Math.round(deviceWidth / 2 - markWidth / 2);
      const y = mark.position * (deviceHeight - markHeight);
      this.#context.fillRect(x, y, markWidth, markHeight);
    }
  }

  #startMotion() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#activePinch = this.#motionTarget;
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
    const target = this.#motionTarget ?? this.#config().pinch;
    const current = this.#activePinch ?? target;
    const elapsed = this.#lastMotionTime === 0 ? 1 / 60 : (time - this.#lastMotionTime) / 1000;
    const deltaTime = Math.min(1 / 30, Math.max(1 / 240, elapsed));
    this.#lastMotionTime = time;

    const spring = this.#isPointerActive ? 240 : 180;
    const damping = this.#isPointerActive ? 28 : 14;
    const acceleration = spring * (target - current) - damping * this.#motionVelocity;
    this.#motionVelocity += acceleration * deltaTime;
    this.#activePinch = Math.min(0.999999, Math.max(
      0.000001,
      current + this.#motionVelocity * deltaTime,
    ));
    this.#render();

    if (Math.abs(target - this.#activePinch) < 0.0001 && Math.abs(this.#motionVelocity) < 0.0001) {
      this.#activePinch = target;
      this.#motionVelocity = 0;
      this.#motionFrame = undefined;
      this.#render();
      return;
    }

    this.#motionFrame = requestAnimationFrame((nextTime) => this.#animateMotion(nextTime));
  }

  #align() {
    const sequence = this.parentElement;
    const zero = sequence?.querySelector("[data-scale-zero]");
    const end = sequence?.querySelector("[data-scale-end]");
    if (!sequence || !zero || !end) return;

    const { endpointGap } = this.#config();
    const sequenceRect = sequence.getBoundingClientRect();
    const zeroRect = zero.getBoundingClientRect();
    const endRect = end.getBoundingClientRect();
    const startX = zeroRect.left + zeroRect.width / 2 - sequenceRect.left;
    const startY = zeroRect.bottom - sequenceRect.top + endpointGap;
    const endY = endRect.top - sequenceRect.top - this.#config().endpointGapEnd;

    this.style.left = `${startX}px`;
    this.style.top = `${startY}px`;
    this.style.height = `${Math.max(1, endY - startY)}px`;
  }
}

if (!customElements.get("range-scale")) {
  customElements.define("range-scale", RangeScale);
}
