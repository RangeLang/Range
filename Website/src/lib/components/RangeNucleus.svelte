<script lang="ts">
  import { onDestroy, onMount } from "svelte";
  import {
    rangePlaybackOrder,
    rangePlaybackStep,
  } from "$lib/range-rhythm";

  type ConceptID = "shape" | "ownership" | "capability";

  type Concept = {
    path: number[];
    labels: Record<number, string>;
  };

  const concepts: Record<ConceptID, Concept> = {
    shape: {
      path: [1, 2, 4],
      labels: { 1: "source", 2: "step", 4: "result" },
    },
    ownership: {
      path: [1, 2, 8],
      labels: { 1: "value", 2: "transfer", 8: "effect paths" },
    },
    capability: {
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
  const spiralSteps = [
    { conceptID: "shape", value: 4, detuneCents: -5 },
    { conceptID: "ownership", value: 8, detuneCents: 0 },
    { conceptID: "capability", value: 16, detuneCents: 4 },
  ] as const;
  let selectedID = $state<ConceptID>("shape");
  let looping = $state(false);
  let spiralActiveIndex = $state(-1);
  let playbackStepIndex = 0;
  let audioContext: AudioContext | undefined;
  let audioMasterInput: GainNode | undefined;
  let audioMasterCompressor: DynamicsCompressorNode | undefined;
  let audioMasterOutput: GainNode | undefined;
  let reverbInput: GainNode | undefined;
  let distantVoiceGain: GainNode | undefined;
  let distantVoiceFilter: BiquadFilterNode | undefined;
  let sectionElement: HTMLElement;
  let scrollFilterPosition = 0;
  let activeOscillators: OscillatorNode[] = [];
  let loopTimer: number | undefined;

  const center = 382;
  const centerY = 320;
  const spiralFlowDurationSeconds = 16;
  const spiralDashCount = 30;
  const spiralDashStartLength = 3.2;
  const spiralDashEndLength = 12;
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
    const sampleCount = 96;
    return Array.from({ length: sampleCount + 1 }, (_, index) => {
      const point = spiralPoint(index / sampleCount);
      return `${index === 0 ? "M" : "L"} ${point.x} ${point.y}`;
    }).join(" ");
  }

  function spiralRestingDashPattern() {
    const sampleCount = 128;
    let previous = spiralPoint(0);
    let length = 0;

    for (let index = 1; index <= sampleCount; index += 1) {
      const point = spiralPoint(index / sampleCount);
      length += Math.hypot(point.x - previous.x, point.y - previous.y);
      previous = point;
    }

    const pattern: number[] = [];
    let cursor = 0;
    while (cursor < length) {
      const logarithmicMagnitude = Math.log2(
        4 * Math.pow(4, cursor / length),
      );
      const dashProgress = (logarithmicMagnitude - Math.log2(4)) / 2;
      const dashLength =
        spiralDashStartLength +
        (spiralDashEndLength - spiralDashStartLength) * dashProgress;
      const gapLength = 2.8 + logarithmicMagnitude * 1.25;
      pattern.push(dashLength, gapLength);
      cursor += dashLength + gapLength;
    }
    return pattern.join(" ");
  }

  const restingSpiralPattern = spiralRestingDashPattern();

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

  function getAudioMasterInput() {
    if (!audioContext) return;
    if (audioMasterInput) return audioMasterInput;

    audioMasterInput = audioContext.createGain();
    audioMasterCompressor = audioContext.createDynamicsCompressor();
    audioMasterOutput = audioContext.createGain();
    audioMasterInput.gain.value = 1.8;
    audioMasterCompressor.threshold.value = -28;
    audioMasterCompressor.knee.value = 8;
    audioMasterCompressor.ratio.value = 12;
    audioMasterCompressor.attack.value = 0.003;
    audioMasterCompressor.release.value = 0.12;
    audioMasterOutput.gain.value = 1;
    audioMasterInput.connect(audioMasterCompressor);
    audioMasterCompressor.connect(audioMasterOutput);
    audioMasterOutput.connect(audioContext.destination);
    return audioMasterInput;
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
    resonance.frequency.value = 420;
    resonance.Q.value = 0.65;
    wet.gain.value = 0.62;
    input.connect(convolver);
    convolver.connect(rumbleCut);
    rumbleCut.connect(resonance);
    resonance.connect(wet);
    const master = getAudioMasterInput();
    if (master) wet.connect(master);
    reverbInput = input;
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
    distantVoiceGain = undefined;
    distantVoiceFilter = undefined;
    playbackStepIndex = 0;
    spiralActiveIndex = -1;
    looping = false;
  }

  function scrollFilterFrequency(position: number) {
    const minimum = 190;
    const maximum = 760;
    return minimum + (maximum - minimum) * position;
  }

  function updateScrollFilter() {
    if (!sectionElement || typeof window === "undefined") return;
    const bounds = sectionElement.getBoundingClientRect();
    const viewportCenter = window.innerHeight / 2;
    const sectionCenter = bounds.top + bounds.height / 2;
    const reach = window.innerHeight * 0.92 + bounds.height * 0.12;
    const proximity = Math.max(
      0,
      Math.min(1, 1 - Math.abs(sectionCenter - viewportCenter) / reach),
    );
    scrollFilterPosition = proximity * proximity * (3 - 2 * proximity);

    if (!audioContext || !distantVoiceFilter) return;
    const now = audioContext.currentTime;
    distantVoiceFilter.frequency.cancelScheduledValues(now);
    distantVoiceFilter.frequency.setTargetAtTime(
      scrollFilterFrequency(scrollFilterPosition),
      now,
      0.08,
    );
  }

  function murmurVelocityEnvelope(
    duration: number,
    peakGain: number,
    bodyGain: number,
  ) {
    const sampleCount = Math.max(128, Math.ceil(duration * 144));
    const envelope = new Float32Array(sampleCount);
    const floor = 0.0001;
    const accentEnd = 0.38;
    const bodyEnd = 0.52;
    const ease = (progress: number) => (1 - Math.cos(Math.PI * progress)) / 2;

    for (let index = 0; index < sampleCount; index += 1) {
      const progress = index / (sampleCount - 1);
      if (progress <= accentEnd) {
        envelope[index] = floor
          + (peakGain - floor) * ease(progress / accentEnd);
      } else if (progress <= bodyEnd) {
        envelope[index] = peakGain
          + (bodyGain - peakGain)
          * ease((progress - accentEnd) / (bodyEnd - accentEnd));
      } else {
        envelope[index] = bodyGain
          + (floor - bodyGain)
          * ease((progress - bodyEnd) / (1 - bodyEnd));
      }
    }

    return envelope;
  }

  function startDistantVoice() {
    if (!audioContext || distantVoiceGain) return;
    const startAt = audioContext.currentTime + 0.03;
    const voiceGain = audioContext.createGain();
    const voiceFilter = audioContext.createBiquadFilter();
    const direct = audioContext.createGain();
    const fundamental = audioContext.createOscillator();
    const fundamentalGain = audioContext.createGain();
    const haze = audioContext.createOscillator();
    const hazeGain = audioContext.createGain();
    const breath = audioContext.createOscillator();
    const breathDepth = audioContext.createGain();

    voiceGain.gain.setValueAtTime(0.09, startAt);
    voiceFilter.type = "lowpass";
    voiceFilter.frequency.value = scrollFilterFrequency(scrollFilterPosition);
    voiceFilter.Q.value = 0.28;
    direct.gain.value = 0.14;

    fundamental.type = "sine";
    fundamental.frequency.value = intervalNote.frequency - 0.22;
    fundamentalGain.gain.value = 0.78;
    haze.type = "triangle";
    haze.frequency.value = intervalNote.frequency + 0.31;
    hazeGain.gain.value = 0.09;

    breath.type = "sine";
    breath.frequency.value = 0.037;
    breathDepth.gain.value = 0.0038;
    breath.connect(breathDepth);
    breathDepth.connect(voiceGain.gain);

    fundamental.connect(fundamentalGain);
    fundamentalGain.connect(voiceFilter);
    haze.connect(hazeGain);
    hazeGain.connect(voiceFilter);
    voiceFilter.connect(voiceGain);
    voiceGain.connect(direct);
    const master = getAudioMasterInput();
    if (master) direct.connect(master);
    const reverb = getReverbInput();
    if (reverb) voiceGain.connect(reverb);

    fundamental.start(startAt);
    haze.start(startAt);
    breath.start(startAt);
    activeOscillators.push(fundamental, haze, breath);
    distantVoiceGain = voiceGain;
    distantVoiceFilter = voiceFilter;
  }

  function playIntervalNote() {
    if (!looping) return;
    const currentStep = rangePlaybackStep(playbackStepIndex);
    const stepDuration = currentStep.windowSeconds;
    const noteDuration = currentStep.noteSeconds;
    const spiralStepIndex = conceptIDs.indexOf(currentStep.conceptID);
    const spiralStep = spiralSteps[spiralStepIndex];
    selectedID = currentStep.conceptID;

    playSpiralTone(
      spiralStep.detuneCents,
      Math.max(noteDuration + 1.6, stepDuration * 1.8),
    );
    spiralActiveIndex = spiralStepIndex;
    playbackStepIndex = (playbackStepIndex + 1) % rangePlaybackOrder.length;
    loopTimer = window.setTimeout(() => {
      if (!looping) return;
      playIntervalNote();
    }, stepDuration * 1000);
  }

  function playSpiralTone(detuneCents: number, duration: number) {
    if (!looping || !audioContext) return;
    const startAt = audioContext.currentTime + Math.min(0.16, duration * 0.04);
    const noteEnd = startAt + duration;
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();

    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(intervalNote.frequency, startAt);
    oscillator.detune.setValueAtTime(detuneCents, startAt);
    gain.gain.setValueCurveAtTime(
      murmurVelocityEnvelope(duration, 0.006, 0.0048),
      startAt,
      duration,
    );
    oscillator.connect(gain);
    const reverb = getReverbInput();
    if (reverb) gain.connect(reverb);
    oscillator.start(startAt);
    oscillator.stop(noteEnd + 0.02);
    activeOscillators.push(oscillator);
    oscillator.onended = () => {
      activeOscillators = activeOscillators.filter((active) => active !== oscillator);
    };
  }

  async function startPlayback() {
    if (looping) return;
    stopPlayback();
    audioContext ??= new AudioContext();
    if (audioContext.state === "suspended") await audioContext.resume();
    looping = true;
    startDistantVoice();
    playIntervalNote();
  }

  function selectConcept(conceptID: ConceptID) {
    stopPlayback();
    selectedID = conceptID;
  }

  onMount(() => {
    let frame = 0;
    const scheduleFilterUpdate = () => {
      if (frame) return;
      frame = window.requestAnimationFrame(() => {
        frame = 0;
        updateScrollFilter();
      });
    };

    updateScrollFilter();
    window.addEventListener("scroll", scheduleFilterUpdate, { passive: true });
    window.addEventListener("resize", scheduleFilterUpdate);

    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      window.removeEventListener("scroll", scheduleFilterUpdate);
      window.removeEventListener("resize", scheduleFilterUpdate);
    };
  });

  onDestroy(() => {
    stopPlayback();
    void audioContext?.close();
    audioMasterInput = undefined;
    audioMasterCompressor = undefined;
    audioMasterOutput = undefined;
    reverbInput = undefined;
  });

</script>

<section class="rangeSection" aria-labelledby="range-title" bind:this={sectionElement}>
  <header class="rangeHeader">
    <h2 id="range-title">Cardinality</h2>
    <p>
      Range treats source and compiler as one graph-backed model.
    </p>
  </header>

  <div class="graphControls">
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
    <div class="pathPlayback">
      <div class="playbackControls" role="group" aria-label="Interval note playback">
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
    aria-label="A shared source nucleus with Shape, Ownership, and Capability branching outward across a concentric value scale. Small dots mark each value and only the sounding concept is accented."
  >
    <g class="circularScale" aria-hidden="true">
      {#each circularScaleValues as value}
        {@const radius = numericRadius(value)}
        <circle cx={center} cy={centerY} r={radius}></circle>
      {/each}
    </g>

    <g class="valueSpiral" class:playing={looping} aria-hidden="true">
      <path
        id="value-spiral-motion-path"
        class="spiralMotionPath"
        d={spiralPathData()}
      ></path>
      {#if looping}
        {#each Array.from({ length: spiralDashCount }) as _, index}
          {@const delay = -(index / spiralDashCount) * spiralFlowDurationSeconds}
          <line
            class="spiralDash"
            x1={-spiralDashStartLength / 2}
            x2={spiralDashStartLength / 2}
            y1="0"
            y2="0"
          >
            <animateMotion
              dur={`${spiralFlowDurationSeconds}s`}
              begin={`${delay}s`}
              repeatCount="indefinite"
              rotate="auto"
            >
              <mpath href="#value-spiral-motion-path"></mpath>
            </animateMotion>
            <animate
              attributeName="x1"
              values={`${-spiralDashStartLength / 2};${-spiralDashEndLength / 2}`}
              dur={`${spiralFlowDurationSeconds}s`}
              begin={`${delay}s`}
              repeatCount="indefinite"
            ></animate>
            <animate
              attributeName="x2"
              values={`${spiralDashStartLength / 2};${spiralDashEndLength / 2}`}
              dur={`${spiralFlowDurationSeconds}s`}
              begin={`${delay}s`}
              repeatCount="indefinite"
            ></animate>
            <animate
              attributeName="opacity"
              values="0;0.62;0.62;0"
              keyTimes="0;0.06;0.94;1"
              dur={`${spiralFlowDurationSeconds}s`}
              begin={`${delay}s`}
              repeatCount="indefinite"
            ></animate>
          </line>
        {/each}
      {:else}
        <path
          class="spiralRestingTrack"
          d={spiralPathData()}
          style={`--spiral-resting-pattern: ${restingSpiralPattern}`}
        ></path>
      {/if}
    </g>

    {#each conceptIDs as conceptID}
      {@const concept = concepts[conceptID]}
      {@const branchActive = looping && selectedID === conceptID}
      {@const labelPoint = branchLabelPoint(conceptID, concept)}
      {@const dashSegments = branchDashSegments(conceptID, concept)}
      <g
        class="conceptBranch"
        class:active={branchActive}
        data-concept-branch={conceptID}
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
            class:spiralStepActive={looping &&
              spiralSteps[spiralActiveIndex]?.conceptID === conceptID &&
              spiralSteps[spiralActiveIndex]?.value === value}
            transform={`translate(${point.x} ${point.y})`}
          >
            <title>{conceptID} {value} · {noteForValue(concept, value).name}</title>
            <circle class="valueDot" r="2.8"></circle>
          </g>
        {/each}

        <text class="branchName" x={labelPoint.x} y={labelPoint.y}>
          {conceptID}
        </text>
      </g>
    {/each}

    <g
      class:activeSource={looping}
      class="sourceNucleus"
    >
      <g class="numberNode sourceNumber" transform={`translate(${center} ${centerY})`}>
        <title>1 · shared source</title>
        <circle class="valueDot" r="3"></circle>
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
    margin: 0 auto;
    overflow: hidden;
  }

  .conceptPicker button {
    min-height: 38px;
    padding: 0 14px;
    border: 0;
    background: transparent;
    color: var(--muted);
    font: 500 12px var(--font-geist-mono);
    cursor: pointer;
  }

  .conceptPicker button[aria-pressed="true"] {
    color: var(--range-accent-ink);
    font-weight: 700;
  }

  .conceptPicker button:focus-visible {
    position: relative;
    z-index: 1;
    outline: 2px solid var(--range-accent);
    outline-offset: -2px;
  }

  .graphControls {
    position: relative;
    min-height: 38px;
    margin-bottom: 22px;
  }

  .pathPlayback {
    position: absolute;
    top: 50%;
    right: 0;
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
    transform: translateY(-50%);
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
  }

  .spiralMotionPath {
    fill: none;
    stroke: none;
  }

  .spiralRestingTrack {
    fill: none;
    opacity: 0.62;
    stroke: var(--range-accent);
    stroke-dasharray: var(--spiral-resting-pattern);
    stroke-linecap: round;
    stroke-width: 1;
  }

  .spiralDash {
    opacity: 0.62;
    stroke: var(--range-accent);
    stroke-linecap: round;
    stroke-width: 1;
  }

  .valueSpiral.playing .spiralDash {
    stroke: var(--range-playing-accent);
  }

  .valueDot {
    fill: oklch(0.53 0.025 236);
    stroke: var(--paper);
    stroke-width: 2px;
  }

  .sourceNucleus.activeSource .valueDot,
  .conceptBranch.active .valueDot,
  .numberNode.spiralStepActive .valueDot {
    fill: currentColor;
  }

  .numberNode.spiralStepActive .valueDot {
    color: var(--range-playing-accent);
    filter: drop-shadow(0 0 3px color-mix(in oklch, currentColor 38%, transparent));
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
  }

  .conceptBranch.active .branchTrack {
    stroke: currentColor;
  }

  .sourceNucleus.activeSource,
  .conceptBranch.active {
    color: var(--range-playing-accent);
  }

  .circularScale circle {
    fill: none;
    stroke: color-mix(in oklch, var(--line) 62%, var(--paper));
    stroke-width: 1;
  }

  @media (prefers-reduced-motion: reduce) {
    .valueSpiral.playing {
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
      width: fit-content;
      max-width: 100%;
      overflow-x: auto;
    }

    .conceptPicker button {
      flex: 1 0 auto;
    }

    .pathPlayback {
      position: static;
      justify-content: center;
      margin-top: 12px;
      transform: none;
    }
  }
</style>
