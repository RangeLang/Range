# Protocol

Protocols are the main way Neat describes behavior and required structure.

```neat
protocol Component {
    var title: String
}
```

A protocol can later be applied to a declaration using its `@` form:

```neat
@HeroCard: Component {
    var title: String = "Hero"
}
```

Current direction:

- protocols define member requirements
- protocols can define initializer requirements
- protocol names can be used as declaration roles
