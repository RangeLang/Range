const DEFAULT_EPSILON = 1e-7;

function assertFiniteNumber(value, label) {
  if (!Number.isFinite(value)) throw new TypeError(`${label} must be finite`);
}

export function normalizedLogPosition(step, base = 10) {
  assertFiniteNumber(step, "step");
  assertFiniteNumber(base, "base");
  if (step < 0 || step > 1) throw new RangeError("step must be within [0, 1]");
  if (base <= 1) throw new RangeError("base must be greater than 1");
  return Math.log1p((base - 1) * step) / Math.log(base);
}

export function createScaleMarks({ count = 18, base = 10 } = {}) {
  if (!Number.isInteger(count) || count < 2) {
    throw new RangeError("count must be an integer of at least 2");
  }

  return Array.from({ length: count }, (_, index) => ({
    isRadix: index === 0 || index === count - 1 || index % 4 === 0,
    position: normalizedLogPosition(index / (count - 1), base),
    source: "scale",
    weight: 1,
  }));
}

export function createPinchMarks({
  center = 0.27,
  count = 9,
  growth = 1.8,
  minimumDistance = 0.006,
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

export function mergeMarks(markGroups, epsilon = DEFAULT_EPSILON) {
  assertFiniteNumber(epsilon, "epsilon");
  if (epsilon < 0) throw new RangeError("epsilon cannot be negative");

  const sorted = markGroups.flat().map((mark) => {
    const weight = mark.weight ?? 1;
    assertFiniteNumber(mark.position, "mark.position");
    assertFiniteNumber(weight, "mark.weight");
    if (mark.position < 0 || mark.position > 1) {
      throw new RangeError("mark.position must be within [0, 1]");
    }
    if (weight <= 0) throw new RangeError("mark.weight must be positive");
    if (typeof mark.source !== "string" || mark.source.length === 0) {
      throw new TypeError("mark.source must be a non-empty string");
    }
    return { ...mark, weight };
  }).sort((left, right) => left.position - right.position);

  return sorted.reduce((merged, mark) => {
    const previous = merged.at(-1);
    if (!previous || mark.position - previous.anchor > epsilon) {
      merged.push({
        anchor: mark.position,
        isRadix: Boolean(mark.isRadix),
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
    previous.weight = combinedWeight;
    previous.isRadix ||= Boolean(mark.isRadix);
    previous.sources.add(mark.source);
    return merged;
  }, []).map((mark) => ({
    isRadix: mark.isRadix,
    position: mark.position,
    sources: [...mark.sources].sort(),
  }));
}

export function createLogarithmicMarks(config = {}) {
  return mergeMarks([
    createScaleMarks({ count: config.marks, base: config.base }),
    createPinchMarks({
      center: config.pinch,
      count: config.pinchMarks,
      growth: config.pinchGrowth,
      minimumDistance: config.pinchDistance,
    }),
  ]);
}
