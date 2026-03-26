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

- Scalar families: `Int`, `String`, `Bool`, `Float`
- Literal carrier types: `IntLiteral`, `StringLiteral`, `BoolLiteral`, `FloatLiteral`, `NilLiteral`, `ArrayLiteral`, `DictionaryLiteral`, `SetLiteral`
- Literal bridge protocols: `ExpressableByIntLiteral`, `ExpressableByStringLiteral`, `ExpressableByBoolLiteral`, `ExpressableByFloatLiteral`, `ExpressableByNilLiteral`, `ExpressableByArrayLiteral`, `ExpressableByDictionaryLiteral`, `ExpressableBySetLiteral`
- Core generic data types: `Optional`, `Array`, `Dictionary`, `Set`
- Foundational protocols: `Equatable`, `Hashable`, `Comparable`
- Supporting enums: `Signedness`, `FloatingPointWidth`

These definitions are intentionally minimal. They describe the language-facing model first; they do not yet imply that every type already has a complete runtime/storage implementation behind it.

### `Primitives`

Low-level compiler-facing building blocks such as `Bit` and `Byte`.

These are closer to the implementation boundary than the main `DataSystem` layer.

### `Macros/Exploration`

Exploratory macro and metaprogramming material.

This directory is intentionally excluded from normal core loading. It is a staging area for experiments, not part of the active bootstrap surface.

## Current Design Rules

- `construct` is the normal identity-bearing modeling form.
- `@core construct` is compiler-recognized, non-identity-bearing, and intended for plain structural/bootstrap data.
- The memory graph is foundational and always generated.
- Reactivity is an optional exposed layer derived from the memory graph, not a separate base system.
- Literal bridging currently uses `#literal(...)` protocols plus empty literal carrier types.
- Type sugar and literal sugar are still separate concerns. For example, `#literal(NilLiteral)` is part of the core surface, while `T? -> Optional<T>` remains compiler type sugar.

## Current Limits

`NeatCore` is still an early foundation layer. In particular:

- Collection storage/lowering is not complete yet.
- `Set` and `Dictionary` do not yet have full `Equatable` or `Hashable` conformances.
- There is no public `Hasher` model yet.
- Conformance synthesis and macro-driven derivation are still exploratory.
- Some language sugar is supported by the compiler but not yet fully documented as formal language rules.

## Loading Model

`NeatCore` is loaded by `NeatCLI` through the same Swift-based compiler pipeline used for other Neat source. The point is not to eliminate the compiler's bootstrap role, but to keep that role narrow and explicit.

In short: Swift hosts the compiler today, but Neat's basic world should increasingly be described in Neat.
