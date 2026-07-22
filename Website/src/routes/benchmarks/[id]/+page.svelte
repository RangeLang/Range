<script lang="ts">
  import { formatMemory } from "$lib/benchmarks";
  import Chart from "$lib/components/Chart.svelte";
  import Procedure from "$lib/components/Procedure.svelte";

  let { data: pageData } = $props();
</script>

<range-benchmark-page>
  <main>
    <header class="benchmarkDetailHeader"><a class="backLink" href="/benchmarks">Benchmarks</a><div><p>{pageData.category.name}</p><h1>{pageData.subcategory.name} · {pageData.leaf.name}</h1><span>{pageData.leaf.description}</span></div></header>
    <section class="benchmarkDetailChart" aria-label="Benchmark comparison"><Chart benchmark={pageData.benchmark} id={`benchmark-${pageData.leaf.id}`} /></section>
    <section class="measurementsSection" aria-labelledby="measurements-title">
      <div class="sectionHeader"><h2 id="measurements-title">Measurements</h2><p class="dateLabel">Range {pageData.leaf.rangeStatus}</p></div>
      <div class="measurementTableWrap"><table class="measurementTable"><thead><tr><th>Language</th><th>Wall</th><th>CPU</th><th>Peak memory</th><th>Relative</th><th>Output</th></tr></thead><tbody>{#each pageData.leaf.results as result}<tr><th>{result.language}</th><td>{result.wallMilliseconds.toFixed(1)} ms</td><td>{result.cpuMilliseconds.toFixed(1)} ms</td><td>{formatMemory(result.peakRssKilobytes)}</td><td>{result.relativeToFastest.toFixed(2)}×</td><td>{result.output}</td></tr>{/each}</tbody></table></div>
    </section>
    <section class="benchmarkProcedureSection" aria-labelledby="procedure-title"><div class="sectionHeader"><h2 id="procedure-title">Run procedure</h2></div><Procedure /></section>
  </main>
</range-benchmark-page>
