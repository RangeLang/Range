export function nextItemGap(nextWidth, extra = 1) {
  return Math.max(0, nextWidth) + Math.max(0, extra);
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
      const gap = nextItemGap(widths[index], 1);
      link.style.setProperty("--spline-gap-before", `${gap.toFixed(2)}px`);
    });
  }
}

if (globalThis.customElements && !customElements.get("range-spline-nav")) {
  customElements.define("range-spline-nav", RangeSplineNav);
}
