# Freestanding Macros

## Definition

Freestanding macros are syntax rewrites invoked directly at the use site.

## Properties

- Come in freestanding expression and freestanding block forms

```neat
macro literal: Freestanding<Expression> { }
macro lock: Freestanding<Block> { }
```

- Are declared as freestanding macros

```neat
macro literal: Freestanding<Expression> { }
```

```neat
macro lock: Freestanding<Block> { }
```

- Use `#` at the call site

```neat
#lock {
    work()
}
```

- Can rewrite expressions

```neat
macro literal: Freestanding<Expression> { }

#literal("hello")
```

- Can rewrite blocks

```neat
macro lock: Freestanding<Block> { }

#lock {
    work()
}
```

- Operate on syntax rather than resolved types

```neat
macro literal: Freestanding<Expression> { context in
    context.expression
}
```

- Receive syntax context

```neat
macro lock: Freestanding<Block> { context in
    context.block
}
```

```neat
macro literal: Freestanding<Expression> { context in
    context.expression
}
```

- Produce the same kind of syntax they rewrite

```neat
Freestanding<Expression>  -> expression
Freestanding<Block>       -> block
```

- Do not depend on graph or type information

```neat
macro lock: Freestanding<Block> { context in
    context.block
}
```

Freestanding macros work on syntax rather than resolved graph or type context.

## Notes

- They are best suited for block and expression transformations such as `#lock` and literal rewriting.
