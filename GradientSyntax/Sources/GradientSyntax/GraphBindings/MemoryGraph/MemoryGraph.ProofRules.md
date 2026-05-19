# Memory Graph Proof Rules

## Definition

This document defines the invariants the compiler must enforce to treat the memory graph as a proof system rather than a visualization.

## Role

The rules here are the contract for memory safety in Neat's storage model. If any invariant is violated, compilation fails.

## Mental Model

- `let`, `state`, `binding`, and `derived` are ownership declarations, not style hints.
- The memory graph is the canonical semantic model used for validation.
- Reactivity is layered on top later; these rules are memory-first.

## Invariants

- Every mutable write target must resolve to mutable storage.

```neat
state count: Int = 0
count += 1
```

- `let` is immutable after initialization.

```neat
let name: String = "George"
name = "Ava" // invalid
```

- Mutation through a `let` root is always invalid, including member-path mutation.

```neat
let person: Person(name: "George", age: 26)
person.age = 27 // invalid
```

- `derived` owns no mutable storage and cannot be assignment targets.

```neat
derived title: String { name }
title = "x" // invalid
```

- `binding` must alias existing storage; it cannot create ownership.

```neat
state person: Person = Person(name: "George", age: 26)
state user: User = User(person: $person)
```

- `let` cannot store a construct type that declares `binding` members.

```neat
let user: User(person: $person) // invalid if User contains binding members
```

- Assigning a construct from `let` into `state` performs an owned copy, not aliasing.

```neat
let person: Person(name: "George", age: 26)
state statefulPerson: Person = person
```

`statefulPerson` is independent storage. Mutating `statefulPerson` does not mutate `person`.

- Construct references are identity references, not nested ownership.

```neat
construct Book {
    let author: Author
}
```

- `construct` member `state` may be declared without a default, but must be initialized by construction unless a default exists.

```neat
construct Person {
    let name: String
    state age: Int
}
```

- Top-level `state` must have an initializer.

```neat
state counter: Int = 1
```

- Local block `state` must have an initializer.

```neat
@main {
    state counter: Int = 1
}
```

- Function call effects must be represented as graph reads/writes/aliases on reachable storage paths.

```neat
function incrementAge() {
    person.age += 1
}
```

## Rejection Rules

- Reject assignment to immutable storage (`let`, constants).
- Reject unresolved mutable targets.
- Reject uninitialized required construct members at construction sites.
- Reject invalid binding sources (non-addressable, temporary, or incompatible storage).
- Reject alias paths that violate ownership constraints.
- Reject mutation effects that escape allowed storage paths.
- Reject `let` declarations whose type declares `binding` members.
- Reject mutation attempts through `let` roots, including member-path writes.

## Examples

Valid:

```neat
construct Person {
    let name: String
    state age: Int
}

@main {
    state person: Person = Person(name: "George", age: 26)
    person.age += 1
}
```

Invalid:

```neat
construct Person {
    let name: String
    state age: Int
}

@main {
    state person: Person = Person(name: "George") // missing age
}
```

Valid:

```neat
@main {
    let person: Person(name: "George", age: 26)
    state statefulPerson: Person = person
    statefulPerson.age = 27
}
```

Invalid:

```neat
@main {
    let person: Person(name: "George", age: 26)
    person.age = 27
}
```

Invalid:

```neat
@main {
    state person: Person = Person(name: "George", age: 26)
    let user: User(person: $person) // User has binding members
}
```

Invalid:

```neat
@main {
    state counter: Int // invalid local state without initializer
}
```

Invalid:

```neat
state counter: Int // invalid top-level state without initializer
```

Valid:

```neat
construct Person {
    let name: String
    state age: Int
}

@main {
    state person: Person = Person(name: "George", age: 26)
}
```

## Notes

- This ruleset is intentionally strict to keep ownership solvable from declarations.
- Compiler implementation may stage these checks over multiple passes, but all listed invariants are the target contract.
