# Protocol

## Definition

A protocol is a non-instantiable contract.

## Role

`protocol` defines required graph shape and behavior for conforming constructs.

## Mental Model

- `construct` owns storage and identity
- `protocol` declares requirements

## Properties

- Non-instantiable

```range
protocol Named {
    let name: String
}
```

- Can be inherited by constructs

```range
protocol Named {
    let name: String
}

construct User: Named {
    let name: String
}
```

- Can inherit from other protocols

```range
protocol Named {
    let name: String
}

protocol Person: Named {
    let age: Int
}
```

- Can declare graph-binding requirements

```range
protocol Paginated {
    state page: Int
}
```

- The graph-binding kind is part of the contract

```range
protocol Paginated {
    state page: Int
}

construct UserList: Paginated {
    state page: Int = 0
}
```

`state page: Int` must be satisfied by `state`, not by `let`, `binding`, or `derived`.

- Constructs own the storage that satisfies protocol requirements

```range
protocol Identifiable {
    let id: UUID
}

construct User: Identifiable {
    let id: UUID
}
```

The protocol requires the member, but the storage lives in the construct.

- Protocols can require functions

```range
protocol Named {
    function displayName() -> String
}
```

- Protocols can require initializers

```range
protocol Loadable {
    init(path: String)
}
```

- Default behavior lives in protocol extensions, not in protocol storage

```range
protocol Paginated {
    state page: Int
}

extension Paginated {
    function nextPage() {
        page += 1
    }
}
```

- Protocols can be generic

```range
protocol Container<Item>

protocol Mapping<Input: Comparable, Output>
```

Generic syntax is documented separately from the language protocol concept.

## Notes

- Protocols define contracts, not storage ownership.
- Protocol extensions may provide behavior defaults.
- Protocol extensions do not provide storage defaults.
