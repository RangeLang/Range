# Renderable Roles

Renderable declarations should come from reusable declaration roles rather than hardcoded compiler types.

```neat
@Page {
    var head: Head
}

@Component {
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
- semantics come from the declarations they compose
