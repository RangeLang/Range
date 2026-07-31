const learnedTimingWeights = Object.freeze({
  alternateHand: -0.12,
  sameHand: 0.08,
  sameFinger: 0.3,
  repeatedKey: 0.18,
  keyTravel: 0.045,
  uppercase: 0.16,
  wordBoundary: 0.2,
  punctuation: 0.72,
  commonDigraph: -0.16,
  burstMomentum: 0.17,
});

const commonDigraphs = new Set([
  "th", "he", "in", "er", "an", "re", "on", "at", "en", "nd", "ti", "es",
  "or", "te", "of", "ed", "is", "it", "al", "ar", "st", "to", "nt", "ng",
]);

const keyboardProfiles = new Map();
[
  ["qwertyuiop", 0, 0.25, ["l5", "l4", "l3", "l2", "l2", "r2", "r2", "r3", "r4", "r5"]],
  ["asdfghjkl", 1, 0.5, ["l5", "l4", "l3", "l2", "l2", "r2", "r2", "r3", "r4"]],
  ["zxcvbnm", 2, 1, ["l5", "l4", "l3", "l2", "r2", "r2", "r3"]],
].forEach(([keys, row, offset, fingers]) => {
  [...keys].forEach((key, index) => {
    const finger = fingers[index];
    keyboardProfiles.set(key, {
      row,
      x: index + offset,
      finger,
      hand: finger[0],
    });
  });
});
keyboardProfiles.set(" ", { row: 3, x: 4.75, finger: "thumb", hand: "thumb" });

let typingAudioContext;
let typingNoiseBuffer;
let typingAudioOutput;
let typingAudioUnlocked = false;

function getTypingAudioContext() {
  if (typingAudioContext) return typingAudioContext;
  const AudioContextConstructor = window.AudioContext ?? window.webkitAudioContext;
  if (!AudioContextConstructor) return undefined;
  typingAudioContext = new AudioContextConstructor();
  return typingAudioContext;
}

async function unlockTypingAudio() {
  const context = getTypingAudioContext();
  if (!context) return;
  await context.resume();
  typingAudioUnlocked = context.state === "running";
  if (typingAudioUnlocked) {
    removeEventListener("pointerdown", unlockTypingAudio, true);
    removeEventListener("keydown", unlockTypingAudio, true);
  }
}

addEventListener("pointerdown", unlockTypingAudio, { capture: true, once: false });
addEventListener("keydown", unlockTypingAudio, { capture: true, once: false });

function typingNoise(context) {
  if (typingNoiseBuffer) return typingNoiseBuffer;
  const sampleCount = Math.ceil(context.sampleRate * 0.035);
  typingNoiseBuffer = context.createBuffer(1, sampleCount, context.sampleRate);
  const samples = typingNoiseBuffer.getChannelData(0);
  let noiseState = 0x51f15e;
  for (let index = 0; index < samples.length; index += 1) {
    noiseState = (noiseState * 1664525 + 1013904223) >>> 0;
    samples[index] = (noiseState / 0xffffffff) * 2 - 1;
  }
  return typingNoiseBuffer;
}

function typingOutput(context) {
  if (typingAudioOutput) return typingAudioOutput;
  const smoothingFilter = context.createBiquadFilter();
  const compressor = context.createDynamicsCompressor();
  const outputGain = context.createGain();
  smoothingFilter.type = "lowpass";
  smoothingFilter.frequency.value = 3600;
  smoothingFilter.Q.value = 0.45;
  compressor.threshold.value = -30;
  compressor.knee.value = 10;
  compressor.ratio.value = 8;
  compressor.attack.value = 0.003;
  compressor.release.value = 0.08;
  outputGain.gain.value = 1;
  smoothingFilter.connect(compressor).connect(outputGain).connect(context.destination);
  typingAudioOutput = smoothingFilter;
  return typingAudioOutput;
}

function playSynthesizedKey(character, articulation) {
  const context = typingAudioContext;
  if (!typingAudioUnlocked || !context || context.state !== "running") return;
  const now = context.currentTime;
  const isSpace = character === " ";
  const isPunctuation = /[.,;:!?]/.test(character);
  const duration = 0.038 * articulation.durationScale;
  const transient = context.createBufferSource();
  const transientFilter = context.createBiquadFilter();
  const transientGain = context.createGain();
  const panner = context.createStereoPanner?.();
  transient.buffer = typingNoise(context);
  transientFilter.type = "bandpass";
  transientFilter.frequency.value =
    (isSpace ? 900 : isPunctuation ? 2250 : 1550) * articulation.brightness;
  transientFilter.Q.value = 0.58;
  transientGain.gain.setValueAtTime(0.0001, now);
  transientGain.gain.exponentialRampToValueAtTime(
    (isSpace ? 0.005 : 0.008) * articulation.velocity,
    now + 0.004,
  );
  transientGain.gain.exponentialRampToValueAtTime(0.0001, now + duration);
  transient.connect(transientFilter).connect(transientGain);
  if (panner) {
    panner.pan.value = articulation.pan;
    transientGain.connect(panner).connect(typingOutput(context));
  } else {
    transientGain.connect(typingOutput(context));
  }
  transient.start(now);
  transient.stop(now + duration + 0.006);

  const body = context.createOscillator();
  const bodyGain = context.createGain();
  body.type = "sine";
  body.frequency.value = isSpace ? 94 : 118 + (character.charCodeAt(0) % 17);
  bodyGain.gain.setValueAtTime(0.0001, now);
  bodyGain.gain.exponentialRampToValueAtTime(
    0.0024 * articulation.velocity,
    now + 0.005,
  );
  bodyGain.gain.exponentialRampToValueAtTime(
    0.0001,
    now + 0.03 * articulation.durationScale,
  );
  body.connect(bodyGain);
  if (panner) {
    bodyGain.connect(panner);
  } else {
    bodyGain.connect(typingOutput(context));
  }
  body.start(now);
  body.stop(now + 0.036 * articulation.durationScale);
}

function seedFromText(text) {
  let seed = 2166136261;
  for (const character of text) {
    seed ^= character.codePointAt(0);
    seed = Math.imul(seed, 16777619);
  }
  return seed >>> 0;
}

class RangeTypedText extends HTMLElement {
  static observedAttributes = ["delay", "interval", "text"];

  #timer;
  #run = 0;
  #randomState = 1;
  #burstMomentum = 0;
  #pendingArticulation = {
    velocity: 0.82,
    brightness: 0.94,
    durationScale: 1,
    pan: 0,
  };

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
    const content = document.createElement("span");
    content.setAttribute("data-collapse-content", "");
    content.textContent = this.textContent;
    this.textContent = "";
    this.append(content);
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
    this.removeAttribute("data-typing");
    this.removeAttribute("data-collapsing");
  }

  #start() {
    this.#cancel();
    const run = this.#run;
    const text = this.getAttribute("text") ?? this.textContent ?? "";
    const delay = Math.max(0, Number(this.getAttribute("delay")) || 0);
    const interval = Math.max(1, Number(this.getAttribute("interval")) || 45);
    this.#randomState = seedFromText(text) || 1;
    this.#burstMomentum = 0;
    this.#pendingArticulation = {
      velocity: 0.82,
      brightness: 0.94,
      durationScale: 1,
      pan: 0,
    };
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
      const emittedCharacter = characters[index - 1];
      playSynthesizedKey(emittedCharacter, this.#pendingArticulation);
      if (index < characters.length) {
        const nextStroke = this.#learnedStroke(
          emittedCharacter,
          characters[index],
          interval,
        );
        this.#pendingArticulation = nextStroke.articulation;
        this.#timer = setTimeout(
          () => typeCharacter(index + 1),
          nextStroke.delay,
        );
      } else {
        this.removeAttribute("data-typing");
      }
    };

    const begin = (startDelay) => {
      if (run !== this.#run) return;
      this.setAttribute("data-typing", "");
      this.#timer = setTimeout(() => typeCharacter(1), startDelay);
    };

    begin(delay);
  }

  #random() {
    let state = this.#randomState;
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    this.#randomState = state >>> 0;
    return this.#randomState / 0xffffffff;
  }

  #learnedStroke(previousCharacter, nextCharacter, baseInterval) {
    const previous = previousCharacter.toLowerCase();
    const next = nextCharacter.toLowerCase();
    const previousProfile = keyboardProfiles.get(previous);
    const nextProfile = keyboardProfiles.get(next);
    const commonDigraph = commonDigraphs.has(previous + next);
    const sameFinger =
      previousProfile &&
      nextProfile &&
      previousProfile.finger === nextProfile.finger;
    let multiplier = 1;

    if (previousProfile && nextProfile) {
      if (previousProfile.hand !== nextProfile.hand) {
        multiplier += learnedTimingWeights.alternateHand;
      } else if (previousProfile.hand !== "thumb") {
        multiplier += learnedTimingWeights.sameHand;
      }
      if (sameFinger) {
        multiplier += learnedTimingWeights.sameFinger;
      }
      multiplier +=
        Math.hypot(
          previousProfile.x - nextProfile.x,
          previousProfile.row - nextProfile.row,
        ) * learnedTimingWeights.keyTravel;
    }

    if (previous === next) multiplier += learnedTimingWeights.repeatedKey;
    if (nextCharacter !== next) multiplier += learnedTimingWeights.uppercase;
    if (previous === " " || next === " ") multiplier += learnedTimingWeights.wordBoundary;
    if (/[.,;:!?]/.test(previousCharacter)) multiplier += learnedTimingWeights.punctuation;
    if (commonDigraph) multiplier += learnedTimingWeights.commonDigraph;

    const burstNoise = (this.#random() + this.#random() - 1) * 0.48;
    this.#burstMomentum = this.#burstMomentum * 0.72 + burstNoise * 0.28;
    multiplier += this.#burstMomentum * learnedTimingWeights.burstMomentum;

    const delay = Math.round(
      Math.max(baseInterval * 0.48, Math.min(baseInterval * 3.2, baseInterval * multiplier)),
    );
    const hand = nextProfile?.hand;
    const travel =
      previousProfile && nextProfile
        ? Math.hypot(
            previousProfile.x - nextProfile.x,
            previousProfile.row - nextProfile.row,
          )
        : 0;

    return {
      delay,
      articulation: {
        velocity: Math.max(
          0.66,
          Math.min(
            0.98,
            0.84 +
              (sameFinger ? 0.06 : 0) -
              (commonDigraph ? 0.08 : 0) +
              Math.min(0.05, travel * 0.008),
          ),
        ),
        brightness: Math.max(
          0.78,
          Math.min(
            1.12,
            0.96 + (nextProfile ? (1 - nextProfile.row) * 0.035 : 0) -
              (commonDigraph ? 0.05 : 0),
          ),
        ),
        durationScale:
          (commonDigraph ? 0.84 : 1) *
          (sameFinger ? 1.12 : 1) *
          (/[.,;:!?]/.test(nextCharacter) ? 1.18 : 1),
        pan: hand === "l" ? -0.16 : hand === "r" ? 0.16 : 0,
      },
    };
  }
}

if (!customElements.get("range-typed-text")) {
  customElements.define("range-typed-text", RangeTypedText);
}
