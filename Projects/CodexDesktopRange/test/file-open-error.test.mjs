import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const editorPath = new URL(
  "../direct-renderer/app/webview/assets/text-file-editor-tab-content.electron-VsIQEixd.js",
  import.meta.url,
);

test("missing restored files report inline without duplicate global toasts", async () => {
  const source = await readFile(editorPath, "utf8");
  const tabSetup = source.slice(source.indexOf("function zb(e)"), source.indexOf("var Bb,"));

  assert.match(source, /id: `pierreFileEditor\.loadError`/);
  assert.match(source, /defaultMessage: `Could not open file`/);
  assert.match(tabSetup, /Range keeps missing restored files as an inline editor state/);
  assert.doesNotMatch(tabSetup, /id: `textFileEditor\.openError`/);
  assert.match(tabSetup, /id: `textFileEditor\.saveError`/);
});
