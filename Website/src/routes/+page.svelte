<script lang="ts">
  import { data, githubUrl } from "$lib/benchmarks";
  import RangeNucleus from "$lib/components/RangeNucleus.svelte";
  import GithubIcon from "$lib/components/GithubIcon.svelte";
</script>

<range-home-page>
  <main class="landingPage">
    <div class="landingSequence">
      <header class="landingNav">
        <a class="landingWordmark" href="/"><span class="landingIndex" data-scale-zero>0</span><span class="rangeWord">Range</span></a>
        <range-spline-nav role="navigation" aria-label="Primary navigation">
          <a href="/benchmarks">Benchmarks</a><a href="/updates/string-lowering">Updates</a><a href={githubUrl} target="_blank" rel="noreferrer">GitHub</a>
        </range-spline-nav>
      </header>
      <range-scale aria-hidden="true" endpoint-gap="8" endpoint-gap-end="16" division-base="3" division-levels="3" mark-length="5" mark-thickness="0.25" zero-drag-falloff="0.38" zero-drag-limit="0.42"></range-scale>
      <range-optical-guide aria-hidden="true"></range-optical-guide>
      <section class="landingHero" aria-labelledby="range-title">
        <h1 id="range-title"><span class="landingIndex" data-scale-end><span>1</span></span><span class="rangeTitleWord">Range</span><span class="rangePerformanceAnchor" aria-hidden="true"></span></h1>
        <div class="landingSupport">
          <p>a love letter to electrons, logic and abstraction</p>
          <div class="landingActions"><a class="primaryAction" href="/benchmarks">Benchmarks</a><a class="secondaryAction" href={githubUrl} target="_blank" rel="noreferrer"><GithubIcon />GitHub</a></div>
        </div>
      </section>
    </div>
    <RangeNucleus />
    <section class="landingLinks" aria-label="Range links">
      <a href="/benchmarks"><span><strong>Benchmarks</strong><small>{data.summary.runLeafCount} generated comparisons</small></span><span>View</span></a>
      <a href="/updates/string-lowering"><span><strong>String lowering</strong><small>100k appends · 491.2 ms → 4.1 ms</small></span><span>View</span></a>
    </section>
  </main>
</range-home-page>
