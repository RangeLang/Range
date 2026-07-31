<script lang="ts">
  const articleUrl =
    "/posts/one-source-two-lenses?preview=range-draft";
</script>

<svelte:head>
  <title>Phone preview · One Source, Two Lenses</title>
</svelte:head>

<main class="previewStage" aria-label="Phone preview">
  <iframe
    class="phoneViewport"
    title="One Source, Two Lenses phone preview"
    src={articleUrl}
  ></iframe>
</main>

<style>
  .previewStage {
    box-sizing: border-box;
    display: grid;
    min-height: 100vh;
    place-items: start center;
    padding: 24px;
    background: oklch(0.94 0.006 255);
    overflow: auto;
  }

  .phoneViewport {
    width: 390px;
    height: 844px;
    max-width: 100%;
    border: 0;
    background: white;
    box-shadow:
      0 0 0 1px oklch(0.78 0.01 255),
      0 20px 60px oklch(0.25 0.02 255 / 0.18);
  }

  @media (max-width: 438px) {
    .previewStage {
      padding: 0;
    }

    .phoneViewport {
      width: 100%;
      box-shadow: none;
    }
  }
</style>
