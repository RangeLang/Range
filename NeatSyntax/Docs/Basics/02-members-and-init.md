# Members, Init, And Callables

Declarations use typed members directly, and callable entrypoints use `@name(...)`.

```neat
#Counter: Value {
    value count: Int
}
```

Typed member example:

```neat
#Record: Value {
    value id: Int
    value name: String
    value selectedID: Int?
}
```

Callable example:

```neat
#Logger: Service {
    @write(message _: String) {
    }
}
```

Parameter label forms:

```neat
#Example: Service {
    @same(text: String) {
    }

    @renamed(message content: String) {
    }

    @unlabeled(message _: String) {
    }
}
```

In callable and initializer parameters:

- `text: String` uses the same external label and local name
- `message content: String` uses `content` at the call site and `message` inside the body
- `message _: String` omits the external label and keeps `message` as the local name

Initializer example:

```neat
#Counter: Value {
    value title: String

    init(title: String) {
        Logger.info("init \(title)")
    }
}
```

Overloaded callable example:

```neat
#Formatter: Service {
    @format(value: Int) {
    }

    @format(value: String) {
    }
}
```

Current surface:

- `@name(...)` defines a callable entrypoint on a declaration
- `Target@name(...)` defines a callable with an explicit projection target
- `init(...)` defines an explicit initializer on a declaration and must include a body
- callable and initializer parameters support real external labels and local names
- `name: Type` means the call-site label and local name are both `name`
- `local external: Type` means callers use `external` while the implementation uses `local`
- `local _: Type` omits the external label while keeping `local` available inside the body
- local parameter names cannot be `_`
- multiple callables are allowed on the same declaration
- multiple initializer overloads are allowed
- duplicate callable signatures are checked using external labels and types
- duplicate initializer signatures are checked using external labels and types
- member declarations parse as `value name: Type` and can also use optional types like `value name: Type?`
