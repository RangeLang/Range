import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";

const port = 43_000 + (process.pid % 1_000);
const origin = `http://127.0.0.1:${port}`;
let server: ReturnType<typeof Bun.spawn>;

beforeAll(async () => {
  server = Bun.spawn([process.execPath, "build/index.js"], {
    cwd: new URL("..", import.meta.url).pathname,
    env: { ...process.env, HOST: "127.0.0.1", PORT: String(port) },
    stdout: "ignore",
    stderr: "pipe",
  });

  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      const response = await fetch(origin);
      if (response.ok) return;
    } catch {
      await Bun.sleep(40);
    }
  }

  throw new Error("SvelteKit server did not start in time");
});

afterAll(() => server?.kill());

async function render(path = "/") {
  return fetch(`${origin}${path}`, { headers: { accept: "text/html" } });
}

describe("SvelteKit routes", () => {
  test("renders the Range landing page with its enhanced components", async () => {
    const response = await render();
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("a love letter to electrons, logic and abstraction");
    expect(html).toContain("<range-spline-nav");
    expect(html).toContain("<range-scale");
    expect(html).toContain('href="/benchmarks"');
    expect(html).toContain('href="/updates/string-lowering"');
    expect(html).not.toContain("Benchmark suite");
  });

  test("renders and filters the benchmark hierarchy", async () => {
    const response = await render("/benchmarks?category=noise");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("Benchmark suite");
    expect(html).toContain("Perlin");
    expect(html).toContain("Voronoi");
    expect(html).toContain("12 of 12 leaves run");
    expect(html).toContain("Range passed 12");
    expect(html).not.toContain("Sequential modulo");
  });

  test("renders an individual benchmark", async () => {
    const response = await render("/benchmarks/integer_loop");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("While · Sequential modulo");
    expect(html).toContain("Measurements");
    expect(html).toContain("Peak memory");
    expect(html).toContain("Run procedure");
    expect(html).toContain('class="token keyword">state</span>');
  });

  test("returns a real 404 for an unknown benchmark", async () => {
    expect((await render("/benchmarks/not-a-benchmark")).status).toBe(404);
  });

  test("renders the string-lowering update", async () => {
    const response = await render("/updates/string-lowering");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("String lowering");
    expect(html).toContain("~120× faster");
    expect(html).toContain("491.2 ms");
    expect(html).toContain("10m appends");
  });
});

test("keeps the generated benchmark artifact complete and versioned", async () => {
  const [artifactText, schemaText] = await Promise.all([
    readFile(new URL("../public/benchmarks.json", import.meta.url), "utf8"),
    readFile(new URL("../../Benchmarks/Speed/benchmark-results.schema.json", import.meta.url), "utf8"),
  ]);
  const artifact = JSON.parse(artifactText);
  const schema = JSON.parse(schemaText);

  expect(schema.required).toContain("schemaVersion");
  expect(artifact.schemaVersion).toBe(schema.properties.schemaVersion.const);
  expect(artifact.summary.leafCount).toBe(12);
  expect(artifact.summary.runLeafCount).toBe(12);
  expect(artifact.categories.length).toBeGreaterThan(0);
  expect(artifact.categories.flatMap((category: any) => category.subcategories).flatMap((subcategory: any) => subcategory.leaves)).toHaveLength(12);
});

test("uses Svelte components and Bun without the legacy renderer", async () => {
  const [packageText, layout, home, chart] = await Promise.all([
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../src/routes/+layout.svelte", import.meta.url), "utf8"),
    readFile(new URL("../src/routes/+page.svelte", import.meta.url), "utf8"),
    readFile(new URL("../src/lib/components/Chart.svelte", import.meta.url), "utf8"),
  ]);

  expect(packageText).toContain('"svelte": "5.56.7"');
  expect(packageText).toContain('"@sveltejs/kit": "2.70.1"');
  expect(layout).toContain("{@render children()}");
  expect(home).toContain("<range-home-page>");
  expect(chart).toContain("<range-benchmark-chart>");
});

test("keeps the scale math deterministic", async () => {
  const { createRangeMarks, createScaleMarks, pinchMarkerWidth, snapScalePosition } = await import("../public/range-scale-math.js");
  const logicalMarks = createScaleMarks({ divisionBase: 3, divisionLevels: 3 });
  expect(logicalMarks).toHaveLength(28);
  expect(new Set(logicalMarks.map((mark: any) => mark.measure))).toEqual(new Set([1]));
  const warpedMarks = createRangeMarks({ pinch: 0.27, pinchFalloff: 0.16, pinchStrength: 0.9 });
  expect(warpedMarks[7].position).toBe(7 / 27);
  expect(warpedMarks[7].width).toBe(pinchMarkerWidth(7 / 27, { center: 0.27, falloff: 0.16, strength: 0.9 }));
  expect(warpedMarks[7].width).toBeLessThan(warpedMarks[0].width);
  expect(warpedMarks.every((mark: any, index: number) => mark.position === index / 27)).toBe(true);
  expect(warpedMarks.every((mark: any) => mark.measure === 1)).toBe(true);
  expect(snapScalePosition(0.27)).toEqual({ index: 7, position: 7 / 27 });
});
