# Typed Construction Metadata

Neat should treat typed construction in declarations as first-class metadata. The shift is small in syntax, but large in meaning: initialization stops looking like assignment, and a binding becomes a piece of declared structure that is born with construction data.

## The Starting Point

The ordinary way to write an explicitly typed initialized binding is:

```neat
let version: Version = Version(0.1.8)
```

That line works, but it teaches the wrong model. It makes the declaration look like two events:

```text
declare a slot named version with type Version
assign Version(0.1.8) into the slot
```

That is a good story for mutation. It is not the best story for initialization.

Initialization is not a later write into an already meaningful location. Initialization is the moment the binding becomes meaningful. For properties, this is even clearer: the initializer is part of the data that describes the construct.

The repetition is the visible symptom:

```neat
Version = Version(...)
```

The deeper issue is that the source shape hides the declaration-level fact. The binding is not just receiving a value. The binding is being constructed as a `Version`.

## The Turn

The smaller form makes that fact visible:

```neat
let version: Version(0.1.8)
```

This should read as:

```text
version is a Version, constructed with 0.1.8
```

The `:` opens a window into the type. What follows is not merely an annotation, and it is not a missing assignment expression. It is construction data attached to the declaration.

The inferred constructor form still has its place:

```neat
let version = Version(0.1.8)
```

That form says the expression determines the type. The typed construction form says the declaration owns the type, and the construction inputs belong to that declaration.

That distinction gives the compiler a better source model before any backend lowering happens.

## The Model

The graph should keep typed construction as binding metadata:

```text
binding version
  storage: let
  type: Version
  construction:
    target: Version
    inputs:
      0 -> 0.1.8
```

At first, an unlabeled argument can be represented positionally. After constructor resolution, the graph can carry the resolved parameter shape:

```text
binding version
  storage: let
  type: Version
  construction:
    target: Version
    inputs:
      value -> 0.1.8
```

The important part is ownership. The construction belongs to the binding. It is declaration metadata, not an arbitrary expression glued onto the side.

Assignment remains separate:

```neat
version = Version(0.1.9)
```

That source line creates a mutation:

```text
mutation
  target: version
  value:
    call Version
      value -> 0.1.9
```

The two forms can eventually produce similar machine behavior, but they do not mean the same thing in the source graph. One creates the binding. The other changes an existing binding.

## The Property Shape

Once the graph keeps that fact, properties become data-shaped:

```neat
construct Package {
    let name: String("Neat")
    let version: Version(0.1.8)
    let license: License(.mit)
}
```

This reads as data about `Package`:

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

The construct now exposes a clear property map. Each property carries its storage kind, declared type, construction target, and construction inputs.

That is the model Neat wants tools to see. A documentation view can show the property as typed data. A diagnostic can explain the construction input that failed. A package or cloud view can inspect the construct shape without reverse-engineering repeated constructor calls.

The old form still describes how to make a value:

```neat
let version: Version = Version(0.1.8)
```

The new form describes what the declaration is.

## The Boundary

Lowering can still be ordinary Swift, but it happens later.

The source form:

```neat
let version: Version(0.1.8)
```

can lower to:

```swift
let version: Version = Version(0.1.8)
```

That does not make the Neat feature assignment sugar. It means the Swift backend has a convenient target shape.

The source graph should preserve this operation:

```text
declare binding with construction metadata
```

The backend can emit this operation:

```text
typed variable initialized by constructor call
```

The boundary matters because parser behavior, diagnostics, editor features, graph rendering, macro expansion, and future cloud/package metadata all operate before or beside backend lowering. They should see the source intent, not only the emitted shape.

## The Path

The parser recognizes `let name: Type(args)` as a declaration initializer form. When a construction argument list follows the type, the parser should not treat the missing `=` as an error.

The AST stores this initializer as typed construction metadata. It can reuse call-argument structures, but it should keep the declaration form distinct from a normal expression initializer.

The graph builder attaches construction metadata to the binding or property node. Positional inputs can be stored first, then enriched with parameter labels after constructor resolution.

The semantic validator checks that the construction target matches the declared type. In this position, the type after `:` owns the construction context, so `Version(...)` means construction of `Version`, not a chance to call something unrelated.

The backend lowers the metadata to the target representation. Swift output can use a normal constructor call. The graph remains richer than the output because the graph is carrying Neat's source-level model.

## The Result

Typed construction metadata makes declarations read like declarations again.

```neat
let version: Version(0.1.8)
```

The binding is born with construction data. The graph keeps that fact. Properties become key/value-shaped metadata about their construct. Assignment remains available for mutation, but it stops being the default metaphor for initialization.

That gives Neat a cleaner compiler model and a clearer user-facing model at the same time. The code is shorter, but the real win is that the source now says what the graph needs to know.
