# Neat Zed Extension

Local Zed extension that adds language support for `.neat` files.

The bundled grammar and queries are aligned with the current Neat surface, including `construct Name: Contract { ... }`, builder declarations like `*builder RenderableBuilder { ... }`, builder-backed derived members like `*RenderableBuilder derived body: Renderable`, and `@main { ... }`.

## Features

- Registers a `Neat` language and associates `*.neat` files
- Uses the bundled Tree-sitter grammar for syntax highlighting
- Adds bracket matching, outline items, and indentation queries
- Launches `neat lsp` for editor features over stdio
- Supports hover, document symbols, go to definition, find references, rename, completion, formatting, and parser-backed diagnostics

## Requirements

- Zed with dev extensions enabled
- A `neat` binary on your `PATH`

The extension resolves the language server by running:

```text
neat lsp
```

## Install (dev extension)

1. In Zed, open the command palette.
2. Run `zed: install dev extension`.
3. Select this folder: `Zed/Neat`.
4. Reload Zed if the language does not appear immediately.

## Dev Workflow

Whenever changing this extension, use:

```text
./scripts/sync-zed-extension.sh
```

The script:

- bumps `version` in `extension.toml`
- updates the grammar `rev` to `HEAD` when `Zed/Neat` is clean
- rebuilds the Rust extension
- recompiles the Zed grammar WASM
- refreshes Zed's installed extension cache

If `Zed/Neat` still has uncommitted changes, the script leaves `rev` unchanged and prints a warning.

This applies especially to:

- `highlights.scm`
- grammar changes under `grammars/tree-sitter-neat`
- `src/lib.rs`
- language config/query files

Zed caches extension manifests, compiled extension output, and checked-out grammar revisions aggressively enough that version bumps work as the safest cache-buster.

## Grammar Source

The authored Tree-sitter grammar lives in `Zed/Neat/grammars/tree-sitter-neat`.

Zed may create `Zed/Neat/grammars/neat` during dev-extension installs as a local checkout/build workspace. That directory is transient extension state, not a source directory, and should not be edited or committed.

## Notes on colors

This extension provides syntax and language-server driven language support. It does not currently draw inline color swatches for Neat color values. If you want visual color chips in the editor, that will likely require a dedicated color-highlighting language server path in addition to the Neat syntax and LSP integration.
