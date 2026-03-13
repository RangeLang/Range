# Style Modifier

Style modifiers are still in design, but the current direction is to treat them as framework-level declaration roles with typed callable behavior.

```neat
@BackgroundStyle: StyleModifier on Renderable {
    #background(color: Color) {
    }
}
```

Open questions:

- how `on Renderable` should project `.background(...)` into the receiver surface
- whether modifier bodies mutate the callee or lower into semantic style nodes
- how conflicts should be handled when multiple declarations project the same callable
