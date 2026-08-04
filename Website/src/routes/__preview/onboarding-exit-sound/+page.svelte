<script lang="ts">
  import { onDestroy } from "svelte";
  import {
    playOnboardingExitSwell,
    type OnboardingExitSwell,
  } from "$lib/audio/onboarding-exit-swell";

  let audioContext: AudioContext | undefined;
  let destinationGain: GainNode | undefined;
  let swell: OnboardingExitSwell | undefined;
  let stopTimer: number | undefined;
  let volume = $state(1.1);
  let playing = $state(false);

  function ensureDestination(context: AudioContext) {
    if (destinationGain) return destinationGain;
    destinationGain = context.createGain();
    destinationGain.gain.value = volume;
    destinationGain.connect(context.destination);
    return destinationGain;
  }

  function stop() {
    if (stopTimer !== undefined) window.clearTimeout(stopTimer);
    stopTimer = undefined;
    if (!audioContext || !swell) {
      playing = false;
      return;
    }
    const now = audioContext.currentTime;
    swell.gain.gain.cancelScheduledValues(now);
    swell.gain.gain.setTargetAtTime(0.0001, now, 0.06);
    for (const voice of swell.voices) {
      try {
        voice.stop(now + 0.16);
      } catch {
        // The voice may already be scheduled to stop.
      }
    }
    swell = undefined;
    playing = false;
  }

  async function play() {
    const Context = window.AudioContext
      ?? (window as Window & { webkitAudioContext?: typeof AudioContext })
        .webkitAudioContext;
    if (!Context) return;
    audioContext ??= new Context();
    await audioContext.resume();
    stop();
    const destination = ensureDestination(audioContext);
    swell = playOnboardingExitSwell(audioContext, destination, 400);
    playing = true;
    stopTimer = window.setTimeout(() => {
      swell = undefined;
      playing = false;
      stopTimer = undefined;
    }, 700);
  }

  function updateVolume(event: Event) {
    volume = Number((event.currentTarget as HTMLInputElement).value);
    if (audioContext && destinationGain) {
      destinationGain.gain.setTargetAtTime(volume, audioContext.currentTime, 0.04);
    }
  }

  onDestroy(() => {
    stop();
    void audioContext?.close();
  });
</script>

<svelte:head>
  <title>Onboarding exit sound preview</title>
</svelte:head>

<main class="preview">
  <p class="eyebrow">Local audio preview</p>
  <h1>Exit swell</h1>
  <p class="description">
    The 400ms sound used when the sky expands into the site, with an audible
    release tail. It is isolated from
    the sphere so the body, definition, and release are easy to hear.
  </p>

  <div class="controls">
    <button type="button" onclick={play} disabled={playing}>
      {playing ? "Playing…" : "Play exit swell"}
    </button>
    <button type="button" class="secondary" onclick={stop} disabled={!playing}>
      Stop
    </button>
  </div>

  <label>
    <span>Preview volume <output>{Math.round(volume * 100)}%</output></span>
    <input
      type="range"
      min="0"
      max="1.2"
      step="0.01"
      value={volume}
      oninput={updateVolume}
    />
  </label>
</main>

<style>
  :global(html) {
    background: oklch(0.98 0.003 255);
  }

  :global(body) {
    margin: 0;
  }

  .preview {
    display: grid;
    align-content: center;
    gap: 18px;
    box-sizing: border-box;
    width: min(100% - 48px, 620px);
    min-height: 100svh;
    margin: 0 auto;
    padding: 48px 0;
    color: oklch(0.18 0.018 255);
    font-family: var(--font-geist-mono), monospace;
  }

  .eyebrow,
  h1,
  .description,
  label {
    margin: 0;
  }

  .eyebrow {
    color: oklch(0.48 0.03 255);
    font-size: 12px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
  }

  h1 {
    font-family: var(--font-geist-sans), sans-serif;
    font-size: clamp(42px, 8vw, 76px);
    letter-spacing: -0.07em;
    line-height: 0.92;
  }

  .description {
    max-width: 500px;
    color: oklch(0.43 0.025 255);
    font-size: 15px;
    line-height: 1.55;
  }

  .controls {
    display: flex;
    gap: 10px;
    margin-top: 12px;
  }

  button {
    min-height: 44px;
    padding: 0 18px;
    border: 1px solid oklch(0.28 0.04 255);
    border-radius: 999px;
    background: oklch(0.18 0.03 255);
    color: white;
    cursor: pointer;
    font: inherit;
  }

  button.secondary {
    background: transparent;
    color: oklch(0.25 0.025 255);
  }

  button:disabled {
    cursor: default;
    opacity: 0.45;
  }

  label {
    display: grid;
    gap: 10px;
    max-width: 360px;
    margin-top: 18px;
    color: oklch(0.36 0.02 255);
    font-size: 13px;
  }

  label span {
    display: flex;
    justify-content: space-between;
  }

  input {
    width: 100%;
    accent-color: oklch(0.42 0.12 255);
  }
</style>
