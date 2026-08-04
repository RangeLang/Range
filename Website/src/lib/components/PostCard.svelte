<script lang="ts">
  import type { Post } from "$lib/posts";
  import type { PostContrastPalette } from "$lib/post-contrast";
  import PostNoiseShader from "$lib/components/PostNoiseShader.svelte";
  import FibonacciSphereShader from "$lib/components/FibonacciSphereShader.svelte";
  import SphereLineShader from "$lib/components/SphereLineShader.svelte";

  let {
    post,
    href = post.href,
    still = false,
    social = false,
    onhoverchange,
    onfocuschange,
  }: {
    post: Post;
    href?: string;
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
  {href}
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
    {#if post.socialShader === "fibonacci-sphere"}
      <div class="socialSphereShader socialIntroShader">
        <FibonacciSphereShader
          showSphere={false}
          fadeToPaper={false}
          starScale={1.35}
          vivid
        />
      </div>
    {:else if post.socialShader === "sphere-lines"}
      <div class="socialSphereShader">
        <SphereLineShader palette={post.palette} topAligned />
      </div>
    {:else}
      <PostNoiseShader palette={post.palette} {still} oncontrast={applyContrast} />
    {/if}
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

  .socialSphereShader {
    position: absolute;
    inset: 0;
    z-index: 0;
    overflow: hidden;
  }

  .socialSphereShader::after {
    position: absolute;
    inset: 0;
    background:
      linear-gradient(
        180deg,
        oklch(1 0 0 / 0.08),
        oklch(1 0 0 / 0.18) 56%,
        oklch(1 0 0 / 0.9)
      ),
      linear-gradient(
        90deg,
        oklch(1 0 0 / 0.96),
        oklch(1 0 0 / 0.48) 47%,
        transparent 80%
      );
    content: "";
  }

  .socialIntroShader::after {
    display: none;
  }

  .socialSphereShader :global(canvas) {
    position: absolute;
    inset: 0;
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

  .socialPost:has(.socialSphereShader) .postCopy {
    padding: 246px 72px 72px;
    background: none;
  }

  .socialPost:has(.socialIntroShader) {
    --post-foreground: white !important;
    --post-foreground-muted: white !important;
    background: oklch(0.07 0.015 255);
  }

  .socialPost:has(.socialIntroShader) .postCopy {
    inset: 0;
    align-content: center;
    align-items: center;
    justify-content: center;
    padding: 72px;
    text-align: center;
  }

  .socialPost:has(.socialIntroShader) .postCopy small {
    display: none;
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

  .latestPost .postCopy strong,
  .latestPost .postCopy > span {
    display: -webkit-box;
    max-block-size: 2lh;
    overflow: hidden;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
    line-clamp: 2;
  }

  .latestPost .postCopy strong {
    min-block-size: 1lh;
  }

  .latestPost .postCopy > span {
    min-block-size: 2lh;
  }
</style>
