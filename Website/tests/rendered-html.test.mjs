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
  assert.match(html, /<h1[^>]*>.*>1<\/span><\/span>.*>Range<\/span><\/h1>/);
  assert.match(html, /landingWordmark[^>]*>.*>0<\/span>.*>Range<\/span>/);
  assert.match(
    html,
    /<range-scale(?=[^>]*endpoint-gap="8")(?=[^>]*division-base="3")(?=[^>]*division-levels="3")(?=[^>]*pinch="0.27")(?=[^>]*pinch-core="10")(?=[^>]*pinch-falloff="0.16")(?=[^>]*pinch-inner-edge="0.68")(?=[^>]*pinch-strength="0.9")(?=[^>]*measure-minimum="0.35")(?=[^>]*marker-capture-division-weight="0.48")(?=[^>]*marker-capture-falloff="0.14")(?=[^>]*marker-capture-strength="0.9")(?=[^>]*stroke-minimum="0.25")(?=[^>]*tone-falloff="0.12")(?=[^>]*tone-intensity="0.82")[^>]*>/,
  );
  assert.match(html, /<script[^>]*type="module"[^>]*src="\/range-scale\.js(?:\?[^\"]*)?"/);
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
  assert.match(normalized, /class="rangeTitleWord">Range<\/span>/);
  assert.match(normalized, /<range-typed-text(?=[^>]*text="Performance")(?=[^>]*delay="600")(?=[^>]*interval="45")[^>]*>/);
  assert.match(normalized, /src="\/range-typed-text\.js"/);
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

test("merges linear scale and pinch marks deterministically", async () => {
  const mathUrl = new URL("../public/range-scale-math.js", import.meta.url);
  mathUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const {
    createRangeMarks,
    createScaleMarks,
    captureMarkerPosition,
    measureWithFalloff,
    mergeMarks,
    pinchScaleValue,
    sphericalPinchInfluence,
  } = await import(mathUrl.href);

  assert.deepEqual(
    createScaleMarks({ divisionBase: 3, divisionLevels: 1 }).map(({ position }) => position),
    [0, 1 / 3, 2 / 3, 1],
  );
  const scaleHierarchy = createScaleMarks({ divisionBase: 3, divisionLevels: 3 });
  assert.equal(scaleHierarchy.length, 28);
  assert.equal(scaleHierarchy.filter(({ tier }) => tier === "major").length, 4);
  assert.equal(scaleHierarchy.filter(({ tier }) => tier === "division").length, 6);
  assert.equal(scaleHierarchy.filter(({ tier }) => tier === "single").length, 18);
  assert.deepEqual(
    [scaleHierarchy[0].measure, scaleHierarchy[3].measure, scaleHierarchy[1].measure],
    [5, 3, 1],
  );
  assert.equal(measureWithFalloff(0.27), 0.35);
  assert.equal(measureWithFalloff(0), 1);
  assert.equal(measureWithFalloff(1), 1);
  assert.ok(Math.abs(measureWithFalloff(0.258) - measureWithFalloff(0.282)) < 1e-12);
  assert.ok(measureWithFalloff(0.258) < measureWithFalloff(0.2436));
  assert.equal(pinchScaleValue(0), 0);
  assert.equal(pinchScaleValue(0.27), 0.27);
  assert.equal(pinchScaleValue(1), 1);
  assert.ok(pinchScaleValue(0.22, { falloff: 0.16, strength: 0.9 }) < 0.22);
  assert.ok(pinchScaleValue(0.32, { falloff: 0.16, strength: 0.9 }) > 0.32);
  assert.equal(captureMarkerPosition(0.4, { anchor: 0.4, center: 0.27, falloff: 0.1 }), 0.4);
  assert.equal(captureMarkerPosition(0.27, { anchor: 0.27, center: 0.27 }), 0.27);
  assert.ok(captureMarkerPosition(0.34, { anchor: 0.31, center: 0.27 }) < 0.34);
  assert.equal(captureMarkerPosition(0.34, { anchor: 0.31, center: 0.27, weight: 0 }), 0.34);
  assert.equal(sphericalPinchInfluence(0.27, { coreRadius: 0.04 }), 1);
  assert.equal(sphericalPinchInfluence(0.31, { coreRadius: 0.04 }), 0.68);
  assert.ok(sphericalPinchInfluence(0.29, { coreRadius: 0.04 }) > 0.68);
  assert.ok(sphericalPinchInfluence(0.35, { coreRadius: 0.04 }) < 0.68);

  const marks = createRangeMarks({
    divisionBase: 3,
    divisionLevels: 3,
    pinch: 0.27,
    pinchCoreRadius: 5 / 136,
    pinchFalloff: 0.16,
    pinchInnerEdge: 0.68,
    pinchStrength: 0.9,
    measureMinimum: 0.35,
    markerCaptureDivisionWeight: 0.48,
    markerCaptureFalloff: 0.14,
    markerCaptureStrength: 0.9,
    strokeMinimum: 0.25,
    toneFalloff: 0.12,
  });
  assert.ok(marks.every((mark) => mark.position >= 0 && mark.position <= 1));
  assert.ok(marks.every((mark) => mark.measure >= 0.35 - 1e-12));
  assert.ok(marks.every((mark) => mark.stroke >= 0.25 - 1e-12 && mark.stroke <= 1));
  assert.ok(marks.every((mark) => mark.tone >= 0 && mark.tone <= 1));
  assert.ok(marks.every((mark) => mark.opacity >= 0 && mark.opacity <= 1));
  assert.ok(marks.every((mark, index) => index === 0 || mark.position > marks[index - 1].position));
  assert.equal(marks.length, 28);
  assert.ok(marks[7].position < 7 / 27);
  assert.ok(marks[8].position > 8 / 27);
  assert.ok(marks[8].position - marks[7].position > 0.065);
  assert.ok(marks[7].measure < 1);
  assert.ok(marks[7].stroke < 1);
  assert.ok(marks[7].tone > 0.9);
  assert.ok(marks[7].opacity < 0.4);
  assert.ok(marks[8].opacity > marks[7].opacity);
  assert.equal(marks[0].measure, 5);
  assert.equal(marks[21].measure, 3);
  assert.equal(marks[22].measure, 1);
  assert.equal(marks[27].measure, 5);
  for (const center of [0.001, 0.01, 0.1, 0.27, 0.5, 0.9, 0.99, 0.999]) {
    for (let index = 1; index <= 1000; index += 1) {
      assert.ok(
        pinchScaleValue(index / 1000, { center }) >
        pinchScaleValue((index - 1) / 1000, { center }),
      );
    }
  }

  const merged = mergeMarks([
    [{ isRadix: false, position: 0.27, source: "scale", weight: 1 }],
    [{ isRadix: true, position: 0.27000000001, source: "pinch", weight: 3 }],
  ]);
  const expectedPosition = (0.27 + 0.27000000001 * 3) / 4;
  assert.equal(merged.length, 1);
  assert.ok(Math.abs(merged[0].position - expectedPosition) < 1e-15);
  assert.equal(merged[0].measure, 1.6);
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
    rangeScaleElement,
  ] = await Promise.all([
    readFile(new URL("../public/benchmarks.json", import.meta.url), "utf8"),
    readFile(new URL("../app/benchmarks/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../../benchmark-results.schema.json", import.meta.url), "utf8"),
    readFile(new URL("../dist/server/index.js", import.meta.url), "utf8"),
    readFile(new URL("../public/range-scale.js", import.meta.url), "utf8"),
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
  assert.match(styles, /\.landingHero \.rangeTitleWord\s*{[^}]*transform:\s*translateX\(-3px\)/s);
  assert.match(styles, /\.landingSequence\s*{[^}]*--range-title-leading:\s*calc\(var\(--range-index-column\) \+ var\(--range-index-gap\) - 3px\)/s);
  assert.match(styles, /\.landingHero p\s*{[^}]*margin:\s*40px 0 0 var\(--range-title-leading\)/s);
  assert.match(styles, /\.landingActions\s*{[^}]*margin:\s*32px 0 0 var\(--range-title-leading\)/s);
  assert.match(styles, /view-transition-group\(range-title-morph\)/);
  assert.match(styles, /view-transition-old\(range-title-morph\)\s*{[^}]*opacity:\s*1[^}]*animation:\s*none/s);
  assert.match(styles, /view-transition-new\(range-title-morph\)\s*{[^}]*opacity:\s*0[^}]*animation:\s*none/s);
  assert.match(styles, /range-typed-text\[data-typing\]::after/);
  assert.doesNotMatch(styles, /range-title-(?:out|in)/);
  assert.match(landingPage, /<range-scale/);
  assert.match(rangeScaleElement, /customElements\.define\("range-scale"/);
  assert.match(rangeScaleElement, /createRangeMarks/);
  assert.match(rangeScaleElement, /width:\s*calc\(1px \* var\(--measure\)\)/);
  assert.match(rangeScaleElement, /height:\s*calc\(1px \* var\(--stroke\)\)/);
  assert.match(rangeScaleElement, /white var\(--lighten\)/);
  assert.match(rangeScaleElement, /opacity:\s*var\(--opacity\)/);
  assert.match(rangeScaleElement, /mark\.tone \* config\.toneIntensity \* 100/);
  assert.match(rangeScaleElement, /pointerenter/);
  assert.match(rangeScaleElement, /pointermove/);
  assert.match(rangeScaleElement, /pointerleave/);
  assert.match(rangeScaleElement, /requestAnimationFrame/);
  assert.match(rangeScaleElement, /spring\s*=\s*this\.#isPointerActive\s*\?\s*240\s*:\s*180/);
  assert.match(rangeScaleElement, /damping\s*=\s*this\.#isPointerActive\s*\?\s*28\s*:\s*14/);
  assert.match(styles, /\.landingIndex\s*{[^}]*font-size:\s*20px/s);
  assert.match(styles, /\.landingSequence\s*{[^}]*--range-index-column:\s*15px[^}]*--range-index-gap:\s*10px/s);
  assert.match(styles, /\.landingWordmark\s*{[^}]*display:\s*inline-grid[^}]*grid-template-columns:\s*var\(--range-index-column\) auto[^}]*align-items:\s*center[^}]*column-gap:\s*var\(--range-index-gap\)/s);
  assert.match(styles, /\.landingIndex\s*{[^}]*width:\s*var\(--range-index-column\)/s);
  assert.match(styles, /\.landingIndex\s*{[^}]*text-align:\s*center/s);
  assert.match(styles, /\.landingNav \[data-scale-zero\]\s*{[^}]*font-size:\s*14\.6px/s);
  assert.match(styles, /\.landingHero h1\s*{[^}]*display:\s*grid[^}]*grid-template-columns:\s*var\(--range-index-column\) auto[^}]*align-items:\s*flex-start[^}]*column-gap:\s*var\(--range-index-gap\)/s);
  assert.match(styles, /\.landingHero \[data-scale-end\]\s*{[^}]*position:\s*relative[^}]*font-size:\s*25\.4px[^}]*overflow:\s*visible/s);
  assert.match(styles, /\.landingHero \[data-scale-end\] > span\s*{[^}]*left:\s*50%[^}]*transform:\s*translateX\(-50%\)/s);
  assert.match(styles, /prefers-reduced-motion:\s*reduce/);
  assert.doesNotMatch(serverBundle, /@shikijs|engine-oniguruma|wasm-DtTceah8/);
});
