export type DeepAcidWowParameters = {
  cutoff: number;
  gain: number;
  resonance: number;
  sawLevel: number;
};

export const deepAcidWowEnvelope = Object.freeze({
  attackTimeConstant: 0.035,
  axisTimeConstant: 0.055,
  releaseDuration: 1.2,
});

type DeepAcidWow = {
  shape: (
    displacement: number,
    speed: number,
    vertical: number,
  ) => void;
  sustain: (strength?: number) => void;
  volume: (level?: number, duration?: number) => void;
  idleFade: (level?: number, duration?: number) => void;
  release: (duration?: number) => void;
  silence: () => void;
  dispose: () => void;
};

const clampUnit = (value: number) => Math.min(1, Math.max(0, value));

export function deepAcidWowAxisStrength(vertical: number): number {
  const axisDistance = Math.abs(clampUnit(vertical) - 0.5) * 2;
  const falloffStart = 0.08;
  const normalizedFalloff = clampUnit(
    (axisDistance - falloffStart) / (1 - falloffStart),
  );
  const smoothFalloff =
    normalizedFalloff * normalizedFalloff * (3 - 2 * normalizedFalloff);
  return 1 - smoothFalloff * 0.78;
}

export function deepAcidWowParameters(
  displacement: number,
  speed: number,
  vertical: number,
): DeepAcidWowParameters {
  const pull = clampUnit(displacement);
  const motion = clampUnit(speed);
  const height = clampUnit(vertical);
  const energy = clampUnit(pull * 0.78 + motion * 0.5);
  const roundedSweep = Math.pow(energy, 0.72);

  return {
    cutoff: 105 + roundedSweep * 360 + height * 35,
    gain: 0.018 + energy * 0.032,
    resonance: 2.15 + energy * 0.85,
    sawLevel: 0.1 + motion * 0.05,
  };
}

export function createDeepAcidWow(
  audio: AudioContext,
  destination: AudioNode,
  { transposeSemitones = 0 }: { transposeSemitones?: number } = {},
): DeepAcidWow {
  const pitchRatio = 2 ** (transposeSemitones / 12);
  const fundamental = audio.createOscillator();
  fundamental.type = "triangle";
  fundamental.frequency.value = 55 * pitchRatio;

  const sub = audio.createOscillator();
  sub.type = "sine";
  sub.frequency.value = 27.5 * pitchRatio;

  const acidEdge = audio.createOscillator();
  acidEdge.type = "sawtooth";
  acidEdge.frequency.value = 55 * pitchRatio;

  const fundamentalGain = audio.createGain();
  fundamentalGain.gain.value = 0.62;
  const subGain = audio.createGain();
  subGain.gain.value = 0.18;
  const acidEdgeGain = audio.createGain();
  acidEdgeGain.gain.value = 0.1;

  const filter = audio.createBiquadFilter();
  filter.type = "lowpass";
  filter.frequency.value = 105;
  filter.Q.value = 2.15;

  const highpass = audio.createBiquadFilter();
  highpass.type = "highpass";
  highpass.frequency.value = 24;
  highpass.Q.value = 0.7;

  const saturation = audio.createWaveShaper();
  const curve = new Float32Array(1024);
  for (let index = 0; index < curve.length; index += 1) {
    const input = (index / (curve.length - 1)) * 2 - 1;
    curve[index] = Math.tanh(input * 1.75) / Math.tanh(1.75);
  }
  saturation.curve = curve;
  saturation.oversample = "2x";

  const output = audio.createGain();
  output.gain.value = 0.018;
  const volumeGain = audio.createGain();
  volumeGain.gain.value = 0.0001;
  const idleGain = audio.createGain();
  idleGain.gain.value = 1;
  const envelopeGain = audio.createGain();
  envelopeGain.gain.value = 0.0001;

  fundamental.connect(fundamentalGain).connect(filter);
  sub.connect(subGain).connect(filter);
  acidEdge.connect(acidEdgeGain).connect(filter);
  filter.connect(highpass).connect(saturation).connect(output);
  output.connect(volumeGain).connect(idleGain).connect(envelopeGain).connect(destination);

  fundamental.start();
  sub.start();
  acidEdge.start();

  let envelopeTarget = 0;
  let releasing = false;
  const sustainEnvelope = (strength: number) => {
    const target = clampUnit(strength);
    if (!releasing && Math.abs(envelopeTarget - target) < 0.001) return;
    envelopeTarget = target;
    releasing = false;
    const time = audio.currentTime;
    envelopeGain.gain.cancelAndHoldAtTime(time);
    envelopeGain.gain.setTargetAtTime(
      target,
      time,
      target > envelopeGain.gain.value
        ? deepAcidWowEnvelope.attackTimeConstant
        : deepAcidWowEnvelope.axisTimeConstant,
    );
  };

  const trailOff = (duration: number) => {
    if (releasing) return;
    releasing = true;
    envelopeTarget = 0;
    const time = audio.currentTime;
    envelopeGain.gain.cancelAndHoldAtTime(time);
    envelopeGain.gain.linearRampToValueAtTime(0.0001, time + duration);
  };

  const setVolume = (level: number, duration: number) => {
    const target = 0.0001 + clampUnit(level) * 0.9999;
    const time = audio.currentTime;
    volumeGain.gain.cancelAndHoldAtTime(time);
    volumeGain.gain.setTargetAtTime(target, time, duration);
  };

  return {
    shape(displacement, speed, vertical) {
      const time = audio.currentTime;
      const parameters = deepAcidWowParameters(
        displacement,
        speed,
        vertical,
      );
      filter.frequency.cancelScheduledValues(time);
      filter.frequency.setTargetAtTime(parameters.cutoff, time, 0.055);
      filter.Q.cancelScheduledValues(time);
      filter.Q.setTargetAtTime(parameters.resonance, time, 0.075);
      acidEdgeGain.gain.cancelScheduledValues(time);
      acidEdgeGain.gain.setTargetAtTime(parameters.sawLevel, time, 0.06);
      output.gain.cancelAndHoldAtTime(time);
      output.gain.setTargetAtTime(parameters.gain, time, 0.065);
    },
    sustain(strength = 1) {
      sustainEnvelope(strength);
    },
    volume(level = 1, duration = 0.18) {
      setVolume(level, duration);
    },
    idleFade(level = 1, duration = 0.18) {
      const target = 0.0001 + clampUnit(level) * 0.9999;
      const time = audio.currentTime;
      idleGain.gain.cancelAndHoldAtTime(time);
      idleGain.gain.setTargetAtTime(target, time, duration);
    },
    release(duration = deepAcidWowEnvelope.releaseDuration) {
      trailOff(duration);
    },
    silence() {
      const time = audio.currentTime;
      trailOff(deepAcidWowEnvelope.releaseDuration);
      filter.frequency.cancelScheduledValues(time);
      filter.frequency.setTargetAtTime(105, time, 0.16);
    },
    dispose() {
      fundamental.stop();
      sub.stop();
      acidEdge.stop();
      fundamental.disconnect();
      sub.disconnect();
      acidEdge.disconnect();
      fundamentalGain.disconnect();
      subGain.disconnect();
      acidEdgeGain.disconnect();
      filter.disconnect();
      highpass.disconnect();
      saturation.disconnect();
      output.disconnect();
      volumeGain.disconnect();
      idleGain.disconnect();
      envelopeGain.disconnect();
    },
  };
}
