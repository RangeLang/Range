# Members And Callables

Declarations use typed members directly, and callable entrypoints use `@name(...)`.

```neat
#Counter: Value {
    var count: Int
}
```

Typed member example:

```neat
#Record: Value {
    var id: Int
    var name: String
    var selectedID: Int?
}
```

Callable example:

```neat
#Logger: Service {
    @write(text: String) {
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
- multiple callables are allowed on the same declaration
- duplicate exact callable signatures on the same declaration are rejected
- member declarations parse as `var name: Type` and can also use optional types like `var name: Type?`
- plain `init(...)` is not a special language construct
