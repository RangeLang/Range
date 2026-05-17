# Typed Construction Metadata

Neat should let properties and local bindings be born with construction data, instead of pretending initialization is assignment.

## The Problem

This form works, but it says more than it needs to:

```neat
let version: Version = Version(0.1.8)
```

It reads like two separate operations: declare a typed slot, then assign a constructed value into it. That is a useful model for mutation, but it is not the cleanest model for initialization.

For properties especially, initialization is structural. It is part of the data that defines the construct.

## The Change

The proposed form is:

```neat
let version: Version(0.1.8)
```

This should read as:

```text
version is a Version, with construction data 0.1.8
```

The colon becomes a window into the type. What follows is not just an annotation and not a later assignment. It is typed construction metadata for the binding.

## Graph Meaning

This should not be implemented as shallow syntax sugar. The graph should preserve the declaration-level intent:

```text
binding version
  storage: let
  type: Version
  initializer:
    construct Version
      inputs:
        value -> 0.1.8
```

Assignment stays separate:

```neat
version = Version(0.1.9)
```

That means "mutate an existing storage location." Typed construction metadata means "this binding is created with this construct data."

## Why It Matters

For construct properties, the shape becomes naturally key/value-like:

```neat
construct Package {
    let name: String("Neat")
    let version: Version(0.1.8)
    let license: License(.mit)
}
```

The graph can now understand these declarations as data about the construct:

```text
property name
  construct String
  input value -> "Neat"

property version
  construct Version
  input value -> 0.1.8

property license
  construct License
  input value -> .mit
```

That helps the compiler, editor tooling, diagnostics, documentation, and future package or cloud views. The graph does not need to reverse-engineer intent from a repeated constructor call.

## Implementation Sequence

The parser should recognize `let name: Type(args)` as a declaration initializer form, not as a type annotation followed by a missing `=`.

The AST should preserve that distinction. A normal expression initializer and a typed construction initializer may lower similarly later, but they should not be collapsed before the graph has captured source intent.

The graph builder should emit construction metadata on the binding or property node. Unlabeled constructor inputs can be represented with positional keys until the declaration graph resolves parameter names.

The semantic validator should require the constructor target to match the declared type in this position. That keeps the form readable: the type after `:` owns the construction context.

The backend can lower the form to the existing constructor call shape when needed, but that is a backend lowering detail. The source graph should continue to know that the binding was born from typed construction metadata.
