<script lang="ts">
  import { page } from "$app/state";
  import { onMount, setContext } from "svelte";
  import {
    createRangeSoundManager,
    RANGE_SOUND_MANAGER_CONTEXT,
  } from "$lib/audio/sound-manager";
  import {
    createRangeLayoutTracker,
    RANGE_LAYOUT_TRACKER_CONTEXT,
  } from "$lib/layout/layout-tracker";
  import { postForPath, postImageUrl } from "$lib/posts";
  import Footer from "$lib/components/Footer.svelte";
  import "../../app/globals.css";

  const siteTitle = "Range — An Applied Programming Language";
  const siteDescription = "A love letter to electrons, logic and abstraction.";
  const defaultImage = "https://rangelang.org/og-homepage.png";
  let activePost = $derived(postForPath(page.url.pathname));
  let socialImage = $derived(activePost ? postImageUrl(activePost) : defaultImage);
  let socialImageAlt = $derived(
    activePost
      ? `${activePost.cardTitle} — ${activePost.cardDescription}`
      : "Range — an applied programming language",
  );

  const soundManager = createRangeSoundManager();
  const layoutTracker = createRangeLayoutTracker();
  setContext(RANGE_SOUND_MANAGER_CONTEXT, soundManager);
  setContext(RANGE_LAYOUT_TRACKER_CONTEXT, layoutTracker);
  if (typeof window !== "undefined") {
    window.__rangeSoundManager = soundManager;
    window.__rangeLayoutTracker = layoutTracker;
  }

  let { children } = $props();

  onMount(() => () => {
    if (window.__rangeSoundManager === soundManager) {
      delete window.__rangeSoundManager;
    }
    if (window.__rangeLayoutTracker === layoutTracker) {
      delete window.__rangeLayoutTracker;
    }
    soundManager.dispose();
    layoutTracker.dispose();
  });
</script>

<svelte:head>
  <title>{siteTitle}</title>
  <meta name="description" content={siteDescription} />
  <meta property="og:title" content={siteTitle} />
  <meta property="og:description" content={siteDescription} />
  <meta property="og:type" content="website" />
  <meta property="og:image" content={socialImage} />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:alt" content={socialImageAlt} />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={siteTitle} />
  <meta name="twitter:description" content={siteDescription} />
  <meta name="twitter:image" content={socialImage} />
  <meta name="twitter:image:alt" content={socialImageAlt} />
</svelte:head>

<range-site-shell>
  {@render children()}
  <Footer />
</range-site-shell>
