<script lang="ts">
  import { getContext, onMount } from "svelte";
  import {
    RANGE_SOUND_MANAGER_CONTEXT,
    type RangeSoundManager,
    type RangeSoundRoute,
  } from "$lib/audio/sound-manager";

  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );
  let active = $state(false);
  let route: RangeSoundRoute | undefined;
  let voices: OscillatorNode[] = [];
  let master: GainNode | undefined;

  function stopVoice() {
    if (!route || !master) return;
    const now = route.audioContext.currentTime;
    master.gain.cancelScheduledValues(now);
    master.gain.setTargetAtTime(0.0001, now, 0.7);
    for (const voice of voices) {
      try {
        voice.stop(now + 3);
      } catch {
        // The oscillator may already be stopping during teardown.
      }
    }
    voices = [];
    master = undefined;
    route.dispose();
    route = undefined;
    active = false;
  }

  async function startVoice() {
    if (!soundManager || active) return;
    const audio = await soundManager.resume();
    if (!audio) return;
    soundManager.setEnabled(true);
    route = soundManager.register("compilation-tree", 0.72);
    if (!route) return;

    const now = audio.currentTime;
    const filter = audio.createBiquadFilter();
    const voiceMaster = audio.createGain();
    const delay = audio.createDelay(2.5);
    const feedback = audio.createGain();
    const wet = audio.createGain();

    filter.type = "lowpass";
    filter.frequency.setValueAtTime(780, now);
    filter.Q.setValueAtTime(0.8, now);
    voiceMaster.gain.setValueAtTime(0.0001, now);
    voiceMaster.gain.exponentialRampToValueAtTime(0.045, now + 2.8);
    delay.delayTime.setValueAtTime(0.82, now);
    feedback.gain.setValueAtTime(0.38, now);
    wet.gain.setValueAtTime(0.3, now);

    filter.connect(voiceMaster).connect(route.input);
    voiceMaster.connect(delay).connect(wet).connect(route.input);
    delay.connect(feedback).connect(delay);

    voices = [55, 82.41, 110].map((frequency, index) => {
      const voice = audio.createOscillator();
      const gain = audio.createGain();
      voice.type = index === 0 ? "triangle" : "sine";
      voice.frequency.setValueAtTime(frequency, now);
      voice.detune.setValueAtTime(index * 4 - 3, now);
      gain.gain.setValueAtTime([0.52, 0.24, 0.12][index], now);
      voice.connect(gain).connect(filter);
      voice.start(now);
      return voice;
    });
    master = voiceMaster;
    active = true;
  }

  function toggleVoice() {
    if (active) stopVoice();
    else void startVoice();
  }

  onMount(() => stopVoice);
</script>

<figure class:active class="compilationTree">
  <div class="diagram" aria-label="Core compiles the Range compiler, which compiles branching Range projects">
    <svg viewBox="0 0 760 330" role="img">
      <title>Range compilation tree</title>
      <g class="connections">
        <path pathLength="1" d="M128 165 H302" />
        <path pathLength="1" d="M378 165 H510" />
        <path pathLength="1" d="M510 165 C560 165 560 78 622 78" />
        <path pathLength="1" d="M510 165 H622" />
        <path pathLength="1" d="M510 165 C560 165 560 252 622 252" />
      </g>
      <g class="nodes">
        <circle cx="92" cy="165" r="36" />
        <circle cx="340" cy="165" r="38" />
        <circle cx="660" cy="78" r="29" />
        <circle cx="660" cy="165" r="29" />
        <circle cx="660" cy="252" r="29" />
      </g>
      <g class="labels">
        <text x="92" y="220">Core</text>
        <text x="340" y="220">Range compiler</text>
        <text x="660" y="123">Project</text>
        <text x="660" y="210">Project</text>
        <text x="660" y="297">Project</text>
      </g>
    </svg>
    <button type="button" class="soundControl" onclick={toggleVoice} aria-pressed={active}>
      <span class="soundMark" aria-hidden="true"></span>
      {active ? "Silence the graph" : "Hear the graph"}
    </button>
  </div>
  <figcaption>
    The smallest compiler authority becomes the compiler project; that compiler
    can then compile any Range project, including its own source.
  </figcaption>
</figure>

<style>
  .compilationTree {
    margin: 36px 0;
  }

  .diagram {
    position: relative;
    overflow: hidden;
    border: 1px solid color-mix(in oklch, var(--line), var(--ink) 10%);
    border-radius: 18px;
    background:
      radial-gradient(circle at 12% 50%, oklch(0.72 0.16 286 / 0.15), transparent 27%),
      linear-gradient(145deg, oklch(0.985 0.008 270), oklch(0.955 0.025 260));
  }

  svg {
    display: block;
    width: 100%;
    height: auto;
  }

  .connections path {
    fill: none;
    stroke: oklch(0.48 0.12 270 / 0.68);
    stroke-width: 2;
    stroke-linecap: round;
    stroke-dasharray: 1;
    stroke-dashoffset: 0;
  }

  .nodes circle {
    fill: oklch(0.99 0.01 270);
    stroke: oklch(0.43 0.16 277);
    stroke-width: 2;
    filter: drop-shadow(0 8px 16px oklch(0.24 0.08 270 / 0.14));
  }

  .labels text {
    fill: oklch(0.29 0.06 270);
    font: 520 15px var(--font-geist), sans-serif;
    text-anchor: middle;
  }

  .soundControl {
    position: absolute;
    right: 14px;
    bottom: 14px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 8px 11px;
    border: 1px solid oklch(0.43 0.08 270 / 0.26);
    border-radius: 999px;
    color: oklch(0.3 0.06 270);
    background: oklch(1 0 0 / 0.72);
    font: 540 12px var(--font-geist), sans-serif;
    cursor: pointer;
    backdrop-filter: blur(12px);
  }

  .soundMark {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--range);
    box-shadow: 0 0 0 0 color-mix(in oklch, var(--range), transparent 55%);
  }

  .active .soundMark {
    animation: resonate 2.8s ease-out infinite;
  }

  figcaption {
    margin: 12px 8px 0;
    color: oklch(0.48 0.018 255);
    font-size: 13px;
    line-height: 1.5;
  }

  @keyframes resonate {
    60%, 100% { box-shadow: 0 0 0 10px transparent; }
  }

  @media (prefers-reduced-motion: no-preference) {
    .connections path {
      animation: draw 1.4s ease both;
    }

    .connections path:nth-child(2) { animation-delay: 0.35s; }
    .connections path:nth-child(n + 3) { animation-delay: 0.7s; }

    @keyframes draw {
      from { stroke-dashoffset: 1; }
    }
  }

  @media (max-width: 600px) {
    .labels text { font-size: 13px; }
    .soundControl { right: 10px; bottom: 10px; }
  }
</style>
