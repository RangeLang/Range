# Abstraction Storage Graph

When the system can see both the declaration and the application of abstraction storage, it can build a graph from the language instead of guessing one after parsing.

## Feature

An abstraction is not only the place where a shape is declared.

It is also the place where that shape is applied, reflected, constrained, stored, and re-used by another shape.

## Shape

```neat
construct User {
    let id: Int
    let name: String
}

let user: User(id: 1, name: "George")
```

```text
User
  declaration
    id: Int
    name: String

User(id: 1, name: "George")
  application
    id -> User.id
    name -> User.name

graph
  User.declaration <-> User.application
  User.id          <-> application.id
  User.name        <-> application.name
```

Each edge reflects a stored abstraction fact from another position in the system.

The result is almost a grid of mirrors: every declaration has an application-facing reflection, and every application points back to the declaration that gives it shape.

## Reason

The graph gets stronger when declaration storage and application storage are both visible.

The compiler no longer has to flatten meaning into one node or recover relationships later. The source already carries the mirrored structure the graph needs.
