# Memory Graph

## Definition

The memory graph is Neat's static model of ownership, storage, borrowing, identity, mutation, and dependency. It is a compiler graph, not a runtime system.

## Role

The memory graph gives the compiler enough information to prove memory safety, determine when storage can be freed, and serve as the substrate for later reactive invalidation. The same underlying graph can be viewed from a memory-management angle or a reactivity angle.

## Mental Model

- Neat does not bolt reactivity on top of an unrelated ownership system. The storage declaration keywords define both ownership intent and dependency shape.
- The memory graph is not a dynamic runtime trace. It is a static semantic graph produced by the compiler.
- The reactivity graph is not a separate foundation. It is an exposed view derived from the same underlying graph once dependency and invalidation rules are applied.
- Neat aims for compile-time memory reasoning like Rust, but derives ownership from surface declarations instead of requiring explicit borrow and lifetime syntax everywhere.

## Properties

- The storage declaration keywords define ownership semantics.

```neat
value title: String
state person: Person
derived personString: String
binding selectedPerson: Person
environment session: Session
```

- `value` is immutable owned data declared here.

```neat
value title: String = "Neat"
```

The compiler does not need to track mutation for `value`.

- `state` is mutable owned storage with a single source of truth.

```neat
state count: Int = 0
count += 1
```

`state` is the compiler-known owner of mutable storage.

- `derived` owns no storage and is always reconstructed from dependencies.

```neat
derived fullName: String {
    firstName + " " + lastName
}
```

`derived` is present in the memory graph as a dependency node, not as owned mutable storage.

- `binding` is borrowed storage whose owner lives elsewhere.

```neat
construct Editor {
    binding person: Person
}
```

`binding` creates an alias or borrowed path into existing storage rather than introducing new ownership.

- `environment` is inherited storage from a higher scope.

```neat
environment theme: Theme
```

`environment` participates in the graph as externally provided storage rather than locally owned storage.

- Ownership intent is declared by keyword rather than by extra borrow syntax.

```neat
state person: Person
binding selectedPerson: Person
```

The difference between owned mutable storage and borrowed access is part of the language surface.

- Construct references are identity references in the memory graph.

```neat
construct Author {
    value name: String
    value books: [Book]
}

construct Book {
    value title: String
    value author: Author
}
```

`author: Author` is surface syntax. In the memory graph, construct-to-construct relationships are tracked through compiler-synthesized identity rather than literal nested containment.

- Every construct is identity-bearing even when identity is not written explicitly.

```neat
construct User {
    value name: String
}
```

The graph can refer to `User` instances by intrinsic identity without requiring `userID: UUID` in user code.

- Cycles between constructs are graph-safe because construct references are identity references.

```neat
construct User {
    value manager: User
}
```

This does not imply infinitely nested storage.

- The memory graph models mutation paths, not just declarations.

```neat
state person: Person = Person(name: "George", age: 26)
person.age += 1
```

The graph must represent that `person` owns mutable storage and that `person.age` is mutated through that storage path.

- The memory graph models aliasing through bindings.

```neat
state person: Person = Person(name: "George", age: 26)
state user: User = User(person: $person)
```

If `User.person` is a binding, the graph records that `user.person` aliases existing storage owned by `person`.

- The memory graph records derived dependencies.

```neat
derived personString: String {
    "Person: \(person.name), Age: \(person.age)"
}
```

`personString` depends on the memory locations read through `person.name` and `person.age`.

- Function bodies can contribute mutation and dependency edges to the graph.

```neat
construct User {
    binding person: Person

    function incrementAge() {
        person.age += 1
    }
}
```

The graph records that `incrementAge` mutates storage reachable through the `person` binding.

- The memory graph can be compiled at different levels.

```neat
@noMemoryGraph
package LowLevelRuntime
```

Neat supports full graph analysis by default, ownership-focused analysis where reactive invalidation is not needed, and graph-free packages for explicitly low-level code.

- Memory graph information composes across modules.

```neat
package UI
package Domain
```

When packages interact, the compiler merges the relevant graph information at build time rather than relying on runtime ownership machinery.

## Examples

```neat
@main {
    state person: Person = Person(name: "George", age: 26)
    person.age += 1

    derived personString: String {
        "Person: \(person.name), Age: \(person.age)"
    }

    state user: User = User(person: $person)
    user.incrementAge()
}

construct Person {
    value name: String
    value age: Int
}

construct User {
    binding person: Person

    function incrementAge() {
        person.age += 1
    }
}
```

The memory graph for this code includes:

- owned mutable storage for `person`
- mutation of `person.age`
- a derived node for `personString`
- dependency edges from `personString` to `person.name` and `person.age`
- owned mutable storage for `user`
- an alias edge from `user.person` to the storage owned by `person`
- a mutation effect from `user.incrementAge()` to `person.age`

## Notes

- The memory graph is the semantic foundation for later exposed reactivity behavior, but reactivity rules are documented separately.
- The graph is intended to be solvable from Neat's constrained storage model without general-purpose borrow annotations.
- This document defines the memory-side model only. It does not yet specify the separate reactive invalidation view in detail.
