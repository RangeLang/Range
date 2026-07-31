import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import {
  allPosts,
  draftPosts,
  posts,
  postImagePath,
  postImageUrl,
} from "../src/lib/posts";

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

async function render(
  path = "/",
  redirect: RequestRedirect = "follow",
) {
  return fetch(`${origin}${path}`, {
    headers: { accept: "text/html" },
    redirect,
  });
}

describe("SvelteKit routes", () => {
  test("renders the Range landing page with its enhanced components", async () => {
    const response = await render();
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain(
      "<title>Range — A Graph-Backed Programming Language</title>",
    );
    expect(html).toContain(
      'name="description" content="A love letter to electrons, logic and abstraction."',
    );
    expect(html).toContain(
      'property="og:title" content="Range — A Graph-Backed Programming Language"',
    );
    expect(html).toContain(
      'name="twitter:title" content="Range — A Graph-Backed Programming Language"',
    );
    expect(html).toContain(
      'property="og:image" content="https://rangelang.org/og-v3.png"',
    );
    expect(html).not.toContain(
      "Native benchmark results for Range, C, C++, Rust, Go, and Swift",
    );
    expect(html).toContain("a love letter to electrons, logic and abstraction");
    expect(html).toContain("<range-spline-nav");
    expect(html).toContain("<range-scale");
    expect(html).not.toContain('aria-label="Homepage composition"');
    expect(html).not.toContain('data-scale-zero>0</span>');
    expect(html).not.toContain('data-scale-end><span>1</span>');
    expect(html).not.toContain("zero-drag");
    expect(html).not.toContain('pinch="');
    expect(html).not.toContain(">Cardinality</h2>");
    expect(html).not.toContain(
      "Range treats source and compiler as one graph-backed model.",
    );
    expect(html).toContain("shared source nucleus");
    expect(html).toContain('class="valueDot ');
    expect(html).not.toContain("An explicit shape steps through graph values.");
    expect(html).toContain("Play interval note");
    expect(html).not.toContain("Stop interval note");
    expect(html).not.toContain("Spiral track");
    expect(html).not.toContain("Codability lives in the language.");
    expect(html).toContain('href="/features/macros/codability-under-100"');
    expect(html).toContain('href="/features/macros/50-declarative-50-imperative"');
    expect(html).toContain('href="/features/macros/somewhere-sometime-some-here"');
    expect(html).not.toContain('href="/posts/one-source-two-lenses"');
    expect(html).not.toContain('href="/posts/intro-to-range"');
    expect(html).toContain("Latest posts");
    expect(html).not.toContain("Range Has a Dual Shape");
    expect(html).not.toContain("One Source, Two Lenses");
    expect(html).not.toContain("Intro to Range");
    expect(html).toContain("50% Declarative, 50% Imperative");
    expect(html).toContain("Somewhere, Sometime, Some-here");
    expect(html).toContain("Codability under 100");
    expect(html).toContain("latestPostShader");
    expect(html).toContain('class="latestPostCursor"');
    expect(html).toContain('data-active-post="0"');
    expect(html).not.toContain("data-range-focus-ring");
    const postPalettes = html.match(/data-post-palette="\d+"/g) ?? [];
    expect(postPalettes).toHaveLength(posts.length);
    expect(new Set(postPalettes).size).toBe(posts.length);
    expect(html).not.toContain('variant="codability"');
    expect(html).not.toContain('variant="string"');
    expect(html).not.toContain("source() →");
    expect(html).not.toContain("Program melody");
    expect(html).toContain('href="/benchmarks"');
    expect(html).not.toContain('href="/optimizations/general/strings-go-fast"');
    expect(html).not.toContain("Strings Go Fast");
    expect(html).not.toContain('class="landingLinks"');
    expect(html).not.toContain("generated comparisons</small>");
    expect(html).not.toContain("Benchmark suite");

    const latestPostsSource = await readFile(
      new URL("../src/lib/components/LatestPosts.svelte", import.meta.url),
      "utf8",
    );
    expect(latestPostsSource).toContain(
      'import { dev } from "$app/environment"',
    );
    expect(latestPostsSource).toContain(
      "const visiblePosts = dev ? allPosts : posts",
    );
    expect(latestPostsSource).toContain(
      "palettes={visiblePosts.map((post) => post.palette)}",
    );
    expect(latestPostsSource).toContain(
      "{#each visiblePosts as post, index}",
    );
    expect(latestPostsSource).toContain(
      "href={dev ? post.previewHref ?? post.href : post.href}",
    );

    const rangeTitleSource = await readFile(
      new URL("../src/lib/components/RangeTitle.svelte", import.meta.url),
      "utf8",
    );
    expect(rangeTitleSource).toContain("float width = 0.24");
    expect(rangeTitleSource).toContain("uRevealColor,\n        focus");
    expect(rangeTitleSource).toContain(
      "gl.uniform3f(uniformLocations.charcoalColor, 0, 0, 0)",
    );
    expect(rangeTitleSource).toContain(
      "gl.uniform3f(uniformLocations.revealColor, 0.24, 0.25, 0.27)",
    );
    expect(rangeTitleSource).toContain("gl.RGBA8");
    expect(rangeTitleSource).toContain("gl.UNSIGNED_BYTE");
    expect(rangeTitleSource).toContain("const reanchorDelay = 1000");
    expect(rangeTitleSource).toContain(
      "setTimeout(beginReanchor, reanchorDelay)",
    );
    expect(rangeTitleSource).not.toContain("}, 5000)");
    expect(rangeTitleSource).toContain(
      "clamp(glyph.rgb, 0.0, 1.0) * glyph.a",
    );
    expect(rangeTitleSource).not.toContain("focus * 1.08");
    expect(rangeTitleSource).not.toContain("gl.RGBA16F");
    expect(rangeTitleSource).not.toContain("gl.HALF_FLOAT");
    expect(rangeTitleSource).not.toContain("EXT_color_buffer_float");
  });

  test("does not expose a separate Posts index", async () => {
    const response = await render("/posts", "manual");

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("/");
  });

  test("retires the former Updates namespace", async () => {
    const response = await render(
      "/updates/one-program-two-lenses",
      "manual",
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("/");
  });

  test("retires the former One Program, Two Lenses slug", async () => {
    const response = await render(
      "/posts/one-program-two-lenses",
      "manual",
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("/");
  });

  test("renders codability as a dedicated long-form article", async () => {
    const response = await render("/features/macros/codability-under-100");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("<title>Codability Under 100 · Range</title>");
    expect(html).toContain(
      'property="og:image" content="https://rangelang.org/og/posts/codability-under-100.png"',
    );
    expect(html).toContain(
      'name="twitter:image" content="https://rangelang.org/og/posts/codability-under-100.png"',
    );
    expect(html).toContain("<h1");
    expect(html).toContain("Codability Under 100");
    expect(html).toContain("01 · metaprogramming");
    expect(html).toContain("Core/Macro/Codable.range");
    expect(html).toContain("#environment");
    expect(html).not.toContain("environment.expand");
    expect(html).not.toContain("declaration → graph query → expansion");
    expect(html).toContain('aria-label="Code inspection"');
    expect(html.match(/data-step="[1-7]"/g)).toHaveLength(7);
    expect(
      new Set(html.match(/data-inspection-id="[^"]+"/g) ?? []).size,
    ).toBe(7);
    expect(html).toContain('class="codabilityStage');
  });

  test("renders the declarative and imperative essay", async () => {
    const response = await render("/features/macros/50-declarative-50-imperative");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("<title>50% Declarative, 50% Imperative · Range</title>");
    expect(html).toContain(">50% Declarative, 50% Imperative</h1>");
    expect(html).toContain('aria-label="Core/Macro/Project.range"');
    expect(html).toContain('class="rangeSource language-range');
    expect(html).toContain("The declarative half");
    expect(html).toContain("The imperative half");
    expect(html).not.toContain("environment.expand");
    expect(html).toContain("The macro’s target is also its access type.");
    expect(html).toContain('aria-label="Complete Equatable synthesis"');
    expect(html).not.toContain('aria-label="Query through the Construct access type"');
    expect(html).not.toContain('aria-label="Emit an Equatable implementation"');
    expect(html).toContain("#values");
    expect(html).toContain("@property");
    expect(html).toContain("The macro performs the complete synthesis.");
    expect(html).toContain("invalidate and re-identify");
    expect(html).toContain("Runtime equality then narrows");
    expect(html).toContain("An empty");
    expect(html).toContain(">Case iterable</h2>");
    expect(html).toContain('aria-label="A modern CaseIterable derivation"');
    expect(html).toContain("@caseIterable requires cases without associated values");
    expect(html).toContain("the macro receives typed enum syntax");
  });

  test("renders the environment essay", async () => {
    const response = await render("/features/macros/somewhere-sometime-some-here");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("<title>Somewhere, Sometime, Some-here · Range</title>");
    expect(html).toContain(">Somewhere, Sometime, Some-here</h1>");
    expect(html).toContain('class="rangeSource language-range');
    expect(html).toContain(">Place</h2>");
    expect(html).not.toContain(">Some-here</h2>");
    expect(html).toContain('aria-label="Static declaration"');
    expect(html).toContain('aria-label="Compile-time projection"');
    expect(html).toContain('aria-label="Filter, then map"');
    expect(html).toContain('<span class="token property">defaults</span>');
    expect(html).toContain('<span class="token method">filter</span>');
    expect(html).toContain('<span class="token splice">#collection</span>');
    expect(html).toContain(
      "Somewhere gives the macro a place. Sometime gives it a phase. Some place gives it a boundary.",
    );
    expect(html).toContain("Not expand. Environment.");
    expect(html).not.toContain("environment.expand");
  });

  test("keeps the One Source, Two Lenses observation hidden", async () => {
    const [response, draft, previewGate] = await Promise.all([
      render("/posts/one-source-two-lenses", "manual"),
      readFile(
        new URL(
          "../src/routes/posts/one-source-two-lenses/+page.svelte",
          import.meta.url,
        ),
        "utf8",
      ),
      readFile(
        new URL(
          "../src/routes/posts/one-source-two-lenses/+page.server.ts",
          import.meta.url,
        ),
        "utf8",
      ),
    ]);
    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("/");
    expect(draft).toContain('title="One Source, Two Lenses"');
    expect(draft).toContain(
      'description="In Range, written source and intended meaning share one typed graph."',
    );
    expect(previewGate).toContain(
      'dev && url.searchParams.get("preview") === "range-draft"',
    );
    expect(draft).toContain("<h2>No language is ever done</h2>");
    expect(draft).toContain("C is more than fifty years");
    expect(draft).toContain('class="standardTerm"');
    expect(draft).toContain(
      'title="C23 is the 2024 international standard for C, formally ISO/IEC 9899:2024."',
    );
    expect(draft).toContain(">C23</abbr> in 2024, and keeps going.");
    expect(draft).not.toContain("C2y");
    expect(draft).toContain("cursor: help");
    expect(draft).toContain("It can");
    expect(draft).toContain("create one.");
    expect(draft).toContain("later languages");
    expect(draft).toContain("are judged by an expectation");
    expect(draft).toContain("A Range program has a semantic shape");
    expect(draft).toContain("The concrete shape is the");
    expect(draft).toContain("C preprocessor");
    expect(draft).toContain("Lisp macros");
    expect(draft).toContain("one program through two");
    expect(draft).toContain("Expansion is not governed by one typed");
    expect(draft).toContain("share one substrate");
    expect(draft).toContain("like a sheet of paper folded into");
    expect(draft).toContain("without erasing");
    expect(draft).toContain("its meaning.");
    expect(draft).toContain("<h2>Requirements emerge</h2>");
    expect(draft).toContain("subtractive language");
    expect(draft).toContain("thirty-two keywords to sixty");
    expect(draft).not.toContain("<h2>Intro to Range</h2>");
    expect(draft).not.toContain("<ThreeFourRhythm>");
    expect(draft).toContain("<h2>One source, two shapes</h2>");
    expect(draft).not.toContain("<h2>The semantic shape</h2>");
    expect(draft).not.toContain("<h2>The concrete shape</h2>");
    expect(draft).not.toContain("<h2>An unfinished experiment</h2>");
    expect(draft).not.toContain("Meaning first, representation later");
    expect(draft).not.toContain("construct VStack");
    expect(draft).not.toContain("<h2>Macros</h2>");
    expect(draft).not.toContain("<h2>Routes</h2>");
    expect(draft).not.toContain("<h2>The reference knot</h2>");
    expect(draft).not.toContain("graph one source of truth");
  });

  test("keeps the Intro to Range draft hidden", async () => {
    const [response, intro, previewGate, rhythm] = await Promise.all([
      render("/posts/intro-to-range", "manual"),
      readFile(
        new URL(
          "../src/routes/posts/intro-to-range/+page.svelte",
          import.meta.url,
        ),
        "utf8",
      ),
      readFile(
        new URL(
          "../src/routes/posts/intro-to-range/+page.server.ts",
          import.meta.url,
        ),
        "utf8",
      ),
      readFile(
        new URL(
          "../src/lib/components/ThreeFourRhythm.svelte",
          import.meta.url,
        ),
        "utf8",
      ),
    ]);
    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("/");
    expect(intro).toContain('title="Intro to Range"');
    expect(previewGate).toContain(
      'dev && url.searchParams.get("preview") === "range-draft"',
    );
    expect(intro).toContain("Constructs describe");
    expect(intro).toContain("enums describe alternatives");
    expect(intro).toContain("macros describe");
    expect(intro).toContain("<ThreeFourRhythm>");
    expect(intro).toContain(
      '<span class="accentTerm">value</span> form the smallest semantic unit',
    );
    expect(intro).toContain("tracked independently through the program graph");
    expect(intro).toContain("A value can contain smaller structure");
    expect(intro).toContain("identity and value move through those");
    expect(rhythm).toContain("step % 4 === 0");
    expect(rhythm).toContain("step % 3 === 0");
    expect(rhythm).toContain("step % 6 === 0");
    expect(rhythm).toContain("mod(u_time, 1.8) / 0.9");
    expect(rhythm).toContain(
      "const enabledMasterLevel = 0.85",
    );
    expect(rhythm).toContain(
      "masterLimiter.ratio.setValueAtTime(4, audioContext.currentTime)",
    );
    expect(rhythm).toContain("gain.connect(destination)");
    expect(rhythm).toContain("const peakVolume = Math.max(0.0001, volume)");
    expect(rhythm).toContain(
      "gain.gain.exponentialRampToValueAtTime(peakVolume",
    );
    expect(rhythm).toContain("clickGain.connect(destination)");
    expect(rhythm).toContain("createDynamicsCompressor");
    expect(rhythm).not.toContain("output.gain.setValueAtTime(15, now)");
    expect(rhythm).toContain("audioContext.sampleRate * 0.006");
    expect(rhythm).toContain("audioContext.createBufferSource()");
    expect(rhythm).toContain("seed = (seed * 1664525 + 1013904223)");
    expect(rhythm).toContain('clickHighpass.type = "bandpass"');
    expect(rhythm).toContain("clickHighpass.frequency.setValueAtTime(620");
    expect(rhythm).toContain("0.16 * volumeScale");
    expect(rhythm).toContain("frequency: 461.75");
    expect(rhythm).toContain("frequency: 740.75");
    expect(rhythm).toContain("volume: 0.14");
    expect(rhythm).toContain("volume: 0.08");
    expect(rhythm).toContain('oscillator.type = "sine"');
    expect(rhythm).toContain("gain.gain.linearRampToValueAtTime");
    expect(rhythm).not.toContain("metallicResonances");
    expect(rhythm).not.toContain("createDynamicsCompressor();\n\n    output");
    expect(rhythm).not.toContain(
      "gain.gain.exponentialRampToValueAtTime(partial.volume",
    );
    expect(rhythm).not.toContain("oscillator.frequency.exponentialRamp");
    expect(rhythm).toContain("createBiquadFilter");
    expect(rhythm).toContain("gain.gain.exponentialRampToValueAtTime(0.0001");
    expect(rhythm).toContain('side === "identity" ? 27.5 : 41.2034');
    expect(rhythm).toContain("function centeredRhythmVolume");
    expect(rhythm).toContain("window.innerHeight * 0.5");
    expect(rhythm).toContain(
      "const figures = [identityFigure, triangleFigure, squareFigure]",
    );
    expect(rhythm).toContain("function smoothRange");
    expect(rhythm).toContain("Math.pow(0.45, passedFigures)");
    expect(rhythm).toContain("Math.max(0.2");
    expect(rhythm).toContain("window.innerHeight * 1.1");
    expect(rhythm).toContain("return retainedLevel * tail * 0.8");
    expect(rhythm).toContain("audioContext.createConvolver()");
    expect(rhythm).toContain("audioContext.sampleRate * 0.72");
    expect(rhythm).toContain(
      "masterReverbWet.gain.setValueAtTime(0.12",
    );
    expect(rhythm).toContain(
      "masterGain.connect(masterDryGain).connect(masterLimiter)",
    );
    expect(rhythm).toContain("centeredRhythmVolume(identityFigure)");
    expect(rhythm).toContain("centeredRhythmVolume(triangleFigure)");
    expect(rhythm).toContain("centeredRhythmVolume(squareFigure)");
    expect(rhythm).not.toContain("data-line-note");
    expect(rhythm).toContain(
      "nextStepAt < now - subdivisionMilliseconds",
    );
    expect(rhythm).toContain("audioContext ??= new AudioContext()");
    expect(rhythm).toContain("startRhythm();");
    expect(rhythm).toContain("return stopRhythm");
    expect(rhythm).toContain('class="volumeButton"');
    expect(rhythm).toContain('"Mute rhythm" : "Enable rhythm sound"');
    expect(rhythm).toContain("onclick={toggleAudio}");
    expect(rhythm).not.toContain("Play 3 against 4 rhythm");
    expect(rhythm).not.toContain("Stop rhythm");
    expect(rhythm).not.toContain("one shared clock");
    expect(intro).toContain('label="Three abstraction forms"');
    expect(intro).toContain(
      "macro component(): Construct -> Void {}",
    );
    expect(intro).toContain("@component");
    expect(intro).toContain("construct Point");
    expect(intro).toContain("enum Axis");
    expect(intro).toContain("case horizontal");
    expect(intro).toContain("case vertical");
    expect(intro).toContain('label="Binding access"');
    expect(intro).toContain("let seed: Int");
    expect(intro).toContain("state count: Int");
    expect(intro).toContain("binding source: Int");
    expect(intro).toContain("derived total: Int");
    expect(intro).toContain("immutable  · owned storage");
    expect(intro).toContain("mutable    · owned storage");
    expect(intro).toContain("read/write · projected access");
    expect(intro).toContain("read-only  · computed access");
    expect(intro).toContain("{#snippet bindingIntro()}");
    expect(intro).toContain(
      "the declaration tells us whether a value is immutable,",
    );
    expect(intro).toContain(
      "coarse type-level choice—class or",
    );
    expect(intro).toContain(
      "each property’s storage and access relationship",
    );
    expect(intro).toContain("representation more composable");
    expect(intro).toContain("mutable, computed, or projected:");
    expect(intro).not.toContain('<p class="bindingIntro">');
    expect(intro.indexOf("{#snippet bindingIntro()}")).toBeLessThan(
      intro.indexOf("{#snippet bindingCode()}"),
    );
    expect(rhythm).toContain(
      'aria-label="Let, state, binding, and derived rhythm"',
    );
    expect(rhythm.indexOf('class="abstractionIntro"')).toBeLessThan(
      rhythm.indexOf('class="shapeFigure triangleFigure"'),
    );
    expect(
      rhythm.indexOf('class="shapeFigure triangleFigure"'),
    ).toBeLessThan(rhythm.indexOf('class="abstractionCode"'));
    expect(rhythm.indexOf('class="bindingCode"')).toBeLessThan(
      rhythm.indexOf('class="bindingDetail"'),
    );
    expect(rhythm.indexOf('class="bindingDetail"')).toBeLessThan(
      rhythm.indexOf('class="shapeFigure squareFigure"'),
    );
    expect(rhythm).toContain("bind:this={squareStage}");
    expect(rhythm).toContain(">Let</text>");
    expect(rhythm).toContain(">State</text>");
    expect(rhythm).toContain(">Binding</text>");
    expect(rhythm).toContain(">Derived</text>");
    expect(rhythm.match(/data-shader="path-rhythm"/g)).toHaveLength(1);
    expect(rhythm).toContain("drawTarget(squareStage, 2, time, density)");
    expect(rhythm).toContain('shaderCanvas.dataset.sharedPaths = "3"');
    expect(rhythm).toContain("segmentInfo(");
    expect(rhythm).toContain("chooseClosest(");
    expect(rhythm).toContain("gl_FragCoord.xy - u_origin");
    expect(rhythm).not.toContain("lightTail");
    expect(rhythm).not.toContain("lightMid");
    expect(rhythm).not.toContain("lightHead");
    expect(rhythm).not.toContain("<animateMotion");
    expect(rhythm).not.toContain("stroke-dasharray");
    expect(rhythm).toContain("whiteToAccentOklch(");
    expect(rhythm).toContain("lineValueX = mix(start.x, end.x, progress)");
    expect(rhythm).toContain("pathDistance = min(pathDistance, perimeter - pathDistance)");
    expect(rhythm).toContain("max(perimeter * 0.18, 1.0)");
    expect(rhythm).toContain("float capsuleAlpha = 1.0 - smoothstep(");
    expect(rhythm).toContain("float valueRadius = u_shape < 0.5");
    expect(rhythm).toContain("max(u_resolution.x * 0.24, 1.0)");
    expect(rhythm).toContain("abs(point.x - lineValueX)");
    expect(rhythm).toContain("alpha = capsuleAlpha");
    expect(rhythm).not.toContain("trailDistance");
    expect(rhythm).not.toContain("trailColor");
    expect(rhythm).not.toContain("triangle-corner-bloom");
    expect(rhythm).not.toContain("square-corner-bloom");
    expect(rhythm).not.toContain("triangleLightGradient");
    expect(rhythm).not.toContain("squareLightGradient");
    expect(rhythm).toContain("powerPreference: \"high-performance\"");
    expect(rhythm).toContain("window.devicePixelRatio || 1, 1.25");
    expect(rhythm).not.toContain("<circle");
    expect(rhythm).not.toContain("transform: scale(");
    expect(rhythm).not.toContain("identity-light-travel");
    expect(rhythm).not.toContain("Identity + Value");
    expect(rhythm).toContain('class="rhythmAudioControl"');
    expect(rhythm).toContain("position: sticky");
    expect(rhythm).toContain("top: 20px");
    expect(rhythm).toContain('class="identityExpression"');
    expect(rhythm).toContain("<span>identity</span>");
    expect(rhythm).toContain("<span>value</span>");
    expect(rhythm).toContain('aria-label="Identity is connected to value"');
    expect(rhythm.indexOf('class="identityIntro"')).toBeLessThan(
      rhythm.indexOf('class="lineFigure"'),
    );
    expect(rhythm.indexOf('class="lineFigure"')).toBeLessThan(
      rhythm.indexOf('class="identityDetail"'),
    );
    expect(rhythm).toContain(
      ".identityDetail + .abstractionIntro",
    );
    expect(rhythm).toContain("margin-top: 20px");
    expect(rhythm).not.toContain("identityConnectors");
    expect(rhythm).not.toContain("lineLabels");
    expect(rhythm).not.toContain("connectorGeometry");
    expect(rhythm).not.toContain('viewBox="0 0 100 64"');
    expect(rhythm).not.toContain('<path d="M44 20 C');
    expect(rhythm).toContain("font-size: clamp(18px, 2.4vw, 24px)");
    expect(rhythm).toContain("gap: 56px");
    expect(rhythm).toContain("padding: 40px 20px");
    expect(rhythm).not.toContain("data-line-side");
    expect(intro).toContain("smallest semantic unit");
    expect(intro).not.toContain("The name is not the identity");
    expect(intro).toContain(
      "Lowering",
    );
  });

  test("renders the hidden observation's sphere shader social card", async () => {
    const [draftPost] = draftPosts;
    const response = await render(`/og-card/posts/${draftPost.slug}`);
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain(draftPost.cardTitle);
    expect(html).toContain(draftPost.cardDescription);
    expect(html).toContain('data-shader="sphere-lines"');
    expect(html).toContain('data-top-aligned=""');
    expect(html).not.toContain('data-shader="post-noise"');
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
    expect(html).not.toContain("Compiler status");
    expect(html).not.toContain("4 of 6 tests emitted and passed");
    expect(html).not.toContain("<range-status-list");
    expect(html).not.toContain("Initial benchmark");
    expect(html).not.toContain('id="baseline-');
    expect(html).not.toContain('href="/benchmarks/history"');
  });

  test("retires the Performance Over Time page", async () => {
    const response = await render("/benchmarks/history", "manual");

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("/");
  });

  test("renders an individual benchmark", async () => {
    const response = await render("/benchmarks/integer_loop");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("While · Sequential modulo");
    expect(html).toContain("Measurements");
    expect(html).toContain("Peak memory");
    expect(html).toContain("Run procedure");
    expect(html).toContain('class="procedureBranch"');
    expect(html).toContain('class="procedureTrunk"');
    expect(html).not.toContain('class="procedureConnector"');
    expect(html).toContain('class="token keyword">state</span>');
  });

  test("redirects unknown pages to the homepage", async () => {
    for (const path of [
      "/benchmarks/not-a-benchmark",
      "/this-route-does-not-exist",
    ]) {
      const response = await render(path, "manual");
      expect(response.status).toBe(302);
      expect(response.headers.get("location")).toBe("/");
    }
  });

  test("retires the Strings Go Fast optimization", async () => {
    const response = await render(
      "/optimizations/general/strings-go-fast",
      "manual",
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("/");
  });

  test("uses each exact post card as its article social preview", async () => {
    for (const post of posts) {
      const [articleResponse, cardResponse] = await Promise.all([
        render(post.href),
        render(`/og-card/posts/${post.slug}`),
      ]);
      const [articleHtml, cardHtml] = await Promise.all([
        articleResponse.text(),
        cardResponse.text(),
      ]);

      expect(articleResponse.status).toBe(200);
      expect(articleHtml).toContain(
        `property="og:image" content="${postImageUrl(post)}"`,
      );
      expect(articleHtml).toContain(
        `name="twitter:image" content="${postImageUrl(post)}"`,
      );
      expect(cardResponse.status).toBe(200);
      expect(cardHtml).toContain('name="robots" content="noindex, nofollow"');
      expect(cardHtml).toContain(post.category);
      expect(cardHtml).toContain(post.cardTitle);
      expect(cardHtml).toContain(post.cardDescription);
      expect(cardHtml).toContain(`data-palette="${post.palette}"`);
      expect(cardHtml).not.toContain("latestPostCursor");
    }
  });
});

test("keeps every post social image generated at 1200 by 630", async () => {
  for (const post of allPosts) {
    expect(postImageUrl(post)).toBe(
      `https://rangelang.org${postImagePath(post)}`,
    );
    const bytes = await readFile(
      new URL(`../public${postImagePath(post)}`, import.meta.url),
    );
    expect(bytes.subarray(0, 8).toString("hex")).toBe("89504e470d0a1a0a");
    expect(bytes.readUInt32BE(16)).toBe(1200);
    expect(bytes.readUInt32BE(20)).toBe(630);
  }
});

test("reuses the homepage navigation as the global site header", async () => {
  const [
    siteHeader,
    home,
    essayPage,
    codability,
    benchmarks,
    benchmarkDetail,
    history,
  ] = await Promise.all([
    readFile(
      new URL("../src/lib/components/SiteHeader.svelte", import.meta.url),
      "utf8",
    ),
    readFile(new URL("../src/routes/+page.svelte", import.meta.url), "utf8"),
    readFile(
      new URL("../src/lib/components/EssayPage.svelte", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL(
        "../src/routes/features/macros/codability-under-100/+page.svelte",
        import.meta.url,
      ),
      "utf8",
    ),
    readFile(
      new URL("../src/routes/benchmarks/+page.svelte", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../src/routes/benchmarks/[id]/+page.svelte", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL(
        "../src/routes/benchmarks/history/+page.svelte",
        import.meta.url,
      ),
      "utf8",
    ),
  ]);

  expect(siteHeader).toContain('aria-label="Range home"');
  expect(siteHeader).toContain('aria-label="Primary navigation"');
  expect(siteHeader).toContain('href="/benchmarks"');
  expect(siteHeader).not.toContain('href="/posts"');
  expect(siteHeader).toContain(">GitHub</a>");
  expect(siteHeader).toContain("{#if indexed}");
  expect(siteHeader).toContain("data-scale-zero");
  expect(siteHeader).toContain(
    "grid-template-columns: minmax(0, 1fr) auto",
  );
  expect(siteHeader).toContain("align-items: baseline");
  expect(siteHeader).toContain("justify-self: end");
  expect(siteHeader).toContain("padding-inline-end: var(--page-gutter, 24px)");
  expect(siteHeader).toContain("gap: var(--page-gutter, 24px)");
  expect(siteHeader).toContain("@media (max-width: 420px)");
  expect(siteHeader).toContain("padding-inline-end: 0");
  expect(essayPage).toContain("padding-top: 0");
  expect(home).toContain("<SiteHeader indexed />");
  for (const route of [
    essayPage,
    codability,
    benchmarks,
    benchmarkDetail,
    history,
  ]) {
    expect(route).toContain("<SiteHeader />");
  }
  expect(essayPage).not.toContain("<span>{category}</span>");
  expect(codability).not.toContain("<span>Metaprogramming</span>");
});

test("renders the homepage description in the site monospace face", async () => {
  const globals = await readFile(
    new URL("../app/globals.css", import.meta.url),
    "utf8",
  );
  const descriptionRule = globals.match(
    /\.landingHero p \{([\s\S]*?)\n\}/,
  )?.[1];

  expect(descriptionRule).toBeDefined();
  expect(descriptionRule).toContain(
    "font-family: var(--font-geist-mono), monospace",
  );
  expect(descriptionRule).toContain("max-width: none");
  expect(descriptionRule).toContain("white-space: nowrap");
  expect(globals).toContain(
    "max-width: 620px;\n    white-space: normal;",
  );
});

test("jumps one post cursor between exact card-sized positions", async () => {
  const [latestPosts, globals] = await Promise.all([
    readFile(
      new URL("../src/lib/components/LatestPosts.svelte", import.meta.url),
      "utf8",
    ),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
  ]);

  expect(latestPosts).toContain(
    '<span class="latestPostCursor" aria-hidden="true"></span>',
  );
  expect(globals).toContain("--latest-post-cursor-x: calc(100% + 16px);");
  expect(globals).toContain("--latest-post-cursor-y: calc(100% + 16px);");
  expect(globals).toContain("--latest-post-cursor-x: calc(200% + 32px);");
  expect(globals).toContain("--latest-post-cursor-x: calc(300% + 48px);");
  expect(globals).toContain("--latest-post-cursor-x: calc(400% + 64px);");
  expect(globals).toContain("overflow-x: auto;\n    overflow-y: hidden;");
  expect(globals).toContain("padding-bottom: 24px;");
  expect(globals).toContain("scrollbar-color:");
  expect(globals).toContain(".latestPostStrip::-webkit-scrollbar-track");
  expect(globals).toContain(".latestPostStrip::-webkit-scrollbar-thumb");
  expect(globals).toContain("background: transparent;");
  const cursorRule = globals.match(/\.latestPostCursor \{([\s\S]*?)\n\}/)?.[1];
  expect(cursorRule).toBeDefined();
  expect(cursorRule).toContain("display: none");
  expect(cursorRule).toContain("border-radius: 0");
  expect(cursorRule).not.toContain("transition");
  expect(cursorRule).not.toContain("will-change");
  const cardRule = globals.match(/\.latestPost \{([\s\S]*?)\n\}/)?.[1];
  expect(cardRule).toBeDefined();
  expect(cardRule).toContain("border: 0");
  expect(cardRule).toContain("border-radius: 0");
  expect(globals).not.toContain(
    "--latest-post-cursor-x: calc(var(--latest-post-card-width) + 16px);",
  );
  expect(globals).toContain(".latestPost::after {");
  expect(globals).toContain("mix-blend-mode: screen");
  expect(globals).toContain(
    "inset 0 0 3px 1px oklch(1 0 0 / 0.78)",
  );
  expect(globals).toContain(
    "inset 0 0 14px 2px oklch(1 0 0 / 0.38)",
  );
  expect(globals).toContain("inset 0 0 38px oklch(1 0 0 / 0.16)");
  expect(globals).toContain(".latestPost:hover::after");
  expect(globals).not.toContain(
    "box-shadow: inset 0 0 0 3px var(--range);",
  );
});

test("runs one synchronized shader across the visible post cards", async () => {
  const [latestPosts, card, shader] = await Promise.all([
    readFile(
      new URL("../src/lib/components/LatestPosts.svelte", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../src/lib/components/PostCard.svelte", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../src/lib/components/PostNoiseShader.svelte", import.meta.url),
      "utf8",
    ),
  ]);

  expect(latestPosts.match(/<PostNoiseShader/g)).toHaveLength(1);
  expect(latestPosts).toContain(
    "palettes={visiblePosts.map((post) => post.palette)}",
  );
  expect(latestPosts).toContain("maxFps={30}");
  expect(latestPosts).toContain("densityLimit={1.25}");
  expect(latestPosts).toContain("measure={false}");
  expect(card).toContain("{#if social}");
  expect(shader).toContain("new IntersectionObserver");
  expect(shader).toContain('parent.querySelectorAll<HTMLElement>(".latestPost")');
  expect(shader).toContain("palettes[index] ?? palette");
  expect(shader).toContain('parent.dataset.shaderRendered = ""');
  expect(shader).toContain("uniform vec4 u_card_rects[8]");
  expect(shader).toContain("context.uniform4fv(cardRectsLocation, cardRects)");
  expect(shader).toContain("card.offsetLeft * density");
  expect(shader).toContain("card.offsetTop + card.offsetHeight");
  expect(shader).toContain("vec2 animationOrigin");
  expect(shader).not.toContain("paletteOrigin");
  expect(shader).not.toContain("flowDirection = vec2(" + "\n        cos");
  expect(shader).toContain("? gl_FragCoord.xy");
  expect(shader).toContain("surfacePoint / max(localResolution.y, 1.0)");
  expect(shader).toContain("vec2 grainCell = floor(surfacePoint * 0.5)");
  expect(shader).toContain("distance(cardUv, vec2(0.5))");
  expect(shader).not.toContain("u_corner_radius");
  expect(shader).not.toContain("localCornerRadius");
  expect(shader).not.toContain("roundedDistance");
  expect(shader).toContain("cardEdgeAlpha = smoothstep(0.0, 1.0");
  expect(shader).toContain("vec4(color, cardEdgeAlpha)");
  expect(shader).toContain('document.addEventListener("visibilitychange"');
  expect(shader).toContain("1000 / Math.max(1, maxFps)");
  expect(shader).toContain("lastMeasurement === -Infinity");
  expect(shader).not.toContain("now - lastMeasurement >= 125");
});

test("gives post copy a broad softly fading radial backing", async () => {
  const [globals, card] = await Promise.all([
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(
      new URL("../src/lib/components/PostCard.svelte", import.meta.url),
      "utf8",
    ),
  ]);

  expect(globals).toContain("padding: 104px 24px 24px;");
  expect(globals).toContain("ellipse 110% 150% at 50% 135%");
  expect(globals).toContain("oklch(1 0 0 / 0.11) 66%");
  expect(globals).toContain("transparent 90%");
  expect(card).toContain("padding: 240px 72px 116px;");
  expect(card).toContain("oklch(1 0 0 / 0.12) 66%");
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
  const [scale, audioEffects, app] = await Promise.all([
    readFile(new URL("../public/range-scale.js", import.meta.url), "utf8"),
    readFile(new URL("../public/range-audio-effects.js", import.meta.url), "utf8"),
    readFile(new URL("../src/app.html", import.meta.url), "utf8"),
  ]);
  expect(scale).toContain("const damping = this.#isHovered ? 36 : 32;");
  expect(scale).toContain("Math.max(0, this.#focusPosition");
  expect(scale).toContain("new AudioContextConstructor()");
  expect(scale).toContain("createWheelDetentSound");
  expect(scale).toContain(
    "this.#focusTarget,\n      this.#focusPosition,",
  );
  expect(scale).toContain("focusPosition = this.#focusPosition");
  expect(scale).toContain("this.#playRenderedDetent();");
  expect(scale).toContain("const audioReady = this.#primeAudio();");
  expect(scale).toContain("await audioReady;");
  expect(scale).toContain("audioRequestIndex !== this.#audioRequestIndex");
  expect(scale).toContain("const pointerSpeed = Math.abs(delta) / elapsed;");
  expect(scale).toContain("this.#wheelDetentSound?.play(");
  expect(scale).toContain('this.addEventListener("pointerdown", this.#handlePointerDown);');
  expect(scale).toContain("const renderedTitleShift = Number.parseFloat(");
  expect(scale).toContain("const rawEndX = measuredEndX - renderedTitleShift;");
  expect(scale).not.toContain("#titleInkShift");
  expect(scale).not.toContain("createOscillator()");
  expect(scale).not.toContain("createDynamicsCompressor()");
  expect(app).toContain(
    "range-scale.js?profile=hover-rendered-scale-audio-v19",
  );
  expect(audioEffects).toContain("export function createHashingSound(audio)");
  expect(audioEffects).toContain("export function createWheelDetentSound(audio)");
  expect(audioEffects).toContain('filter.type = "bandpass";');
  expect(audioEffects).toContain("source.loop = true;");
  expect(audioEffects).toContain("const body = Math.sin(Math.PI * 2 * 720 * time)");
  expect(audioEffects).toContain("nextDetentTime = time + 0.022;");
  expect(audioEffects).toContain('filter.type = "lowpass";');
});

test("navigates between pages without cross-page transitions", async () => {
  const [navigation, typedText, globals, app] = await Promise.all([
    readFile(
      new URL("../public/range-navigation-v2.js", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../public/range-typed-text.js", import.meta.url),
      "utf8",
    ),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../src/app.html", import.meta.url), "utf8"),
  ]);

  expect(app).toContain("range-navigation-v2.js?version=87");
  expect(navigation).toContain("currentShell.replaceChildren");
  expect(navigation).not.toContain("startViewTransition");
  expect(navigation).not.toContain("range-route-");
  expect(typedText).not.toContain("range-route-transition-finished");
  expect(globals).not.toContain("@view-transition");
  expect(globals).not.toContain("::view-transition");
  expect(globals).not.toContain("view-transition-name");
});

test("humanizes the benchmark heading with learned timing and synthesized keys", async () => {
  const [typedText, app] = await Promise.all([
    readFile(new URL("../public/range-typed-text.js", import.meta.url), "utf8"),
    readFile(new URL("../src/app.html", import.meta.url), "utf8"),
  ]);

  expect(app).toContain("range-typed-text.js?version=88");
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

test("keeps the homepage sound generator continuous beneath its visual rhythm", async () => {
  const nucleus = await readFile(
    new URL("../src/lib/components/RangeNucleus.svelte", import.meta.url),
    "utf8",
  );

  expect(nucleus).not.toContain("<h2 id=\"range-title\">Cardinality</h2>");
  expect(nucleus).not.toContain(
    "Range treats source and compiler as one graph-backed model.",
  );
  expect(nucleus.match(/class="playbackControl"/g)).toHaveLength(1);
  expect(nucleus).toContain(
    'aria-label={looping ? "Stop interval note" : "Play interval note"}',
  );
  expect(nucleus).toContain("onclick={togglePlayback}");
  expect(nucleus).toContain("background: oklch(0 0 0)");
  expect(nucleus).toContain("background: var(--range)");
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
      environment.target.Declaration.members.filter(all: @stored)
    )
    function encode<Format>(to encoder: Encoder<Format>): Result<Void, EncodingError> {
      let container: KeyedEncodingContainer<Format>(encoder.keyedContainer())
      #fields.map { property in
        switch container.encode(self.#property.identifier, forKey: #property.identifier.name) {
        case .success:
          break
        }
      }
      extension #environment.target.Declaration.identifier {}
      return .success(result: Void())
    }
  }`);

  expect(highlighted).toContain('<span class="token keyword">macro</span>');
  expect(highlighted).toContain('<span class="token macro-declaration">codable</span>');
  expect(highlighted).toContain('<span class="token type">Construct</span>');
  expect(highlighted.match(/<span class="token type">@stored<\/span>/g)).toHaveLength(2);
  expect(highlighted).toContain('<span class="token function-declaration">encode</span>');
  expect(highlighted).toContain('<span class="token method">keyedContainer</span>');
  expect(highlighted).toContain('<span class="token splice">#fields</span>');
  expect(highlighted).toContain(
    '<span class="token keyword">self</span>',
  );
  expect(highlighted).toContain('<span class="token splice">#property</span>');
  expect(highlighted).toContain('<span class="token keyword">switch</span>');
  expect(highlighted).toContain('<span class="token parameter">container</span>');
  expect(highlighted).toContain('<span class="token brace">{</span>');
  expect(highlightRange("for")).toBe('<span class="token variable">for</span>');
});

test("reuses one whitespace-safe Range source renderer", async () => {
  const [codeBlock, rangeCode, globals] = await Promise.all([
    readFile(
      new URL("../src/lib/components/CodeBlock.svelte", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../src/lib/components/RangeCode.svelte", import.meta.url),
      "utf8",
    ),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
  ]);

  expect(codeBlock).toContain('import RangeCode from "./RangeCode.svelte"');
  expect(codeBlock).toContain("<RangeCode {source} {syntax} />");
  expect(codeBlock).not.toContain("highlightRange");
  expect(rangeCode).toContain('import { escapeHtml, highlightRange } from "$lib/benchmarks"');
  expect(rangeCode).toContain('class={`rangeSource language-${syntax}`}');
  expect(globals).toContain(".rangeSource {\n  min-width: max-content;");
  expect(globals).toContain(".rangeSource code {\n  font: inherit;");
  expect(globals).toContain(".language-range .token.keyword {");
  expect(globals).not.toContain(".codeBlockBody code > span");
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
    "switch container.encode(self.#property.identifier, forKey: #property.identifier.name)",
  );
  expect(codable).toContain(
    "switch container.decode(#property.type.self, forKey: #property.identifier.name, default: #property.value)",
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
    '"Collect the stored properties from the target and filter them. `Declaration.members` exposes the target’s declared members, and `filter(all: @stored)` retains both `let` and `state` properties through their shared storage capability."',
  );
  expect(sheet).toContain("let fields: [@stored](");
  expect(sheet).toContain("members.filter(all: @stored)");
  expect(sheet).toContain('title: "Normal Range code"');
  expect(sheet).toContain('title: "Code splicing"');
  expect(sheet).toContain(
    'const extensionMarker = "extension #environment.target.Declaration.identifier {"',
  );
  expect(sheet).toContain("token: extensionMarker");
  expect(sheet).toContain(
    '"Everything inside the #environment block is normal type-checked code."',
  );
  expect(sheet).toContain('accent: "#environment.target.Declaration.identifier"');
  expect(sheet).toContain(
    '"`Declaration.identifier` is the target construct’s canonical declared name. The # prefix splices that compile-time identifier into the generated extension."',
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
    '"The generated `encode<Format>` function keeps the encoder and keyed container on the same coding format, then returns `Result<Void, EncodingError>`."',
  );
  expect(sheet).not.toContain(
    "The body is small, so we can keep it here instead of making another macro.",
  );
  expect(sheet).toContain('title: "Decoding the construct"');
  expect(sheet).toContain(
    '"The matching `decode<Format>` function decodes each stored property by its declared type and key, preserves `#property.value` as the default, assigns successful values to `self`, and returns the completed construct."',
  );
  expect(sheet).toContain("highlightInspectableLines(activePane.source)");
  expect(sheet).toContain(
    "`Codability chapter ${chapter.step} no longer matches Codable.range`",
  );
  expect(sheet).toContain(
    'const expansionSection = sourceBlock(declarationSource, "#environment")',
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
    '"For every stored property, the macro splices `self.#property.identifier` as the value and its declared identifier name as the coding key."',
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
    ".chapterFiltered .lineCodeContent) {\n    opacity: 0.24;",
  );
  expect(sheet).toContain(
    ".chapterFiltered .chapterContext) {\n    opacity: 0.48;\n    filter: blur(0);",
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
  expect(sheet).toContain(
    ".chapterStart.inspectSection) {\n    position: static;",
  );
  expect(sheet).toContain(
    ".codeLine) {\n    position: relative;\n    display: block;",
  );
  expect(sheet).toContain("text-decoration: none;");
  expect(sheet).toContain(".chapterBadge)");
  expect(sheet).toContain("position: absolute;");
  expect(sheet).toContain("top: 50%;");
  expect(sheet).toContain("transform: translateY(-50%);");
  expect(sheet).toContain("left: -2.25em;");
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
  expect(sheet).toContain('class="rangeSource language-range"');
  expect(globals).toContain(
    ".language-range .token.keyword {\n  color: oklch(0.56 0.2 var(--range-hue));",
  );
  expect(globals).toContain("--range-hue: 252;");
  expect(globals).toContain("--range: oklch(0.65 0.2 var(--range-hue));");
  expect(globals).toContain("color: oklch(0.63 0.19 315);");
  expect(globals).toContain(
    ".language-range .token.splice {\n  color: oklch(0.62 0.18 290);\n  font-weight: 600;",
  );
  expect(sheet).not.toContain("color: #3f8128;");
  expect(globals).toContain(
    ".language-range .token.method {\n  color: #000000d9;\n  font-weight: 400;",
  );
  expect(globals).toContain("color: oklch(0.55 0.16 190);");
  expect(globals).toContain(
    ".language-range .token.property {\n  color: oklch(0.51 0.11 190);",
  );
  expect(globals).toContain(".language-range .token.function-declaration,");
  expect(globals).toContain(".language-range .token.macro-declaration {");
  expect(globals).toContain("color: #000000d9;");
  expect(globals).toContain(".language-range .token.type,");
  expect(globals).toContain(".language-range .token.type-declaration {");
  expect(globals).toContain("color: #8a8f98;");
  expect(globals).toContain("color: #565d66;");
  expect(globals).toContain("font-weight: 400;");
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
    "function encode<Format>(to encoder: Encoder<Format>): Result<Void, EncodingError> {",
  );
  expect(codable).not.toContain("#(");
});

test("switches story chapters without fading code lines", async () => {
  const sheet = await readFile(
    new URL("../src/lib/components/CodabilitySheet.svelte", import.meta.url),
    "utf8",
  );

  expect(sheet).toContain(
    ".chapterFiltered .chapterActive .lineCodeContent) {\n    opacity: 1;",
  );
  expect(sheet).not.toContain("opacity 180ms ease-out");
  expect(sheet).not.toContain("filter 180ms ease-out");
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
