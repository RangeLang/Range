<script lang="ts">
  import {
    performanceObservations,
    performanceScales,
    type PerformanceObservation,
  } from "$lib/benchmark-history";
  import type { BenchmarkResult } from "$lib/benchmarks";
  import Footer from "$lib/components/Footer.svelte";

  type LanguageSeries = {
    color: string;
    language: string;
    points: { milliseconds: number; operationCount: number }[];
  };

  const chart = {
    left: 72,
    right: 968,
    top: 24,
    bottom: 552,
  };
  const runtimeTicks = [4, 10, 25, 50, 125];
  const minimumOperations = Math.min(
    ...performanceScales.map((scale) => scale.count),
  );
  const maximumOperations = Math.max(
    ...performanceScales.map((scale) => scale.count),
  );
  const minimumRuntime = runtimeTicks[0];
  const maximumRuntime = runtimeTicks[runtimeTicks.length - 1];
  const languageColors: Record<string, string> = {
    C: "oklch(0.50 0.025 255)",
    "C++": "oklch(0.62 0.035 255)",
    Rust: "oklch(0.61 0.12 52)",
    Go: "oklch(0.66 0.10 220)",
    Swift: "oklch(0.68 0.15 42)",
    Range: "var(--range)",
  };

  function normalizedResults(
    observation: PerformanceObservation,
    operationCount: number,
  ): BenchmarkResult[] {
    const benchmark = observation.slices.find(
      (slice) => slice.operationCount === operationCount,
    )?.benchmark;
    return (
      benchmark?.results.map((result) =>
        Array.isArray(result)
          ? { language: result[0], milliseconds: result[1] }
          : result,
      ) ?? []
    );
  }

  function languageSeries(
    observation: PerformanceObservation,
  ): LanguageSeries[] {
    const series = new Map<string, LanguageSeries>();
    for (const scale of performanceScales) {
      for (const result of normalizedResults(observation, scale.count)) {
        const existing = series.get(result.language) ?? {
          color: languageColors[result.language] ?? "var(--peer)",
          language: result.language,
          points: [],
        };
        existing.points.push({
          milliseconds: result.milliseconds,
          operationCount: scale.count,
        });
        series.set(result.language, existing);
      }
    }
    return [...series.values()].sort((left, right) => {
      if (left.language === "Range") return 1;
      if (right.language === "Range") return -1;
      return left.language.localeCompare(right.language);
    });
  }

  function operationX(operationCount: number): number {
    const progress =
      (Math.log10(operationCount) - Math.log10(minimumOperations)) /
      (Math.log10(maximumOperations) - Math.log10(minimumOperations));
    return chart.left + progress * (chart.right - chart.left);
  }

  function runtimeY(milliseconds: number): number {
    const progress =
      (Math.log10(milliseconds) - Math.log10(minimumRuntime)) /
      (Math.log10(maximumRuntime) - Math.log10(minimumRuntime));
    return chart.bottom - progress * (chart.bottom - chart.top);
  }

  function seriesPoints(series: LanguageSeries): string {
    return series.points
      .map(
        (point) =>
          `${operationX(point.operationCount)},${runtimeY(point.milliseconds)}`,
      )
      .join(" ");
  }

  function scaleLabel(operationCount: number): string {
    return (
      performanceScales.find((scale) => scale.count === operationCount)?.label ??
      operationCount.toLocaleString("en-US")
    );
  }

  function observationDate(value: string): string {
    return new Date(`${value}T00:00:00Z`).toLocaleDateString("en-US", {
      day: "numeric",
      month: "short",
      timeZone: "UTC",
      year: "numeric",
    });
  }
</script>

<svelte:head>
  <title>Performance Over Time · Range</title>
  <meta
    name="description"
    content="Observed cross-language scaling snapshots for Range and peer runtimes."
  />
</svelte:head>

<range-performance-history>
  <main class="performanceHistoryPage">
    <header class="performanceHistoryHeader">
      <a class="backLink routeWordmark" href="/benchmarks">
        <span class="rangeWord">Range Performance</span>
      </a>
      <div>
        <p>Scaling observations</p>
        <h1>Performance over time</h1>
        <span>
          Each dated snapshot compares how Range and peer languages scale as
          the same workload grows. New benchmark dates append new snapshots.
        </span>
      </div>
    </header>

    {#each performanceObservations as observation}
      {@const series = languageSeries(observation)}
      <section
        class="historyGraphSection"
        aria-labelledby={`${observation.id}-title`}
        aria-describedby={`${observation.id}-description`}
      >
        <div class="historyGraphMeta">
          <div>
            <span id={`${observation.id}-title`}>{observation.label}</span>
            <time datetime={observation.observedAt}>
              Observed {observationDate(observation.observedAt)}
            </time>
          </div>
          <p id={`${observation.id}-description`}>
            {observation.note} X-axis: String append operations. Y-axis:
            runtime in milliseconds on a logarithmic scale.
          </p>
        </div>

        <div class="historyLanguageLegend" aria-label="Language lines">
          {#each series as item}
            <span class:rangeSeries={item.language === "Range"}>
              <i style={`--series-color:${item.color};`}></i>
              {item.language}
            </span>
          {/each}
        </div>

        <div class="historyGraphViewport">
          <div class="historyGraph historyScalingGraph">
            <span class="historyYAxisTitle">runtime · milliseconds · log scale</span>
            <span class="historyXAxisTitle">String append operations · log scale</span>

            <svg
              class="historyLineChart"
              viewBox="0 0 1000 600"
              role="img"
              aria-labelledby={`${observation.id}-chart-title`}
              aria-describedby={`${observation.id}-chart-description`}
            >
              <title id={`${observation.id}-chart-title`}>
                {observation.label}, observed {observationDate(observation.observedAt)}
              </title>
              <desc id={`${observation.id}-chart-description`}>
                Six language lines compare runtime in milliseconds as String
                append operations increase from 100 thousand to 10 million.
              </desc>

              {#each runtimeTicks as tick}
                <line
                  class="historyRuntimeGrid"
                  x1={chart.left}
                  x2={chart.right}
                  y1={runtimeY(tick)}
                  y2={runtimeY(tick)}
                ></line>
                <text
                  class="historyRuntimeTick"
                  x={chart.left - 18}
                  y={runtimeY(tick)}
                  text-anchor="end"
                  dominant-baseline="middle"
                >{tick} ms</text>
              {/each}

              {#each performanceScales as scale}
                <line
                  class="historyOperationGrid"
                  x1={operationX(scale.count)}
                  x2={operationX(scale.count)}
                  y1={chart.top}
                  y2={chart.bottom}
                ></line>
                <text
                  class="historyOperationTick"
                  x={operationX(scale.count)}
                  y={chart.bottom + 28}
                  text-anchor="middle"
                >{scale.label}</text>
              {/each}

              {#each series as item}
                <polyline
                  class="historyLanguageLine"
                  class:rangeSeries={item.language === "Range"}
                  points={seriesPoints(item)}
                  style={`--series-color:${item.color};`}
                ></polyline>
                {#each item.points as point}
                  <circle
                    class="historyLanguagePoint"
                    class:rangeSeries={item.language === "Range"}
                    cx={operationX(point.operationCount)}
                    cy={runtimeY(point.milliseconds)}
                    r={item.language === "Range" ? 6 : 4}
                    style={`--series-color:${item.color};`}
                  >
                    <title>
                      {item.language}: {point.milliseconds.toFixed(1)} ms at
                      {scaleLabel(point.operationCount)} appends
                    </title>
                  </circle>
                {/each}
              {/each}
            </svg>
          </div>
        </div>

        <table class="historyAccessibleTable">
          <caption>
            {observation.label}, observed {observationDate(observation.observedAt)}
          </caption>
          <thead>
            <tr>
              <th>Language</th>
              {#each performanceScales as scale}
                <th>{scale.label} appends</th>
              {/each}
            </tr>
          </thead>
          <tbody>
            {#each series as item}
              <tr>
                <th>{item.language}</th>
                {#each item.points as point}
                  <td>{point.milliseconds.toFixed(1)} ms</td>
                {/each}
              </tr>
            {/each}
          </tbody>
        </table>
      </section>
    {/each}

    <div class="historyLegend">
      <p>
        Lines show scaling within one observed benchmark date. Future dates
        append comparable snapshots without mixing old implementations into
        the current result.
      </p>
    </div>

    <Footer />
  </main>
</range-performance-history>
