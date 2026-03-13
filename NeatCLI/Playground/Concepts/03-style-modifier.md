# Style Modifier

Style modifiers are still in design, but the current direction is to treat them as framework-level declaration roles with typed callable behavior.

```neat
protocol Stylable {
}

@StyleModifier Background for Stylable {
    func background(color: Color) -> Self {
        return self
    }
}
```

Open questions:

- how `for Stylable` should be represented in syntax
- whether modifier bodies mutate `Self` or lower into semantic style nodes
- how style behavior should be shared across protocols and renderable roles
