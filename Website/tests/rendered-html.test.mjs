import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render(pathname = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`http://localhost${pathname}`, { headers: { accept: "text/html" } }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("renders the Range landing page", async () => {
  const response = await render();
  assert.equal(response.status, 200);

  const html = (await response.text()).replaceAll("<!-- -->", "");
  assert.match(html, /<h1[^>]*>.*>1<\/span>.*>Range<\/span><\/h1>/);
  assert.match(html, /landingWordmark[^>]*>.*>0<\/span>.*>Range<\/span>/);
  assert.match(
    html,
    /<range-log-scale(?=[^>]*base="10")(?=[^>]*endpoint-gap="8")(?=[^>]*marks="18")(?=[^>]*pinch="0.27")(?=[^>]*pinch-marks="5")[^>]*>/,
  );
  assert.match(html, /<script[^>]*type="module"[^>]*src="\/range-log-scale\.js"/);
  assert.match(html, /Range-authored and emits native LLVM/);
  assert.doesNotMatch(html, /12 of 12 passed/);
  assert.doesNotMatch(html, /landingFacts/);
  assert.match(html, /href="\/benchmarks"/);
  assert.match(html, /href="\/updates\/string-lowering"/);
  assert.doesNotMatch(html, /Benchmark suite/);
});

test("renders the generated benchmark hierarchy", async () => {
  const response = await render("/benchmarks");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  const normalized = html.replaceAll("<!-- -->", "");
  assert.match(normalized, /<title>Range<\/title>/i);
  assert.match(normalized, /Range Performance/);
  assert.match(normalized, /Benchmark suite/);
  assert.match(normalized, /Sequential modulo/);
  assert.match(normalized, /href="\/benchmarks\?category=noise"/);
  assert.match(normalized, /<a(?=[^>]*href="\/benchmarks\?category=loops")(?=[^>]*aria-current="page")[^>]*>/);
  assert.doesNotMatch(normalized, /Perlin/);
  assert.match(normalized, /12 of 12 leaves run/);
  assert.match(normalized, /Range passed 12/);
  assert.match(normalized, /Not emitted 0/);
  assert.match(normalized, /Failed 0/);
  assert.match(normalized, /Run procedure/);
  assert.match(normalized, /Test code/);
  assert.match(normalized, /C · main\.c/);
  assert.match(normalized, /Range · Playground\.range/);
  assert.match(normalized, /aria-label="Suite"/);
  assert.match(normalized, /class="token keyword"[^>]*>state<\/span>/);
  assert.match(normalized, /class="token [^"]*atrule[^"]*"[^>]*>@main<\/span>/);
  assert.match(normalized, /class="token [^"]*class-name[^"]*"[^>]*>Int<\/span>/);
  assert.match(normalized, /Initial benchmark/);
  assert.match(normalized, /href="\/benchmarks\/integer_loop"/);
  assert.match(normalized, /href="\/updates\/string-lowering"/);
  assert.doesNotMatch(normalized, /Range Strings improvement/);
  assert.doesNotMatch(normalized, /Building your site|Your site is taking shape|codex-preview/i);
});

test("filters the benchmark display by selected category", async () => {
  const response = await render("/benchmarks?category=noise");
  assert.equal(response.status, 200);

  const html = (await response.text()).replaceAll("<!-- -->", "");
  assert.match(html, /<a(?=[^>]*href="\/benchmarks\?category=noise")(?=[^>]*aria-current="page")[^>]*>/);
  assert.match(html, /Perlin/);
  assert.match(html, /Voronoi/);
  assert.match(html, /Value Noise/);
  assert.doesNotMatch(html, /Sequential modulo/);
});

test("renders an individual benchmark route", async () => {
  const response = await render("/benchmarks/integer_loop");
  assert.equal(response.status, 200);

  const html = (await response.text()).replaceAll("<!-- -->", "");
  assert.match(html, /<a[^>]*href="\/benchmarks"[^>]*>Benchmarks<\/a>/);
  assert.match(html, /<h1>While · Sequential modulo<\/h1>/);
  assert.match(html, /Measurements/);
  assert.match(html, /Peak memory/);
  assert.match(html, /Run procedure/);
  assert.match(html, /Test code/);
  assert.match(html, /class="token keyword"[^>]*>state<\/span>/);
});

test("renders string lowering as its own update route", async () => {
  const response = await render("/updates/string-lowering");
  assert.equal(response.status, 200);

  const html = (await response.text()).replaceAll("<!-- -->", "");
  assert.match(html, /<h1>String lowering<\/h1>/);
  assert.match(html, /href="\/">Range<\/a>/);
  assert.match(html, /Sequence/);
  assert.match(html, /Improvement/);
  assert.match(html, /~120× faster/);
  assert.match(html, /491\.2 ms/);
  assert.match(html, /4\.1 ms/);
  assert.match(html, /Scaling/);
  assert.match(html, /10m appends/);
});

test("merges configurable logarithmic marks deterministically", async () => {
  const mathUrl = new URL("../public/range-log-scale-math.js", import.meta.url);
  mathUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const {
    createLogarithmicMarks,
    mergeMarks,
    normalizedLogPosition,
  } = await import(mathUrl.href);

  assert.equal(normalizedLogPosition(0, 10), 0);
  assert.equal(normalizedLogPosition(1, 10), 1);

  const marks = createLogarithmicMarks({
    base: 10,
    marks: 18,
    pinch: 0.27,
    pinchDistance: 0.006,
    pinchGrowth: 1.8,
    pinchMarks: 5,
  });
  assert.ok(marks.every((mark) => mark.position >= 0 && mark.position <= 1));
  assert.ok(marks.every((mark, index) => index === 0 || mark.position > marks[index - 1].position));
  assert.ok(marks.some((mark) => Math.abs(mark.position - 0.27) < 1e-12 && mark.isRadix));

  const merged = mergeMarks([
    [{ isRadix: false, position: 0.27, source: "scale", weight: 1 }],
    [{ isRadix: true, position: 0.27000000001, source: "pinch", weight: 3 }],
  ]);
  const expectedPosition = (0.27 + 0.27000000001 * 3) / 4;
  assert.equal(merged.length, 1);
  assert.ok(Math.abs(merged[0].position - expectedPosition) < 1e-15);
  assert.equal(merged[0].isRadix, true);
  assert.deepEqual(merged[0].sources, ["pinch", "scale"]);
  assert.throws(
    () => mergeMarks([[{ position: 0.5, source: "invalid", weight: 0 }]]),
    /mark\.weight must be positive/,
  );
});

test("keeps the benchmark artifact complete and versioned", async () => {
  const [
    artifactText,
    benchmarkPage,
    landingPage,
    styles,
    schemaText,
    serverBundle,
    logScaleElement,
  ] = await Promise.all([
    readFile(new URL("../public/benchmarks.json", import.meta.url), "utf8"),
    readFile(new URL("../app/benchmarks/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../../benchmark-results.schema.json", import.meta.url), "utf8"),
    readFile(new URL("../dist/server/index.js", import.meta.url), "utf8"),
    readFile(new URL("../public/range-log-scale.js", import.meta.url), "utf8"),
  ]);
  const artifact = JSON.parse(artifactText);
  const schema = JSON.parse(schemaText);

  assert.equal(artifact.schemaVersion, 2);
  assert.equal(schema.properties.schemaVersion.const, 2);
  assert.equal(artifact.summary.leafCount, 12);
  assert.equal(artifact.summary.runLeafCount, 12);
  assert.equal(artifact.summary.rangePassed, 12);
  assert.equal(artifact.procedure.commands.c[0], "cc -O3 -mcpu=native main.c -o speed-c");
  assert.match(artifact.procedure.commands.range[0], /emit-llvm/);

  const leaves = artifact.categories.flatMap((category) =>
    category.subcategories.flatMap((subcategory) => subcategory.leaves),
  );
  assert.equal(leaves.length, 12);
  assert.ok(leaves.every((leaf) => leaf.runStatus === "passed"));
  assert.ok(leaves.every((leaf) => leaf.rangeStatus === "passed"));
  assert.ok(leaves.every((leaf) => leaf.results.length === 6));
  assert.ok(leaves.every((leaf) => leaf.implementations.length === 2));
  assert.ok(leaves.every((leaf) => leaf.implementations.some((item) => item.language === "C")));
  assert.ok(leaves.every((leaf) => leaf.implementations.some((item) => item.language === "Range")));
  assert.ok(leaves.every((leaf) => leaf.results.some((result) => result.language === "Range")));
  assert.match(benchmarkPage, /from "\.\.\/\.\.\/public\/benchmarks\.json"/);
  assert.match(landingPage, /from "\.\.\/public\/benchmarks\.json"/);
  assert.match(styles, /@view-transition\s*{\s*navigation:\s*auto/);
  assert.match(styles, /view-transition-name:\s*range-navigation/);
  assert.match(styles, /view-transition-name:\s*range-title-morph/);
  assert.match(styles, /view-transition-group\(range-title-morph\)/);
  assert.match(landingPage, /<range-log-scale/);
  assert.match(logScaleElement, /customElements\.define\("range-log-scale"/);
  assert.match(logScaleElement, /createLogarithmicMarks/);
  assert.match(styles, /\.landingIndex\s*{[^}]*font-size:\s*20px/s);
  assert.match(styles, /\.landingHero h1\s*{[^}]*align-items:\s*flex-start[^}]*gap:\s*10px/s);
  assert.match(styles, /prefers-reduced-motion:\s*reduce/);
  assert.doesNotMatch(serverBundle, /@shikijs|engine-oniguruma|wasm-DtTceah8/);
});
