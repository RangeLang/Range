# Construct

## Definition

A construct is Neat's concrete identity-bearing type.

## Role

`construct` is the normal way user code models real entities without choosing between separate `struct` and `class` categories.

## Mental Model

`construct` is identity-bearing by default.

Plain value foundations such as `Int` are a separate `@core construct` case and are not the default meaning of `construct`.

## Properties

- Declared as a concrete, identity-bearing type

```neat
construct Person {
    value name: String
}
```

- Instantiable

```neat
value user = Person(name: "George")
```

- Can conform to protocols

```neat
protocol Named {
    function displayName() -> String
}

construct Person: Named {
    value name: String

    function displayName() -> String {
        return name
    }
}
```

- References to other constructs preserve construct identity rather than forcing inline structural containment

```neat
construct Author {
    value name: String
}

construct Book {
    value title: String
    value author: Author
}
```

## Notes

- `construct` is identity-bearing by definition.
- `construct` does not inherit from other constructs.
- Recursive relationships between constructs are legal because construct-to-construct members are modeled as construct relationships in the graph.
- Non-identity foundational types belong to `@core construct`, not ordinary `construct`.
