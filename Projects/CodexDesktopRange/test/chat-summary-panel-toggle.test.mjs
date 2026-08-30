import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL(
    "../direct-renderer/app/webview/assets/thread-app-shell-chrome-CXa8yzv0.js",
    import.meta.url,
  ),
  "utf8",
);

test("top-right panel toggle hides Chat/Summary instead of the editor", () => {
  const start = source.indexOf("function Fi()");
  const end = source.indexOf("function Ii()", start);
  const toggle = source.slice(start, end);

  assert.ok(start >= 0 && end > start, "panel toggle component should exist");
  assert.match(toggle, /defaultMessage: `Toggle Chat\/Summary panel`/);
  assert.match(
    toggle,
    /n \? \{ mode: `split`, contentSide: e\.get\(d\) \} : \{ mode: `full` \}/,
  );
  assert.match(toggle, /K\(`toggleSidePanel`, c, \{ enabled: s != null \}\)/);
  assert.doesNotMatch(toggle, /At\(e\)|At\(t\)/);
});

test("project Build locks the file browser against toggle and close actions", () => {
  const start = source.indexOf("function Ti(e)");
  const end = source.indexOf("function Ei(e)", start);
  const toggle = source.slice(start, end);

  assert.match(toggle, /codex-range-close-file-browser/);
  assert.match(toggle, /codex-range-file-browser-visibility/);
  assert.match(toggle, /dataset\.rangeProjectBuildLocked !== `true` && S\(\)/);
  assert.match(toggle, /dataset\.rangeProjectBuildLocked === `true`/);
  assert.match(toggle, /detail: \{ visible: !0 \}/);
  assert.match(toggle, /window\.addEventListener/);
  assert.match(toggle, /window\.removeEventListener/);
});
