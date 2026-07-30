<script lang="ts">
  import type { Post } from "$lib/posts";
  import type { PostContrastPalette } from "$lib/post-contrast";
  import PostNoiseShader from "$lib/components/PostNoiseShader.svelte";

  let {
    post,
    still = false,
    social = false,
    onhoverchange,
    onfocuschange,
  }: {
    post: Post;
    still?: boolean;
    social?: boolean;
    onhoverchange?: (hovered: boolean) => void;
    onfocuschange?: (focused: boolean) => void;
  } = $props();

  let measuredContrast = $state<PostContrastPalette>();
  let contrast = $derived(
    measuredContrast ?? {
      ...post.cardPalette,
      complementHue: 0,
    },
  );
  let paletteHue = $derived((22 + post.palette * 137.507764) % 360);

  const applyContrast = (measured: PostContrastPalette) => {
    measuredContrast = measured;
  };
</script>

<a
  class:latestPost={!social}
  class:socialPost={social}
  href={post.href}
  aria-label={post.cardTitle}
  data-post-palette={post.palette}
  data-foreground-contrast={contrast?.contrast.toFixed(2)}
  data-measured-background={contrast?.background}
  style={`--palette-hue: ${paletteHue}; --post-foreground: ${contrast.foreground}; --post-foreground-muted: ${contrast.mutedForeground}`}
  onpointerenter={() => onhoverchange?.(true)}
  onpointerleave={() => onhoverchange?.(false)}
  onfocus={() => onfocuschange?.(true)}
  onblur={() => onfocuschange?.(false)}
>
  {#if social}
    <PostNoiseShader palette={post.palette} {still} oncontrast={applyContrast} />
  {/if}
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
    color: var(--post-foreground);
    text-decoration: none;
  }

  .socialPost > :global(.postShader) {
    position: absolute;
    inset: 0;
    z-index: 0;
  }

  .socialPost .postCopy {
    padding: 240px 72px 116px;
    gap: 14px;
    background: radial-gradient(
      ellipse 110% 150% at 50% 135%,
      oklch(1 0 0 / 0.68),
      oklch(1 0 0 / 0.32) 42%,
      oklch(1 0 0 / 0.12) 66%,
      transparent 90%
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
