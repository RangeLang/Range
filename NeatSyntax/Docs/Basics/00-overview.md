# Overview

Neat is currently a declaration-first language.

The parser recognizes a small number of core ideas:

- declarations begin with `#`
- declarations can project onto other declarations with `on`
- declarations can compose with `:`
- declarations can expose callables with `@name(...)`
- declarations can carry cases with `case ...`
- statements use `let`, `var`, and control flow

Minimal example:

```neat
#Mode {
    case light, dark
}

#Theme on Mode: Config {
    @label() {
    }
}
```

Note: Neat does not use separate `struct`, `class`, `protocol`, `enum`, `namespace`, or `interface` categories. Those concepts are represented through the declaration system, while the full type system beyond the currently parsed surface is still not implemented.
