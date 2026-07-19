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
  if (!Number.isInteger(divisionBase) || divisionBase < 2) {
    throw new RangeError("divisionBase must be an integer of at least 2");
  }
  if (!Number.isInteger(divisionLevels) || divisionLevels < 1 || divisionLevels > 6) {
    throw new RangeError("divisionLevels must be an integer within [1, 6]");
  }

  const intervalCount = divisionBase ** divisionLevels;
  const majorStride = divisionBase ** (divisionLevels - 1);
  const divisionStride = divisionLevels > 1
    ? divisionBase ** (divisionLevels - 2)
    : majorStride;
  return Array.from({ length: intervalCount + 1 }, (_, index) => {
    const isMajor = index === 0 || index === intervalCount || index % majorStride === 0;
    const isDivision = !isMajor && index % divisionStride === 0;
    return {
      isRadix: isMajor || isDivision,
      measure: isMajor ? 5 : isDivision ? 3 : 1,
      position: index / intervalCount,
      source: "scale",
      tier: isMajor ? "major" : isDivision ? "division" : "single",
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
  return value + strength * offset * pinchInfluence(value, center, falloff);
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
  if (!Number.isInteger(divisionBase) || divisionBase < 2) {
    throw new RangeError("divisionBase must be an integer of at least 2");
  }
  if (!Number.isInteger(divisionLevels) || divisionLevels < 1 || divisionLevels > 6) {
    throw new RangeError("divisionLevels must be an integer within [1, 6]");
  }
  if (hysteresis < 0 || hysteresis >= 0.5) {
    throw new RangeError("hysteresis must be within [0, 0.5)");
  }

  const intervalCount = divisionBase ** divisionLevels;
  const candidate = Math.min(intervalCount, Math.max(0, Math.round(value * intervalCount)));
  let index = candidate;
  if (Number.isInteger(previousIndex) && previousIndex >= 0 && previousIndex <= intervalCount) {
    if (candidate > previousIndex) {
      const forwardBoundary = (previousIndex + 0.5 + hysteresis) / intervalCount;
      if (value < forwardBoundary) index = previousIndex;
    } else if (candidate < previousIndex) {
      const backwardBoundary = (previousIndex - 0.5 - hysteresis) / intervalCount;
      if (value > backwardBoundary) index = previousIndex;
    }
  }

  return { index, position: index / intervalCount };
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

  return logicalMarks.map((mark) => {
    const baseline = mark.measure ?? (mark.isRadix ? 1.8 : 1);
    if (mark.position === 0 || mark.position === 1) {
      return {
        ...mark,
        anchored: true,
        measure: baseline,
        opacity: 1,
        position: mark.position,
        stroke: 1,
        tone: 0,
      };
    }
    const markerCaptureWeight = baseline >= 5
      ? 1
      : baseline >= 3
        ? (config.markerCaptureDivisionWeight ?? 0.48)
        : 0;
    const shape = sphericalPinchInfluence(mark.position, {
      center: config.pinch,
      coreRadius: config.pinchCoreRadius,
      falloff: config.pinchFalloff,
      innerEdge: config.pinchInnerEdge,
    });
    const tone = sphericalPinchInfluence(mark.position, {
      center: config.pinch,
      coreRadius: config.pinchCoreRadius,
      falloff: config.toneFalloff,
      innerEdge: config.pinchInnerEdge,
    });
    const opacity = Math.max(0, 1 - tone ** 6 / 0.98);
    const collapse = (1 - opacity) ** (config.invisibleCollapsePower ?? 1.35);
    const measureCollapse = 1 - (1 - (config.invisibleMeasureMinimum ?? 0.1)) * collapse;
    const strokeCollapse = 1 - (1 - (config.invisibleStrokeMinimum ?? 0.06)) * collapse;
    const stroke = (1 - (1 - config.strokeMinimum) * shape) * strokeCollapse;
    return {
      ...mark,
      measure: baseline * (1 - (1 - config.measureMinimum) * shape) * measureCollapse,
      stroke,
      opacity,
      tone,
      position: captureMarkerPosition(pinchScaleValue(mark.position, {
        center: config.pinch,
        falloff: config.pinchFalloff,
        strength: config.pinchStrength,
      }), {
        anchor: mark.position,
        center: config.pinch,
        falloff: config.markerCaptureFalloff ?? 0.14,
        strength: config.markerCaptureStrength ?? 1,
        weight: markerCaptureWeight,
      }),
    };
  });
}
