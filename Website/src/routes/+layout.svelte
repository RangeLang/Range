<script lang="ts">
  import "../../app/globals.css";

  const siteTitle = "Range — A Graph-Backed Programming Language";
  const siteDescription = "A love letter to electrons, logic and abstraction.";

  let { children } = $props();
</script>

<svelte:head>
  <title>{siteTitle}</title>
  <meta name="description" content={siteDescription} />
  <meta property="og:title" content={siteTitle} />
  <meta property="og:description" content={siteDescription} />
  <meta property="og:type" content="website" />
  <meta property="og:image" content="https://rangelang.org/og-v3.png" />
  <meta property="og:image:alt" content="Range programming language" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={siteTitle} />
  <meta name="twitter:description" content={siteDescription} />
</svelte:head>

<range-site-shell>{@render children()}</range-site-shell>
