# Core Migration TODO

- [ ] Decide whether `@core` is allowed only in `NeatCore` or compiler-owned modules.
- [ ] Decide whether a normal `construct` can store a `@core construct` member as plain inline value data.
- [ ] Replace the parser's hardcoded operator precedence table with explicit Neat operator and precedence declarations.
- [ ] Shrink Swift-side operator typing rules so operator meaning can migrate toward Neat declarations instead of `BuiltinType` special cases.
- [ ] Remove the literal-lowering fallback path in `MacroExpander` once `Init` declaration/application rewrite execution is authoritative, and emit an explicit diagnostic instead of silently falling back when init-macro interpretation fails.
