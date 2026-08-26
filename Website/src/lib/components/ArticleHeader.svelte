<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    title,
    description,
    category,
    date,
    shader,
    heading,
    shaderFocusX = 78,
    shaderFocusY = 42,
    shaderOffsetX = 0,
    shaderOpacity = 0.9,
    shaderFade = true,
    alignment = "default",
    tone = "default",
    variant = "default",
  }: {
    title: string;
    description: string;
    category: string;
    date: string;
    shader?: Snippet;
    heading?: Snippet;
    shaderFocusX?: number;
    shaderFocusY?: number;
    shaderOffsetX?: number;
    shaderOpacity?: number;
    shaderFade?: boolean;
    alignment?: "default" | "center";
    tone?: "default" | "inverse";
    variant?: "default" | "saturated-p3";
  } = $props();
</script>

<header
  class="articleHeader"
  class:hasShader={shader !== undefined}
  class:centered={alignment === "center"}
  class:inverse={tone === "inverse"}
  class:saturatedP3={variant === "saturated-p3"}
>
  {#if shader}
    <div
      class="shader"
      class:unmasked={!shaderFade}
      style={`--article-shader-focus-x: ${shaderFocusX}%; --article-shader-focus-y: ${shaderFocusY}%; --article-shader-offset-x: ${shaderOffsetX}%; --article-shader-opacity: ${shaderOpacity};`}
    >
      {@render shader()}
    </div>
  {/if}

  <div class="copy">
    <p class="eyebrow">{category} · {date}</p>
    <h1>
      {#if heading}
        {@render heading()}
      {:else}
        {title}
      {/if}
    </h1>
    <p class="description">{description}</p>
  </div>
</header>

<style>
  .articleHeader {
    position: relative;
    display: grid;
    gap: 24px;
    padding: 88px 0 64px;
    overflow: hidden;
    border-bottom: 1px solid var(--line);
  }

  .articleHeader.hasShader {
    min-height: 380px;
    align-items: end;
    margin-top: 0;
    padding: 88px 0 56px;
    isolation: isolate;
  }

  .shader {
    position: absolute;
    inset: 28px 0 0;
    z-index: 0;
    overflow: hidden;
    opacity: var(--article-shader-opacity);
  }

  .shader :global(canvas) {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    transform: translateX(var(--article-shader-offset-x));
    -webkit-mask-image: radial-gradient(
      circle at var(--article-shader-focus-x) var(--article-shader-focus-y),
      black 0%,
      black 26%,
      rgb(0 0 0 / 0.88) 38%,
      rgb(0 0 0 / 0.56) 52%,
      rgb(0 0 0 / 0.2) 66%,
      transparent 78%
    );
    mask-image: radial-gradient(
      circle at var(--article-shader-focus-x) var(--article-shader-focus-y),
      black 0%,
      black 26%,
      rgb(0 0 0 / 0.88) 38%,
      rgb(0 0 0 / 0.56) 52%,
      rgb(0 0 0 / 0.2) 66%,
      transparent 78%
    );
  }

  .shader.unmasked :global(canvas) {
    -webkit-mask-image: none;
    mask-image: none;
  }

  .shader.unmasked {
    inset: 0;
  }

  .copy {
    position: relative;
    z-index: 1;
    display: grid;
    gap: 24px;
  }

  .eyebrow,
  .articleHeader h1,
  .description {
    margin: 0;
  }

  .eyebrow {
    color: var(--muted);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .articleHeader h1 {
    max-width: 760px;
    font-size: clamp(44px, 8vw, 82px);
    font-weight: 520;
    letter-spacing: -0.065em;
    line-height: 0.96;
  }

  .description {
    max-width: 650px;
    color: var(--muted);
    font-size: clamp(19px, 2.6vw, 25px);
    letter-spacing: -0.025em;
    line-height: 1.38;
  }

  .hasShader .eyebrow {
    color: color-mix(in oklch, var(--ink), transparent 22%);
  }

  .hasShader .description {
    max-width: 560px;
    color: color-mix(in oklch, var(--ink), transparent 14%);
    font-size: clamp(18px, 2.2vw, 22px);
  }

  .articleHeader.hasShader h1 {
    max-width: 680px;
    font-size: clamp(44px, 6vw, 66px);
    line-height: 0.98;
  }

  .articleHeader.centered {
    align-items: center;
  }

  .centered .copy {
    justify-items: center;
    text-align: center;
  }

  .centered h1,
  .centered .description {
    max-width: none;
  }

  .centered h1 {
    width: fit-content;
  }

  .inverse .eyebrow,
  .inverse h1,
  .inverse .description {
    color: white;
  }

  .saturatedP3 {
    background: color(display-p3 0.012 0.004 0.035);
  }

  .saturatedP3 .eyebrow,
  .saturatedP3 .description {
    color: color(display-p3 1 0.97 0.88);
  }

  .saturatedP3.inverse .eyebrow,
  .saturatedP3.inverse h1,
  .saturatedP3.inverse .description {
    color: color(display-p3 1 1 1);
  }

  .saturatedP3 .shader {
    filter: saturate(1.12) brightness(1.04);
  }

  @media (dynamic-range: high) {
    .saturatedP3 .shader {
      filter: saturate(1.2) brightness(1.14);
    }
  }

  @media (max-width: 640px) {
    .articleHeader {
      gap: 20px;
      padding: 64px 0 48px;
    }

    .articleHeader.hasShader {
      min-height: 340px;
      margin-top: 0;
      padding: 64px 0 40px;
    }

    .shader {
      inset: 16px 0 0;
      opacity: 0.7;
    }

    .copy {
      gap: 20px;
    }

  }
</style>
