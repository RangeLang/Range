<script lang="ts">
  import { VStack } from "sveltely";
  import { githubUrl } from "$lib/benchmarks";
  import FeaturedIntroPost from "$lib/components/FeaturedIntroPost.svelte";
  import GithubIcon from "$lib/components/GithubIcon.svelte";
  import LatestPosts from "$lib/components/LatestPosts.svelte";
  import RangeNucleus from "$lib/components/RangeNucleus.svelte";
  import SiteHeader from "$lib/components/SiteHeader.svelte";
  import RangeTitle from "$lib/components/RangeTitle.svelte";
</script>

<VStack as="main" spacing={0} data-range-home-page>
  <SiteHeader indexed />
  <range-scale
    aria-hidden="true"
    endpoint-gap="8"
    endpoint-gap-end="0"
    division-base="3"
    division-levels="3"
    mark-length="5"
    mark-thickness="0.25"
  ></range-scale>
  <section class="landingHero" aria-labelledby="range-title">
    <h1 id="range-title"><span class="scaleAnchorEnd" data-scale-end aria-hidden="true"></span><RangeTitle /><span class="rangePerformanceAnchor" aria-hidden="true"></span></h1>
    <div class="landingLowerScale" aria-hidden="true">
      <span class="landingLowerScaleStart" data-scale-zero></span>
      <range-scale
        reversed
        endpoint-gap="0"
        endpoint-gap-end="0"
        division-base="3"
        division-levels="3"
        mark-length="5"
        mark-thickness="0.25"
      ></range-scale>
      <span class="landingLowerScaleEnd" data-scale-end></span>
    </div>
    <range-optical-guide aria-hidden="true"></range-optical-guide>
    <div class="landingSupport">
      <p>a love letter to electrons, logic and abstraction</p>
      <div class="landingActions"><a class="primaryAction" href="/benchmarks">Benchmarks</a><a class="secondaryAction" href={githubUrl} target="_blank" rel="noreferrer"><GithubIcon />GitHub</a></div>
    </div>
  </section>
  <FeaturedIntroPost />
  <LatestPosts />
  <RangeNucleus />
</VStack>
