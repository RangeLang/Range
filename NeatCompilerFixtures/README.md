# Neat Compiler Fixtures

This folder holds `.neat` source files used by compiler regression tests.

- `CompilePass`: files that must parse, build a semantic graph, and validate.
- `CompileFail`: files that must fail validation or compilation.

These are compiler fixtures, not the future Neat-native testing library.

## Adding Fixtures

Create new compiler fixtures in this folder, not inline inside Swift test files.

- Put validating examples in `CompilePass/<Category>/Name.neat`.
- Put expected-failure examples in `CompileFail/<Category>/Name.neat`.
- Reuse an existing category when possible. Add a new category only when it
  reflects a real compiler surface that is starting to accumulate coverage.
- Name fixtures after the behavior being protected, not after the test method.
  Good examples: `ClampedState.neat`, `InitMacroRewrite.neat`,
  `UnknownAttribute.neat`.
- Keep each fixture focused. Prefer one behavior per file unless the behaviors
  are inseparable.
- If a Swift test needs to inspect expanded AST or graph details for one
  specific fixture, load the fixture file by path from `NeatCompilerFixtures`
  rather than embedding the `.neat` source directly in the test.

Current top-level layout:

- `CompilePass/Macros`: macro expansion and validation fixtures
- `CompilePass/System`: core language/system behavior that should validate
- `CompilePass/Concurrency`: concurrency semantics that should validate
- `CompileFail/...`: negative fixtures grouped by the same surface areas

The default rule is simple: if it is compiler input worth keeping around, it
belongs in `NeatCompilerFixtures`.

## Roadmap

The current fixture surface is intentionally small. Add categories only when
they protect real compiler behavior.

- `CompileFail` diagnostics: require specific error text or diagnostic codes,
  not just "any failure".
- `RunPass`: compile and run the generated program, then check stdout, stderr,
  and exit status.
- `EmitSwift`: compile through the Swift backend and compare important emitted
  Swift shapes.
- `Artifacts`: verify compiler artifacts such as declaration graphs, dependency
  graphs, and lowered IR once those formats stabilize.
- `ParsePass` / `ParseFail`: add parser-only fixtures if syntax work starts
  changing faster than semantic validation.

Keep `NeatTesting` or `Testing` reserved for a future Neat-native user testing
library. These fixtures are for host-side compiler regression tests.

## Macro Fixtures

The current macro fixtures cover only the supported bootstrap surface:

- direct literal bridge attachment through `#literal<T>` on a concrete `init`
- literal bridge carry through `#literal<T>`
- init-targeted call-site rewrite from attached init macros
- function-targeted macro attachment and rewrite-site validation
- function nested argument-slot rewrite shape (`target.application.arguments[i].expression.rewrite(...)`)
- construct-target macro attachment validation
- construct extension-surface call shape (`target.addExtension(...)`)
- parameter-targeted `#autoclosure`
- nested parameter application rewrite (`target.application.expression.rewrite(...)`)
- parameter declaration type rewrite (`target.declaration.type.rewrite(...)`)
- parameter single-application rewrite (`target.application.expression.rewrite(...)`)
- expression-targeted `#stringify(...)`
- expression-targeted rewrite through `target.rewrite(...)`, including
  `#unwrap(...)` and a custom macro fixture
- custom `capture Expression` macro parameters
- generic expression macro result substitution, for example
  `#unwrap<T>(...) -> T` inferring the expanded expression result type
- syntax-category expression macro parameters must use `capture`, for example
  `value _: capture Expression`
- invalid capture usage, for example `capture String`
- invalid rewrite-site usage for a macro target kind, for example a
  `Parameter` macro using `target.rewrite(...)`
- invalid nested parameter rewrite-site usage, for example
  `target.application.rewrite(...)`
- invalid rewrite-site usage for `Function` target macros, for example
  `target.rewrite(...)` instead of `target.application.rewrite(...)`
- invalid construct rewrite-site usage, for example `target.rewrite(...)` on a
  `Construct` target macro
- function nested rewrite execution gap fixture (expected fail until function
  call-site rewrite execution is fully enabled)
- parameter-targeted `#variadic` rewriting that now validates return semantics
  against the expanded parameter type
