# Tests

This folder is a quarantine for historical Range source examples.

Active compiler coverage no longer sweeps `CompilePass`, `CompileFail`, or
`RunPass` as `.range` input fixtures. Those files described the old model where
the Range parser/type checker/macro expander (Swift) owned language constructs
such as bare `construct`, `function`, `let`, `if`, `while`, `return`, literals,
and operator forms.

The macro-first direction keeps active source tests focused on the macro carrier
surface:

- `@macro ...`
- `@macro(...) { ... }`
- top-level macro blocks such as `@construct(name: "...") { ... }`
- explicit macro statement forms such as `@return`, `@if`, `@while`, `@state`,
  `@let`, and `@assignment`

Historical examples are retained as `.range.txt` so they can be referenced while
Range-authored macro surfaces replace the old Swift-owned language model. Do not
rename those files back to `.range` unless the source has been converted to the
macro-carrier surface and the test is intentionally reintroduced.

Prefer focused Swift tests with inline Range source for now. That keeps each
active test tied to the current bootstrap contract instead of reviving a broad
fixture sweep.
