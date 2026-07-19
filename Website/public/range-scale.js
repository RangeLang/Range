import { createRangeMarks } from "./range-scale-math.js";

const defaults = {
  endpointGap: 8,
  marks: 51,
  radixBase: 5,
  pinch: 0.27,
  pinchFalloff: 0.12,
  pinchStrength: 0.72,
  measureMinimum: 0.35,
  strokeMinimum: 0.25,
};

function finiteAttribute(element, name, fallback) {
  const value = Number(element.getAttribute(name));
  return Number.isFinite(value) ? value : fallback;
}

class RangeScale extends HTMLElement {
  static observedAttributes = [
    "endpoint-gap",
    "marks",
    "radix-base",
    "pinch",
    "pinch-falloff",
    "pinch-strength",
    "measure-minimum",
    "stroke-minimum",
  ];

  #activePinch;
  #lastReturnTime = 0;
  #resizeObserver;
  #returnFrame;
  #returnVelocity = 0;

  #handlePointerMove = (event) => {
    const bounds = this.getBoundingClientRect();
    if (bounds.height <= 0) return;

    this.#cancelReturn();
    const position = (event.clientY - bounds.top) / bounds.height;
    this.#activePinch = Math.min(0.999999, Math.max(0.000001, position));
    this.#render();
  };

  #handlePointerLeave = () => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#activePinch = this.#config().pinch;
      this.#render();
      return;
    }

    this.#returnVelocity = 0;
    this.#lastReturnTime = 0;
    this.#returnFrame = requestAnimationFrame((time) => this.#returnToOrigin(time));
  };

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
  }

  connectedCallback() {
    this.#activePinch = this.#config().pinch;
    this.#render();
    this.addEventListener("pointermove", this.#handlePointerMove);
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
    this.removeEventListener("pointermove", this.#handlePointerMove);
    this.removeEventListener("pointerleave", this.#handlePointerLeave);
    this.#cancelReturn();
    this.#resizeObserver?.disconnect();
  }

  attributeChangedCallback() {
    if (!this.isConnected) return;
    this.#activePinch = this.#config().pinch;
    this.#render();
    this.#align();
  }

  #config() {
    return {
      endpointGap: Math.max(0, finiteAttribute(this, "endpoint-gap", defaults.endpointGap)),
      marks: Math.max(2, Math.round(finiteAttribute(this, "marks", defaults.marks))),
      radixBase: Math.max(1, Math.round(finiteAttribute(this, "radix-base", defaults.radixBase))),
      pinch: Math.min(1, Math.max(0, finiteAttribute(this, "pinch", defaults.pinch))),
      pinchFalloff: Math.max(0.000001, finiteAttribute(this, "pinch-falloff", defaults.pinchFalloff)),
      pinchStrength: Math.min(0.999999, Math.max(0, finiteAttribute(this, "pinch-strength", defaults.pinchStrength))),
      measureMinimum: Math.min(1, Math.max(0.000001, finiteAttribute(this, "measure-minimum", defaults.measureMinimum))),
      strokeMinimum: Math.min(1, Math.max(0.000001, finiteAttribute(this, "stroke-minimum", defaults.strokeMinimum))),
    };
  }

  #render() {
    const config = this.#config();
    const marks = createRangeMarks({
      ...config,
      pinch: this.#activePinch ?? config.pinch,
    });
    this.shadowRoot.innerHTML = `
      <style>
        :host {
          display: block;
          position: absolute;
          width: 48px;
          pointer-events: auto;
          transform: translateX(-50%);
        }
        i {
          position: absolute;
          top: var(--position);
          left: 50%;
          width: calc(5px * var(--measure));
          height: calc(1px * var(--stroke));
          border-radius: 999px;
          background: var(--line, oklch(0.9 0.012 255));
          transform: translate(-50%, -50%);
        }
        i.radix {
          background: color-mix(
            in oklch,
            var(--muted, oklch(0.58 0.015 255)),
            var(--line, oklch(0.9 0.012 255)) 42%
          );
        }
      </style>
      ${marks.map((mark) => (
        `<i class="${mark.isRadix ? "radix" : "normal"}" style="--measure:${mark.measure};--stroke:${mark.stroke};--position:${mark.position * 100}%"></i>`
      )).join("")}
    `;
  }

  #cancelReturn() {
    if (this.#returnFrame === undefined) return;
    cancelAnimationFrame(this.#returnFrame);
    this.#returnFrame = undefined;
  }

  #returnToOrigin(time) {
    const target = this.#config().pinch;
    const current = this.#activePinch ?? target;
    const elapsed = this.#lastReturnTime === 0 ? 1 / 60 : (time - this.#lastReturnTime) / 1000;
    const deltaTime = Math.min(1 / 30, Math.max(1 / 240, elapsed));
    this.#lastReturnTime = time;

    const spring = 180;
    const damping = 14;
    const acceleration = spring * (target - current) - damping * this.#returnVelocity;
    this.#returnVelocity += acceleration * deltaTime;
    this.#activePinch = Math.min(0.999999, Math.max(
      0.000001,
      current + this.#returnVelocity * deltaTime,
    ));
    this.#render();

    if (Math.abs(target - this.#activePinch) < 0.0001 && Math.abs(this.#returnVelocity) < 0.0001) {
      this.#activePinch = target;
      this.#returnVelocity = 0;
      this.#returnFrame = undefined;
      this.#render();
      return;
    }

    this.#returnFrame = requestAnimationFrame((nextTime) => this.#returnToOrigin(nextTime));
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
    const endY = endRect.top - sequenceRect.top - endpointGap;

    this.style.left = `${startX}px`;
    this.style.top = `${startY}px`;
    this.style.height = `${Math.max(1, endY - startY)}px`;
  }
}

if (!customElements.get("range-scale")) {
  customElements.define("range-scale", RangeScale);
}
