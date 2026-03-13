# Members And Init

Declarations use typed members directly.

```neat
protocol Palette {
    var colors: [Color] = [.red, .blue]
}
```

Concrete declarations can provide stored values or builder bodies:

```neat
@Theme: Palette {
    var colors: [Color] {
    }
}
```

Initializers are universal in Neat.

```neat
protocol Palette {
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

- `init` can appear on protocols and declarations
- zero-argument `init()` may be synthesized by the compiler
- required protocol initializers must be satisfied or defaulted
- protocol member requirements may provide default values
