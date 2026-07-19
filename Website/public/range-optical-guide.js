function firstVisibleCharacter(element) {
  return element.textContent?.trim().charAt(0) ?? "";
}

function lastVisibleTextNode(element) {
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
  let node;
  let last;
  while ((node = walker.nextNode())) {
    if (node.data.trim().length > 0) last = node;
  }
  return last;
}

class RangeOpticalGuide extends HTMLElement {
  #canvas;
  #context;
  #frame;
  #resizeObserver;
  #shifts = { actionEnd: 0, copy: 0, wordmark: 0 };

  connectedCallback() {
    this.#canvas = document.createElement("canvas");
    this.#context = this.#canvas.getContext("2d");
    this.#resizeObserver = new ResizeObserver(() => this.#schedule());
    const sequence = this.closest(".landingSequence");
    if (sequence) this.#resizeObserver.observe(sequence);
    document.fonts.ready.then(() => this.#schedule());
    this.#align();
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

  #inkEnd(element, appliedShift = 0) {
    const node = lastVisibleTextNode(element);
    const end = node?.data.trimEnd().length ?? 0;
    if (!node || end === 0 || !this.#context) {
      return element.getBoundingClientRect().right - appliedShift;
    }

    const range = document.createRange();
    range.setStart(node, end - 1);
    range.setEnd(node, end);
    const rect = range.getBoundingClientRect();
    const style = getComputedStyle(element);
    this.#context.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    this.#context.fontKerning = style.fontKerning;
    const metrics = this.#context.measureText(node.data.charAt(end - 1));
    return rect.left - appliedShift + metrics.actualBoundingBoxRight;
  }

  #align() {
    const sequence = this.closest(".landingSequence");
    const reference = sequence?.querySelector(".rangeTitleWord");
    const wordmark = sequence?.querySelector(".landingWordmark .rangeWord");
    const copy = sequence?.querySelector(".landingHero p");
    const github = sequence?.querySelector(".secondaryAction");
    if (!sequence || !reference || !wordmark || !copy || !github) return;

    const guide = this.#inkStart(reference);
    const copyShift = guide - this.#inkStart(copy, this.#shifts.copy);
    const copyEnd = this.#inkEnd(copy, this.#shifts.copy) + copyShift;
    const nextShifts = {
      actionEnd: copyEnd - this.#inkEnd(github, this.#shifts.actionEnd),
      copy: copyShift,
      wordmark: guide - this.#inkStart(wordmark, this.#shifts.wordmark),
    };

    this.#shifts = nextShifts;
    sequence.style.setProperty("--range-actions-end-shift", `${nextShifts.actionEnd}px`);
    sequence.style.setProperty("--range-copy-optical-shift", `${nextShifts.copy}px`);
    sequence.style.setProperty("--range-wordmark-optical-shift", `${nextShifts.wordmark}px`);
  }
}

if (!customElements.get("range-optical-guide")) {
  customElements.define("range-optical-guide", RangeOpticalGuide);
}
