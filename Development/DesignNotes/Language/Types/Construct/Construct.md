# Construct

## Definition

A construct is Range's concrete identity-bearing type.

## Role

`construct` is the normal way user code models real entities without choosing between separate `struct` and `class` categories.

## Mental Model

`construct` unifies the roles that other languages split across value types and reference types.

User code writes `construct` for concrete modeled entities.

Ordinary `construct` declarations are identity-bearing by default.

Plain foundational and compiler-structural values such as `Int` and `Closure` belong to ` construct`, not the default `construct` model.

## Properties

- Declared as a concrete, identity-bearing type

```range
construct Person {
    let name: String
}
```

- Instantiable

```range
let user: Person(name: "George")
```

- Does not inherit from other constructs

- Reuses behavior through protocols and generics rather than construct inheritance

- Can conform to protocols

```range
protocol Named {
    function displayName(): String
}

construct Person: Named {
    let name: String

    function displayName(): String {
        return name
    }
}
```

- References to other constructs preserve construct identity rather than forcing inline structural containment

```range
construct Author {
    let name: String
}

construct Book {
    let title: String
    let author: Author
}
```

## Notes

- `construct` is identity-bearing by definition.
- `construct` does not inherit from other constructs.
- `construct` replaces the struct/class split in normal user modeling.
- Recursive relationships between constructs are legal because construct-to-construct members are modeled as construct relationships in the graph.
- Non-identity foundational types belong to ` construct`, not ordinary `construct`.
