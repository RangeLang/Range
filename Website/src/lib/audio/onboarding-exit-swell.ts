export type OnboardingExitSwell = {
  readonly gain: GainNode;
  readonly voices: AudioScheduledSourceNode[];
};

function createExitNoise(context: AudioContext) {
  const buffer = context.createBuffer(
    1,
    Math.floor(context.sampleRate * 0.72),
    context.sampleRate,
  );
  const samples = buffer.getChannelData(0);
  for (let index = 0; index < samples.length; index += 1) {
    const progress = index / samples.length;
    samples[index] = (Math.random() * 2 - 1) * Math.pow(1 - progress, 1.8);
  }
  return buffer;
}

export function playOnboardingExitSwell(
  context: AudioContext,
  destination: AudioNode,
  durationMilliseconds = 400,
): OnboardingExitSwell {
  const now = context.currentTime;
  const duration = Math.max(0.2, durationMilliseconds / 1_000);
  const filter = context.createBiquadFilter();
  const swellGain = context.createGain();
  const noise = context.createBufferSource();
  const noiseGain = context.createGain();
  const attackEnd = Math.min(0.18, duration * 0.16);
  // Leave more of the envelope for the falloff so the sound releases instead
  // of dropping away immediately after its sustained body.
  const bodyEnd = duration * 0.64;

  filter.type = "lowpass";
  filter.frequency.setValueAtTime(155, now);
  filter.frequency.exponentialRampToValueAtTime(
    265,
    now + Math.min(0.32, duration * 0.22),
  );
  filter.frequency.exponentialRampToValueAtTime(175, now + duration);
  filter.Q.setValueAtTime(0.16, now);

  // A quicker, slightly louder body makes the swell readable without turning
  // it into a click. The release remains tied to the exit timeline.
  swellGain.gain.setValueAtTime(0.0001, now);
  // One continuous swell: no percussive attack, just a smooth rise into the
  // sustained sine body before the final release.
  swellGain.gain.exponentialRampToValueAtTime(0.24, now + attackEnd);
  swellGain.gain.setValueAtTime(0.24, now + bodyEnd);
  swellGain.gain.exponentialRampToValueAtTime(0.0001, now + duration);
  filter.connect(swellGain).connect(destination);
  noise.buffer = createExitNoise(context);
  noiseGain.gain.setValueAtTime(0.0001, now);
  noiseGain.gain.exponentialRampToValueAtTime(0.3, now + 0.018);
  noiseGain.gain.exponentialRampToValueAtTime(0.0001, now + duration * 0.9);
  noise.connect(noiseGain).connect(filter);

  const voices: AudioScheduledSourceNode[] = [];
  for (const [frequency, level, pan] of [
    [48, 0.16, 0],
    [96, 0.025, -0.2],
    [144, 0.003, 0.2],
  ] as const) {
    const voice = context.createOscillator();
    const voiceGain = context.createGain();
    const stereo = context.createStereoPanner();
    voice.type = "sine";
    voice.frequency.setValueAtTime(frequency, now);
    voiceGain.gain.setValueAtTime(level, now);
    stereo.pan.setValueAtTime(pan, now);
    voice.connect(voiceGain).connect(stereo).connect(filter);
    voice.start(now);
    voice.stop(now + duration + 0.2);
    voices.push(voice);
  }

  noise.start(now);
  noise.stop(now + duration + 0.2);
  voices.push(noise);

  // Let a pair of quiet upper partials surface around the swell peak. Keep
  // their frequencies and stereo positions fixed so the sustained sine body
  // stays clean instead of developing a mid-note phase wobble.
  const shimmerStart = 0.24;
  const shimmerEnd = 0.52;
  const shimmerSteps = 128;
  for (const [frequency, level, pan] of [
    [192, 0.018, -0.16],
    [240, 0.009, 0.16],
  ] as const) {
    const voice = context.createOscillator();
    const voiceGain = context.createGain();
    const stereo = context.createStereoPanner();
    const gainCurve = new Float32Array(shimmerSteps);
    const frequencyCurve = new Float32Array(shimmerSteps);
    const panCurve = new Float32Array(shimmerSteps);
    for (let index = 0; index < shimmerSteps; index += 1) {
      const progress = index / (shimmerSteps - 1);
      const windowProgress = Math.min(
        1,
        Math.max(0, (progress - shimmerStart) / (shimmerEnd - shimmerStart)),
      );
      const shimmerWindow = Math.sin(windowProgress * Math.PI);
      gainCurve[index] = 0.0001 + level * shimmerWindow;
      frequencyCurve[index] = frequency;
      panCurve[index] = pan;
    }
    voice.type = "sine";
    voice.frequency.setValueAtTime(frequencyCurve[0], now);
    voice.frequency.setValueCurveAtTime(frequencyCurve, now, duration);
    voiceGain.gain.setValueAtTime(gainCurve[0], now);
    voiceGain.gain.setValueCurveAtTime(gainCurve, now, duration);
    stereo.pan.setValueAtTime(panCurve[0], now);
    stereo.pan.setValueCurveAtTime(panCurve, now, duration);
    voice.connect(voiceGain).connect(stereo).connect(filter);
    voice.start(now);
    voice.stop(now + duration + 0.2);
    voices.push(voice);
  }

  return { gain: swellGain, voices };
}
