<script lang="ts">
  import { getContext, onMount } from "svelte";
  import {
    RANGE_SOUND_MANAGER_CONTEXT,
    type RangeSoundManager,
    type RangeSoundRoute,
  } from "$lib/audio/sound-manager";

  type Phase = "hidden" | "press" | "explore" | "leaving";

  const storageKey = "range:sound-onboarding:v1";
  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );

  let phase = $state<Phase>("hidden");
  let fieldElement = $state<HTMLButtonElement>();
  let dragging = $state(false);
  let x = $state(0);
  let y = $state(0);
  let travel = 0;
  let lastX = 0;
  let lastY = 0;
  let exploreStartedAt = 0;
  let completionTimer: number | undefined;
  let route: RangeSoundRoute | undefined;
  let oscillator: OscillatorNode | undefined;
  let overtone: OscillatorNode | undefined;
  let filter: BiquadFilterNode | undefined;
  let gain: GainNode | undefined;

  function stopVoice() {
    const context = route?.audioContext;
    if (context && gain) {
      const now = context.currentTime;
      gain.gain.cancelScheduledValues(now);
      gain.gain.setTargetAtTime(0.0001, now, 0.12);
      try {
        oscillator?.stop(now + 0.7);
        overtone?.stop(now + 0.7);
      } catch {
        // A released onboarding voice may already be stopping.
      }
    }
    oscillator = undefined;
    overtone = undefined;
    filter = undefined;
    gain = undefined;
  }

  function startVoice() {
    if (!route || oscillator) return;
    const context = route.audioContext;
    const now = context.currentTime;
    oscillator = context.createOscillator();
    overtone = context.createOscillator();
    filter = context.createBiquadFilter();
    gain = context.createGain();
    oscillator.type = "sine";
    overtone.type = "sine";
    oscillator.frequency.setValueAtTime(174.61, now);
    overtone.frequency.setValueAtTime(261.63, now);
    filter.type = "lowpass";
    filter.frequency.setValueAtTime(1_400, now);
    filter.Q.setValueAtTime(0.45, now);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(0.035, now + 0.08);
    oscillator.connect(filter);
    overtone.connect(filter);
    filter.connect(gain).connect(route.input);
    oscillator.start(now);
    overtone.start(now);
  }

  function shapeVoice() {
    if (!route || !oscillator || !overtone || !filter || !gain) return;
    const now = route.audioContext.currentTime;
    const pitch = 174.61 * Math.pow(2, x * 0.7);
    oscillator.frequency.setTargetAtTime(pitch, now, 0.045);
    overtone.frequency.setTargetAtTime(pitch * 1.5, now, 0.055);
    filter.frequency.setTargetAtTime(520 + (1 - y) * 2_600, now, 0.06);
    gain.gain.setTargetAtTime(0.018 + (1 - y) * 0.024, now, 0.07);
  }

  async function unlock() {
    const context = await soundManager?.resume();
    if (!context || !soundManager) return;
    soundManager.setEnabled(true);
    route ??= soundManager.register("sound-onboarding", 0.72);
    startVoice();
    x = 0;
    y = 0;
    travel = 0;
    lastX = 0;
    lastY = 0;
    exploreStartedAt = performance.now();
    phase = "explore";
  }

  function updatePointer(event: PointerEvent) {
    if (!fieldElement) return;
    const bounds = fieldElement.getBoundingClientRect();
    const nextX = Math.max(-1, Math.min(1, ((event.clientX - bounds.left) / bounds.width) * 2 - 1));
    const nextY = Math.max(-1, Math.min(1, ((event.clientY - bounds.top) / bounds.height) * 2 - 1));
    travel += Math.hypot(nextX - lastX, nextY - lastY);
    lastX = nextX;
    lastY = nextY;
    x = nextX;
    y = nextY;
    shapeVoice();
  }

  function beginDrag(event: PointerEvent) {
    if (!fieldElement || event.pointerType === "mouse") return;
    dragging = true;
    travel = 0;
    lastX = x;
    lastY = y;
    fieldElement.setPointerCapture(event.pointerId);
    updatePointer(event);
  }

  function moveDrag(event: PointerEvent) {
    if (!dragging) return;
    updatePointer(event);
  }

  function completeExperience() {
    if (phase !== "explore") return;
    localStorage.setItem(storageKey, "complete");
    phase = "leaving";
    stopVoice();
    window.setTimeout(() => {
      phase = "hidden";
      route?.dispose();
      route = undefined;
    }, 820);
  }

  function followMouse(event: PointerEvent) {
    if (phase !== "explore" || event.pointerType !== "mouse") return;
    updatePointer(event);
    if (
      travel >= 0.72
      && performance.now() - exploreStartedAt >= 1_200
      && completionTimer === undefined
    ) {
      completionTimer = window.setTimeout(completeExperience, 520);
    }
  }

  function finishDrag(event: PointerEvent) {
    if (!dragging || !fieldElement) return;
    dragging = false;
    if (fieldElement.hasPointerCapture(event.pointerId)) {
      fieldElement.releasePointerCapture(event.pointerId);
    }
    if (travel < 0.16) return;
    completeExperience();
  }

  onMount(() => {
    if (localStorage.getItem(storageKey) !== "complete") {
      phase = "press";
      return;
    }

    const rearm = async () => {
      const context = await soundManager?.resume();
      if (!context || !soundManager) return;
      soundManager.setEnabled(true);
      window.removeEventListener("pointerdown", rearm);
      window.removeEventListener("keydown", rearm);
    };
    window.addEventListener("pointerdown", rearm, { passive: true });
    window.addEventListener("keydown", rearm);
    return () => {
      window.removeEventListener("pointerdown", rearm);
      window.removeEventListener("keydown", rearm);
      window.clearTimeout(completionTimer);
      stopVoice();
      route?.dispose();
    };
  });
</script>

<svelte:window onpointermove={followMouse} />

{#if phase !== "hidden"}
  <div
    class="onboarding"
    class:leaving={phase === "leaving"}
  >
    {#if phase === "press"}
      <div class="entryPrompt">
        <button class="entryDot" type="button" aria-label="Press here to enable sound" onclick={unlock}></button>
        <small>Press here</small>
      </div>
    {:else}
      <div class="lesson">
        <p>
          <span class="mouseInstruction">Move left, right, up, and down</span>
          <span class="touchInstruction">Drag left, right, up, and down</span>
        </p>
        <button
          type="button"
          class="field"
          class:dragging
          bind:this={fieldElement}
          aria-label="Explore sound in two dimensions"
          onpointerdown={beginDrag}
          onpointermove={moveDrag}
          onpointerup={finishDrag}
          onpointercancel={finishDrag}
        >
          <span class="axis axisX" aria-hidden="true"></span>
          <span class="axis axisY" aria-hidden="true"></span>
          <span
            class="handle"
            aria-hidden="true"
            style={`--x: ${x}; --y: ${y}`}
          ></span>
        </button>
        <small>Be curious.</small>
      </div>
    {/if}
  </div>
{/if}

<style>
  .onboarding {
    position: fixed;
    z-index: 1000;
    inset: 0;
    display: grid;
    place-items: center;
    overflow: hidden;
    background: white;
    opacity: 1;
    transition: opacity 760ms cubic-bezier(0.22, 0.61, 0.36, 1);
  }

  .onboarding.leaving {
    opacity: 0;
    pointer-events: none;
  }

  .entryDot {
    width: 56px;
    aspect-ratio: 1;
    padding: 0;
    border: 0;
    border-radius: 50%;
    background: oklch(0.09 0.01 255);
    cursor: pointer;
    box-shadow: 0 8px 30px oklch(0.09 0.01 255 / 0.18);
    transition: transform 380ms cubic-bezier(0.16, 1, 0.3, 1);
  }

  .entryDot:hover {
    transform: scale(1.045);
  }

  .entryPrompt {
    display: grid;
    justify-items: center;
    gap: 13px;
    color: color-mix(in oklch, var(--ink), transparent 42%);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    letter-spacing: 0.045em;
  }

  .entryDot:focus-visible,
  .field:focus-visible {
    outline: 2px solid var(--range);
    outline-offset: 6px;
  }

  .lesson {
    display: grid;
    justify-items: center;
    gap: 24px;
    color: var(--ink);
    font-family: var(--font-geist-mono), monospace;
    animation: reveal-field 680ms cubic-bezier(0.16, 1, 0.3, 1) both;
  }

  .lesson p,
  .lesson small {
    margin: 0;
  }

  .lesson p {
    font-size: 13px;
    letter-spacing: 0.035em;
  }

  .lesson small {
    color: color-mix(in oklch, var(--ink), transparent 48%);
    font-size: 11px;
  }

  .field {
    position: relative;
    width: min(58vw, 360px);
    aspect-ratio: 1;
    padding: 0;
    border: 0;
    background: transparent;
    cursor: default;
    touch-action: none;
  }

  .field.dragging {
    cursor: grabbing;
  }

  .touchInstruction {
    display: none;
  }

  .axis {
    position: absolute;
    background: color-mix(in oklch, var(--ink), transparent 76%);
  }

  .axisX {
    top: 50%;
    right: 0;
    left: 0;
    height: 1px;
  }

  .axisY {
    top: 0;
    bottom: 0;
    left: 50%;
    width: 1px;
  }

  .handle {
    position: absolute;
    top: calc(50% + var(--y) * 45%);
    left: calc(50% + var(--x) * 45%);
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: oklch(0.09 0.01 255);
    box-shadow: 0 8px 30px oklch(0.09 0.01 255 / 0.18);
    transform: translate(-50%, -50%);
    transition: box-shadow 180ms ease;
  }

  .dragging .handle {
    box-shadow:
      0 12px 38px oklch(0.09 0.01 255 / 0.22),
      0 0 0 10px oklch(0.09 0.01 255 / 0.06);
  }

  @keyframes reveal-field {
    from {
      opacity: 0;
      transform: scale(0.18);
    }
    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  @media (hover: none), (pointer: coarse) {
    .field {
      cursor: grab;
    }

    .mouseInstruction {
      display: none;
    }

    .touchInstruction {
      display: inline;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .onboarding,
    .entryDot {
      transition-duration: 1ms;
    }
  }
</style>
