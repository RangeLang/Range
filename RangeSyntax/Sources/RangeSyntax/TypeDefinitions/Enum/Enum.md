# Enum

## Definition

An enum is a sum type with a fixed set of cases.

## Role

`enum` models a closed set of possibilities.

## Mental Model

- `enum` = fixed set of cases
- `construct` = identity-bearing thing

## Properties

- Fixed set of cases
- Can carry associated values
- Can have raw values
- Can contain nested enums
- Can define methods on the enum itself
- Exhaustive `switch` is enforced by the compiler

## Examples

```gradient
enum Direction {
    case north
    case south
    case east
    case west
}
```

```gradient
enum Result {
    case success(String)
    case failure(Error)
}
```

```gradient
enum Planet: Int
```

## Notes

- Enums are not identity-bearing.
- Enums are not inherited from.
- Enums are not instantiated like ordinary objects.
- Gradient enums are intended to behave as compiler-checked tagged unions.

## Composition

If an enum case wraps another enum, the compiler may flatten matching syntax so switching over nested enums can stay direct rather than deeply nested.

## Open Questions

- How raw values are represented in the AST
- What the exact surface for enum methods is
- How nested enums should be represented in the parser and AST
- How enum composition and flattened matching should be specified precisely
