# Primitive

## Definition

`primitive` marks a type definition as compiler-implemented rather than implemented in ordinary Neat code.

## Role

`primitive` exists to expose the compiler basement explicitly in the language surface.

It makes compiler-known foundations visible in stdlib code instead of hiding them as unnamed language magic.

## Applies To

- `primitive construct`
- `primitive enum`
- `primitive protocol`

## Meaning

- The declaration is real Neat surface syntax.
- The compiler is responsible for its implementation.
- Ordinary Neat code is expected to build on top of primitive declarations.
- `primitive` changes implementation origin, not declaration shape.
- Bodies are allowed wherever the underlying declaration kind normally allows a body.

## Examples

```neat
primitive protocol Digit

primitive enum Bit: Digit {
    case zero
    case one
}

primitive construct RawInt

construct Int<value bits: RawInt, value signedness: Signedness = .signed> {
    value data: [Bit]
}
```

## Notes

- `primitive` is a modifier on a type definition, not a standalone declaration category.
- A primitive declaration may omit its body because no ordinary Neat implementation exists at that level.
- If a primitive declaration includes a body, that body is still part of the declaration surface.
- Primitive declarations are intended to keep the boundary between compiler and stdlib explicit.

## Open Questions

- If a primitive declaration has a body, whether that body is interface-only or semantically enforced
- Whether primitive declarations are restricted to stdlib or compiler-owned modules
- How `primitive` should be represented in the AST and parser
- How compiler-native values such as `RawInt` participate in value-generic positions
