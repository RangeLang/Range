# Main Entry

Neat currently treats `@main` as the builtin application entry marker.

```neat
@main MyApp: App {
    var head: Head {
        Meta.title("Neat")
        Meta.description("A Neat app")
    }

    var routes: Routes {
        Route("/", HomePage)
    }
}
```

Current direction:

- `@main` declares the entry and selects the entry contract with `:`
- `App` is the entry contract name, not a separate local protocol declaration
- member validation should come from the applied entry declaration, not hardcoded names
