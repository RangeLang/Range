class RangeTypedText extends HTMLElement {
  static observedAttributes = ["delay", "interval", "text"];

  #timer;
  #routeReady;
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

  async collapse() {
    this.#cancel();
    const run = this.#run;
    this.setAttribute("data-collapsing", "");

    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.textContent = "";
      this.removeAttribute("data-collapsing");
      return;
    }

    await new Promise((resolve) => requestAnimationFrame(resolve));
    await new Promise((resolve) => {
      this.#timer = setTimeout(resolve, 180);
    });

    if (run !== this.#run) return;
    this.textContent = "";
    this.removeAttribute("data-collapsing");
  }

  #cancel() {
    this.#run += 1;
    clearTimeout(this.#timer);
    if (this.#routeReady) removeEventListener("range-route-transition-finished", this.#routeReady);
    this.#routeReady = undefined;
    this.removeAttribute("data-typing");
    this.removeAttribute("data-route-pending");
    this.removeAttribute("data-collapsing");
  }

  #start() {
    this.#cancel();
    const run = this.#run;
    const text = this.getAttribute("text") ?? this.textContent ?? "";
    const waitsForRoute = document.documentElement.classList.contains("range-route-performance")
      && document.documentElement.classList.contains("range-route-forward");
    const delay = Math.max(0, Number(this.getAttribute("delay")) || 0);
    const interval = Math.max(1, Number(this.getAttribute("interval")) || 45);
    this.setAttribute("aria-label", text);

    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.textContent = text;
      return;
    }

    const characters = [...text];
    this.textContent = "";

    const typeCharacter = (index) => {
      if (run !== this.#run) return;
      this.textContent = characters.slice(0, index).join("");
      if (index < characters.length) {
        this.#timer = setTimeout(() => typeCharacter(index + 1), interval);
      } else {
        this.removeAttribute("data-typing");
      }
    };

    const begin = (startDelay) => {
      if (run !== this.#run) return;
      this.removeAttribute("data-route-pending");
      this.setAttribute("data-typing", "");
      this.#timer = setTimeout(() => typeCharacter(1), startDelay);
    };

    if (waitsForRoute) {
      this.setAttribute("data-route-pending", "");
      this.#routeReady = () => begin(16);
      addEventListener("range-route-transition-finished", this.#routeReady, { once: true });
    } else {
      begin(delay);
    }
  }
}

if (!customElements.get("range-typed-text")) {
  customElements.define("range-typed-text", RangeTypedText);
}
