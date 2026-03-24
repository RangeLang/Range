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

```neat
protocol Named {
    value name: String
}
```

- Can be inherited by constructs

```neat
protocol Named {
    value name: String
}

construct User: Named {
    value name: String
}
```

- Can inherit from other protocols

```neat
protocol Named {
    value name: String
}

protocol Person: Named {
    value age: Int
}
```

- Can declare graph-binding requirements

```neat
protocol Paginated {
    state page: Int
}
```

- The graph-binding kind is part of the contract

```neat
protocol Paginated {
    state page: Int
}

construct UserList: Paginated {
    state page: Int = 0
}
```

`state page: Int` must be satisfied by `state`, not by `value`, `binding`, or `derived`.

- Constructs own the storage that satisfies protocol requirements

```neat
protocol Identifiable {
    value id: UUID
}

construct User: Identifiable {
    value id: UUID
}
```

The protocol requires the member, but the storage lives in the construct.

- Protocols can require functions

```neat
protocol Named {
    function displayName() -> String
}
```

- Protocols can require initializers

```neat
protocol Loadable {
    init(path: String)
}
```

- Default behavior lives in protocol extensions, not in protocol storage

```neat
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

```neat
protocol Container<Item>

protocol Mapping<Input: Comparable, Output>
```

Generic syntax is documented separately from the core protocol concept.

## Notes

- Protocols define contracts, not storage ownership.
- Protocol extensions may provide behavior defaults.
- Protocol extensions do not provide storage defaults.
