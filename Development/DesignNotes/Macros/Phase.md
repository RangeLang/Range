# Macro Phase

## Immediate Declaration Macros
An immediate declaration-targeted macro expands on the declaration it is directly attached to.

```range
#clamped(min: 0, max: 10)
state count: Int = 0
```

`#clamped` expands on that `state` declaration itself.

The same base rule applies to literal carrier constructs:

```range
@literal
construct IntLiteral { }

construct Int {
    function literal(literal: IntLiteral): Self { }
}
```

Here `@literal` belongs to the carrier construct, not the bridge function.

For primitive literal bridging, the bridge function parameter must use a compiler-recognized literal carrier construct such as `IntLiteral`, `StringLiteral`, `BoolLiteral`, `FloatLiteral`, or `NilLiteral`. Collection constructs such as `Array`, `Dictionary`, and `Set` can carry `@literal` directly.

## Deferred Conformance Macros
A protocol can also carry macros targeted at declaration kinds that conform to it, such as constructs or enums.

```range

protocol Equatable {
    function ==(lhs: Self, rhs: Self): Bool
}
```

`` does not expand on the protocol body itself. It is carried by the protocol and expands when a conforming declaration of the matching kind is realized.

## Rule
Macros attached to protocol requirements or protocols themselves are part of that protocol's semantics. They expand when those semantics are realized by a concrete conforming declaration of the matching kind.

For literal bridging specifically:

- `@literal` is the canonical carrier form.
- The literal bridge function parameter type is a carrier construct recognized by the compiler.
- The compiler recognizes literal categories and carrier types.
- A concrete carrier construct carries `@literal` directly.
- The macro model rewrites concrete use sites through the realized literal function.
- This rewrite is part of Range semantic correctness, not backend adaptation.
- A semantic rewrite such as `5 -> Int.literal(literal: 5)` is the correct Range result even if a backend later chooses a different target-specific representation.

## Backend Boundary

Literal bridge realization belongs to the Range semantic phase.

- The semantic phase decides what a literal means in Range.
- A backend phase decides how to represent that meaning in a target language such as Swift or C.
- Backend adaptation must not replace declaration-graph literal resolution as the source of truth.

For example:

- semantic result: `Int.literal(literal: 5)`
- Swift backend adaptation may later lower that to a Swift-native form

The important boundary is that the backend may adapt a settled semantic result, but it does not define literal meaning.
