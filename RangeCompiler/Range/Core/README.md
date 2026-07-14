# RangeCore

`RangeCore` is Range's bootstrap foundation.

The language implementation is currently hosted by Swift, but Range's foundational data types and protocols are defined here as ordinary `.range` source instead of being baked into the compiler as ad hoc builtins.

This keeps the boundary clear:

- The compiler owns parsing, semantic analysis, lowering, runtime machinery, and a small set of bootstrap hooks.
- `RangeCore` owns the everyday foundational surface that Range programs should see as language-native library definitions.

## Purpose

`RangeCore` exists so the compiler does not have to hardcode Range's basic data model.

That means types such as `Int`, `String`, `Bool`, `Optional`, `Array`, `Dictionary`, and `Set`, along with foundational protocols such as `Equatable`, `Hashable`, and `Comparable`, live in Range source and are loaded through the normal compiler pipeline.

If the compiler has special knowledge of one of these types, that knowledge should be treated as bootstrap or lowering behavior, not as evidence that the type is intrinsically built into the language.

## Current Structure

### `DataSystem`

The main foundational type and protocol layer:

- Scalar/data families: `Int`, `String`, `Bool`, `Float`, `Data`, `Void`
- Scalar storage families: `IntStorage`, `StringStorage`, `BoolStorage`, `FloatStorage`
- Literal carrier/value constructs: `IntLiteral`, `StringLiteral`, `BoolLiteral`, `FloatLiteral`, `NilLiteral`, `Array`, `Dictionary`, `Set`
- Core generic data types: `Optional`, `Array`, `Dictionary`, `Set`
- Collection storage families: `ArrayStorage`, `DictionaryStorage`, `SetStorage`
- Foundational protocols: `Equatable`, `Hashable`, `Comparable`
- Supporting enums: `Signedness`, `FloatingPointWidth`

These definitions are intentionally minimal. They describe the language-facing model first; they do not yet imply that every type already has a complete runtime/storage implementation behind it.

### `Operators`

The intended language-owned home for explicit operator and precedence declarations.

This is where Range's operator model is being documented as it moves out of compiler bootstrap logic and toward source-defined language rules.

### `Macro`

The compiler-facing macro surface, including macro declarations,
diagnostics, and syntax rewrite/expansion protocols.

### `../Foundation/Macros`

Compiler-bundled macro implementations are shipped from Foundation rather than
Core. They are available by default, but are not part of the minimal core
surface.

## Current Design Rules

- `construct` is the normal identity-bearing modeling form.
- `@builtin` is a compiler-owned RangeCore attribute. It has one canonical spelling and no compatibility alias.
- `@builtin construct` is compiler-recognized, non-identity-bearing, and intended for plain structural/bootstrap data.
- Members inside an `@builtin construct` may omit bodies when the operation is backed by compiler, runtime, or backend behavior. This is how semantic boundary types such as `ArrayStorage`, `DictionaryStorage`, `SetStorage`, and scalar storage types describe operations whose implementation is not written in Range yet.
- Top-level `@builtin function` declarations may omit bodies when the operation is backed by compiler, runtime, or backend behavior. This is how primitive operator signatures can live in `RangeCore` without recursively implementing themselves in Range.
- `@builtin protocol` declarations define compiler-recognized semantic categories. `@builtin` does not cascade through protocol conformance; each builtin declaration must be explicitly marked.
- The memory graph is foundational and always generated.
- Reactivity is an optional exposed layer derived from the memory graph, not a separate base system.
- Literal-capable constructs are marked by `@literal`, such as `IntLiteral`, `StringLiteral`, `BoolLiteral`, `FloatLiteral`, `NilLiteral`, `Array`, `Dictionary`, and `Set`.
- Literal bridging for primitive syntax is derived from concrete `literal(literal: T)` functions whose parameter type is one of those carrier constructs; collection literals are handled by the collection constructs directly.
- Everything beyond carrier recognition is modeled as ordinary Range initialization and function behavior.
- Language-facing wrapper types increasingly use dedicated `...Storage` members as the semantic representation boundary. This keeps wrapper semantics in `RangeCore` while leaving backend/runtime realization free to evolve behind those storage types.
- Type sugar and literal sugar are still separate concerns. For example, `@literal` is part of the core surface, while `T? -> Optional<T>` remains compiler type sugar.
- Literal meaning is settled on the Range side before any target backend runs. A semantic result such as `Int(literal: 5)` belongs to Range correctness even if a backend later lowers it to a target-native form.

## Current Limits

`RangeCore` is still an early foundation layer. In particular:

- Collection storage/lowering is not complete yet.
- Scalar and collection `...Storage` types are still semantic boundary types rather than fully realized runtime/storage implementations.
- `Set` and `Dictionary` do not yet have full `Equatable` or `Hashable` conformances.
- `Hasher` exists as a public core surface, but its storage and mixing behavior are still bootstrap/runtime responsibilities.
- Conformance synthesis and macro-driven derivation are still exploratory.
- Some language sugar is supported by the compiler but not yet fully documented as formal language rules.

## Loading Model

`RangeCore` is loaded by the Range script runner through the same Swift-based compiler pipeline used for other Range source. The point is not to eliminate the compiler's bootstrap role, but to keep that role narrow and explicit.

In short: Swift hosts the compiler today, but Range's basic world should increasingly be described in Range.

## Boundary Note

Swift may define compiler implementation types such as parser enums, lowering state, backend structures, and other internal machinery.

Range should define the language-visible type world.

More precisely:

- Range and `RangeCore` define language semantics.
- A backend such as Swift may adapt those settled semantics to a target representation.
- Target adaptation must not become the source of truth for language meaning.
- Wrapper types such as `Int`, `String`, `Array`, `Dictionary`, and `Set` may delegate representation concerns to `...Storage` types without giving up their role as the semantic source of truth.

That means foundational language types and protocols such as `Int`, `String`, `Bool`, `Float`, `Data`, `Optional`, `Array`, `Dictionary`, `Set`, `Equatable`, `Hashable`, and `Comparable` belong in `RangeCore`, not as the real source of truth inside Swift compiler enums.
