# Typed Construction Metadata

I am moving this from point A to point B.

Point A:

```neat
let version: Version = Version(0.1.8)
```

Point B:

```neat
let version: Version(0.1.8)
```

Small syntax.

Different model.

Point A says: typed slot, then assignment.

Point B says: binding born with construction data.

That is the change.

## The Question

Should initialization be assignment into a slot?

Or construction metadata on the declaration?

My answer is point B.

Declaration metadata.

Not assignment.

Not sugar.

## Point A

Point A works.

But it teaches the wrong first story.

```neat
let version: Version = Version(0.1.8)
```

It reads like:

```text
declare slot
annotate Version
assign Version(...)
```

This is the annoying part.

The type repeats.

The `=` makes birth look like mutation.

The graph starts with:

```text
slot
then value
```

I want:

```text
binding
type
construction data
```

Same value.

Better truth.

## Point B

Point B says the thing directly.

```neat
let version: Version(0.1.8)
```

Read:

```text
version is a Version
constructed with 0.1.8
```

The `:` opens the type.

The type receives data.

The declaration owns construction.

Point A:

```text
annotation + assignment expression
```

Point B:

```text
typed construction metadata
```

## The Move

The visible move removes:

```text
=
repeated Version
```

The real move is deeper.

Point A makes the graph recover intent:

```text
annotation: Version
initializer: call Version(...)
```

Point B gives intent directly:

```text
type: Version
construction: Version(...)
```

I do not want the compiler reverse-engineering this.

The source should say it.

## The Model

At point B, the graph keeps the birth shape.

```text
binding version
  storage: let
  type: Version
  construction:
    target: Version
    inputs:
      0 -> 0.1.8
```

After resolution:

```text
binding version
  storage: let
  type: Version
  construction:
    target: Version
    inputs:
      value -> 0.1.8
```

Construction belongs to the declaration.

Not nearby.

Not guessed.

Stored.

Assignment stays separate:

```neat
version = Version(0.1.9)
```

That is mutation.

```text
mutation
  target: version
  value:
    call Version
      value -> 0.1.9
```

One creates.

One changes.

The graph should not blur them.

## Properties

Point A gets worse in constructs.

```neat
construct Package {
    let name: String = String("Neat")
    let version: Version = Version(0.1.8)
    let license: License = License(.mit)
}
```

String equals String.

Version equals Version.

Noise.

Also wrong shape.

Point B:

```neat
construct Package {
    let name: String("Neat")
    let version: Version(0.1.8)
    let license: License(.mit)
}
```

Now it reads as construct data.

```text
Package
  property name
    type: String
    construction:
      value -> "Neat"

  property version
    type: Version
    construction:
      value -> 0.1.8

  property license
    type: License
    construction:
      value -> .mit
```

Storage.

Type.

Construction.

Enough for diagnostics.

Enough for docs.

Enough for hovers.

Enough for package views.

Enough for NeatCloud later.

## Boundary

Lowering can stay boring.

Neat:

```neat
let version: Version(0.1.8)
```

Swift:

```swift
let version: Version = Version(0.1.8)
```

Fine.

Backend shape is not source truth.

Source graph:

```text
declare binding with construction metadata
```

Swift backend:

```text
typed variable initialized by constructor call
```

Different layers.

Different jobs.

The graph comes first.

## Path

Parser sees:

```neat
let name: Type(args)
```

Parser says:

```text
typed construction initializer
```

Not missing `=`.

AST stores:

```text
normal expression initializer
typed construction initializer
```

Graph attaches construction to the binding.

First:

```text
0 -> value
```

Then:

```text
label -> value
```

Validator checks:

```text
declared type owns construction
```

Backend lowers later.

Neat keeps the fact.

## Result

Point A:

```text
assignment-shaped initialization
```

Point B:

```text
declaration-shaped construction
```

The binding is born with construction data.

The graph keeps the birth shape.

Properties become key/value-shaped metadata.

Assignment stays.

Later.

Mutation.

Not birth.

```text
point A repeats
point B reveals
graph remembers
lowering continues
```
