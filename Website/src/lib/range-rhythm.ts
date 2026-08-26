export const rangeRhythmUnitSeconds = 0.6;
export const rangeRhythmMultipliers = [1, 2, 4] as const;
export const rangePlaybackOrder = [
  "shape",
  "ownership",
  "capability",
  "shape",
  "ownership",
  "shape",
] as const;

export function rangeRhythmStep(index: number) {
  const normalizedIndex = (
    (index % rangeRhythmMultipliers.length) + rangeRhythmMultipliers.length
  ) % rangeRhythmMultipliers.length;
  const multiplier = rangeRhythmMultipliers[normalizedIndex];
  const windowSeconds = multiplier * rangeRhythmUnitSeconds;

  return {
    multiplier,
    windowSeconds,
    noteSeconds: windowSeconds * 0.9,
  };
}

export function rangePlaybackStep(index: number) {
  const normalizedIndex = (
    (index % rangePlaybackOrder.length) + rangePlaybackOrder.length
  ) % rangePlaybackOrder.length;

  return {
    conceptID: rangePlaybackOrder[normalizedIndex],
    ...rangeRhythmStep(normalizedIndex),
  };
}
