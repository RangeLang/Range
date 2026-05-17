# NeatCore

`NeatCore` is Neat's bootstrap foundation.

The language implementation is currently hosted by Swift, but Neat's foundational data types and protocols are defined here as ordinary `.neat` source instead of being baked into the compiler as ad hoc builtins.

This keeps the boundary clear:

- The compiler owns parsing, semantic analysis, lowering, runtime machinery, and a small set of bootstrap hooks.
- `NeatCore` owns the everyday foundational surface that Neat programs should see as language-native library definitions.

## Purpose

`NeatCore` exists so the compiler does not have to hardcode Neat's basic data model.

That means types such as `Int`, `String`, `Bool`, `Optional`, `Array`, `Dictionary`, and `Set`, along with foundational protocols such as `Equatable`, `Hashable`, and `Comparable`, live in Neat source and are loaded through the normal compiler pipeline.

If the compiler has special knowledge of one of these types, that knowledge should be treated as bootstrap or lowering behavior, not as evidence that the type is intrinsically built into the language.

## Current Structure

### `DataSystem`

The main foundational type and protocol layer:

- Scalar/data families: `Int`, `String`, `Bool`, `Float`, `Data`, `Void`
- Scalar storage families: `IntStorage`, `StringStorage`, `BoolStorage`, `FloatStorage`
- Literal carrier types: `IntLiteral`, `StringLiteral`, `BoolLiteral`, `FloatLiteral`, `NilLiteral`, `ArrayLiteral`, `DictionaryLiteral`, `SetLiteral`
- Literal bridge protocols: `ExpressibleByIntLiteral`, `ExpressibleByStringLiteral`, `ExpressibleByBoolLiteral`, `ExpressibleByFloatLiteral`, `ExpressibleByNilLiteral`, `ExpressibleByArrayLiteral`, `ExpressibleByDictionaryLiteral`, `ExpressibleBySetLiteral`
- Core generic data types: `Optional`, `Array`, `Dictionary`, `Set`
- Collection storage families: `ArrayStorage`, `DictionaryStorage`, `SetStorage`
- Foundational protocols: `Equatable`, `Hashable`, `Comparable`
- Supporting enums: `Signedness`, `FloatingPointWidth`

These definitions are intentionally minimal. They describe the language-facing model first; they do not yet imply that every type already has a complete runtime/storage implementation behind it.

### `Operators`

The intended language-owned home for explicit operator and precedence declarations.

This is where Neat's operator model is being documented as it moves out of compiler bootstrap logic and toward source-defined language rules.

### `Macros/Exploration`

Exploratory macro and metaprogramming material.

This directory is intentionally excluded from normal core loading. It is a staging area for experiments, not part of the active bootstrap surface.

## Current Design Rules

- `construct` is the normal identity-bearing modeling form.
- `@language construct` is compiler-recognized, non-identity-bearing, and intended for plain structural/bootstrap data.
- Members inside an `@language construct` may omit bodies when the operation is backed by compiler, runtime, or backend behavior. This is how semantic boundary types such as `ArrayStorage`, `DictionaryStorage`, `SetStorage`, and scalar storage types describe operations whose implementation is not written in Neat yet.
- Top-level `@language function` declarations may omit bodies when the operation is backed by compiler, runtime, or backend behavior. This is how primitive operator signatures can live in `NeatCore` without recursively implementing themselves in Neat.
- `@language protocol` declarations define compiler-recognized semantic categories. `@language` does not cascade through protocol conformance; each language declaration must be explicitly marked.
- The memory graph is foundational and always generated.
- Reactivity is an optional exposed layer derived from the memory graph, not a separate base system.
- Literal bridging is defined by `#literal<T>` on `init(literal: T)`, where `T` is a compiler-recognized literal carrier type. Protocol requirements may carry the same macro onto conforming initializers, but direct initializer attachment is the base form.
- The compiler recognizes the literal carrier types themselves, such as `IntLiteral`, `StringLiteral`, `BoolLiteral`, `FloatLiteral`, `NilLiteral`, `ArrayLiteral`, `DictionaryLiteral`, and `SetLiteral`.
- Everything beyond carrier recognition is modeled as literal bridge macro behavior on concrete initializers, with protocol conformance acting as an optional carry layer on top.
- Language-facing wrapper types increasingly use dedicated `...Storage` members as the semantic representation boundary. This keeps wrapper semantics in `NeatCore` while leaving backend/runtime realization free to evolve behind those storage types.
- Type sugar and literal sugar are still separate concerns. For example, `#literal<NilLiteral>` is part of the core surface, while `T? -> Optional<T>` remains compiler type sugar.
- Literal meaning is settled on the Neat side before any target backend runs. A semantic result such as `Int(literal: 5)` belongs to Neat correctness even if a backend later lowers it to a target-native form.

## Current Limits

`NeatCore` is still an early foundation layer. In particular:

- Collection storage/lowering is not complete yet.
- Scalar and collection `...Storage` types are still semantic boundary types rather than fully realized runtime/storage implementations.
- `Set` and `Dictionary` do not yet have full `Equatable` or `Hashable` conformances.
- `Hasher` exists as a public core surface, but its storage and mixing behavior are still bootstrap/runtime responsibilities.
- Conformance synthesis and macro-driven derivation are still exploratory.
- Some language sugar is supported by the compiler but not yet fully documented as formal language rules.

## Loading Model

`NeatCore` is loaded by `NeatCLI` through the same Swift-based compiler pipeline used for other Neat source. The point is not to eliminate the compiler's bootstrap role, but to keep that role narrow and explicit.

In short: Swift hosts the compiler today, but Neat's basic world should increasingly be described in Neat.

## Boundary Note

Swift may define compiler implementation types such as parser enums, lowering state, backend structures, and other internal machinery.

Neat should define the language-visible type world.

More precisely:

- Neat and `NeatCore` define language semantics.
- A backend such as Swift may adapt those settled semantics to a target representation.
- Target adaptation must not become the source of truth for language meaning.
- Wrapper types such as `Int`, `String`, `Array`, `Dictionary`, and `Set` may delegate representation concerns to `...Storage` types without giving up their role as the semantic source of truth.

That means foundational language types and protocols such as `Int`, `String`, `Bool`, `Float`, `Data`, `Optional`, `Array`, `Dictionary`, `Set`, `Equatable`, `Hashable`, and `Comparable` belong in `NeatCore`, not as the real source of truth inside Swift compiler enums.
