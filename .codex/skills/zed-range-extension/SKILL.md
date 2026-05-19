---
name: zed-gradient-extension
description: Use when working on the Gradient Zed extension, Gradient semantic highlighting, Zed integration issues, or the local gradient-lsp workflow. Covers the split between the main Gradient repo and the nested Zed/Gradient repo, when to change GradientCLI vs the extension, how to sync the extension, and which logs and commands to use for debugging.
---

# Zed Gradient Extension

Use this skill when the task touches:
- `Zed/Gradient`
- `GradientCLI` language-server behavior
- semantic highlighting in `.gradient` files
- Zed extension install/sync/debugging

## Repo split

There are two repos:
- main repo: `/Users/george/Documents/Gradient`
- nested Zed extension repo: `/Users/george/Documents/Gradient/Zed/Gradient`

Treat them separately when checking git status or making commits.

## Source of truth

Use this rule first:

- semantic meaning belongs in `GradientCLI/Sources/GradientCLI/GradientLanguageServer.swift`
- extension packaging, grammar, fallback queries, and Zed integration belong in `Zed/Gradient`

Examples:
- token kind/coloring issue in `.gradient` files:
  start in `GradientLanguageServer.swift`
- autocomplete/completion issue:
  start in `GradientLanguageServer.swift`
- grammar parse/query issue:
  start in `Zed/Gradient/grammars/tree-sitter-gradient` or `Zed/Gradient/languages/gradient`
- extension install/launcher/sync issue:
  start in `Zed/Gradient/src/lib.rs` and `Zed/Gradient/scripts`

## Current architecture

Gradient in Zed is semantic-first.

- Zed launches the local binary:
  - `/Users/george/Documents/Gradient/GradientCLI/.build/arm64-apple-macosx/debug/GradientCLI`
- the extension should not fall back to Homebrew or PATH binaries
- semantic tokens should drive Gradient colors
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
cd /Users/george/Documents/Gradient/GradientCLI
swift test
```

Then tell the user:
- `zed: restart language servers`

Do not reinstall the extension for pure `GradientCLI` changes.

### 2. Extension-side change

Examples:
- grammar
- `highlights.scm`
- `semantic_token_rules.json`
- launcher in `src/lib.rs`
- `extension.toml`

Do:

```sh
cd /Users/george/Documents/Gradient/Zed/Gradient
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
./GradientCLI/.build/arm64-apple-macosx/debug/GradientCLI semantic-tokens <file>
```

If the token stream is wrong, fix `GradientLanguageServer.swift`.

If the token stream is correct, then inspect Zed integration:
- `semantic_token_rules.json`
- extension sync state
- Zed settings
- live logs

## Important files

### Main repo

- `GradientCLI/Sources/GradientCLI/GradientLanguageServer.swift`
- `GradientCLI/Tests/GradientCLITests/GradientLanguageServerSemanticTokenTests.swift`
- `GradientSyntax/Sources/GradientSyntax/...`
- `GradientCompilerFixtures/...`

### Nested repo

- `Zed/Gradient/extension.toml`
- `Zed/Gradient/src/lib.rs`
- `Zed/Gradient/languages/gradient/config.toml`
- `Zed/Gradient/languages/gradient/semantic_token_rules.json`
- `Zed/Gradient/languages/gradient/highlights.scm`
- `Zed/Gradient/grammars/tree-sitter-gradient/grammar.js`
- `Zed/Gradient/scripts/sync-zed-extension.sh`
- `Zed/Gradient/scripts/smoke-check.sh`

## Logs

Check these when Zed behavior disagrees with local CLI behavior:

- Zed log:
  - `~/Library/Logs/Zed/Zed.log`
- LSP debug log:
  - `/tmp/gradient-lsp-debug.log`
- extension launcher log:
  - `/tmp/gradient-zed-launch.log`

Use them to answer:
- Did Zed launch the local `GradientCLI` binary?
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
cd /Users/george/Documents/Gradient/GradientCLI
swift test
```

For syntax/compiler changes:

```sh
cd /Users/george/Documents/Gradient/GradientSyntax
swift test --filter compileFailFixturesFail
swift test --filter compilePassFixturesValidate
```

For extension-side work:

```sh
cd /Users/george/Documents/Gradient/Zed/Gradient
./scripts/smoke-check.sh
./scripts/sync-zed-extension.sh
```

## Quick diagnosis map

- wrong token meaning or autocomplete:
  `GradientLanguageServer.swift`
- right token stream locally, wrong color in Zed:
  `semantic_token_rules.json`, Zed settings, logs
- extension installed but language not loading:
  `Zed.log`, grammar/query compatibility, `extension.toml`
- wrong binary launched:
  `/tmp/gradient-zed-launch.log`, `Zed/Gradient/src/lib.rs`
