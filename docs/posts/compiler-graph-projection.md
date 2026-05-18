# Compiler Graph Projection

Macros and markers should receive typed compiler views, not scrape raw source.

## Feature

Neat can expose core compiler concepts as ordinary typed values. Macros use those values to transform syntax, and markers use abstract effect types to project metadata and graph concepts.

## Example

```neat
marker namespace(): Namespace<Construct>

#namespace
// Basic numeric helpers exposed through the Math namespace.
construct Math {
    function clamp(_ value: Int, min: Int, max: Int) -> Int
}
```

Graph shape:

```text
construct Math
  source comments:
    Basic numeric helpers exposed through the Math namespace.

namespace Math
  description:
    Basic numeric helpers exposed through the Math namespace.
  functions:
    clamp
```

## Reason

This makes the compiler graph a first-class surface. Source shape, comments, declarations, markers, and macros become different views of the same program instead of separate private systems.

The compiler still owns parsing, validation, and lowering, but macros and markers can move data through typed graph values. That is where source and compiler start to become one model.
