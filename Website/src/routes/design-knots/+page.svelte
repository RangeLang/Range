<script lang="ts">
  import { highlightRange } from "$lib/benchmarks";
  import { music, type SoundProfile } from "$lib/audio/music";
  import KnotGlyph from "$lib/components/KnotGlyph.svelte";
  import ShapeMorph from "$lib/components/ShapeMorph.svelte";
  import {
    codeViewportLines,
    designKnots,
    falseCircle,
    macroContrast,
    viewportStart,
  } from "$lib/design-knots";

  /** 1 while the false circle is showing itself as a dot, 0 once opened. */
  let falseCircleClosed = $state(1);

  const highlighted = designKnots.map((knot) =>
    knot.sources.map((source) => highlightRange(source.source.trimEnd())),
  );
  const macroContrastSource = highlightRange(macroContrast);

  /*
   * The library's pulse: dam · wait · dam · wait · half, on repeat. Each knot
   * carries it as its own layer, so the conductor only voices the one you are
   * actually reading and the rest sit at zero presence.
   */
  const knotPulse = (id: string): SoundProfile => ({
    name: `knot-${id}`,
    bar: 5,
    hits: [
      { beat: 0, voice: "dam", level: 0.44 },
      { beat: 2, voice: "dam", level: 0.44 },
      { beat: 4, voice: "dam", level: 0.2, light: true },
    ],
  });
</script>

<svelte:head>
  <title>Design Knots · Range</title>
  <meta
    name="description"
    content="Places where Range's notation states one decision more than once, and what each one collapses into."
  />
  <meta name="robots" content="noindex, nofollow, noai" />
</svelte:head>

<range-design-knots-page>
  <main class="knotsPage">
    <header class="pageHeader">
      <p class="eyebrow">Language design</p>
      <h1>Design Knots</h1>
      <p class="lede">
        A design knot is a place where the notation states one decision more
        than once. The number of restatements is the knot's shape. Collapsing
        it is not deletion — it is finding the single spelling that all the
        others were approximating.
      </p>
    </header>

    <section class="shapeModel" aria-labelledby="shape-model-title">
      <h2 id="shape-model-title">Counting corners</h2>

      <div class="shapeStage">
        <ShapeMorph />
      </div>

      <p class="shapeNote">
        Three edge tangents press a circle inward until their shared pressure
        resolves as an equilateral triangle. A knot collapses when its
        restatements converge on one decision.
      </p>
    </section>

    <section class="catalogue" aria-labelledby="catalogue-title">
      <h2 id="catalogue-title">The library</h2>

      <ol class="knotList">
        {#each designKnots as knot, index}
          <li class="knot" use:music={{ profile: knotPulse(knot.id), background: 0.5 }}>
            <p class="knotMeta">
              <span class="knotIndex">{String(index + 1).padStart(2, "0")}</span>
              <span class="knotShapeName">{knot.shape}</span>
            </p>

            <h3>{knot.title}</h3>

            <div class="knotSources">
              {#each knot.sources as source, sourceIndex}
                <figure class="codeViewport">
                  <div
                    class="codeWindow"
                    style={`--start-line: ${viewportStart(source.focusLine)}; --code-lines: ${codeViewportLines}`}
                  >
                    <pre
                      class="rangeSource language-range"><code>{@html highlighted[index][sourceIndex]}</code></pre>
                  </div>
                  <figcaption>{source.path}</figcaption>
                </figure>
              {/each}
            </div>

            <p class="knotSays">
              The notation says <em>{knot.says}</em>
              {#if knot.corners.length > 0}
                {knot.corners.length} times.
              {:else}
                once.
              {/if}
            </p>

            {#if knot.corners.length > 0}
              <ul class="knotCorners">
                {#each knot.corners as corner}
                  <li>
                    <code>{corner.spelling}</code>
                    <span>{corner.role}</span>
                  </li>
                {/each}
              </ul>
            {/if}

            <p class="knotQuestion">{knot.question}</p>

          </li>
        {/each}
      </ol>
    </section>

    <section class="falseCircle" aria-labelledby="false-circle-title">
      <h2 id="false-circle-title">The false circle</h2>

      <div class="falseCircleLede">
        <div class="falseCircleFigure">
          <KnotGlyph
            corners={falseCircle.sites.length}
            progress={falseCircleClosed}
            size={130}
          />
          <button
            type="button"
            class="collapseToggle"
            aria-pressed={falseCircleClosed === 0}
            onclick={() => (falseCircleClosed = falseCircleClosed === 0 ? 1 : 0)}
          >
            {falseCircleClosed === 0 ? "Close" : "Open"}
          </button>
        </div>

        <div class="falseCircleText">
          <p>
            Every knot above gathers its corners in one line, where they can be
            counted. The harder case spends one spelling across many places and
            lets position pick the meaning. From any single site it looks like
            a dot — one word, said once. It is only a polygon when the whole
            file is held at once.
          </p>
          <p>
            C's <code>{falseCircle.spelling}</code> has three of these. They sit
            far apart in an ordinary codebase, which is usually offered as the
            reason it costs nothing. It is the reason it costs something: the
            association has nowhere to live except in the reader, and the reader
            has to carry all three to understand any one of them.
          </p>
        </div>
      </div>

      <ol class="falseCircleSites">
        {#each falseCircle.sites as site, siteIndex}
          <li>
            <p class="sitePosition">
              <span class="siteIndex">{siteIndex + 1}</span>
              {site.position}
            </p>
            <pre class="knotNotation">{site.notation}</pre>
            <p class="siteMeaning">{site.meaning}</p>
          </li>
        {/each}
      </ol>

      <div class="macroContrast">
        <h3>Why a macro is not this</h3>
        <p>
          A macro has the same silhouette: one name, many expansions, applied in
          many places. The difference is not restraint, it is that a macro
          carries the full effect of its execution. Its target position is
          declared rather than inferred, and what it becomes at a site is
          derivable from the macro itself instead of recalled from the standard.
        </p>
        <pre
          class="knotNotation rangeSource language-range"><code>{@html macroContrastSource}</code></pre>
        <p class="macroNote">
          <code>Member</code>, <code>Construct</code>, and
          <code>Function</code> are the positions. Range writes down the thing
          <code>static</code> leaves to the reader — so one name still means
          several things, and none of them has to be remembered.
        </p>
      </div>
    </section>

    <footer class="pageFooter">
      <p>
        Entries live in <code>Website/src/lib/design-knots.ts</code>. A knot
        earns a place when the repetition is visible in real Range source, not
        when it is merely arguable.
      </p>
    </footer>
  </main>
</range-design-knots-page>

<style>
  .knotsPage {
    max-width: 980px;
    margin: 0 auto;
    padding: 72px var(--page-gutter) 120px;
    color: var(--ink);
  }

  .pageHeader {
    max-width: 660px;
    margin-bottom: 76px;
  }

  .eyebrow {
    margin: 0 0 14px;
    color: var(--range);
    font-family: var(--font-geist-mono), monospace;
    font-size: 12px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
  }

  h1 {
    margin: 0 0 22px;
    font-size: clamp(38px, 6vw, 62px);
    font-weight: 560;
    letter-spacing: -0.045em;
    line-height: 1.02;
  }

  .lede {
    margin: 0;
    color: var(--muted);
    font-size: clamp(17px, 2.2vw, 20px);
    line-height: 1.62;
  }

  h2 {
    margin: 0 0 30px;
    font-size: 13px;
    font-weight: 500;
    font-family: var(--font-geist-mono), monospace;
    letter-spacing: 0.09em;
    text-transform: uppercase;
    color: var(--muted);
  }

  .shapeModel {
    padding: 46px 0;
    border-top: 1px solid var(--line);
    border-bottom: 1px solid var(--line);
  }

  .shapeStage {
    display: flex;
    justify-content: center;
    padding: 24px 0;
  }

  .shapeModel h2 {
    text-align: center;
  }

  .shapeNote {
    max-width: 560px;
    margin: 30px auto 0;
    color: var(--muted);
    font-size: 15px;
    line-height: 1.6;
    text-align: center;
  }

  .falseCircle {
    padding: 52px 0 8px;
    border-bottom: 1px solid var(--line);
  }

  .falseCircleLede {
    display: grid;
    grid-template-columns: 200px minmax(0, 1fr);
    align-items: start;
    gap: 44px;
  }

  .falseCircleFigure {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 14px;
  }

  .falseCircleText p {
    margin: 0 0 16px;
    font-size: 16px;
    line-height: 1.66;
  }

  .falseCircleText p:last-child {
    margin-bottom: 0;
  }

  .falseCircleText code,
  .macroNote code {
    padding: 1px 5px;
    border-radius: 4px;
    background: color-mix(in oklch, var(--range), transparent 92%);
    font-family: var(--font-geist-mono), monospace;
    font-size: 13px;
  }

  .falseCircleSites {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 22px;
    margin: 40px 0 0;
    padding: 0;
    list-style: none;
  }

  .falseCircleSites li {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .sitePosition {
    display: flex;
    align-items: baseline;
    gap: 9px;
    margin: 0;
    font-family: var(--font-geist-mono), monospace;
    font-size: 12px;
    letter-spacing: 0.05em;
  }

  .siteIndex {
    color: var(--range);
  }

  .falseCircleSites .knotNotation {
    flex: 1 0 auto;
    margin: 0;
    font-size: 12.5px;
  }

  .siteMeaning {
    margin: 0;
    color: var(--muted);
    font-size: 14px;
    line-height: 1.55;
  }

  .macroContrast {
    margin-top: 46px;
    padding: 30px 0 46px;
    border-top: 1px solid var(--line);
  }

  .macroContrast h3 {
    margin: 0 0 12px;
    font-size: 20px;
    font-weight: 540;
    letter-spacing: -0.028em;
  }

  .macroContrast p {
    max-width: 680px;
    margin: 0 0 20px;
    font-size: 16px;
    line-height: 1.66;
  }

  .macroNote {
    color: var(--muted);
    font-size: 15px !important;
  }

  .catalogue {
    margin-top: 72px;
  }

  .knotList {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .knot {
    padding: 40px 0;
    border-bottom: 1px solid var(--line);
  }

  .knotMeta {
    display: flex;
    align-items: baseline;
    gap: 14px;
    margin: 0 0 12px;
    font-family: var(--font-geist-mono), monospace;
    font-size: 12px;
    letter-spacing: 0.06em;
  }

  .knotShapeName {
    color: var(--ink);
  }

  .collapseToggle {
    margin-left: auto;
    padding: 5px 12px;
    border: 1px solid var(--line);
    border-radius: 999px;
    background: transparent;
    color: var(--muted);
    font-family: var(--font-geist-mono), monospace;
    font-size: 11px;
    letter-spacing: 0.05em;
    cursor: pointer;
    transition: border-color 200ms ease, color 200ms ease;
  }

  .collapseToggle:hover,
  .collapseToggle[aria-pressed="true"] {
    border-color: color-mix(in oklch, var(--range), transparent 60%);
    color: var(--range);
  }

  .knotIndex {
    color: var(--range);
  }

  .knot h3 {
    margin: 0 0 8px;
    font-size: clamp(21px, 2.8vw, 27px);
    font-weight: 540;
    letter-spacing: -0.032em;
  }

  .knotSources {
    display: flex;
    flex-direction: column;
    gap: 26px;
    margin: 22px 0 20px;
  }

  .codeViewport {
    margin: 0;
  }

  /*
   * A window onto the real file rather than a trimmed excerpt: the source is
   * one independent layer, offset to the line the knot lives on, and the
   * window dissolves at the bottom and the right instead of ending in a rule.
   */
  .codeWindow {
    --code-line: 22px;
    position: relative;
    height: calc(var(--code-line) * var(--code-lines, 12));
    overflow: hidden;
    mask-image:
      linear-gradient(to bottom, #000 58%, transparent 100%),
      linear-gradient(to right, #000 86%, transparent 100%);
    mask-composite: intersect;
    -webkit-mask-image:
      linear-gradient(to bottom, #000 58%, transparent 100%),
      linear-gradient(to right, #000 86%, transparent 100%);
    -webkit-mask-composite: source-in;
  }

  .codeWindow :global(.rangeSource) {
    position: absolute;
    top: calc(var(--start-line) * var(--code-line) * -1);
    left: 0;
    margin: 0;
    font-family: var(--font-geist-mono), monospace;
    font-size: 13px;
    line-height: var(--code-line);
    white-space: pre;
    tab-size: 4;
  }

  .codeViewport figcaption {
    margin-top: 10px;
    color: var(--muted);
    font-family: var(--font-geist-mono), monospace;
    font-size: 11.5px;
    word-break: break-all;
  }

  .knotNotation {
    margin: 0 0 18px;
    padding: 20px 22px;
    overflow-x: auto;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: color-mix(in oklch, var(--ink), transparent 97%);
    color: var(--ink);
    font-family: var(--font-geist-mono), monospace;
    font-size: 13px;
    line-height: 1.75;
    white-space: pre;
  }

  .knotSays {
    max-width: 760px;
    margin: 0 0 20px;
    color: var(--muted);
    font-size: 14px;
  }

  .knotSays em {
    color: var(--ink);
    font-family: var(--font-geist-mono), monospace;
    font-style: normal;
  }

  .knotCorners {
    max-width: 820px;
    display: flex;
    flex-direction: column;
    gap: 9px;
    margin: 0 0 24px;
    padding: 0;
    list-style: none;
  }

  .knotCorners li {
    display: grid;
    grid-template-columns: minmax(120px, max-content) minmax(0, 1fr);
    gap: 16px;
    padding-left: 14px;
    border-left: 2px solid color-mix(in oklch, var(--range), transparent 78%);
  }

  .knotCorners code {
    color: var(--ink);
    font-family: var(--font-geist-mono), monospace;
    font-size: 13px;
  }

  .knotCorners span {
    color: var(--muted);
    font-size: 14px;
    line-height: 1.5;
  }

  .knotQuestion {
    max-width: 760px;
    margin: 0;
    font-size: 16px;
    line-height: 1.66;
  }

  .pageFooter {
    margin-top: 54px;
  }

  .pageFooter p {
    max-width: 620px;
    margin: 0;
    color: var(--muted);
    font-size: 14px;
    line-height: 1.6;
  }

  .pageFooter code {
    font-family: var(--font-geist-mono), monospace;
    font-size: 13px;
  }

  @media (max-width: 760px) {
    .falseCircleLede {
      grid-template-columns: minmax(0, 1fr);
      gap: 28px;
    }

    .knotMeta {
      flex-wrap: wrap;
      gap: 10px;
    }

    .knotCorners li {
      grid-template-columns: minmax(0, 1fr);
      gap: 3px;
    }

    .falseCircleSites {
      grid-template-columns: minmax(0, 1fr);
    }

    .falseCircleFigure {
      flex-direction: row;
      gap: 18px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .collapseToggle {
      transition: none;
    }
  }
</style>
