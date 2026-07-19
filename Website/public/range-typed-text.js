class RangeTypedText extends HTMLElement {
  static observedAttributes = ["delay", "interval", "text"];

  #timer;
  #run = 0;

  connectedCallback() {
    this.#start();
  }

  disconnectedCallback() {
    this.#cancel();
  }

  attributeChangedCallback() {
    if (this.isConnected) this.#start();
  }

  #cancel() {
    this.#run += 1;
    clearTimeout(this.#timer);
    this.removeAttribute("data-typing");
  }

  #start() {
    this.#cancel();
    const run = this.#run;
    const text = this.getAttribute("text") ?? this.textContent ?? "";
    const delay = Math.max(0, Number(this.getAttribute("delay")) || 0);
    const interval = Math.max(1, Number(this.getAttribute("interval")) || 45);
    this.setAttribute("aria-label", text);

    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.textContent = text;
      return;
    }

    const characters = [...text];
    this.textContent = "";
    this.setAttribute("data-typing", "");

    const typeCharacter = (index) => {
      if (run !== this.#run) return;
      this.textContent = characters.slice(0, index).join("");
      if (index < characters.length) {
        this.#timer = setTimeout(() => typeCharacter(index + 1), interval);
      } else {
        this.removeAttribute("data-typing");
      }
    };

    this.#timer = setTimeout(() => typeCharacter(1), delay);
  }
}

if (!customElements.get("range-typed-text")) {
  customElements.define("range-typed-text", RangeTypedText);
}
