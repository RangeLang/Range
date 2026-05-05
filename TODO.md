# Syntax Highlighting Parity

Current architecture is two-stage:

- Tree-sitter query highlighting provides fallback lexical/syntax colors before the LSP is ready.
- `neat-lsp` semantic tokens provide meaning-aware highlighting once the language server is loaded.
- Zed semantic token rules are generated from `Editor/Highlighting/semantic_token_rules.zed.json`.

Missing or incomplete work for Xcode-style parity:

- Add semantic origin modifiers for project vs other/core/external symbols.
- Map origin-aware semantic rules, such as `type.neat.project` and `type.neat.other`.
- Split constants from mutable variables where the declaration graph knows immutability.
- Split globals from locals and properties where symbol scope is known.
- Add semantic attribute classification instead of relying only on fallback syntax highlighting.
- Add documentation comment / documentation markup categories if Neat adds or formalizes doc comments.
- Add character literal category if Neat adds first-class character literals.
- Add regex literal categories if Neat adds regex syntax.
- Add URL highlighting if wanted for comments/strings or documentation.
- Decide whether `heading` and `plain text` categories matter for Neat source files or only documentation views.
