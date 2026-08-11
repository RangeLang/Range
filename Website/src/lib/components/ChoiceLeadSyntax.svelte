<script lang="ts">
  import { getContext, onMount } from "svelte";
  import {
    RANGE_RHYTHM_SUBDIVISION_MS,
    RANGE_SOUND_MANAGER_CONTEXT,
    type RangeSoundManager,
  } from "$lib/audio/sound-manager";

  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );
  let {
    choices = ["String", "Message", "Error"],
    frequencies = [329.63, 277.18, 293.66],
    noteNames = "mi · do♯ · re",
    timbre = "lead",
    stepSubdivisions = 2,
    cycleSubdivisions = 6,
    offsets,
    score,
    scaleRatios,
    complement = false,
    ring = 0,
  }: {
    choices?: string[];
    frequencies?: number[];
    noteNames?: string;
    timbre?: "lead" | "gamelan" | "ice";
    stepSubdivisions?: number;
    cycleSubdivisions?: number;
    offsets?: number[];
    score?: readonly (readonly [token: number, degree: number, step: number])[];
    scaleRatios?: readonly number[];
    complement?: boolean;
    ring?: number;
  } = $props();
  let display: HTMLDivElement;

  onMount(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const soundRoute = soundManager?.register("choice-lead", timbre === "ice" ? 0.76 : 0.72);
    const routeGain = soundRoute?.audioContext.createGain();
    if (routeGain && soundRoute) {
      routeGain.gain.value = 0.0001;
      routeGain.connect(soundRoute.input);
    }
    const tokens = Array.from(
      display.querySelectorAll<HTMLElement>("[data-choice-index]"),
    );
    let noteTimers: number[] = [];
    let phrase = 0;

    const playLead = (index: number, frequencyOverride?: number) => {
      if (!soundRoute || !soundManager?.isEnabled()) return;
      const audio = soundRoute.audioContext;
      const now = audio.currentTime;
      const main = audio.createOscillator();
      const round = audio.createOscillator();
      const crystal = audio.createOscillator();
      const filter = audio.createBiquadFilter();
      const compressor = audio.createDynamicsCompressor();
      const crystalGain = audio.createGain();
      const motionDepth = audio.createGain();
      const motion = audio.createOscillator();
      const gain = audio.createGain();
      const gamelan = timbre === "gamelan";
      const frequency = frequencyOverride ?? frequencies[index];
      const phraseAccent = [0.72, 0.9, 0.78, 1][phrase % 4];
      const noteAccent = [1, 0.76, 0.88][index % 3];
      const amplitude = (complement ? 0.105 : 0.17)
        * Math.log1p(4 * phraseAccent * noteAccent) / Math.log(5);
      main.type = gamelan ? "triangle" : "sine";
      round.type = "sine";
      crystal.type = timbre === "ice" ? "sine" : "triangle";
      main.frequency.setValueAtTime(frequency, now);
      round.frequency.setValueAtTime(
        frequency * (timbre === "ice" ? 0.5 : gamelan ? 1.014 : 1.003),
        now,
      );
      crystal.frequency.setValueAtTime(
        frequency * (timbre === "ice" ? 4.01 : gamelan ? 2.73 : 3.012),
        now,
      );
      crystalGain.gain.setValueAtTime(
        timbre === "ice" ? 0.072 : gamelan ? (complement ? 0.042 : 0.065) : 0.038,
        now,
      );
      crystalGain.gain.exponentialRampToValueAtTime(
        0.0001,
        now + (timbre === "ice" ? 0.48 : 0.085),
      );
      motion.type = "sine";
      motion.frequency.setValueAtTime(timbre === "ice" ? 39 : 6.2, now);
      motionDepth.gain.setValueAtTime(timbre === "ice" ? 42 : 18, now);
      motion.connect(motionDepth).connect(filter.frequency);
      filter.type = "bandpass";
      filter.frequency.setValueAtTime(
        timbre === "ice" ? 4_800 : frequency * (gamelan ? 2.35 : 1.55),
        now,
      );
      filter.frequency.exponentialRampToValueAtTime(
        timbre === "ice" ? 1_900 : frequency * (gamelan ? 1.42 : 1.08),
        now + (timbre === "ice" ? 0.32 : 0.21),
      );
      filter.Q.setValueAtTime(timbre === "ice" ? 7 : gamelan ? 6.2 : 3.8 + ring * 1.4, now);
      compressor.threshold.value = -31;
      compressor.knee.value = 20;
      compressor.ratio.value = 3;
      compressor.attack.value = 0.018;
      compressor.release.value = 0.28;
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.linearRampToValueAtTime(
        amplitude,
        now + (timbre === "ice" ? 0.006 : complement ? 0.018 : 0.004),
      );
      gain.gain.exponentialRampToValueAtTime(amplitude * 0.17, now + 0.14);
      gain.gain.exponentialRampToValueAtTime(
        0.0001,
        now + (timbre === "ice" ? 0.82 : 0.58 + ring * 0.38),
      );
      main.connect(filter);
      round.connect(filter);
      crystal.connect(crystalGain).connect(filter);
      filter.connect(compressor).connect(gain).connect(routeGain ?? soundRoute.input);
      if (timbre === "ice") {
        const delay = audio.createDelay(0.8);
        const feedback = audio.createGain();
        const frostFilter = audio.createBiquadFilter();
        delay.delayTime.setValueAtTime(0.225, now);
        feedback.gain.setValueAtTime(0.28, now);
        frostFilter.type = "highpass";
        frostFilter.frequency.setValueAtTime(2_400, now);
        gain.connect(delay).connect(frostFilter).connect(feedback);
        feedback.connect(delay);
        feedback.connect(routeGain ?? soundRoute.input);
      } else {
        const bounce = audio.createDelay(0.5);
        const bounceFilter = audio.createBiquadFilter();
        const bounceGain = audio.createGain();
        bounce.delayTime.setValueAtTime(gamelan ? 0.15 : 0.18, now);
        bounceFilter.type = "lowpass";
        bounceFilter.frequency.setValueAtTime(gamelan ? 2_800 : 1_600, now);
        bounceGain.gain.setValueAtTime(
          gamelan ? (complement ? 0.1 : 0.22) : 0.16,
          now,
        );
        bounceGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.52);
        gain.connect(bounce).connect(bounceFilter).connect(bounceGain)
          .connect(routeGain ?? soundRoute.input);
      }
      main.start(now);
      round.start(now);
      crystal.start(now);
      motion.start(now);
      main.stop(now + (timbre === "ice" ? 0.84 : 0.6 + ring * 0.4));
      round.stop(now + (timbre === "ice" ? 0.84 : 0.6 + ring * 0.4));
      crystal.stop(now + (timbre === "ice" ? 0.84 : 0.5 + ring * 0.32));
      motion.stop(now + (timbre === "ice" ? 0.84 : 0.6 + ring * 0.4));
    };

    const playCycle = () => {
      noteTimers.forEach(window.clearTimeout);
      const events = score ?? choices.map((_, index) => [
        index,
        index,
        offsets?.[index] ?? index * stepSubdivisions,
      ] as const);
      const direction = phrase % 4 === 2 ? -1 : 1;
      const degreeShift = [0, 1, 0, -1][phrase % 4];
      const phraseEvents = direction === 1 ? events : [...events].reverse();
      noteTimers = phraseEvents.map(([activeToken, degree, offset], eventIndex) => window.setTimeout(() => {
        tokens.forEach((token, tokenIndex) => {
          token.classList.toggle("activeChoice", tokenIndex === activeToken);
        });
        const base = frequencies[0];
        const shiftedDegree = Math.max(0, degree + degreeShift);
        const frequency = scaleRatios
          ? base * scaleRatios[shiftedDegree % scaleRatios.length]
            * Math.pow(2, Math.floor(shiftedDegree / scaleRatios.length))
          : frequencies[shiftedDegree % frequencies.length];
        playLead(activeToken, frequency);
      }, (direction === 1 ? offset : events[eventIndex][2]) * RANGE_RHYTHM_SUBDIVISION_MS));
      phrase = (phrase + 1) % 4;
    };

    const unsubscribeRhythm = soundManager?.subscribeRhythmBeat(() => {
      if (reducedMotion.matches) return;
      playCycle();
    });
    const updatePresence = () => {
      if (!routeGain || !soundRoute) return;
      const knot = display.closest<HTMLElement>(".knot");
      const progress = Number.parseFloat(
        knot?.style.getPropertyValue("--scroll-progress") || "0",
      );
      const distance = Math.abs(Number.parseFloat(
        knot?.style.getPropertyValue("--scroll-distance") || "9999",
      ));
      const centerHold = 1 - Math.max(0, Math.min(1, (distance - 120) / 760));
      const linearPresence = Math.max(0, Math.min(1, progress * centerHold));
      const presence = Math.log1p(5 * linearPresence) / Math.log(6);
      routeGain.gain.setTargetAtTime(
        Math.max(0.0001, presence),
        soundRoute.audioContext.currentTime,
        0.42,
      );
    };
    window.addEventListener("scroll", updatePresence, { passive: true });
    updatePresence();
    return () => {
      noteTimers.forEach(window.clearTimeout);
      unsubscribeRhythm?.();
      window.removeEventListener("scroll", updatePresence);
      routeGain?.disconnect();
      soundRoute?.dispose();
    };
  });
</script>

<div class="choiceDisplay" bind:this={display} aria-label="String, Message, or Error progression">
  {#each choices as choice, index}
    <span class="choice" data-choice-index={index}>{choice}</span>
    {#if index < choices.length - 1}<span class="operator">|</span>{/if}
  {/each}
  <p>{noteNames}</p>
</div>

<style>
  .choiceDisplay {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: clamp(10px, 2vw, 20px);
    min-height: 190px;
    overflow: hidden;
    border: 1px solid var(--line);
    border-radius: 10px;
    background:
      radial-gradient(circle at center, color-mix(in oklch, var(--range), transparent 91%), transparent 64%),
      oklch(0.97 0.006 255);
    font-family: var(--font-geist-mono), monospace;
  }

  .choice {
    color: oklch(0.48 0.08 210);
    font-size: clamp(19px, 4vw, 32px);
    transition:
      color 220ms ease,
      transform 220ms cubic-bezier(0.16, 1, 0.3, 1),
      text-shadow 220ms ease;
  }

  .choice:global(.activeChoice) {
    color: oklch(0.54 0.22 var(--range-hue));
    text-shadow: 0 0 20px color-mix(in oklch, var(--range), transparent 40%);
    transform: translateY(-2px) scale(1.06);
  }

  .operator {
    color: oklch(0.65 0.025 255);
    font-size: clamp(18px, 3vw, 27px);
  }

  p {
    position: absolute;
    right: 14px;
    bottom: 10px;
    margin: 0;
    color: var(--muted);
    font-size: 10px;
  }
</style>
