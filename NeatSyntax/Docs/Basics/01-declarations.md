# Declarations

Neat is declaration-first.

```neat
@Palette {
    case light, dark
}

@Theme: Palette {
    #theme() {
    }
}
```

Current surface:

- `@Name { ... }` defines a named declaration
- `@Name: OtherThing { ... }` composes from other declarations
- declarations are reusable by default
- declarations can contain members, callables, cases, state, functions, and a body depending on kind
- the parser does not use separate `protocol`, `enum`, or `namespace` keywords anymore
