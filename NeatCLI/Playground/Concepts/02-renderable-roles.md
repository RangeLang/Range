# Renderable Roles

Renderable declarations are expected to come from protocol-defined roles rather than hardcoded compiler types.

```neat
protocol Component {
}

protocol Page {
    var head: Head
}
```

```neat
@HeroCard: Component {
}

@HomePage: Page {
    var head: Head {
        Meta.title("Home")
    }
}
```

Current direction:

- renderable declarations can now be written directly as `@Name`
- composition is expressed with `:`
- semantics still come from the declarations and protocols they compose
