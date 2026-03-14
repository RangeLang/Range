# NeatPlayground

Small local Neat playground for trying syntax and compiler changes quickly.

## Files

- `Package.neat` configures the playground package
- `Playground.neat` contains the runnable `@main { ... }` block

The package manifest uses standard Neat declaration syntax:

```neat
#NeatPlayground: Package {
}
```

## Run

```bash
cd NeatPlayground
neat compile
neat run
```
