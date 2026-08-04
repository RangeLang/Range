<script lang="ts">
  import { onMount } from "svelte";
  import HomePageContent from "$lib/components/HomePageContent.svelte";
  import OnboardingSphereShader from "$lib/components/OnboardingSphereShader.svelte";

  let fisheyeTarget = $state(1.5);
  let distortionTarget = $state(1);
  let glitter = $state(1);
  let brightness = $state(1);
  let size = $state(70);
  let growthTimeline = $state(0);
  let fisheyeTimeline = $state(0);
  let whiteoutTimeline = $state(0);
  let starFadeTimeline = $state(0);
  let entrancePlaying = $state(false);
  let exitPlaying = $state(false);
  let siteRevealed = $state(false);
  let homepageSwapTimeline = $state(0);
  let sphereStage = $state<"small" | "medium" | "fullscreen">("small");
  let renderedSize = $state(56);
  let renderedFisheye = $state(0);
  let renderedDistortion = $state(0);
  let dissolveAmount = $state(0);
  let entranceFrame: number | undefined;
  let exitFrame: number | undefined;
  let collapseFrame: number | undefined;
  let anchorFrame: number | undefined;
  let anchorScale = 1;
  let anchorPhase = 0;
  let anchorLastAt = 0;
  let anchorStartedAt = 0;
  let anchorSettledAt = 0;
  let stage: HTMLElement | undefined;
  let previewAudioContext: AudioContext | undefined;
  let previewSustain: {
    voices: OscillatorNode[];
    noise: AudioBufferSourceNode;
    noiseGain: GainNode;
    noiseLfo: OscillatorNode;
    toneGain: GainNode;
    harmonicGain: GainNode;
    harmonicLfo: OscillatorNode;
    harmonicLfoGain: GainNode;
    harmonics: OscillatorNode[];
    filter: BiquadFilterNode;
    gain: GainNode;
  } | undefined;
  const exitDuration = 1_000;
  const fullscreenHoldDuration = 260;
  const homepageRevealDuration = 800;
  // Flip to full-bleed before the exact diagonal so antialiasing cannot leave
  // a one-frame white flash in the viewport corners.
  const fullscreenCoverageEpsilon = 8;
  const firstInhaleDuration = 4_200;
  const anchorBreathPeriod = 13_500;
  const animatedFisheyePeak = 0.55;
  const breathingAmplitude = 56;
  const breathingFisheyeFloor = 0.18;
  const breathingWowFloor = 0.42;
  const breathingHarmonicFrequencies = [110.0, 146.83] as const;

  function reset() {
    if (entranceFrame !== undefined) cancelAnimationFrame(entranceFrame);
    if (exitFrame !== undefined) cancelAnimationFrame(exitFrame);
    if (collapseFrame !== undefined) cancelAnimationFrame(collapseFrame);
    if (anchorFrame !== undefined) cancelAnimationFrame(anchorFrame);
    entranceFrame = undefined;
    exitFrame = undefined;
    collapseFrame = undefined;
    anchorFrame = undefined;
    anchorScale = 1;
    anchorPhase = 0;
    anchorLastAt = 0;
    anchorStartedAt = 0;
    anchorSettledAt = 0;
    entrancePlaying = false;
    exitPlaying = false;
    siteRevealed = false;
    homepageSwapTimeline = 0;
    sphereStage = "small";
    fisheyeTarget = 1.5;
    distortionTarget = 1;
    glitter = 1;
    brightness = 1;
    size = 70;
    setGrowth(0);
    setFisheye(0);
    setDistortion(0);
    dissolveAmount = 0;
    whiteoutTimeline = 0;
    starFadeTimeline = 0;
  }

  function targetSize() {
    return Math.min(
      window.innerHeight * (size / 100),
      window.innerWidth * 0.76,
    );
  }

  function setGrowth(value: number) {
    growthTimeline = value;
    renderedSize = 56 + (targetSize() * anchorScale - 56) * value;
  }

  function smoothstep(value: number) {
    const clamped = Math.min(1, Math.max(0, value));
    return clamped * clamped * (3 - 2 * clamped);
  }

  function anchoredGrowth(value: number) {
    return smoothstep(value);
  }

  function breathingFrame(phaseValue: number) {
    // Keep the preview on the exact same symmetric size/lens/audio driver as
    // the real onboarding surface.
    const signal = Math.sin(phaseValue);
    return {
      signal,
      envelope: (signal + 1) * 0.5,
      size: targetSize() + signal * breathingAmplitude,
      // Keep the space outward-facing throughout the breath; never produce a
      // negative, concave fisheye as the sphere exhales.
      fisheye: animatedFisheyePeak * (
        breathingFisheyeFloor
          + (1 - breathingFisheyeFloor) * ((signal + 1) * 0.5)
      ),
    };
  }

  function stopAnchorSuspension() {
    if (anchorFrame !== undefined) cancelAnimationFrame(anchorFrame);
    anchorFrame = undefined;
    anchorScale = 1;
    if (growthTimeline > 0) setGrowth(growthTimeline);
  }

  function startAnchorSuspension(reanchor = false) {
    if (reanchor) {
      stopAnchorSuspension();
      // Begin at the low point: the first active half-cycle can only expand.
      anchorPhase = -Math.PI / 2;
      anchorLastAt = performance.now();
      anchorStartedAt = anchorLastAt;
    }
    if (anchorFrame !== undefined) return;
    const frame = (now: number) => {
      if (exitPlaying) {
        anchorFrame = undefined;
        return;
      }
      const interactionProgress = Math.min(
        1,
        Math.max(0, (now - anchorStartedAt) / firstInhaleDuration),
      );
      if (interactionProgress < 1) {
        // The zoom *is* the first inhale: low point to peak with no separate
        // breathing clock to catch up afterward.
        anchorPhase = -Math.PI / 2 + Math.PI * interactionProgress;
        const growth = anchoredGrowth(interactionProgress);
        const breathing = breathingFrame(anchorPhase);
        anchorScale = breathing.size / targetSize();
        shapeHashEnvelope(breathing.envelope);
        shapePreviewHarmonics(breathing.envelope);
        setGrowth(growth);
        setFisheye(animatedFisheyePeak * growth);
        setDistortion(0);
      } else if (entrancePlaying) {
        // At the exact inhale peak, transition into the normal breathing rate.
        anchorPhase = Math.PI / 2;
        anchorLastAt = now;
        entrancePlaying = false;
        anchorSettledAt = now;
        sphereStage = "medium";
        holdPreviewSustain(previewSustain, 0.18);
        shapeTwinkleHarmonics(1);
      }
      if (!entrancePlaying) {
        const elapsed = now - anchorLastAt;
        anchorLastAt = now;
        anchorPhase += elapsed / anchorBreathPeriod * Math.PI * 2;
        const breathing = breathingFrame(anchorPhase);
        anchorScale = breathing.size / targetSize();
        shapeHashEnvelope(breathing.envelope);
        shapePreviewWow(breathing.envelope);
        shapePreviewHarmonics(breathing.envelope);
        setGrowth(1);
        setFisheye(breathing.fisheye);
      }
      anchorFrame = requestAnimationFrame(frame);
    };
    anchorFrame = requestAnimationFrame(frame);
  }


  function setFisheye(value: number) {
    fisheyeTimeline = value;
    renderedFisheye = fisheyeTarget * value;
  }

  function setDistortion(value: number) {
    renderedDistortion = distortionTarget * value;
  }

  async function startPreviewSustain(motion = 0) {
    previewAudioContext ??= new AudioContext();
    await previewAudioContext.resume();
    const context = previewAudioContext;
    const now = context.currentTime;
    if (previewSustain) {
      shapePreviewSustain(motion);
      return;
    }
    const filter = context.createBiquadFilter();
    const gain = context.createGain();
    const drive = context.createWaveShaper();
    const dryGain = context.createGain();
    const reverb = context.createConvolver();
    const wetGain = context.createGain();
    const noise = context.createBufferSource();
    const noiseGain = context.createGain();
    const noiseFilter = context.createBiquadFilter();
    const noiseLfo = context.createOscillator();
    const noiseLfoGain = context.createGain();
    const toneGain = context.createGain();
    const harmonicGain = context.createGain();
    const harmonicLfo = context.createOscillator();
    const harmonicLfoGain = context.createGain();
    const harmonicDetuneGain = context.createGain();
    const curve = new Float32Array(256);
    const impulseLength = Math.floor(context.sampleRate * 0.82);
    const impulse = context.createBuffer(2, impulseLength, context.sampleRate);
    // Avoid a perceptible short-loop repeat in the distant hash texture.
    const noiseBuffer = context.createBuffer(1, context.sampleRate * 8, context.sampleRate);
    for (let index = 0; index < curve.length; index += 1) {
      const input = index * 2 / (curve.length - 1) - 1;
      curve[index] = Math.tanh(input * 1.2);
    }

    filter.type = "lowpass";
    for (let channel = 0; channel < impulse.numberOfChannels; channel += 1) {
      const samples = impulse.getChannelData(channel);
      for (let index = 0; index < samples.length; index += 1) {
        samples[index] = (Math.random() * 2 - 1) * Math.pow(1 - index / samples.length, 2.8);
      }
    }
    filter.frequency.setValueAtTime(230, now);
    filter.Q.setValueAtTime(0.14, now);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.linearRampToValueAtTime(0.0025, now + 1.1);
    drive.curve = curve;
    drive.oversample = "2x";
    reverb.buffer = impulse;
    dryGain.gain.setValueAtTime(0.82, now);
    wetGain.gain.setValueAtTime(0.18, now);
    filter.connect(drive);
    drive.connect(dryGain).connect(gain);
    drive.connect(reverb).connect(wetGain).connect(gain);
    gain.connect(context.destination);
    const noiseSamples = noiseBuffer.getChannelData(0);
    for (let index = 0; index < noiseSamples.length; index += 1) {
      noiseSamples[index] = Math.random() * 2 - 1;
    }
    noise.buffer = noiseBuffer;
    noise.loop = true;
    noiseFilter.type = "bandpass";
    noiseFilter.frequency.setValueAtTime(2_600, now);
    noiseFilter.Q.setValueAtTime(0.45, now);
    noiseGain.gain.setValueAtTime(0.04, now);
    noiseLfo.type = "sine";
    noiseLfo.frequency.setValueAtTime(0.07, now);
    // The anchor timeline owns the hash envelope so the sound and size share
    // one phase; keep this legacy LFO neutral.
    noiseLfoGain.gain.setValueAtTime(0, now);
    noiseLfo.connect(noiseLfoGain).connect(noiseGain.gain);
    noise.connect(noiseFilter).connect(noiseGain).connect(gain);
    noise.start(now);
    noiseLfo.start(now);
    toneGain.gain.setValueAtTime(0.0001, now);
    toneGain.connect(filter);
    harmonicGain.gain.setValueAtTime(0.0001, now);
    harmonicLfo.type = "sine";
    harmonicLfo.frequency.setValueAtTime(0.0125, now);
    harmonicLfoGain.gain.setValueAtTime(0.004, now);
    harmonicDetuneGain.gain.setValueAtTime(7, now);
    harmonicLfo.connect(harmonicLfoGain).connect(harmonicGain.gain);
    harmonicLfo.connect(harmonicDetuneGain);
    harmonicGain.connect(filter);
    harmonicLfo.start(now);

    const voices: OscillatorNode[] = [];
    for (const [frequency, detune, weight] of [
      [73.42, -3, 0.12],
      [110.0, 2, 0.08],
      [146.83, 5, 0.06],
    ] as const) {
      const voice = context.createOscillator();
      const voiceGain = context.createGain();
      voice.type = "sawtooth";
      voice.frequency.setValueAtTime(frequency, now);
      voice.detune.setValueAtTime(detune, now);
      voiceGain.gain.setValueAtTime(weight, now);
      voice.connect(voiceGain).connect(toneGain);
      voice.start(now);
      voices.push(voice);
    }
    const harmonics: OscillatorNode[] = [];
    for (const frequency of breathingHarmonicFrequencies) {
      const harmonic = context.createOscillator();
      harmonic.type = "sine";
      harmonic.frequency.setValueAtTime(frequency, now);
      harmonicDetuneGain.connect(harmonic.detune);
      harmonic.connect(harmonicGain);
      harmonic.start(now);
      harmonics.push(harmonic);
    }
    previewSustain = {
      voices, noise, noiseGain, noiseLfo, toneGain, harmonicGain, harmonicLfo, harmonicLfoGain, harmonics, filter, gain,
    };
    holdPreviewSustain(previewSustain, 0.05);
    shapePreviewSustain(motion);
  }

  function scheduleFirstInhale(sustain: NonNullable<typeof previewSustain>) {
    if (!previewAudioContext || previewSustain !== sustain) return;
    const now = previewAudioContext.currentTime;
    const steps = 96;
    const toneCurve = new Float32Array(steps);
    const gainCurve = new Float32Array(steps);
    const filterCurve = new Float32Array(steps);
    for (let index = 0; index < steps; index += 1) {
      const amount = smoothstep(index / (steps - 1));
      toneCurve[index] = 0.0001 + amount * 0.4199;
      gainCurve[index] = 0.0025 + amount * 0.0315;
      filterCurve[index] = 230 + amount * 1_180;
    }
    sustain.toneGain.gain.cancelScheduledValues(now);
    sustain.gain.gain.cancelScheduledValues(now);
    sustain.filter.frequency.cancelScheduledValues(now);
    sustain.toneGain.gain.setValueAtTime(0.0001, now);
    sustain.gain.gain.setValueAtTime(0.0025, now);
    sustain.filter.frequency.setValueAtTime(230, now);
    sustain.toneGain.gain.setValueCurveAtTime(toneCurve, now, firstInhaleDuration / 1_000);
    sustain.gain.gain.setValueCurveAtTime(gainCurve, now, firstInhaleDuration / 1_000);
    sustain.filter.frequency.setValueCurveAtTime(filterCurve, now, firstInhaleDuration / 1_000);
  }

  function holdPreviewSustain(sustain: NonNullable<typeof previewSustain>, level: number) {
    if (!previewAudioContext || previewSustain !== sustain) return;
    const now = previewAudioContext.currentTime;
    sustain.toneGain.gain.cancelScheduledValues(now);
    sustain.toneGain.gain.setTargetAtTime(level, now, 0.65);
  }

  function shapePreviewSustain(motion: number) {
    if (!previewSustain || !previewAudioContext) return;
    const now = previewAudioContext.currentTime;
    const amount = Math.min(1, Math.max(0, motion));
    previewSustain.filter.frequency.setTargetAtTime(230 + amount * 1_180, now, 0.2);
    previewSustain.gain.gain.setTargetAtTime(
      0.0025 + amount * 0.0315,
      now,
      amount > 0.001 ? 0.24 : 1.1,
    );
  }

  function shapePreviewWow(envelope: number) {
    if (!previewSustain || !previewAudioContext) return;
    const amount = Math.min(1, Math.max(0, envelope));
    const wowEnvelope = breathingWowFloor + (1 - breathingWowFloor) * amount;
    previewSustain.toneGain.gain.setTargetAtTime(
      0.18 * wowEnvelope,
      previewAudioContext.currentTime,
      0.55,
    );
  }

  function shapePreviewHarmonics(envelope: number) {
    if (!previewSustain || !previewAudioContext) return;
    const amount = Math.min(1, Math.max(0, envelope));
    const now = previewAudioContext.currentTime;
    previewSustain.harmonicGain.gain.setTargetAtTime(
      0.003 + amount * 0.009,
      now,
      0.55,
    );
    previewSustain.harmonicLfoGain.gain.setTargetAtTime(
      amount * 0.004,
      now,
      0.55,
    );
    for (const [index, harmonic] of previewSustain.harmonics.entries()) {
      const rise = 1 + amount * (index === 0 ? 0.18 : 0.24);
      harmonic.frequency.setTargetAtTime(
        breathingHarmonicFrequencies[index] * rise,
        now,
        0.55,
      );
    }
  }

  function shapeHashEnvelope(envelope: number) {
    if (!previewSustain || !previewAudioContext) return;
    const amount = Math.min(1, Math.max(0, envelope));
    previewSustain.noiseGain.gain.setTargetAtTime(
      0.018 + amount * 0.047,
      previewAudioContext.currentTime,
      0.18,
    );
  }

  function shapeTwinkleHarmonics(amount: number) {
    if (!previewSustain || !previewAudioContext) return;
    previewSustain.harmonicGain.gain.setTargetAtTime(
      Math.min(1, Math.max(0, amount)) * 0.012,
      previewAudioContext.currentTime,
      0.9,
    );
    previewSustain.harmonicLfoGain.gain.setTargetAtTime(
      Math.min(1, Math.max(0, amount)) * 0.004,
      previewAudioContext.currentTime,
      0.9,
    );
  }

  function releasePreviewSustain() {
    if (!previewSustain || !previewAudioContext) return;
    const sustain = previewSustain;
    previewSustain = undefined;
    const now = previewAudioContext.currentTime;
    sustain.gain.gain.cancelScheduledValues(now);
    sustain.gain.gain.setTargetAtTime(0.0001, now, 1.1);
    for (const voice of sustain.voices) voice.stop(now + 1.2);
    for (const harmonic of sustain.harmonics) harmonic.stop(now + 1.2);
    sustain.noise.stop(now + 1.2);
    sustain.noiseLfo.stop(now + 1.2);
    sustain.harmonicLfo.stop(now + 1.2);
  }

  function exitDiameter() {
    // Match the real flow: the fullscreen state is the measured viewport
    // diagonal, followed by the page handoff.
    if (typeof window === "undefined") return renderedSize;
    const viewportWidth = window.visualViewport?.width ?? window.innerWidth;
    const viewportHeight = window.visualViewport?.height ?? window.innerHeight;
    return Math.hypot(viewportWidth, viewportHeight);
  }

  async function playEntrance() {
    if (exitFrame !== undefined) cancelAnimationFrame(exitFrame);
    exitFrame = undefined;
    exitPlaying = false;
    stopAnchorSuspension();
    whiteoutTimeline = 0;
    starFadeTimeline = 0;
    siteRevealed = false;
    homepageSwapTimeline = 0;
    sphereStage = "small";
    setGrowth(0);
    setFisheye(0);
    setDistortion(0);
    dissolveAmount = 0;
    entrancePlaying = true;
    // The first click re-anchors the already-continuous suspended motion.
    await startPreviewSustain(0);
    if (!previewSustain || !entrancePlaying) return;
    scheduleFirstInhale(previewSustain);
    startAnchorSuspension(true);
  }

  function activateSphere() {
    if (entrancePlaying || exitPlaying) return;
    if (growthTimeline < 0.999) playEntrance();
    else playExit();
  }

  function collapsePreviewSphere() {
    if (entrancePlaying || exitPlaying || growthTimeline < 0.999) return;
    if (collapseFrame !== undefined) cancelAnimationFrame(collapseFrame);
    stopAnchorSuspension();
    const startingSize = renderedSize;
    const startingFisheye = fisheyeTimeline;
    const startingDistortion = renderedDistortion / Math.max(distortionTarget, 0.001);
    const startedAt = performance.now();
    entrancePlaying = true;
    const frame = (now: number) => {
      const progress = Math.min(1, (now - startedAt) / 2_400);
      const eased = smoothstep(progress);
      const remaining = 1 - eased;
      renderedSize = 56 + (startingSize - 56) * remaining;
      setFisheye(startingFisheye * remaining);
      setDistortion(0);
      shapeTwinkleHarmonics(remaining);
      shapePreviewSustain(remaining);
      if (progress < 1) collapseFrame = requestAnimationFrame(frame);
      else {
        collapseFrame = undefined;
        entrancePlaying = false;
        whiteoutTimeline = 0;
        starFadeTimeline = 0;
        sphereStage = "small";
        setGrowth(0);
        releasePreviewSustain();
      }
    };
    collapseFrame = requestAnimationFrame(frame);
  }

  function playExit() {
    if (entranceFrame !== undefined) cancelAnimationFrame(entranceFrame);
    entranceFrame = undefined;
    entrancePlaying = false;
    if (exitFrame !== undefined) cancelAnimationFrame(exitFrame);
    stopAnchorSuspension();
    whiteoutTimeline = 0;
    starFadeTimeline = 0;
    siteRevealed = false;
    homepageSwapTimeline = 0;
    exitPlaying = true;
    void startPreviewSustain(1);
    shapeTwinkleHarmonics(1);
    const startedAt = performance.now();
    const startingSize = renderedSize;
    const startingFisheye = fisheyeTimeline;
    const duration = exitDuration + fullscreenHoldDuration + homepageRevealDuration;
    const frame = (now: number) => {
      const elapsed = now - startedAt;
      const sphereProgress = Math.min(1, elapsed / exitDuration);
      const homepageProgress = Math.min(1, Math.max(
        0,
        elapsed - exitDuration - fullscreenHoldDuration,
      ) / homepageRevealDuration);
      whiteoutTimeline = 0;
      starFadeTimeline = 0;
      const easedSphere = smoothstep(sphereProgress);
      const finalDiameter = exitDiameter();
      renderedSize = startingSize + (finalDiameter - startingSize) * easedSphere;
      if (
        sphereProgress >= 1 ||
        finalDiameter - renderedSize <= fullscreenCoverageEpsilon
      ) {
        sphereStage = "fullscreen";
      }
      setFisheye(
        startingFisheye + (animatedFisheyePeak - startingFisheye) * easedSphere,
      );
      setDistortion(0);
      homepageSwapTimeline = smoothstep(homepageProgress);
      const revealTail = 1 - homepageSwapTimeline;
      shapePreviewSustain(revealTail);
      shapeTwinkleHarmonics(revealTail);
      if (homepageProgress > 0) siteRevealed = true;
      if (elapsed < duration) exitFrame = requestAnimationFrame(frame);
      else {
        exitFrame = undefined;
        exitPlaying = false;
        siteRevealed = true;
        releasePreviewSustain();
      }
    };
    exitFrame = requestAnimationFrame(frame);
  }

  onMount(() => {
    setGrowth(0);
    setFisheye(0);
    return () => {
      if (entranceFrame !== undefined) cancelAnimationFrame(entranceFrame);
      if (exitFrame !== undefined) cancelAnimationFrame(exitFrame);
      if (collapseFrame !== undefined) cancelAnimationFrame(collapseFrame);
      if (anchorFrame !== undefined) cancelAnimationFrame(anchorFrame);
      releasePreviewSustain();
      void previewAudioContext?.close();
    };
  });
</script>

<svelte:head>
  <title>Onboarding sphere playground</title>
</svelte:head>

<main class="playground">
  <aside class="controls" aria-label="Sphere effect controls">
    <div>
      <p class="eyebrow">Local preview</p>
      <h1>Sphere layers</h1>
      <p class="description">
        Tune the sky field and fisheye lens independently.
      </p>
    </div>

    <p class="sectionLabel">Effect targets</p>
    <label>
      <span>Fisheye <output>{fisheyeTarget.toFixed(2)}</output></span>
      <input type="range" min="0" max="1.5" step="0.01" bind:value={fisheyeTarget} />
    </label>
    <label>
      <span>Lens distortion <output>{distortionTarget.toFixed(2)}</output></span>
      <input type="range" min="0" max="2" step="0.01" bind:value={distortionTarget} />
    </label>
    <label>
      <span>Glitter <output>{glitter.toFixed(2)}</output></span>
      <input type="range" min="0" max="2.5" step="0.01" bind:value={glitter} />
    </label>
    <label>
      <span>Field brightness <output>{brightness.toFixed(2)}</output></span>
      <input type="range" min="0" max="1.8" step="0.01" bind:value={brightness} />
    </label>
    <label>
      <span>Sphere size <output>{size}vmin</output></span>
      <input type="range" min="24" max="86" step="1" bind:value={size} />
    </label>
    <p class="sectionLabel">Timelines</p>
    <label>
      <span>Growth <output>{Math.round(growthTimeline * 100)}%</output></span>
      <input
        type="range"
        min="0"
        max="1"
        step="0.001"
        value={growthTimeline}
        oninput={(event) => setGrowth(Number(event.currentTarget.value))}
      />
    </label>
    <label>
      <span>Fisheye <output>{Math.round(fisheyeTimeline * 100)}%</output></span>
      <input
        type="range"
        min="0"
        max="1"
        step="0.001"
        value={fisheyeTimeline}
        oninput={(event) => setFisheye(Number(event.currentTarget.value))}
      />
    </label>
    <label>
      <span>Sky whiteout <output>{Math.round(whiteoutTimeline * 100)}%</output></span>
      <input type="range" min="0" max="1" step="0.001" bind:value={whiteoutTimeline} />
    </label>
    <label>
      <span>Star fade <output>{Math.round(starFadeTimeline * 100)}%</output></span>
      <input type="range" min="0" max="1" step="0.001" bind:value={starFadeTimeline} />
    </label>
    <div class="actions">
      <button type="button" onclick={playEntrance} disabled={entrancePlaying || exitPlaying}>
        {entrancePlaying ? "Growing…" : "Play first click + tone"}
      </button>
      <button type="button" onclick={playExit} disabled={exitPlaying}>
        {exitPlaying ? "Revealing…" : "Play second click + tone"}
      </button>
      <button type="button" onclick={reset}>Reset</button>
    </div>
  </aside>

  <section bind:this={stage} class="stage" aria-label="Live sphere preview" onclick={collapsePreviewSphere}>
    <div
      class="siteContent"
      class:revealed={siteRevealed}
      aria-hidden="true"
      style={`opacity: ${homepageSwapTimeline}; filter: blur(${(1 - homepageSwapTimeline) * 18}px); transform: scale(${1 + (1 - homepageSwapTimeline) * 0.018});`}
    >
      <HomePageContent />
    </div>
    <div
      class="exitLayer"
      class:revealed={siteRevealed}
      style={`opacity: ${1 - homepageSwapTimeline}; filter: blur(${homepageSwapTimeline * 18}px); transform: scale(${1 + homepageSwapTimeline * 0.025});`}
    >
      <button
        type="button"
        class="sphere"
        aria-label="Play sphere exit"
        onpointerenter={() => void startPreviewSustain()}
        onpointerleave={() => {
          if (!entrancePlaying && !exitPlaying) releasePreviewSustain();
        }}
        onclick={(event) => {
          event.stopPropagation();
          activateSphere();
        }}
        disabled={exitPlaying}
        style={`--exit-size: ${renderedSize}px;`}
      >
        <OnboardingSphereShader
          fisheyeAmount={renderedFisheye}
          fullBleed={sphereStage === "fullscreen"}
          distortionAmount={renderedDistortion}
          starOpacity={glitter * (1 - smoothstep(starFadeTimeline))}
          fieldBrightness={brightness}
          dissolveAmount={dissolveAmount}
          whiteoutAmount={smoothstep(whiteoutTimeline)}
        />
      </button>
    </div>
  </section>
</main>

<style>
  :global(html) {
    background: oklch(0.98 0.003 255);
  }

  .playground {
    display: grid;
    grid-template-columns: minmax(230px, 300px) minmax(0, 1fr);
    width: 100%;
    min-height: 0;
    height: 100svh;
    margin: 0;
    padding: 0;
    background: oklch(0.98 0.003 255);
    color: oklch(0.18 0.018 255);
    font-family: var(--font-geist-mono), monospace;
  }

  .controls {
    display: grid;
    align-content: start;
    gap: 20px;
    overflow-y: auto;
    padding: 28px;
    border-right: 1px solid oklch(0.84 0.01 255);
    background: oklch(1 0 0 / 0.8);
  }

  .eyebrow,
  h1,
  .description {
    margin: 0;
  }

  .sectionLabel {
    margin: 4px 0 -8px;
    color: oklch(0.48 0.025 255);
    font-size: 10px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
  }

  .eyebrow {
    margin-bottom: 8px;
    color: oklch(0.5 0.02 255);
    font-size: 10px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
  }

  h1 {
    font-size: 20px;
    font-weight: 500;
  }

  .description {
    margin-top: 10px;
    color: oklch(0.43 0.015 255);
    font-size: 12px;
    line-height: 1.55;
  }

  label {
    display: grid;
    gap: 8px;
    color: oklch(0.33 0.015 255);
    font-size: 11px;
  }

  label span {
    display: flex;
    justify-content: space-between;
    gap: 16px;
  }

  output {
    color: oklch(0.51 0.04 255);
  }

  input {
    width: 100%;
    accent-color: oklch(0.38 0.12 255);
  }

  button {
    padding: 10px 12px;
    border: 1px solid oklch(0.74 0.02 255);
    border-radius: 6px;
    background: oklch(1 0 0);
    color: inherit;
    font: inherit;
    font-size: 11px;
    cursor: pointer;
  }

  .actions {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
  }

  button:disabled {
    cursor: default;
    opacity: 0.52;
  }

  .stage {
    position: relative;
    display: grid;
    min-width: 0;
    place-items: center;
    overflow: hidden;
    background: oklch(1 0 0);
  }

  .siteContent {
    position: absolute;
    inset: 0;
    z-index: 0;
    overflow: hidden;
    background: transparent;
    pointer-events: none;
    transform-origin: center;
    will-change: opacity, filter, transform;
  }

  .siteContent.revealed {
    z-index: 2;
  }

  .siteContent :global([data-range-home-page] > *) {
    opacity: 0;
    transform: translateY(10px);
  }

  .siteContent.revealed :global([data-range-home-page] > *) {
    opacity: 1;
    transform: none;
  }

  .exitLayer {
    position: absolute;
    inset: 0;
    z-index: 1;
    display: grid;
    place-items: center;
    background: transparent;
    transform-origin: center;
    will-change: opacity, filter, transform;
  }

  .sphere {
    position: absolute;
    top: 50%;
    left: 50%;
    width: var(--exit-size);
    height: var(--exit-size);
    overflow: hidden;
    padding: 0;
    border: 0;
    border-radius: 50%;
    background: transparent;
    transform: translate(-50%, -50%);
    transform-origin: center;
    cursor: pointer;
  }

  .sphere:disabled {
    opacity: 1;
  }

  .stage :global(.sphere[data-shader-rendered="true"]) {
    border-radius: 0;
    overflow: visible;
  }

  @media (max-width: 760px) {
    .playground {
      grid-template-columns: 1fr;
      height: auto;
    }

    .controls {
      grid-template-columns: repeat(2, minmax(0, 1fr));
      overflow-y: visible;
      border-right: 0;
      border-bottom: 1px solid oklch(0.84 0.01 255);
    }

    .controls > :first-child,
    .controls > .actions {
      grid-column: 1 / -1;
    }

    .stage {
      min-height: 62vh;
      padding: 20px;
    }

    .sphere {
      max-width: 100%;
    }
  }
</style>
