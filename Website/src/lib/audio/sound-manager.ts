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
  let masterLimiter: DynamicsCompressorNode | undefined;
  let masterOutput: GainNode | undefined;
  let enabled = false;
  const routes = new Set<RangeSoundRoute>();
  const enabledListeners = new Set<(enabled: boolean) => void>();
  const rhythmBeatListeners = new Set<(beat: RangeRhythmBeat) => void>();

  function createGraph() {
    if (audioContext && masterInput) return audioContext;
    const Constructor = audioContextConstructor();
    if (!Constructor) return undefined;

    audioContext = new Constructor();
    masterInput = audioContext.createGain();
    masterLimiter = audioContext.createDynamicsCompressor();
    masterOutput = audioContext.createGain();
    masterInput.gain.value = 1;
    masterLimiter.threshold.value = -6;
    masterLimiter.knee.value = 8;
    masterLimiter.ratio.value = 4;
    masterLimiter.attack.value = 0.003;
    masterLimiter.release.value = 0.16;
    masterOutput.gain.value = 1;
    masterInput.connect(masterLimiter).connect(masterOutput).connect(
      audioContext.destination,
    );
    return audioContext;
  }

  async function resume() {
    const context = createGraph();
    if (!context) return undefined;
    if (context.state === "suspended") await context.resume();
    return context.state === "running" ? context : undefined;
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

  function dispose() {
    setEnabled(false);
    enabledListeners.clear();
    rhythmBeatListeners.clear();
    for (const route of [...routes]) route.dispose();
    masterInput?.disconnect();
    masterLimiter?.disconnect();
    masterOutput?.disconnect();
    const context = audioContext;
    audioContext = undefined;
    masterInput = undefined;
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
    dispose,
  };
}
