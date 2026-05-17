# Construct Identity

## Definition

Every construct is identity-bearing by default.

## Role

Construct identity lets Neat model real relationships without making users choose between separate class and struct worlds.

## Mental Model

Constructs are identity-bearing, but that does not mean every construct relationship is literal inline storage.

Construct-to-construct members preserve construct identity in the graph, which keeps recursive models legal.

## Properties

- Constructs have value semantics by default

```neat
construct User {
    let name: String
}
```

- Every construct has an implicit compiler-synthesized `ID`

```neat
construct User {
    let name: String
}

let userID: User.ID
```

- The identity used by the graph is distinct from ordinary user-defined fields

```neat
construct User {
    let id: UUID
    let name: String
}

let userID: User.ID
```

- References to other constructs are identity references

```neat
construct Author {
    let name: String
}

construct Book {
    let title: String
    let author: Author
}
```

`author: Author` is surface syntax. The graph treats it as a reference through `Author.ID`.

- Construct relationships do not imply literal inline containment

```neat
construct Author {
    let name: String
}

construct Book {
    let title: String
    let author: Author
}
```

`Book` does not literally contain `Author` as stored nested data. The relationship is tracked through identity.

- Recursive construct references are legal

```neat
construct FileNode {
    let name: String
    let parent: FileNode
}
```

Recursive construct references are legal because construct members preserve construct identity in the graph rather than demanding infinite inline size.

- Cycles between constructs are safe

```neat
construct User {
    let manager: User
}
```

Cycles are safe because construct references are identity references, not containment.

## Notes

- `User.ID` is the compiler-provided identity type for `User`.
- Ordinary fields such as `let id: UUID` are user-facing data and do not replace the intrinsic construct identity.
- `construct` identity is part of the language model even though user code does not choose a separate reference type.
- Foundational plain-value types such as `Int` belong to `@language construct`, not this identity model.
- Compiler structural constructs such as `Closure` and `Block` may also belong to `@language construct` when they are non-identity-bearing values.

## Open Boundary

The following identity details are not fully settled yet:

- how construct identity behaves across copies
- how much of `Type.ID` is directly exposed in ordinary user code

## Implementation Note

Constructs may still use optimizations such as copy-on-write internally when that preserves the same observable value semantics.

Those optimizations do not change the language rule that ordinary assignment is not the shared-reference mechanism. Shared live access remains the role of `binding`.
