# Self Description Before Self Hosting

Neat does not need to be fully self-hosted before it can start describing itself.

## Observation

Self-hosting means the compiler is written in the language it compiles.

Self-description is smaller and earlier: the language-visible world is written in the language itself, even while the compiler is still hosted by another implementation language.

## Shape

```neat
@language
construct Int<let bits: IntLiteral, let signedness: Signedness = .signed>: ExpressibleByIntLiteral {
    let storage: IntStorage
}

@language
construct Array<Element>: ExpressibleByArrayLiteral {
    let storage: ArrayStorage<Element>
}

@language
function +(lhs: Int, rhs: Int) -> Int
```

These declarations do not remove the compiler's bootstrap role.

They move the source of language meaning into Neat source.

```text
Swift-hosted compiler
  parses Neat
  checks NeatCore
  lowers settled Neat semantics

NeatCore
  describes Int
  describes Array
  describes literal bridges
  describes operators
```

The compiler may still know how to lower `IntStorage`.

The language meaning of `Int` still lives in `Int.neat`.

## Reason

Self-hosting is an implementation milestone. Self-description is a language-design milestone.

The second can happen first.

That matters because it keeps bootstrap hooks narrow. Swift can host parsing, checking, and lowering today, but it should not become the permanent source of truth for Neat's basic world.

The better direction is gradual: more of the language-facing model moves into `.neat` files, while the host compiler keeps only the machinery needed to load, validate, and lower that model.
