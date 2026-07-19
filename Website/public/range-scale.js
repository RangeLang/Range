import { createRangeMarks } from "./range-scale-math.js";

const defaults = {
  endpointGap: 8,
  marks: 18,
  pinch: 0.27,
  pinchFalloff: 0.12,
  pinchStrength: 0.72,
  measurePeak: 2.95,
};

function finiteAttribute(element, name, fallback) {
  const value = Number(element.getAttribute(name));
  return Number.isFinite(value) ? value : fallback;
}

class RangeScale extends HTMLElement {
  static observedAttributes = [
    "endpoint-gap",
    "marks",
    "pinch",
    "pinch-falloff",
    "pinch-strength",
    "measure-peak",
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
    const zero = sequence?.querySelector("[data-scale-zero]");
    const one = sequence?.querySelector("[data-scale-one]");
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
    return {
      endpointGap: Math.max(0, finiteAttribute(this, "endpoint-gap", defaults.endpointGap)),
      marks: Math.max(2, Math.round(finiteAttribute(this, "marks", defaults.marks))),
      pinch: Math.min(1, Math.max(0, finiteAttribute(this, "pinch", defaults.pinch))),
      pinchFalloff: Math.max(0.000001, finiteAttribute(this, "pinch-falloff", defaults.pinchFalloff)),
      pinchStrength: Math.min(0.999999, Math.max(0, finiteAttribute(this, "pinch-strength", defaults.pinchStrength))),
      measurePeak: Math.max(1, finiteAttribute(this, "measure-peak", defaults.measurePeak)),
    };
  }

  #render() {
    const marks = createRangeMarks(this.#config());
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
          width: calc(5px * var(--measure));
          height: 1px;
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
        `<i class="${mark.isRadix ? "radix" : "normal"}" style="--measure:${mark.measure};--position:${mark.position * 100}%"></i>`
      )).join("")}
    `;
  }

  #align() {
    const sequence = this.parentElement;
    const zero = sequence?.querySelector("[data-scale-zero]");
    const one = sequence?.querySelector("[data-scale-one]");
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

if (!customElements.get("range-scale")) {
  customElements.define("range-scale", RangeScale);
}
