# Neat Highlighting

This directory owns editor-agnostic highlighting policy for Neat.

The split is:

- `NeatCLI` emits semantic token meaning through the language server.
- `Editor/Highlighting` defines how those semantic categories should map to editor style names.
- Editor extensions generate their local configuration from these files.
- Tree-sitter query files remain fallback syntax highlighting for files without semantic token support.

The current Zed adapter reads `semantic_token_rules.zed.json` and copies it to:

`Zed/Neat/languages/neat/semantic_token_rules.json`

Keep richer distinctions, such as declaration/application and future project/core origin, in the semantic token stream rather than tree-sitter queries.
