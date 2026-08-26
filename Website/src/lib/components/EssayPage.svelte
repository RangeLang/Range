<script lang="ts">
  import type { Snippet } from "svelte";
  import ArticleHeader from "$lib/components/ArticleHeader.svelte";

  let {
    title,
    description,
    category,
    date,
    heroShader,
    heroHeading,
    heroShaderFocusX = 78,
    heroShaderFocusY = 42,
    heroShaderOffsetX = 0,
    heroShaderOpacity = 0.9,
    heroShaderFade = true,
    heroAlignment = "default",
    heroTone = "default",
    heroVariant = "default",
    children,
  }: {
    title: string;
    description: string;
    category: string;
    date: string;
    heroShader?: Snippet;
    heroHeading?: Snippet;
    heroShaderFocusX?: number;
    heroShaderFocusY?: number;
    heroShaderOffsetX?: number;
    heroShaderOpacity?: number;
    heroShaderFade?: boolean;
    heroAlignment?: "default" | "center";
    heroTone?: "default" | "inverse";
    heroVariant?: "default" | "saturated-p3";
    children: Snippet;
  } = $props();
</script>

<range-essay-page>
  <main class="essayPage">
    <article>
      <div class="heroOverlay" data-range-hero-overlay></div>

      <ArticleHeader
        {title}
        {description}
        {category}
        {date}
        shader={heroShader}
        heading={heroHeading}
        shaderFocusX={heroShaderFocusX}
        shaderFocusY={heroShaderFocusY}
        shaderOffsetX={heroShaderOffsetX}
        shaderOpacity={heroShaderOpacity}
        shaderFade={heroShaderFade}
        alignment={heroAlignment}
        tone={heroTone}
        variant={heroVariant}
      />

      <div class="essayBody">
        {@render children()}
      </div>
    </article>
  </main>
</range-essay-page>

<style>
  range-essay-page {
    display: block;
  }

  .essayPage {
    width: min(820px, calc(100% - 48px));
    padding-bottom: 96px;
  }

  article {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    grid-template-rows: auto auto;
  }

  article > :global(.articleHeader) {
    grid-area: 1 / 1;
  }

  .heroOverlay {
    position: sticky;
    z-index: 3;
    top: 20px;
    grid-column: 1;
    grid-row: 1 / 3;
    align-self: start;
    justify-self: end;
    display: flex;
    max-width: calc(100% - 40px);
    margin: 20px 20px 0;
    padding: 5px;
    overflow: hidden;
    border: 1px solid oklch(0.56 0 0 / 0.42);
    border-radius: 999px;
    background: oklch(1 0 0 / 0.055);
    box-shadow: 0 10px 28px oklch(0.05 0 0 / 0.16);
    backdrop-filter: blur(18px) saturate(1.12);
    -webkit-mask-image: linear-gradient(black, black);
    mask-image: linear-gradient(black, black);
  }

  .heroOverlay:empty {
    display: none;
  }

  .essayBody {
    grid-area: 2 / 1;
  }

  .essayBody {
    padding-top: 60px;
  }

  .essayBody :global(section + section) {
    margin-top: 64px;
  }

  .essayBody :global(h2) {
    margin: 0 0 18px;
    font-size: clamp(27px, 4vw, 38px);
    font-weight: 520;
    letter-spacing: -0.045em;
    line-height: 1.08;
  }

  .essayBody :global(p) {
    margin: 0;
    color: oklch(0.31 0.018 255);
    font-size: 17px;
    line-height: 1.72;
  }

  .essayBody :global(p + p) {
    margin-top: 20px;
  }

  .essayBody :global(range-code-block) {
    margin: 32px 0;
  }

  .essayBody :global(ul) {
    display: grid;
    gap: 12px;
    margin: 24px 0 0;
    padding-left: 22px;
    color: oklch(0.31 0.018 255);
    font-size: 16px;
    line-height: 1.6;
  }

  .essayBody :global(blockquote) {
    margin: 56px 0;
    padding: 28px 0 28px 28px;
    border-left: 2px solid var(--range);
    color: var(--ink);
    font-size: clamp(23px, 3.4vw, 32px);
    font-weight: 480;
    letter-spacing: -0.035em;
    line-height: 1.28;
  }

  .essayBody :global(code) {
    font-family: var(--font-geist-mono), monospace;
  }

  @media (max-width: 640px) {
    .essayPage {
      width: min(100% - 28px, 600px);
      padding-top: 0;
      padding-bottom: 72px;
    }

    .essayBody {
      padding-top: 44px;
    }

    .heroOverlay {
      top: 12px;
      max-width: calc(100% - 24px);
      margin: 12px 12px 0;
      padding: 4px;
    }

    .essayBody :global(section + section) {
      margin-top: 48px;
    }
  }
</style>
