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

## Validation

Built-in attributes such as `@main`, `@background`, `@language`, and `@package` are always available.

Any other attribute must match a visible namespace name:

```neat
@Missing
construct Panel {}
```

This fails unless `namespace Missing {}` exists in the program.
