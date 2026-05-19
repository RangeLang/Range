# Expression And Block Macros

## Definition

Expression-targeted and block-targeted macros are syntax rewrites invoked directly at the use site.

## Properties

- Come in expression and block forms

```gradient
macro stringify(value _: capture Expression): Expression -> String { }
macro lock(): Block { }
```

- Are declared by direct target type

```gradient
macro stringify(value _: capture Expression): Expression -> String { }
```

```gradient
macro lock(): Block { }
```

- Use `#` at the call site

```gradient
#lock {
    work()
}
```

- Can rewrite expressions

```gradient
macro stringify(value _: capture Expression): Expression -> String { }

#stringify(1 + 2)
```

- Can rewrite blocks

```gradient
macro lock(): Block { }

#lock {
    work()
}
```

- Operate on syntax rather than resolved types

```gradient
macro stringify(value _: capture Expression): Expression -> String { target, diagnostics in
    target.rewrite("\(value)")
}
```

- Receive syntax context

```gradient
macro lock(): Block { target, diagnostics in
    target.rewrite({
        target()
    })
}
```

```gradient
macro stringify(value _: capture Expression): Expression -> String { target, diagnostics in
    target.rewrite("\(value)")
}
```

- Produce the same kind of syntax they rewrite

```gradient
Expression -> expression
Block      -> block
```

- Do not depend on graph or type information

```gradient
macro lock(): Block { target, diagnostics in
    target.rewrite({
        target()
    })
}
```

These macros work on syntax rather than resolved graph or type context.

## Notes

- They are best suited for block and expression transformations such as `#lock` and literal rewriting.
