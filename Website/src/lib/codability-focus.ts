export type CodabilityFocusState = "entering" | "focused" | "exiting";

export function nextCodabilityFocusState({
  state,
  progress,
  centerOffset,
  interactionFocused = false,
}: {
  state: CodabilityFocusState;
  progress: number;
  centerOffset: number;
  interactionFocused?: boolean;
}): CodabilityFocusState {
  // Enter only at the plateau, but remain focused through a wider exit band.
  // The hysteresis prevents resize and fractional scroll measurements from
  // repeatedly flipping the code viewport between scroll modes.
  if (state === "focused") {
    if (interactionFocused && progress >= 0.8) return "focused";
    if (progress >= 0.94) return "focused";
    return centerOffset < 0 ? "exiting" : "entering";
  }

  if (progress >= 0.995) return "focused";
  return centerOffset < 0 ? "exiting" : "entering";
}

export function codabilityFocusProgress({
  stageTop,
  stageHeight,
  viewportHeight,
}: {
  stageTop: number;
  stageHeight: number;
  viewportHeight: number;
}) {
  const stageCenter = stageTop + stageHeight / 2;
  const centerDistance = Math.abs(stageCenter - viewportHeight / 2);
  const plateauHalfWidth = viewportHeight * 0.3;
  if (centerDistance <= plateauHalfWidth) return 1;

  const falloffRange = viewportHeight * 0.85;
  const distanceFromPlateau = centerDistance - plateauHalfWidth;
  const linearProgress = Math.max(
    0,
    Math.min(1, 1 - distanceFromPlateau / falloffRange),
  );
  return linearProgress * linearProgress * (3 - 2 * linearProgress);
}

export function codabilityPlateauScrollProgress({
  stageTop,
  stageHeight,
  viewportHeight,
}: {
  stageTop: number;
  stageHeight: number;
  viewportHeight: number;
}) {
  const centerOffset =
    stageTop + stageHeight / 2 - viewportHeight / 2;
  const plateauHalfWidth = viewportHeight * 0.3;
  return Math.max(
    0,
    Math.min(
      1,
      (plateauHalfWidth - centerOffset) / (plateauHalfWidth * 2),
    ),
  );
}
