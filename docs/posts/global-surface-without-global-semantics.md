# Global Surface Without Global Semantics

`#namespace` gives shared values and functions a globally available surface without changing what the declaration means.

## Observation

The source can stay ordinary:

```neat
#namespace
// Basic numeric helpers exposed through Math.
construct Math {
    function clamp(_ value: Int, min: Int, max: Int) -> Int
}
```

`Math` is still a construct.

`clamp` is still a function on that declaration.

The namespace marker projects a global surface from those facts:

```text
construct Math
  functions:
    clamp

namespace Math
  globally available functions:
    clamp -> Math.clamp
```

## Shape

The graph can expose `Math.clamp` everywhere without inventing a separate global variable or static member model.

```text
source declaration
  construct Math
    function clamp

graph projection
  namespace Math
    clamp

use sites
  can resolve Math.clamp
```

Global availability is a graph projection.

It is not a mutation of the source semantics.

## Reason

Static-like helpers are useful, but they should not corrupt the core model.

`#namespace` keeps the declaration shape honest and moves the availability rule into the graph. The compiler gets a globally discoverable handle, while the language still has one meaning for constructs, functions, and namespace projection.
