<script lang="ts">
  import { beforeNavigate } from "$app/navigation";
  import { page, updated } from "$app/state";
  import { onMount, setContext } from "svelte";
  import {
    createRangeSoundManager,
    RANGE_SOUND_MANAGER_CONTEXT,
  } from "$lib/audio/sound-manager";
  import {
    createRangeLayoutTracker,
    RANGE_LAYOUT_TRACKER_CONTEXT,
  } from "$lib/layout/layout-tracker";
  import {
    createRangeOnboardingMachine,
    RANGE_ONBOARDING_MACHINE_CONTEXT,
  } from "$lib/interaction/onboarding-machine";
  import { postForPath, postImageUrl } from "$lib/posts";
  import Footer from "$lib/components/Footer.svelte";
  import SiteHeader from "$lib/components/SiteHeader.svelte";
  import SoundOnboarding from "$lib/components/SoundOnboarding.svelte";
  import "sveltely/style.css";
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
  let isHome = $derived(page.url.pathname === "/");
  let isPreview = $derived(page.url.pathname.startsWith("/__preview/"));
  let isOgCard = $derived(page.url.pathname.startsWith("/__og-card/"));
  let isError = $derived(page.status >= 400);
  let hasCompactHeader = $derived(page.url.pathname.startsWith("/posts/"));

  const soundManager = createRangeSoundManager();
  const layoutTracker = createRangeLayoutTracker();
  const onboardingMachine = createRangeOnboardingMachine();
  setContext(RANGE_SOUND_MANAGER_CONTEXT, soundManager);
  setContext(RANGE_LAYOUT_TRACKER_CONTEXT, layoutTracker);
  setContext(RANGE_ONBOARDING_MACHINE_CONTEXT, onboardingMachine);
  if (typeof window !== "undefined") {
    window.__rangeSoundManager = soundManager;
    window.__rangeLayoutTracker = layoutTracker;
  }

  let { children } = $props();

  beforeNavigate(({ willUnload, to }) => {
    if (updated.current && !willUnload && to?.url) {
      window.location.href = to.url.href;
    }
  });

  onMount(() => {
    let resumeSoundOnFocus = false;
    const leaveWindow = () => {
      if (!soundManager.isEnabled()) return;
      resumeSoundOnFocus = true;
      soundManager.setEnabled(false);
    };
    const enterWindow = () => {
      if (
        !resumeSoundOnFocus
        || document.hidden
        || !document.hasFocus()
      ) return;
      resumeSoundOnFocus = false;
      soundManager.setEnabled(true);
    };
    const handleVisibility = () => {
      if (document.hidden) leaveWindow();
      else enterWindow();
    };

    window.addEventListener("blur", leaveWindow);
    window.addEventListener("focus", enterWindow);
    document.addEventListener("visibilitychange", handleVisibility);

    return () => {
      window.removeEventListener("blur", leaveWindow);
      window.removeEventListener("focus", enterWindow);
      document.removeEventListener("visibilitychange", handleVisibility);
      if (window.__rangeSoundManager === soundManager) {
        delete window.__rangeSoundManager;
      }
      if (window.__rangeLayoutTracker === layoutTracker) {
        delete window.__rangeLayoutTracker;
      }
      soundManager.dispose();
      layoutTracker.dispose();
    };
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
  {#if !isPreview && isHome}
    <SoundOnboarding />
  {/if}
  <range-site-content data-range-site-content>
    {#if !isHome && !isPreview && !isOgCard && !isError}
      <div class="persistentSiteHeader" class:compact={hasCompactHeader}>
        <SiteHeader />
      </div>
    {/if}
    <range-route-view>
      {@render children()}
    </range-route-view>
    {#if !isPreview && !isOgCard && !isError}
      <Footer />
    {/if}
  </range-site-content>
</range-site-shell>

<style>
  .persistentSiteHeader {
    --page-gutter: 24px;
    width: min(1180px, calc(100% - (2 * var(--page-gutter))));
    margin: 0 auto;
    padding-top: 48px;
    transition: width 760ms cubic-bezier(0.16, 1, 0.3, 1);
  }

  .persistentSiteHeader.compact {
    width: min(820px, calc(100% - (2 * var(--page-gutter))));
  }

  @media (max-width: 640px) {
    .persistentSiteHeader {
      --page-gutter: 14px;
      padding-top: 28px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .persistentSiteHeader {
      transition: none;
    }
  }
</style>
