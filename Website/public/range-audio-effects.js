function makeNoiseBuffer(audio, duration, sampleAtTime) {
  const frameCount = Math.ceil(audio.sampleRate * duration);
  const buffer = audio.createBuffer(1, frameCount, audio.sampleRate);
  const channel = buffer.getChannelData(0);
  let noise = 0;
  for (let index = 0; index < channel.length; index += 1) {
    const whiteNoise = Math.random() * 2 - 1;
    noise = noise * 0.58 + whiteNoise * 0.42;
    channel[index] = sampleAtTime(index / audio.sampleRate, noise);
  }
  return buffer;
}

export function createHashingSound(audio) {
  const filter = audio.createBiquadFilter();
  filter.type = "bandpass";
  filter.frequency.value = 1_900;
  filter.Q.value = 0.42;
  const gain = audio.createGain();
  gain.gain.value = 0.0001;
  const output = audio.createGain();
  output.gain.value = 1;
  filter.connect(gain);
  gain.connect(output);
  output.connect(audio.destination);

  const buffer = makeNoiseBuffer(audio, 1.5, (_time, noise) => noise);
  const channel = buffer.getChannelData(0);
  const seamLength = Math.min(512, Math.floor(channel.length / 8));
  for (let index = 0; index < seamLength; index += 1) {
    const blend = index / seamLength;
    const tailIndex = channel.length - seamLength + index;
    channel[tailIndex] = channel[tailIndex] * (1 - blend)
      + channel[index] * blend;
  }

  const source = audio.createBufferSource();
  source.buffer = buffer;
  source.loop = true;
  source.connect(filter);
  source.start();

  return {
    shape(pointerSpeed, position, direction) {
      const time = audio.currentTime;
      const speed = Math.min(1, Math.max(0, pointerSpeed / 0.72));
      const level = 0.018 + speed * 0.052;
      const frequency = 1_450 + position * 1_050 + speed * 420 + direction * 55;
      filter.frequency.cancelScheduledValues(time);
      filter.frequency.setTargetAtTime(frequency, time, 0.028);
      gain.gain.cancelScheduledValues(time);
      gain.gain.setTargetAtTime(level, time, 0.016);
      gain.gain.setTargetAtTime(0.0001, time + 0.045, 0.07);
    },
    silence() {
      const time = audio.currentTime;
      gain.gain.cancelScheduledValues(time);
      gain.gain.setTargetAtTime(0.0001, time, 0.025);
    },
    dispose() {
      source.stop();
      source.disconnect();
      filter.disconnect();
      gain.disconnect();
      output.disconnect();
    },
  };
}

export function createWheelDetentSound(audio) {
  const output = audio.createGain();
  output.gain.value = 1;
  output.connect(audio.destination);

  const buffer = makeNoiseBuffer(audio, 0.032, (time, noise) => {
    const attack = Math.min(1, time / 0.0014);
    const decay = Math.exp(-time * 108);
    const release = Math.max(0, 1 - time / 0.032);
    const body = Math.sin(Math.PI * 2 * 720 * time) * 0.5;
    const edge = Math.sin(Math.PI * 2 * 1_420 * time + 0.38) * 0.16;
    return attack * decay * release * release * (body + edge + noise * 0.13);
  });
  let nextDetentTime = 0;

  return {
    play(pointerSpeed, direction, detentIndex) {
      const time = audio.currentTime;
      if (time < nextDetentTime) return;
      nextDetentTime = time + 0.022;

      const speed = Math.min(1, Math.max(0, pointerSpeed / 0.72));
      const variation = ((detentIndex * 7) % 9 - 4) / 4;
      const source = audio.createBufferSource();
      const filter = audio.createBiquadFilter();
      const gain = audio.createGain();
      source.buffer = buffer;
      source.playbackRate.value = 0.96 + speed * 0.07 + variation * 0.008;
      filter.type = "lowpass";
      filter.frequency.value = 3_100 - speed * 420 + direction * 35;
      filter.Q.value = 0.52;
      gain.gain.value = 0.052 - speed * 0.015;
      source.connect(filter);
      filter.connect(gain);
      gain.connect(output);
      source.addEventListener("ended", () => {
        source.disconnect();
        filter.disconnect();
        gain.disconnect();
      }, { once: true });
      source.start(time);
    },
    dispose() {
      output.disconnect();
    },
  };
}
