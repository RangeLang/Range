# Typed Construction Metadata

Use this reference when writing about the proposed Neat syntax:

```neat
let version: Version(0.1.8)
```

Core idea: this is not assignment sugar for:

```neat
let version: Version = Version(0.1.8)
```

It should be treated as a first-class declaration form. The binding or property is constructed with typed metadata at declaration time.

Conceptual read:

```text
version is a Version, with construction data 0.1.8
```

Graph model:

```text
binding version
  storage: let
  type: Version
  initializer:
    construct Version
      inputs:
        value -> 0.1.8
```

Assignment remains a separate operation:

```neat
version = Version(0.1.9)
```

That means mutation of an existing storage location. It should not be the graph model for property initialization.

Especially for properties, the new form reads like data about the construct:

```neat
construct Package {
    let name: String("Neat")
    let version: Version(0.1.8)
}
```

The graph can preserve key/value-shaped construction metadata for tooling, diagnostics, documentation, and future cloud/package views.
