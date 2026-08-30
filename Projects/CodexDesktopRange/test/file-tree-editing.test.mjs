import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(
  new URL(
    "../direct-renderer/app/webview/assets/review-file-tree-pane-Dg3636o1.js",
    import.meta.url,
  ),
  "utf8",
);

test("workspace tree exposes the complete editing context menu", () => {
  for (const item of ["New File…", "New Folder…", "Rename…", "Delete…"]) {
    assert.match(source, new RegExp(item.replace("…", "\\u2026"), "u"));
  }
});

test("workspace tree context menu uses editing-first ordering", () => {
  const menu = source.slice(source.indexOf("function Ne("), source.indexOf("function Le("));
  const orderedIds = [
    "file-tree-new-file",
    "file-tree-new-folder",
    "file-tree-rename",
    "file-tree-delete",
    "file-tree-secondary-separator",
    "save-as",
    "copy-path",
    "add-to-chat",
  ];
  let previous = -1;
  for (const id of orderedIds) {
    const current = menu.indexOf(`id: \`${id}\``);
    assert.ok(current > previous, `${id} should follow the previous menu item`);
    previous = current;
  }
  assert.doesNotMatch(menu, /Open in|Open with|open-in/);
});

test("workspace tree context-menu actions have icons", () => {
  for (const icon of [
    "saveAs",
    "copyPath",
    "addToChat",
    "newFile",
    "newFolder",
    "rename",
    "delete",
  ]) {
    assert.match(source, new RegExp(`icon: contextMenuIcons\\.${icon}`));
  }
});

test("workspace tree guards destructive and conflicting mutations", () => {
  assert.match(source, /window\.confirm\(`Delete/);
  assert.match(source, /This cannot be undone/);
  assert.match(source, /ifMatch: `missing`/);
  assert.match(source, /Names cannot contain path separators/);
  assert.match(source, /sendRequest\(`fs\/remove`/);
});

test("workspace tree refreshes after every mutation", () => {
  assert.match(source, /async function refreshWorkspaceTree/);
  assert.ok(source.match(/await refreshWorkspaceTree\(scope\)/g)?.length >= 3);
});

test("folder rename recursively copies the resolved tree path before removal", () => {
  assert.match(source, /async function copyWorkspaceItem/);
  assert.match(source, /sendRequest\(`fs\/getMetadata`, \{ path: sourcePath \}\)/);
  assert.match(source, /sendRequest\(`fs\/readDirectory`, \{ path: sourcePath \}\)/);
  assert.match(source, /sendRequest\(`fs\/createDirectory`, \{ path: destinationPath, recursive: !1 \}\)/);
  assert.match(source, /await copyWorkspaceItem\(client, sourcePath, destinationPath, isWindowsHost\)/);
});

test("rename and delete use the resolved path rather than the flattened display path", () => {
  assert.match(source, /targetPath: e,[\s\S]*?return Ne\(/);
  assert.match(source, /renameWorkspaceItem\(\{ hostId, isWindowsHost, scope, targetPath: sourcePath \}\)/);
  assert.match(
    source,
    /deleteWorkspaceItem\(\{ hostId, isWindowsHost, scope, targetPath: path \}\)/,
  );
  assert.doesNotMatch(
    source.slice(source.indexOf("async function renameWorkspaceItem"), source.indexOf("var Re =")),
    /targetPathByDisplayPath: new Map\(\)/,
  );
});

test("folder rows become context-menu targets", () => {
  const targetResolver = source.slice(source.indexOf("function ze(e)"), source.indexOf("var Be ="));

  assert.match(targetResolver, /\[`file`, `folder`\]\.includes\(t\.getAttribute\(`data-item-type`\)\)/);
  assert.match(source, /async function deleteWorkspaceItem\(\{ hostId, isWindowsHost, scope, targetPath: path \}\)/);
});

test("files and folders are draggable move sources", () => {
  assert.match(source, /function installWorkspaceTreeDragAndDrop/);
  assert.match(
    source,
    /querySelectorAll\(\s*`\[data-item-type='file'\], \[data-item-type='folder'\]`/,
  );
  assert.match(source, /row\.setAttribute\(`draggable`, `true`\)/);
  assert.match(source, /root\.addEventListener\(`dragstart`, onDragStart\)/);
  assert.match(source, /event\.dataTransfer\.effectAllowed = `move`/);
});

test("drop destinations move through the guarded workspace mutation path", () => {
  assert.match(source, /function canMoveWorkspaceItem/);
  assert.match(source, /isDirectory && destination\.startsWith\(`\$\{source\}\/`\)/);
  assert.match(source, /async function moveWorkspaceItem/);
  assert.match(source, /await copyWorkspaceItem\(client, sourcePath, destinationPath, isWindowsHost\)/);
  assert.match(
    source,
    /sendRequest\(`fs\/remove`, \{ path: sourcePath, force: !0, recursive: !0 \}\)/,
  );
  assert.match(source, /await refreshWorkspaceTree\(scope\)/);
  assert.match(source, /root\.addEventListener\(`dragover`, onDragOver\)/);
  assert.match(source, /root\.addEventListener\(`drop`, onDrop\)/);
});

test("drag and drop exposes source and destination feedback", () => {
  assert.match(source, /\[data-workspace-drag-source='true'\]/);
  assert.match(source, /\[data-workspace-drop-target='true'\]/);
  assert.match(source, /box-shadow: inset 0 0 0 1px var\(--color-ring\)/);
  assert.match(source, /new MutationObserver\(prepareRows\)/);
});
