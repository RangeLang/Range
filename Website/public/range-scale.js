import { createRangeMarks } from "./range-scale-math.js?profile=spherical-10";

const defaults = {
  endpointGap: 8,
  divisionBase: 3,
  divisionLevels: 3,
  pinch: 0.27,
  pinchCore: 10,
  pinchFalloff: 0.16,
  pinchInnerEdge: 0.68,
  pinchStrength: 0.9,
  measureMinimum: 0.35,
  strokeMinimum: 0.25,
  toneFalloff: 0.12,
  toneIntensity: 0.82,
};

function finiteAttribute(element, name, fallback) {
  const value = Number(element.getAttribute(name));
  return Number.isFinite(value) ? value : fallback;
}

class RangeScale extends HTMLElement {
  static observedAttributes = [
    "endpoint-gap",
    "division-base",
    "division-levels",
    "pinch",
    "pinch-core",
    "pinch-falloff",
    "pinch-inner-edge",
    "pinch-strength",
    "measure-minimum",
    "stroke-minimum",
    "tone-falloff",
    "tone-intensity",
  ];

  #activePinch;
  #isPointerActive = false;
  #lastMotionTime = 0;
  #motionFrame;
  #motionTarget;
  #motionVelocity = 0;
  #resizeObserver;

  #setPointerTarget = (event) => {
    const bounds = this.getBoundingClientRect();
    if (bounds.height <= 0) return;

    const position = (event.clientY - bounds.top) / bounds.height;
    this.#isPointerActive = true;
    this.#motionTarget = Math.min(0.999999, Math.max(0.000001, position));
    this.#startMotion();
  };

  #handlePointerLeave = () => {
    this.#isPointerActive = false;
    this.#motionTarget = this.#config().pinch;
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
    this.#activePinch = this.#config().pinch;
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
    this.#activePinch = this.#config().pinch;
    this.#motionTarget = this.#activePinch;
    this.#render();
    this.#align();
  }

  #config() {
    return {
      endpointGap: Math.max(0, finiteAttribute(this, "endpoint-gap", defaults.endpointGap)),
      divisionBase: Math.max(2, Math.round(finiteAttribute(this, "division-base", defaults.divisionBase))),
      divisionLevels: Math.min(6, Math.max(1, Math.round(finiteAttribute(this, "division-levels", defaults.divisionLevels)))),
      pinch: Math.min(1, Math.max(0, finiteAttribute(this, "pinch", defaults.pinch))),
      pinchCore: Math.max(0, finiteAttribute(this, "pinch-core", defaults.pinchCore)),
      pinchFalloff: Math.max(0.000001, finiteAttribute(this, "pinch-falloff", defaults.pinchFalloff)),
      pinchInnerEdge: Math.min(1, Math.max(0, finiteAttribute(this, "pinch-inner-edge", defaults.pinchInnerEdge))),
      pinchStrength: Math.min(0.999999, Math.max(0, finiteAttribute(this, "pinch-strength", defaults.pinchStrength))),
      measureMinimum: Math.min(1, Math.max(0.000001, finiteAttribute(this, "measure-minimum", defaults.measureMinimum))),
      strokeMinimum: Math.min(1, Math.max(0.000001, finiteAttribute(this, "stroke-minimum", defaults.strokeMinimum))),
      toneFalloff: Math.max(0.000001, finiteAttribute(this, "tone-falloff", defaults.toneFalloff)),
      toneIntensity: Math.min(1, Math.max(0, finiteAttribute(this, "tone-intensity", defaults.toneIntensity))),
    };
  }

  #render() {
    const config = this.#config();
    const marks = createRangeMarks({
      ...config,
      pinch: this.#activePinch ?? config.pinch,
      pinchCoreRadius: config.pinchCore / (2 * Math.max(1, this.getBoundingClientRect().height)),
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
          width: calc(1px * var(--measure));
          height: calc(1px * var(--stroke));
          border-radius: 999px;
          background: color-mix(
            in oklch,
            var(--line, oklch(0.9 0.012 255)),
            white var(--lighten)
          );
          opacity: var(--opacity);
          transform: translate(-50%, -50%);
        }
        i.division,
        i.major {
          background: color-mix(
            in oklch,
            color-mix(
              in oklch,
              var(--muted, oklch(0.58 0.015 255)),
              var(--line, oklch(0.9 0.012 255)) 42%
            ),
            white var(--lighten)
          );
        }
      </style>
      ${marks.map((mark) => (
        `<i class="${mark.tier}" style="--measure:${mark.measure};--stroke:${mark.stroke};--lighten:${mark.tone * config.toneIntensity * 100}%;--opacity:${mark.opacity};--position:${mark.position * 100}%"></i>`
      )).join("")}
    `;
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
    const endY = endRect.top - sequenceRect.top - endpointGap;

    this.style.left = `${startX}px`;
    this.style.top = `${startY}px`;
    this.style.height = `${Math.max(1, endY - startY)}px`;
  }
}

if (!customElements.get("range-scale")) {
  customElements.define("range-scale", RangeScale);
}
