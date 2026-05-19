# Namespace Attributes

## Definition

A namespace is declared by applying a marker whose effect type is `Namespace<Construct>` to a construct.
That makes the construct name available as an attribute.

## Role

Namespace attributes are semantic tags. They let libraries group declarations under a named concept without requiring a new built-in attribute for every domain.

## Example

```neat
#namespace
construct Styling {
}

@Styling
construct Panel {
    let title: String
}
```

The standard `#namespace` marker is just the core spelling of that pattern:

```neat
marker namespace(): Namespace<Construct>

#namespace
construct Language {
    let defaultLocale: String("en")
}
```

The marker's `Namespace<Construct>` effect declares a namespace named `Language`. The `let` entries are namespace configuration, not instance fields.

## Validation

Built-in surfaces such as `#main`, `@background`, `@syntax`, and `@package` are always available.

Any other attribute must match a visible namespace name:

```neat
@Missing
construct Panel {}
```

This fails unless a visible `Namespace<Construct>` marker-backed namespace named `Missing` exists in the program, for example `#namespace construct Missing`.
