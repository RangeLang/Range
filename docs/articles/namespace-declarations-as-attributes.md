# Namespace Declarations As Attributes

Namespace-backed attributes are declaration facts.

Not validator side tables.

## Shape

```neat
namespace Styling {}

@Styling
construct Panel {
    let title: String
}
```

A namespace declaration makes an attribute name available.

Namespace-shaped configuration can use the declaration macro form:

```neat
#namespace
construct Language {
    let defaultLocale: String("en")
}
```

This also makes `@Language` valid. The construct body acts like namespace-owned configuration instead of instance storage.

The declaration graph should collect that fact:

```text
namespace Styling
attribute Styling
  source: namespace Styling

namespace Language
attribute Language
  source: #namespace construct Language
```

## Rule

Validation asks the graph whether an attribute name is known.

The graph knows because it collected namespace declarations.

Unknown attributes should still produce a concrete diagnostic:

```text
Declare namespace Missing to use @Missing.
```

## Boundary

Built-in attributes remain compiler-known.

Namespace attributes are program-declared names.

The parser should not hardcode every domain tag, and the validator should not rediscover namespace declarations by walking raw source.
