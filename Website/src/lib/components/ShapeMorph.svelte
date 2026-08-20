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
    samples = 160,
    hold = 2,
    morph = 2.5,
    settle = 2.5,
    zoom = 5,
    strikeLead = 0.5,
  }: {
    samples?: number;
    /*
     * Phases are counted in beats, not milliseconds, and they sum to twelve —
     * the master cycle every other layer divides into. The strike then falls
     * on beat four of that cycle, which is why it can sit with the rest.
     */
    /** Beats the promoted circle rests before it starts morphing. */
    hold?: number;
    /** Beats the circle takes to become the triangle. */
    morph?: number;
    /** Beats the completed outer triangle settles before the zoom. */
    settle?: number;
    /** Beats the nested stack takes to scale into its next level. */
    zoom?: number;
    /** Beats the gong strike leads the finished outer morph by. */
    strikeLead?: number;
  } = $props();

  /*
   * One turn of a recursive morph and zoom, in flat colour with no strokes.
   *
   * The active blue circle is also the crop. It morphs into a triangle while
   * the paired paper triangle morphs into a circle. The alternating stack then
   * scales from one to four. Its next blue circle grows from the triangle's
   * incircle to the full outer radius and joins the clip as it grows, becoming
   * the following turn's active mask without a visible reset.
   */
  const unit = 200;
  /*
   * The inner triangle is half the crop's circumradius and reaches the crop at
   * two times scale. The zoom continues to four times, when the blue circle
   * nested inside that triangle reaches the same boundary.
   */
  const cropRadius = 0.985;
  const radius = cropRadius / 2;
  /** 0 while the crop is a circle, 1 once it is a triangle. */
  let progress = $state(0);
  /** Normalized progress from 1x to the completed 4x nested-stack zoom. */
  let zoomed = $state(0);
  let zoomScale = $derived(1 + zoomed * 3);
  /** The promoted blue circle itself, used as the incoming half of the clip. */
  let handoffRadius = $derived((cropRadius / 4) * zoomScale);

  function morphPath(localRadius: number, amount: number) {
    const circleOutline = shapeOutline(
      shapeCorners.circle,
      samples,
      localRadius,
    );
    const triangleOutline = shapeOutline(
      shapeCorners.triangle,
      samples,
      localRadius,
    );
    return pathFromOutline(
      circleOutline.map((point, index) => ({
        x: point.x + (triangleOutline[index].x - point.x) * amount,
        y: point.y + (triangleOutline[index].y - point.y) * amount,
      })),
      unit / 2,
    );
  }

  let cropPath = $derived(morphPath(cropRadius, progress));
  let innerPath = $derived(morphPath(radius, 1 - progress));

  /*
   * Every triangle's incircle has half its circumradius. Alternating a circle
   * and triangle at that exact ratio makes the construction recursive. Ten
   * visible layers take the stack below a rendered pixel. Deeper levels remain
   * alternating circle/triangle masks during the current step instead of
   * duplicating the active morph at every depth.
   *
   * These are the actual nested figures. None is a flash or cutout overlay.
   */
  let nestedLayers = $derived(
    Array.from({ length: 10 }, (_, index) => {
      const nestedRadius = radius / 2 ** (index + 1);
      const fieldLayer = index % 2 === 0;
      const kind = fieldLayer ? "circle" : "triangle";
      return {
        fieldLayer,
        path: pathFromOutline(
          shapeOutline(shapeCorners[kind], samples, nestedRadius),
          unit / 2,
        ),
      };
    }),
  );

  const fieldColour = "var(--range)";
  const shapeColour = "var(--paper)";
  const clipId = "design-knot-morph-clip";

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
    // Phases arrive in beats; everything below the clock works in milliseconds.
    const beatMs = KNOT_BEAT_SECONDS * 1_000;
    const holdMs = hold * beatMs;
    const morphMs = morph * beatMs;
    const settleMs = settle * beatMs;
    const zoomMs = zoom * beatMs;
    const cycle = holdMs + morphMs + settleMs + zoomMs;
    const zoomStart = holdMs + morphMs + settleMs;
    const revealPoint = holdMs + morphMs - strikeLead * beatMs;

    /*
     * The animation runs on performance.now() and the music runs on the audio
     * clock; nothing lines them up on its own. Offset the start so the morph's
     * strike lands on a beat of audio time; every later forward-only turn has
     * the same twelve-beat length.
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
    const ease = (value: number) =>
      value * value * value * (value * (value * 6 - 15) + 10);

    const tick = (now: number) => {
      const total = Math.max(0, now - start);
      const turn = Math.floor(total / cycle);
      const elapsed = total % cycle;
      if (elapsed < holdMs) {
        progress = 0;
        zoomed = 0;
      } else if (elapsed < holdMs + morphMs) {
        progress = ease((elapsed - holdMs) / morphMs);
        zoomed = 0;
      } else if (elapsed < zoomStart) {
        progress = 1;
        zoomed = 0;
      } else {
        progress = 1;
        zoomed = ease((elapsed - zoomStart) / zoomMs);
      }
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
    <defs>
      <clipPath id={clipId} clipPathUnits="userSpaceOnUse">
        <path d={cropPath} />
        <circle cx="0" cy="0" r={handoffRadius} />
      </clipPath>
    </defs>
    <g clip-path={`url(#${clipId})`}>
      <path d={cropPath} fill={fieldColour} />
      <g transform={`scale(${zoomScale})`}>
        <path d={innerPath} fill={shapeColour} />
        {#each nestedLayers as layer}
          <path
            d={layer.path}
            fill={layer.fieldLayer ? fieldColour : shapeColour}
          />
        {/each}
      </g>
    </g>
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
