import type { RangeSoundRoute } from "$lib/audio/sound-manager";

/** Exponentially decaying noise: a long, plain hall for the metal to sit in. */
function buildHall(audio: AudioContext, seconds: number, decay: number) {
  const length = Math.floor(audio.sampleRate * seconds);
  const impulse = audio.createBuffer(2, length, audio.sampleRate);
  for (let channel = 0; channel < impulse.numberOfChannels; channel += 1) {
    const data = impulse.getChannelData(channel);
    let randomState = 0x1f123bb5 + channel * 0x9e3779b9;
    for (let index = 0; index < length; index += 1) {
      randomState = (randomState * 1664525 + 1013904223) >>> 0;
      const white = (randomState / 4294967296) * 2 - 1;
      data[index] = white * (1 - index / length) ** decay;
    }
  }
  return impulse;
}

export type DesignKnotVoices = {
  /** A struck bell. */
  gong: (at: number) => void;
  /** Two short metal grains, or one for the half. */
  chaka: (at: number, level: number, half: boolean) => void;
  /** A bright hand cymbal, shorter for the half. */
  tsam: (at: number, level: number, half: boolean) => void;
  /** A pitched drum hit. */
  dam: (at: number, level: number, light: boolean) => void;
};

/**
 * The percussion the design knots page is scored for. One hall, shared, so
 * every voice sits in the same room however it is triggered.
 */
export function createDesignKnotVoices(
  route: RangeSoundRoute,
): DesignKnotVoices {
  const audio = route.audioContext;
  const hall = audio.createConvolver();
  const wet = audio.createGain();
  const dry = audio.createGain();
  hall.buffer = buildHall(audio, 6.5, 2.6);
  wet.gain.value = 0.62;
  dry.gain.value = 0.72;
  hall.connect(wet).connect(route.input);
  dry.connect(route.input);

  /** One short metal grain. Two of them make a chaka; one is half of it. */
  const grain = (at: number, level: number, centre: number, length: number) => {
    const now = Math.max(audio.currentTime, at);
    const size = Math.floor(audio.sampleRate * length);
    const buffer = audio.createBuffer(1, size, audio.sampleRate);
    const samples = buffer.getChannelData(0);
    let randomState = 0x9e3779b9 + Math.floor(now * 1_000);
    for (let index = 0; index < size; index += 1) {
      randomState = (randomState * 1664525 + 1013904223) >>> 0;
      samples[index] = (randomState / 4294967296) * 2 - 1;
    }
    const noise = audio.createBufferSource();
    const filter = audio.createBiquadFilter();
    const gain = audio.createGain();
    noise.buffer = buffer;
    filter.type = "bandpass";
    filter.frequency.setValueAtTime(centre, now);
    filter.Q.setValueAtTime(1.1, now);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.linearRampToValueAtTime(level, now + 0.006);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + length);
    noise.connect(filter).connect(gain).connect(dry);
    gain.connect(hall);
    noise.start(now);
    noise.stop(now + length + 0.05);
  };

  /*
   * A deep bell rather than a tube: a hum partial an octave under the prime,
   * the tierce/quint/nominal above it, then inharmonic upper metal. Several
   * partials are doubled a fraction of a hertz apart so the tail beats instead
   * of sitting still, and a short low thump carries the weight of the strike.
   */
  const gong = (at: number) => {
    const now = Math.max(audio.currentTime, at);

    const body = audio.createGain();
    body.gain.setValueAtTime(0.0001, now);
    body.gain.exponentialRampToValueAtTime(0.72, now + 0.02);
    body.gain.exponentialRampToValueAtTime(0.34, now + 1);
    body.gain.exponentialRampToValueAtTime(0.0001, now + 7);
    body.connect(dry);
    body.connect(hall);

    const metal = audio.createBiquadFilter();
    metal.type = "lowpass";
    metal.frequency.setValueAtTime(4_200, now);
    metal.frequency.exponentialRampToValueAtTime(420, now + 4.6);
    metal.Q.setValueAtTime(0.5, now);
    metal.connect(body);

    const prime = 55;
    // ratio, level, decay, beat detune in hertz
    const partials: [number, number, number, number][] = [
      [0.5, 1, 7.5, 0.21],
      [1, 0.92, 6.8, 0.33],
      [1.19, 0.55, 5.8, 0.47],
      [1.5, 0.4, 5, 0.6],
      [2, 0.5, 4.6, 0.72],
      [2.55, 0.26, 3.6, 0],
      [3.01, 0.19, 2.8, 0],
      [4.18, 0.13, 2, 0],
      [5.43, 0.08, 1.5, 0],
    ];
    for (const [index, [ratio, level, decay, detune]] of partials.entries()) {
      const frequency = prime * ratio;
      const voices = detune > 0 ? [-detune / 2, detune / 2] : [0];
      for (const offset of voices) {
        const oscillator = audio.createOscillator();
        const gain = audio.createGain();
        oscillator.type = "sine";
        oscillator.frequency.setValueAtTime((frequency + offset) * 1.006, now);
        oscillator.frequency.exponentialRampToValueAtTime(
          frequency + offset,
          now + 2.2,
        );
        gain.gain.setValueAtTime(0.0001, now);
        gain.gain.linearRampToValueAtTime(
          (level / voices.length) * 0.24,
          now + 0.014 + index * 0.006,
        );
        gain.gain.exponentialRampToValueAtTime(0.0001, now + decay);
        oscillator.connect(gain).connect(metal);
        oscillator.start(now);
        oscillator.stop(now + decay + 0.1);
      }
    }

    const thump = audio.createOscillator();
    const thumpGain = audio.createGain();
    thump.type = "sine";
    thump.frequency.setValueAtTime(96, now);
    thump.frequency.exponentialRampToValueAtTime(41, now + 0.16);
    thumpGain.gain.setValueAtTime(0.0001, now);
    thumpGain.gain.linearRampToValueAtTime(0.5, now + 0.008);
    thumpGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.7);
    thump.connect(thumpGain).connect(body);
    thump.start(now);
    thump.stop(now + 0.8);

    grain(now, 0.3, 3_200, 0.32);
  };

  const chaka = (at: number, level: number, half: boolean) => {
    grain(at, level, 4_100, 0.11);
    if (!half) grain(at + 0.085, level * 0.78, 5_600, 0.09);
  };

  const tsam = (at: number, level: number, half: boolean) => {
    const now = Math.max(audio.currentTime, at);
    grain(now, level, 7_200, half ? 0.19 : 0.42);
    const ring = half ? 0.26 : 0.52;
    for (const [index, frequency] of (half ? [1_182] : [1_182, 1_787]).entries()) {
      const oscillator = audio.createOscillator();
      const gain = audio.createGain();
      oscillator.type = "sine";
      oscillator.frequency.setValueAtTime(frequency, now);
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.linearRampToValueAtTime(
        level * (index === 0 ? 0.3 : 0.18),
        now + 0.01,
      );
      gain.gain.exponentialRampToValueAtTime(0.0001, now + ring);
      oscillator.connect(gain).connect(dry);
      gain.connect(hall);
      oscillator.start(now);
      oscillator.stop(now + ring + 0.08);
    }
  };

  const dam = (at: number, level: number, light: boolean) => {
    const now = Math.max(audio.currentTime, at);
    const from = light ? 152 : 112;
    const to = light ? 94 : 61;
    const decay = light ? 0.18 : 0.34;
    const oscillator = audio.createOscillator();
    const gain = audio.createGain();
    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(from, now);
    oscillator.frequency.exponentialRampToValueAtTime(to, now + decay * 0.55);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.linearRampToValueAtTime(level, now + 0.007);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + decay);
    oscillator.connect(gain).connect(dry);
    gain.connect(hall);
    oscillator.start(now);
    oscillator.stop(now + decay + 0.05);
    grain(now, level * 0.3, 2_200, 0.05);
  };

  return { gong, chaka, tsam, dam };
}

/** The site's rhythm grid, in seconds: two subdivisions to a beat. */
export const KNOT_BEAT_SECONDS = 0.3;
