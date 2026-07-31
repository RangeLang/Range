<script lang="ts">
  import { benchmarkFromLeaf, data } from "$lib/benchmarks";
  import Chart from "$lib/components/Chart.svelte";
  import Footer from "$lib/components/Footer.svelte";
  import Procedure from "$lib/components/Procedure.svelte";
  import SiteHeader from "$lib/components/SiteHeader.svelte";

  let { data: pageData } = $props();
  let count = $derived(pageData.active.subcategories.reduce((sum: number, item: any) => sum + item.leaves.length, 0));
</script>

<range-benchmarks-page>
  <main>
    <SiteHeader />
    <header class="pageHeader"><h1><span>Range</span><range-typed-text text="Performance" delay="300" interval="45">Performance</range-typed-text></h1></header>
    <section class="benchmarkProject" aria-labelledby="benchmark-project-title">
      <div class="sectionHeader"><h2 id="benchmark-project-title">Benchmark suite</h2><div class="benchmarkHeaderMeta"><p class="dateLabel">{new Date(data.generatedAt).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric", timeZone: "UTC" })}</p></div></div>
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
    <Footer />
  </main>
</range-benchmarks-page>
