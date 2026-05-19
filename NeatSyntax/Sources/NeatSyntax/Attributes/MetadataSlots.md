# Metadata Slot Markers

## Definition

`Namespace<T>` is a marker effect type. A marker with that value type declares a semantic metadata slot for targets of type `T`.

## Role

Metadata slot markers let libraries attach named semantic facts to declarations without creating new declaration kinds or turning the target into a namespace.

## Example

```neat
marker styling(): Namespace<Construct>

#styling
construct Panel {
    let title: String
}
```

`Panel` remains a construct. The `styling` marker is metadata attached to that construct.

## Validation

Built-in surfaces such as `#main`, `@background`, `@syntax`, and `@package` are always available.

Use `@` for macros and built-in attribute surfaces. Use `#` for semantic markers.
