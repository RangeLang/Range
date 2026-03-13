# Declarations

Neat is declaration-first.

```neat
@Palette {
    var colors: [Color] = [.red, .blue]
}

@Theme: Palette {
    var accentColor: Color
}
```

Current direction:

- `@Name { ... }` defines a named declaration
- `@Name: OtherThing { ... }` composes from other declarations
- declarations are reusable by default
- `Name(...)` is the usage side and should follow normal `init` rules
