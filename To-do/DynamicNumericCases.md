# Dynamic Numeric Cases

Some numeric models need more than listed enum cases and more than ordinary
finite literals.

The important distinction is that infinity is not stored as an `Int` payload and
it is not hidden behind generic semantic tag storage. Dynamic integer signedness
is expressed directly in the case space.

## Intended Surface

The expressive surface should be able to write:

```range
.infinity<+>
.infinity<->
.zero
1
2
3
4
5
6
7
-6
-5
```

That means the value space has direct members:

- finite numeric literals, such as `1`, `2`, `-6`, and `-5`
- direct semantic cases, such as `.zero`, `.infinity<+>`, and `.infinity<->`

The tags enrich the model. They are not strings and they are not fake integers.
They are typed metadata that the graph and backends can branch on.

## Core Storage Shape

The active core spelling should be direct:

```range
enum DynamicInt {
    case negativeInfinity
    case finite(value: Int)
    case zero
    case positiveInfinity
}
```

This keeps normal integer values finite while allowing the model to carry dynamic
semantic cases. Positive and negative infinity are direct links in the value
space, not payloads inside a generic storage wrapper.

## Syntax Direction

The desired shorthand:

```range
.infinity<+>
.infinity<->
```

should lower to the same semantic storage as:

```range
DynamicInt.positiveInfinity
DynamicInt.negativeInfinity
```

The `+` and `-` tokens are not arithmetic here. They are sign metadata inside a
semantic tag application, and they link directly to the corresponding dynamic
integer case.

`.zero` is a direct case because it often has special algebraic meaning. It can
still lower to numeric `0` when a backend needs a plain integer, but the model
should not lose the fact that the user wrote the named zero case.

## Why This Matters

This is how Range can express open or dynamic case spaces:

- `Bool` is a closed binary value space: `true` or `false`
- an enum is a closed named case space unless metadata says otherwise
- `DynamicInt` is a finite-literal stream plus direct semantic cases

That gives the compiler a typed place to attach infinity, zero, bounds, unbounded
surfaces, and generated cases without pretending they are all ordinary enum
cases or ordinary integers.
