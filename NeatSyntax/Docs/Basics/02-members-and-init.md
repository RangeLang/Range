# Members And Callables

Declarations use typed members directly, and callable entrypoints use `#name(...)`.

```neat
@App: Role {
    var head: Head {
    }
}
```

Typed member example:

```neat
@Page: Role {
    var head: Head
    var selectedID: Int?
    var body: Component {
    }
}
```

Callable example:

```neat
@Theme: Role {
    #theme() {
    }
}
```

Overloaded callable example:

```neat
@BackgroundStyle: Role {
    #background(color: Color) {
    }

    #background(color: String) {
    }
}
```

Current surface:

- `#name(...)` defines a callable entrypoint on a declaration
- multiple callables are allowed on the same declaration
- duplicate exact callable signatures on the same declaration are rejected
- member declarations parse as `var name: Type` and can also use optional types like `var name: Type?`
- plain `init(...)` is not a special language construct
