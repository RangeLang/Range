# State

## Definition

State is a mutable owned graph binding.

## Properties

- Declares mutable owned data

```neat
state page: Int
```

- Can be initialized directly

```neat
state page: Int = 0
```

- Can participate in memberwise initialization

```neat
construct Counter {
    state count: Int
}

value counter = Counter(count: 0)
```

- Can be mutated after initialization

```neat
state page: Int = 0

page = 1
page += 1
```

- Acts as a source of truth for derived values and behavior

```neat
construct Counter {
    state count: Int = 0

    derived isEmpty: Bool {
        return count == 0
    }
}
```
