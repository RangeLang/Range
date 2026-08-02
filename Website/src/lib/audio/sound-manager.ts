export const RANGE_SOUND_MANAGER_CONTEXT = Symbol("range-sound-manager");
export const RANGE_RHYTHM_SUBDIVISION_MS = 150;

export type RangeSoundRoute = {
  readonly name: string;
  readonly audioContext: AudioContext;
  readonly input: GainNode;
  dispose: () => void;
};

export type RangeRhythmBeat = {
  readonly step: number;
  readonly tick: number;
  readonly audioTime?: number;
};

export type RangeSoundManager = {
  resume: () => Promise<AudioContext | undefined>;
  register: (name: string, level?: number) => RangeSoundRoute | undefined;
  isEnabled: () => boolean;
  setEnabled: (enabled: boolean) => void;
  subscribe: (listener: (enabled: boolean) => void) => () => void;
  publishRhythmBeat: (beat: RangeRhythmBeat) => void;
  subscribeRhythmBeat: (listener: (beat: RangeRhythmBeat) => void) => () => void;
  setLayerPresence: (name: string, presence: number) => void;
  subscribeLayerPresence: (
    name: string,
    listener: (presence: number) => void,
  ) => () => void;
  dispose: () => void;
};

declare global {
  interface Window {
    __rangeSoundManager?: RangeSoundManager;
  }
}

type AudioContextConstructor = new () => AudioContext;

function audioContextConstructor(): AudioContextConstructor | undefined {
  if (typeof window === "undefined") return undefined;
  return (
    window.AudioContext
    ?? (window as Window & { webkitAudioContext?: AudioContextConstructor })
      .webkitAudioContext
  ) as AudioContextConstructor | undefined;
}

export function createRangeSoundManager(): RangeSoundManager {
  let audioContext: AudioContext | undefined;
  let masterInput: GainNode | undefined;
  let masterDry: GainNode | undefined;
  let environmentFilter: BiquadFilterNode | undefined;
  let environmentCompressor: DynamicsCompressorNode | undefined;
  let environmentWet: GainNode | undefined;
  let environmentNoiseSource: AudioBufferSourceNode | undefined;
  let environmentNoiseFilter: BiquadFilterNode | undefined;
  let environmentNoiseGain: GainNode | undefined;
  let masterLimiter: DynamicsCompressorNode | undefined;
  let masterOutput: GainNode | undefined;
  let enabled = false;
  const routes = new Set<RangeSoundRoute>();
  const enabledListeners = new Set<(enabled: boolean) => void>();
  const rhythmBeatListeners = new Set<(beat: RangeRhythmBeat) => void>();
  const layerPresence = new Map<string, number>();
  const layerPresenceListeners = new Map<
    string,
    Set<(presence: number) => void>
  >();

  function createBrownNoise(context: AudioContext) {
    const duration = 6;
    const buffer = context.createBuffer(
      2,
      Math.floor(context.sampleRate * duration),
      context.sampleRate,
    );
    for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
      const samples = buffer.getChannelData(channel);
      let randomState = 0x42524f57 + channel * 0x13579;
      let brown = 0;
      for (let index = 0; index < samples.length; index += 1) {
        randomState = (randomState * 1664525 + 1013904223) >>> 0;
        const white = (randomState / 4294967296) * 2 - 1;
        brown = (brown + white * 0.018) / 1.018;
        samples[index] = Math.max(-1, Math.min(1, brown * 3.4));
      }
    }
    return buffer;
  }

  function applyEnvironmentSpace(presence: number, immediate = false) {
    if (!audioContext) return;
    const bounded = Math.max(0, Math.min(1, presence));
    const amount = bounded * bounded * (3 - 2 * bounded);
    const now = audioContext.currentTime;
    const timeConstant = immediate ? 0.001 : 1.35;
    const setSmooth = (parameter: AudioParam, value: number) => {
      parameter.cancelScheduledValues(now);
      if (immediate) parameter.setValueAtTime(value, now);
      else parameter.setTargetAtTime(value, now, timeConstant);
    };

    // Environment represents distance: the foreground recedes almost entirely
    // while a quiet, dark copy remains suspended behind the noise floor.
    setSmooth(masterDry!.gain, 1 - amount * 0.92);
    setSmooth(environmentWet!.gain, amount * 0.16);
    setSmooth(
      environmentFilter!.frequency,
      18_000 * Math.pow(280 / 18_000, amount),
    );
    setSmooth(environmentNoiseGain!.gain, amount * 0.007);
    setSmooth(environmentNoiseFilter!.frequency, 190 + amount * 130);
  }

  function createGraph() {
    if (audioContext && masterInput) return audioContext;
    const Constructor = audioContextConstructor();
    if (!Constructor) return undefined;

    audioContext = new Constructor();
    masterInput = audioContext.createGain();
    masterDry = audioContext.createGain();
    environmentFilter = audioContext.createBiquadFilter();
    environmentCompressor = audioContext.createDynamicsCompressor();
    environmentWet = audioContext.createGain();
    environmentNoiseSource = audioContext.createBufferSource();
    environmentNoiseFilter = audioContext.createBiquadFilter();
    environmentNoiseGain = audioContext.createGain();
    masterLimiter = audioContext.createDynamicsCompressor();
    masterOutput = audioContext.createGain();
    masterInput.gain.value = 1;
    masterDry.gain.value = 1;
    environmentFilter.type = "lowpass";
    environmentFilter.frequency.value = 18_000;
    environmentFilter.Q.value = 0.36;
    environmentCompressor.threshold.value = -30;
    environmentCompressor.knee.value = 18;
    environmentCompressor.ratio.value = 7;
    environmentCompressor.attack.value = 0.08;
    environmentCompressor.release.value = 0.72;
    environmentWet.gain.value = 0.0001;
    environmentNoiseSource.buffer = createBrownNoise(audioContext);
    environmentNoiseSource.loop = true;
    environmentNoiseFilter.type = "lowpass";
    environmentNoiseFilter.frequency.value = 260;
    environmentNoiseFilter.Q.value = 0.28;
    environmentNoiseGain.gain.value = 0.0001;
    masterLimiter.threshold.value = -6;
    masterLimiter.knee.value = 8;
    masterLimiter.ratio.value = 4;
    masterLimiter.attack.value = 0.003;
    masterLimiter.release.value = 0.16;
    masterOutput.gain.value = enabled ? 1 : 0;
    masterInput.connect(masterDry).connect(masterLimiter);
    masterInput
      .connect(environmentFilter)
      .connect(environmentCompressor)
      .connect(environmentWet)
      .connect(masterLimiter);
    environmentNoiseSource
      .connect(environmentNoiseFilter)
      .connect(environmentNoiseGain)
      .connect(masterLimiter);
    masterLimiter.connect(masterOutput).connect(
      audioContext.destination,
    );
    environmentNoiseSource.start();
    applyEnvironmentSpace(layerPresence.get("environment") ?? 0, true);
    return audioContext;
  }

  async function resume() {
    const context = createGraph();
    if (!context) return undefined;
    if (context.state === "suspended") await context.resume();
    // WebKit may briefly report `interrupted` after a successful user-gesture
    // resume. The context is still valid and becomes running as the page gains
    // audio focus, so only reject a context that has actually been closed.
    return context.state === "closed" ? undefined : context;
  }

  function register(name: string, level = 1) {
    const context = createGraph();
    if (!context || !masterInput) return undefined;

    const input = context.createGain();
    input.gain.value = level;
    input.connect(masterInput);

    let route: RangeSoundRoute;
    route = {
      name,
      audioContext: context,
      input,
      dispose() {
        if (!routes.has(route)) return;
        routes.delete(route);
        input.disconnect();
      },
    };
    routes.add(route);
    return route;
  }

  function isEnabled() {
    return enabled;
  }

  function setEnabled(nextEnabled: boolean) {
    if (enabled === nextEnabled) return;
    enabled = nextEnabled;
    if (audioContext && masterOutput) {
      const now = audioContext.currentTime;
      masterOutput.gain.cancelScheduledValues(now);
      masterOutput.gain.setTargetAtTime(enabled ? 1 : 0, now, enabled ? 0.18 : 0.8);
    }
    for (const listener of enabledListeners) listener(enabled);
  }

  function subscribe(listener: (enabled: boolean) => void) {
    enabledListeners.add(listener);
    listener(enabled);
    return () => enabledListeners.delete(listener);
  }

  function publishRhythmBeat(beat: RangeRhythmBeat) {
    for (const listener of rhythmBeatListeners) listener(beat);
  }

  function subscribeRhythmBeat(listener: (beat: RangeRhythmBeat) => void) {
    rhythmBeatListeners.add(listener);
    return () => rhythmBeatListeners.delete(listener);
  }

  function setLayerPresence(name: string, presence: number) {
    const boundedPresence = Math.max(0, Math.min(1, presence));
    if (layerPresence.get(name) === boundedPresence) return;
    layerPresence.set(name, boundedPresence);
    if (name === "environment") applyEnvironmentSpace(boundedPresence);
    for (const listener of layerPresenceListeners.get(name) ?? []) {
      listener(boundedPresence);
    }
  }

  function subscribeLayerPresence(
    name: string,
    listener: (presence: number) => void,
  ) {
    let listeners = layerPresenceListeners.get(name);
    if (!listeners) {
      listeners = new Set();
      layerPresenceListeners.set(name, listeners);
    }
    listeners.add(listener);
    listener(layerPresence.get(name) ?? 0);
    return () => {
      listeners?.delete(listener);
      if (listeners?.size === 0) layerPresenceListeners.delete(name);
    };
  }

  function dispose() {
    setEnabled(false);
    enabledListeners.clear();
    rhythmBeatListeners.clear();
    layerPresence.clear();
    layerPresenceListeners.clear();
    for (const route of [...routes]) route.dispose();
    try {
      environmentNoiseSource?.stop();
    } catch {
      // The source may already have stopped with its context.
    }
    masterInput?.disconnect();
    masterDry?.disconnect();
    environmentFilter?.disconnect();
    environmentCompressor?.disconnect();
    environmentWet?.disconnect();
    environmentNoiseSource?.disconnect();
    environmentNoiseFilter?.disconnect();
    environmentNoiseGain?.disconnect();
    masterLimiter?.disconnect();
    masterOutput?.disconnect();
    const context = audioContext;
    audioContext = undefined;
    masterInput = undefined;
    masterDry = undefined;
    environmentFilter = undefined;
    environmentCompressor = undefined;
    environmentWet = undefined;
    environmentNoiseSource = undefined;
    environmentNoiseFilter = undefined;
    environmentNoiseGain = undefined;
    masterLimiter = undefined;
    masterOutput = undefined;
    if (context) void context.close();
  }

  return {
    resume,
    register,
    isEnabled,
    setEnabled,
    subscribe,
    publishRhythmBeat,
    subscribeRhythmBeat,
    setLayerPresence,
    subscribeLayerPresence,
    dispose,
  };
}
