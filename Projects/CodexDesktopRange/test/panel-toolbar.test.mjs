import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL("../direct-renderer/app/webview/assets/app-initial-DJrCTPoN.js", import.meta.url),
  "utf8",
);

test("right panel toolbar omits the expand-panel button", () => {
  const toolbar = source.slice(source.indexOf("function Oca()"), source.indexOf("var Aca"));
  assert.doesNotMatch(toolbar, /jsx\)\(Cca/);
  assert.match(toolbar, /children: \[t, g\]/);
});
