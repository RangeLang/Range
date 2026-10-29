# To-dos

The one place where open work is gathered. Design discussions are questions
George has not decided yet; implementation items are decided or are known
gaps in the compiler.

## Design discussion

### Async, from scratch
The earlier exploration document was deleted on 2026-10-29; start over.
The accepted rules for ticks, commits and bindings of `state` still stand.
Revisit together with namespacing.

### Namespacing and collections of functions
The need: quickly define a group such as `Math` and call `Math.clamp(…)`;
the same shape would give `Console.print(…)` and `Diagnostics.warning(…)`.
Range has no static functions, not even without the keyword, and a construct
is a type, so `Logger()` is always a value.

- In place for now: `print`, `diagnostic` and `warning` are plain `@builtin`
  top-level functions, and `diagnostic` returns `Never`.
- Ruled out:
  - modules as folders for grouping functions;
  - a handed-in value such as `{ system in system.console.print(…) }`;
  - methods on grammar values such as `parameter.error(…)`;
  - `static`.
- Leaning: namespaces as a real thing.
  ```range
  namespace Math {
      function clamp(let value: Int, let low: Int, let high: Int): Int { … }
  }
  Math.clamp(value: x, low: 0, high: 10)
  ```
- Other candidates:
  - a type with no values is a namespace, as an enum without cases is in Swift;
  - a function that reads no members can be called through the type name.
    This one is fragile: a body edit changes who can call it.
- Questions:
  - its own declaration kind, or a construct or enum used that way?
  - state in a namespace would be global state;
  - nesting, `extension Math`, and holding types and macros;
  - how it meets reach (who may print) and async;
  - is a collection of functions ever a value that can be passed around?
- History:
  - a `Logger` construct, April to July 2026, called as `Logger.info(…)`;
  - Compiler B's `Diagnostic` with `enum Severity { error, warning,
    information, hint }`;
  - the idea of one `report(severity:message:)` beside a separate,
    diverging `error`.
- derived must not perform effects (print, diagnostic, warning); detecting
  that needs effects to have an owner instead of free functions, so it waits
  for namespacing.

### How optionality is spelled
Optionality on the type is fine; the bare `?` (`Int?`, `Int?.absent`,
`Array<String?>`) feels iffy. Moving `?` onto bindings was rejected because
it splits one concept by position.

### Union types
They were removed in 798beab7: `A | B` in a type is an error that points to
an enum with one case per alternative, because `|` is logical or. Reusing
`||` for types was rejected. Discuss together with `?`.

### `named:` lookup and heterogeneous collections
`#target.members.first(named: "value")` will come back. Selecting elements
of a collection by a shared property is central to heterogeneous collections.
The path back is generic constraints, as the type of a type slot.

### Parameter defaults
Functions have none, so macros have none, and overloads cover it for now.
Decide for both together.

### Macros written in run code
Nothing written in run code is a macro anymore. A macro that runs in place
and leaves code behind, as Swift's freestanding macros do, would need a
target kind for "a place in a block" and `#graph` that emits there.

### `@ignored`
A marker plus an ordinary function any macro can call to skip a member. The
scoped form `@ignored([@equatable, @database])` needs macros referenced as
values.

### Reflected types as specializations
`Parameter.type`, `Function.output` and `Function.receiver` are declarations,
generic arguments aside. A type written with generic arguments is a
specialization at macro time, so these fields differ from it. Making them
specializations would mean typing references under a context, and the shape
of a generic declaration would differ between its own run and its law runs.

## Implementation

### Next
- `derived` and `binding`, compiled to the accepted wire-scheduler rules.

### Language gaps
- String interpolation of values known only at run.
- Escaping closures, such as stored event handlers.
- Constraints as the type of a type slot.
- `state` as a run-time cell only; values known before run are not yet
  followed through writes.
- `binding` in a block is rejected as not implemented; a binding is a
  construct member.

### Macro gaps
- `@holding(type: Array<@nominal>)` does not parse.
- Splicing a specialization of a macro type is not implemented; nothing can
  write one yet.
- When one macro emits a second application of another, the first
  application may already have run in that round; the emitted one never runs.
- A trap while computing a macro argument, such as dividing by zero, is
  reported as "not known at macro time" with the trap as a note. A trap is
  known; it deserves its own message.
- `--match-literal` does not run typing, so a wrong `@literal` label is
  caught only when compiling.
- Unused generic bodies are only lightly checked.

### `Never`
- A construct member of type `Never` is accepted without comment.
- An `@extern` or `@builtin` function returning `Never` is trusted.

### C shortcuts to replace
- Builtins selected by name:
  - `resize`, `read`, `write`, `byte`, `storage` and `count`;
  - the labels `lower`, `upper`, `at` and `value`;
  - `print`, `diagnostic` and `warning`, in `nativeCall`, `nativeEffect`,
    `evalBuiltin` and `evalEffect`.
- `@literal` patterns are registered by C while reading, before typing.
- setjmp/longjmp in the resolver and typer.

### Code generation
- Jump tables for `switch`.
- Flat, numbered storage.
- A derived value is computed again on every read; caching it until one of
  its inputs changes is an optimization still to do.

### Tooling and site
- The summary counts in `check-compiler-native` and `rejections=7` in
  `check-compiler-literal` are hardcoded and wrong.
- Website sources still use `@diagnostic(` and `#cases.map`.
