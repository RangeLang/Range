# Members And Init

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

Initializers are universal in Neat.

```neat
@Palette {
    var colors: [Color]

    init(colors _: [Color])
}
```

```neat
@Theme: Palette {
    var colors: [Color]

    init(colors _: [Color]) {
        self.colors = colors
    }
}
```

Current direction:

- `init` can appear on any declaration
- zero-argument `init()` may be synthesized by the compiler
- required initializers should be satisfied or defaulted through composition
- member defaults may be provided directly on the declaration
