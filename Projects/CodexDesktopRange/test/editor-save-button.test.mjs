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

test("editable files use a deliberate Save/Saved toolbar control", () => {
  const label = source.indexOf('"aria-label": hasUnsavedChanges');
  const button = source.slice(label, label + 2_500);

  assert.ok(label >= 0, "save control should exist");
  assert.match(button, /right-3 top-3/);
  assert.match(button, /color: hasUnsavedChanges \? "primary" : "ghost"/);
  assert.match(button, /hasUnsavedChanges \? "Save" : "Saved"/);
  assert.match(button, /className: "icon-xs shrink-0"/);
  assert.doesNotMatch(button, /disabled:/);
  assert.doesNotMatch(button, /children: "Save"/);
});

test("save state is driven by the controller change callback", () => {
  assert.match(
    source,
    /\[hasUnsavedChanges, setHasUnsavedChanges\] = \(0, J\.useState\)\(!1\)/,
  );
  assert.match(
    source,
    /Ft = R\(\(e\) => \{\s*\(setHasUnsavedChanges\(e\), te\(e\)\);\s*\}\)/,
  );
  assert.doesNotMatch(source, /He\.current\?\.hasUnsavedChanges/);
});
