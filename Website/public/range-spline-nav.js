export function splinePairGap(leftWidth, rightWidth, {
  minGap = 24,
  maxGap = 42,
  widthFloor = 40,
  widthCeiling = 100,
} = {}) {
  const pairMeasure = Math.sqrt(Math.max(0, leftWidth) * Math.max(0, rightWidth));
  const progress = Math.min(1, Math.max(0, (pairMeasure - widthFloor) / (widthCeiling - widthFloor)));
  const spline = progress * progress * (3 - 2 * progress);
  return minGap + (maxGap - minGap) * spline;
}

const ElementBase = globalThis.HTMLElement ?? class {};

class RangeSplineNav extends ElementBase {
  #resizeObserver;

  connectedCallback() {
    this.#resizeObserver = new ResizeObserver(() => this.#measure());
    this.#resizeObserver.observe(this);
    for (const link of this.querySelectorAll(":scope > a")) this.#resizeObserver.observe(link);
    document.fonts.ready.then(() => this.#measure());
    this.#measure();
  }

  disconnectedCallback() {
    this.#resizeObserver?.disconnect();
  }

  #measure() {
    const links = [...this.querySelectorAll(":scope > a")];
    const widths = links.map((link) => link.getBoundingClientRect().width);
    links.forEach((link, index) => {
      if (index === 0) return;
      const gap = splinePairGap(widths[index - 1], widths[index]);
      link.style.setProperty("--spline-gap-before", `${gap.toFixed(2)}px`);
    });
  }
}

if (globalThis.customElements && !customElements.get("range-spline-nav")) {
  customElements.define("range-spline-nav", RangeSplineNav);
}
