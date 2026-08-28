import type { RangeSoundRoute } from "$lib/audio/sound-manager";

export type ErrorPageSynth = {
  activate: () => void;
  deactivate: () => void;
  dam: () => void;
  twinkle: () => void;
  dispose: () => void;
};

function buildSpaceImpulse(
  audio: AudioContext,
  seconds: number,
  decayPower: number,
) {
  const length = Math.round(audio.sampleRate * seconds);
  const impulse = audio.createBuffer(2, length, audio.sampleRate);
  for (let channel = 0; channel < impulse.numberOfChannels; channel += 1) {
    const samples = impulse.getChannelData(channel);
    let randomState = 0x46415200 + channel * 0x13579;
    for (let index = 0; index < samples.length; index += 1) {
      randomState = (randomState * 1664525 + 1013904223) >>> 0;
      const noise = randomState / 4294967296 * 2 - 1;
      samples[index] = noise * Math.pow(1 - index / samples.length, decayPower);
    }
  }
  return impulse;
}

/**
 * A sparse two-voice synthesizer for the error page.
 *
 *   dam trigger -----------------------------------------------> VCA
 *   twinkle trigger -> space send -> compressor --------------> VCA
 *
 * The page owns timing. This module owns the instrument and its envelopes.
 */
export function createErrorPageSynth(route: RangeSoundRoute): ErrorPageSynth {
  const audio = route.audioContext;
  const now = audio.currentTime;

  // Master amplifier and pad dynamics.
  const amplifier = audio.createGain();
  const compressor = audio.createDynamicsCompressor();
  amplifier.gain.setValueAtTime(0.0001, now);
  compressor.threshold.setValueAtTime(-44, now);
  compressor.knee.setValueAtTime(24, now);
  compressor.ratio.setValueAtTime(2.4, now);
  compressor.attack.setValueAtTime(0.18, now);
  compressor.release.setValueAtTime(0.95, now);
  compressor.connect(amplifier).connect(route.input);

  // Shared distant space.
  const space = audio.createConvolver();
  const spaceReturn = audio.createGain();
  space.buffer = buildSpaceImpulse(audio, 1.6, 6.2);
  spaceReturn.gain.setValueAtTime(0.075, now);
  space.connect(spaceReturn).connect(compressor);

  let disposed = false;

  return {
    activate() {
      if (disposed) return;
      const at = audio.currentTime;
      amplifier.gain.cancelAndHoldAtTime(at);
      amplifier.gain.setTargetAtTime(0.55, at, 3.2);
    },
    deactivate() {
      if (disposed) return;
      const at = audio.currentTime;
      amplifier.gain.cancelAndHoldAtTime(at);
      amplifier.gain.setTargetAtTime(0.0001, at, 0.8);
    },
    dam() {
      if (disposed) return;
      const at = audio.currentTime + 0.02;
      const voice = audio.createOscillator();
      const filter = audio.createBiquadFilter();
      const envelope = audio.createGain();
      voice.type = "sine";
      voice.frequency.setValueAtTime(112, at);
      voice.frequency.exponentialRampToValueAtTime(74, at + 0.48);
      filter.type = "lowpass";
      filter.frequency.setValueAtTime(280, at);
      filter.Q.setValueAtTime(0.42, at);
      envelope.gain.setValueAtTime(0.0001, at);
      envelope.gain.exponentialRampToValueAtTime(0.065, at + 0.028);
      envelope.gain.exponentialRampToValueAtTime(0.0001, at + 2.1);
      voice.connect(filter).connect(envelope).connect(amplifier);
      voice.start(at);
      voice.stop(at + 2.2);
    },
    twinkle() {
      if (disposed) return;
      const at = audio.currentTime + 0.02;
      const notes = [659.25, 783.99, 987.77, 1174.66];
      const voice = audio.createOscillator();
      const filter = audio.createBiquadFilter();
      const envelope = audio.createGain();
      const panner = audio.createStereoPanner();
      voice.type = "sine";
      voice.frequency.setValueAtTime(
        notes[Math.floor(Math.random() * notes.length)] ?? notes[0],
        at,
      );
      filter.type = "highpass";
      filter.frequency.setValueAtTime(520, at);
      envelope.gain.setValueAtTime(0.0001, at);
      envelope.gain.exponentialRampToValueAtTime(0.018, at + 0.06);
      envelope.gain.exponentialRampToValueAtTime(0.0001, at + 2.8);
      panner.pan.setValueAtTime(Math.random() * 1.4 - 0.7, at);
      voice.connect(filter).connect(envelope).connect(panner).connect(space);
      voice.start(at);
      voice.stop(at + 3);
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      space.disconnect();
      spaceReturn.disconnect();
      compressor.disconnect();
      amplifier.disconnect();
    },
  };
}
