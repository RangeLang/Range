# Product Ideas

Active compiler/language cleanup now lives in:

- [To-do/README.md](To-do/README.md)

- Create GradientCloud so people can share Gradient packages, articles, examples, and language-design notes.

# Embedded Swift Direction

- Make Embedded Swift compatibility a design constraint for all Swift code in Gradient.
- Port in this order: `GradientSyntax`, `GradientBackendSwift`, then host adapters in `GradientCLI`.
- Add an Embedded-capable SDK/toolchain build lane once local SwiftPM can load the Embedded standard library for the chosen target.

# Syntax Highlighting Parity

Current architecture is two-stage:

- Tree-sitter query highlighting provides fallback lexical/syntax colors before the LSP is ready.
- `gradient-lsp` semantic tokens provide meaning-aware highlighting once the language server is loaded.
- Zed semantic token rules are generated from `Editor/Highlighting/semantic_token_rules.zed.json`.

Missing or incomplete work for Xcode-style parity:

- Add semantic origin modifiers for project vs other/core/external symbols.
- Map origin-aware semantic rules, such as `type.gradient.project` and `type.gradient.other`.
- Split constants from mutable variables where the declaration graph knows immutability.
- Split globals from locals and properties where symbol scope is known.
- Add semantic attribute classification instead of relying only on fallback syntax highlighting.
- Add documentation comment / documentation markup categories if Gradient adds or formalizes doc comments.
- Add character literal category if Gradient adds first-class character literals.
- Add regex literal categories if Gradient adds regex syntax.
- Add URL highlighting if wanted for comments/strings or documentation.
- Decide whether `heading` and `plain text` categories matter for Gradient source files or only documentation views.
