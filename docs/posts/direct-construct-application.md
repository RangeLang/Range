# Direct Construct Application

I removed the idea that construction needs an `init` declaration in the language model.

## Before

```neat
construct User {
    let id: Int
    let name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

let user: User(id: 1, name: "George")
```

## After

```neat
construct User {
    let id: Int
    let name: String
}

let user: User(id: 1, name: "George")
```

## Why

The old form worked, but it repeated the same fact twice.

I already declared `id`.

I already declared `name`.

The application should link to those declarations directly.

```text
User(id: 1)
  id -> User.id
```

No hidden initializer.

No synthesized initializer.

Just an application of the construct data shape.

Functions still carry behavior. Constructs carry data shape.
