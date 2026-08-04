const root = document.documentElement;

function reveal() {
  window.dispatchEvent(new Event("range-layout-ready"));
  root.classList.remove("range-layout-pending");
}

const failSafe = window.setTimeout(reveal, 2500);

function hasFontFamily(family) {
  return [...document.fonts].some((face) =>
    face.family.replaceAll('"', "").replaceAll("'", "") === family
  );
}

async function waitForFontFaces() {
  while (!hasFontFamily("Geist") || !hasFontFamily("Geist Mono")) {
    await new Promise((resolve) => requestAnimationFrame(resolve));
  }

  await Promise.all([
    document.fonts.load('500 1em "Geist"'),
    document.fonts.load('500 1em "Geist Mono"'),
  ]);
  await document.fonts.ready;
}

async function waitForLayout() {
  await Promise.all([
    waitForFontFaces(),
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
