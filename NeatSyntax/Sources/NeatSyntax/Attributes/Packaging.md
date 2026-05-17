# Packaging Attribute

## Definition

`@packaging` marks declarations that define Neat package manager metadata.

## Role

Packaging declarations are ordinary language declarations with a semantic tag. The tag makes package infrastructure easy to discover without giving the declaration privileged lowering behavior.

## Examples

```neat
@packaging
protocol Package {
    let version: String
    let author: String
    let remotes: [Remote]
}
```

```neat
@packaging
construct Remote {
    let url: String
}
```

## Notes

- `@packaging` is not a replacement for `@language`.
- `@packaging` does not make a construct non-identity-bearing.
- Package manifests conform to the `Package` protocol; they are not themselves marked `@packaging`.
