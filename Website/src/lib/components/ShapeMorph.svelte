<script lang="ts">
  import { getContext, onMount } from "svelte";
  import {
    createDesignKnotVoices,
    KNOT_BEAT_SECONDS,
  } from "$lib/audio/design-knot-voices";
  import {
    RANGE_SOUND_MANAGER_CONTEXT,
    type RangeSoundManager,
  } from "$lib/audio/sound-manager";
  import { pathFromOutline, shapeCorners, shapeOutline } from "$lib/design-knots";

  let {
    samples = 192,
    halfCycle = 6,
    strikeLead = 0.5,
  }: {
    samples?: number;
    /*
     * Circle peak to triangle peak takes six beats; the return makes the
     * twelve-beat master cycle. The peaks turn immediately with no dwell.
     */
    /** Beats between the circle and triangle peaks. */
    halfCycle?: number;
    /** Beats the gong strike leads the triangle peak by. */
    strikeLead?: number;
  } = $props();

  /** A circle yields only where the three eventual triangle edges press it. */
  const unit = 200;
  const radius = 0.985;
  /** 0 at the circle, 1 at the equilateral triangle. */
  let progress = $state(0);
  /** Tracks the triangle spokes from the first moment of the shape morph. */
  let detailProgress = $state(0);
  /** The solid cube shares the shape's breath exactly. */
  let cubeScale = $state(0);
  const traceCount = 5;
  const traceSpacingBeats = 0.3;
  let traceProgresses = $state<number[]>(Array(traceCount).fill(0));

  function morphOutline(amount: number) {
    const startingOutline = shapeOutline(shapeCorners.circle, samples, radius);
    const endingOutline = shapeOutline(shapeCorners.triangle, samples, radius);
    return startingOutline.map((point, index) => ({
      x: point.x + (endingOutline[index].x - point.x) * amount,
      y: point.y + (endingOutline[index].y - point.y) * amount,
    }));
  }

  let currentOutline = $derived(morphOutline(progress));
  let shapePath = $derived(pathFromOutline(currentOutline, unit / 2));
  let tracePaths = $derived(
    traceProgresses.map((amount, index) => ({
      path: pathFromOutline(morphOutline(amount), unit / 2),
      opacity: 0.28 * (1 - index / traceCount),
    })),
  );
  /* The cube is layered above these spokes and masks their center endpoints. */
  let vertexSpokes = $derived(
    Array.from({ length: 3 }, (_, index) => {
      const vertex = currentOutline[(index * samples) / 3];
      return {
        x1: vertex.x * (unit / 2),
        y1: vertex.y * (unit / 2),
        x2: vertex.x * (1 - detailProgress) * (unit / 2),
        y2: vertex.y * (1 - detailProgress) * (unit / 2),
      };
    }),
  );
  const fieldColour = "var(--range)";

  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );
  let soundEnabled = $state(false);

  onMount(() => {
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const route = soundManager?.register("design-knot-gong", 0.8);
    const unsubscribe = soundManager?.subscribe((enabled) => {
      soundEnabled = enabled;
    });

    const voices = route ? createDesignKnotVoices(route) : undefined;

    /*
     * The turn's own figure, struck once as the triangle resolves:
     *   gong · eight beats · chaka · two beats · half chaka
     * The original 4/5-beat follow-up is stretched to 8/10, exactly twice as
     * long while remaining inside the twelve-beat turn.
     * The cymbals are not part of this. They run as their own repeating layer
     * against it, so they rotate rather than landing in the same place every
     * turn.
     */
    const phrase = (beat: number, at: number) => {
      if (!route || !voices || !soundManager?.isEnabled()) return;
      voices.gong(at);
      voices.chaka(at + beat * 8, 0.26, false);
      voices.chaka(at + beat * 10, 0.17, true);
    };

    if (motion.matches) {
      return () => {
        unsubscribe?.();
        route?.dispose();
      };
    }

    let frame = 0;
    // Timing arrives in beats; everything below the clock works in milliseconds.
    const beatMs = KNOT_BEAT_SECONDS * 1_000;
    const trianglePeak = halfCycle * beatMs;
    const cycle = trianglePeak * 2;
    const revealPoint = trianglePeak - strikeLead * beatMs;

    /*
     * The animation runs on performance.now() and the music runs on the audio
     * clock; nothing lines them up on its own. Offset the start so the morph's
     * strike lands on a beat of audio time; every later oscillation has the
     * same twelve-beat length.
     */
    let start = performance.now();
    let firstStrike = 0;
    if (route) {
      const strikeAt = route.audioContext.currentTime + revealPoint / 1_000;
      firstStrike = Math.ceil(strikeAt / KNOT_BEAT_SECONDS) * KNOT_BEAT_SECONDS;
      start += (firstStrike - strikeAt) * 1_000;
    }
    // Tracked by turn rather than by frame, so a dropped frame cannot swallow
    // the gong that lands once per turn as the triangle resolves.
    let struckTurn = -1;
    const cycleSeconds = cycle / 1_000;
    const breathAt = (time: number) =>
      (1 - Math.cos((time / cycle) * Math.PI * 2)) / 2;

    const tick = (now: number) => {
      const total = Math.max(0, now - start);
      const turn = Math.floor(total / cycle);
      const elapsed = total % cycle;
      const breathProgress = breathAt(elapsed);
      progress = breathProgress;
      detailProgress = breathProgress;
      cubeScale = breathProgress;
      traceProgresses = Array.from({ length: traceCount }, (_, index) =>
        breathAt(
          Math.max(0, total - (index + 1) * traceSpacingBeats * beatMs),
        ),
      );
      /*
       * Scheduled ahead of the frame that draws it, at the exact grid time.
       * Striking at whatever currentTime the frame happened to observe put
       * the gong most of a frame behind everything else.
       */
      if (route && struckTurn !== turn) {
        const strikeTime = firstStrike + turn * cycleSeconds;
        if (route.audioContext.currentTime >= strikeTime - 0.25) {
          struckTurn = turn;
          phrase(KNOT_BEAT_SECONDS, strikeTime);
        }
      }
      frame = requestAnimationFrame(tick);
    };

    frame = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(frame);
      unsubscribe?.();
      route?.dispose();
    };
  });

  async function toggleSound() {
    if (!soundManager) return;
    if (soundManager.isEnabled()) {
      soundManager.setEnabled(false);
      return;
    }
    const audio = await soundManager.resume();
    if (audio) soundManager.setEnabled(true);
  }
</script>

<div class="morphStage">
  <svg
    class="shapeMorph"
    viewBox={`${-unit / 2} ${-unit / 2} ${unit} ${unit}`}
    preserveAspectRatio="xMidYMid meet"
    aria-hidden="true"
  >
    {#each tracePaths as trace}
      <path
        class="morphTrace"
        d={trace.path}
        style={`--trace-opacity: ${trace.opacity}`}
      />
    {/each}
    <path d={shapePath} fill={fieldColour} />
    {#each vertexSpokes as spoke}
      <line
        class="vertexSpoke"
        x1={spoke.x1}
        y1={spoke.y1}
        x2={spoke.x2}
        y2={spoke.y2}
      />
    {/each}
    <polygon
      class="cubeFill"
      transform={`scale(${cubeScale})`}
      points="0,-22 19,-11 19,11 0,22 -19,11 -19,-11"
    />
  </svg>

  {#if soundManager}
    <button
      type="button"
      class="gongToggle"
      class:enabled={soundEnabled}
      aria-pressed={soundEnabled}
      aria-label={soundEnabled ? "Mute the gong" : "Sound the gong"}
      onclick={toggleSound}
    >
      <span aria-hidden="true"></span>
    </button>
  {/if}
</div>

<style>
  .morphStage {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 22px;
  }

  .shapeMorph {
    display: block;
    width: min(60vw, 60vh);
    height: min(60vw, 60vh);
  }

  .morphTrace {
    fill: none;
    opacity: var(--trace-opacity);
    stroke: var(--range);
    stroke-width: 1;
    vector-effect: non-scaling-stroke;
  }

  .vertexSpoke {
    stroke: var(--paper);
    stroke-width: 2;
    stroke-linecap: round;
    vector-effect: non-scaling-stroke;
  }

  .cubeFill {
    fill: var(--paper);
  }

  .gongToggle {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 30px;
    height: 30px;
    padding: 0;
    border: 1px solid var(--line);
    border-radius: 999px;
    background: transparent;
    cursor: pointer;
    transition: border-color 320ms ease;
  }

  .gongToggle:hover,
  .gongToggle.enabled {
    border-color: color-mix(in oklch, var(--range), transparent 55%);
  }

  .gongToggle:focus-visible {
    outline: 2px solid var(--range);
    outline-offset: 3px;
  }

  .gongToggle span {
    width: 7px;
    height: 7px;
    border-radius: 999px;
    background: var(--line);
    transition:
      background 320ms ease,
      border-radius 320ms ease;
  }

  .gongToggle.enabled span {
    border-radius: 1px;
    background: var(--range);
  }

  @media (prefers-reduced-motion: reduce) {
    .gongToggle,
    .gongToggle span {
      transition: none;
    }
  }
</style>
