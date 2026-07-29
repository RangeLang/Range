<script lang="ts">
  import { githubUrl } from "$lib/benchmarks";
  import RangeNucleus from "$lib/components/RangeNucleus.svelte";
  import GithubIcon from "$lib/components/GithubIcon.svelte";
  import PostCard from "$lib/components/PostCard.svelte";
  import { posts } from "$lib/posts";
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
        {#each posts as post}
          <PostCard {post} />
        {/each}
      </div>
    </section>
    <RangeNucleus />
  </main>
</range-home-page>
