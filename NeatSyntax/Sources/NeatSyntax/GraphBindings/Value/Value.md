# Value

## Definition

A value is an immutable owned graph binding.

## Role

`value` declares owned data that cannot be mutated through that root after initialization.

## Mental Model

`value` freezes access through that binding.

For plain value data, this means no reassignment or mutation through the path.

For constructs, this means member mutation through the `value` root is also invalid even when the construct contains internal `state`.

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

- Cannot be used to mutate member paths

```neat
construct Person {
    value name: String
    state age: Int
}

value person: Person = Person(name: "George", age: 26)
```

`person.age = 27` is invalid because `person` is a `value` root.

- Copying a `value` into owned mutable storage creates a new independent logical value

```neat
construct Person {
    value name: String
    state age: Int
}

value person: Person = Person(name: "George", age: 26)
state editablePerson: Person = person
```

`editablePerson` is a separate owned value semantically. Shared live access requires `binding`, not ordinary assignment.
