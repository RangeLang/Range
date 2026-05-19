---
name: zed-range-extension
description: Use when working on the Range Zed extension, Range semantic highlighting, Zed integration issues, or the local range-lsp workflow. Covers the split between the main Range repo and the nested Zed/Range repo, when to change RangeCLI vs the extension, how to sync the extension, and which logs and commands to use for debugging.
---

# Zed Range Extension

Use this skill when the task touches:
- `Zed/Range`
- `RangeCLI` language-server behavior
- semantic highlighting in `.range` files
- Zed extension install/sync/debugging

## Repo split

There are two repos:
- main repo: `/Users/george/Documents/Range`
- nested Zed extension repo: `/Users/george/Documents/Range/Zed/Range`

Treat them separately when checking git status or making commits.

## Source of truth

Use this rule first:

- semantic meaning belongs in `RangeCLI/Sources/RangeCLI/RangeLanguageServer.swift`
- extension packaging, grammar, fallback queries, and Zed integration belong in `Zed/Range`

Examples:
- token kind/coloring issue in `.range` files:
  start in `RangeLanguageServer.swift`
- autocomplete/completion issue:
  start in `RangeLanguageServer.swift`
- grammar parse/query issue:
  start in `Zed/Range/grammars/tree-sitter-range` or `Zed/Range/languages/range`
- extension install/launcher/sync issue:
  start in `Zed/Range/src/lib.rs` and `Zed/Range/scripts`

## Current architecture

Range in Zed is semantic-first.

- Zed launches the local binary:
  - `/Users/george/Documents/Range/RangeCLI/.build/arm64-apple-macosx/debug/RangeCLI`
- the extension should not fall back to Homebrew or PATH binaries
- semantic tokens should drive Range colors
- Tree-sitter queries are fallback only

## Normal workflows

### 1. LSP-only change

Examples:
- semantic token changes
- completions
- hover/definition/rename
- diagnostics behavior

Do:

```sh
cd /Users/george/Documents/Range/RangeCLI
swift test
```

Then tell the user:
- `zed: restart language servers`

Do not reinstall the extension for pure `RangeCLI` changes.

### 2. Extension-side change

Examples:
- grammar
- `highlights.scm`
- `semantic_token_rules.json`
- launcher in `src/lib.rs`
- `extension.toml`

Do:

```sh
cd /Users/george/Documents/Range/Zed/Range
./scripts/sync-zed-extension.sh
```

Then tell the user:
- `zed: reload extensions`

If the change affects the launcher or grammar revision, a full Zed restart may still be needed.

## First debugging step

Before patching, identify which layer is wrong.

### Semantic token check

Use:

```sh
./RangeCLI/.build/arm64-apple-macosx/debug/RangeCLI semantic-tokens <file>
```

If the token stream is wrong, fix `RangeLanguageServer.swift`.

If the token stream is correct, then inspect Zed integration:
- `semantic_token_rules.json`
- extension sync state
- Zed settings
- live logs

## Important files

### Main repo

- `RangeCLI/Sources/RangeCLI/RangeLanguageServer.swift`
- `RangeCLI/Tests/RangeCLITests/RangeLanguageServerSemanticTokenTests.swift`
- `RangeSyntax/Sources/RangeSyntax/...`
- `RangeCompilerFixtures/...`

### Nested repo

- `Zed/Range/extension.toml`
- `Zed/Range/src/lib.rs`
- `Zed/Range/languages/range/config.toml`
- `Zed/Range/languages/range/semantic_token_rules.json`
- `Zed/Range/languages/range/highlights.scm`
- `Zed/Range/grammars/tree-sitter-range/grammar.js`
- `Zed/Range/scripts/sync-zed-extension.sh`
- `Zed/Range/scripts/smoke-check.sh`

## Logs

Check these when Zed behavior disagrees with local CLI behavior:

- Zed log:
  - `~/Library/Logs/Zed/Zed.log`
- LSP debug log:
  - `/tmp/range-lsp-debug.log`
- extension launcher log:
  - `/tmp/range-zed-launch.log`

Use them to answer:
- Did Zed launch the local `RangeCLI` binary?
- Is Zed requesting `textDocument/semanticTokens/full`?
- Is the server crashing or resetting?
- Is the extension query/grammar load failing?

## Guardrails

- Do not reintroduce global binary fallbacks in the Zed extension launcher.
- Do not fix semantic-coloring issues primarily in Tree-sitter queries unless it is explicitly a fallback issue.
- Do not add bogus legacy completions such as built-in views.
- Keep attributes limited to real supported forms only.
- Prefer semantic-token tests and fixture tests over visual guesswork.

## Minimal validation checklist

For LSP work:

```sh
cd /Users/george/Documents/Range/RangeCLI
swift test
```

For syntax/compiler changes:

```sh
cd /Users/george/Documents/Range/RangeSyntax
swift test --filter compileFailFixturesFail
swift test --filter compilePassFixturesValidate
```

For extension-side work:

```sh
cd /Users/george/Documents/Range/Zed/Range
./scripts/smoke-check.sh
./scripts/sync-zed-extension.sh
```

## Quick diagnosis map

- wrong token meaning or autocomplete:
  `RangeLanguageServer.swift`
- right token stream locally, wrong color in Zed:
  `semantic_token_rules.json`, Zed settings, logs
- extension installed but language not loading:
  `Zed.log`, grammar/query compatibility, `extension.toml`
- wrong binary launched:
  `/tmp/range-zed-launch.log`, `Zed/Range/src/lib.rs`
