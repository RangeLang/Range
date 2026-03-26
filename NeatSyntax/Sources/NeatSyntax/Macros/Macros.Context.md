# Macros Context

## Definition

Macros receive the compiler structure appropriate to the phase they run in.

## Properties

- Freestanding macros receive syntax-phase structures directly

```neat
macro literal: Freestanding<Expression> { expression in
    expression
}
```

```neat
macro lock: Freestanding<Block> { block in
    block()
}
```

- Attached macros receive resolved semantic structures directly

```neat
macro codable: Attached<Construct> { construct in
    construct.values
    construct.states
    construct.bindings
    construct.deriveds
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

- Freestanding structures are syntax-first

```neat
macro lock: Freestanding<Block> { block in
    acquire()
    block()
    release()
}
```

- Attached structures are graph-aware

```neat
macro clamped: Attached<Property> { property in
    property.bindingKind
    property.type
    property.owner
}
```

- Callable-attached macros should expose callable structure

```neat
macro literal<T>: Attached<Init> { init in
    init.params
    init.arguments
}
```

```neat
macro traced: Attached<Function> { function in
    function.params
    function.arguments
    function.returnType
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
- Freestanding and attached macros do not need to share one fake universal context bag.
