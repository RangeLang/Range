# Expression And Block Macros

## Definition

Expression-targeted and block-targeted macros are syntax rewrites invoked directly at the use site.

## Properties

- Come in expression and block forms

```range
macro stringify(value _: capture Expression): Expression -> String { }
macro lock(): Block { }
```

- Are declared by direct target type

```range
macro stringify(value _: capture Expression): Expression -> String { }
```

```range
macro lock(): Block { }
```

- Use `#` at the call site

```range
#lock {
    work()
}
```

- Can rewrite expressions

```range
macro stringify(value _: capture Expression): Expression -> String { }

#stringify(1 + 2)
```

- Can rewrite blocks

```range
macro lock(): Block { }

#lock {
    work()
}
```

- Operate on syntax rather than resolved types

```range
macro stringify(value _: capture Expression): Expression -> String { target, diagnostics in
    target.rewrite("\(value)")
}
```

- Receive syntax context

```range
macro lock(): Block { target, diagnostics in
    target.rewrite({
        target()
    })
}
```

```range
macro stringify(value _: capture Expression): Expression -> String { target, diagnostics in
    target.rewrite("\(value)")
}
```

- Produce the same kind of syntax they rewrite

```range
Expression -> expression
Block      -> block
```

- Do not depend on graph or type information

```range
macro lock(): Block { target, diagnostics in
    target.rewrite({
        target()
    })
}
```

These macros work on syntax rather than resolved graph or type context.

## Notes

- They are best suited for block and expression transformations such as `#lock` and literal rewriting.
