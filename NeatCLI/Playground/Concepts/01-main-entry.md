# Main Entry

Neat currently treats `@main` as the builtin application entry marker.

```neat
protocol App {
    var head: Head
    var routes: Routes
}

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
- the contract is expected to be declared in Neat
- member validation should come from the protocol, not hardcoded names
