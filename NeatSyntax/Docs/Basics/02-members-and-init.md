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
    @write(text: String) {
    }
}
```

Initializer example:

```neat
#Counter: Value {
    value title: String

    init(title: String) {
        print("init \(title)")
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
- `init(...)` defines an explicit initializer on a declaration
- multiple callables are allowed on the same declaration
- multiple initializer overloads are allowed
- duplicate exact callable signatures on the same declaration are rejected
- duplicate exact initializer signatures on the same declaration are rejected
- member declarations parse as `value name: Type` and can also use optional types like `value name: Type?`
