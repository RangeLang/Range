<script lang="ts">
  import { benchmarkFromLeaf, data } from "$lib/benchmarks";
  import Chart from "$lib/components/Chart.svelte";
  import Footer from "$lib/components/Footer.svelte";
  import Procedure from "$lib/components/Procedure.svelte";

  let { data: pageData } = $props();
  let count = $derived(pageData.active.subcategories.reduce((sum: number, item: any) => sum + item.leaves.length, 0));
</script>

<range-benchmarks-page>
  <main>
    <header class="pageHeader"><a class="backLink routeWordmark" href="/"><span class="rangeWord">Range</span></a><h1><span>Range</span><range-typed-text text="Performance" delay="300" interval="45">Performance</range-typed-text></h1></header>
    <section class="benchmarkProject" aria-labelledby="benchmark-project-title">
      <div class="sectionHeader"><h2 id="benchmark-project-title">Benchmark suite</h2><div class="benchmarkHeaderMeta"><a href="/benchmarks/history">Performance over time</a><p class="dateLabel">{new Date(data.generatedAt).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric", timeZone: "UTC" })}</p></div></div>
      <nav class="benchmarkIndex" aria-label="Benchmark categories">
        {#each pageData.categories as category}
          {@const categoryCount = category.subcategories.reduce((sum: number, item: any) => sum + item.leaves.length, 0)}
          <a href={`/benchmarks?category=${category.id}`} aria-current={category.id === pageData.active.id ? "page" : undefined}><span>{category.name}</span><small>{categoryCount}</small></a>
        {/each}
      </nav>
      <details class="runProcedure"><summary>Run procedure</summary><div class="runProcedureBody"><Procedure /></div></details>
      <details class="benchmarkCategory" open>
        <summary><span class="benchmarkCategoryTitle" role="heading" aria-level="3">{pageData.active.name}</span><span>{count} {count === 1 ? "comparison" : "comparisons"}</span></summary>
        <div class="chartGrid">{#each pageData.active.subcategories as subcategory}{#each subcategory.leaves as leaf}<Chart benchmark={benchmarkFromLeaf(subcategory.name, leaf)} id={`current-${pageData.active.id}-${subcategory.id}-${leaf.id}`} />{/each}{/each}</div>
      </details>
      <div class="benchmarkRunStatus" aria-label="Current benchmark run status"><span>{data.summary.runLeafCount} of {data.summary.leafCount} leaves run</span><span>Range passed {data.summary.rangePassed}</span><span>Not emitted {data.summary.rangeNotEmitted}</span><span>Failed {data.summary.rangeFailed}</span></div>
    </section>
    <section class="updatesSection" aria-labelledby="updates-title"><div class="sectionHeader"><h2 id="updates-title">Updates</h2></div><a class="updateLink" href="/optimizations/general/strings-go-fast"><span><strong>Strings Go Fast</strong><small>100k appends · 491.2 ms → 4.1 ms</small></span><time datetime="2026-07-18">July 18, 2026</time></a></section>
    <Footer />
  </main>
</range-benchmarks-page>
