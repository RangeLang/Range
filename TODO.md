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
@hashable`), where `|` reads as logical or: "this face or that one". That
reverses the reason they were removed. Heterogeneous arrays do not use them:
they hold a macro type, `Array<@fruit>` (below).

### `named:` lookup and heterogeneous collections
`#target.members.first(named: "value")` will come back. Selecting elements
of a collection by a shared property is central to heterogeneous collections.
The path back is generic constraints, as the type of a type slot. See
"Macros in place of protocols and classes" below.

**Heterogeneous arrays: accepted 2026-10-31.** `Array<@fruit>`, `@fruit`
values with `@fruit`'s face, `fruit = Apple` with its narrowing, the
partitioned storage, `remove(at:)` and `slice(at:)` are implemented; see
Testing/Compiler/Native/MacroValues.range and Partitioned.range. Still to do:

- Selection: the narrowing that holds when `filter`'s predicate is true
  becomes the result's element type, so `fruits.filter { fruit in fruit =
  Apple }` is `Array<Apple>` and `names.filter { name in name.present }` is
  `Array<String>`. Today the result stays `Array<@fruit>`; `for fruit in
  fruits & fruit = Apple { … }` narrows already. This replaces the
  2026-09-08 note that `filter` need not read narrowing from a predicate.
  - Open: how `filter`'s declaration in `@collection` says it, without C
    naming `filter`. Candidate: a parameter macro, as in
    `function filter<Kept>(@narrows(to: Kept) let where: (Element) -> Bool): Array<Kept>`,
    where Kept is what a true result narrows the closure's parameter to, and
    Element when it narrows nothing.
  - When the predicate is exactly a type test, the result can share that
    type's block, copy-on-write. That needs a slot primitive that hands one
    type's block to another collection's `@many` member, with Range code
    setting its count and capacity.
- Decided while implementing, for George to confirm: a face member whose
  signature names the face's own type, as `=(let other: #target.name)`
  does, is not read through a `@fruit` value, since that type differs from
  value to value. Two `@fruit` values compare with the built-in `=`: the
  same type, then that type's `=`.
- Payoff: `#target.members` as `Array<@member>`, which brings back
  `first(named:)`.
- Open:
  - `fruits.filter(only: Apple)` as a shorter spelling; it passes a type as
    an argument, which Range does nowhere at run time.
  - Whether `shape = .circle` tests an enum's case, ignoring its payload.
  - `{ fruit in fruit = Apple }` reads oddly: a closure's `in` reads like
    `for … in`, singular in plural.

### Macros in place of protocols and classes
Range has neither protocols nor classes; macros cover conformance checks,
default implementations and retroactive conformance (applied on an
extension). What protocols and classes give that Range does not have yet:

- **A constraint that carries an element type.** A face may name only T,
  its own members and the program's declarations, so `T: @collection` is
  rejected: "@collection cannot be a constraint: its 'elements' names
  Element, which each target declares for itself". Generic code over
  collections writes `Array<T>`. Protocols answer this with associated types;
  Range has no design for it yet.
- **Values of different types at run time.** This is the heterogeneous
  array, `Array<@fruit>`, accepted 2026-10-31 (see `named:` above).
- **Shared identity.** Range does not nest values that point at each other; it
  references them by ID, as in `let parent: ID?`. No ID type exists in
  Language/Types today. The July 2026 model had
  `Identifier { name, id, parent }`.

Ideas from algebraic subtyping (Dolan, MLscript) worth keeping, without its
inference engine: Range writes signatures and checks generics against
their constraints, so there is nothing for biunification to solve.

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
- A type parameter's constraint is not visible to macros: TypeParameter
  reflects only its name.
- `T: @boolean` has `!`, `&` and `|` in its face, but they are C primitives
  of the condition type only: "builtin '&' is a C primitive of the condition
  type only; T declares it".
- A face holds signatures only, so a face function that changes its
  receiver, called on a let, is caught per use: "'bump' changes its
  receiver, which must be declared with state; in bumped<T: Tally>,
  specialized at …".
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
- Values of a macro's types (`@fruit`):
  - only top-level types applying the macro are its types; a nested one,
    as `Basket.Fig`, is not, and a generic one is reported as not
    implemented;
  - a value is narrowed once, so an optional `@fruit` narrowed to its
    `@fruit` is not narrowed again by `head = Apple`, and `@fruit?` does not
    compare with an Apple: promotion goes one step;
  - a face function that changes its receiver is not called through a
    `@fruit` value: each case's arm holds a copy;
  - `Array<@fruit>` is not compiled when a type applying `@fruit` holds
    `@fruit` values itself, and its storage cannot shrink below the
    elements it holds.

### Macro gaps
- `@holding(type: Array<@nominal>)` does not parse.
- Splicing a specialization of a macro type is not implemented; nothing can
  write one yet.
- When one macro emits a second application of another, the first
  application may already have run in that round; the emitted one never runs.
- `--match-literal` does not run typing, so a wrong `@literal` label is
  caught only when compiling.

### `Never`
- An `@extern` or `@builtin` function returning `Never` is trusted.

### C shortcuts to replace
- Builtins selected by name:
  - `resize`, `read`, `write`, `drop`, `byte` and `count`;
  - a scalar's generics `bits` and `signed`: a construct applying the macro
    integer literals select is a scalar, and C reads its width and
    signedness from those two generics;
  - the labels `lower`, `upper`, `at` and `value`;
  - `print`, `diagnostic` and `warning`, in `nativeCall`, `nativeEffect`,
    `evalBuiltin` and `evalEffect`.
- `@literal` patterns are registered by C while reading, before typing.
- setjmp/longjmp in the resolver and typer.
- Partitioned `@many` storage grows each type's block by doubling from
  four slots, a policy C holds.

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
