<script lang="ts">
  import { dev } from "$app/environment";
  import PostCard from "$lib/components/PostCard.svelte";
  import PostNoiseShader from "$lib/components/PostNoiseShader.svelte";
  import { draftPosts, posts } from "$lib/posts";

  const publishedIntro = posts.find((post) => post.slug === "intro-to-range");
  const futureIntros = dev
    ? ["intro-to-range-2", "intro-to-range-3", "intro-to-range-4"]
      .map((slug) => draftPosts.find((post) => post.slug === slug))
      .filter((post) => post !== undefined)
    : [];
  const introPosts = [publishedIntro, ...futureIntros].filter(
    (post) => post !== undefined,
  );
</script>

<section class="featuredIntroSeries" aria-labelledby="intro-series-title">
  <header>
    <h2 id="intro-series-title">Introduction</h2>
  </header>

  {#each introPosts as introPost}
    <section class="featuredIntroPost" aria-label={introPost.cardTitle}>
      <PostNoiseShader
        palette={introPost.palette}
        maxFps={30}
        densityLimit={1.25}
        measure={false}
      />
      <PostCard
        post={introPost}
        href={introPost.previewHref ?? introPost.href}
      />
    </section>
  {/each}
</section>

<style>
  .featuredIntroSeries {
    margin-top: 64px;
    padding-top: 24px;
  }

  .featuredIntroSeries > header {
    display: flex;
    align-items: baseline;
    justify-content: flex-end;
    text-align: right;
  }

  .featuredIntroSeries > header h2 {
    margin: 0;
    font-size: clamp(28px, 4vw, 42px);
    font-weight: 520;
    letter-spacing: -0.045em;
  }

  .featuredIntroPost {
    position: relative;
    min-width: 0;
    height: clamp(320px, 38vw, 460px);
    margin-top: 32px;
    overflow: hidden;
  }

  .featuredIntroPost > :global(.postShader) {
    position: absolute;
    inset: 0;
    z-index: 0;
  }

  .featuredIntroPost > :global(canvas) {
    position: absolute;
    inset: 0;
    z-index: 0;
  }

  .featuredIntroPost > :global(.latestPost) {
    width: 100%;
    height: 100%;
    background: transparent;
  }

  @media (max-width: 720px) {
    .featuredIntroSeries {
      margin-top: 40px;
    }

    .featuredIntroPost {
      height: 320px;
      margin-top: 24px;
    }
  }
</style>
