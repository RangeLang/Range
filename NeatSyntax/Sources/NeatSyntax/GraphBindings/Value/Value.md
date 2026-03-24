# Value

## Definition

A value is an immutable owned graph binding.

## Properties

- Declares immutable owned data

```neat
value name: String
```

- Can be initialized directly

```neat
value name: String = "Ava"
```

- Can participate in memberwise initialization

```neat
construct User {
    value name: String
    value age: Int
}

value user = User(name: "Ava", age: 20)
```

- Cannot be reassigned after initialization

```neat
value name: String
```

`name` is fixed once the construct has been initialized.
