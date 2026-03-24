# Construct

## Definition

A construct is an identity-bearing struct.

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

- Can inherit from other constructs

```neat
construct Person {
    value name: String
}

construct User: Person {
    value age: Int
}
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

## Notes

- `construct` defines a concrete runtime type.
- A construct carries identity rather than being a purely structural value.
