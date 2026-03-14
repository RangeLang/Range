# Renderable Roles

Renderable declarations should come from reusable declaration roles rather than hardcoded compiler types.

```neat
@Page: Role {
    var head: Head
}

@Component: Role {
}
```

```neat
@HeroCard: Component {
    var body: Component {
    }
}

@HomePage: Page {
    var head: Head {
        Meta.title("Home")
    }

    var body: Component {
    }
}
```

Current direction:

- renderable declarations are written as `@Name: Role`
- composition is expressed with `:`
- semantics come from the declarations they compose
