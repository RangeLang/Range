<script lang="ts">
  import type { Snippet } from "svelte";
  import SphereLineShader from "$lib/components/SphereLineShader.svelte";

  let {
    title,
    description,
    category,
    date,
    heroShaderPalette,
    children,
  }: {
    title: string;
    description: string;
    category: string;
    date: string;
    heroShaderPalette?: number;
    children: Snippet;
  } = $props();
</script>

<svelte:head>
  <title>{title} · Range</title>
  <meta name="description" content={description} />
  <meta property="og:title" content={`${title} · Range`} />
  <meta property="og:description" content={description} />
  <meta property="og:type" content="article" />
</svelte:head>

<range-essay-page>
  <main class="essayPage">
    <header class="articleNav">
      <a href="/">Range</a>
      <span>{category}</span>
    </header>

    <article>
      <header class="essayHero" class:hasShader={heroShaderPalette !== undefined}>
        {#if heroShaderPalette !== undefined}
          <div class="heroShader">
            <SphereLineShader palette={heroShaderPalette} />
          </div>
        {/if}
        <div class="heroCopy">
          <p class="eyebrow">{category} · {date}</p>
          <h1>{title}</h1>
          <p class="description">{description}</p>
        </div>
      </header>

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

  .articleNav {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 24px;
    padding-bottom: 24px;
    border-bottom: 1px solid var(--line);
  }

  .articleNav a {
    color: var(--ink);
    font-size: 20px;
    font-weight: 600;
    letter-spacing: -0.04em;
    text-decoration: none;
  }

  .articleNav a:hover,
  .articleNav a:focus-visible {
    color: var(--range);
    outline: none;
  }

  .articleNav span,
  .eyebrow {
    color: var(--muted);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .essayHero {
    position: relative;
    display: grid;
    gap: 24px;
    padding: 88px 0 64px;
    overflow: hidden;
    border-bottom: 1px solid var(--line);
  }

  .essayHero.hasShader {
    min-height: 380px;
    align-items: end;
    margin-top: 0;
    padding: 88px 0 56px;
    border-bottom: 1px solid var(--line);
    isolation: isolate;
  }

  .heroShader {
    position: absolute;
    inset: 28px -18vw 0 30%;
    z-index: 0;
    overflow: hidden;
    opacity: 0.9;
    -webkit-mask-image: linear-gradient(90deg, transparent, black 32%);
    mask-image: linear-gradient(90deg, transparent, black 32%);
  }

  .heroShader::after {
    position: absolute;
    inset: 0;
    background:
      linear-gradient(
        180deg,
        oklch(1 0 0 / 0.18),
        oklch(1 0 0 / 0.22) 58%,
        oklch(1 0 0 / 0.94)
      ),
      linear-gradient(
        90deg,
        oklch(1 0 0 / 0.94),
        oklch(1 0 0 / 0.42) 42%,
        transparent 76%
      );
    content: "";
  }

  .heroShader :global(canvas) {
    position: absolute;
    inset: 0;
  }

  .heroCopy {
    position: relative;
    z-index: 1;
    display: grid;
    gap: 24px;
  }

  .eyebrow,
  .essayHero h1,
  .description {
    margin: 0;
  }

  .essayHero h1 {
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
    color: color-mix(in oklch, var(--ink), transparent 14%);
  }

  .essayHero.hasShader h1 {
    max-width: 680px;
    font-size: clamp(44px, 6vw, 66px);
    line-height: 0.98;
  }

  .essayHero.hasShader .description {
    max-width: 560px;
    font-size: clamp(18px, 2.2vw, 22px);
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
      padding-top: 28px;
      padding-bottom: 72px;
    }

    .essayHero {
      gap: 20px;
      padding: 64px 0 48px;
    }

    .essayHero.hasShader {
      min-height: 340px;
      margin-top: 0;
      padding: 64px 0 40px;
    }

    .heroShader {
      inset: 16px -48px 0 18%;
      opacity: 0.7;
    }

    .heroCopy {
      gap: 20px;
    }

    .essayBody {
      padding-top: 44px;
    }

    .essayBody :global(section + section) {
      margin-top: 48px;
    }
  }
</style>
