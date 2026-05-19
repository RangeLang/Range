# Memory Graph

## Definition

The memory graph is Gradient's static model of ownership, storage, borrowing, identity, mutation, and dependency. It is a compiler graph, not a runtime system.

## Role

The memory graph gives the compiler enough information to prove memory safety, determine when storage can be freed, and serve as the substrate for later reactive invalidation. The same underlying graph can be viewed from a memory-management angle or a reactivity angle.

## Pipeline Position

The memory graph comes after declaration-graph realization, not before it.

The compiler pipeline should be understood as:

1. `Lexer`
2. `Parser`
3. `AST`
4. `Declaration Graph`
5. `Semantic Resolution`
6. `Memory Graph`
7. `Reactivity Graph`
8. `Backend Lowering`
9. `Emission`

This means the memory graph consumes already-settled declaration semantics. It should not be responsible for resolving protocol conformance, declaration-targeted macro carry, literal bridge meaning, or similar declaration-level facts on its own.

## Mental Model

- Gradient does not bolt reactivity on top of an unrelated ownership system. The storage declaration keywords define both ownership intent and dependency shape.
- The memory graph is not a dynamic runtime trace. It is a static semantic graph produced by the compiler.
- The reactivity graph is not a separate foundation. It is an exposed view derived from the same underlying graph once dependency and invalidation rules are applied.
- Gradient aims for compile-time memory reasoning like Rust, but derives ownership from surface declarations instead of requiring explicit borrow and lifetime syntax everywhere.

## Properties

- The storage declaration keywords define ownership semantics.

```gradient
let title: String
state person: Person
derived personString: String
binding selectedPerson: Person
```

- `let` is immutable owned data declared here.

```gradient
let title: String = "Gradient"
```

The compiler does not need to track mutation for `let`.

- `state` is mutable owned storage with a single source of truth.

```gradient
state count: Int = 0
count += 1
```

`state` is the compiler-known owner of mutable storage.

- `derived` owns no storage and is always reconstructed from dependencies.

```gradient
derived fullName: String {
    firstName + " " + lastName
}
```

`derived` is present in the memory graph as a dependency node, not as owned mutable storage.

- `binding` is borrowed storage whose owner lives elsewhere.

```gradient
construct Editor {
    binding person: Person
}
```

`binding` creates an alias or borrowed path into existing storage rather than introducing new ownership.

- Ordinary assignment is value-semantic, not implicit shared reference.

```gradient
construct Person {
    let name: String
    state age: Int
}

let person: Person(name: "George", age: 26)
state editablePerson: Person = person
```

The memory graph treats `editablePerson` as a new owned value, not as an alias to `person`.

- Copy-on-write is an implementation optimization, not a semantic aliasing rule.

```gradient
let values: [Int] = [1, 2, 3]
state editableValues: [Int] = values

editableValues.append(4)
```

The graph still treats `values` and `editableValues` as independent logical values after assignment. An implementation may share underlying storage temporarily and copy on mutation, but that storage sharing is not modeled as semantic aliasing in the memory graph.

- Shared mutable access is explicit through `binding`.

```gradient
state person: Person = Person(name: "George", age: 26)
binding selectedPerson: Person = $person
```

The graph records `selectedPerson` as borrowed access to the storage owned by `person`.

- Ownership intent is declared by keyword rather than by extra borrow syntax.

```gradient
state person: Person
binding selectedPerson: Person
```

The difference between owned mutable storage and borrowed access is part of the language surface.

- Construct references are identity references in the memory graph.

```gradient
construct Author {
    let name: String
    let books: [Book]
}

construct Book {
    let title: String
    let author: Author
}
```

`author: Author` is surface syntax. In the memory graph, construct-to-construct relationships are tracked through compiler-synthesized identity rather than literal nested containment.

- `#language construct` references stay plain type composition in the graph.

```gradient
#language
construct IntLiteral { }

#language
construct IntStorage {
    function storage(literal: IntLiteral) -> Self
}

#language
construct Int {
    let storage: IntStorage
}
```

`Int.storage` is modeled as plain value composition rather than a construct-identity relationship.

- Wrapper types may delegate representation to dedicated storage primitives.

```gradient
#language
construct ArrayStorage<Element> { }

#language
construct Array<Element> {
    state storage: ArrayStorage<Element>
}
```

This keeps wrapper semantics and representation semantics separate:

- `Array` remains the language-facing collection type
- `ArrayStorage` is the mutable storage primitive owned by `Array`
- a backend may realize that storage in different ways without changing `Array` semantics

- Every construct is identity-bearing even when identity is not written explicitly.

```gradient
construct User {
    let name: String
}
```

The graph can refer to `User` instances by intrinsic identity without requiring `userID: UUID` in user code.

- Cycles between constructs are graph-safe because construct references are identity references.

```gradient
construct User {
    let manager: User
}
```

This does not imply infinitely nested storage.

- The memory graph models mutation paths, not just declarations.

```gradient
state person: Person = Person(name: "George", age: 26)
person.age += 1
```

The graph must represent that `person` owns mutable storage and that `person.age` is mutated through that storage path.

- The memory graph models aliasing through bindings.

```gradient
state person: Person = Person(name: "George", age: 26)
state user: User = User(person: $person)
```

If `User.person` is a binding, the graph records that `user.person` aliases existing storage owned by `person`.

- Mutation through a `let` root is invalid even when the construct contains internal `state`.

```gradient
construct Person {
    let name: String
    state age: Int
}

let person: Person(name: "George", age: 26)
```

`person.age = 27` is rejected because `person` is immutable at the root path.

- The memory graph records derived dependencies.

```gradient
derived personString: String {
    "Person: \(person.name), Age: \(person.age)"
}
```

`personString` depends on the memory locations read through `person.name` and `person.age`.

- Function bodies can contribute mutation and dependency edges to the graph.

```gradient
construct User {
    binding person: Person

    function incrementAge() {
        person.age += 1
    }
}
```

The graph records that `incrementAge` mutates storage reachable through the `person` binding.

- The memory graph is always generated.

The memory graph is the default compiler model for ownership, storage, identity, mutation, and dependency. Gradient does not provide a graph-free escape hatch for ordinary memory management.

- Reactivity is an additional exposed layer built on top of the memory graph.

```gradient
@reactive
package UI
```

Reactive invalidation and update behavior are opt-in views over the existing memory graph rather than a separate ownership system.

- Memory graph information composes across modules.

```gradient
package UI
package Domain
```

When packages interact, the compiler merges the relevant graph information at build time rather than relying on runtime ownership machinery.

## Examples

```gradient
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
    let name: String
    state age: Int
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
- The graph is intended to be solvable from Gradient's constrained storage model without general-purpose borrow annotations.
- This document defines the memory-side model only. It does not yet specify the separate reactive invalidation view in detail.
- `binding` is the explicit shared-reference mechanism in Gradient. It is pointer-like in role, but compiler-tracked and constrained by the storage system.
- Copy-on-write may be used by `#language` collections and other suitable implementations to preserve value semantics without eager copying.
