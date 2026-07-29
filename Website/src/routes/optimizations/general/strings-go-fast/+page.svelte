<script lang="ts">
  import { improvedStringsBenchmark, slug, stringScalingBenchmarks } from "$lib/benchmarks";
  import Chart from "$lib/components/Chart.svelte";
</script>

<svelte:head>
  <title>Strings Go Fast · Range</title>
  <meta
    name="description"
    content="How Range made 100,000 String appends about 120 times faster while sharply reducing peak memory."
  />
  <meta property="og:title" content="Strings Go Fast · Range" />
  <meta
    property="og:description"
    content="How Range made 100,000 String appends about 120 times faster while sharply reducing peak memory."
  />
  <meta property="og:type" content="article" />
</svelte:head>

<range-update-page>
  <main>
    <header class="updatePageHeader"><a href="/">Range</a><div><h1>Strings Go Fast</h1><p class="dateLabel">July 18, 2026</p></div></header>
    <section class="contextSection" aria-labelledby="lowering-sequence-title"><div class="sectionHeader"><h2 id="lowering-sequence-title">Sequence</h2><p class="dateLabel">7:29 PM</p></div><figure class="contextFigure"><div class="contextImageCrop"><img src="/string-lowering-conversation.png" alt="User message about processing strings together followed by the complete Codex response behind the Strings Go Fast optimization" /></div><figcaption>Owned String storage carries length, capacity, and data forward so unique growth can extend the same allocation.</figcaption></figure></section>
    <section class="improvementSection" aria-labelledby="improved-title">
      <div class="sectionHeader"><h2 id="improved-title">Improvement</h2><p class="dateLabel">July 18, 2026</p></div>
      <section class="improvementChart" aria-labelledby="range-improvement-chart-title"><header class="improvementHeader"><div class="improvementTitle"><h2 id="range-improvement-chart-title">100k appends · Range</h2><div class="improvementSummary"><span>~120× faster</span><span>~2,800× less peak memory</span></div></div></header><div class="improvementPlot"><svg class="bezierChart" viewBox="0 0 960 380" role="img" aria-labelledby="range-improvement-svg-title range-improvement-svg-description"><title id="range-improvement-svg-title">Range String performance before and after lowering</title><desc id="range-improvement-svg-description">Median wall time falls from 491.2 milliseconds to 4.1 milliseconds, while peak memory falls from 5.3 gigabytes to 1.9 megabytes.</desc><g class="bezierGrid"><line x1="55" y1="70" x2="930" y2="70"></line><line x1="55" y1="180" x2="930" y2="180"></line><line x1="55" y1="290" x2="930" y2="290"></line></g><path class="bezierLine" d="M 90 72 C 285 72, 430 290, 900 290"></path><circle class="bezierPoint" cx="90" cy="72" r="6"></circle><circle class="bezierPoint" cx="900" cy="290" r="6"></circle><g class="pointMetrics"><text class="pointTime" x="90" y="48" text-anchor="middle">491.2 ms</text><text class="pointMemory" x="90" y="102" text-anchor="middle">5.3 GB</text><text class="pointTime" x="900" y="266" text-anchor="middle">4.1 ms</text><text class="pointMemory" x="900" y="320" text-anchor="middle">1.9 MB</text></g><g class="bezierLabels"><text x="90" y="364" text-anchor="middle">Before</text><text x="900" y="364" text-anchor="middle">After</text></g></svg></div></section>
      <div class="improvedStringComparison"><Chart benchmark={improvedStringsBenchmark} id="improved-strings" /></div>
    </section>
    <section class="scalingSection" aria-labelledby="scaling-title"><div class="sectionHeader"><h2 id="scaling-title">Scaling</h2><p class="dateLabel">July 18, 2026</p></div><div class="chartGrid">{#each stringScalingBenchmarks as benchmark}<Chart {benchmark} id={`scaling-${slug(benchmark.name)}`} />{/each}</div></section>
  </main>
</range-update-page>
