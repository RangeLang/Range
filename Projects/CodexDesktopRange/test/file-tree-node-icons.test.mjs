import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL(
    "../direct-renderer/app/webview/assets/review-file-tree-pane-Dg3636o1.js",
    import.meta.url,
  ),
  "utf8",
);

test("folder node icons replace disclosure chevrons without changing row expansion", () => {
  assert.match(source, /const workspaceTreeNodeIcons = \{/);
  assert.match(
    source,
    /\[data-item-type='folder'\][\s\S]*?\[data-icon-name='file-tree-icon-chevron'\][\s\S]*?display: none !important/,
  );
  assert.match(
    source,
    /\[data-item-type='folder'\]\[aria-expanded='true'\][\s\S]*?workspaceTreeNodeIcons\.folderOpen/,
  );
  assert.match(source, /\[data-item-type='folder'\] > \[data-item-section='icon'\]::before/);
  assert.doesNotMatch(
    source,
    /\[data-item-type='file'\][\s\S]{0,200}\[data-icon-name='file-tree-icon-file'\][\s\S]{0,100}display: none/,
  );
});

test("common workspace folder types receive distinct system-style symbols", () => {
  for (const icon of ["git", "repository", "range", "build", "code", "test", "terminal", "package"])
    assert.match(source, new RegExp(`workspaceTreeNodeIcons\\.${icon}`));

  for (const path of [".git", ".github", ".range", "build", "sources", "tests", "scripts", "package"])
    assert.match(source, new RegExp(`data-item-path\\$='${path.replace(".", "\\.")}'`, "i"));
});

test("node symbols inherit the current macOS-style monochrome tree color", () => {
  assert.match(source, /background-color: currentColor/);
  assert.match(source, /-webkit-mask: var\(--workspace-tree-node-icon\)/);
  assert.match(source, /stroke="black" stroke-width="1\.35"/);
});
