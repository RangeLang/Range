<script lang="ts">
  import { getContext, onMount, tick } from "svelte";
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
  let targetX = 0;
  let targetY = 0;
  let segmentMask = $state(0);
  let travel = 0;
  let lastX = 0;
  let lastY = 0;
  let exploreStartedAt = 0;
  let completionTimer: number | undefined;
  let motionFrame: number | undefined;
  let route: RangeSoundRoute | undefined;
  let oscillator: OscillatorNode | undefined;
  let overtone: OscillatorNode | undefined;
  let filter: BiquadFilterNode | undefined;
  let gain: GainNode | undefined;

  const welcomingIntervals = [
    [261.63, 329.63],
    [293.66, 392.0],
    [329.63, 440.0],
    [392.0, 523.25],
    [220.0, 329.63],
    [246.94, 392.0],
  ] as const;

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
    oscillator.frequency.setValueAtTime(130.81, now);
    overtone.frequency.setValueAtTime(196.0, now);
    filter.type = "lowpass";
    filter.frequency.setValueAtTime(1_050, now);
    filter.Q.setValueAtTime(0.2, now);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(0.006, now + 0.18);
    oscillator.connect(filter);
    overtone.connect(filter);
    filter.connect(gain).connect(route.input);
    oscillator.start(now);
    overtone.start(now);
  }

  function shapeVoice() {
    if (!route || !oscillator || !overtone || !filter || !gain) return;
    const now = route.audioContext.currentTime;
    const pitch = 130.81 * Math.pow(2, x / 12);
    oscillator.frequency.setTargetAtTime(pitch, now, 0.12);
    overtone.frequency.setTargetAtTime(pitch * 1.5, now, 0.14);
    filter.frequency.setTargetAtTime(900 + (1 - y) * 420, now, 0.16);
    gain.gain.setTargetAtTime(0.004 + (1 - y) * 0.003, now, 0.18);
  }

  function playInterval(segment: number) {
    if (!route) return;
    const context = route.audioContext;
    const now = context.currentTime;
    const interval = welcomingIntervals[segment % welcomingIntervals.length];
    const inversion = segment >= welcomingIntervals.length;
    const frequencies = inversion
      ? [interval[1] / 2, interval[0]]
      : interval;
    const noteFilter = context.createBiquadFilter();
    const noteGain = context.createGain();
    noteFilter.type = "lowpass";
    noteFilter.frequency.setValueAtTime(2_100, now);
    noteFilter.Q.setValueAtTime(0.18, now);
    noteGain.gain.setValueAtTime(0.0001, now);
    noteGain.gain.exponentialRampToValueAtTime(0.018, now + 0.045);
    noteGain.gain.exponentialRampToValueAtTime(0.0001, now + 1.45);
    noteFilter.connect(noteGain).connect(route.input);
    frequencies.forEach((frequency, index) => {
      const voice = context.createOscillator();
      voice.type = index === 0 ? "sine" : "triangle";
      voice.frequency.setValueAtTime(frequency, now);
      voice.connect(noteFilter);
      voice.start(now);
      voice.stop(now + 1.55);
    });
  }

  async function unlock(event: MouseEvent) {
    const pointerX = event.clientX;
    const pointerY = event.clientY;
    const context = await soundManager?.resume();
    if (!context || !soundManager) return;
    soundManager.setEnabled(true);
    route ??= soundManager.register("sound-onboarding", 0.72);
    startVoice();
    x = 0;
    y = 0;
    targetX = 0;
    targetY = 0;
    travel = 0;
    lastX = 0;
    lastY = 0;
    segmentMask = 0;
    exploreStartedAt = performance.now();
    phase = "explore";
    await tick();
    setPointerTarget(pointerX, pointerY);
  }

  function activateSegment() {
    const radius = Math.hypot(x, y);
    if (radius < 0.88) return;
    const angle = Math.atan2(y, x);
    const normalizedAngle = (angle + Math.PI * 2) % (Math.PI * 2);
    const segment = Math.floor((normalizedAngle / (Math.PI * 2)) * 12) % 12;
    const isNewSegment = (segmentMask & (1 << segment)) === 0;
    const nextMask = segmentMask | (1 << segment);
    segmentMask = nextMask;
    if (isNewSegment) playInterval(segment);
    if (
      nextMask === (1 << 12) - 1
      && performance.now() - exploreStartedAt >= 1_200
      && completionTimer === undefined
    ) {
      completionTimer = window.setTimeout(completeExperience, 720);
    }
  }

  function animateHandle() {
    const dx = targetX - x;
    const dy = targetY - y;
    x += dx * 0.115;
    y += dy * 0.115;
    shapeVoice();
    activateSegment();
    if (Math.hypot(dx, dy) > 0.0015) {
      motionFrame = requestAnimationFrame(animateHandle);
    } else {
      x = targetX;
      y = targetY;
      activateSegment();
      motionFrame = undefined;
    }
  }

  function setPointerTarget(clientX: number, clientY: number) {
    if (!fieldElement) return;
    const bounds = fieldElement.getBoundingClientRect();
    const rawX = ((clientX - bounds.left) / bounds.width) * 2 - 1;
    const rawY = ((clientY - bounds.top) / bounds.height) * 2 - 1;
    const radius = Math.hypot(rawX, rawY);
    const projection = radius > 1 ? 1 / radius : 1;
    const nextX = rawX * projection;
    const nextY = rawY * projection;
    travel += Math.hypot(nextX - lastX, nextY - lastY);
    lastX = nextX;
    lastY = nextY;
    targetX = nextX;
    targetY = nextY;
    if (motionFrame === undefined) {
      motionFrame = requestAnimationFrame(animateHandle);
    }
  }

  function beginDrag(event: PointerEvent) {
    if (!fieldElement || event.pointerType === "mouse") return;
    dragging = true;
    travel = 0;
    lastX = x;
    lastY = y;
    fieldElement.setPointerCapture(event.pointerId);
    setPointerTarget(event.clientX, event.clientY);
  }

  function moveDrag(event: PointerEvent) {
    if (!dragging) return;
    setPointerTarget(event.clientX, event.clientY);
  }

  function completeExperience() {
    if (phase !== "explore") return;
    if (!import.meta.env.DEV) {
      localStorage.setItem(storageKey, "complete");
    }
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
    setPointerTarget(event.clientX, event.clientY);
  }

  function finishDrag(event: PointerEvent) {
    if (!dragging || !fieldElement) return;
    dragging = false;
    if (fieldElement.hasPointerCapture(event.pointerId)) {
      fieldElement.releasePointerCapture(event.pointerId);
    }
  }

  onMount(() => {
    if (import.meta.env.DEV || localStorage.getItem(storageKey) !== "complete") {
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
      if (motionFrame !== undefined) cancelAnimationFrame(motionFrame);
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
          <span class="mouseInstruction">Touch every segment</span>
          <span class="touchInstruction">Touch every segment</span>
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
          <span class="fieldBackdrop" aria-hidden="true"></span>
          <svg class="torus" viewBox="0 0 100 100" aria-hidden="true">
            {#each Array(12) as _, index}
              <circle
                class:active={(segmentMask & (1 << index)) !== 0}
                cx="50"
                cy="50"
                r="47"
                pathLength="12"
                transform={`rotate(${index * 30} 50 50)`}
              ></circle>
            {/each}
          </svg>
          <svg class="connector" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
            <line x1="50" y1="50" x2={50 + x * 45} y2={50 + y * 45}></line>
          </svg>
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
    transition: background-color 760ms cubic-bezier(0.22, 0.61, 0.36, 1);
  }

  .onboarding.leaving {
    background-color: transparent;
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
    position: relative;
    display: grid;
    justify-items: center;
    color: var(--ink);
    font-family: var(--font-geist-mono), monospace;
    opacity: 1;
    transform: scale(1);
    transition:
      opacity 620ms cubic-bezier(0.22, 0.61, 0.36, 1),
      transform 760ms cubic-bezier(0.4, 0, 0.2, 1);
    transform-origin: center;
  }

  .leaving .lesson {
    opacity: 0;
    transform: scale(0.68);
  }

  .lesson p,
  .lesson small {
    margin: 0;
  }

  .lesson p {
    position: absolute;
    bottom: calc(100% + 24px);
    font-size: 13px;
    letter-spacing: 0.035em;
    white-space: nowrap;
  }

  .lesson small {
    position: absolute;
    top: calc(100% + 24px);
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

  .fieldBackdrop {
    position: absolute;
    z-index: 0;
    inset: 0;
    border: 0;
    border-radius: 50%;
    background: oklch(0.09 0.01 255);
    transform: scale(0.1556);
    animation: expand-field 760ms cubic-bezier(0.16, 1, 0.3, 1) both;
    transform-origin: center;
  }

  .field.dragging {
    cursor: grabbing;
  }

  .touchInstruction {
    display: none;
  }

  .torus {
    position: absolute;
    z-index: 4;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
    pointer-events: none;
  }

  .torus circle {
    r: 47px;
    fill: none;
    stroke: oklch(0.34 0.012 255);
    stroke-width: 1.35;
    stroke-linecap: round;
    stroke-dasharray: 0.76 11.24;
    transition:
      stroke 320ms cubic-bezier(0.22, 0.61, 0.36, 1),
      stroke-width 320ms cubic-bezier(0.22, 0.61, 0.36, 1),
      r 420ms cubic-bezier(0.16, 1, 0.3, 1),
      filter 320ms cubic-bezier(0.22, 0.61, 0.36, 1);
  }

  .torus circle.active {
    r: 49px;
    stroke: var(--range);
    stroke-width: 1.8;
    filter: drop-shadow(0 0 2px color-mix(in oklch, var(--range), transparent 30%));
  }

  .connector {
    position: absolute;
    z-index: 2;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
    pointer-events: none;
  }

  .connector line {
    stroke: white;
    stroke-width: 0.32;
    vector-effect: non-scaling-stroke;
    opacity: 0.78;
  }

  .handle {
    position: absolute;
    z-index: 3;
    top: calc(50% + var(--y) * 45%);
    left: calc(50% + var(--x) * 45%);
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: white;
    box-shadow: 0 8px 30px oklch(0 0 0 / 0.24);
    transform: translate(-50%, -50%);
    transition: box-shadow 180ms ease;
    animation: reveal-handle 220ms 110ms ease both;
  }

  .dragging .handle {
    box-shadow:
      0 12px 38px oklch(0.09 0.01 255 / 0.22),
      0 0 0 10px oklch(0.09 0.01 255 / 0.06);
  }

  @keyframes expand-field {
    from {
      background: oklch(0.09 0.01 255);
      transform: scale(0.1556);
    }
    to {
      background: oklch(0.09 0.01 255);
      transform: scale(1);
    }
  }

  @keyframes reveal-handle {
    from {
      opacity: 0;
      background: oklch(0.09 0.01 255);
    }
    to {
      opacity: 1;
      background: white;
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
