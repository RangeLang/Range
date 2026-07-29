<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    title,
    description,
    category,
    date,
    children,
  }: {
    title: string;
    description: string;
    category: string;
    date: string;
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
      <header class="essayHero">
        <p class="eyebrow">{category} · {date}</p>
        <h1>{title}</h1>
        <p class="description">{description}</p>
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
    display: grid;
    gap: 24px;
    padding: 88px 0 64px;
    border-bottom: 1px solid var(--line);
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

    .essayBody {
      padding-top: 44px;
    }

    .essayBody :global(section + section) {
      margin-top: 48px;
    }
  }
</style>
