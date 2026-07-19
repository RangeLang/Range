function firstVisibleCharacter(element) {
  return element.textContent?.trim().charAt(0) ?? "";
}

class RangeOpticalGuide extends HTMLElement {
  #canvas;
  #context;
  #frame;
  #resizeObserver;
  #shifts = { copy: 0, wordmark: 0 };

  connectedCallback() {
    this.#canvas = document.createElement("canvas");
    this.#context = this.#canvas.getContext("2d");
    this.#resizeObserver = new ResizeObserver(() => this.#schedule());
    const sequence = this.closest(".landingSequence");
    if (sequence) this.#resizeObserver.observe(sequence);
    document.fonts.ready.then(() => this.#schedule());
    this.#schedule();
  }

  disconnectedCallback() {
    if (this.#frame !== undefined) cancelAnimationFrame(this.#frame);
    this.#resizeObserver?.disconnect();
  }

  #schedule() {
    if (this.#frame !== undefined) return;
    this.#frame = requestAnimationFrame(() => {
      this.#frame = undefined;
      this.#align();
    });
  }

  #inkStart(element, appliedShift = 0) {
    const character = firstVisibleCharacter(element);
    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    if (!character || !this.#context) return rect.left - appliedShift;

    this.#context.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    this.#context.fontKerning = style.fontKerning;
    const metrics = this.#context.measureText(character);
    return rect.left - appliedShift - metrics.actualBoundingBoxLeft;
  }

  #align() {
    const sequence = this.closest(".landingSequence");
    const reference = sequence?.querySelector(".rangeTitleWord");
    const wordmark = sequence?.querySelector(".landingWordmark .rangeWord");
    const copy = sequence?.querySelector(".landingHero p");
    if (!sequence || !reference || !wordmark || !copy) return;

    const guide = this.#inkStart(reference);
    const nextShifts = {
      copy: guide - this.#inkStart(copy, this.#shifts.copy),
      wordmark: guide - this.#inkStart(wordmark, this.#shifts.wordmark),
    };

    this.#shifts = nextShifts;
    sequence.style.setProperty("--range-copy-optical-shift", `${nextShifts.copy}px`);
    sequence.style.setProperty("--range-wordmark-optical-shift", `${nextShifts.wordmark}px`);
  }
}

if (!customElements.get("range-optical-guide")) {
  customElements.define("range-optical-guide", RangeOpticalGuide);
}
