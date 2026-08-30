import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const headerPath = new URL(
  "../direct-renderer/app/webview/assets/artifact-preview-header-Drf1s0S4.js",
  import.meta.url,
);
const treePath = new URL(
  "../direct-renderer/app/webview/assets/review-file-tree-pane-Dg3636o1.js",
  import.meta.url,
);

test("artifact preview omits the external Open split button", async () => {
  const source = await readFile(headerPath, "utf8");
  assert.match(
    source,
    /function ye\(e\) \{\s*\/\/ Range removes[\s\S]*?return null;/,
  );
});

test("file tree omits external Open context-menu actions", async () => {
  const source = await readFile(treePath, "utf8");
  const menu = source.slice(source.indexOf("function Ne("), source.indexOf("function Le("));
  assert.doesNotMatch(menu, /Open in|Open with|open-in/);
});
