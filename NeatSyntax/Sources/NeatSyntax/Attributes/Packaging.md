# Package Space

## Definition

`@package { ... }` opens a package metadata space.

## Role

Package spaces collect package facts in the declaration graph without making package metadata a namespace. Declarations inside the space still register normally, so metadata types such as `Package`, `Title`, `Version`, and `Remote` are available by name.

## Examples

```neat
@package {
    protocol Package {
        let name: Title
        let version: Version
        let author: String
        let remotes: [Remote]
    }

    construct Title {
        let raw: String
    }

    construct Version {
        let raw: String
    }

    construct Remote {
        let url: String
    }
}
```

Package manifests can write metadata directly in the package space:

```neat
@package {
    let name: Title("Neat")
    let version: Version(0.1.8)
    let author: String("George")
    Module("acme/logger")
}
```

## Notes

- `@package` is not a replacement for `@language`.
- `@package` does not make declarations non-identity-bearing.
- `@package` is not a namespace declaration. It is a package metadata space collected by the graph.
- Package entries such as `Module("owner/repo")` are also collected in the package space.
- When package remotes are omitted, the CLI can resolve package remotes from git.
