<script lang="ts">
  import CodabilitySheet from "$lib/components/CodabilitySheet.svelte";
</script>

<svelte:head>
  <title>Codability Under 100 · Range</title>
  <meta
    name="description"
    content="A line-by-line exploration of how Range implements Codable with graph queries, code expansion, splicing, and reusable nested macros."
  />
  <meta property="og:title" content="Codability Under 100 · Range" />
  <meta
    property="og:description"
    content="A line-by-line exploration of how Range implements Codable with graph queries, code expansion, splicing, and reusable nested macros."
  />
  <meta property="og:type" content="article" />
</svelte:head>

<main class="codabilityArticle">
  <header class="articleNav">
    <a href="/">Range</a>
    <span>Metaprogramming</span>
  </header>

  <article>
    <CodabilitySheet />
  </article>
</main>

<style>
  .codabilityArticle {
    padding-bottom: 0;
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

  .articleNav span {
    color: var(--muted);
    font-family: var(--font-geist-mono), monospace;
    font-size: 11px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
</style>
