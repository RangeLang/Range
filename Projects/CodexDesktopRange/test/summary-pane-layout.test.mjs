import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const appInitial = readFileSync(
  new URL(
    "../direct-renderer/app/webview/assets/app-initial-DJrCTPoN.js",
    import.meta.url,
  ),
  "utf8",
);
const conversationPage = readFileSync(
  new URL(
    "../direct-renderer/app/webview/assets/local-conversation-page-BFpUCld2.js",
    import.meta.url,
  ),
  "utf8",
);

test("summary pane fills its host instead of using the floating card surface", () => {
  assert.match(appInitial, /value: i \? `pane` : !0/);
  assert.match(
    appInitial,
    /t === `pane`[\s\S]*?`relative flex h-full min-h-0 w-full min-w-0 flex-1 flex-col overflow-hidden`/,
  );
  assert.match(
    appInitial,
    /i \? \{ width: `100%`, height: `100%` \} : \{ width: 300 \}/,
  );
});

test("Chat fills the pane without rendering Summary beside it", () => {
  assert.match(
    conversationPage,
    /"data-range-summary-screen": summaryReplacesChat,[\s\S]*?"data-range-pane": `chat`/,
  );
  assert.match(conversationPage, /relative flex h-full min-h-0 w-full/);
  assert.match(
    conversationPage,
    /"data-range-pane": `chat`,[\s\S]*?relative h-full min-h-0 w-full min-w-0 flex-1 overflow-hidden/,
  );
  assert.doesNotMatch(conversationPage, /data-range-inline-summary/);
  assert.doesNotMatch(conversationPage, /data-range-chat-summary-separator/);
  assert.doesNotMatch(conversationPage, /"data-range-pane": `summary`/);
});

test("the obsolete Chat and Summary split-resize state is removed", () => {
  assert.doesNotMatch(conversationPage, /inlineSummaryWidth/);
  assert.doesNotMatch(conversationPage, /beginInlineSummaryResize/);
  assert.doesNotMatch(conversationPage, /resizeInlineSummaryWithKeyboard/);
  assert.doesNotMatch(conversationPage, /Resize Chat and Summary columns/);
});

test("selecting Summary replaces the chat surface instead of adding a third pane", () => {
  assert.match(
    conversationPage,
    /summaryReplacesChat = rangeViewState\.replaceChatWithSummary === !0/,
  );
  assert.match(
    conversationPage,
    /children: summaryReplacesChat[\s\S]*?"data-range-summary-replacement": !0[\s\S]*?: \[/,
  );
  assert.match(
    conversationPage,
    /"data-range-summary-replacement": !0,[\s\S]*?h-full min-h-0 w-full min-w-0 flex-1 overflow-hidden/,
  );
});
