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
  #shifts = {
    actionEnd: 0,
    copy: 0,
    copyY: 0,
    lowerScaleX: 0,
    lowerScaleY: 0,
  };

  connectedCallback() {
    this.#canvas = document.createElement("canvas");
    this.#context = this.#canvas.getContext("2d");
    this.#resizeObserver = new ResizeObserver(() => this.#schedule());
    const sequence = this.closest("[data-range-home-page]");
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

  #leadingInkCenter(element, appliedShift = 0) {
    const character = firstVisibleCharacter(element);
    const rect = element.getBoundingClientRect();
    if (!character || !this.#context) {
      return rect.left - appliedShift + rect.width / 2;
    }
    const style = getComputedStyle(element);
    this.#context.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    this.#context.fontKerning = style.fontKerning;
    const metrics = this.#context.measureText(character);
    const inkStart =
      rect.left - appliedShift - metrics.actualBoundingBoxLeft;
    const inkWidth =
      metrics.actualBoundingBoxLeft + metrics.actualBoundingBoxRight;
    return inkStart + inkWidth / 2;
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

  #titleInkBounds(element) {
    const character = firstVisibleCharacter(element);
    if (!character || !this.#context) {
      const rect = element.getBoundingClientRect();
      return { top: rect.top, leadingBottom: rect.bottom };
    }
    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    this.#context.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    this.#context.fontKerning = style.fontKerning;
    const titleMetrics = this.#context.measureText(element.textContent?.trim() ?? "");
    const leadingMetrics = this.#context.measureText(character);
    const inkHeight =
      titleMetrics.actualBoundingBoxAscent +
      titleMetrics.actualBoundingBoxDescent;
    const top = rect.top + (rect.height - inkHeight) / 2;
    const baseline = top + titleMetrics.actualBoundingBoxAscent;
    return {
      top,
      bottom: top + inkHeight,
      leadingBottom: baseline + leadingMetrics.actualBoundingBoxDescent,
    };
  }

  #textInkBounds(element) {
    if (!this.#context) return element.getBoundingClientRect();
    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    this.#context.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    this.#context.fontKerning = style.fontKerning;
    const metrics = this.#context.measureText(element.textContent?.trim() ?? "");
    const height =
      metrics.actualBoundingBoxAscent + metrics.actualBoundingBoxDescent;
    const top = rect.top + (rect.height - height) / 2;
    return { top, bottom: top + height };
  }

  #align() {
    const sequence = this.closest("[data-range-home-page]");
    const reference = sequence?.querySelector(".rangeTitleWord");
    const wordmark = sequence?.querySelector(".landingWordmark .rangeWord");
    const copy = sequence?.querySelector(".landingHero p");
    const github = sequence?.querySelector(".secondaryAction");
    const upperScale = sequence?.querySelector(":scope > range-scale");
    const lowerScale = sequence?.querySelector(".landingLowerScale");
    const lowerScaleMarks = lowerScale?.querySelector("range-scale");
    if (
      !sequence ||
      !reference ||
      !wordmark ||
      !copy ||
      !github ||
      !upperScale ||
      !lowerScale ||
      !lowerScaleMarks
    ) return;

    const guide = upperScale.getBoundingClientRect().left;
    const titleInk = this.#titleInkBounds(reference);
    const wordmarkInk = this.#textInkBounds(wordmark);
    const copyInk = this.#textInkBounds(copy);
    const upperScaleRect = upperScale.getBoundingClientRect();
    const outerGap = Math.max(
      0,
      upperScaleRect.top - wordmarkInk.bottom,
    );
    const upperGap = Math.max(
      0,
      titleInk.top - upperScaleRect.bottom,
    );
    const lowerScaleRect = lowerScale.getBoundingClientRect();
    const lowerScaleMarksRect = lowerScaleMarks.getBoundingClientRect();
    const lowerScaleX =
      guide - (lowerScaleRect.left - this.#shifts.lowerScaleX);
    const lowerScaleY =
      titleInk.leadingBottom +
      upperGap -
      (lowerScaleRect.top - this.#shifts.lowerScaleY);
    const projectedLowerScaleBottom =
      lowerScaleRect.bottom - this.#shifts.lowerScaleY + lowerScaleY;
    const projectedLowerScaleCenter =
      lowerScaleMarksRect.left -
      this.#shifts.lowerScaleX +
      lowerScaleX +
      lowerScaleMarksRect.width / 2;
    const copyShift =
      projectedLowerScaleCenter -
      this.#leadingInkCenter(copy, this.#shifts.copy);
    const copyEnd = this.#inkEnd(copy, this.#shifts.copy) + copyShift;
    const nextShifts = {
      actionEnd: copyEnd - this.#inkEnd(github, this.#shifts.actionEnd),
      copy: copyShift,
      copyY:
        projectedLowerScaleBottom +
        outerGap -
        (copyInk.top - this.#shifts.copyY),
      lowerScaleX,
      lowerScaleY,
    };

    this.#shifts = nextShifts;
    sequence.style.setProperty("--range-actions-end-shift", `${nextShifts.actionEnd}px`);
    sequence.style.setProperty("--range-copy-optical-shift", `${nextShifts.copy}px`);
    sequence.style.setProperty("--range-copy-vertical-shift", `${nextShifts.copyY}px`);
    sequence.style.setProperty("--range-lower-scale-x", `${nextShifts.lowerScaleX}px`);
    sequence.style.setProperty("--range-lower-scale-y", `${nextShifts.lowerScaleY}px`);
  }
}

if (!customElements.get("range-optical-guide")) {
  customElements.define("range-optical-guide", RangeOpticalGuide);
}
