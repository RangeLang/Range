# Construct Initialization

## Definition

Constructs support automatic memberwise initialization by default.

## Properties

- A construct gets a memberwise initializer automatically

```range
construct User {
    let name: String
    let age: Int
}

let user: User(name: "Ava", age: 20)
```

- Default values reduce the required initializer surface

```range
construct User {
    let name: String
    let age: Int = 20
}

let user: User(name: "Ava")
```

- A construct may declare custom initializers

```range
construct User {
    let name: String
    let age: Int

    init(name: String) {
        self.name = name
        self.age = 0
    }
}
```

- A construct may declare multiple initializers as long as their signatures do not clash

```range
construct User {
    let name: String
    let age: Int

    init(name: String) {
        self.name = name
        self.age = 0
    }

    init(name: String, age: Int) {
        self.name = name
        self.age = age
    }
}
```

- Every `let` and `state` must be initialized unless it has a default value

```range
construct User {
    let name: String
    state visits: Int = 0
}
```

## Notes

- Construct initialization follows Swift-like memberwise initializer semantics.
- Default values remove the need to supply that member during initialization.
