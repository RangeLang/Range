import { createLogarithmicMarks } from "./range-log-scale-math.js";

const defaults = {
  base: 10,
  endpointGap: 8,
  marks: 18,
  pinch: 0.27,
  pinchDistance: 0.006,
  pinchGrowth: 1.8,
  pinchMarks: 5,
};

function finiteAttribute(element, name, fallback) {
  const value = Number(element.getAttribute(name));
  return Number.isFinite(value) ? value : fallback;
}

class RangeLogScale extends HTMLElement {
  static observedAttributes = [
    "base",
    "endpoint-gap",
    "marks",
    "pinch",
    "pinch-distance",
    "pinch-growth",
    "pinch-marks",
  ];

  #resizeObserver;

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
  }

  connectedCallback() {
    this.#render();
    this.#resizeObserver = new ResizeObserver(() => this.#align());
    const sequence = this.parentElement;
    const zero = sequence?.querySelector("[data-log-zero]");
    const one = sequence?.querySelector("[data-log-one]");
    if (sequence) this.#resizeObserver.observe(sequence);
    if (zero) this.#resizeObserver.observe(zero);
    if (one) this.#resizeObserver.observe(one);
    document.fonts.ready.then(() => this.#align());
    this.#align();
  }

  disconnectedCallback() {
    this.#resizeObserver?.disconnect();
  }

  attributeChangedCallback() {
    if (!this.isConnected) return;
    this.#render();
    this.#align();
  }

  #config() {
    const pinchMarks = Math.max(1, Math.round(finiteAttribute(this, "pinch-marks", defaults.pinchMarks)));
    return {
      base: Math.max(1.000001, finiteAttribute(this, "base", defaults.base)),
      endpointGap: Math.max(0, finiteAttribute(this, "endpoint-gap", defaults.endpointGap)),
      marks: Math.max(2, Math.round(finiteAttribute(this, "marks", defaults.marks))),
      pinch: Math.min(1, Math.max(0, finiteAttribute(this, "pinch", defaults.pinch))),
      pinchDistance: Math.max(0.000001, finiteAttribute(this, "pinch-distance", defaults.pinchDistance)),
      pinchGrowth: Math.max(1.000001, finiteAttribute(this, "pinch-growth", defaults.pinchGrowth)),
      pinchMarks: pinchMarks % 2 === 0 ? pinchMarks + 1 : pinchMarks,
    };
  }

  #render() {
    const marks = createLogarithmicMarks(this.#config());
    this.shadowRoot.innerHTML = `
      <style>
        :host {
          display: block;
          position: absolute;
          width: 1px;
          pointer-events: none;
        }
        i {
          position: absolute;
          top: var(--position);
          left: 50%;
          width: 5px;
          height: 1px;
          border-radius: 999px;
          background: var(--line, oklch(0.9 0.012 255));
          transform: translate(-50%, -50%);
        }
        i.radix {
          width: 9px;
          background: color-mix(
            in oklch,
            var(--muted, oklch(0.58 0.015 255)),
            var(--line, oklch(0.9 0.012 255)) 42%
          );
        }
      </style>
      ${marks.map((mark) => (
        `<i class="${mark.isRadix ? "radix" : "normal"}" style="--position:${mark.position * 100}%"></i>`
      )).join("")}
    `;
  }

  #align() {
    const sequence = this.parentElement;
    const zero = sequence?.querySelector("[data-log-zero]");
    const one = sequence?.querySelector("[data-log-one]");
    if (!sequence || !zero || !one) return;

    const { endpointGap } = this.#config();
    const sequenceRect = sequence.getBoundingClientRect();
    const zeroRect = zero.getBoundingClientRect();
    const oneRect = one.getBoundingClientRect();
    const startX = zeroRect.left + zeroRect.width / 2 - sequenceRect.left;
    const startY = zeroRect.bottom - sequenceRect.top + endpointGap;
    const endY = oneRect.top - sequenceRect.top - endpointGap;

    this.style.left = `${startX}px`;
    this.style.top = `${startY}px`;
    this.style.height = `${Math.max(1, endY - startY)}px`;
  }
}

if (!customElements.get("range-log-scale")) {
  customElements.define("range-log-scale", RangeLogScale);
}
