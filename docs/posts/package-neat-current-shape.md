# Package.neat Current Shape

`Package.neat` is now a typed package manifest, not a loose metadata file.

## Before

```neat
Package("Example") {
    version "0.1.0"
    author "George"
}
```

## After

Create one with the CLI:

```sh
neat create Example ./Example
```

That writes a manifest with the current shape:

```neat
#package
construct Project {
    let name: Title("Example")
    let version: Version(0.1.0)
    let author: "George"
}
```

A published package can also conform to the package protocol directly:

```neat
construct Example: Package {
    let name: Title("Example")
    let version: Version(0.1.0)
    let author: "George"
    let remotes: [Remote] = [
        Remote(url: "https://github.com/example/example.git")
    ]
}
```

## Why

The old form hid which facts were package fields and which values had domain meaning.

The current form keeps the package body as a normal construct. `name` is born as a `Title`, `version` is born as a `Version`, and `author` is declared directly from its literal value.

`#package` is the CLI-friendly form. It can infer remotes from git when the manifest does not list them.

Direct `construct Name: Package` is the explicit package shape. It must include the package protocol fields, including `remotes`, so publishing and search can read the metadata without guessing.
