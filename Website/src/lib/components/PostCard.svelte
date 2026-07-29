<script lang="ts">
  import type { Post } from "$lib/posts";
  import PostNoiseShader from "$lib/components/PostNoiseShader.svelte";

  let {
    post,
    still = false,
    social = false,
  }: {
    post: Post;
    still?: boolean;
    social?: boolean;
  } = $props();
</script>

<a
  class:latestPost={!social}
  class:socialPost={social}
  href={post.href}
  aria-label={post.cardTitle}
>
  <PostNoiseShader palette={post.palette} {still} />
  <span class="postCopy">
    <small>{post.category}</small>
    <strong>{post.cardTitle}</strong>
    <span>{post.cardDescription}</span>
  </span>
</a>

<style>
  .socialPost {
    position: relative;
    width: 1200px;
    height: 630px;
    display: block;
    overflow: hidden;
    isolation: isolate;
    background: var(--paper);
    color: var(--ink);
    text-decoration: none;
  }

  .socialPost > :global(.postShader) {
    position: absolute;
    inset: 0;
    z-index: 0;
  }

  .socialPost .postCopy {
    padding: 180px 72px 64px;
    gap: 14px;
    background: radial-gradient(
      ellipse 94% 128% at 50% 118%,
      oklch(1 0 0 / 0.58),
      oklch(1 0 0 / 0.2) 56%,
      transparent 80%
    );
  }

  .socialPost .postCopy small {
    font-size: 19px;
    letter-spacing: 0.065em;
  }

  .socialPost .postCopy strong {
    max-width: 1080px;
    font-size: 72px;
    line-height: 1;
  }

  .socialPost .postCopy > span {
    font-size: 27px;
    line-height: 1.35;
  }
</style>
