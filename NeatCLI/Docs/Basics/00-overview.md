# Overview

Neat is currently a declaration-first language.

The parser recognizes a small number of core ideas:

- declarations begin with `@`
- declarations can compose with `:`
- declarations can expose callables with `#name(...)`
- declarations can carry cases with `case ...`
- statements use `var`, `let`, `for`, and `switch`

Minimal example:

```neat
@Palette {
    case light, dark
}

@Theme: Palette {
    #theme() {
    }
}
```

What Neat is not doing right now:

- no `protocol`
- no separate `enum`
- no separate `namespace`
- no full type system beyond the currently parsed surface

Those concepts are being folded into the declaration system instead.
