<script lang="ts">
  import { getContext, onMount } from "svelte";
  import { highlightRange } from "$lib/benchmarks";
  import {
    RANGE_RHYTHM_SUBDIVISION_MS,
    RANGE_SOUND_MANAGER_CONTEXT,
    type RangeSoundManager,
  } from "$lib/audio/sound-manager";

  const source = `macro identity() { value in
    function identity(value) {
        return value
    }
}`;
  const sequence = ["identity", "identity", "value", "value", "value"];
  const highlighted = highlightRange(source);
  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );
  let display: HTMLDivElement;
  let sourceLayer: HTMLPreElement;
  let pipeLayer: SVGSVGElement;

  onMount(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const soundRoute = soundManager?.register("identity-pipes", 0.84);
    const routeGain = soundRoute?.audioContext.createGain();
    if (routeGain && soundRoute) {
      routeGain.gain.value = 0.0001;
      routeGain.connect(soundRoute.input);
    }
    const candidates = Array.from(
      sourceLayer.querySelectorAll<HTMLElement>(
        ".macro-declaration, .function-declaration, .function, .variable, .parameter",
      ),
    );
    const occurrence = new Map<string, number>();
    const ordered = sequence.map((name) => {
      const index = occurrence.get(name) ?? 0;
      occurrence.set(name, index + 1);
      return candidates.filter((token) => token.textContent === name)[index];
    }).filter(Boolean) as HTMLElement[];
    let arpeggioTimers: number[] = [];
    let identitySwing = 0;
    let valuePhrase = 0;

    const playPipe = (
      index: number,
      group: "identity" | "value",
      audioTime?: number,
    ) => {
      if (!soundRoute || !soundManager?.isEnabled()) return;
      const audio = soundRoute.audioContext;
      const now = Math.max(audio.currentTime, audioTime ?? audio.currentTime);
      const oscillator = audio.createOscillator();
      const overtone = audio.createOscillator();
      const grit = audio.createOscillator();
      const filter = audio.createBiquadFilter();
      const gritGain = audio.createGain();
      const bodyCompressor = audio.createDynamicsCompressor();
      const bodyGain = audio.createGain();
      const pulseGain = audio.createGain();
      const pulse = audio.createOscillator();
      const edgeFilter = audio.createBiquadFilter();
      const edgeGain = audio.createGain();
      const gain = audio.createGain();
      const identityFrequencies = [32.74, 38.8];
      const valueScale = [261.91, 293.26, 310.4, 349.22, 392.88, 419.05, 465.61];
      const frequency = group === "identity"
        ? identityFrequencies[index]
        : valueScale[index % valueScale.length];
      oscillator.type = "triangle";
      overtone.type = "triangle";
      grit.type = "sine";
      oscillator.frequency.setValueAtTime(frequency, now);
      overtone.frequency.setValueAtTime(frequency * 1.014, now);
      grit.frequency.setValueAtTime(frequency * 2.73, now);
      gritGain.gain.setValueAtTime(group === "identity" ? 0.035 : 0.009, now);
      gritGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.11);
      filter.type = "bandpass";
      filter.frequency.setValueAtTime(group === "identity" ? 190 : frequency * 2.35, now);
      filter.frequency.exponentialRampToValueAtTime(
        group === "identity" ? 92 : frequency * 1.42,
        now + 0.19,
      );
      filter.Q.setValueAtTime(group === "identity" ? 3.8 : 4.6, now);
      bodyCompressor.threshold.setValueAtTime(-28, now);
      bodyCompressor.knee.setValueAtTime(18, now);
      bodyCompressor.ratio.setValueAtTime(5, now);
      bodyCompressor.attack.setValueAtTime(0.012, now);
      bodyCompressor.release.setValueAtTime(0.16, now);
      bodyGain.gain.setValueAtTime(group === "identity" ? 0.82 : 0.68, now);
      pulse.type = "sine";
      pulse.frequency.setValueAtTime(group === "identity" ? 5.5 : 31, now);
      pulseGain.gain.setValueAtTime(group === "identity" ? 0.18 : 0.08, now);
      pulse.connect(pulseGain).connect(bodyGain.gain);
      edgeFilter.type = "highpass";
      edgeFilter.frequency.setValueAtTime(group === "identity" ? 720 : 1_450, now);
      edgeFilter.Q.setValueAtTime(0.8, now);
      edgeGain.gain.setValueAtTime(0.0001, now);
      edgeGain.gain.linearRampToValueAtTime(
        group === "identity" ? 0.026 : 0.035,
        now + 0.003,
      );
      edgeGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.052);
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.linearRampToValueAtTime(
        group === "identity" ? 0.11 : 0.085,
        now + (group === "identity" ? 0.085 : 0.022),
      );
      gain.gain.exponentialRampToValueAtTime(
        group === "identity" ? 0.045 : 0.018,
        now + (group === "identity" ? 0.72 : 0.2),
      );
      gain.gain.exponentialRampToValueAtTime(
        0.0001,
        now + (group === "identity" ? 2.4 : 0.46),
      );
      oscillator.connect(filter);
      overtone.connect(filter);
      grit.connect(gritGain).connect(filter);
      filter.connect(bodyCompressor).connect(bodyGain).connect(gain);
      filter.connect(edgeFilter).connect(edgeGain).connect(gain);
      gain.connect(routeGain ?? soundRoute.input);
      if (group === "identity") {
        const fieldDelay = audio.createDelay(1.2);
        const fieldFeedback = audio.createGain();
        const fieldFilter = audio.createBiquadFilter();
        const fieldWet = audio.createGain();
        fieldDelay.delayTime.setValueAtTime(0.43, now);
        fieldFeedback.gain.setValueAtTime(0.48, now);
        fieldFilter.type = "bandpass";
        fieldFilter.frequency.setValueAtTime(118, now);
        fieldFilter.Q.setValueAtTime(2.2, now);
        fieldWet.gain.setValueAtTime(0.27, now);
        fieldWet.gain.exponentialRampToValueAtTime(0.0001, now + 4.1);
        gain.connect(fieldDelay).connect(fieldFilter).connect(fieldFeedback);
        fieldFeedback.connect(fieldDelay);
        fieldFeedback.connect(fieldWet).connect(routeGain ?? soundRoute.input);
      }
      if (group === "value") {
        const bounceFilter = audio.createBiquadFilter();
        bounceFilter.type = "lowpass";
        bounceFilter.frequency.setValueAtTime(2_400, now);
        gain.connect(bounceFilter);
        for (const [tapIndex, level] of [0.14, 0.07].entries()) {
          const delay = audio.createDelay(0.6);
          const tapGain = audio.createGain();
          delay.delayTime.setValueAtTime(0.09 * (tapIndex + 1), now);
          tapGain.gain.setValueAtTime(level, now);
          tapGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.42);
          bounceFilter.connect(delay).connect(tapGain).connect(routeGain ?? soundRoute.input);
        }
      }
      oscillator.start(now);
      overtone.start(now);
      grit.start(now);
      pulse.start(now);
      oscillator.stop(now + (group === "identity" ? 2.45 : 0.48));
      overtone.stop(now + (group === "identity" ? 2.45 : 0.48));
      grit.stop(now + 0.12);
      pulse.stop(now + (group === "identity" ? 2.45 : 0.48));
    };

    const render = () => {
      const displayRect = display.getBoundingClientRect();
      const points = ordered.map((token) => {
        const rect = token.getBoundingClientRect();
        return {
          x: rect.left - displayRect.left + rect.width / 2,
          y: rect.top - displayRect.top + rect.height / 2,
        };
      });
      pipeLayer.innerHTML = points.slice(0, -1).map((point, index) => {
        const next = points[index + 1];
        const middleX = (point.x + next.x) / 2;
        return `<path d="M ${point.x} ${point.y} H ${middleX} V ${next.y} H ${next.x}" />`;
      }).join("");
    };

    const showGroupStep = (activeIndex: number, group: "identity" | "value") => {
      ordered.forEach((token, index) => {
        if ((group === "identity") === (index < 2)) {
          token.classList.toggle("activeIdentityToken", index === activeIndex);
        }
      });
      pipeLayer.style.setProperty("--pipe-step", String(activeIndex));
    };

    const playArpeggio = () => {
      arpeggioTimers.forEach(window.clearTimeout);
      arpeggioTimers = [];
      const valueScores = [
        [[0, 0, 300], [1, 4, 900], [2, 2, 1_500]],
        [[2, 3, 300], [0, 1, 900], [1, 5, 1_500]],
        [[1, 2, 300], [2, 6, 900], [0, 0, 1_500]],
      ] as const;
      const valueScore = valueScores[valuePhrase % valueScores.length];
      const rotation = valuePhrase % 3;
      const schedule = valueScore.map(
        ([tokenIndex, degree, offset]) => ({
          token: (tokenIndex + rotation) % 3 + 2,
          groupIndex: degree,
          group: "value" as const,
          offset,
        }),
      );
      valuePhrase = (valuePhrase + 1) % 3;
      const identityToken = identitySwing % 2;
      showGroupStep(identityToken, "identity");
      for (const offset of [0, 75, 180]) {
        arpeggioTimers.push(window.setTimeout(() => {
          playPipe(identityToken, "identity");
        }, offset));
      }
      identitySwing = (identitySwing + 1) % 2;
      for (const event of schedule) {
        arpeggioTimers.push(window.setTimeout(() => {
          showGroupStep(event.token, event.group);
          playPipe(event.groupIndex, event.group);
        }, event.offset));
      }
    };

    document.fonts.ready.then(() => {
      render();
      showGroupStep(0, "identity");
      showGroupStep(2, "value");
    });
    const unsubscribeRhythm = soundManager?.subscribeRhythmBeat(() => {
      if (reducedMotion.matches) return;
      playArpeggio();
    });
    const resizeObserver = new ResizeObserver(render);
    resizeObserver.observe(display);
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
      arpeggioTimers.forEach(window.clearTimeout);
      unsubscribeRhythm?.();
      resizeObserver.disconnect();
      window.removeEventListener("scroll", updatePresence);
      routeGain?.disconnect();
      soundRoute?.dispose();
    };
  });
</script>

<div class="identityDisplay" bind:this={display} aria-label="Identity relationship progression">
  <svg class="pipeLayer" bind:this={pipeLayer} aria-hidden="true"></svg>
  <pre class="sourceLayer language-range" bind:this={sourceLayer}><code>{@html highlighted}</code></pre>
  <p>identity → identity → value → value → value</p>
</div>

<style>
  .identityDisplay {
    position: relative;
    overflow: hidden;
    min-height: 250px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: oklch(0.97 0.006 255);
  }

  .sourceLayer {
    position: relative;
    z-index: 1;
    margin: 0;
    padding: 28px 28px 56px;
    color: oklch(0.25 0.018 255);
    font-family: var(--font-geist-mono), monospace;
    font-size: clamp(15px, 2.3vw, 20px);
    line-height: 1.8;
    white-space: pre;
  }

  .sourceLayer :global(.token) {
    position: relative;
    z-index: 2;
    transition:
      color 280ms ease,
      text-shadow 280ms ease;
  }

  .sourceLayer :global(.token.keyword) {
    color: oklch(0.56 0.2 var(--range-hue));
  }

  .sourceLayer :global(.activeIdentityToken) {
    color: oklch(0.54 0.22 var(--range-hue)) !important;
    text-shadow: 0 0 16px color-mix(in oklch, var(--range), transparent 42%);
  }

  .pipeLayer {
    position: absolute;
    z-index: 0;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
    pointer-events: none;
  }

  .pipeLayer :global(path) {
    fill: none;
    stroke: color-mix(in oklch, var(--range), transparent 72%);
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-dasharray: 5 10;
    animation: pipeFlow 1.44s linear infinite;
  }

  .identityDisplay > p {
    position: absolute;
    z-index: 2;
    right: 16px;
    bottom: 11px;
    margin: 0;
    color: var(--muted);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    letter-spacing: 0.02em;
  }

  @keyframes pipeFlow {
    to { stroke-dashoffset: -30; }
  }

  @media (prefers-reduced-motion: reduce) {
    .pipeLayer :global(path) { animation: none; }
  }
</style>
