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

- literal bridge carry through `#literal<T>`
- attached parameter `#autoclosure`
- freestanding expression `#stringify(...)`
- known `#variadic` return-validation gap

Move the variadic fixture from `CompileFail` to `CompilePass` when callable
return validation consumes the expanded parameter type consistently.
