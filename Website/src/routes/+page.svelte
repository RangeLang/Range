<script lang="ts">
  import { data, githubUrl } from "$lib/benchmarks";
  import RangeNucleus from "$lib/components/RangeNucleus.svelte";
  import GithubIcon from "$lib/components/GithubIcon.svelte";
  import PostNoiseShader from "$lib/components/PostNoiseShader.svelte";
</script>

<range-home-page>
  <main class="landingPage">
    <div class="landingSequence">
      <header class="landingNav">
        <a class="landingWordmark" href="/"><span class="landingIndex" data-scale-zero>0</span><span class="rangeWord">Range</span></a>
        <range-spline-nav role="navigation" aria-label="Primary navigation">
          <a href="/benchmarks">Benchmarks</a><a href="/optimizations/general/strings-go-fast">Updates</a><a href={githubUrl} target="_blank" rel="noreferrer">GitHub</a>
        </range-spline-nav>
      </header>
      <range-scale aria-hidden="true" endpoint-gap="8" endpoint-gap-end="16" division-base="3" division-levels="3" mark-length="5" mark-thickness="0.25"></range-scale>
      <range-optical-guide aria-hidden="true"></range-optical-guide>
      <section class="landingHero" aria-labelledby="range-title">
        <h1 id="range-title"><span class="landingIndex" data-scale-end><span>1</span></span><span class="rangeTitleWord">Range</span><span class="rangePerformanceAnchor" aria-hidden="true"></span></h1>
        <div class="landingSupport">
          <p>a love letter to electrons, logic and abstraction</p>
          <div class="landingActions"><a class="primaryAction" href="/benchmarks">Benchmarks</a><a class="secondaryAction" href={githubUrl} target="_blank" rel="noreferrer"><GithubIcon />GitHub</a></div>
        </div>
      </section>
    </div>
    <section class="latestPosts" aria-labelledby="latest-posts-title">
      <header class="latestPostsHeader">
        <h2 id="latest-posts-title">Latest posts</h2>
        <span>Notes from the language</span>
      </header>
      <div class="latestPostStrip">
        <a class="latestPost" href="/features/macros/codability-under-100">
          <PostNoiseShader variant="codability" />
          <span class="postCopy">
            <small>Metaprogramming</small>
            <strong>Codability under 100</strong>
            <span>One Range-authored macro, explained line by line.</span>
          </span>
        </a>
        <a class="latestPost" href="/optimizations/general/strings-go-fast">
          <PostNoiseShader variant="string" />
          <span class="postCopy">
            <small>Compiler update</small>
            <strong>Strings Go Fast</strong>
            <span>100k appends, from 491.2 ms to 4.1 ms.</span>
          </span>
        </a>
      </div>
    </section>
    <RangeNucleus />
    <section class="landingLinks" aria-label="Range links">
      <a href="/benchmarks"><span><strong>Benchmarks</strong><small>{data.summary.runLeafCount} generated comparisons</small></span><span>View</span></a>
      <a href="/optimizations/general/strings-go-fast"><span><strong>Strings Go Fast</strong><small>100k appends · 491.2 ms → 4.1 ms</small></span><span>View</span></a>
    </section>
  </main>
</range-home-page>
