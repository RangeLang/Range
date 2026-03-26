# Handoff

## Objective
- Build out Neat's foundation layer while keeping the memory-graph-first language model coherent.
- Keep `NeatCore` as real `.neat` source consumed by the current Swift-based compiler pipeline.

## What Changed
- Moved `NeatCore` out of `NeatSyntax/Sources` into top-level [`NeatCore`](/Users/george/Documents/Neat/NeatCore).
- Updated [`NeatCoreLoader.swift`](/Users/george/Documents/Neat/NeatCLI/Sources/NeatCLI/NeatCoreLoader.swift) to load from the new root path and continue excluding `NeatCore/Macros/Exploration`.
- Fixed parser support for value-generic defaults like `.signed` in construct headers by adding expression terminators for generic default parsing:
  - [`Parser.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Shared/Parser.swift)
  - [`Parser+Expression.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Expression/Parser+Expression.swift)
  - [`Parser+Construct.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/TypeDefinitions/Construct/Parser+Construct.swift)
- Generalized `state` declarations from builtin-only types to general `TypeReference`, so declarations like `state elements: [Element]` are legal:
  - [`AST+State.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/State/AST+State.swift)
  - [`Parser+State.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/State/Parser+State.swift)
  - [`EntityIR.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/EntityIR.swift)
  - [`DependencyGraph.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/DependencyGraph.swift)
- Extended parameter label parsing so keyword labels can appear in the second label position (`for key: Key`):
  - [`Parser+Shared.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Shared/Parser+Shared.swift)
- Corrected memory-graph docs:
  - memory graph is always generated
  - `@noMemoryGraph` removed
  - reactivity is the optional exposed layer (`@reactive` direction)
  - file: [`MemoryGraph.md`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/MemoryGraph/MemoryGraph.md)

## Key Decisions
- `construct` is identity-bearing by default for normal user modeling.
- `@core construct` is non-identity-bearing, compiler-recognized, and plain-value/structural.
- Memory graph is foundational and always-on.
- Reactivity is not a separate base system; it is an optional exposed layer derived from the memory graph.
- `Macros/Exploration` stays excluded from normal compiler/core loading.
- Core literal bridges use `#literal(...)` protocols and empty literal carrier types for now.
- Keep type sugar and literal sugar separate for now:
  - `#literal(NilLiteral)` is fine
  - `T? -> Optional<T>` remains compiler type sugar, not macro-defined yet
- Keep `Hashable` simple for now:
  - `function hashValue() -> Int`
  - no public `Hasher`/`inout` model yet

## Current State
- `NeatCore` exists as a top-level source tree:
  - [`NeatCore/DataSystem`](/Users/george/Documents/Neat/NeatCore/DataSystem)
  - [`NeatCore/Primitives`](/Users/george/Documents/Neat/NeatCore/Primitives)
  - [`NeatCore/Macros/Exploration`](/Users/george/Documents/Neat/NeatCore/Macros/Exploration)
- Current core scalar/data families exist:
  - `Int`, `IntLiteral`, `Signedness`, `ExpressableByIntLiteral`
  - `String`, `StringLiteral`, `ExpressableByStringLiteral`
  - `Bool`, `BoolLiteral`, `ExpressableByBoolLiteral`
  - `Float`, `FloatLiteral`, `FloatingPointWidth`, `ExpressableByFloatLiteral`
  - `Optional`, `NilLiteral`, `ExpressableByNilLiteral`
  - `Array`, `ArrayLiteral`, `ExpressableByArrayLiteral`
  - `Dictionary`, `DictionaryLiteral`, `ExpressableByDictionaryLiteral`
  - `Set`, `SetLiteral`, `ExpressableBySetLiteral`
- Current foundational protocols exist:
  - [`Equatable.neat`](/Users/george/Documents/Neat/NeatCore/DataSystem/Protocols/Equatable.neat)
  - [`Hashable.neat`](/Users/george/Documents/Neat/NeatCore/DataSystem/Protocols/Hashable.neat)
  - [`Comparable.neat`](/Users/george/Documents/Neat/NeatCore/DataSystem/Protocols/Comparable.neat)
- Current explicit scalar conformances:
  - [`Int.neat`](/Users/george/Documents/Neat/NeatCore/DataSystem/Int/Int.neat): `ExpressableByIntLiteral, Equatable, Hashable, Comparable`
  - [`Bool.neat`](/Users/george/Documents/Neat/NeatCore/DataSystem/Bool/Bool.neat): `ExpressableByBoolLiteral, Equatable, Hashable`
  - [`String.neat`](/Users/george/Documents/Neat/NeatCore/DataSystem/String/String.neat): `ExpressableByStringLiteral, Equatable, Hashable, Comparable`
  - [`Float.neat`](/Users/george/Documents/Neat/NeatCore/DataSystem/Float/Float.neat): `ExpressableByFloatLiteral, Equatable, Hashable, Comparable`
- Current collection constraints:
  - [`Set.neat`](/Users/george/Documents/Neat/NeatCore/DataSystem/Set/Set.neat): `Set<Element: Hashable>`
  - [`Dictionary.neat`](/Users/george/Documents/Neat/NeatCore/DataSystem/Dictionary/Dictionary.neat): `Dictionary<Key: Hashable, Value>`
- Current collection APIs remain intentionally opaque:
  - `Array` has `init()`, `init(literal:)`, `count`, `append`, `element(index:)`
  - `Dictionary` has `init()`, `init(literal:)`, `count`, `value(for key:)`, `updateValue(value:for key:)`
  - `Set` has `init()`, `init(literal:)`, `count`, `contains(element:)`, `insert(element:)`
- Intentionally incomplete:
  - no real storage lowering for collections yet
  - no public `Hasher`
  - no `Set`/`Dictionary` equality/hash conformances yet
  - no conformance synthesis/macros promoted out of exploration
  - no type-sugar lowering hooks documented beyond existing compiler behavior

## Important Files
- Loader / integration:
  - [`NeatCoreLoader.swift`](/Users/george/Documents/Neat/NeatCLI/Sources/NeatCLI/NeatCoreLoader.swift)
- Parser / type system changes:
  - [`Parser.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Shared/Parser.swift)
  - [`Parser+Shared.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Shared/Parser+Shared.swift)
  - [`Parser+Expression.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Expression/Parser+Expression.swift)
  - [`Parser+Construct.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/TypeDefinitions/Construct/Parser+Construct.swift)
  - [`AST+State.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/State/AST+State.swift)
  - [`Parser+State.swift`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/State/Parser+State.swift)
- Memory graph docs:
  - [`MemoryGraph.md`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/MemoryGraph/MemoryGraph.md)
  - [`MemoryGraph.ProofRules.md`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/MemoryGraph/MemoryGraph.ProofRules.md)
- Core protocols:
  - [`NeatCore/DataSystem/Protocols`](/Users/george/Documents/Neat/NeatCore/DataSystem/Protocols)
- Core scalar and collection families:
  - [`NeatCore/DataSystem`](/Users/george/Documents/Neat/NeatCore/DataSystem)

## Open Questions
- Should `@core` be restricted to `NeatCore` / compiler-owned modules?
  - tracked in [`CORE_MIGRATION_TODO.md`](/Users/george/Documents/Neat/CORE_MIGRATION_TODO.md)
- Can a normal `construct` store a `@core construct` member as plain inline value data?
  - tracked in [`CORE_MIGRATION_TODO.md`](/Users/george/Documents/Neat/CORE_MIGRATION_TODO.md)
- Should `String` really be `Comparable`, and if so what exact ordering semantics should that imply?
- Should `Float` really be `Hashable`/`Comparable` as-is, given future NaN/ordering semantics?
- When should `Set` / `Dictionary` get `Equatable` / `Hashable` conformances?
- When should type sugar like `T? -> Optional<T>` be documented/formalized beyond current compiler behavior?

## Next Step
- Start tightening conformance relationships for collection and optional types:
  - `Optional<Wrapped: Equatable>: Equatable`
  - `Array<Element: Equatable>: Equatable`
  - `Set<Element: Equatable>: Equatable`
  - `Dictionary<Key: Equatable, Value: Equatable>: Equatable`
- If that feels too early, the alternative next step is to document the current `NeatCore` surface explicitly in a top-level `NeatCore/README.md`.

## Verification
- Commands run successfully:
  - `cd /Users/george/Documents/Neat/NeatSyntax && swift build`
  - `cd /Users/george/Documents/Neat/NeatCLI && swift build`
  - `cd /Users/george/Documents/Neat/NeatCLI && ./.build/debug/NeatCLI artifacts ../NeatPlayground --output /Users/george/Documents/Neat/NeatPlayground/.neat/Artifacts`
- Current generated artifact path:
  - [`NeatPlayground/.neat/Artifacts`](/Users/george/Documents/Neat/NeatPlayground/.neat/Artifacts)
- Current warning status:
  - `NeatSyntax` still has an unrelated unhandled markdown warning for [`Macros.Phase.md`](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/Macros.Phase.md)
