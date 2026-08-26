<script lang="ts">
  import { githubUrl } from "$lib/benchmarks";

  let { indexed = false }: { indexed?: boolean } = $props();
</script>

<header class="landingNav siteHeader" class:indexed>
  <a class="landingWordmark" href="/" aria-label="Range home">
    {#if indexed}
      <span class="scaleAnchorStart" data-scale-zero aria-hidden="true"></span>
    {/if}
    <span class="rangeWord">Range</span>
  </a>
  <range-spline-nav role="navigation" aria-label="Primary navigation">
    <a href="/benchmarks">Benchmarks</a>
    <a href={githubUrl} target="_blank" rel="noreferrer">GitHub</a>
  </range-spline-nav>
</header>

<style>
  .siteHeader.landingNav {
    position: relative;
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: baseline;
    gap: 24px;
    margin-block-end: clamp(28px, 3vw, 40px);
    padding-inline-end: var(--page-gutter, 24px);
  }

  .siteHeader.landingNav.indexed {
    margin-block-end: 0;
  }

  .siteHeader .landingWordmark {
    justify-self: start;
    text-align: left;
  }

  .siteHeader range-spline-nav {
    display: flex;
    flex-wrap: nowrap;
    justify-self: end;
    gap: var(--page-gutter, 24px);
  }

  .siteHeader .landingWordmark {
    --range-wordmark-optical-shift: -0.05em;
    position: relative;
  }

  .scaleAnchorStart {
    position: absolute;
    bottom: 0;
    left: 0;
    width: 1px;
    height: 1px;
    pointer-events: none;
  }

  .siteHeader range-spline-nav > a + a {
    margin-inline-start: 0;
  }

  @media (max-width: 420px) {
    .siteHeader.landingNav {
      gap: var(--page-gutter, 14px);
      margin-block-end: 24px;
      padding-inline-end: 0;
    }

    .siteHeader.landingNav.indexed {
      margin-block-end: 0;
    }

    .siteHeader range-spline-nav {
      min-width: 0;
    }
  }

</style>
