# Protocol

## Definition

A protocol is an abstract, non-instantiable type definition that describes shared behavior.

## Role

`protocol` defines capability and contract rather than concrete identity-bearing data.

## Mental Model

- `construct` = concrete shape and data
- `protocol` = abstract capability and contract

## Properties

- Non-instantiable
- Can be inherited by constructs
- Can inherit from other protocols
- Can declare functions with or without bodies
- Supports both requirements and default implementations

## Generic Form

Protocols use direct generic parameters rather than a separate `associatedtype` mechanism.

Examples:

```neat
protocol Container<Item>

protocol Mapping<Input: Comparable, Output>
```

`where` is reserved for genuinely relational constraints between type parameters.

## Conflict Rule

If two inherited protocols provide the same default function implementation, that is a compile error. A construct inheriting both protocols must implement that function explicitly.

## Notes

- `protocol` is the main abstraction mechanism in Neat.
- Protocols are intended to stay lightweight and composable.
- Generic protocols are meant to be expressed directly, without extra conceptual layers.

## Open Questions

- What the exact protocol body surface is beyond functions
- How protocol generic syntax should be represented in the AST
- Whether protocol default implementations have any restrictions relative to construct functions
