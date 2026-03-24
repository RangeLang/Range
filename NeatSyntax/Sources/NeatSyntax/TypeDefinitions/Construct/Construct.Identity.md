# Construct Identity

## Definition

Every construct is identity-bearing by default.

## Properties

- Constructs have value semantics by default

```neat
construct User {
    value name: String
}
```

- Every construct has an implicit compiler-synthesized `ID`

```neat
construct User {
    value name: String
}

value userID: User.ID
```

- The identity used by the graph is distinct from ordinary user-defined fields

```neat
construct User {
    value id: UUID
    value name: String
}

value userID: User.ID
```

- References to other constructs are identity references

```neat
construct Author {
    value name: String
}

construct Book {
    value title: String
    value author: Author
}
```

`author: Author` is surface syntax. The graph treats it as a reference through `Author.ID`.

- Construct relationships do not imply literal containment

```neat
construct Author {
    value name: String
}

construct Book {
    value title: String
    value author: Author
}
```

`Book` does not literally contain `Author` as stored nested data. The relationship is tracked through identity.

- Cycles between constructs are safe

```neat
construct User {
    value manager: User
}
```

Cycles are safe because construct references are identity references, not containment.

## Notes

- `User.ID` is the compiler-provided identity type for `User`.
- Ordinary fields such as `value id: UUID` are user-facing data and do not replace the intrinsic construct identity.
