# Marker Language Markdown

Marker language can carry Markdown as source metadata.

## Addition

```neat
#description {
# User

Represents an authenticated account.

- Has a stable identity
- Owns posts
- Can sign in
}
construct User {
    let id: UUID
    let name: String
}
```

## Reason

The old comment forms would make documentation a side channel. This keeps the description attached to the declaration as graph data, while still letting the body be direct Markdown.

The editor can project this into hovers, outlines, generated docs, or section navigation without hardcoding `//`, `///`, or `MARK` conventions.
