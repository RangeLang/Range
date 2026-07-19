const shellSelector = "range-site-shell";
let navigationInFlight = false;

function nextFrame() {
  return new Promise((resolve) => requestAnimationFrame(resolve));
}

async function settleLayout() {
  await Promise.all([
    document.fonts.ready,
    customElements.whenDefined("range-scale"),
    customElements.whenDefined("range-optical-guide"),
  ]);
  await nextFrame();
  await nextFrame();
}

async function loadRoute(destination, historyMode) {
  if (navigationInFlight) return;
  navigationInFlight = true;

  try {
    const response = await fetch(destination, {
      headers: { accept: "text/html" },
    });
    if (!response.ok) throw new Error(`Navigation failed with ${response.status}`);

    const nextDocument = new DOMParser().parseFromString(await response.text(), "text/html");
    const currentShell = document.querySelector(shellSelector);
    const nextShell = nextDocument.querySelector(shellSelector);
    if (!currentShell || !nextShell) throw new Error("Range shell missing");

    const commit = async () => {
      currentShell.replaceChildren(...nextShell.cloneNode(true).childNodes);
      document.title = nextDocument.title;
      if (historyMode === "push") history.pushState({}, "", destination);
      scrollTo({ top: 0, left: 0, behavior: "instant" });
      await settleLayout();
    };

    if (typeof document.startViewTransition === "function") {
      await document.startViewTransition(commit).finished;
    } else {
      await commit();
    }
  } catch {
    location.assign(destination);
  } finally {
    navigationInFlight = false;
  }
}

document.addEventListener("click", (event) => {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  const anchor = event.composedPath().find((node) => node instanceof HTMLAnchorElement);
  if (!anchor || anchor.target || anchor.download || anchor.origin !== location.origin) return;
  const destination = new URL(anchor.href);
  if (destination.hash || destination.href === location.href) return;

  event.preventDefault();
  loadRoute(destination.href, "push");
});

addEventListener("popstate", () => loadRoute(location.href, "none"));
