<script lang="ts">
  import { getContext, onMount } from "svelte";
  import {
    RANGE_SOUND_MANAGER_CONTEXT,
    type RangeSoundManager,
    type RangeSoundRoute,
  } from "$lib/audio/sound-manager";
  import {
    RANGE_ONBOARDING_MACHINE_CONTEXT,
    type OnboardingEffect,
    type OnboardingInput,
    type OnboardingSnapshot,
    type RangeOnboardingMachine,
  } from "$lib/interaction/onboarding-machine";
  import OnboardingSphereShader from "$lib/components/OnboardingSphereShader.svelte";

  const storageKey = "range:sound-onboarding:v1";
  const soundManager = getContext<RangeSoundManager | undefined>(
    RANGE_SOUND_MANAGER_CONTEXT,
  );
  const onboardingMachine = getContext<RangeOnboardingMachine>(
    RANGE_ONBOARDING_MACHINE_CONTEXT,
  );

  let machineSnapshot = $state<OnboardingSnapshot>(
    onboardingMachine.getSnapshot(),
  );
  let phase = $derived(machineSnapshot.phase);
  let concreteness = $derived(machineSnapshot.reveal);
  let completionTimer: number | undefined;
  let entryTimer: number | undefined;
  let leaveTimer: number | undefined;
  let activationPadStarted = false;
  let activationPadStarting = false;
  let route: RangeSoundRoute | undefined;
  let liveAttackGain: GainNode | undefined;
  let liveBreathGain: GainNode | undefined;
  let liveHashGain: GainNode | undefined;
  let liveBreathFilter: BiquadFilterNode | undefined;
  let liveNoise: AudioBufferSourceNode | undefined;
  let liveVoices: OscillatorNode[] = [];
  let liveLevel = 0.055;
  let lastBreathShapeAt = -Infinity;
  let sphereEpoch = typeof performance === "undefined" ? 0 : performance.now();
  let fisheyeAmount = $state(0);
  let lensDistortionAmount = $state(0);
  let exitDiameter = $state(0);
  let sphereSize = $state(56);
  let whiteoutTimeline = $state(0);
  let twinkleTimeline = $state(0);
  let starFadeTimeline = $state(0);
  let homepageSwapTimeline = $state(0);
  let sphereFrame: number | undefined;
  let exitFrame: number | undefined;
  let collapseFrame: number | undefined;
  let anchorPhase = -Math.PI / 2;
  let anchorLastAt = 0;
  let anchorStartedAt = 0;
  let anchorSettledAt = 0;
  let liveCollapsing = $state(false);
  const entryDuration = 4_200;
  const exitDuration = 1_000;
  const fullscreenHoldDuration = 260;
  const homepageRevealDuration = 800;
  const anchorBreathPeriod = 13_500;

  function smoothstep(value: number) {
    const clamped = Math.min(1, Math.max(0, value));
    return clamped * clamped * (3 - 2 * clamped);
  }

  function setHomepageSwap(value: number) {
    homepageSwapTimeline = Math.min(1, Math.max(0, value));
    if (typeof document === "undefined") return;
    const incoming = homepageSwapTimeline;
    document.documentElement.style.setProperty(
      "--range-homepage-opacity",
      incoming.toFixed(4),
    );
    document.documentElement.style.setProperty(
      "--range-homepage-blur",
      `${((1 - incoming) * 18).toFixed(2)}px`,
    );
    document.documentElement.style.setProperty(
      "--range-homepage-scale",
      (1 + (1 - incoming) * 0.018).toFixed(5),
    );
  }

  function naturalBreathEnvelope(phaseValue: number) {
    // Preserve one inhale and one exhale per cycle, but linger gently at each
    // turn instead of reading as a mechanically uniform sine wave.
    return smoothstep((Math.sin(phaseValue) + 1) * 0.5);
  }

  function anchoredBreathSignal(phaseValue: number) {
    // The second harmonic preserves a little forward inertia through the
    // inhale peak, producing one soft overshoot before the exhale takes over.
    return (
      naturalBreathEnvelope(phaseValue) * 2 - 1
        - Math.sin(phaseValue * 2) * 0.16
    ) / 1.1131;
  }

  function anchoredSphereSize(phaseValue: number) {
    const anchor = targetSphereSize();
    const signal = anchoredBreathSignal(phaseValue);
    const inhaleWeight = smoothstep((signal + 1) * 0.5);
    const swingDistance = 56 + (anchor * 0.05 - 56) * inhaleWeight;
    return anchor + signal * swingDistance;
  }

  function targetSphereSize() {
    return Math.min(window.innerHeight * 0.7, window.innerWidth * 0.76);
  }

  function stopSphereTimeline() {
    if (sphereFrame !== undefined) cancelAnimationFrame(sphereFrame);
    sphereFrame = undefined;
  }

  function shapeLiveBreath(envelope: number, residual = 1, force = false) {
    if (!route || !liveBreathGain || !liveHashGain || !liveBreathFilter) return;
    const context = route.audioContext;
    const now = context.currentTime;
    if (!force && now - lastBreathShapeAt < 0.04) return;
    lastBreathShapeAt = now;
    const breath = Math.min(1, Math.max(0, envelope));
    const tail = Math.min(1, Math.max(0, residual));
    const masterLevel = Math.max(0.0001, (0.0045 + liveLevel * 0.52 * breath) * tail);
    const hashLevel = Math.max(0.0001, (0.01 + breath * 0.025) * tail);
    liveBreathGain.gain.setTargetAtTime(masterLevel, now, 0.55);
    liveHashGain.gain.setTargetAtTime(hashLevel, now, 0.7);
    liveBreathFilter.frequency.setTargetAtTime(240 + breath * 320, now, 0.75);
  }

  function stopLiveBreath() {
    if (route && liveAttackGain) {
      const now = route.audioContext.currentTime;
      liveAttackGain.gain.cancelAndHoldAtTime(now);
      liveAttackGain.gain.setTargetAtTime(0.0001, now, 0.24);
    }
    if (route && liveBreathGain) {
      liveBreathGain.gain.setTargetAtTime(0.0001, route.audioContext.currentTime, 0.12);
    }
    const stopAt = route ? route.audioContext.currentTime + 0.8 : 0;
    try {
      liveNoise?.stop(stopAt);
    } catch {
      // The source may already have ended during teardown.
    }
    for (const voice of liveVoices) {
      try {
        voice.stop(stopAt);
      } catch {
        // The source may already have ended during teardown.
      }
    }
    liveNoise = undefined;
    liveVoices = [];
    liveAttackGain = undefined;
    liveBreathGain = undefined;
    liveHashGain = undefined;
    liveBreathFilter = undefined;
    lastBreathShapeAt = -Infinity;
  }

  function startSphereTimeline() {
    stopSphereTimeline();
    anchorPhase = -Math.PI / 2;
    anchorStartedAt = performance.now();
    anchorLastAt = anchorStartedAt;
    anchorSettledAt = 0;
    twinkleTimeline = 0;
    whiteoutTimeline = 0;
    starFadeTimeline = 0;
    setHomepageSwap(0);
    const frame = (now: number) => {
      const entryProgress = Math.min(1, Math.max(0, (now - anchorStartedAt) / entryDuration));
      if (entryProgress < 1) {
        anchorPhase = -Math.PI / 2 + Math.PI * entryProgress;
        const breathSignal = anchoredBreathSignal(anchorPhase);
        shapeLiveBreath((Math.sin(anchorPhase) + 1) * 0.5);
        const growth = smoothstep(entryProgress);
        const earlySwing = breathSignal
          * 0.042
          * (1 - smoothstep(growth))
          * smoothstep((now - anchorStartedAt) / 1_200);
        const anchorScale = anchoredSphereSize(anchorPhase) / targetSphereSize()
          + earlySwing;
        sphereSize = 56 + (targetSphereSize() * anchorScale - 56) * growth;
        fisheyeAmount = 1.5 * (
          growth * 0.65 + Math.sin(growth * Math.PI) * 0.5 + (anchorScale - 1) * 3
        );
        const fisheyeIn = smoothstep(entryProgress / 0.38);
        const fisheyeOut = 1 - smoothstep((entryProgress - 0.42) / 0.58);
        lensDistortionAmount = fisheyeIn * fisheyeOut * 0.85;
      } else {
        if (anchorSettledAt === 0) {
          anchorPhase = Math.PI / 2;
          anchorLastAt = now;
          anchorSettledAt = now;
        }
        const elapsed = now - anchorLastAt;
        anchorLastAt = now;
        anchorPhase += elapsed / anchorBreathPeriod * Math.PI * 2;
        shapeLiveBreath((Math.sin(anchorPhase) + 1) * 0.5);
        sphereSize = anchoredSphereSize(anchorPhase);
        // Run the lens opposite the size on a clean sine. Keeping it separate
        // from the asymmetric size swing removes the midpoint velocity kink.
        fisheyeAmount = 1.5 * (0.9 - Math.sin(anchorPhase) * 0.1);
        lensDistortionAmount = 0;
        twinkleTimeline = smoothstep((now - anchorSettledAt) / 1_800);
      }
      if (phase !== "leaving" && !liveCollapsing) sphereFrame = requestAnimationFrame(frame);
      else sphereFrame = undefined;
    };
    sphereFrame = requestAnimationFrame(frame);
  }

  function hasCompletedExperience() {
    try {
      return localStorage.getItem(storageKey) === "complete";
    } catch {
      return false;
    }
  }

  function persistCompletedExperience() {
    if (import.meta.env.DEV) return;
    try {
      localStorage.setItem(storageKey, "complete");
    } catch {
      // Storage can be unavailable in private or restricted browser contexts.
    }
  }

  function playActivationTone(level = 0.06) {
    if (!route) return;
    const context = route.audioContext;
    const now = context.currentTime;
    const filter = context.createBiquadFilter();
    const breathGain = context.createGain();
    const attackGain = context.createGain();
    liveLevel = level;

    filter.type = "lowpass";
    filter.frequency.setValueAtTime(210, now);
    filter.Q.setValueAtTime(0.14, now);
    breathGain.gain.setValueAtTime(0.0001, now);
    attackGain.gain.setValueAtTime(0.0001, now);
    const attackCurve = new Float32Array(128);
    for (let index = 0; index < attackCurve.length; index += 1) {
      const progress = index / (attackCurve.length - 1);
      // Equal-power rise: audible movement begins with the click, while the
      // slope settles softly as it reaches the sustained breathing level.
      attackCurve[index] = 0.0001 + Math.sin(progress * Math.PI * 0.5) * 0.9999;
    }
    attackGain.gain.setValueCurveAtTime(attackCurve, now, 2.4);

    filter.connect(breathGain).connect(attackGain).connect(route.input);
    const noise = context.createBufferSource();
    const noiseGain = context.createGain();
    const noiseFilter = context.createBiquadFilter();
    const noiseBuffer = context.createBuffer(1, context.sampleRate * 8, context.sampleRate);
    const noiseSamples = noiseBuffer.getChannelData(0);
    for (let index = 0; index < noiseSamples.length; index += 1) {
      noiseSamples[index] = Math.random() * 2 - 1;
    }
    noise.buffer = noiseBuffer;
    noise.loop = true;
    noiseFilter.type = "bandpass";
    noiseFilter.frequency.setValueAtTime(1_450, now);
    noiseFilter.Q.setValueAtTime(0.24, now);
    noiseGain.gain.setValueAtTime(0.012, now);
    noise.connect(noiseFilter).connect(noiseGain).connect(breathGain);
    noise.start(now);
    liveNoise = noise;
    liveVoices = [];
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
      voice.connect(voiceGain).connect(filter);
      voice.start(now);
      liveVoices.push(voice);
    }
    liveAttackGain = attackGain;
    liveBreathGain = breathGain;
    liveHashGain = noiseGain;
    liveBreathFilter = filter;
    shapeLiveBreath(0.08, 1, true);
  }

  function runEffects(effects: readonly OnboardingEffect[]) {
    for (const effect of effects) {
      if (effect.type === "PLAY_ACTIVATION_TONE") {
        void startActivationTone(effect.input);
      } else if (effect.type === "SCHEDULE_ENTRY_FINISH") {
        window.clearTimeout(entryTimer);
        entryTimer = window.setTimeout(() => {
          const transition = onboardingMachine.send({ type: "ENTRY_FINISHED" });
          runEffects(transition.effects);
        }, effect.delay);
      } else if (effect.type === "SCHEDULE_COMPLETION") {
        window.clearTimeout(completionTimer);
        completionTimer = window.setTimeout(
          completeExperience,
          effect.delay,
        );
      } else if (effect.type === "SCHEDULE_LEAVE_FINISH") {
        window.clearTimeout(leaveTimer);
        leaveTimer = window.setTimeout(() => {
          onboardingMachine.send({ type: "LEAVE_FINISHED" });
          stopLiveBreath();
          route?.dispose();
          route = undefined;
        }, effect.delay);
      } else if (effect.type === "PERSIST_COMPLETION") {
        persistCompletedExperience();
      }
    }
  }

  function beginActivation(input: OnboardingInput) {
    if (phase !== "prompting") return;
    const transition = onboardingMachine.send({
      type: "ACTIVATE",
      input,
      now: performance.now(),
    });
    runEffects(transition.effects);
    startSphereTimeline();
  }

  function unlockFromPointer(event: PointerEvent) {
    event.preventDefault();
    event.stopPropagation();
    if (phase === "exploring") {
      completeExperience();
      return;
    }
    const input = event.pointerType === "mouse" ? "mouse" : "touch";
    beginActivation(input);
  }

  async function startActivationTone(input: OnboardingInput) {
    if (activationPadStarted || activationPadStarting) return;
    activationPadStarting = true;
    try {
      const context = await soundManager?.resume();
      if (!context || !soundManager) return;
      soundManager.setEnabled(true);
      route ??= soundManager.register("sound-onboarding", 1);
      activationPadStarted = true;
      playActivationTone(input === "touch" ? 0.075 : 0.055);
    } finally {
      activationPadStarting = false;
    }
  }

  function unlockFromKeyboard(event: MouseEvent) {
    if (event.detail !== 0) return;
    if (phase === "exploring") {
      completeExperience();
      return;
    }
    beginActivation("keyboard");
  }

  function completeExperience() {
    stopSphereTimeline();
    const viewportWidth = window.visualViewport?.width ?? window.innerWidth;
    const viewportHeight = window.visualViewport?.height ?? window.innerHeight;
    exitDiameter = Math.hypot(viewportWidth, viewportHeight) + 4;
    const transition = onboardingMachine.send({ type: "BEGIN_LEAVE" });
    if (transition.snapshot.phase !== "leaving") return;
    const startedAt = performance.now();
    const startingSize = sphereSize;
    const startingFisheye = fisheyeAmount / 1.5;
    setHomepageSwap(0);
    let contentRevealStarted = false;
    const frame = (now: number) => {
      const elapsed = now - startedAt;
      const sphereProgress = Math.min(1, elapsed / exitDuration);
      const homepageProgress = Math.min(1, Math.max(
        0,
        elapsed - exitDuration - fullscreenHoldDuration,
      ) / homepageRevealDuration);
      const easedSphere = smoothstep(sphereProgress);
      sphereSize = startingSize + (exitDiameter - startingSize) * easedSphere;
      // Keep the spatial lens alive for the complete fullscreen hold. The
      // homepage replaces the whole field; there is no second lens tail.
      fisheyeAmount = 1.5 * startingFisheye;
      lensDistortionAmount = 0;
      whiteoutTimeline = 0;
      starFadeTimeline = 0;
      twinkleTimeline = 1;
      if (!contentRevealStarted && homepageProgress > 0) {
        contentRevealStarted = true;
        document.documentElement.dataset.rangeOnboarding = "revealing";
      }
      const easedHomepage = smoothstep(homepageProgress);
      setHomepageSwap(easedHomepage);
      const revealTail = 1 - easedHomepage;
      shapeLiveBreath(revealTail, revealTail);
      const totalDuration = exitDuration + fullscreenHoldDuration + homepageRevealDuration;
      if (elapsed < totalDuration) exitFrame = requestAnimationFrame(frame);
      else exitFrame = undefined;
    };
    exitFrame = requestAnimationFrame(frame);
    runEffects(transition.effects);
  }

  function collapseSettledSphere() {
    if (phase !== "exploring") return;
    stopSphereTimeline();
    liveCollapsing = true;
    const transition = onboardingMachine.send({ type: "RESET" });
    runEffects(transition.effects);
    const startingSize = sphereSize;
    const startingFisheye = fisheyeAmount;
    const startedAt = performance.now();
    const frame = (now: number) => {
      const progress = Math.min(1, (now - startedAt) / 1_600);
      const remaining = 1 - smoothstep(progress);
      sphereSize = 56 + (startingSize - 56) * remaining;
      fisheyeAmount = startingFisheye * remaining;
      lensDistortionAmount *= remaining;
      twinkleTimeline = remaining;
      shapeLiveBreath(remaining, 1);
      if (progress < 1) collapseFrame = requestAnimationFrame(frame);
      else {
        collapseFrame = undefined;
        liveCollapsing = false;
        whiteoutTimeline = 0;
        starFadeTimeline = 0;
        twinkleTimeline = 0;
        lensDistortionAmount = 0;
        shapeLiveBreath(0.08, 1, true);
      }
    };
    collapseFrame = requestAnimationFrame(frame);
  }

  onMount(() => {
    const unsubscribe = onboardingMachine.subscribe((snapshot) => {
      const previousPhase = machineSnapshot.phase;
      machineSnapshot = snapshot;
      document.documentElement.dataset.rangeOnboarding = snapshot.phase === "complete"
        ? document.documentElement.dataset.rangeOnboarding === "revealing"
          ? "ready"
          : previousPhase === "leaving" ? "revealing" : "ready"
        : "active";
    });
    const skipPreview = import.meta.env.DEV
      && new URLSearchParams(window.location.search).get("onboarding") === "skip";
    onboardingMachine.send({
      type: "RESTORE",
      completed: skipPreview || hasCompletedExperience(),
      force: import.meta.env.DEV && !skipPreview,
    });

    const rearm = async (event?: Event) => {
      if (onboardingMachine.getSnapshot().phase !== "complete") return;
      if (
        event?.target instanceof Element
        && event.target.closest(".transportButton")
      ) return;
      // A transport stop is an intentional mute. Do not let this document-level
      // gesture listener turn playback back on while the user clicks Stop/Start.
      if (!soundManager?.isEnabled()) return;
      const context = await soundManager?.resume();
      if (!context || !soundManager) return;
      soundManager.setEnabled(true);
      window.removeEventListener("pointerdown", rearm);
      window.removeEventListener("keydown", rearm);
    };
    window.addEventListener("pointerdown", rearm, { passive: true });
    window.addEventListener("keydown", rearm);
    return () => {
      unsubscribe();
      window.removeEventListener("pointerdown", rearm);
      window.removeEventListener("keydown", rearm);
      window.clearTimeout(completionTimer);
      window.clearTimeout(entryTimer);
      window.clearTimeout(leaveTimer);
      if (sphereFrame !== undefined) cancelAnimationFrame(sphereFrame);
      if (exitFrame !== undefined) cancelAnimationFrame(exitFrame);
      if (collapseFrame !== undefined) cancelAnimationFrame(collapseFrame);
      delete document.documentElement.dataset.rangeOnboarding;
      document.documentElement.style.removeProperty("--range-homepage-opacity");
      document.documentElement.style.removeProperty("--range-homepage-blur");
      document.documentElement.style.removeProperty("--range-homepage-scale");
      stopLiveBreath();
      route?.dispose();
    };
  });
</script>

{#if phase !== "booting" && phase !== "complete"}
  <div
    class="onboarding"
    class:leaving={phase === "leaving"}
    onpointerdown={collapseSettledSphere}
  >
    <button
      class="sphereControl"
      type="button"
      aria-label="Tap to discover Range and enable sound"
      disabled={phase === "entering" || phase === "leaving" || liveCollapsing}
      onpointerdown={unlockFromPointer}
      onclick={unlockFromKeyboard}
      style={`--sphere-size: ${sphereSize}px;`}
    >
      <span
        class="fieldBackdrop"
        aria-hidden="true"
        style={`--sky-opacity: ${1 - homepageSwapTimeline}; --sky-blur: ${homepageSwapTimeline * 18}px; --sky-scale: ${1 + homepageSwapTimeline * 0.025};`}
      >
        <OnboardingSphereShader
          concreteness={concreteness}
          timeOrigin={sphereEpoch}
          fisheyeAmount={fisheyeAmount}
          distortionAmount={lensDistortionAmount}
          glitterAmount={1 - smoothstep(starFadeTimeline)}
          twinkleAmount={twinkleTimeline}
          whiteoutAmount={smoothstep(whiteoutTimeline)}
        />
      </span>
    </button>
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
    background-color: oklch(1 0 0);
    touch-action: none;
    overscroll-behavior: none;
  }

  .onboarding.leaving {
    pointer-events: none;
  }

  .sphereControl {
    position: absolute;
    top: 50%;
    left: 50%;
    display: block;
    width: var(--sphere-size);
    height: var(--sphere-size);
    min-width: 56px;
    min-height: 56px;
    overflow: hidden;
    padding: 0;
    border: 0;
    border-radius: 50%;
    background: transparent;
    transform: translate(-50%, -50%);
    transform-origin: center;
    cursor: pointer;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
  }

  .sphereControl:disabled {
    cursor: default;
    opacity: 1;
  }

  .sphereControl:focus-visible {
    outline: 2px solid var(--range);
    outline-offset: 6px;
  }

  .fieldBackdrop {
    position: absolute;
    z-index: 0;
    inset: 0;
    overflow: hidden;
    border: 0;
    border-radius: 50%;
    background: transparent;
    opacity: var(--sky-opacity, 1);
    filter: blur(var(--sky-blur, 0px));
    transform: scale(var(--sky-scale, 1));
    transform-origin: center;
    will-change: opacity, filter, transform;
  }

  /* Keep the discovery object visible before WebGL has completed its first draw. */
  .onboarding:not(.leaving) .fieldBackdrop {
    background: radial-gradient(
      circle at 42% 38%,
      oklch(0.19 0.045 258),
      oklch(0.075 0.025 260) 68%,
      oklch(0.035 0.014 260)
    );
  }

  .onboarding :global(.fieldBackdrop[data-shader-rendered="true"]) {
    background: transparent;
    border-radius: 0;
    overflow: visible;
  }

  .onboarding :global(.sphereControl:has(.fieldBackdrop[data-shader-rendered="true"])) {
    border-radius: 0;
    overflow: visible;
  }

  @media (prefers-reduced-motion: reduce) {
    .onboarding,
    .sphereControl {
      transition-duration: 1ms;
    }
  }
</style>
