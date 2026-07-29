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
    expect(html).not.toContain("zero-drag");
    expect(html).not.toContain('pinch="');
    expect(html).toContain(">Cardinality</h2>");
    expect(html).toContain("shared source nucleus");
    expect(html).toContain('class="valueDot ');
    expect(html).not.toContain("An explicit shape steps through graph values.");
    expect(html).toContain("Play interval note");
    expect(html).toContain("Stop interval note");
    expect(html).not.toContain("Spiral track");
    expect(html).not.toContain("Codability lives in the language.");
    expect(html).toContain('href="/features/macros/codability-under-100"');
    expect(html).toContain("Latest posts");
    expect(html).toContain("Codability under 100");
    expect(html).toContain('class="postShader');
    expect(html).not.toContain("source() →");
    expect(html).not.toContain("Program melody");
    expect(html).toContain('href="/benchmarks"');
    expect(html).toContain('href="/optimizations/general/strings-go-fast"');
    expect(html).not.toContain('class="landingLinks"');
    expect(html).not.toContain("generated comparisons</small>");
    expect(html).not.toContain("Benchmark suite");
  });

  test("renders codability as a dedicated long-form article", async () => {
    const response = await render("/features/macros/codability-under-100");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("<title>Codability Under 100 · Range</title>");
    expect(html).toContain("<h1");
    expect(html).toContain("Codability Under 100");
    expect(html).toContain("01 · metaprogramming");
    expect(html).toContain("Core/Macro/Codable.range");
    expect(html).not.toContain("declaration → graph query → expansion");
    expect(html).toContain('aria-label="Code inspection"');
    expect(html).toContain('data-step="3"');
    expect(html).toContain('data-step="4"');
    expect(html).toContain('class="codabilityStage');
  });

  test("renders and filters the benchmark hierarchy", async () => {
    const response = await render("/benchmarks?category=constructs");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("Benchmark suite");
    expect(html).toContain("Raw Struct Race");
    expect(html).toContain("Eight-level nested chain");
    expect(html).toContain("4 of 15 leaves run");
    expect(html).toContain("Range passed 4");
    expect(html).not.toContain("Depth 20 and 21");
    expect(html).toContain('href="/benchmarks/history"');
  });

  test("renders dated cross-language scaling observations", async () => {
    const response = await render("/benchmarks/history");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("<title>Performance Over Time · Range</title>");
    expect(html).toContain("Performance over time");
    expect(html).toContain("Scaling observations");
    expect(html).toContain("Observed Jul 18, 2026");
    expect(html).toContain("String append operations · log scale");
    expect(html).toContain("runtime · milliseconds · log scale");
    expect(html).toContain(">100k</text>");
    expect(html).toContain(">1m</text>");
    expect(html).toContain(">5m</text>");
    expect(html).toContain(">10m</text>");
    expect(html).toContain("Language lines");
    expect(html).toContain("Range</span>");
    expect(html).toContain("Swift</span>");
    expect(html).toContain('style="--series-color:var(--range);"');
    expect(html).not.toContain("Initial");
    expect(html).not.toContain("Lowering");
    expect(html).not.toContain("Scale sweep");
    expect(html).toContain("<range-performance-history");
    expect(html).toContain("historyScalingGraph");
    expect(html).toContain("historyLanguageLine");
    expect(html).toContain("historyAccessibleTable");
    expect(html).toContain("Range: 50.1 ms at");
    expect(html).not.toContain("awaiting observation");
    expect(html).not.toContain('class="historyMatrix"');
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

  test("renders the Strings Go Fast optimization", async () => {
    const response = await render("/optimizations/general/strings-go-fast");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("<title>Strings Go Fast · Range</title>");
    expect(html).toContain("Strings Go Fast");
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
  expect(artifact.summary.leafCount).toBe(15);
  expect(artifact.summary.runLeafCount).toBe(4);
  expect(artifact.categories.length).toBeGreaterThan(0);
  expect(artifact.categories.flatMap((category: any) => category.subcategories).flatMap((subcategory: any) => subcategory.leaves)).toHaveLength(15);
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
  const scale = await readFile(
    new URL("../public/range-scale.js", import.meta.url),
    "utf8",
  );
  expect(scale).toContain("const damping = this.#isHovered ? 36 : 32;");
  expect(scale).toContain("Math.max(0, this.#focusPosition");
  expect(scale).toContain("new AudioContextConstructor()");
  expect(scale).toContain('filter.type = "bandpass";');
  expect(scale).toContain("this.#hoverDistance / 3.2");
  expect(scale).toContain("createDynamicsCompressor()");
  expect(scale).toContain("this.#clickCompressor.ratio.value = 8;");
  expect(scale).toContain("this.#clickOutput.gain.value = 1.15;");
  expect(scale).toContain("const audioReady = this.#primeAudio();");
  expect(scale).toContain("await audioReady;");
  expect(scale).toContain("audioRequestIndex !== this.#audioRequestIndex");
  expect(scale).toContain("const pointerSpeed = Math.abs(delta) / elapsed;");
  expect(scale).toContain("const transientLevel = 1 - fastMovement * 0.55;");
  expect(scale).toContain("const minimumClickInterval = 0.06 + intervalVariation;");
  expect(scale).toContain("if (audio.currentTime < this.#nextClickTime) return;");
  expect(scale).toContain("bristleGain.gain.linearRampToValueAtTime(");
  expect(scale).toContain('this.addEventListener("pointerdown", this.#handlePointerDown);');
  expect(scale).toContain("this.#clickCompressor.threshold.value = -12;");
  expect(scale).toContain("const peakGain = (0.11 + intensity * 0.035)");
  expect(scale).not.toContain("createOscillator()");
  expect(scale).toContain("const speedAttenuation = Math.min(0.32");
  expect(scale).not.toContain("index * 0.005");
  expect(scale).not.toContain('tone.type = "triangle";');
});

test("humanizes the benchmark heading with learned timing and synthesized keys", async () => {
  const [typedText, app] = await Promise.all([
    readFile(new URL("../public/range-typed-text.js", import.meta.url), "utf8"),
    readFile(new URL("../src/app.html", import.meta.url), "utf8"),
  ]);

  expect(app).toContain("range-typed-text.js?version=87");
  expect(typedText).toContain("const learnedTimingWeights");
  expect(typedText).toContain("const commonDigraphs = new Set");
  expect(typedText).toContain("const keyboardProfiles = new Map");
  expect(typedText).toContain("learnedTimingWeights.alternateHand");
  expect(typedText).toContain("learnedTimingWeights.sameFinger");
  expect(typedText).toContain("learnedTimingWeights.keyTravel");
  expect(typedText).toContain("this.#burstMomentum = this.#burstMomentum * 0.72");
  expect(typedText).toContain("playSynthesizedKey(");
  expect(typedText).toContain('transientFilter.type = "bandpass";');
  expect(typedText).toContain('body.type = "sine";');
  expect(typedText).toContain("context.createDynamicsCompressor()");
  expect(typedText).toContain('smoothingFilter.type = "lowpass";');
  expect(typedText).toContain("compressor.ratio.value = 8;");
  expect(typedText).toContain("outputGain.gain.value = 1;");
  expect(typedText).toContain("context.createStereoPanner?.()");
  expect(typedText).toContain("this.#pendingArticulation");
  expect(typedText).toContain("const nextStroke = this.#learnedStroke(");
  expect(typedText).toContain("this.#pendingArticulation = nextStroke.articulation;");
  expect(typedText).toContain("commonDigraph ? 0.84 : 1");
  expect(typedText).toContain("typingAudioUnlocked");
  expect(typedText).toContain('addEventListener("pointerdown", unlockTypingAudio');
  expect(typedText).toContain("prefers-reduced-motion: reduce");
  expect(typedText).not.toContain(
    "setTimeout(() => typeCharacter(index + 1), interval)",
  );
});

test("keeps the scale math deterministic", async () => {
  const {
    createRangeMarks,
    createScaleMarks,
    logarithmicScalePosition,
    logarithmicScalePositionAround,
  } = await import("../public/range-scale-math.js");
  const logicalMarks = createScaleMarks({ divisionBase: 3, divisionLevels: 3 });
  expect(logicalMarks).toHaveLength(28);
  expect(new Set(logicalMarks.map((mark: any) => mark.measure))).toEqual(new Set([1]));
  expect(logicalMarks[0]).toMatchObject({ position: 0, value: 0 });
  expect(logicalMarks[27]).toMatchObject({ position: 1, value: 1 });
  expect(logicalMarks[7].value).toBe(7 / 27);
  expect(logicalMarks[7].position).toBe(logarithmicScalePosition(7 / 27));
  expect(logicalMarks[1].position - logicalMarks[0].position)
    .toBeGreaterThan(logicalMarks[27].position - logicalMarks[26].position);
  const restingMarks = createRangeMarks({ focusPosition: 0 });
  expect(restingMarks.map((mark: any) => mark.position))
    .toEqual(logicalMarks.map((mark: any) => mark.position));
  const focusedMarks = createRangeMarks({ focusPosition: 0.5 });
  expect(focusedMarks[0].position).toBe(0);
  expect(focusedMarks[27].position).toBe(1);
  expect(focusedMarks[14].position - focusedMarks[13].position)
    .toBeGreaterThan(logicalMarks[14].position - logicalMarks[13].position);
  expect(focusedMarks.every((mark: any) => mark.width === 1)).toBe(true);
  expect(focusedMarks.every((mark: any, index: number) => mark.value === index / 27)).toBe(true);
  expect(focusedMarks.every((mark: any, index: number) => (
    index === 0 || mark.position >= focusedMarks[index - 1].position
  ))).toBe(true);
  expect(logarithmicScalePositionAround(0.5, { center: 0.5 })).toBe(0.5);
});

test("maps Range values into expanding rhythm windows", async () => {
  const {
    rangePlaybackOrder,
    rangePlaybackStep,
    rangeRhythmStep,
  } = await import("../src/lib/range-rhythm");
  const steps = [0, 1, 2].map(rangeRhythmStep);

  expect(steps.map((step) => step.multiplier)).toEqual([1, 2, 4]);
  expect(steps.map((step) => step.windowSeconds)).toEqual([0.6, 1.2, 2.4]);
  expect(steps.map((step) => step.noteSeconds)).toEqual([0.54, 1.08, 2.16]);
  expect(rangeRhythmStep(3)).toEqual(steps[0]);
  expect(rangePlaybackOrder).toEqual([
    "shape",
    "ownership",
    "capability",
    "shape",
    "ownership",
    "shape",
  ]);
  expect([0, 1, 2, 3, 4, 5].map((index) => rangePlaybackStep(index).conceptID))
    .toEqual([...rangePlaybackOrder]);
  expect(rangePlaybackStep(6)).toEqual(rangePlaybackStep(0));
});

test("keeps cardinality audio continuous beneath its visual rhythm", async () => {
  const nucleus = await readFile(
    new URL("../src/lib/components/RangeNucleus.svelte", import.meta.url),
    "utf8",
  );

  expect(nucleus).toContain("function startDistantVoice()");
  expect(nucleus).toContain("breath.frequency.value = 0.037;");
  expect(nucleus).toContain("voiceGain.gain.setValueAtTime(0.09, startAt);");
  expect(nucleus).toContain("direct.gain.value = 0.14;");
  expect(nucleus).toContain("function getAudioMasterInput()");
  expect(nucleus).toContain("audioMasterInput.gain.value = 1.8;");
  expect(nucleus).toContain("audioMasterCompressor.ratio.value = 12;");
  expect(nucleus).toContain("audioMasterOutput.gain.value = 1;");
  expect(nucleus).toContain("function scrollFilterFrequency(position: number)");
  expect(nucleus).toContain("const minimum = 190;");
  expect(nucleus).toContain("const maximum = 760;");
  expect(nucleus).toContain("distantVoiceFilter.frequency.setTargetAtTime(");
  expect(nucleus).toContain(
    'window.addEventListener("scroll", scheduleFilterUpdate, { passive: true });',
  );
  expect(nucleus).toContain("startDistantVoice();");
  expect(nucleus).not.toContain("playTone(");
  expect(nucleus).not.toContain('name: "C3"');
  expect(nucleus).not.toContain('name: "E3"');
  expect(nucleus).not.toContain('name: "G3"');
});

test("snaps concept color while the spiral moves at one constant speed", async () => {
  const nucleus = await readFile(
    new URL("../src/lib/components/RangeNucleus.svelte", import.meta.url),
    "utf8",
  );

  expect(nucleus).toContain("const spiralFlowDurationSeconds = 16;");
  expect(nucleus).toContain("const spiralDashCount = 30;");
  expect(nucleus).toContain("const spiralDashStartLength = 3.2;");
  expect(nucleus).toContain("const spiralDashEndLength = 12;");
  expect(nucleus).toContain(
    "(spiralDashEndLength - spiralDashStartLength) * dashProgress",
  );
  expect(nucleus).toContain("<animateMotion");
  expect(nucleus).toContain("{#if looping}");
  expect(nucleus).toContain('href="#value-spiral-motion-path"');
  expect(nucleus).toContain('values="0;0.62;0.62;0"');
  expect(nucleus).toContain('keyTimes="0;0.06;0.94;1"');
  expect(nucleus).toContain("const restingSpiralPattern");
  expect(nucleus).toContain("class=\"spiralRestingTrack\"");
  expect(nucleus).not.toContain("stroke-dashoffset");
  expect(nucleus).not.toContain("spiralTrackEnabled");
  expect(nucleus).not.toContain("toggleSpiralTrack");
  expect(nucleus).not.toContain("spiralTrackControl");
  expect(nucleus).toContain("class:playing={looping}");
  expect(nucleus).not.toContain("--rhythm-duration");
  expect(nucleus).not.toContain("rhythm-color");
  expect(nucleus).not.toContain("rhythmPulse");
  expect(nucleus).not.toContain("transition: color");
  expect(nucleus).not.toContain("fill 220ms");
  expect(nucleus).not.toContain("stroke 220ms");
});

test("uses Range-native semantic syntax roles", async () => {
  const { highlightRange } = await import("../src/lib/benchmarks");
  const highlighted = highlightRange(`macro codable(): Construct { environment in
    let fields: [@stored](
      environment.target.declaration.members.filter(all: @stored)
    )
    function encode(to encoder: Encoder): Result<Void, EncodingError> {
      let container: KeyedEncodingContainer(encoder.keyedContainer())
      #properties.map { property in
        switch container.encode(#property.identifier, forKey: property.identifier.name) {
        case .success:
          break
        }
      }
      extension #environment.target.declaration.self {}
      return .success(result: Void())
    }
  }`);

  expect(highlighted).toContain('<span class="token keyword">macro</span>');
  expect(highlighted).toContain('<span class="token macro-declaration">codable</span>');
  expect(highlighted).toContain('<span class="token type">Construct</span>');
  expect(highlighted.match(/<span class="token type">@stored<\/span>/g)).toHaveLength(2);
  expect(highlighted).toContain('<span class="token function-declaration">encode</span>');
  expect(highlighted).toContain('<span class="token method">keyedContainer</span>');
  expect(highlighted).toContain('<span class="token splice">#properties</span>');
  expect(highlighted).toContain(
    '<span class="token property">self</span>',
  );
  expect(highlighted).toContain('<span class="token splice">#property</span>');
  expect(highlighted).toContain('<span class="token keyword">switch</span>');
  expect(highlighted).toContain('<span class="token parameter">container</span>');
  expect(highlighted).toContain('<span class="token brace">{</span>');
});

test("keeps the concrete codability application example", async () => {
  const [sheet, codable, globals] = await Promise.all([
    readFile(
      new URL("../src/lib/components/CodabilitySheet.svelte", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../../RangeCompiler/Sources/Core/Macro/Codable.range", import.meta.url),
      "utf8",
    ),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
  ]);

  expect(sheet).toContain("construct User");
  expect(sheet).toContain('let name: String("George")');
  expect(sheet).toContain('state message: String("Working on Range!")');
  expect(sheet).toContain('label: "Usage"');
  expect(sheet).toContain('label: "Declaration"');
  expect(sheet.match(/label: "Usage"/g)).toHaveLength(1);
  expect(sheet.indexOf('label: "Declaration"')).toBeLessThan(
    sheet.indexOf('id: "usage"'),
  );
  expect(sheet).not.toContain('label: "Field"');
  expect(sheet).not.toContain('id: "usage-before-fields"');
  expect(sheet).not.toContain('id: "usage-after-fields"');
  expect(sheet).not.toContain('label: "Apply"');
  expect(sheet).not.toContain('label: "Fields"');
  expect(sheet).toContain("const declarationSource = sourceFrom(codableSource, macroMarker)");
  expect(sheet).toContain("source: declarationSource");
  expect(sheet).not.toContain("synthesisSource");
  expect(codable).not.toContain("macro codableEncodeBody(");
  expect(codable).not.toContain("macro codableDecodeBody(");
  expect(codable).not.toContain("macro codableEncodeProperty(");
  expect(codable).not.toContain("macro codableDecodeProperty(");
  expect(codable).not.toContain("@codableEncodeProperty");
  expect(codable).not.toContain("@codableDecodeProperty");
  expect(codable.match(/#fields\.map/g)).toHaveLength(2);
  expect(codable.match(/switch container\.encode/g)).toHaveLength(1);
  expect(codable.match(/switch container\.decode/g)).toHaveLength(1);
  expect(codable).toContain(
    "switch container.encode(#property.identifier, forKey: property.identifier.name)",
  );
  expect(codable).toContain(
    "switch container.decode(#property.type.self, forKey: property.identifier.name)",
  );
  expect(sheet).not.toContain("previewFooter");
  expect(sheet).not.toContain("declaration → graph query → expansion");
  expect(sheet).toContain('state message: String("Working on Range!")');
  expect(sheet).toContain('token: "#fields.map"');
  expect(sheet).toContain("Macro-time collection map");
  expect(sheet).toContain('title: "Declaring the macro"');
  expect(sheet).toContain(
    '"A standard macro declaration gives the macro:"',
  );
  expect(sheet).not.toContain(
    "This is the basic shape for drafting behavioral relationships.",
  );
  expect(sheet).toContain('"a name"');
  expect(sheet).toContain('"a target"');
  expect(sheet).toContain('"access to the surroundings"');
  expect(sheet).toContain('class="inspectorPoints"');
  expect(sheet).not.toContain('visual: "codable-attachment"');
  expect(sheet).not.toContain('class="teachingBlockout"');
  expect(sheet).not.toContain('class="constructBlock"');
  expect(sheet).not.toContain('class="codableAttachment"');
  expect(sheet).not.toContain('title: "Declaring a macro"');
  expect(sheet).not.toContain('title: "Declare the codable macro"');
  expect(sheet).not.toContain("a Construct-attached compiler environment");
  expect(sheet).toContain("{#if activeInspection.description}");
  expect(sheet.indexOf("{#if activeInspection.description}")).toBeLessThan(
    sheet.indexOf("{#if activeInspection.accent}"),
  );
  expect(sheet).not.toContain("{#if activeInspection.phase && activeInspection.result}");
  expect(sheet).not.toContain("<dt>Phase</dt>");
  expect(sheet).not.toContain("<dt>Produces</dt>");
  expect(sheet).toContain('title: "Querying the properties"');
  expect(sheet).toContain(
    "const fieldQuerySection = `    let fields: [@stored](",
  );
  expect(sheet).toContain(
    '"Construct members are values in the compile-time graph, so macros can perform type-level set operations over their declarations. Here `filter(all:)` selects the fields that participate in storage, using `@stored` as its criterion."',
  );
  expect(sheet).toContain("let fields: [@stored](");
  expect(sheet).toContain("members.filter(all: @stored)");
  expect(sheet).toContain('title: "Normal Range code"');
  expect(sheet).toContain('title: "Code splicing"');
  expect(sheet).toContain(
    'const extensionMarker = "extension #environment.target.declaration.self {"',
  );
  expect(sheet).toContain("token: extensionMarker");
  expect(sheet).toContain(
    '"Everything inside the expand block is normal type-checked code."',
  );
  expect(sheet).toContain('accent: "#environment.target.declaration.self"');
  expect(sheet).toContain(
    '"extension expects a nominal value, and environment is supplying it. The # prefix splices that macro-time value into the generated extension, so the result is valid Range code."',
  );
  expect(sheet).toContain(
    '<code class="inspectionAccent">{activeInspection.accent}</code>',
  );
  expect(sheet).toContain(
    '<p class="inspectionAccentDescription">',
  );
  expect(sheet).toContain(".inspectionAccent {\n    display: block;");
  expect(sheet).toContain("color: var(--range);");
  expect(sheet).toContain('macro: "macro-declaration"');
  expect(sheet).toContain('kind: "section"');
  expect(sheet).toContain("step: 1");
  expect(sheet).toContain("step: 2");
  expect(sheet).toContain("step: 3");
  expect(sheet).toContain("step: 4");
  expect(sheet).toContain("step: 5");
  expect(sheet).toContain("step: 6");
  expect(sheet).toContain("step: 7");
  expect(sheet).toContain('title: "Ordinary Range code, continued"');
  expect(sheet).toContain(
    '"An ordinary Range function named `encode` takes an `Encoder`, the coding representation for a specific target, opens that target’s keyed container, and returns `Result<Void, EncodingError>`."',
  );
  expect(sheet).not.toContain(
    "The body is small, so we can keep it here instead of making another macro.",
  );
  expect(sheet).toContain('title: "Decoding the construct"');
  expect(sheet).toContain(
    '"The matching `decode` function opens the keyed container, maps the same stored fields, returns on the first `DecodingError`, and produces `self` when every field succeeds."',
  );
  expect(sheet).toContain("highlightInspectableLines(activePane.source)");
  expect(sheet).toContain(
    'const expansionSection = sourceBlock(declarationSource, "environment.expand")',
  );
  expect(sheet).toContain("scopeToken: expansionSection");
  expect(sheet).toContain("scopeToken: macroSection");
  expect(sheet).toContain("scopeToken: extensionSection");
  expect(sheet).toContain("scopeToken: encodeFunctionScope");
  expect(sheet).toContain(
    'const encodeFunctionScope = sourceBlock(',
  );
  expect(sheet).toContain(
    'id: "encode-body",\n      token: encodeFunctionSection',
  );
  expect(sheet).toContain("scopeToken: encodeMapSection");
  expect(sheet).toContain(
    'id: "field-synthesis",\n      token: encodeMapSection',
  );
  expect(sheet).toContain('title: "Synthesizing each field"');
  expect(sheet).toContain(
    '"Here we map the stored fields directly inside `encode`."',
  );
  expect(sheet).toContain("scopeToken: decodeFunctionSection");
  expect(sheet).toContain(
    'id: "decode-body",\n      token: decodeFunctionSection',
  );
  expect(sheet).toContain("line.scopeIDs.includes(activeInspectionID)");
  expect(sheet).toContain("class:chapterContext={isChapterContext(line)}");
  expect(sheet).toContain("inspectionID: range.chapter.id");
  expect(sheet).toContain(
    'class="chapterBadge" data-step={line.step} aria-hidden="true"',
  );
  expect(sheet).toContain("onclick={() => selectCodeChapter(line.inspectionID!)}");
  expect(sheet).not.toContain("const shouldClear");
  expect(sheet).toContain("storyMode = true;");
  expect(sheet).toContain("activeInspectionID = chapter.id;");
  expect(sheet).toContain('{#if activeID === "macro" && storyMode}');
  expect(sheet).toContain('class="chapterNav"');
  expect(sheet).toContain('class="storyModeToggle"');
  expect(sheet).toContain('aria-label="Story mode"');
  expect(sheet).toContain("aria-pressed={storyMode}");
  expect(sheet).toContain("onclick={() => setStoryMode(!storyMode)}");
  expect(sheet).toContain("let storyMode = $state(true);");
  expect(sheet).toContain("activeInspectionID = null;");
  expect(sheet).toContain(
    "class:inspectionVisible={activeInspection !== undefined}",
  );
  expect(sheet).toContain("{#if activeInspection}");
  expect(sheet).toContain(".codeWorkspace.inspectionVisible");
  expect(sheet).toContain("class:chapterFiltered={hasChapterSelection}");
  expect(sheet).toContain(
    "class:chapterActive={activeInspectionID === line.inspectionID}",
  );
  expect(sheet).toContain(
    ".chapterFiltered .lineCodeContent) {\n    opacity: 0.14;",
  );
  expect(sheet).toContain(
    ".chapterFiltered .chapterContext) {\n    opacity: 0.34;\n    filter: blur(0.3px);",
  );
  expect(sheet).toContain(
    ".chapterFiltered .chapterActive .lineCodeContent) {\n    opacity: 1;",
  );
  expect(sheet).toContain('class="codeLine"');
  expect(sheet).toContain("function responsiveIndent(value: string)");
  expect(sheet).toContain('Math.floor(spaces.length / 4)');
  expect(sheet).toContain("container-type: inline-size;");
  expect(sheet).toContain("tab-size: clamp(1.15rem, 2.5cqw, 2rem);");
  expect(sheet).not.toContain("const sharedWhitespace");
  expect(sheet).not.toContain("line.slice(sharedWhitespace.length)");
  expect(sheet).toContain("cursor: pointer;");
  expect(sheet).toContain(".inspectSection) {\n    position: relative;");
  expect(sheet).toContain("text-decoration: none;");
  expect(sheet).toContain(".chapterBadge)");
  expect(sheet).toContain("position: absolute;");
  expect(sheet).toContain("top: 50%;");
  expect(sheet).toContain("transform: translateY(-50%);");
  expect(sheet).toContain("left: -2.1em;");
  expect(sheet).not.toContain("margin-right: 0.65em;");
  expect(sheet).toContain("background: var(--range);");
  expect(sheet).toContain("color: white;");
  expect(sheet).not.toContain(".inspectSection::after");
  expect(sheet).not.toContain("drop-shadow(");
  expect(sheet).not.toContain("sectionRadiance");
  expect(sheet).not.toContain("text-shadow:");
  expect(sheet).toContain("codabilityFocusProgress({");
  expect(sheet).toContain("nextCodabilityFocusState({");
  expect(sheet).toContain('stageFocused = focusState === "focused"');
  expect(sheet).toContain("previewElement.dataset.focusState = focusState");
  expect(sheet).not.toContain("transition: transform 90ms linear");
  expect(sheet).not.toContain("animateInspectorBounds");
  expect(sheet).not.toContain("inspectorBoundsAnimation");
  expect(sheet).toContain(
    ".inspectorBody {\n    width: 100%;\n    height: 100%;\n    align-self: stretch;",
  );
  expect(sheet).toContain(
    "grid-template-rows: minmax(0, 1fr) clamp(165px, 18svh, 185px);",
  );
  expect(sheet).toContain(".codeInspector {\n    position: relative;\n    grid-row: 2;");
  expect(sheet).not.toContain("Highlighted expressions carry compile-time meaning.");
  expect(sheet).toContain(
    ".codeInspector {\n      width: 100%;\n      height: 100%;\n      min-height: 0;",
  );
  expect(sheet).not.toContain("<code>{activeInspection.token}</code>");
  expect(sheet).not.toContain("Range-authored source");
  expect(sheet).not.toContain("hover · focus · tap");
  expect(sheet).toContain("height: 220svh");
  expect(sheet).toContain("position: sticky");
  expect(sheet).toContain(".codePreviewCard.stageFocused .codeViewport");
  expect(sheet).toContain("background: #fff;");
  expect(sheet).toContain("oklch(0.994 0.004 300)");
  expect(sheet).not.toContain("color: #9b2393;");
  expect(sheet).toContain(
    ".token.keyword) {\n    color: oklch(0.56 0.2 var(--range-hue));",
  );
  expect(globals).toContain("--range-hue: 252;");
  expect(globals).toContain("--range: oklch(0.65 0.2 var(--range-hue));");
  expect(sheet).toContain("color: oklch(0.63 0.19 315);");
  expect(sheet).toContain(
    ".token.splice) {\n    color: oklch(0.62 0.18 290);\n    font-weight: 600;",
  );
  expect(sheet).not.toContain("color: #3f8128;");
  expect(sheet).toContain(
    ".token.method) {\n    color: #000000d9;\n    font-weight: 400;",
  );
  expect(sheet).toContain("color: oklch(0.55 0.16 190);");
  expect(sheet).toContain(
    ".token.property) {\n    color: oklch(0.51 0.11 190);",
  );
  expect(sheet).toContain(".token.function-declaration),");
  expect(sheet).toContain(".token.macro-declaration) {");
  expect(sheet).toContain("color: #000000d9;");
  expect(sheet).toContain(".token.type),");
  expect(sheet).toContain(".token.type-declaration) {");
  expect(sheet).toContain("color: #8a8f98;");
  expect(sheet).toContain("color: #565d66;");
  expect(sheet).toContain("font-weight: 400;");
  expect(sheet).toContain("text-decoration: none;");
  expect(sheet).not.toContain("onpointerover={inspectFromEvent}");
  expect(sheet).toContain("overflow-y: hidden;");
  expect(sheet).toContain(
    "codeViewportElement.scrollTop = codeScrollDistance * stageScrollProgress;",
  );
  expect(sheet).toContain("function centerChapterInViewport(");
  expect(sheet).toContain(
    '`[data-inspection-id="${inspectionID}"]`',
  );
  expect(sheet).toContain("centerChapterInViewport(activeInspectionID);");
  expect(sheet).toContain("data-inspection-id={line.inspectionID}");
  expect(sheet).toContain(
    'if (storyMode && activeID === "macro" && activeInspectionID)',
  );
  expect(sheet).toContain(
    "const nextScrollChapterIndex = codabilityChapterIndex(",
  );
  expect(sheet).toContain(
    "nextScrollChapterIndex !== scrollChapterIndex",
  );
  expect(sheet).toContain(
    "activeInspectionID = chapters[nextScrollChapterIndex]?.id ?? null;",
  );
  expect(sheet).not.toContain("filter: blur(3px);");
  expect(sheet).not.toContain("opacity: 0.4;");
  expect(codable.match(/#fields\.map/g)).toHaveLength(2);
  expect(codable).not.toContain("#state.map");
  expect(codable).not.toContain("macro encode(");
  expect(codable).not.toContain("codableEncodeStateBody");
  expect(codable).not.toContain("codableDecodeStateBody");
  expect(codable).toContain("let fields: [@stored](");
  expect(codable).toContain("members.filter(all: @stored)");
  expect(codable).toContain(
    "function encode(to encoder: Encoder): Result<Void, EncodingError> {",
  );
  expect(codable).not.toContain("#(");
});

test("holds a symmetric plateau around the codability focus stage", async () => {
  const {
    codabilityFocusProgress,
    codabilityChapterIndex,
    codabilityPlateauScrollProgress,
    nextCodabilityFocusState,
    shouldSynchronizeCodabilityChapter,
  } = await import(
    "../src/lib/codability-focus"
  );
  const viewportHeight = 800;
  const stageHeight = 1_760;
  const centeredTop = viewportHeight / 2 - stageHeight / 2;

  expect(codabilityFocusProgress({
    stageTop: centeredTop,
    stageHeight,
    viewportHeight,
  })).toBe(1);
  expect(codabilityFocusProgress({
    stageTop: centeredTop,
    stageHeight,
    viewportHeight,
  })).toBe(1);

  for (const offset of [-240, -120, 0, 120, 240]) {
    expect(codabilityFocusProgress({
      stageTop: centeredTop + offset,
      stageHeight,
      viewportHeight,
    })).toBe(1);
  }

  const beforeCenter = codabilityFocusProgress({
    stageTop: centeredTop + 440,
    stageHeight,
    viewportHeight,
  });
  const afterCenter = codabilityFocusProgress({
    stageTop: centeredTop - 440,
    stageHeight,
    viewportHeight,
  });
  expect(beforeCenter).toBe(afterCenter);
  expect(beforeCenter).toBeGreaterThan(0);
  expect(beforeCenter).toBeLessThan(1);
  expect(codabilityFocusProgress({
    stageTop: centeredTop + 280,
    stageHeight,
    viewportHeight,
  })).toBeLessThan(1);
  expect(codabilityFocusProgress({
    stageTop: viewportHeight,
    stageHeight,
    viewportHeight,
  })).toBe(0);
  expect(codabilityPlateauScrollProgress({
    stageTop: centeredTop + 240,
    stageHeight,
    viewportHeight,
  })).toBe(0);
  expect(codabilityPlateauScrollProgress({
    stageTop: centeredTop,
    stageHeight,
    viewportHeight,
  })).toBe(0.5);
  expect(codabilityPlateauScrollProgress({
    stageTop: centeredTop - 240,
    stageHeight,
    viewportHeight,
  })).toBe(1);

  expect(codabilityChapterIndex(0, 7)).toBe(0);
  expect(codabilityChapterIndex(1 / 7 - 0.0001, 7)).toBe(0);
  expect(codabilityChapterIndex(1 / 7, 7)).toBe(1);
  expect(codabilityChapterIndex(3.5 / 7, 7)).toBe(3);
  expect(codabilityChapterIndex(6 / 7, 7)).toBe(6);
  expect(codabilityChapterIndex(1, 7)).toBe(6);
  expect(codabilityChapterIndex(0.5, 0)).toBe(-1);

  expect(shouldSynchronizeCodabilityChapter({
    manualChapterIndex: 4,
    selectionScrollY: 800,
    currentScrollY: 800,
    elapsedMilliseconds: 1_000,
  })).toBe(false);
  expect(shouldSynchronizeCodabilityChapter({
    manualChapterIndex: 4,
    selectionScrollY: 800,
    currentScrollY: 820,
    elapsedMilliseconds: 120,
  })).toBe(false);
  expect(shouldSynchronizeCodabilityChapter({
    manualChapterIndex: 4,
    selectionScrollY: 800,
    currentScrollY: 820,
    elapsedMilliseconds: 500,
  })).toBe(true);
  expect(shouldSynchronizeCodabilityChapter({
    manualChapterIndex: null,
    selectionScrollY: 800,
    currentScrollY: 800,
    elapsedMilliseconds: 0,
  })).toBe(true);

  expect(nextCodabilityFocusState({
    state: "entering",
    progress: 0.99,
    centerOffset: 20,
  })).toBe("entering");
  expect(nextCodabilityFocusState({
    state: "entering",
    progress: 1,
    centerOffset: 0,
  })).toBe("focused");
  expect(nextCodabilityFocusState({
    state: "focused",
    progress: 0.95,
    centerOffset: -300,
  })).toBe("focused");
  expect(nextCodabilityFocusState({
    state: "focused",
    progress: 0.9,
    centerOffset: -300,
  })).toBe("exiting");
  expect(nextCodabilityFocusState({
    state: "exiting",
    progress: 1,
    centerOffset: -20,
  })).toBe("focused");
  expect(nextCodabilityFocusState({
    state: "exiting",
    progress: 0.4,
    centerOffset: 200,
  })).toBe("entering");
  expect(nextCodabilityFocusState({
    state: "entering",
    progress: 0.3,
    centerOffset: 500,
    interactionFocused: true,
  })).toBe("entering");
  expect(nextCodabilityFocusState({
    state: "focused",
    progress: 0.85,
    centerOffset: -300,
    interactionFocused: true,
  })).toBe("focused");
  expect(nextCodabilityFocusState({
    state: "focused",
    progress: 0.4,
    centerOffset: -800,
    interactionFocused: true,
  })).toBe("exiting");
  expect(codabilityFocusProgress({
    stageTop: viewportHeight,
    stageHeight,
    viewportHeight,
  })).toBe(0);
});
