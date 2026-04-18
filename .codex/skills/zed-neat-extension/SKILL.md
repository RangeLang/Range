---
name: zed-neat-extension
description: Use when working on the Neat Zed extension, Neat semantic highlighting, Zed integration issues, or the local neat-lsp workflow. Covers the split between the main Neat repo and the nested Zed/Neat repo, when to change NeatCLI vs the extension, how to sync the extension, and which logs and commands to use for debugging.
---

# Zed Neat Extension

Use this skill when the task touches:
- `Zed/Neat`
- `NeatCLI` language-server behavior
- semantic highlighting in `.neat` files
- Zed extension install/sync/debugging

## Repo split

There are two repos:
- main repo: `/Users/george/Documents/Neat`
- nested Zed extension repo: `/Users/george/Documents/Neat/Zed/Neat`

Treat them separately when checking git status or making commits.

## Source of truth

Use this rule first:

- semantic meaning belongs in `NeatCLI/Sources/NeatCLI/NeatLanguageServer.swift`
- extension packaging, grammar, fallback queries, and Zed integration belong in `Zed/Neat`

Examples:
- token kind/coloring issue in `.neat` files:
  start in `NeatLanguageServer.swift`
- autocomplete/completion issue:
  start in `NeatLanguageServer.swift`
- grammar parse/query issue:
  start in `Zed/Neat/grammars/tree-sitter-neat` or `Zed/Neat/languages/neat`
- extension install/launcher/sync issue:
  start in `Zed/Neat/src/lib.rs` and `Zed/Neat/scripts`

## Current architecture

Neat in Zed is semantic-first.

- Zed launches the local binary:
  - `/Users/george/Documents/Neat/NeatCLI/.build/arm64-apple-macosx/debug/NeatCLI`
- the extension should not fall back to Homebrew or PATH binaries
- semantic tokens should drive Neat colors
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
cd /Users/george/Documents/Neat/NeatCLI
swift test
```

Then tell the user:
- `zed: restart language servers`

Do not reinstall the extension for pure `NeatCLI` changes.

### 2. Extension-side change

Examples:
- grammar
- `highlights.scm`
- `semantic_token_rules.json`
- launcher in `src/lib.rs`
- `extension.toml`

Do:

```sh
cd /Users/george/Documents/Neat/Zed/Neat
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
./NeatCLI/.build/arm64-apple-macosx/debug/NeatCLI semantic-tokens <file>
```

If the token stream is wrong, fix `NeatLanguageServer.swift`.

If the token stream is correct, then inspect Zed integration:
- `semantic_token_rules.json`
- extension sync state
- Zed settings
- live logs

## Important files

### Main repo

- `NeatCLI/Sources/NeatCLI/NeatLanguageServer.swift`
- `NeatCLI/Tests/NeatCLITests/NeatLanguageServerSemanticTokenTests.swift`
- `NeatSyntax/Sources/NeatSyntax/...`
- `NeatCompilerFixtures/...`

### Nested repo

- `Zed/Neat/extension.toml`
- `Zed/Neat/src/lib.rs`
- `Zed/Neat/languages/neat/config.toml`
- `Zed/Neat/languages/neat/semantic_token_rules.json`
- `Zed/Neat/languages/neat/highlights.scm`
- `Zed/Neat/grammars/tree-sitter-neat/grammar.js`
- `Zed/Neat/scripts/sync-zed-extension.sh`
- `Zed/Neat/scripts/smoke-check.sh`

## Logs

Check these when Zed behavior disagrees with local CLI behavior:

- Zed log:
  - `~/Library/Logs/Zed/Zed.log`
- LSP debug log:
  - `/tmp/neat-lsp-debug.log`
- extension launcher log:
  - `/tmp/neat-zed-launch.log`

Use them to answer:
- Did Zed launch the local `NeatCLI` binary?
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
cd /Users/george/Documents/Neat/NeatCLI
swift test
```

For syntax/compiler changes:

```sh
cd /Users/george/Documents/Neat/NeatSyntax
swift test --filter compileFailFixturesFail
swift test --filter compilePassFixturesValidate
```

For extension-side work:

```sh
cd /Users/george/Documents/Neat/Zed/Neat
./scripts/smoke-check.sh
./scripts/sync-zed-extension.sh
```

## Quick diagnosis map

- wrong token meaning or autocomplete:
  `NeatLanguageServer.swift`
- right token stream locally, wrong color in Zed:
  `semantic_token_rules.json`, Zed settings, logs
- extension installed but language not loading:
  `Zed.log`, grammar/query compatibility, `extension.toml`
- wrong binary launched:
  `/tmp/neat-zed-launch.log`, `Zed/Neat/src/lib.rs`
