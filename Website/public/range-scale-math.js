const DEFAULT_EPSILON = 1e-7;

function assertFiniteNumber(value, label) {
  if (!Number.isFinite(value)) throw new TypeError(`${label} must be finite`);
}

function pinchInfluence(value, center, falloff) {
  const normalizedDistance = (value - center) / falloff;
  const supportRadius = Math.min(center, 1 - center, falloff * 2);
  const supportDistance = Math.abs(value - center) / supportRadius;
  if (supportDistance >= 1) return 0;

  const taper = Math.pow(1 - supportDistance * supportDistance, 2);
  return Math.exp(-0.5 * normalizedDistance * normalizedDistance) * taper;
}

function scaleIntervalCount(divisionBase, divisionLevels) {
  if (!Number.isInteger(divisionBase) || divisionBase < 2) {
    throw new RangeError("divisionBase must be an integer of at least 2");
  }
  if (!Number.isInteger(divisionLevels) || divisionLevels < 1 || divisionLevels > 6) {
    throw new RangeError("divisionLevels must be an integer within [1, 6]");
  }
  return divisionBase ** divisionLevels;
}

export function logarithmicScalePosition(value, {
  divisionBase = 3,
  divisionLevels = 3,
} = {}) {
  assertFiniteNumber(value, "value");
  if (value < 0 || value > 1) throw new RangeError("value must be within [0, 1]");

  const intervalCount = scaleIntervalCount(divisionBase, divisionLevels);
  return Math.log1p(value * intervalCount) / Math.log1p(intervalCount);
}

export function logarithmicScalePositionAround(value, {
  center = 0,
  divisionBase = 3,
  divisionLevels = 3,
} = {}) {
  assertFiniteNumber(value, "value");
  assertFiniteNumber(center, "center");
  if (value < 0 || value > 1) throw new RangeError("value must be within [0, 1]");
  if (center < 0 || center > 1) throw new RangeError("center must be within [0, 1]");

  if (center === 0) {
    return logarithmicScalePosition(value, { divisionBase, divisionLevels });
  }
  if (center === 1) {
    return 1 - logarithmicScalePosition(1 - value, {
      divisionBase,
      divisionLevels,
    });
  }
  if (value === center) return center;

  if (value < center) {
    const distance = (center - value) / center;
    return center - center * logarithmicScalePosition(distance, {
      divisionBase,
      divisionLevels,
    });
  }

  const distance = (value - center) / (1 - center);
  return center + (1 - center) * logarithmicScalePosition(distance, {
    divisionBase,
    divisionLevels,
  });
}

export function dragZeroWithFalloff(position, {
  value = position,
  drag = 0,
  falloff = 0.38,
} = {}) {
  for (const [number, label] of [
    [position, "position"],
    [value, "value"],
    [drag, "drag"],
    [falloff, "falloff"],
  ]) assertFiniteNumber(number, label);
  if (position < 0 || position > 1) throw new RangeError("position must be within [0, 1]");
  if (value < 0 || value > 1) throw new RangeError("value must be within [0, 1]");
  if (drag < 0 || drag >= 1) throw new RangeError("drag must be within [0, 1)");
  if (falloff <= 0 || falloff > 1) throw new RangeError("falloff must be within (0, 1]");
  if (drag === 0 || value >= falloff) return position;

  const falloffProgress = value / falloff;
  const influence = Math.pow(1 - falloffProgress * falloffProgress, 2);
  const compressedPosition = drag + (1 - drag) * position;
  return position + (compressedPosition - position) * influence;
}

export function sphericalPinchInfluence(value, {
  center = 0.27,
  coreRadius = 0,
  falloff = 0.12,
  innerEdge = 0.68,
} = {}) {
  assertFiniteNumber(value, "value");
  assertFiniteNumber(center, "center");
  assertFiniteNumber(coreRadius, "coreRadius");
  assertFiniteNumber(falloff, "falloff");
  assertFiniteNumber(innerEdge, "innerEdge");
  if (value < 0 || value > 1) throw new RangeError("value must be within [0, 1]");
  if (center <= 0 || center >= 1) throw new RangeError("center must be inside (0, 1)");
  if (coreRadius < 0) throw new RangeError("coreRadius cannot be negative");
  if (falloff <= 0) throw new RangeError("falloff must be positive");
  if (innerEdge < 0 || innerEdge > 1) throw new RangeError("innerEdge must be within [0, 1]");

  const distance = Math.abs(value - center);
  if (coreRadius > 0 && distance < coreRadius) {
    const progress = distance / coreRadius;
    const smoothProgress = progress * progress * (3 - 2 * progress);
    return 1 - (1 - innerEdge) * smoothProgress;
  }

  const outsideDistance = Math.max(0, distance - coreRadius);
  const outside = Math.exp(-0.5 * (outsideDistance / falloff) ** 2);
  const supportRadius = Math.min(center, 1 - center, coreRadius + falloff * 2);
  const supportProgress = Math.min(1, distance / supportRadius);
  const taper = (1 - supportProgress * supportProgress) ** 2;
  return innerEdge * outside * taper;
}

export function createScaleMarks({ divisionBase = 3, divisionLevels = 3 } = {}) {
  const intervalCount = scaleIntervalCount(divisionBase, divisionLevels);
  const majorStride = divisionBase ** (divisionLevels - 1);
  const divisionStride = divisionLevels > 1
    ? divisionBase ** (divisionLevels - 2)
    : majorStride;
  return Array.from({ length: intervalCount + 1 }, (_, index) => {
    const isMajor = index === 0 || index === intervalCount || index % majorStride === 0;
    const isDivision = !isMajor && index % divisionStride === 0;
    return {
      isRadix: isMajor || isDivision,
      measure: 1,
      position: logarithmicScalePosition(index / intervalCount, {
        divisionBase,
        divisionLevels,
      }),
      source: "scale",
      tier: isMajor ? "major" : isDivision ? "division" : "single",
      value: index / intervalCount,
      weight: 1,
    };
  });
}

export function pinchScaleValue(value, {
  center = 0.27,
  falloff = 0.16,
  strength = 0.9,
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
  return value - strength * offset * pinchInfluence(value, center, falloff);
}

export function pinchMarkerWidth(value, {
  center = 0.27,
  falloff = 0.16,
  strength = 0.9,
} = {}) {
  assertFiniteNumber(value, "value");
  assertFiniteNumber(center, "center");
  assertFiniteNumber(falloff, "falloff");
  assertFiniteNumber(strength, "strength");
  if (value < 0 || value > 1) throw new RangeError("value must be within [0, 1]");
  if (center <= 0 || center >= 1) throw new RangeError("center must be inside (0, 1)");
  if (falloff <= 0) throw new RangeError("falloff must be positive");
  if (strength < 0 || strength > 1) throw new RangeError("strength must be within [0, 1]");

  return 1 - strength * pinchInfluence(value, center, falloff);
}

export function captureMarkerPosition(position, {
  anchor = position,
  center = 0.27,
  falloff = 0.14,
  strength = 1,
  weight = 1,
} = {}) {
  for (const [value, label] of [
    [position, "position"],
    [anchor, "anchor"],
    [center, "center"],
    [falloff, "falloff"],
    [strength, "strength"],
    [weight, "weight"],
  ]) assertFiniteNumber(value, label);
  if (position < 0 || position > 1) throw new RangeError("position must be within [0, 1]");
  if (anchor < 0 || anchor > 1) throw new RangeError("anchor must be within [0, 1]");
  if (center <= 0 || center >= 1) throw new RangeError("center must be inside (0, 1)");
  if (falloff <= 0) throw new RangeError("falloff must be positive");
  if (strength < 0 || strength > 1) throw new RangeError("strength must be within [0, 1]");
  if (weight < 0 || weight > 1) throw new RangeError("weight must be within [0, 1]");

  const distance = Math.abs(anchor - center);
  if (distance >= falloff || strength === 0 || weight === 0) return position;
  const proximity = 1 - distance / falloff;
  const field = proximity * proximity * (3 - 2 * proximity);
  return position + (center - position) * field * strength * weight;
}

export function snapScalePosition(value, {
  divisionBase = 3,
  divisionLevels = 3,
  hysteresis = 0.08,
  previousIndex,
} = {}) {
  assertFiniteNumber(value, "value");
  assertFiniteNumber(hysteresis, "hysteresis");
  if (value < 0 || value > 1) throw new RangeError("value must be within [0, 1]");
  const intervalCount = scaleIntervalCount(divisionBase, divisionLevels);
  if (hysteresis < 0 || hysteresis >= 0.5) {
    throw new RangeError("hysteresis must be within [0, 0.5)");
  }

  const positions = Array.from(
    { length: intervalCount + 1 },
    (_, index) => logarithmicScalePosition(index / intervalCount, {
      divisionBase,
      divisionLevels,
    }),
  );
  let candidate = 0;
  while (
    candidate < intervalCount
    && value >= (positions[candidate] + positions[candidate + 1]) / 2
  ) candidate += 1;

  let index = candidate;
  if (Number.isInteger(previousIndex) && previousIndex >= 0 && previousIndex <= intervalCount) {
    if (candidate > previousIndex) {
      const nextIndex = Math.min(intervalCount, previousIndex + 1);
      const forwardBoundary = positions[previousIndex]
        + (0.5 + hysteresis) * (positions[nextIndex] - positions[previousIndex]);
      if (value < forwardBoundary) index = previousIndex;
    } else if (candidate < previousIndex) {
      const priorIndex = Math.max(0, previousIndex - 1);
      const backwardBoundary = positions[previousIndex]
        - (0.5 + hysteresis) * (positions[previousIndex] - positions[priorIndex]);
      if (value > backwardBoundary) index = previousIndex;
    }
  }

  return { index, position: positions[index] };
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

  const influence = pinchInfluence(position, center, falloff);
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
  const logicalMarks = createScaleMarks({
    divisionBase: config.divisionBase,
    divisionLevels: config.divisionLevels,
  });
  const center = Number.isFinite(config.focusPosition)
    ? Math.min(1, Math.max(0, config.focusPosition))
    : 0;

  return logicalMarks.map((mark) => ({
    ...mark,
    anchored: mark.position === 0 || mark.position === 1,
    position: logarithmicScalePositionAround(mark.value, {
      center,
      divisionBase: config.divisionBase,
      divisionLevels: config.divisionLevels,
    }),
    width: 1,
  }));
}
