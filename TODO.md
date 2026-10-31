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

Constraints are being reopened as logic over types (`@comparable |
@hashable`), and the heterogeneous-array design uses `Triangle | Circle`. In
both, `|` in a type reads as logical or: "a value of this type or that one".
That reverses the reason they were removed.

### `named:` lookup and heterogeneous collections
`#target.members.first(named: "value")` will come back. Selecting elements
of a collection by a shared property is central to heterogeneous collections.
The path back is generic constraints, as the type of a type slot. See
"Macros in place of protocols and classes" below.

### Macros in place of protocols and classes
Range has neither protocols nor classes; macros cover conformance checks,
default implementations and retroactive conformance (applied on an
extension). What protocols and classes give that Range does not have yet:

- **A generic body checked once: accepted 2026-10-30, to implement.**
  - A constraint is a macro type, as in `function sum<T: @integer>(…)`.
  - A macro's face is what its unconditional `#graph` blocks emit, with
    `#target.name` read as T. What a macro emits and what it requires are the
    same thing; its other checks are for better errors.
  - Emitted members whose types depend on splices of the target or of
    arguments (`#type`, `#width`) are not part of the face.
  - One rule for every generic body: it is checked against its constraints. A
    bare `T` guarantees only what every type has, the built-in `=`. Code is
    still generated per use.
  - Constraints combine with the logic symbols: `@comparable & @hashable` has
    both faces, and `@comparable | @hashable` has what both share. A plain list
    is ambiguous, so it is an error.
  - **Open:** a macro overloaded by target type (`@equatable` on Construct and
    on Enum). The candidate reading is the `|` of its overloads, so its face is
    what they share.
- **Values of different types at run time.** This is the heterogeneous array
  (see `named:` above). Its design is a partitioned array: one concrete buffer
  per member type, plus one buffer of `(type, index)` references in source
  order. It has the face of a normal array. `filter(for: Triangle)` returns
  `Array<Triangle>`, which is that type's buffer. History: 457104e3 TODO.md
  ("nominally partitioned multibuffer") and e0823c81
  Development/CompilerFlow/GoalAudit.md ("Collection predicates and explicit
  type selection", 2026-09-08).
- **Shared identity.** Range does not nest values that point at each other; it
  references them by ID, as in `let parent: ID?`. No ID type exists in
  Language/Types today. The July 2026 model had
  `Identifier { name, id, parent }`.

Ideas from algebraic subtyping (Dolan, MLscript) worth keeping, without its
inference engine: Range writes signatures and checks generics per use, so
there is nothing for biunification to solve.

- Structural "has these members" requirements, checked per specialization,
  give `named:` lookup without runtime field shuffling. Only a runtime
  collection of different types brings back the layout question.
- If union types return, they are joins, with `Never` as bottom.
- Value collections are copy-on-write, so `Array<T>` can be covariant safely.

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

### `$` for bindings
Revisit the `$` spelling for passing a state to a binding
(`Stepper(quantity: $amount)`); George chose `$` for visibility at the call
site on 2026-10-29, to be revisited.

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
- Passing a state to a binding is not run at macro time: "passing a state to
  a binding is not run at macro time".
- `$` to a function's `binding` parameter is reported as not implemented;
  such a parameter is otherwise read as a let.
- A value holding a binding follows a conservative rule: it is never
  returned from a function, never held by a state member or @many storage,
  and assigned only to a local of the assignment's own block. Returning one
  whose bound state outlives the call needs lifetimes of what it binds.
- `let s: make(1)`, where `make` is a closure parameter, is not compiled
  natively ("native values of <unknown> are not implemented").

### Macro gaps
- `@holding(type: Array<@nominal>)` does not parse.
- Splicing a specialization of a macro type is not implemented; nothing can
  write one yet.
- When one macro emits a second application of another, the first
  application may already have run in that round; the emitted one never runs.
- `--match-literal` does not run typing, so a wrong `@literal` label is
  caught only when compiling.
- Unused generic bodies are only lightly checked.

### `Never`
- An `@extern` or `@builtin` function returning `Never` is trusted.

### C shortcuts to replace
- Builtins selected by name:
  - `resize`, `read`, `write`, `byte` and `count`;
  - a scalar's generics `bits` and `signed`: a construct applying the macro
    integer literals select is a scalar, and C reads its width and
    signedness from those two generics;
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
- The Website's Range samples are still written in the earlier
  `#environment` dialect: `#environment.target.Declaration`, `if`,
  `switch x { case … }`, and `#name` splices of macro locals such as
  `#fields.map` and `#property.identity`. Rewriting them is a choice
  between updating dated essays and keeping them as written.
