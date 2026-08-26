export type PostContrastPalette = {
  foreground: string;
  mutedForeground: string;
  background: string;
  contrast: number;
  complementHue: number;
};

type Rgb = {
  red: number;
  green: number;
  blue: number;
};

type Candidate = {
  color: Rgb;
  css: string;
  contrast: number;
  chroma: number;
  lightness: number;
};

const clamp = (value: number, minimum = 0, maximum = 1) =>
  Math.min(maximum, Math.max(minimum, value));

const srgbToLinear = (channel: number) =>
  channel <= 0.04045
    ? channel / 12.92
    : ((channel + 0.055) / 1.055) ** 2.4;

const linearToSrgb = (channel: number) =>
  channel <= 0.0031308
    ? 12.92 * channel
    : 1.055 * channel ** (1 / 2.4) - 0.055;

const relativeLuminance = ({ red, green, blue }: Rgb) =>
  0.2126 * srgbToLinear(red) +
  0.7152 * srgbToLinear(green) +
  0.0722 * srgbToLinear(blue);

export const contrastRatio = (first: Rgb, second: Rgb) => {
  const lighter = Math.max(relativeLuminance(first), relativeLuminance(second));
  const darker = Math.min(relativeLuminance(first), relativeLuminance(second));
  return (lighter + 0.05) / (darker + 0.05);
};

const rgbToOklab = ({ red, green, blue }: Rgb) => {
  const linearRed = srgbToLinear(red);
  const linearGreen = srgbToLinear(green);
  const linearBlue = srgbToLinear(blue);
  const l = Math.cbrt(
    0.4122214708 * linearRed +
      0.5363325363 * linearGreen +
      0.0514459929 * linearBlue,
  );
  const m = Math.cbrt(
    0.2119034982 * linearRed +
      0.6806995451 * linearGreen +
      0.1073969566 * linearBlue,
  );
  const s = Math.cbrt(
    0.0883024619 * linearRed +
      0.2817188376 * linearGreen +
      0.6299787005 * linearBlue,
  );

  return {
    lightness: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  };
};

const oklchToRgb = (lightness: number, chroma: number, hue: number): Rgb => {
  const radians = (hue * Math.PI) / 180;
  const a = chroma * Math.cos(radians);
  const b = chroma * Math.sin(radians);
  const lRoot = lightness + 0.3963377774 * a + 0.2158037573 * b;
  const mRoot = lightness - 0.1055613458 * a - 0.0638541728 * b;
  const sRoot = lightness - 0.0894841775 * a - 1.291485548 * b;
  const l = lRoot ** 3;
  const m = mRoot ** 3;
  const s = sRoot ** 3;

  return {
    red: clamp(
      linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    ),
    green: clamp(
      linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    ),
    blue: clamp(
      linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
    ),
  };
};

const rgbCss = ({ red, green, blue }: Rgb) =>
  `rgb(${Math.round(red * 255)} ${Math.round(green * 255)} ${Math.round(blue * 255)})`;

const conservativeContrast = (
  foreground: Rgb,
  backgroundLuminances: number[],
  ratios: Float64Array,
) => {
  const foregroundLuminance = relativeLuminance(foreground);
  for (let index = 0; index < backgroundLuminances.length; index += 1) {
    const backgroundLuminance = backgroundLuminances[index] ?? 0;
    const lighter = Math.max(foregroundLuminance, backgroundLuminance);
    const darker = Math.min(foregroundLuminance, backgroundLuminance);
    ratios[index] = (lighter + 0.05) / (darker + 0.05);
  }
  ratios.sort();
  return ratios[Math.floor((ratios.length - 1) * 0.1)] ?? 1;
};

const copyScrimAlpha = (x: number, y: number) => {
  const distance = Math.hypot((x - 0.5) / 0.92, (y - 1.18) / 1.18);
  if (distance >= 0.78) return 0;
  if (distance <= 0.54) {
    return 0.52 + (0.18 - 0.52) * (distance / 0.54);
  }
  return 0.18 * (1 - (distance - 0.54) / (0.78 - 0.54));
};

export function measurePostContrast(
  pixels: Uint8Array,
  width: number,
  height: number,
): PostContrastPalette {
  const backgrounds: Rgb[] = [];
  let lightness = 0;
  let a = 0;
  let b = 0;
  const textRegionStart = Math.floor(height * 0.12);
  const textRegionEnd = Math.max(
    textRegionStart + 1,
    Math.ceil(height * 0.56),
  );

  for (let y = textRegionStart; y < textRegionEnd; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * 4;
      const alpha = copyScrimAlpha(
        (x + 0.5) / width,
        1 - (y + 0.5) / height,
      );
      const color = {
        red: ((pixels[offset] ?? 0) / 255) * (1 - alpha) + alpha,
        green: ((pixels[offset + 1] ?? 0) / 255) * (1 - alpha) + alpha,
        blue: ((pixels[offset + 2] ?? 0) / 255) * (1 - alpha) + alpha,
      };
      const lab = rgbToOklab(color);
      backgrounds.push(color);
      lightness += lab.lightness;
      a += lab.a;
      b += lab.b;
    }
  }

  const count = Math.max(1, backgrounds.length);
  const averageLightness = lightness / count;
  const averageA = a / count;
  const averageB = b / count;
  const sourceHue =
    Math.abs(averageA) + Math.abs(averageB) < 0.0001
      ? 80
      : ((Math.atan2(averageB, averageA) * 180) / Math.PI + 360) % 360;
  const complementHue = (sourceHue + 180) % 360;
  const candidates: Candidate[] = [];
  const backgroundLuminances = backgrounds.map(relativeLuminance);
  const contrastRatios = new Float64Array(backgroundLuminances.length);

  for (const requestedChroma of [0.04, 0.07, 0.1, 0.13, 0.16, 0.19]) {
    for (let step = 4; step <= 98; step += 2) {
      const candidateLightness = step / 100;
      const color = oklchToRgb(
        candidateLightness,
        requestedChroma,
        complementHue,
      );
      const actualLab = rgbToOklab(color);
      candidates.push({
        color,
        css: rgbCss(color),
        contrast: conservativeContrast(
          color,
          backgroundLuminances,
          contrastRatios,
        ),
        chroma: Math.hypot(actualLab.a, actualLab.b),
        lightness: candidateLightness,
      });
    }
  }

  const strongest = candidates.toSorted(
    (first, second) =>
      second.contrast - first.contrast ||
      Math.abs(first.lightness - averageLightness) -
        Math.abs(second.lightness - averageLightness),
  )[0]!;
  const accessible = candidates
    .filter((candidate) => candidate.contrast >= 4.5)
    .toSorted(
      (first, second) =>
        second.chroma - first.chroma ||
        Math.abs(first.lightness - averageLightness) -
          Math.abs(second.lightness - averageLightness) ||
        second.contrast - first.contrast,
    );
  const foreground = accessible[0] ?? strongest;
  const foregroundIsDark = foreground.lightness < averageLightness;
  const muted =
    accessible
      .filter(
        (candidate) =>
          candidate.chroma <= foreground.chroma * 0.65 &&
          (foregroundIsDark
            ? candidate.lightness < averageLightness
            : candidate.lightness > averageLightness),
      )
      .sort(
        (first, second) =>
          Math.abs(first.lightness - averageLightness) -
          Math.abs(second.lightness - averageLightness),
      )[0] ?? foreground;
  const averageBackground = backgrounds.reduce(
    (sum, color) => ({
      red: sum.red + color.red / count,
      green: sum.green + color.green / count,
      blue: sum.blue + color.blue / count,
    }),
    { red: 0, green: 0, blue: 0 },
  );

  return {
    foreground: foreground.css,
    mutedForeground: muted.css,
    background: rgbCss(averageBackground),
    contrast: foreground.contrast,
    complementHue,
  };
}
