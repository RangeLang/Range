# Style Modifier

Style modifiers are still in design, but the current direction is to treat them as framework-level declaration roles with typed callable behavior.

```neat
@StyleModifier Background {
    var color: Color
}
```

Open questions:

- how modifier call surfaces should be declared
- whether modifier bodies mutate the callee or lower into semantic style nodes
- how style behavior should be shared across declarations like `View`, `Page`, and `Component`
