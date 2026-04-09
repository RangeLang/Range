# Macros Context

## Definition

Macros receive the compiler structure appropriate to the syntax target they declare.

## Properties

- Expression-targeted macros receive expression syntax directly

```neat
macro stringify(value _: capture Expression): Expression -> String { target, diagnostics in
    target.rewrite("\(value)")
}
```

```neat
macro lock(): Block { target, diagnostics in
    target.rewrite({
        target()
    })
}
```

- Declaration-targeted macros receive the declared compiler structure directly

```neat
macro codable(): Construct { target, diagnostics in
    target.values
    target.states
    target.bindings
    target.deriveds
}
```

- The macro surface should expose language concepts rather than hidden compiler handles

```neat
construct
property
parameter
init
function
expression
block
```

- Block and expression targets are syntax-first

```neat
macro lock(): Block { target, diagnostics in
    target.rewrite({
        acquire()
        target()
        release()
    })
}
```

- Declaration targets are declaration-aware

```neat
macro clamped(min: Int, max: Int): Property { target, diagnostics in
    target.bindingKind
    target.type
    target.owner
}
```

- Callable and initializer targets should expose callable structure

```neat
macro literal<T>(): Init { target, diagnostics in
    target.params
    target.arguments
}
```

```neat
macro traced(): Function { target, diagnostics in
    target.params
    target.arguments
    target.returnType
}
```

- Attachment targets are compiler-known language concepts

```neat
Expression
Block
Construct
Enum
Protocol
Extension
Property
Parameter
Init
Function
```

## Notes

- Macros should be low-level enough to express advanced features without new baked-in compiler mechanisms.
- Different target kinds do not need to share one fake universal context bag.
- `#literal<T>` is the canonical init-targeted literal bridge form, with `T` constrained to compiler-recognized literal carrier types.
