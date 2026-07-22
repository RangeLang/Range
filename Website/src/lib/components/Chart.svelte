<script lang="ts">
  import type { Benchmark, BenchmarkResult } from "$lib/benchmarks";
  import CodeBlock from "./CodeBlock.svelte";

  let { benchmark, id }: { benchmark: Benchmark; id: string } = $props();
  let results = $derived(benchmark.results.map((item) => Array.isArray(item) ? { language: item[0], milliseconds: item[1] } : item) as BenchmarkResult[]);
  let fastest = $derived(Math.min(...results.map((result) => result.milliseconds)));

  function rowColor(milliseconds: number): string {
    const scaleDeviation = (milliseconds - fastest) / benchmark.axisMax;
    const greenThreshold = 0.02;
    const redThreshold = 0.3;
    const orangeProgress = Math.min(1, Math.max(0, (scaleDeviation - greenThreshold) / (redThreshold - greenThreshold)));
    const softened = Math.log1p(2 * orangeProgress ** 1.7) / Math.log(3);
    const yellowStop = 0.58;
    const yellowMix = Math.min(100, (softened / yellowStop) * 100);
    const orangeMix = Math.max(0, ((softened - yellowStop) / (1 - yellowStop)) * 100);
    const redMix = scaleDeviation <= redThreshold ? 0 : Math.min(100, Math.max(0, (Math.log(scaleDeviation / redThreshold) / Math.log(1 / redThreshold)) * 100));
    const preRed = softened <= yellowStop
      ? `color-mix(in oklch, var(--fastest-bar), var(--yellow-bar) ${yellowMix.toFixed(1)}%)`
      : `color-mix(in oklch, var(--yellow-bar), var(--warning-bar) ${orangeMix.toFixed(1)}%)`;
    return scaleDeviation <= redThreshold ? preRed : `color-mix(in oklch, var(--warning-bar), var(--slow-bar) ${redMix.toFixed(1)}%)`;
  }
</script>

<range-benchmark-chart>
  <section class="chart" aria-labelledby={`${id}-title`}>
    <header class="chartHeader">
      <div>
        <h2 id={`${id}-title`}>
          {#if benchmark.href}<a href={benchmark.href}>{benchmark.name}</a>{:else}{benchmark.name}{/if}
        </h2>
        {#if benchmark.leaf}<p class="chartLeaf">{benchmark.leaf}</p>{/if}
      </div>
      <span>{benchmark.scale}</span>
    </header>
    {#if benchmark.description}<p class="chartDescription">{benchmark.description}</p>{/if}
    <div class="rows">
      {#each results as result}
        {@const isRange = result.language === "Range"}
        {@const isFastest = Math.abs(result.milliseconds - fastest) < 0.0001}
        <div class:range={isRange} class:fastest={isFastest} class="row">
          <span class="language">{result.language}</span>
          <span class="track" aria-hidden="true"><span class="bar" style={`width:${(result.milliseconds / benchmark.axisMax) * 100}%;background:${rowColor(result.milliseconds)}`}></span></span>
          <span class="value"><span>{result.milliseconds.toFixed(1)} ms</span>{#if isFastest && !isRange}<small>absolute best</small>{/if}</span>
        </div>
      {/each}
    </div>
    <div class="axis" aria-hidden="true"><span></span><span class="ticks"><span>0</span><span>{benchmark.axisMax / 2}</span><span>{benchmark.axisMax}</span></span><span></span></div>
    {#if benchmark.note}<p class="chartNote">{benchmark.note}</p>{/if}
    {#if benchmark.implementations?.length}
      <details class="testCode">
        <summary>Test code</summary>
        <div class="testCodeGrid">
          {#each benchmark.implementations as item}
            <CodeBlock source={item.source} syntax={item.syntax} label={`${item.language} · ${item.filename}`} />
          {/each}
        </div>
      </details>
    {/if}
  </section>
</range-benchmark-chart>
