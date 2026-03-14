# Bindings And State

Neat uses `let` and `var` in statement blocks, and `state` inside declarations.

## Local Bindings

Inside statement blocks:

```neat
@increment() {
    let step = 1
    var next = count
    next += step
    count = next
}
```

Current rules:

- `let` is immutable
- `var` is mutable
- local bindings require an initializer
- local bindings currently appear inside statement blocks, not as top-level declarations

## State

Inside declarations:

```neat
#Counter {
    state count: Int = 0

    state doubled: Int {
        return count + count
    }
}
```

Current rules:

- `state` is supported in declarations
- supported built-in state types are `Int`, `String`, `Bool`, `Dictionary`, and `Void`
- state type can be inferred from the initializer when inference exists
- derived state uses a block body and an explicit type
- array inference for `state` initializers is not implemented yet

## Member Declarations

Declaration members also use `var`, but they are not the same thing as local mutable bindings.

```neat
#Counter {
    var step: Int
}
```

Here `var step: Int` means “this declaration has a typed member named `step`.” It is structural, not a statement-level mutable variable.
