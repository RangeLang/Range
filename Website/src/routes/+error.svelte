<script lang="ts">
  import { page } from "$app/state";
  import { getContext, onMount } from "svelte";
  import ErrorBackgroundShader from "$lib/components/ErrorBackgroundShader.svelte";
  import RangeTitle from "$lib/components/RangeTitle.svelte";
  import {
    RANGE_SOUND_MANAGER_CONTEXT,
    type RangeSoundManager,
    type RangeSoundRoute,
  } from "$lib/audio/sound-manager";
  import {
    createErrorPageSynth,
    type ErrorPageSynth,
  } from "$lib/audio/error-page-synth";

  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );

  const status = $derived(page.status || 500);
  const stars = Array.from({ length: 112 }, (_, index) => {
    const random = (offset: number) => {
      const value = Math.sin((index + 1) * 91.173 + offset * 37.719) * 43_758.5453;
      return value - Math.floor(value);
    };
    return {
      x: random(1) * 100,
      y: random(2) * 100,
      size: 0.7 + random(3) * 2.1,
      opacity: 0.16 + random(4) * 0.58,
      duration: 5.5 + random(5) * 10,
      delay: random(6) * -14,
    };
  });

  let route: RangeSoundRoute | undefined;
  let synth: ErrorPageSynth | undefined;
  let twinkleTimer: number | undefined;
  let damTimer: number | undefined;
  let damPulse = $state(0);
  const damIntervalMilliseconds = 2_800;

  function startSynth() {
    if (!soundManager || route) return;
    route = soundManager.register("range-error", 0.75);
    if (!route) return;
    synth = createErrorPageSynth(route);
    scheduleTwinkle();
    scheduleDam(true);
  }

  function playDam() {
    damPulse += 1;
    synth?.dam();
  }

  function scheduleDam(initial = false) {
    if (damTimer !== undefined) window.clearTimeout(damTimer);
    damTimer = window.setTimeout(() => {
      playDam();
      scheduleDam();
    }, initial ? 900 : damIntervalMilliseconds);
  }

  function playTwinkle() {
    synth?.twinkle();
  }

  function scheduleTwinkle() {
    if (twinkleTimer !== undefined) window.clearTimeout(twinkleTimer);
    twinkleTimer = window.setTimeout(() => {
      playTwinkle();
      scheduleTwinkle();
    }, 3_800 + Math.random() * 6_200);
  }

  function removeSoundUnlockListeners() {
    window.removeEventListener("pointerdown", activateSound);
    window.removeEventListener("keydown", activateSound);
  }

  async function activateSound() {
    if (!soundManager) return;
    soundManager.setEnabled(true);
    const audio = await soundManager.resume();
    if (!audio) return;
    startSynth();
    synth?.activate();
    removeSoundUnlockListeners();
  }

  onMount(() => {
    soundManager?.setEnabled(true);
    window.addEventListener("pointerdown", activateSound);
    window.addEventListener("keydown", activateSound);
    void activateSound();

    return () => {
      removeSoundUnlockListeners();
      if (twinkleTimer !== undefined) window.clearTimeout(twinkleTimer);
      if (damTimer !== undefined) window.clearTimeout(damTimer);
      synth?.dispose();
      synth = undefined;
      route?.dispose();
      route = undefined;
    };
  });
</script>

<svelte:head>
  <title>{status} — Range</title>
  <meta name="robots" content="noindex" />
</svelte:head>

<section class="errorPage" aria-labelledby="error-status">
  <div class="starField" aria-hidden="true">
    <div class="nebula"></div>
    {#each stars as star}
      <i
        style={`--x:${star.x}%;--y:${star.y}%;--size:${star.size}px;--opacity:${star.opacity};--duration:${star.duration}s;--delay:${star.delay}s`}
      ></i>
    {/each}
  </div>

  <a class="wordmark" href="/">Range</a>

  <div class="statusWrap">
    <div class="statusStage">
      <ErrorBackgroundShader trigger={damPulse} />
      <h1
        id="error-status"
        aria-label={String(status)}
        oncopy={(event) => event.preventDefault()}
      >
        <RangeTitle
          text={String(status)}
          base="white"
          effect="dam-sweep"
          layout="error-status"
          sound={false}
          trigger={damPulse}
        />
      </h1>
    </div>
  </div>

  <div class="controls">
    <a href="/">Return</a>
    <span class="soundState" aria-label="Sound is always on">
      <span aria-hidden="true"></span>
      Sound
    </span>
  </div>
</section>

<style>
  :global(html:has(.errorPage)),
  :global(body:has(.errorPage)) {
    background: oklch(0.08 0.025 255);
  }

  .errorPage {
    position: relative;
    isolation: isolate;
    display: grid;
    min-height: 100svh;
    overflow: hidden;
    place-items: center;
    background:
      radial-gradient(circle at 50% 48%, oklch(0.19 0.055 255 / 0.52), transparent 42%),
      oklch(0.075 0.022 255);
    color: oklch(0.96 0.012 255);
  }

  .starField,
  .nebula {
    position: absolute;
    inset: 0;
  }

  .starField {
    z-index: -2;
    overflow: hidden;
  }

  .nebula {
    background:
      radial-gradient(ellipse at 35% 65%, oklch(0.22 0.075 275 / 0.32), transparent 40%),
      radial-gradient(ellipse at 70% 24%, oklch(0.18 0.055 230 / 0.24), transparent 36%);
    filter: blur(26px);
  }

  .starField i {
    position: absolute;
    top: var(--y);
    left: var(--x);
    width: var(--size);
    height: var(--size);
    border-radius: 50%;
    background: oklch(0.98 0.02 255);
    box-shadow: 0 0 calc(var(--size) * 4) oklch(0.84 0.08 255 / 0.72);
    opacity: var(--opacity);
    animation: twinkle var(--duration) var(--delay) ease-in-out infinite;
  }

  .wordmark {
    position: absolute;
    top: clamp(20px, 4vw, 48px);
    left: clamp(20px, 4vw, 54px);
    color: inherit;
    font-size: 18px;
    font-weight: 620;
    letter-spacing: -0.045em;
    text-decoration: none;
  }

  .statusWrap {
    width: 100%;
    padding-inline: 2vw;
    text-align: center;
  }

  .statusStage {
    position: relative;
    isolation: isolate;
    display: inline-grid;
    place-items: center;
  }

  h1 {
    position: relative;
    z-index: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    margin: 0;
    color: oklch(0.93 0.018 255);
    font-size: clamp(11rem, 42vw, 42rem);
    font-weight: 850;
    letter-spacing: 0;
    line-height: 0.68;
    text-rendering: geometricPrecision;
    user-select: none;
    -webkit-user-select: none;
  }

  .controls {
    position: absolute;
    right: clamp(20px, 4vw, 54px);
    bottom: clamp(20px, 4vw, 44px);
    left: clamp(20px, 4vw, 54px);
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-family: var(--font-geist-mono), monospace;
    font-size: 11px;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }

  .controls a,
  .soundState {
    color: oklch(0.76 0.02 255);
  }

  .controls a {
    text-decoration: none;
  }

  .soundState {
    display: inline-flex;
    align-items: center;
    gap: 8px;
  }

  .soundState > span {
    width: 6px;
    height: 6px;
    border: 1px solid currentColor;
    border-radius: 50%;
    background: currentColor;
    box-shadow: 0 0 10px currentColor;
  }

  .controls a:hover,
  .controls a:focus-visible {
    color: white;
    outline: none;
  }

  @keyframes twinkle {
    0%, 42%, 58%, 100% { opacity: calc(var(--opacity) * 0.54); transform: scale(0.78); }
    49% { opacity: var(--opacity); transform: scale(1); }
    51% { opacity: calc(var(--opacity) * 0.72); transform: scale(0.9); }
    53% { opacity: var(--opacity); transform: scale(1.12); }
  }

  @media (max-width: 640px) {
    h1 {
      font-size: clamp(9rem, 47vw, 19rem);
      line-height: 0.8;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .starField i {
      animation: none;
      opacity: var(--opacity);
    }
  }

</style>
