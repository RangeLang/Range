import { createRangeMarks } from "./range-scale-math.js?profile=zero-drag-v1";

const defaults = {
  endpointGap: 8,
  endpointGapEnd: 16,
  divisionBase: 3,
  divisionLevels: 3,
  markLength: 5,
  markThickness: 0.25,
  zeroDragFalloff: 0.38,
  zeroDragLimit: 0.42,
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
    "zero-drag-falloff",
    "zero-drag-limit",
  ];

  #activeZeroDrag = 0;
  #canvas;
  #context;
  #colorProbe;
  #didDrag = false;
  #dragStartPosition = 0;
  #dragStartY = 0;
  #isPointerActive = false;
  #lastMotionTime = 0;
  #motionFrame;
  #motionTarget = 0;
  #motionVelocity = 0;
  #pointerId;
  #resizeObserver;
  #zero;

  #handlePointerDown = (event) => {
    if (event.button !== 0 || !this.#zero) return;
    event.preventDefault();
    event.stopPropagation();
    this.#pointerId = event.pointerId;
    this.#dragStartY = event.clientY;
    this.#dragStartPosition = this.#activeZeroDrag;
    this.#didDrag = false;
    this.#isPointerActive = true;
    this.#motionVelocity = 0;
    this.#zero.setPointerCapture(event.pointerId);
  };

  #handlePointerMove = (event) => {
    if (event.pointerId !== this.#pointerId) return;
    event.preventDefault();
    const height = Math.max(1, this.getBoundingClientRect().height);
    const distance = event.clientY - this.#dragStartY;
    if (Math.abs(distance) > 2) this.#didDrag = true;
    this.#motionTarget = Math.min(
      this.#config().zeroDragLimit,
      Math.max(0, this.#dragStartPosition + distance / height),
    );
    this.#startMotion();
  };

  #handlePointerEnd = (event) => {
    if (event.pointerId !== this.#pointerId) return;
    this.#pointerId = undefined;
    this.#isPointerActive = false;
    this.#motionTarget = 0;
    this.#startMotion();
  };

  #handleZeroClick = (event) => {
    if (!this.#didDrag) return;
    event.preventDefault();
    event.stopPropagation();
    this.#didDrag = false;
  };

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
  }

  connectedCallback() {
    this.#activeZeroDrag = 0;
    this.#motionTarget = 0;
    this.#bindZero();
    this.#align();
    this.#render();
    this.#resizeObserver = new ResizeObserver(() => this.#align());
    const sequence = this.parentElement;
    const end = sequence?.querySelector("[data-scale-end]");
    if (sequence) this.#resizeObserver.observe(sequence);
    if (this.#zero) this.#resizeObserver.observe(this.#zero);
    if (end) this.#resizeObserver.observe(end);
    document.fonts.ready.then(() => this.#align());
  }

  disconnectedCallback() {
    this.#unbindZero();
    this.#cancelMotion();
    this.#resizeObserver?.disconnect();
  }

  attributeChangedCallback() {
    if (!this.isConnected) return;
    this.#activeZeroDrag = 0;
    this.#motionTarget = 0;
    this.#motionVelocity = 0;
    this.#render();
    this.#align();
  }

  #bindZero() {
    this.#unbindZero();
    this.#zero = this.parentElement?.querySelector("[data-scale-zero]");
    if (!this.#zero) return;
    this.#zero.addEventListener("pointerdown", this.#handlePointerDown);
    this.#zero.addEventListener("pointermove", this.#handlePointerMove);
    this.#zero.addEventListener("pointerup", this.#handlePointerEnd);
    this.#zero.addEventListener("pointercancel", this.#handlePointerEnd);
    this.#zero.addEventListener("lostpointercapture", this.#handlePointerEnd);
    this.#zero.addEventListener("click", this.#handleZeroClick, true);
  }

  #unbindZero() {
    if (!this.#zero) return;
    this.#zero.removeEventListener("pointerdown", this.#handlePointerDown);
    this.#zero.removeEventListener("pointermove", this.#handlePointerMove);
    this.#zero.removeEventListener("pointerup", this.#handlePointerEnd);
    this.#zero.removeEventListener("pointercancel", this.#handlePointerEnd);
    this.#zero.removeEventListener("lostpointercapture", this.#handlePointerEnd);
    this.#zero.removeEventListener("click", this.#handleZeroClick, true);
    this.#zero.style.removeProperty("--range-zero-drag-y");
    this.#zero = undefined;
  }

  #config() {
    return {
      endpointGap: Math.max(0, finiteAttribute(this, "endpoint-gap", defaults.endpointGap)),
      endpointGapEnd: Math.max(0, finiteAttribute(this, "endpoint-gap-end", defaults.endpointGapEnd)),
      divisionBase: Math.max(2, Math.round(finiteAttribute(this, "division-base", defaults.divisionBase))),
      divisionLevels: Math.min(6, Math.max(1, Math.round(finiteAttribute(this, "division-levels", defaults.divisionLevels)))),
      markLength: Math.max(1, finiteAttribute(this, "mark-length", defaults.markLength)),
      markThickness: Math.max(0.1, finiteAttribute(this, "mark-thickness", defaults.markThickness)),
      zeroDragFalloff: Math.min(1, Math.max(0.000001, finiteAttribute(this, "zero-drag-falloff", defaults.zeroDragFalloff))),
      zeroDragLimit: Math.min(0.8, Math.max(0, finiteAttribute(this, "zero-drag-limit", defaults.zeroDragLimit))),
    };
  }

  #render() {
    const config = this.#config();
    const marks = createRangeMarks({ ...config, zeroDrag: this.#activeZeroDrag });
    if (!this.#canvas) {
      this.shadowRoot.innerHTML = `<style>:host{display:block;position:absolute;width:48px;pointer-events:none;transform:translateX(-50%)}canvas{display:block;width:100%;height:100%}.colorProbe{position:absolute;width:1px;height:1px;opacity:0;pointer-events:none}</style><canvas role="presentation"></canvas><span class="colorProbe" aria-hidden="true"></span>`;
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
    for (const mark of marks) {
      this.#context.fillStyle = color;
      const markWidth = Math.max(1, Math.round(config.markLength * pixelRatio));
      const markHeight = config.markThickness * pixelRatio;
      const x = Math.round(deviceWidth / 2 - markWidth / 2);
      const y = mark.position * (deviceHeight - markHeight);
      this.#context.fillRect(x, y, markWidth, markHeight);
    }

    this.#applyZeroTransform();
  }

  #applyZeroTransform() {
    if (!this.#zero) return;
    const height = Math.max(1, this.getBoundingClientRect().height);
    this.#zero.style.setProperty(
      "--range-zero-drag-y",
      `${this.#activeZeroDrag * height}px`,
    );
  }

  #startMotion() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#activeZeroDrag = this.#motionTarget;
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
    const target = this.#motionTarget;
    const current = this.#activeZeroDrag;
    const elapsed = this.#lastMotionTime === 0 ? 1 / 60 : (time - this.#lastMotionTime) / 1000;
    const deltaTime = Math.min(1 / 30, Math.max(1 / 240, elapsed));
    this.#lastMotionTime = time;

    const spring = this.#isPointerActive ? 280 : 190;
    const damping = this.#isPointerActive ? 34 : 18;
    const acceleration = spring * (target - current) - damping * this.#motionVelocity;
    this.#motionVelocity += acceleration * deltaTime;
    this.#activeZeroDrag = Math.min(
      this.#config().zeroDragLimit,
      Math.max(0, current + this.#motionVelocity * deltaTime),
    );
    this.#render();

    if (Math.abs(target - this.#activeZeroDrag) < 0.0001 && Math.abs(this.#motionVelocity) < 0.0001) {
      this.#activeZeroDrag = target;
      this.#motionVelocity = 0;
      this.#motionFrame = undefined;
      this.#render();
      return;
    }

    this.#motionFrame = requestAnimationFrame((nextTime) => this.#animateMotion(nextTime));
  }

  #align() {
    const sequence = this.parentElement;
    const zero = this.#zero ?? sequence?.querySelector("[data-scale-zero]");
    const end = sequence?.querySelector("[data-scale-end]");
    if (!sequence || !zero || !end) return;

    const config = this.#config();
    const sequenceRect = sequence.getBoundingClientRect();
    const zeroRect = zero.getBoundingClientRect();
    const endRect = end.getBoundingClientRect();
    const currentHeight = Math.max(1, this.getBoundingClientRect().height);
    const dragPixels = this.#activeZeroDrag * currentHeight;
    const startX = zeroRect.left + zeroRect.width / 2 - sequenceRect.left;
    const startY = zeroRect.bottom - dragPixels - sequenceRect.top + config.endpointGap;
    const endY = endRect.top - sequenceRect.top - config.endpointGapEnd;

    this.style.left = `${startX}px`;
    this.style.top = `${startY}px`;
    this.style.height = `${Math.max(1, endY - startY)}px`;
    this.#applyZeroTransform();
  }
}

if (!customElements.get("range-scale")) {
  customElements.define("range-scale", RangeScale);
}
