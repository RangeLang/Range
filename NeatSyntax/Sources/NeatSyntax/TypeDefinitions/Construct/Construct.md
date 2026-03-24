# Construct

## Definition

A construct is an identity-bearing struct.

## Example

```neat
construct User {
    value name: String
    value age: Int
}
```

## Properties

- Instantiable
- Always fully concrete
- Can inherit from other constructs
- Can conform to protocols

## Notes

- `construct` defines a concrete runtime type.
- A construct carries identity rather than being a purely structural value.

## Open Questions

- What inheritance means for constructs in Neat
- Whether construct inheritance is single or multiple
- How identity is represented at runtime
- Whether all constructs have the same construction model
