import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const conversationPagePath = new URL(
  "../direct-renderer/app/webview/assets/local-conversation-page-BFpUCld2.js",
  import.meta.url,
);
const homePath = new URL(
  "../direct-renderer/app/webview/assets/app-initial-DJrCTPoN.js",
  import.meta.url,
);

async function readSwitcher() {
  const source = await readFile(conversationPagePath, "utf8");
  return source.slice(source.indexOf("function So(e)"), source.indexOf("function Co(e)"));
}

test("workspace controls stay centered over the measured trailing layout", async () => {
  const switcher = await readSwitcher();
  assert.match(switcher, /actionId: `local-thread-summary-panel-toggle`/);
  assert.match(switcher, /align: `center`/);
  assert.match(switcher, /unifiedSlotPosition: `right`/);
  assert.match(switcher, /querySelectorAll\(`\[data-app-shell-main-content-layout\]`\)/);
  assert.match(switcher, /target\.rect\.left - hostRect\.left \+ target\.rect\.width \/ 2/);
  assert.match(switcher, /transform: `translateX\(-50%\)`/);
  assert.match(switcher, /new ResizeObserver/);
  assert.match(switcher, /resizeObserver\.observe\(observedTarget\)/);
  assert.match(switcher, /resizeObserver\.observe\(observedCenterHost\)/);
  assert.match(switcher, /resizeObserver\.observe\(observedLeadingHost\)/);
});

test("Build uses the trailing slot leading edge and the native Codex chevron", async () => {
  const switcher = await readSwitcher();
  assert.match(switcher, /actionId: `local-thread-build-action`/);
  assert.match(switcher, /\[toolbarLeadingX, setToolbarLeadingX\]/);
  assert.match(switcher, /target\.rect\.left - leadingHostRect\.left \+ 12/);
  assert.match(switcher, /left: toolbarLeadingX == null \? 0 : `\$\{toolbarLeadingX\}px`/);
  assert.match(switcher, /children: `Build`/);
  assert.match(switcher, /NativeChevronDown/);
  assert.match(switcher, /className: `icon-2xs text-tertiary`/);
  assert.doesNotMatch(switcher, /children: `⌄`/);
  assert.match(switcher, /"aria-label": `Conversation view`/);
  assert.match(switcher, /role: `tablist`/);
  assert.match(switcher, /"aria-selected": chatVisible/);
  assert.match(switcher, /"aria-selected": summaryVisible/);
  assert.match(switcher, /children: `Chat`/);
  assert.match(switcher, /children: `Summary`/);
  assert.doesNotMatch(switcher, /selectWorkspaceView/);
  assert.doesNotMatch(switcher, /slice\(-2\)/);
  assert.doesNotMatch(switcher, /"aria-pressed": chatVisible/);
});

test("project filesystem stays locked while Build remains an execution dropdown", async () => {
  const switcher = await readSwitcher();
  assert.match(switcher, /hasProject = projectContext != null/);
  assert.match(switcher, /dataset\.rangeProjectBuildLocked = `true`/);
  assert.match(switcher, /delete document\.documentElement\.dataset\.rangeProjectBuildLocked/);
  assert.match(switcher, /"aria-expanded": buildMenuOpen/);
  assert.match(switcher, /onClick: \(\) => setBuildMenuOpen/);
  assert.match(switcher, /panelHidden\s+\? null\s+: \(0, Q\.jsx\)\(o\.HeaderAction/);
  assert.doesNotMatch(switcher, /if \(panelHidden\) return null/);
});

test("Chat fills the pane while selecting Summary replaces Chat", async () => {
  const source = await readFile(conversationPagePath, "utf8");
  const switcher = source.slice(source.indexOf("function So(e)"), source.indexOf("function Co(e)"));
  const conversation = source.slice(source.indexOf("function yo(e)"), source.indexOf("function bo(e)"));
  assert.match(switcher, /selectTrailingView = \(view\)/);
  assert.match(switcher, /replaceChatWithSummary: showSummary/);
  assert.match(switcher, /i = \(\) => selectTrailingView\(`chat`\)/);
  assert.match(switcher, /showSummary = \(\) => selectTrailingView\(`summary`\)/);
  assert.match(conversation, /summaryReplacesChat = rangeViewState\.replaceChatWithSummary === !0/);
  assert.match(conversation, /"data-range-pane": `chat`/);
  assert.match(conversation, /data-range-summary-replacement/);
  assert.doesNotMatch(conversation, /data-range-inline-summary/);
  assert.doesNotMatch(conversation, /data-range-chat-summary-separator/);
});

test("Build chooses Local or ChatGPT Work Cloud and applies the run location", async () => {
  const switcher = await readSwitcher();
  const home = await readFile(homePath, "utf8");
  assert.match(switcher, /"aria-label": `Build execution`/);
  assert.match(switcher, /role: `menu`/);
  assert.match(switcher, /chooseBuildMode\(`local`\)/);
  assert.match(switcher, /children: `Local`/);
  assert.match(switcher, /chooseBuildMode\(`cloud`\)/);
  assert.match(switcher, /children: `Cloud \(ChatGPT Work\)`/);
  assert.match(switcher, /buildRunLocation === `cloud` \? `Cloud` : `Local`/);
  assert.match(switcher, /role: `menuitemradio`/);
  assert.match(switcher, /rangeBuildRunLocation: runLocation/);
  assert.match(home, /requestedBuildRunLocation = D\?\.rangeBuildRunLocation/);
  assert.match(home, /n\.setWorkRunLocation\(requestedBuildRunLocation\)/);
  assert.match(home, /rangeBuildRunLocation, \.\.\.nextState/);
});

test("the conversation project resolver is passed into workspace controls", async () => {
  const source = await readFile(conversationPagePath, "utf8");
  const route = source.slice(source.indexOf("function Lo()"), source.indexOf("function Ro(e)"));
  const conversation = source.slice(source.indexOf("function yo(e)"), source.indexOf("function bo(e)"));
  assert.match(route, /let h = Ro\(m\)/);
  assert.match(route, /project: h/);
  assert.match(conversation, /project: projectContext/);
  assert.match(conversation, /project: projectContext,[\s\S]*?onOpenBackgroundAgent/);
});
