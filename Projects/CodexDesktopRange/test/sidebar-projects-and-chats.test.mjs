import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(
  new URL("../direct-renderer/app/webview/assets/app-initial-DJrCTPoN.js", import.meta.url),
  "utf8",
);
const sidebar = source.slice(source.indexOf("function WJc(e)"), source.indexOf("function GJc(e)"));

test("Codex sidebar keeps saved projects visible and separates projectless chats", () => {
  assert.match(sidebar, /mode: T,/);
  assert.doesNotMatch(sidebar, /mode: a === `codex` \? `list` : T/);
  assert.match(sidebar, /defaultMessage: `Projects`/);
  assert.match(sidebar, /defaultMessage: `Chats`/);
  assert.match(sidebar, /heading: `Chats`/);
  assert.match(sidebar, /includeCodexProjects: s/);
  assert.match(sidebar, /a === `codex` && \(F = `all`\)/);
  assert.match(sidebar, /enabled: !0/);
  assert.match(sidebar, /includeChatGptProjects: !0/);
});
