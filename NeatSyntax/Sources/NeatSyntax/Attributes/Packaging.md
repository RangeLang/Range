# Packaging Attribute

## Definition

`@packaging` marks declarations that define Neat package manager metadata.

## Role

Packaging declarations are ordinary language declarations with a semantic tag. The tag makes package infrastructure easy to discover without giving the declaration privileged lowering behavior.

## Examples

```neat
@packaging
protocol Package {
    let name: Title
    let version: Version
    let author: String
    let remotes: [Remote]
}
```

```neat
@packaging
construct Title {
    let raw: String
}
```

```neat
@packaging
construct Version {
    let raw: String
}
```

```neat
@packaging
construct Remote {
    let url: String
}
```

Package manifests can write versions directly:

```neat
let version: Version(0.1.8)
```

The CLI also recognizes `#package` as a manifest macro. When `remotes` is omitted,
the CLI resolves package remotes from git:

```neat
#package
construct Project {
    let name: Title("Neat")
    let version: Version(0.1.8)
    let author: String = "George"
}
```

## Notes

- `@packaging` is not a replacement for `@language`.
- `@packaging` does not make a construct non-identity-bearing.
- Package manifests can either conform to `Package` directly or use the CLI `#package` macro.
- Package manifests are not themselves marked `@packaging`.
