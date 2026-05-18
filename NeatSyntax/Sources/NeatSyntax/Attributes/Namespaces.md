# Namespace Attributes

## Definition

Declaring a namespace makes its name available as an attribute.

## Role

Namespace attributes are semantic tags. They let libraries group declarations under a named concept without requiring a new built-in attribute for every domain.

## Example

```neat
namespace Styling {}

@Styling
construct Panel {
    let title: String
}
```

Namespace-shaped configuration can use `#namespace` on a construct:

```neat
marker namespace(): Construct -> Bool registers namespace {
    true
}

#namespace
construct Language {
    let defaultLocale: String("en")
}
```

The marker's `registers namespace` effect declares a namespace named `Language`. The `let` entries are namespace configuration, not instance fields.

## Validation

Built-in attributes such as `@main`, `@background`, `@language`, `@syntax`, and `@package` are always available.

Any other attribute must match a visible namespace name:

```neat
@Missing
construct Panel {}
```

This fails unless `namespace Missing {}` exists in the program.
