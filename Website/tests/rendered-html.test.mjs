import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", { headers: { accept: "text/html" } }),
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

test("renders the generated benchmark hierarchy", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  const normalized = html.replaceAll("<!-- -->", "");
  assert.match(normalized, /<title>Range<\/title>/i);
  assert.match(normalized, /Range Performance/);
  assert.match(normalized, /Benchmark suite/);
  assert.match(normalized, /Perlin/);
  assert.match(normalized, /Voronoi/);
  assert.match(normalized, /Value Noise/);
  assert.match(normalized, /1D Three Tap/);
  assert.match(normalized, /Fibonacci/);
  assert.match(normalized, /12 of 12 leaves run/);
  assert.match(normalized, /Range passed 12/);
  assert.match(normalized, /Not emitted 0/);
  assert.match(normalized, /Failed 0/);
  assert.match(normalized, /Initial benchmark/);
  assert.match(normalized, /Range Strings improvement/);
  assert.doesNotMatch(normalized, /Building your site|Your site is taking shape|codex-preview/i);
});

test("keeps the benchmark artifact complete and versioned", async () => {
  const [artifactText, page, schemaText] = await Promise.all([
    readFile(new URL("../public/benchmarks.json", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../../benchmark-results.schema.json", import.meta.url), "utf8"),
  ]);
  const artifact = JSON.parse(artifactText);
  const schema = JSON.parse(schemaText);

  assert.equal(artifact.schemaVersion, 1);
  assert.equal(schema.properties.schemaVersion.const, 1);
  assert.equal(artifact.summary.leafCount, 12);
  assert.equal(artifact.summary.runLeafCount, 12);
  assert.equal(artifact.summary.rangePassed, 12);

  const leaves = artifact.categories.flatMap((category) =>
    category.subcategories.flatMap((subcategory) => subcategory.leaves),
  );
  assert.equal(leaves.length, 12);
  assert.ok(leaves.every((leaf) => leaf.runStatus === "passed"));
  assert.ok(leaves.every((leaf) => leaf.rangeStatus === "passed"));
  assert.ok(leaves.every((leaf) => leaf.results.length === 6));
  assert.ok(leaves.every((leaf) => leaf.results.some((result) => result.language === "Range")));
  assert.match(page, /from "\.\.\/public\/benchmarks\.json"/);
});
