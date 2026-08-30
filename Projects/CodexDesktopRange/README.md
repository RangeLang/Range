# Codex Desktop Range highlighting

This project adds Range syntax highlighting to a separate local copy of the
installed Codex/ChatGPT desktop app. It does not modify the official app.

The patch injects the Zed-derived `range.tmLanguage.json` into both the
lightweight code-block provider and the full-file editor's Shiki loader. The
full-file editor also uses the light/dark Range Codability token palettes from
the Range Zed extension. It registers `.range`, updates the Electron ASAR
integrity hash, and ad-hoc signs the copied bundle.

Workspace files opened from the navigation tree use Codex's existing guarded
write path. The patched Pierre editor exposes a Save button and Command-S /
Control-S, while retaining its built-in three-second autosave, undo/redo,
mtime conflict detection, and draft recovery. Large files and review overlays
remain read-only according to the app's existing safety rules.

The main **New chat** row and its command always use Codex's standalone-chat
path, replacing the current pane with the standard start screen and explicitly
clearing the active project. The former Quick chat bubble is replaced by a
compact project dropdown. Its first option is **No project**, followed
by the app's current local and remote projects; choosing one opens the standard
composer scoped to that project. The dropdown uses Codex's own menu, item,
separator, section-label, and chevron components. Its labels are **No project**
and **Projects**, matching the app's existing localized language.
Project rows use Codex's own assigned project-icon renderer in the menu's
leading-icon slot, including each project's configured marker or emoji; the
**No project** row intentionally has no icon.

In Codex mode, the sidebar's product-mode control is rendered through its
built-in static-heading branch. The header remains **Codex**, but the pill,
chevron, click target, and ChatGPT/Codex selector popover are removed.

The **Recents** section uses the app's existing unified conversation source in
Codex mode. It interleaves local Codex tasks and ChatGPT conversations using
their native recency ordering and row components. Project-owned tasks are
included in Recents while their project sections remain available separately,
and no second history store is introduced.

The home screen surfaces the app's built-in routing through two selectable
**Build / Chat** cards. **Chat** uses the native ChatGPT conversation path.
**Build** uses the native task composer and contains its native execution
picker, relabeled **Local / Work**, inside the selected card. Conversation type
and execution location therefore remain separate choices without restoring the
old composer footer control. The Build hero reads **What should we build?**.
The experimental copy also removes the production work-only state guard from
this home-mode setter so both visible choices actually route.
The project and plugin controls remain grouped beneath the composer, while the
Build execution picker is a separate trailing control; the original full-width
utility-bar fill is removed. Back and forward remain the app's native history
actions but are positioned on the content side of the sidebar divider.

In the split workspace, the file/editor content pane is positioned immediately
after the sidebar and the conversation/task pane is positioned to its right.
The patch also inverts the content pane's native side-aware resize edge and
divider so resizing continues to behave correctly in the swapped layout. The
global thread-title strip is omitted because Codex renders it across the whole
window rather than within the swapped conversation column; the editor keeps one
unobstructed native tab row. The redundant thread-header **Share** control is
also omitted from this experimental layout; sharing remains available elsewhere
in the app when needed.

The conversation column replaces the floating **Toggle summary** popover with a
compact **Chat / Summary** segmented control. **Summary** reuses Codex's native
thread-summary content as a full column screen; returning to **Chat** restores
the timeline and composer without changing the task or editor state.

Opening and closing the sidebar no longer animates its opacity. The docked
sidebar keeps its native width transition, and the floating sidebar keeps its
native horizontal translation, so panes move over one another without fading.

ChatGPT Projects remain the shared conversation containers: they can own Chat
conversations as well as Codex tasks through the app's existing project
assignment path. Either conversation type can also be started with **No
project**. Local folders and remote workspaces remain Build execution context,
not a second incompatible kind of conversation container.

Shiki uses TextMate grammars rather than Zed's Tree-sitter queries, so the
grammar translates the canonical RangeZed capture categories and colors into
TextMate scopes. Keep the grammar and the two `range-codability-*.json` themes
in sync when the RangeZed queries or theme change.

The local signature cannot retain OpenAI's restricted team, push, app-group,
or shared-keychain entitlements, so those integrations may be unavailable in
the experimental copy.

```sh
npm install
npm test
npm run patch
```

The default output is `/Applications/ChatGPT Range.app`. The patcher refuses to
overwrite an existing target. It uses a distinct bundle and Electron product
identity so it can run alongside the official app with its own local profile.
The copied bootstrap uses `~/Library/Application Support/Codex Range` for an
independent Electron profile and Codex home, enables the local mock keychain,
and disables the production build's single-instance guard in this copy only.
A tiny native launcher supplies the isolated profile arguments before Owl's
native startup, so normal Finder/Dock launches use the independent runtime.

Because this targets a production asset name and marker, rerun it against each
new Codex app release. It will stop safely if either highlighting path changes.

## Direct renderer editing

For layout work on a pinned desktop-app version, the patched renderer can be
promoted into a directly editable workspace instead of adding more string
replacements to `patch-app.mjs`:

```sh
npm run direct:extract
npm run direct:status
```

This extracts the currently installed `/Applications/ChatGPT Range.app` into
`direct-renderer/app/` and formats the app-shell, conversation, Home composer,
editor, and highlighting chunks. Edit those JavaScript and CSS files directly.
Their hashed filenames remain unchanged, so their existing imports continue to
resolve. The original TypeScript/TSX source maps are referenced by the packaged
chunks but are not present in the installed application.

After an edit, rebuild the same experimental app with:

```sh
npm run direct:build
```

The direct builder syntax-checks the editable JavaScript, preserves the source
ASAR's unpacked-file contract, repacks the renderer, updates Electron's ASAR
integrity hash, and ad-hoc signs and verifies the app. It then asks the running
app to quit normally and waits for it to fully exit so its local databases can
finish writing. Only after that clean shutdown does it move the prior
installation to Trash, install the rebuilt app, and reopen it. If the app does
not quit within 30 seconds, the build stops and leaves the installed copy
untouched. This editable tree is pinned to the extracted desktop version;
create a fresh baseline after an app update.
