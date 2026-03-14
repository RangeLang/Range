# Declarations

Neat is declaration-first.

```neat
#Status {
    case light, dark
}

#Logger: Service {
    @write(text: String) {
    }
}
```

Current surface:

- `#Name { ... }` defines a named declaration
- `#Name: Contract { ... }` composes from another declaration or contract
- `#Name on Target: Contract { ... }` declares a projected declaration with a default target
- declarations are reusable by default
- declarations can contain members, callables, cases, and state
- the parser does not use separate `protocol`, `enum`, or `namespace` keywords anymore
