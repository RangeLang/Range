const DEFAULT_EPSILON = 1e-7;

function assertFiniteNumber(value, label) {
  if (!Number.isFinite(value)) throw new TypeError(`${label} must be finite`);
}

export function createScaleMarks({ count = 18 } = {}) {
  if (!Number.isInteger(count) || count < 2) {
    throw new RangeError("count must be an integer of at least 2");
  }

  return Array.from({ length: count }, (_, index) => ({
    isRadix: index === 0 || index === count - 1 || index % 4 === 0,
    measure: index === 0 || index === count - 1 || index % 4 === 0 ? 1.8 : 1,
    position: index / (count - 1),
    source: "scale",
    weight: 1,
  }));
}

export function createPinchMarks({
  center = 0.27,
  count = 5,
  growth = 2.2,
  minimumDistance = 0.012,
} = {}) {
  assertFiniteNumber(center, "center");
  assertFiniteNumber(growth, "growth");
  assertFiniteNumber(minimumDistance, "minimumDistance");
  if (center < 0 || center > 1) throw new RangeError("center must be within [0, 1]");
  if (!Number.isInteger(count) || count < 1 || count % 2 === 0) {
    throw new RangeError("count must be a positive odd integer");
  }
  if (growth <= 1) throw new RangeError("growth must be greater than 1");
  if (minimumDistance <= 0) throw new RangeError("minimumDistance must be positive");

  const radius = (count - 1) / 2;
  return Array.from({ length: count }, (_, index) => {
    const signedStep = index - radius;
    const distance = signedStep === 0
      ? 0
      : Math.sign(signedStep) * minimumDistance * Math.pow(growth, Math.abs(signedStep) - 1);

    return {
      isRadix: signedStep === 0,
      position: center + distance,
      source: "pinch",
      weight: 1,
    };
  }).filter(({ position }) => position >= 0 && position <= 1);
}

export function measureWithFalloff(position, {
  baseline = 1,
  center = 0.27,
  falloff = 0.018,
  peak = 2.95,
} = {}) {
  assertFiniteNumber(position, "position");
  assertFiniteNumber(baseline, "baseline");
  assertFiniteNumber(center, "center");
  assertFiniteNumber(falloff, "falloff");
  assertFiniteNumber(peak, "peak");
  if (position < 0 || position > 1) throw new RangeError("position must be within [0, 1]");
  if (center < 0 || center > 1) throw new RangeError("center must be within [0, 1]");
  if (baseline <= 0) throw new RangeError("baseline must be positive");
  if (falloff <= 0) throw new RangeError("falloff must be positive");
  if (peak < baseline) throw new RangeError("peak cannot be less than baseline");

  const normalizedDistance = (position - center) / falloff;
  const influence = Math.exp(-0.5 * normalizedDistance * normalizedDistance);
  return baseline + (peak - baseline) * influence;
}

export function mergeMarks(markGroups, epsilon = DEFAULT_EPSILON) {
  assertFiniteNumber(epsilon, "epsilon");
  if (epsilon < 0) throw new RangeError("epsilon cannot be negative");

  const sorted = markGroups.flat().map((mark) => {
    const weight = mark.weight ?? 1;
    const measure = mark.measure ?? (mark.isRadix ? 1.8 : 1);
    assertFiniteNumber(mark.position, "mark.position");
    assertFiniteNumber(weight, "mark.weight");
    assertFiniteNumber(measure, "mark.measure");
    if (mark.position < 0 || mark.position > 1) {
      throw new RangeError("mark.position must be within [0, 1]");
    }
    if (weight <= 0) throw new RangeError("mark.weight must be positive");
    if (measure <= 0) throw new RangeError("mark.measure must be positive");
    if (typeof mark.source !== "string" || mark.source.length === 0) {
      throw new TypeError("mark.source must be a non-empty string");
    }
    return { ...mark, measure, weight };
  }).sort((left, right) => left.position - right.position);

  return sorted.reduce((merged, mark) => {
    const previous = merged.at(-1);
    if (!previous || mark.position - previous.anchor > epsilon) {
      merged.push({
        anchor: mark.position,
        isRadix: Boolean(mark.isRadix),
        measure: mark.measure,
        position: mark.position,
        sources: new Set([mark.source]),
        weight: mark.weight,
      });
      return merged;
    }

    const combinedWeight = previous.weight + mark.weight;
    previous.position = (
      previous.position * previous.weight + mark.position * mark.weight
    ) / combinedWeight;
    previous.measure = (
      previous.measure * previous.weight + mark.measure * mark.weight
    ) / combinedWeight;
    previous.weight = combinedWeight;
    previous.isRadix ||= Boolean(mark.isRadix);
    previous.sources.add(mark.source);
    return merged;
  }, []).map((mark) => ({
    isRadix: mark.isRadix,
    measure: mark.measure,
    position: mark.position,
    sources: [...mark.sources].sort(),
  }));
}

export function createRangeMarks(config = {}) {
  const groups = [
    createScaleMarks({ count: config.marks }),
    createPinchMarks({
      center: config.pinch,
      count: config.pinchMarks,
      growth: config.pinchGrowth,
      minimumDistance: config.pinchDistance,
    }),
  ];

  return mergeMarks(groups.map((marks) => marks.map((mark) => {
    const baseline = mark.measure ?? (mark.isRadix ? 1.8 : 1);
    return {
      ...mark,
      measure: Math.max(baseline, measureWithFalloff(mark.position, {
        center: config.pinch,
        falloff: config.measureFalloff,
        peak: config.measurePeak,
      })),
    };
  })));
}
