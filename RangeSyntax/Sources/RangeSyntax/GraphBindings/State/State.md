# State

## Definition

State is a mutable owned graph binding.

## Role

`state` is Range's mutable source of truth.

## Mental Model

`state` owns mutable storage directly.

If other code needs shared access to that storage, it does so through `binding`.

## Properties

- Declares mutable owned data

```range
state page: Int
```

- Can be initialized directly

```range
state page: Int = 0
```

Outside construct member storage, `state` requires an initializer.

- Can participate in memberwise initialization

```range
construct Counter {
    state count: Int
}

let counter: Counter(count: 0)
```

Inside construct member storage, `state` may be declared without a default and must then be initialized by construction.

- Can be mutated after initialization

```range
state page: Int = 0

page = 1
page += 1
```

- Acts as a source of truth for derived values and behavior

```range
construct Counter {
    state count: Int = 0

    derived isEmpty: Bool {
        return count == 0
    }
}
```

- Shared mutation is exposed through binding projection

```range
construct User {
    binding person: Person
}

state person: Person = Person(name: "George", age: 26)
state user: User = User(person: $person)
```

`person` is the owner. `user.person` is borrowed access to that same mutable storage.
