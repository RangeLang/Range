# Product Ideas

Active compiler/language cleanup now lives in:

- [To-do/README.md](To-do/README.md)

- Create RangeCloud so people can share Range packages, articles, examples, and language-design notes.

# Embedded Swift Direction

- Make Embedded Swift compatibility a design constraint for all Swift code in Range.
- Port in this order: `RangeSyntax`, `RangeBackendSwift`, then host adapters in `RangeCLI`.
- Add an Embedded-capable SDK/toolchain build lane once local SwiftPM can load the Embedded standard library for the chosen target.

# Syntax Highlighting Parity

Current architecture is two-stage:

- Tree-sitter query highlighting provides fallback lexical/syntax colors before the LSP is ready.
- `range-lsp` semantic tokens provide meaning-aware highlighting once the language server is loaded.
- Zed semantic token rules are generated from `Editor/Highlighting/semantic_token_rules.zed.json`.

Missing or incomplete work for Xcode-style parity:

- Add semantic origin modifiers for project vs other/core/external symbols.
- Map origin-aware semantic rules, such as `type.range.project` and `type.range.other`.
- Split constants from mutable variables where the declaration graph knows immutability.
- Split globals from locals and properties where symbol scope is known.
- Add semantic attribute classification instead of relying only on fallback syntax highlighting.
- Add documentation comment / documentation markup categories if Range adds or formalizes doc comments.
- Add character literal category if Range adds first-class character literals.
- Add regex literal categories if Range adds regex syntax.
- Add URL highlighting if wanted for comments/strings or documentation.
- Decide whether `heading` and `plain text` categories matter for Range source files or only documentation views.
