<script lang="ts">
  import CodabilitySheet from "$lib/components/CodabilitySheet.svelte";
  import SiteHeader from "$lib/components/SiteHeader.svelte";
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
  <SiteHeader />

  <article>
    <CodabilitySheet />
  </article>
</main>

<style>
  .codabilityArticle {
    padding-bottom: 0;
  }

</style>
