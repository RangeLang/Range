# Neat Compiler Fixtures

This folder holds `.neat` source files used by compiler regression tests.

- `CompilePass`: files that must parse, build a semantic graph, and validate.
- `CompileFail`: files that must fail validation or compilation.

These are compiler fixtures, not the future Neat-native testing library.

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
- function nested argument rewrite shape (`target.application.arguments[i].rewrite(...)`)
- construct-target macro attachment validation
- construct extension-surface call shape (`target.addExtension(...)`)
- parameter-targeted `#autoclosure`
- nested parameter argument rewrite (`target.application.arguments[i].rewrite(...)`)
- parameter declaration type rewrite (`target.declaration.type.rewrite(...)`)
- parameter single-argument rewrite (`target.application.argument.rewrite(...)`)
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
  `target.application.arguments[0].expression.rewrite(...)`
- invalid rewrite-site usage for `Function` target macros, for example
  `target.rewrite(...)` instead of `target.application.rewrite(...)`
- invalid construct rewrite-site usage, for example `target.rewrite(...)` on a
  `Construct` target macro
- function nested rewrite execution gap fixture (expected fail until function
  call-site rewrite execution is fully enabled)
- parameter-targeted `#variadic` rewriting that now validates return semantics
  against the expanded parameter type
