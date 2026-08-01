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

export function createHashingSound(audio, destination) {
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
  output.connect(destination);

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

export function createScaleClickerSound(audio, destination) {
  const output = audio.createGain();
  output.gain.value = 1;
  output.connect(destination);

  const buffer = makeNoiseBuffer(audio, 0.014, (time, noise) => {
    const attack = Math.min(1, time / 0.0003);
    const decay = Math.exp(-time * 430);
    const mechanicalSnap = Math.max(0, 1 - time / 0.0011);
    return attack * decay * (noise * 0.76 + mechanicalSnap * 0.42);
  });
  let nextClickTime = 0;

  return {
    play(pointerSpeed) {
      const time = audio.currentTime;
      if (time < nextClickTime) return;
      nextClickTime = time + 0.028;

      const speed = Math.min(1, Math.max(0, pointerSpeed / 0.72));
      const source = audio.createBufferSource();
      const clickFilter = audio.createBiquadFilter();
      const gain = audio.createGain();
      source.buffer = buffer;
      source.playbackRate.value = 0.98 + speed * 0.025;
      clickFilter.type = "bandpass";
      clickFilter.frequency.value = 2_350;
      clickFilter.Q.value = 0.72;
      gain.gain.value = 0.044 - speed * 0.008;
      source.connect(clickFilter);
      clickFilter.connect(gain);
      gain.connect(output);
      source.addEventListener("ended", () => {
        source.disconnect();
        clickFilter.disconnect();
        gain.disconnect();
      }, { once: true });
      source.start(time);
    },
    dispose() {
      output.disconnect();
    },
  };
}
