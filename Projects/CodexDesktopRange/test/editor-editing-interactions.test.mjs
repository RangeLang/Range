import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL(
    "../direct-renderer/app/webview/assets/text-file-editor-tab-content.electron-VsIQEixd.js",
    import.meta.url,
  ),
  "utf8",
);

test("the wrapper lets native editor input and clipboard handlers finish", () => {
  const surfaceStart = source.indexOf('"data-pierre-editor-surface"');
  const surface = source.slice(surfaceStart, surfaceStart + 2_000);

  assert.ok(surfaceStart >= 0, "editable surface should exist");
  assert.doesNotMatch(surface, /onBeforeInputCapture:/);
  assert.doesNotMatch(surface, /onCompositionEndCapture:/);
  assert.doesNotMatch(surface, /onCutCapture:/);
  assert.doesNotMatch(surface, /onPasteCapture:/);
  assert.match(surface, /onItemEditChange: \(e, t\) => at\(t, I\.canRedo, I\.canUndo\)/);
  assert.match(source, /He\.current\?\.updateContent\(e\.contents\)/);
});

test("the editor owns editable text and native clipboard events", () => {
  assert.match(source, /contentEditable: `true`/);
  assert.match(source, /W\(e, `copy`,/);
  assert.match(source, /W\(e, `cut`,/);
  assert.match(source, /W\(e, `paste`,/);
  assert.match(source, /W\(e, `beforeinput`,/);
});

test("Command-S saves without intercepting other editor shortcuts", () => {
  const keyHandlerStart = source.indexOf("onKeyDownCapture: (e) => {");
  const keyHandler = source.slice(keyHandlerStart, keyHandlerStart + 500);

  assert.match(keyHandler, /\(e\.metaKey \|\| e\.ctrlKey\) && t === `s`/);
  assert.match(keyHandler, /e\.preventDefault\(\), He\.current\?\.saveUntilClean\(\)/);
  assert.doesNotMatch(keyHandler, /markPotentiallyDirty/);
});
