# Let

## Definition

A let binding is an immutable owned graph binding.

## Role

`let` declares owned data that cannot be mutated through that root after initialization.

## Mental Model

`let` freezes access through that binding.

For plain value data, this means no reassignment or mutation through the path.

For constructs, this means member mutation through the `let` root is also invalid even when the construct contains internal `state`.

## Properties

- Declares immutable owned data

```range
let name: String
```

- Can be initialized directly

```range
let name: "Ava"
```

- Can participate in memberwise initialization

```range
construct User {
    let name: String
    let age: Int
}

let user: User(name: "Ava", age: 20)
```

- Cannot be reassigned after initialization

```range
let name: String
```

`name` is fixed once the construct has been initialized.

- Cannot be used to mutate member paths

```range
construct Person {
    let name: String
    state age: Int
}

let person: Person(name: "George", age: 26)
```

`person.age = 27` is invalid because `person` is a `let` root.

- Copying a `let` binding into owned mutable storage creates a new independent logical value

```range
construct Person {
    let name: String
    state age: Int
}

let person: Person(name: "George", age: 26)
state editablePerson: Person = person
```

`editablePerson` is a separate owned value semantically. Shared live access requires `binding`, not ordinary assignment.

- Implementations may use copy-on-write for some values and constructs

```range
let a: [Int] = [1, 2, 3]
state b: [Int] = a

b.append(4)
```

Range still treats `a` and `b` as independent logical values. Copy-on-write is an allowed optimization that can defer physical copying until mutation, but it does not change the language semantics or turn the two values into aliases.
