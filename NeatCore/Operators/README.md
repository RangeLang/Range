# Operators

## Definition

Neat operators are declared explicitly as language features, following Swift's operator model. Operator declaration, precedence, and implementation are separate concerns.

## Role

Operators should be part of Neat's language-visible surface rather than permanently hardcoded inside the Swift-hosted compiler.

This gives Neat a clear place to define operator names, fixity, precedence relationships, and eventually operator-backed protocol and function behavior.

## Mental Model

An operator is not just punctuation that the parser recognizes.

An operator has:

- a declared token and fixity (`prefix`, `infix`, or `postfix`)
- an optional precedence group relationship
- a separate implementation

This is intentionally close to Swift's model because it is explicit, compact, and keeps declaration separate from behavior.

## Properties

- Neat is targeting an explicit Swift-style operator declaration model.
- Operator declarations belong to the language surface, not only to compiler internals.
- The current parser support for operators such as `+`, `??`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `||`, and `!` is temporary bootstrap behavior.
- Future operator meaning should come from Neat declarations and callable/protocol rules rather than ad hoc Swift enums.
- Precedence groups are expected to be explicit declarations rather than hidden parser tables.
- Operator implementation should stay separate from operator declaration.

## Examples

```neat
precedencegroup AdditionPrecedence {
    associativity: left
    higherThan: ComparisonPrecedence
}

infix operator +: AdditionPrecedence
prefix operator !
```

```neat
function +(left: Int, right: Int) -> Int
function !(value: Bool) -> Bool
```

## Notes

- This folder is the architectural destination for operator declarations. It does not mean the compiler already supports these declarations.
- The immediate migration goal is to shrink Swift-side builtin operator knowledge until it is only bootstrap parsing and lowering behavior.
