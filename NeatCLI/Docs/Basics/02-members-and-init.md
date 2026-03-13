# Members And Callables

Declarations use typed members directly.

```neat
@Palette {
    var colors: [Color] = [.red, .blue]
}
```

Composed declarations can provide stored values or builder bodies:

```neat
@Theme: Palette {
    var colors: [Color] {
    }
}
```

Callable entrypoints are universal in Neat.

```neat
@Palette {
    var colors: [Color]

    #colors(colors _: [Color])
}
```

```neat
@Theme: Palette {
    var colors: [Color]

    #colors(colors _: [Color]) {
        self.colors = colors
    }
}
```

Current direction:

- `#name(...)` defines a callable entrypoint on a declaration
- multiple callables are allowed on the same declaration
- duplicate exact callable signatures on the same declaration are rejected
- required callables should be satisfied or defaulted through composition
- member defaults may be provided directly on the declaration
