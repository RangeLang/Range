import { createRangeMarks } from "./range-scale-math.js?profile=hover-log-origin-v1";

const defaults = {
  endpointGap: 8,
  endpointGapEnd: 16,
  divisionBase: 3,
  divisionLevels: 3,
  markLength: 5,
  markThickness: 0.25,
};

function finiteAttribute(element, name, fallback) {
  const value = Number(element.getAttribute(name));
  return Number.isFinite(value) ? value : fallback;
}

class RangeScale extends HTMLElement {
  static observedAttributes = [
    "endpoint-gap",
    "endpoint-gap-end",
    "division-base",
    "division-levels",
    "mark-length",
    "mark-thickness",
  ];

  #audioContext;
  #audioRequestIndex = 0;
  #bristleBuffer;
  #canvas;
  #clickCompressor;
  #clickIndex = 0;
  #clickOutput;
  #context;
  #colorProbe;
  #focusPosition = 0;
  #focusTarget = 0;
  #focusVelocity = 0;
  #hasHoverSample = false;
  #hoverDistance = 0;
  #isHovered = false;
  #lastHoverTime = 0;
  #lastHoverY = 0;
  #lastMotionTime = 0;
  #motionFrame;
  #nextClickTime = 0;
  #resizeObserver;

  #handlePointerEnter = (event) => {
    this.#hasHoverSample = true;
    this.#hoverDistance = 0;
    this.#lastHoverTime = event.timeStamp;
    this.#lastHoverY = event.clientY;
    this.#focusVelocity = 0;
    this.#nextClickTime = 0;
    void this.#primeAudio();
  };

  #handlePointerMove = async (event) => {
    const bounds = this.getBoundingClientRect();
    if (bounds.height <= 0) return;
    this.#isHovered = true;
    this.#focusTarget = Math.min(
      1,
      Math.max(0, (event.clientY - bounds.top) / bounds.height),
    );
    this.#startMotion();

    const audioReady = this.#primeAudio();
    if (!this.#hasHoverSample) {
      this.#hasHoverSample = true;
      this.#lastHoverY = event.clientY;
      await audioReady;
      return;
    }
    const delta = event.clientY - this.#lastHoverY;
    const elapsed = Math.max(8, event.timeStamp - this.#lastHoverTime);
    const pointerSpeed = Math.abs(delta) / elapsed;
    this.#lastHoverTime = event.timeStamp;
    this.#lastHoverY = event.clientY;
    const fastMovement = Math.min(
      1,
      Math.max(0, (pointerSpeed - 0.18) / 0.62),
    );
    const transientLevel = 1 - fastMovement * 0.55;
    this.#hoverDistance += Math.abs(delta);
    const clickCount = Math.min(6, Math.floor(this.#hoverDistance / 3.2));
    if (clickCount === 0) return;
    this.#hoverDistance %= 3.2;
    const direction = Math.sign(delta);
    const speedAttenuation = Math.min(0.32, Math.abs(delta) / 120);
    const intensity = Math.max(0.26, 0.58 - speedAttenuation);
    const audioRequestIndex = ++this.#audioRequestIndex;
    await audioReady;
    if (audioRequestIndex !== this.#audioRequestIndex) return;
    this.#playClick(direction, intensity, transientLevel);
  };

  #handlePointerDown = async () => {
    await this.#primeAudio();
    this.#nextClickTime = 0;
    this.#playClick(1, 0.58, 1);
  };

  #handlePointerLeave = () => {
    this.#isHovered = false;
    this.#focusTarget = 0;
    this.#focusVelocity = 0;
    this.#hasHoverSample = false;
    this.#hoverDistance = 0;
    this.#audioRequestIndex += 1;
    this.#nextClickTime = 0;
    this.#startMotion();
  };

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
  }

  connectedCallback() {
    this.#focusPosition = 0;
    this.#focusTarget = 0;
    this.#focusVelocity = 0;
    this.#align();
    this.#render();
    this.addEventListener("pointerenter", this.#handlePointerEnter);
    this.addEventListener("pointermove", this.#handlePointerMove);
    this.addEventListener("pointerdown", this.#handlePointerDown);
    this.addEventListener("pointerleave", this.#handlePointerLeave);
    this.#resizeObserver = new ResizeObserver(() => this.#align());
    const sequence = this.parentElement;
    const zero = sequence?.querySelector("[data-scale-zero]");
    const end = sequence?.querySelector("[data-scale-end]");
    if (sequence) this.#resizeObserver.observe(sequence);
    if (zero) this.#resizeObserver.observe(zero);
    if (end) this.#resizeObserver.observe(end);
    document.fonts.ready.then(() => this.#align());
  }

  disconnectedCallback() {
    this.removeEventListener("pointerenter", this.#handlePointerEnter);
    this.removeEventListener("pointermove", this.#handlePointerMove);
    this.removeEventListener("pointerdown", this.#handlePointerDown);
    this.removeEventListener("pointerleave", this.#handlePointerLeave);
    this.#cancelMotion();
    void this.#audioContext?.close();
    this.#audioContext = undefined;
    this.#bristleBuffer = undefined;
    this.#clickCompressor = undefined;
    this.#clickOutput = undefined;
    this.#nextClickTime = 0;
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
      endpointGapEnd: Math.max(0, finiteAttribute(this, "endpoint-gap-end", defaults.endpointGapEnd)),
      divisionBase: Math.max(2, Math.round(finiteAttribute(this, "division-base", defaults.divisionBase))),
      divisionLevels: Math.min(6, Math.max(1, Math.round(finiteAttribute(this, "division-levels", defaults.divisionLevels)))),
      markLength: Math.max(1, finiteAttribute(this, "mark-length", defaults.markLength)),
      markThickness: Math.max(0.1, finiteAttribute(this, "mark-thickness", defaults.markThickness)),
    };
  }

  #render() {
    const config = this.#config();
    const marks = createRangeMarks({
      ...config,
      focusPosition: this.#focusPosition,
    });
    if (!this.#canvas) {
      this.shadowRoot.innerHTML = `<style>:host{display:block;position:absolute;width:48px;pointer-events:auto;cursor:ns-resize;transform:translateX(-50%)}canvas{display:block;width:100%;height:100%}.colorProbe{position:absolute;width:1px;height:1px;opacity:0;pointer-events:none}</style><canvas role="presentation"></canvas><span class="colorProbe" aria-hidden="true"></span>`;
      this.#canvas = this.shadowRoot.querySelector("canvas");
      this.#context = this.#canvas?.getContext("2d");
      this.#colorProbe = this.shadowRoot.querySelector(".colorProbe");
    }
    if (!this.#canvas || !this.#context) return;

    const bounds = this.getBoundingClientRect();
    const width = Math.max(1, bounds.width);
    const height = Math.max(1, bounds.height);
    const pixelRatio = Math.min(8, Math.max(1, globalThis.devicePixelRatio || 1));
    this.#canvas.width = Math.ceil(width * pixelRatio);
    this.#canvas.height = Math.ceil(height * pixelRatio);
    this.#canvas.style.width = `${width}px`;
    this.#canvas.style.height = `${height}px`;
    this.#context.setTransform(1, 0, 0, 1, 0, 0);
    this.#context.clearRect(0, 0, this.#canvas.width, this.#canvas.height);

    const styles = getComputedStyle(this);
    const ink = styles.getPropertyValue("--ink").trim() || "oklch(0.21 0.018 255)";
    if (this.#colorProbe) this.#colorProbe.style.background = ink;
    const color = this.#colorProbe
      ? getComputedStyle(this.#colorProbe).backgroundColor
      : ink;
    const deviceWidth = this.#canvas.width;
    const deviceHeight = this.#canvas.height;
    for (const mark of marks) {
      this.#context.fillStyle = color;
      const markWidth = Math.max(1, Math.round(config.markLength * pixelRatio));
      const markHeight = config.markThickness * pixelRatio;
      const x = Math.round(deviceWidth / 2 - markWidth / 2);
      const y = mark.position * (deviceHeight - markHeight);
      this.#context.fillRect(x, y, markWidth, markHeight);
    }
  }

  async #primeAudio() {
    const AudioContextConstructor = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextConstructor) return;
    if (!this.#audioContext) {
      this.#audioContext = new AudioContextConstructor();
      this.#clickCompressor = this.#audioContext.createDynamicsCompressor();
      this.#clickCompressor.threshold.value = -12;
      this.#clickCompressor.knee.value = 2;
      this.#clickCompressor.ratio.value = 8;
      this.#clickCompressor.attack.value = 0.0005;
      this.#clickCompressor.release.value = 0.03;
      this.#clickOutput = this.#audioContext.createGain();
      this.#clickOutput.gain.value = 1.15;
      this.#clickCompressor.connect(this.#clickOutput);
      this.#clickOutput.connect(this.#audioContext.destination);
      const frameCount = Math.ceil(this.#audioContext.sampleRate * 0.008);
      this.#bristleBuffer = this.#audioContext.createBuffer(
        1,
        frameCount,
        this.#audioContext.sampleRate,
      );
      const channel = this.#bristleBuffer.getChannelData(0);
      for (let index = 0; index < channel.length; index += 1) {
        const envelope = Math.pow(1 - index / channel.length, 4);
        channel[index] = (Math.random() * 2 - 1) * envelope;
      }
    }
    if (this.#audioContext.state === "suspended") {
      await this.#audioContext.resume();
    }
  }

  #playClick(direction, intensity, transientLevel) {
    const audio = this.#audioContext;
    if (
      !audio
      || audio.state !== "running"
      || !this.#bristleBuffer
      || !this.#clickCompressor
    ) return;

    const clickIndex = this.#clickIndex;
    const intervalVariation = ((((clickIndex * 5) % 7) - 3) * 0.004);
    const minimumClickInterval = 0.06 + intervalVariation;
    if (audio.currentTime < this.#nextClickTime) return;
    const time = audio.currentTime;
    this.#nextClickTime = time + minimumClickInterval;
    this.#clickIndex += 1;
    const variation = (((clickIndex * 7) % 11) - 5) / 5;
    const duration = 0.0062 + (variation + 1) * 0.0007;

    const bristle = audio.createBufferSource();
    const filter = audio.createBiquadFilter();
    const bristleGain = audio.createGain();
    bristle.buffer = this.#bristleBuffer;
    bristle.playbackRate.value = 1 + variation * 0.05;
    filter.type = "bandpass";
    filter.frequency.value = 3_200 + variation * 420 + direction * 70;
    filter.Q.value = 0.7;
    const peakGain = (0.11 + intensity * 0.035) * transientLevel;
    bristleGain.gain.setValueAtTime(0.0001, time);
    bristleGain.gain.linearRampToValueAtTime(
      peakGain,
      time + 0.00035,
    );
    bristleGain.gain.exponentialRampToValueAtTime(
      0.0001,
      time + duration,
    );
    bristle.connect(filter);
    filter.connect(bristleGain);
    bristleGain.connect(this.#clickCompressor);
    bristle.start(
      time,
      (clickIndex * 0.0007) % 0.003,
      duration,
    );
    bristle.stop(time + duration);
  }

  #startMotion() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#focusPosition = this.#focusTarget;
      this.#focusVelocity = 0;
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
    const elapsed = this.#lastMotionTime === 0
      ? 1 / 60
      : (time - this.#lastMotionTime) / 1000;
    const deltaTime = Math.min(1 / 30, Math.max(1 / 240, elapsed));
    this.#lastMotionTime = time;

    const spring = this.#isHovered ? 240 : 200;
    const damping = this.#isHovered ? 36 : 32;
    const acceleration = spring * (this.#focusTarget - this.#focusPosition)
      - damping * this.#focusVelocity;
    this.#focusVelocity += acceleration * deltaTime;
    this.#focusPosition = Math.min(
      1,
      Math.max(0, this.#focusPosition + this.#focusVelocity * deltaTime),
    );
    this.#render();

    if (
      Math.abs(this.#focusTarget - this.#focusPosition) < 0.0001
      && Math.abs(this.#focusVelocity) < 0.0001
    ) {
      this.#focusPosition = this.#focusTarget;
      this.#focusVelocity = 0;
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

    const config = this.#config();
    const sequenceRect = sequence.getBoundingClientRect();
    const zeroRect = zero.getBoundingClientRect();
    const endRect = end.getBoundingClientRect();
    const startX = zeroRect.left + zeroRect.width / 2 - sequenceRect.left;
    const startY = zeroRect.bottom - sequenceRect.top + config.endpointGap;
    const endY = endRect.top - sequenceRect.top - config.endpointGapEnd;

    this.style.left = `${startX}px`;
    this.style.top = `${startY}px`;
    this.style.height = `${Math.max(1, endY - startY)}px`;
  }
}

if (!customElements.get("range-scale")) {
  customElements.define("range-scale", RangeScale);
}
