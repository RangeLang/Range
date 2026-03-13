# Attribute Roles

`@` is for declaration-level semantics.

Builtin example:

```neat
@main MyApp: App {
}
```

Reusable declaration example:

```neat
@Meta {
    func title(_ text: String) -> Head
}

@Palette {
    var colors: [Color] = [.red, .blue]
}

@Theme: Palette {
    var accentColor: Color
}

@BackgroundStyle: StyleModifier on Renderable {
    #background(color: Color) {
    }
}
```

Current direction:

- `@main` is builtin
- other `@Name` forms can define reusable declarations directly
- `@Name: OtherThing` composes from other reusable declarations
- `on Target` declares a projection target on the declaration header
- scoped members like `Meta.title(...)` come from `@Meta { ... }`
