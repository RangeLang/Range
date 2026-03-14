# Bindings And State

Neat uses `value` and `state` for owned bindings, plus `binding` for borrowed mutable access.

## Local Bindings

Inside statement blocks:

```neat
@increment() {
    value step = 1
    state next = count
    next += step
    count = next
}
```

Current rules:

- `value` is immutable
- `state` is mutable
- local owned bindings require an initializer
- local owned bindings currently appear inside statement blocks, not as file-level script declarations

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

## Binding

Bindings borrow writable access to state owned elsewhere.

```neat
#ParentCounter: Component {
    state count: Int = 0

    value body: Component {
        ChildCounter(count: $count)
    }
}

#ChildCounter: Component {
    binding count: Int

    value body: Component {
        Button("Increment") {
            count += 1
        }
    }
}
```

Current rules:

- `binding name: Type` declares writable borrowed access
- bindings are declaration members, not local variables
- bindings are passed explicitly with `$name`
- plain `name` passes a value, `$name` passes writable binding access

Derived bindings can transform reads and writes:

```neat
binding adjustedCount: Int {
    get {
        return count + 1
    }

    set {
        count = newValue
    }
}
```

Current rules:

- derived bindings use `get { ... }` and `set { ... }`
- `newValue` is available inside `set`
- reads use the getter body
- writes and compound assignments route through the setter body

## Member Declarations

Declaration members also use `value`, but they are not the same thing as statement-level owned bindings.

```neat
#Counter {
    value step: Int
}
```

Here `value step: Int` means “this declaration has a typed member named `step`.” It is structural, not a statement-level mutable variable.
