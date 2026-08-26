<script lang="ts">
  import PostCard from "$lib/components/PostCard.svelte";

  let { data } = $props();
</script>

<svelte:head>
  <title>{data.post.cardTitle} social card</title>
  <meta name="robots" content="noindex, nofollow" />
</svelte:head>

<range-social-card>
  <PostCard post={data.post} still social />
</range-social-card>

<style>
  range-social-card {
    width: 1200px;
    height: 630px;
    display: block;
    overflow: hidden;
  }

  :global(body:has(range-social-card)) {
    width: 1200px;
    height: 630px;
    overflow: hidden;
  }
</style>
