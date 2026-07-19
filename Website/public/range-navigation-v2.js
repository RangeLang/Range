const shellSelector = "range-site-shell";
const routeCache = new Map();
let navigationInFlight = false;
let activeRoute = location.href;

function routeKey(destination) {
  const url = new URL(destination, location.href);
  return `${url.pathname}${url.search}`;
}

function routeDepth(destination) {
  const pathname = new URL(destination, location.href).pathname;
  if (pathname === "/") return 0;
  if (/^\/benchmarks\/[^/]+$/.test(pathname)) return 2;
  return 1;
}

function routeDirection(destination) {
  const currentDepth = routeDepth(activeRoute);
  const nextDepth = routeDepth(destination);
  if (nextDepth > currentDepth) return "forward";
  if (nextDepth < currentDepth) return "backward";
  return "lateral";
}

function isPerformanceTransition(destination) {
  const currentPath = new URL(activeRoute, location.href).pathname;
  const nextPath = new URL(destination, location.href).pathname;
  return (currentPath === "/" && nextPath === "/benchmarks")
    || (currentPath === "/benchmarks" && nextPath === "/");
}

function fetchRoute(destination) {
  const key = routeKey(destination);
  if (!routeCache.has(key)) {
    routeCache.set(key, fetch(destination, {
      headers: { accept: "text/html" },
    }).then(async (response) => {
      if (!response.ok) throw new Error(`Navigation failed with ${response.status}`);
      return new DOMParser().parseFromString(await response.text(), "text/html");
    }).catch((error) => {
      routeCache.delete(key);
      throw error;
    }));
  }
  return routeCache.get(key);
}

function anchorFromEvent(event) {
  return event.composedPath().find((node) => node instanceof HTMLAnchorElement);
}

function canHandle(anchor) {
  return Boolean(anchor && !anchor.target && !anchor.download && anchor.origin === location.origin);
}

function warmRoute(anchor) {
  if (!canHandle(anchor)) return;
  const destination = new URL(anchor.href);
  if (!destination.hash && destination.href !== location.href) fetchRoute(destination.href).catch(() => {});
}

async function loadRoute(destination, historyMode) {
  if (navigationInFlight) return;
  navigationInFlight = true;
  const direction = routeDirection(destination);
  const transitionClass = `range-route-${direction}`;
  const routeClasses = [transitionClass];
  if (isPerformanceTransition(destination)) routeClasses.push("range-route-performance");

  try {
    const nextDocument = await fetchRoute(destination);
    const currentShell = document.querySelector(shellSelector);
    const nextShell = nextDocument.querySelector(shellSelector);
    if (!currentShell || !nextShell) throw new Error("Range shell missing");

    const commit = () => {
      currentShell.replaceChildren(...nextShell.cloneNode(true).childNodes);
      document.title = nextDocument.title;
      if (historyMode === "push") history.pushState({}, "", destination);
      activeRoute = destination;
      scrollTo({ top: 0, left: 0, behavior: "instant" });
    };

    if (typeof document.startViewTransition === "function") {
      document.documentElement.classList.add(...routeClasses);
      await document.startViewTransition(commit).finished;
    } else {
      commit();
    }
  } catch {
    location.assign(destination);
  } finally {
    document.documentElement.classList.remove(...routeClasses);
    navigationInFlight = false;
  }
}

document.addEventListener("pointerover", (event) => warmRoute(anchorFromEvent(event)), { passive: true });
document.addEventListener("focusin", (event) => warmRoute(anchorFromEvent(event)));

document.addEventListener("click", (event) => {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  const anchor = anchorFromEvent(event);
  if (!canHandle(anchor)) return;
  const destination = new URL(anchor.href);
  if (destination.hash || destination.href === location.href) return;

  event.preventDefault();
  loadRoute(destination.href, "push");
});

addEventListener("popstate", () => loadRoute(location.href, "none"));

const likelyNextRoute = location.pathname === "/" ? "/benchmarks" : "/";
const warmLikelyRoute = () => fetchRoute(likelyNextRoute).catch(() => {});
if ("requestIdleCallback" in window) requestIdleCallback(warmLikelyRoute, { timeout: 1200 });
else setTimeout(warmLikelyRoute, 250);
