# Neat Zed Extension

Local Zed extension that adds language support for `.neat` files.

The bundled grammar and queries are aligned with the current Neat surface, including declaration headers like `#Name on Target: Contract { ... }` and callable members like `@name(...)`.

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
3. Select this folder: `zed/neat`.
4. Reload Zed if the language does not appear immediately.

## Notes on colors

This extension provides syntax and language-server driven language support. It does not currently draw inline color swatches for Neat color values. If you want visual color chips in the editor, that will likely require a dedicated color-highlighting language server path in addition to the Neat syntax and LSP integration.
