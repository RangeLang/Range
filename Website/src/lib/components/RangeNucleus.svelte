<script lang="ts">
  import { onDestroy } from "svelte";

  type ConceptID = "shape" | "ownership" | "capability";

  type Concept = {
    description: string;
    path: number[];
    labels: Record<number, string>;
  };

  const concepts: Record<ConceptID, Concept> = {
    shape: {
      description: "An explicit shape steps through graph values.",
      path: [1, 2, 4],
      labels: { 1: "source", 2: "step", 4: "result" },
    },
    ownership: {
      description: "Ownership follows value paths into derived effects.",
      path: [1, 2, 8],
      labels: { 1: "value", 2: "transfer", 8: "effect paths" },
    },
    capability: {
      description: "Requirements expand into a transitive capability closure.",
      path: [1, 4, 16],
      labels: { 1: "root", 4: "requirement", 16: "closure" },
    },
  };

  const conceptIDs = Object.keys(concepts) as ConceptID[];
  const scale = [
    { name: "C5", frequency: 523.25 },
    { name: "B4", frequency: 493.88 },
    { name: "A4", frequency: 440 },
    { name: "G4", frequency: 392 },
    { name: "F4", frequency: 349.23 },
    { name: "E4", frequency: 329.63 },
    { name: "D4", frequency: 293.66 },
    { name: "C4", frequency: 261.63 },
  ];
  const intervalNote = { name: "A2", frequency: 110 };
  const intervalResonance = { name: "B2", frequency: 123.47 };
  const spiralSteps = [
    { conceptID: "shape", value: 4, note: { name: "B2", frequency: 123.47 } },
    { conceptID: "ownership", value: 8, note: { name: "D3", frequency: 146.83 } },
    { conceptID: "capability", value: 16, note: { name: "E3", frequency: 164.81 } },
  ] as const;
  let selectedID = $state<ConceptID>("shape");
  let looping = $state(false);
  let spiralTrackEnabled = $state(true);
  let spiralActiveIndex = $state(-1);
  let spiralStepIndex = 0;
  let selected = $derived(concepts[selectedID]);
  let rhythmPulse = $state(0);
  const rhythmDuration = 1.8 + 1.8 / 3;
  let audioContext: AudioContext | undefined;
  let reverbInput: GainNode | undefined;
  let reverbResonance: BiquadFilterNode | undefined;
  let activeOscillators: OscillatorNode[] = [];
  let loopTimer: number | undefined;

  const center = 382;
  const centerY = 320;
  const innerRingRadius = 64;
  const outerRadius = 290;
  const circularScaleValues = [2, 4, 8, 16];
  const branchAngles: Record<ConceptID, number> = {
    shape: (-90 * Math.PI) / 180,
    ownership: (30 * Math.PI) / 180,
    capability: (150 * Math.PI) / 180,
  };

  function numericRadius(value: number) {
    if (value <= 1) return 0;
    return innerRingRadius + ((value - 2) / (16 - 2)) * (outerRadius - innerRingRadius);
  }

  function branchGeometry(conceptID: ConceptID, concept: Concept) {
    const angle = branchAngles[conceptID];
    const maximum = concept.path.at(-1) ?? 1;
    const radius = numericRadius(maximum);
    const direction = { x: Math.cos(angle), y: Math.sin(angle) };
    return {
      radius,
      direction,
      end: {
        x: center + direction.x * radius,
        y: centerY + direction.y * radius,
      },
    };
  }

  function branchPoint(conceptID: ConceptID, concept: Concept, value: number) {
    const geometry = branchGeometry(conceptID, concept);
    const radius = numericRadius(value);
    return {
      x: center + geometry.direction.x * radius,
      y: centerY + geometry.direction.y * radius,
    };
  }

  function spiralPoint(progress: number) {
    const value = 4 * Math.pow(4, progress);
    const angle = ((-90 + 240 * progress) * Math.PI) / 180;
    const radius = numericRadius(value);
    return {
      x: center + Math.cos(angle) * radius,
      y: centerY + Math.sin(angle) * radius,
    };
  }

  function spiralPathData() {
    return Array.from({ length: 65 }, (_, index) => {
      const point = spiralPoint(index / 64);
      return `${index === 0 ? "M" : "L"} ${point.x} ${point.y}`;
    }).join(" ");
  }

  function valueAtRadius(radius: number) {
    if (radius <= innerRingRadius) return 1 + radius / innerRingRadius;
    return 2 + ((radius - innerRingRadius) / (outerRadius - innerRingRadius)) * 14;
  }

  function branchDashSegments(conceptID: ConceptID, concept: Concept) {
    const geometry = branchGeometry(conceptID, concept);
    const segments: Array<{ x1: number; y1: number; x2: number; y2: number }> = [];
    let cursor = 0;

    while (cursor < geometry.radius) {
      const logarithmicMagnitude = Math.log2(valueAtRadius(cursor));
      const dashLength = 2.4 + logarithmicMagnitude * 1.7;
      const gapLength = 2.8 + logarithmicMagnitude * 1.25;
      const dashEnd = Math.min(geometry.radius, cursor + dashLength);
      segments.push({
        x1: center + geometry.direction.x * cursor,
        y1: centerY + geometry.direction.y * cursor,
        x2: center + geometry.direction.x * dashEnd,
        y2: centerY + geometry.direction.y * dashEnd,
      });
      cursor = dashEnd + gapLength;
    }

    return segments;
  }

  function branchLabelPoint(conceptID: ConceptID, concept: Concept) {
    const geometry = branchGeometry(conceptID, concept);
    return {
      x: geometry.end.x + geometry.direction.x * 26,
      y: geometry.end.y + geometry.direction.y * 26,
    };
  }

  function noteForValue(concept: Concept, value: number) {
    const first = concept.path[0];
    const maximum = concept.path.at(-1) ?? first;
    const denominator = Math.log(maximum / first);
    const position = denominator === 0 ? 0 : Math.log(value / first) / denominator;
    return scale[Math.round(position * (scale.length - 1))];
  }

  function getReverbInput() {
    if (!audioContext) return;
    if (reverbInput) return reverbInput;

    const duration = 5.2;
    const impulse = audioContext.createBuffer(
      2,
      Math.floor(audioContext.sampleRate * duration),
      audioContext.sampleRate,
    );

    for (let channel = 0; channel < impulse.numberOfChannels; channel += 1) {
      const samples = impulse.getChannelData(channel);
      let noiseState = channel + 1;
      for (let index = 0; index < samples.length; index += 1) {
        noiseState = (noiseState * 16807) % 2147483647;
        const noise = (noiseState / 2147483647) * 2 - 1;
        const progress = index / samples.length;
        samples[index] = noise * Math.pow(1 - progress, 3.1);
      }
    }

    const input = audioContext.createGain();
    const convolver = audioContext.createConvolver();
    const rumbleCut = audioContext.createBiquadFilter();
    const resonance = audioContext.createBiquadFilter();
    const wet = audioContext.createGain();
    convolver.buffer = impulse;
    rumbleCut.type = "highpass";
    rumbleCut.frequency.value = 58;
    rumbleCut.Q.value = 0.7;
    resonance.type = "lowpass";
    resonance.frequency.value = intervalResonance.frequency;
    resonance.Q.value = 2.6;
    wet.gain.value = 0.9;
    input.connect(convolver);
    convolver.connect(rumbleCut);
    rumbleCut.connect(resonance);
    resonance.connect(wet);
    wet.connect(audioContext.destination);
    reverbInput = input;
    reverbResonance = resonance;
    return input;
  }

  function stopPlayback() {
    if (loopTimer !== undefined) window.clearTimeout(loopTimer);
    loopTimer = undefined;
    activeOscillators.forEach((oscillator) => {
      try {
        oscillator.stop();
      } catch {
        // The oscillator may already have completed.
      }
    });
    activeOscillators = [];
    rhythmPulse = 0;
    spiralStepIndex = 0;
    spiralActiveIndex = -1;
    looping = false;
  }

  function playTone(
    frequency: number,
    duration: number,
    peakGain: number,
    resonanceFrequency: number,
  ) {
    if (!looping || !audioContext) return;
    const startAt = audioContext.currentTime + 0.04;
    const noteEnd = startAt + duration;
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();

    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(frequency, startAt);
    gain.gain.setValueAtTime(0.0001, startAt);
    gain.gain.exponentialRampToValueAtTime(peakGain, startAt + 0.085);
    gain.gain.exponentialRampToValueAtTime(0.0001, noteEnd);

    oscillator.connect(gain);
    const dry = audioContext.createGain();
    dry.gain.value = 0.1;
    gain.connect(dry);
    dry.connect(audioContext.destination);
    const reverb = getReverbInput();
    if (reverb) {
      gain.connect(reverb);
      reverbResonance?.frequency.cancelScheduledValues(startAt);
      reverbResonance?.frequency.setTargetAtTime(
        resonanceFrequency,
        startAt,
        0.12,
      );
    }
    oscillator.start(startAt);
    oscillator.stop(noteEnd + 0.02);
    activeOscillators.push(oscillator);
    oscillator.onended = () => {
      activeOscillators = activeOscillators.filter((active) => active !== oscillator);
    };
  }

  function playIntervalNote() {
    if (!looping) return;
    playTone(
      intervalNote.frequency,
      1.1,
      0.4,
      intervalResonance.frequency,
    );
    if (spiralTrackEnabled) {
      const spiralStep = spiralSteps[spiralStepIndex];
      playSpiralTone(spiralStep.note.frequency);
      spiralActiveIndex = spiralStepIndex;
      spiralStepIndex = (spiralStepIndex + 1) % spiralSteps.length;
    }
    rhythmPulse += 1;
    loopTimer = window.setTimeout(() => {
      if (!looping) return;
      const currentConceptIndex = conceptIDs.indexOf(selectedID);
      selectedID = conceptIDs[(currentConceptIndex + 1) % conceptIDs.length];
      playIntervalNote();
    }, rhythmDuration * 1000);
  }

  function playSpiralTone(frequency: number) {
    if (!looping || !audioContext) return;
    const startAt = audioContext.currentTime + 0.12;
    const noteEnd = startAt + 0.72;
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();

    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(frequency, startAt);
    gain.gain.setValueAtTime(0.0001, startAt);
    gain.gain.exponentialRampToValueAtTime(0.09, startAt + 0.13);
    gain.gain.exponentialRampToValueAtTime(0.0001, noteEnd);
    oscillator.connect(gain);
    gain.connect(audioContext.destination);
    oscillator.start(startAt);
    oscillator.stop(noteEnd + 0.02);
    activeOscillators.push(oscillator);
    oscillator.onended = () => {
      activeOscillators = activeOscillators.filter((active) => active !== oscillator);
    };
  }

  function toggleSpiralTrack() {
    spiralTrackEnabled = !spiralTrackEnabled;
    if (!spiralTrackEnabled) spiralActiveIndex = -1;
  }

  async function startPlayback() {
    if (looping) return;
    stopPlayback();
    audioContext ??= new AudioContext();
    if (audioContext.state === "suspended") await audioContext.resume();
    looping = true;
    playIntervalNote();
  }

  function selectConcept(conceptID: ConceptID) {
    stopPlayback();
    selectedID = conceptID;
  }

  onDestroy(() => {
    stopPlayback();
    void audioContext?.close();
    reverbInput = undefined;
    reverbResonance = undefined;
  });

</script>

<section class="rangeSection" aria-labelledby="range-title">
  <header class="rangeHeader">
    <h2 id="range-title">Cardinality</h2>
    <p>
      Range treats source and compiler as one graph-backed model.
    </p>
  </header>

  <div class="conceptPicker" role="group" aria-label="Range concept">
    {#each conceptIDs as conceptID}
      <button
        type="button"
        aria-pressed={selectedID === conceptID}
        onclick={() => selectConcept(conceptID)}
      >
        {conceptID[0].toUpperCase() + conceptID.slice(1)}
      </button>
    {/each}
  </div>

  <div class="selectedState">
    <span>{selected.description}</span>
    <div class="pathPlayback">
      <div class="playbackControls" role="group" aria-label="Interval note playback">
        <button
          class="playbackControl spiralTrackControl"
          class:enabled={spiralTrackEnabled}
          type="button"
          aria-label="Spiral track"
          aria-pressed={spiralTrackEnabled}
          onclick={toggleSpiralTrack}
        >
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M12.8 7.9c0 2.7-2.2 4.8-4.9 4.8S3.2 10.6 3.2 8s2.1-4.3 4.5-4.3c2.2 0 3.7 1.5 3.7 3.4 0 1.7-1.3 2.8-2.8 2.8-1.3 0-2.2-.8-2.2-1.9 0-.9.7-1.5 1.5-1.5"></path>
          </svg>
        </button>
        <button
          class="playbackControl"
          type="button"
          aria-label="Play interval note"
          disabled={looping}
          onclick={startPlayback}
        >
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M4.5 2.75 13 8l-8.5 5.25z"></path>
          </svg>
        </button>
        <button
          class="playbackControl"
          type="button"
          aria-label="Stop interval note"
          disabled={!looping}
          onclick={stopPlayback}
        >
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <rect x="3.5" y="3.5" width="9" height="9" rx="1"></rect>
          </svg>
        </button>
      </div>
    </div>
  </div>


  <svg
    class="rangeGraph nucleusGraph"
    viewBox="0 0 764 640"
    role="img"
    aria-label="A shared source nucleus with Shape 1, 2, 4, Ownership, and Capability branching outward across a concentric numeric scale. Only the sounding concept is accented."
  >
    <g class="circularScale" aria-hidden="true">
      {#each circularScaleValues as value}
        {@const radius = numericRadius(value)}
        <circle cx={center} cy={centerY} r={radius}></circle>
        <text x={center + 7} y={centerY - radius + 4}>×{value}</text>
      {/each}
    </g>

    <path
      class="valueSpiral"
      class:enabled={spiralTrackEnabled}
      class:playing={spiralTrackEnabled && looping}
      d={spiralPathData()}
      aria-hidden="true"
      style={`--rhythm-duration: ${rhythmDuration}s`}
    ></path>

    {#each conceptIDs as conceptID}
      {@const concept = concepts[conceptID]}
      {@const branchActive = looping && selectedID === conceptID}
      {@const labelPoint = branchLabelPoint(conceptID, concept)}
      {@const dashSegments = branchDashSegments(conceptID, concept)}
      <g
        class="conceptBranch"
        class:active={branchActive}
        class:rhythmA={branchActive && rhythmPulse % 2 === 0}
        class:rhythmB={branchActive && rhythmPulse % 2 === 1}
        data-concept-branch={conceptID}
        style={`--rhythm-duration: ${rhythmDuration}s`}
      >
        <g class="branchTrack" aria-hidden="true">
          {#each dashSegments as segment}
            <line {...segment}></line>
          {/each}
        </g>

        {#each concept.path.slice(1) as value}
          {@const point = branchPoint(conceptID, concept, value)}
          <g
            class="numberNode"
            class:spiralStepActive={spiralTrackEnabled &&
              looping &&
              spiralSteps[spiralActiveIndex]?.conceptID === conceptID &&
              spiralSteps[spiralActiveIndex]?.value === value}
            transform={`translate(${point.x} ${point.y})`}
          >
            <title>{conceptID} {value} · {noteForValue(concept, value).name}</title>
            <text>{value}</text>
          </g>
        {/each}

        <text class="branchName" x={labelPoint.x} y={labelPoint.y}>
          {conceptID}
        </text>
      </g>
    {/each}

    <g
      class:activeSource={looping}
      class:rhythmA={looping && rhythmPulse % 2 === 0}
      class:rhythmB={looping && rhythmPulse % 2 === 1}
      class="sourceNucleus"
      style={`--rhythm-duration: ${rhythmDuration}s`}
    >
      <g class="numberNode sourceNumber" transform={`translate(${center} ${centerY})`}>
        <title>1 · shared source</title>
        <text>1</text>
      </g>
      <text class="sourceLabel" x={center - 21} y={centerY + 4}>source</text>
    </g>
  </svg>

</section>

<style>
  .rangeSection {
    --range-accent: oklch(0.86 0.08 236);
    --range-accent-ink: oklch(0.38 0.11 236);
    --range-playing-accent: oklch(0.67 0.15 236);
    padding: 72px 0;
  }

  .rangeHeader {
    display: grid;
    grid-template-columns: minmax(0, 0.8fr) minmax(280px, 1.2fr);
    gap: 48px;
    align-items: start;
    margin-bottom: 36px;
  }

  .rangeHeader h2 {
    margin: 0;
    font-size: clamp(30px, 5vw, 54px);
    font-weight: 500;
    letter-spacing: -0.055em;
    line-height: 0.95;
  }

  .rangeHeader p {
    max-width: 610px;
    margin: 0;
    color: var(--muted);
    font-size: clamp(16px, 2vw, 21px);
    letter-spacing: -0.02em;
    line-height: 1.45;
  }

  .conceptPicker {
    width: fit-content;
    max-width: 100%;
    display: flex;
    gap: 4px;
    margin-bottom: 22px;
    overflow: hidden;
  }

  .conceptPicker button {
    min-height: 38px;
    padding: 0 14px;
    border: 0;
    border-radius: 8px;
    background: var(--paper);
    color: var(--muted);
    font: 500 12px var(--font-geist-mono);
    cursor: pointer;
  }

  .conceptPicker button[aria-pressed="true"] {
    background: var(--range-accent);
    color: var(--range-accent-ink);
    font-weight: 700;
  }

  .conceptPicker button:focus-visible {
    position: relative;
    z-index: 1;
    outline: 2px solid var(--range-accent);
    outline-offset: -2px;
  }

  .selectedState {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20px;
    color: var(--muted);
  }

  .pathPlayback {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
  }

  .playbackControls {
    display: flex;
    gap: 4px;
  }

  .playbackControl {
    display: grid;
    width: 30px;
    height: 30px;
    padding: 0;
    place-items: center;
    border: 0;
    border-radius: 8px;
    background: var(--range-accent);
    color: var(--range-accent-ink);
    cursor: pointer;
  }

  .playbackControl svg {
    width: 14px;
    height: 14px;
    fill: currentColor;
  }

  .spiralTrackControl {
    background: color-mix(in oklch, var(--range-accent) 42%, var(--paper));
  }

  .spiralTrackControl.enabled {
    background: var(--range-accent-ink);
    color: var(--paper);
  }

  .spiralTrackControl path {
    fill: none;
    stroke: currentColor;
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-width: 1.5;
  }

  .playbackControl:disabled {
    background: color-mix(in oklch, var(--range-accent) 28%, var(--paper));
    color: color-mix(in oklch, var(--range-accent-ink) 42%, var(--paper));
    cursor: default;
  }

  .playbackControl:focus-visible {
    outline: 2px solid var(--range-accent-ink);
    outline-offset: 2px;
  }

  .rangeGraph {
    width: 100%;
    height: auto;
    display: block;
    overflow: visible;
  }

  .nucleusGraph {
    margin-top: 8px;
  }

  .valueSpiral {
    fill: none;
    opacity: 0.3;
    stroke: oklch(0.78 0.025 236);
    stroke-dasharray: 2 7;
    stroke-linecap: round;
    stroke-width: 1;
    transition:
      opacity 220ms ease,
      stroke 220ms ease;
  }

  .valueSpiral.enabled {
    opacity: 0.62;
    stroke: var(--range-accent);
  }

  .valueSpiral.playing {
    animation: spiral-flow var(--rhythm-duration) linear infinite;
    stroke: var(--range-playing-accent);
  }

  .sourceNucleus,
  .conceptBranch {
    transition: color 220ms ease;
  }

  .numberNode text {
    fill: oklch(0.53 0.025 236);
    font-family: var(--font-geist-mono);
    font-size: 12px;
    font-weight: 700;
    dominant-baseline: middle;
    paint-order: stroke fill;
    stroke: var(--paper);
    stroke-linejoin: round;
    stroke-width: 7px;
    text-anchor: middle;
    transition:
      fill 220ms ease,
      filter 220ms ease;
  }

  .sourceNucleus.activeSource .numberNode text,
  .conceptBranch.active .numberNode text,
  .numberNode.spiralStepActive text {
    fill: currentColor;
  }

  .numberNode.spiralStepActive text {
    color: var(--range-playing-accent);
    font-weight: 800;
  }

  .sourceNucleus text,
  .branchName {
    fill: var(--muted);
    font-family: var(--font-geist-mono);
    font-size: 11px;
    text-anchor: middle;
  }

  .sourceNucleus .sourceLabel {
    text-anchor: end;
  }

  .conceptBranch.active .branchName {
    fill: currentColor;
    font-weight: 700;
  }

  .branchTrack {
    stroke: oklch(0.88 0.012 236);
    stroke-linecap: round;
    stroke-width: 1.2;
    transition: stroke 220ms ease;
  }

  .conceptBranch.active .branchTrack {
    stroke: currentColor;
  }

  .sourceNucleus.activeSource,
  .conceptBranch.active {
    color: var(--range-playing-accent);
  }

  .sourceNucleus.activeSource.rhythmA,
  .conceptBranch.active.rhythmA {
    animation: rhythm-color-a var(--rhythm-duration) linear both;
  }

  .sourceNucleus.activeSource.rhythmB,
  .conceptBranch.active.rhythmB {
    animation: rhythm-color-b var(--rhythm-duration) linear both;
  }

  @keyframes rhythm-color-a {
    0% {
      color: oklch(0.56 0.19 236);
    }
    18% {
      color: oklch(0.72 0.16 236);
    }
    58% {
      color: oklch(0.63 0.14 236);
    }
    82% {
      color: oklch(0.69 0.16 236);
    }
    100% {
      color: oklch(0.59 0.17 236);
    }
  }

  @keyframes spiral-flow {
    to {
      stroke-dashoffset: -18;
    }
  }

  @keyframes rhythm-color-b {
    0% {
      color: oklch(0.61 0.13 236);
    }
    12% {
      color: oklch(0.68 0.18 236);
    }
    38% {
      color: oklch(0.57 0.2 236);
    }
    72% {
      color: oklch(0.71 0.14 236);
    }
    100% {
      color: oklch(0.62 0.18 236);
    }
  }

  .circularScale circle {
    fill: none;
    stroke: color-mix(in oklch, var(--line) 62%, var(--paper));
    stroke-width: 1;
  }

  .circularScale text {
    fill: color-mix(in oklch, var(--muted) 68%, var(--paper));
    font-family: var(--font-geist-mono);
    font-size: 9px;
  }

  @media (prefers-reduced-motion: reduce) {
    .sourceNucleus.activeSource,
    .conceptBranch.active {
      animation: none;
    }
  }

  @media (max-width: 760px) {
    .rangeSection {
      padding: 52px 0;
    }

    .rangeHeader {
      grid-template-columns: 1fr;
      gap: 18px;
      margin-bottom: 30px;
    }

    .conceptPicker {
      width: 100%;
      overflow-x: auto;
    }

    .conceptPicker button {
      flex: 1 0 auto;
    }
  }

  @media (max-width: 520px) {
    .selectedState {
      align-items: flex-start;
      flex-direction: column;
      gap: 10px;
    }

    .pathPlayback {
      flex-wrap: wrap;
      justify-content: flex-start;
    }
  }
</style>
