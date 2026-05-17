# Packaging Attribute

## Definition

`@packaging` marks declarations that define Neat package manager metadata.

## Role

Packaging declarations are ordinary language declarations with a semantic tag. The tag makes package infrastructure easy to discover without giving the declaration privileged lowering behavior.

## Examples

```neat
@packaging
protocol Package {
    let version: Version
    let author: String
    let remotes: [Remote]
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
let version: Version = Version(0.1.8)
```

## Notes

- `@packaging` is not a replacement for `@language`.
- `@packaging` does not make a construct non-identity-bearing.
- Package manifests conform to the `Package` protocol; they are not themselves marked `@packaging`.
