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
  import { isSearchPrivatePath, seoForPath } from "$lib/seo";
  import Footer from "$lib/components/Footer.svelte";
  import SiteHeader from "$lib/components/SiteHeader.svelte";
  import SoundOnboarding from "$lib/components/SoundOnboarding.svelte";
  import "sveltely/style.css";
  import "../../app/globals.css";

  let seo = $derived(seoForPath(page.url.pathname));
  let searchPrivate = $derived(
    isSearchPrivatePath(page.url.pathname) || page.status >= 400,
  );
  let structuredData = $derived(
    seo?.structuredData
      ? JSON.stringify(seo.structuredData).replaceAll("<", "\\u003c")
      : "",
  );
  let isHome = $derived(page.url.pathname === "/");
  let isPreview = $derived(page.url.pathname.startsWith("/__preview/"));
  let isOgCard = $derived(page.url.pathname.startsWith("/__og-card/"));
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
  {#if seo}
    <title>{seo.title}</title>
    <meta name="description" content={seo.description} />
    {#if seo.canonicalUrl}
      <link rel="canonical" href={seo.canonicalUrl} />
      <meta property="og:url" content={seo.canonicalUrl} />
    {/if}
    <meta property="og:site_name" content="Range" />
    <meta property="og:title" content={seo.title} />
    <meta property="og:description" content={seo.description} />
    <meta property="og:type" content={seo.openGraphType} />
    <meta property="og:image" content={seo.image} />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta property="og:image:alt" content={seo.imageAlt} />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content={seo.title} />
    <meta name="twitter:description" content={seo.description} />
    <meta name="twitter:image" content={seo.image} />
    <meta name="twitter:image:alt" content={seo.imageAlt} />
  {/if}
  {#if searchPrivate}
    <meta name="robots" content="noindex, nofollow" />
  {/if}
  {#if structuredData}
    {@html `<script type="application/ld+json">${structuredData}</script>`}
  {/if}
</svelte:head>

<range-site-shell>
  {#if !isPreview && isHome}
    <SoundOnboarding />
  {/if}
  <range-site-content data-range-site-content>
    {#if !isHome && !isPreview && !isOgCard}
      <div class="persistentSiteHeader" class:compact={hasCompactHeader}>
        <SiteHeader />
      </div>
    {/if}
    <range-route-view>
      {@render children()}
    </range-route-view>
    {#if !isPreview && !isOgCard}
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
