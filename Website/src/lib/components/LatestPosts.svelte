<script lang="ts">
  import { dev } from "$app/environment";
  import { onMount } from "svelte";
  import PostCard from "$lib/components/PostCard.svelte";
  import PostNoiseShader from "$lib/components/PostNoiseShader.svelte";
  import { allPosts, postHref, publishedPosts } from "$lib/posts";

  const withoutIntroSeries = (post: (typeof allPosts)[number]) =>
    !post.slug.startsWith("intro-to-range");
  const visiblePosts = dev
    ? allPosts.filter(withoutIntroSeries)
    : publishedPosts.filter(withoutIntroSeries);

  let hoveredPost = $state<number | null>(null);
  let focusedPost = $state<number | null>(null);
  let lastActivePost = $state(0);
  let focusCursorReady = $state(false);
  let activePost = $derived(hoveredPost ?? focusedPost ?? lastActivePost);
  let focusCursorVisible = $derived(
    hoveredPost !== null || focusedPost !== null,
  );

  const setHoveredPost = (index: number, hovered: boolean) => {
    hoveredPost = hovered ? index : hoveredPost === index ? null : hoveredPost;
    if (hovered) lastActivePost = index;
  };

  const setFocusedPost = (index: number, focused: boolean) => {
    focusedPost = focused ? index : focusedPost === index ? null : focusedPost;
    if (focused) lastActivePost = index;
  };

  onMount(() => {
    focusCursorReady = true;
  });
</script>

<section class="latestPosts" aria-labelledby="latest-posts-title">
  <header class="latestPostsHeader">
    <h2 id="latest-posts-title">Latest posts</h2>
    <span>Notes from the language</span>
  </header>
  <div
    class="latestPostStrip"
    data-active-post={activePost}
    data-focus-cursor-visible={focusCursorVisible ? "" : undefined}
    data-focus-cursor-ready={focusCursorReady ? "" : undefined}
  >
    <span class="latestPostCursor" aria-hidden="true"></span>
    <PostNoiseShader
      palettes={visiblePosts.map((post) => post.palette)}
      maxFps={30}
      densityLimit={1.25}
      measure={false}
      shared
    />
    {#each visiblePosts as post, index}
      <PostCard
        {post}
        href={postHref(post)}
        onhoverchange={(hovered) => setHoveredPost(index, hovered)}
        onfocuschange={(focused) => setFocusedPost(index, focused)}
      />
    {/each}
  </div>
</section>
