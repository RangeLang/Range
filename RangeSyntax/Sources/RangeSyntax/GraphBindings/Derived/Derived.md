# Derived

## Definition

A derived is a computed graph binding.

## Properties

- Declares computed, non-stored data

```gradient
derived fullName: String
```

- Can be defined from other graph bindings

```gradient
derived fullName: String {
    return firstName + " " + lastName
}
```

- Does not own storage

```gradient
derived isEmpty: Bool {
    return count == 0
}
```

`isEmpty` is computed from other data rather than stored separately.

- Changes when its inputs change

```gradient
construct Counter {
    state count: Int = 0

    derived isEmpty: Bool {
        return count == 0
    }
}
```
