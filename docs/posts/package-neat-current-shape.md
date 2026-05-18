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
@package {
    let name: Title("Example")
    let version: Version(0.1.0)
    let author: String("George")
}
```

Remotes can be declared in the same package space:

```neat
@package {
    let name: Title("Example")
    let version: Version(0.1.0)
    let author: String("George")
    let remotes: [Remote] = [
        Remote(url: "https://github.com/example/example.git")
    ]
}
```

## Why

The old form hid which facts were package fields and which values had domain meaning.

The current form keeps package facts in a package space. `name` is born as a `Title`, `version` is born as a `Version`, and `author` is declared directly from its string value.

`@package` is not a namespace, but it gives the graph one place to collect package metadata. When the manifest does not list remotes, the CLI can infer them from git.
