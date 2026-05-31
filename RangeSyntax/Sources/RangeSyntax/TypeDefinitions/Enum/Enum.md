# Enum

## Definition

An enum is a sum type with a fixed set of cases unless it is explicitly
declared open.

## Role

`enum` models a closed set of possibilities by default. `open enum` allows
cases to be added later from extensions.

## Mental Model

- `enum` / `closed enum` = fixed set of cases
- `open enum` = case set can grow through extensions
- `construct` = identity-bearing thing

## Properties

- Fixed set of cases
- Can carry associated values
- Can have raw values
- Can contain nested enums
- Can define methods on the enum itself
- Exhaustive `switch` is enforced by the compiler

## Examples

```range
enum Direction {
    case north
    case south
    case east
    case west
}
```

```range
open enum EncodingFormat {
    case json
}

extension EncodingFormat {
    case binary
}
```

```range
enum Result {
    case success(String)
    case failure(Error)
}
```

```range
enum Planet: Int
```

## Notes

- Enums are not identity-bearing.
- Enums are not inherited from.
- Enums are not instantiated like ordinary objects.
- Range enums are intended to behave as compiler-checked tagged unions.

## Composition

If an enum case wraps another enum, the compiler may flatten matching syntax so switching over nested enums can stay direct rather than deeply nested.

## Open Questions

- How raw values are represented in the AST
- What the exact surface for enum methods is
- How nested enums should be represented in the parser and AST
- How enum composition and flattened matching should be specified precisely
