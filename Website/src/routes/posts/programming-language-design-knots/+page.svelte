<script lang="ts">
  import { onMount } from "svelte";
  import DesignKnotPlane from "$lib/components/DesignKnotPlane.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";
  import IdentityPipesSyntax from "$lib/components/IdentityPipesSyntax.svelte";
  import ChoiceLeadSyntax from "$lib/components/ChoiceLeadSyntax.svelte";

  let knotCatalogue: HTMLElement;
  let knotLinker: SVGSVGElement;

  onMount(() => {
    const knots = Array.from(
      knotCatalogue.querySelectorAll<HTMLElement>(".knot"),
    );
    const smoothRange = (start: number, end: number, value: number) => {
      const progress = Math.max(0, Math.min(1, (value - start) / (end - start)));
      return progress * progress * (3 - 2 * progress);
    };
    let frame = 0;
    const render = () => {
      frame = 0;
      const catalogueRect = knotCatalogue.getBoundingClientRect();
      const points: { x: number; y: number }[] = [];
      for (const knot of knots) {
        const rect = knot.getBoundingClientRect();
        const distancePastCenter = window.innerHeight * 0.5 - (rect.top + rect.height * 0.5);
        const entryStart = -(window.innerHeight + rect.height) * 0.5;
        const centerRadius = Math.max(18, rect.height * 0.14);
        const progress = smoothRange(entryStart, centerRadius, distancePastCenter);
        knot.style.setProperty("--scroll-progress", progress.toFixed(4));
        knot.style.setProperty("--scroll-distance", `${distancePastCenter.toFixed(1)}px`);
        knot.dataset.scrollPhase = distancePastCenter < entryStart
          ? "before"
          : distancePastCenter < -centerRadius
            ? "entering"
            : distancePastCenter <= centerRadius
              ? "centered"
              : "passed";
        points.push({
          x: rect.left - catalogueRect.left + 27,
          y: rect.top - catalogueRect.top + rect.height / 2,
        });
      }
      knotLinker.innerHTML = points.slice(0, -1).map((point, index) => {
        const next = points[index + 1];
        const middleY = (point.y + next.y) / 2;
        return `<path d="M ${point.x} ${point.y} V ${middleY} H ${next.x} V ${next.y}" />`;
      }).join("");
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(render);
    };
    window.addEventListener("scroll", schedule, { passive: true });
    const resizeObserver = new ResizeObserver(schedule);
    resizeObserver.observe(knotCatalogue);
    render();
    return () => {
      if (frame) cancelAnimationFrame(frame);
      window.removeEventListener("scroll", schedule);
      resizeObserver.disconnect();
    };
  });
</script>

<svelte:head>
  <meta name="robots" content="noindex, nofollow, noai" />
</svelte:head>

<EssayPage
  title="Programming Language Design Knots"
  description="What it feels like to reason about syntax and semantics while the substrate itself keeps changing shape."
  category="Language design"
  date="August 9, 2026"
>
  <section>
    <h2>The plane moves under you</h2>

    <p>
      Designing a programming language means working in an unusually open-ended
      substrate. Syntax is not yet a fixed surface that constrains the work.
      Semantics are not yet laws that every later feature must obey. Both are
      still available to change, which gives the designer enormous freedom and
      removes many of the boundaries that normally make a problem tractable.
    </p>

    <p>
      It can feel like reasoning on a plane whose shape changes while you stand
      on it. A rule pinches one point. A more general interpretation inflates
      another. An abstraction flattens a region that previously needed several
      special cases. Then one elegant local decision twists the entire surface
      and changes what every neighboring rule means.
    </p>

    <p>
      This is not ordinary feature design. In an application, the language is
      the ground beneath the feature. In a language, the ground is part of the
      thing being designed. You are deciding not only how to solve a problem,
      but which distinctions are real, which distinctions are written, and
      which distinctions should disappear before they reach the programmer.
    </p>
  </section>

  <section>
    <h2>Local elegance is not enough</h2>

    <p>
      A language rule can be beautiful in isolation and still deform the whole
      system badly. Generic syntax can make one reusable function easy to
      express while quietly moving meta-level substitution into every concrete
      declaration. A special optional type can solve absence while obscuring
      the more general relationship between a value and no value.
    </p>

    <p>
      The difficult work is therefore not selecting the cleverest syntax. It
      is preserving the shape of the language while several correct principles
      pull in different directions. Sometimes the conflict cannot be resolved
      by tightening one rule. It must be held long enough to understand the
      structure of the conflict itself.
    </p>

    <DesignKnotPlane />
  </section>

  <section class="knotCatalogue" bind:this={knotCatalogue}>
    <h2>Design knots</h2>
    <svg class="knotLinker" bind:this={knotLinker} aria-hidden="true"></svg>

    <article class="knot">
      <p class="knotNumber">01</p>
      <h3>Identity without generics</h3>
      <p>
        Concrete Range source should describe values and their relationships
        without exposing meta machinery. But a reusable identity function must
        accept and return the same unknown value. Generic parameters solve that
        by placing meta-level substitution directly inside concrete function
        syntax. If Range removes that syntax, where does the
        unknown-but-identical relationship live?
      </p>
      <div class="designCode">
        <IdentityPipesSyntax />
        <p>
          This spelling exposes the shape of the question. It is not a syntax
          proposal and is not expected to compile.
        </p>
      </div>
    </article>

    <article class="knot">
      <p class="knotNumber">02</p>
      <h3>Choice, coexistence, and cardinality</h3>
      <p>
        <code>String | Void</code> can describe absence and
        <code>String | Error</code> can describe a result-like choice. But a
        value may also carry String, Error, and Delta simultaneously, and each
        relationship may occur many times. The knot is finding a concrete
        notation that keeps alternative values, simultaneous slots, and
        multiplicity independent without rebuilding generic wrappers under new
        names.
      </p>
      <div class="designCode">
        <ChoiceLeadSyntax
          frequencies={[174.61]}
          scaleRatios={[1, 1.125, 1.2, 1.334, 1.5, 1.68, 1.778]}
          score={[
            [0, 0, 2], [1, 4, 6], [2, 2, 10],
          ]}
          cycleSubdivisions={12}
          ring={0.42}
          timbre="gamelan"
          complement
        />
      </div>
    </article>

    <article class="knot">
      <p class="knotNumber">03</p>
      <h3>Shape to be determined</h3>
      <p>
        This knot is still unnamed. Its language question and concrete notation
        remain deliberately open; for now, only its musical place in the larger
        progression is established.
      </p>
      <div class="designCode">
        <ChoiceLeadSyntax
          choices={["?", "?", "?"]}
          frequencies={[174.61]}
          scaleRatios={[1, 1.125, 1.2, 1.5, 1.778]}
          score={[
            [1, 2, 3], [2, 4, 6], [0, 3, 9], [2, 1, 11],
          ]}
          cycleSubdivisions={12}
          noteNames="sol · si · do♯"
          timbre="gamelan"
          ring={0.9}
        />
      </div>
    </article>
  </section>
</EssayPage>

<style>
  .knotCatalogue {
    position: relative;
    margin-top: 82px;
  }

  .knotLinker {
    position: absolute;
    z-index: 0;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
    pointer-events: none;
  }

  .knotLinker :global(path) {
    fill: none;
    stroke: color-mix(in oklch, var(--range), transparent 76%);
    stroke-width: 1.5;
    stroke-linecap: round;
    stroke-dasharray: 4 9;
    animation: linkerFlow 1.8s linear infinite;
  }

  .knot {
    position: relative;
    display: grid;
    grid-template-columns: 54px minmax(0, 1fr);
    column-gap: 22px;
    padding: 30px 0;
    border-top: 1px solid var(--line);
    opacity: calc(0.08 + var(--scroll-progress, 0) * 0.92);
    transform: translateY(calc((1 - var(--scroll-progress, 0)) * 26px));
    transition: opacity 80ms linear;
  }

  @keyframes linkerFlow {
    to { stroke-dashoffset: -26; }
  }

  @media (prefers-reduced-motion: reduce) {
    .knot {
      opacity: 1;
      transform: none;
    }

    .knotLinker :global(path) {
      animation: none;
    }
  }

  .knotNumber,
  .knot h3,
  .knot > p,
  .designCode {
    position: relative;
    z-index: 1;
  }

  .knot:last-child {
    border-bottom: 1px solid var(--line);
  }

  .knotNumber {
    grid-row: 1 / 3;
    color: var(--range) !important;
    font-family: var(--font-geist-mono), monospace;
    font-size: 13px !important;
    letter-spacing: 0.08em;
  }

  .knot h3 {
    margin: 0 0 12px;
    color: var(--ink);
    font-size: clamp(21px, 3vw, 28px);
    font-weight: 540;
    letter-spacing: -0.035em;
  }

  .designCode {
    grid-column: 2;
    margin-top: 24px;
  }

  .designCode :global(range-code-block) {
    margin: 0;
  }

  .designCode > p {
    margin-top: 10px !important;
    color: var(--muted) !important;
    font-size: 13px !important;
    line-height: 1.5 !important;
  }

  @media (max-width: 560px) {
    .knot {
      grid-template-columns: 34px minmax(0, 1fr);
      column-gap: 12px;
    }

    .designCode {
      grid-column: 1 / -1;
    }
  }
</style>
