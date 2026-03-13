# Bindings And State

Neat currently uses `var` and `let` in statement blocks, and `@State` inside renderable declarations.

## Local Bindings

Inside statement blocks:

```neat
Button("Add") {
    let step = 1
    var next = 2
    count += step
    count += next
}
```

Current rules:

- `let` is immutable
- `var` is mutable
- local bindings require an initializer
- local bindings currently appear inside statement blocks, not as top-level declarations

## State

Inside component-like declarations:

```neat
@Counter {
    @State var count: Int = 0
}
```

Current rules:

- `@State` is supported in component/page-style declarations
- supported built-in state types are `Int`, `String`, `Bool`, `Dictionary`, and `Void`
- state type can be inferred from the initializer when inference exists
- array inference for `@State` initializers is not implemented yet

## Member Declarations

Declaration members also use `var`, but they are not the same thing as local mutable bindings.

```neat
@App {
    var head: Head {
    }
}
```

Here `var head: Head` means “this declaration has a typed member named `head`.” It is structural, not a statement-level mutable variable.
