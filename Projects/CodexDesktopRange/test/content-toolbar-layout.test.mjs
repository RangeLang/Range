import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const rendererPath = new URL(
  "../direct-renderer/app/webview/assets/app-initial-DJrCTPoN.js",
  import.meta.url,
);
const stylesPath = new URL(
  "../direct-renderer/app/webview/assets/app-initial-NNCUNt29.css",
  import.meta.url,
);

test("content toolbar omits back and forward navigation controls", async () => {
  const [renderer, styles] = await Promise.all([
    readFile(rendererPath, "utf8"),
    readFile(stylesPath, "utf8"),
  ]);
  const controls = renderer.slice(renderer.indexOf("function cda(e)"), renderer.indexOf("function lda()"));

  assert.doesNotMatch(controls, /data-content-navigation-lane/);
  assert.doesNotMatch(controls, /onClick: uda/);
  assert.doesNotMatch(controls, /onClick: lda/);
  assert.doesNotMatch(controls, /navigationLaneRef/);
  assert.doesNotMatch(styles, /range-content-navigation-offset/);
});
