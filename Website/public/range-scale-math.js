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

export function pinchScaleValue(value, {
  center = 0.27,
  falloff = 0.12,
  strength = 0.72,
} = {}) {
  assertFiniteNumber(value, "value");
  assertFiniteNumber(center, "center");
  assertFiniteNumber(falloff, "falloff");
  assertFiniteNumber(strength, "strength");
  if (value < 0 || value > 1) throw new RangeError("value must be within [0, 1]");
  if (center < 0 || center > 1) throw new RangeError("center must be within [0, 1]");
  if (center === 0 || center === 1) throw new RangeError("center must be inside (0, 1)");
  if (falloff <= 0) throw new RangeError("falloff must be positive");
  if (strength < 0 || strength >= 1) throw new RangeError("strength must be within [0, 1)");

  const offset = value - center;
  const normalizedDistance = offset / falloff;
  const influence = Math.exp(-0.5 * normalizedDistance * normalizedDistance);
  const endpointEnvelope = value * (1 - value) / (center * (1 - center));
  return value - strength * offset * influence * endpointEnvelope;
}

export function measureWithFalloff(position, {
  baseline = 1,
  center = 0.27,
  falloff = 0.12,
  minimum = 0.35,
} = {}) {
  assertFiniteNumber(position, "position");
  assertFiniteNumber(baseline, "baseline");
  assertFiniteNumber(center, "center");
  assertFiniteNumber(falloff, "falloff");
  assertFiniteNumber(minimum, "minimum");
  if (position < 0 || position > 1) throw new RangeError("position must be within [0, 1]");
  if (center < 0 || center > 1) throw new RangeError("center must be within [0, 1]");
  if (center === 0 || center === 1) throw new RangeError("center must be inside (0, 1)");
  if (baseline <= 0) throw new RangeError("baseline must be positive");
  if (falloff <= 0) throw new RangeError("falloff must be positive");
  if (minimum <= 0 || minimum > baseline) {
    throw new RangeError("minimum must be positive and cannot exceed baseline");
  }

  const normalizedDistance = (position - center) / falloff;
  const supportRadius = Math.min(center, 1 - center, falloff * 2);
  const supportDistance = Math.abs(position - center) / supportRadius;
  const taper = supportDistance >= 1 ? 0 : Math.pow(1 - supportDistance * supportDistance, 2);
  const influence = Math.exp(-0.5 * normalizedDistance * normalizedDistance) * taper;
  return baseline - (baseline - minimum) * influence;
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
  const logicalMarks = mergeMarks([
    createScaleMarks({ count: config.marks }),
    [{
      isRadix: true,
      position: config.pinch,
      source: "scale",
      weight: 1,
    }],
  ]);

  return logicalMarks.map((mark) => {
    const baseline = mark.measure ?? (mark.isRadix ? 1.8 : 1);
    return {
      ...mark,
      measure: measureWithFalloff(mark.position, {
        baseline,
        center: config.pinch,
        falloff: config.pinchFalloff,
        minimum: config.measureMinimum,
      }),
      position: pinchScaleValue(mark.position, {
        center: config.pinch,
        falloff: config.pinchFalloff,
        strength: config.pinchStrength,
      }),
    };
  });
}
