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
marker namespace(): Construct -> Bool registers namespace {
    true
}

#namespace
construct Language {
    let defaultLocale: String("en")
}
```

The `registers namespace` marker registration makes every construct annotated with `#namespace` globally visible as a namespace. This also makes `@Language` valid. The construct body acts like namespace-owned configuration instead of instance storage.

The declaration graph should collect that fact:

```text
namespace Styling
attribute Styling
  source: namespace Styling

namespace Language
attribute Language
  source: #namespace construct Language
```

The attribute also attaches the namespace behavior to the declaration that uses it:

```neat
#namespace
construct Persisted {
    let keyPrefix: String("settings")

    function key(_ name: String) -> String {
        return keyPrefix + "." + name
    }
}

@Persisted
construct Profile {
    let displayName: String
}
```

The graph can read this as:

```text
construct Profile
attribute attachment Persisted
  namespace values: keyPrefix
  namespace functions: key
```

That keeps attribute behavior script-defined. A later semantic or backend phase can ask the graph which namespace behavior is attached to `Profile`, instead of treating `@Persisted` as a parser keyword or a backend-private switch.

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

`#namespace` is not a compiler-hardcoded macro name. It is a marker with a global registration effect. That keeps the same path open for later host-specific registrations such as client/server splits without adding one parser rule per host.

The parser should not hardcode every domain tag, and the validator should not rediscover namespace declarations by walking raw source.
