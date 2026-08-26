<script lang="ts">
  import HomePageContent from "$lib/components/HomePageContent.svelte";
  import SkyShader from "$lib/components/SkyShader.svelte";
</script>

<svelte:head>
  <title>Onboarding sky + homepage — Range preview</title>
</svelte:head>

<div class="statePreview" data-preview="onboarding-sky-content">
  <div class="sky" aria-hidden="true">
    <SkyShader />
  </div>
  <div class="homepage">
    <HomePageContent />
  </div>
</div>

<style>
  :global(html),
  :global(body),
  :global(range-site-shell),
  :global(range-route-view) {
    min-height: 100%;
    background: oklch(0.024 0.014 265);
  }

  .statePreview {
    position: relative;
    min-height: 100vh;
    overflow: hidden;
    background: oklch(0.024 0.014 265);
  }

  .sky {
    position: fixed;
    inset: 0;
    z-index: 0;
    pointer-events: none;
  }

  .homepage {
    position: relative;
    z-index: 1;
  }

  .homepage :global([data-range-home-page]) {
    --ink: oklch(1 0 0);
    --muted: oklch(0.9 0.012 255);
    --line: oklch(0.72 0.025 255 / 0.58);
    --paper: transparent;
    color: var(--ink);
  }

  .homepage :global([data-range-home-page] :where(
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    p,
    a,
    span,
    strong,
    small,
    button,
    time,
    code
  )) {
    color: inherit;
  }

  .homepage :global([data-range-layout="range-title-canvas"]),
  .homepage :global(range-scale),
  .homepage :global(range-optical-guide) {
    filter: brightness(0) invert(1);
  }

  .homepage :global(.primaryAction),
  .homepage :global(.secondaryAction) {
    border-color: oklch(1 0 0 / 0.48);
    background: oklch(1 0 0 / 0.07);
  }

  @media (max-width: 720px) {
    .statePreview {
      min-height: 100svh;
    }
  }
</style>
