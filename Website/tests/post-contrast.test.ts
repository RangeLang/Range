import { describe, expect, test } from "bun:test";
import {
  contrastRatio,
  measurePostContrast,
} from "../src/lib/post-contrast";

const solidPixels = (
  width: number,
  height: number,
  red: number,
  green: number,
  blue: number,
) => {
  const pixels = new Uint8Array(width * height * 4);
  for (let offset = 0; offset < pixels.length; offset += 4) {
    pixels[offset] = red;
    pixels[offset + 1] = green;
    pixels[offset + 2] = blue;
    pixels[offset + 3] = 255;
  }
  return pixels;
};

const parseRgb = (value: string) => {
  const [red, green, blue] = value
    .slice(4, -1)
    .split(" ")
    .map((channel) => Number(channel) / 255);
  return { red: red!, green: green!, blue: blue! };
};

describe("post card contrast", () => {
  test("selects a dark complementary foreground for a bright pink field", () => {
    const measured = measurePostContrast(
      solidPixels(16, 10, 196, 89, 166),
      16,
      10,
    );
    const background = parseRgb(measured.background);
    const foreground = parseRgb(measured.foreground);

    expect(measured.complementHue).toBeGreaterThan(120);
    expect(measured.complementHue).toBeLessThan(210);
    expect(measured.contrast).toBeGreaterThanOrEqual(4.5);
    expect(Math.max(foreground.red, foreground.green, foreground.blue) -
      Math.min(foreground.red, foreground.green, foreground.blue)).toBeGreaterThan(0.08);
    expect(contrastRatio(foreground, background)).toBeGreaterThanOrEqual(4.5);
    expect(
      contrastRatio(parseRgb(measured.mutedForeground), background),
    ).toBeGreaterThanOrEqual(4.5);
  });

  test("selects a light complementary foreground for a dark blue field", () => {
    const measured = measurePostContrast(
      solidPixels(16, 10, 20, 31, 71),
      16,
      10,
    );
    const background = parseRgb(measured.background);

    expect(measured.contrast).toBeGreaterThanOrEqual(4.5);
    expect(contrastRatio(parseRgb(measured.foreground), background)).toBeGreaterThanOrEqual(
      4.5,
    );
    expect(
      contrastRatio(parseRgb(measured.mutedForeground), background),
    ).toBeGreaterThanOrEqual(4.5);
  });
});
