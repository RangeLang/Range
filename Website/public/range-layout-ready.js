const root = document.documentElement;

function reveal() {
  root.classList.remove("range-layout-pending");
}

const failSafe = window.setTimeout(reveal, 2500);

async function waitForLayout() {
  await Promise.all([
    document.fonts.load('500 1em "Geist"'),
    document.fonts.load('500 1em "Geist Mono"'),
    document.fonts.ready,
    customElements.whenDefined("range-scale"),
    customElements.whenDefined("range-optical-guide"),
  ]);

  await new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  });

  window.clearTimeout(failSafe);
  reveal();
}

waitForLayout().catch(reveal);
