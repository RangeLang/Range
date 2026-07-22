<script lang="ts">
  import "../../app/globals.css";

  let { children } = $props();
</script>

<svelte:head>
  <title>Range</title>
  <meta name="description" content="Native benchmark results for Range, C, C++, Rust, Go, and Swift, with compiler emission status." />
  <meta property="og:title" content="Range" />
  <meta property="og:description" content="Native benchmark results for Range, C, C++, Rust, Go, and Swift, with compiler emission status." />
  <meta property="og:type" content="website" />
  <meta property="og:image" content="/og-v3.png" />
  <meta name="twitter:card" content="summary_large_image" />
</svelte:head>

<range-site-shell>{@render children()}</range-site-shell>
