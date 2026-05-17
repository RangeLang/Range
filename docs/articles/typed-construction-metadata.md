# Typed Construction Metadata

I want to describe this change as a move from point A to point B.

Point A was this:

```neat
let version: Version = Version(0.1.8)
```

Point B is this:

```neat
let version: Version(0.1.8)
```

The visible change is small. The model change is not. We are moving from "typed slot, then assignment" to "binding born with construction data."

That is the answer to the design question.

## The Question

Should an initialized typed binding be modeled as assignment into a slot, or as construction data attached to the declaration?

At point A, the syntax pushed me toward assignment:

```neat
let version: Version = Version(0.1.8)
```

At point B, the syntax pushes the compiler toward declaration metadata:

```neat
let version: Version(0.1.8)
```

My answer is point B. Not because it is shorter, though it is. Because it tells the graph the right first fact: the binding is born as `Version`, with data.

## Point A

Point A worked, but it made the wrong thing look primary.

```neat
let version: Version = Version(0.1.8)
```

It reads like a sequence of operations: declare a slot named `version`, annotate it as `Version`, then assign `Version(0.1.8)` into it. This is the annoying part. The type appears twice, and the `=` makes initialization look like mutation.

That model is useful when something is actually being assigned later:

```neat
version = Version(0.1.9)
```

But initialization is not that. Initialization is earlier. It is where the binding becomes real.

Point A taught this first abstraction:

```text
slot
then value
```

That is the wrong starting point for the graph. I want the compiler to begin with:

```text
binding
type
construction data
```

Same final value. Different truth.

## Point B

Point B says the thing directly:

```neat
let version: Version(0.1.8)
```

I read it as:

```text
version is a Version
constructed with 0.1.8
```

The `:` opens the type, and the type receives data. The declaration owns the construction.

So the state changes like this:

```text
point A: annotation plus assignment expression
point B: typed construction metadata
```

The inferred form still matters:

```neat
let version = Version(0.1.8)
```

That form says the expression determines the type. Point B says the declaration already knows the type, and the data enters through that type.

Small syntax. Different source fact.

## The Move

The move from point A to point B removes two bits of noise:

```text
=
repeated constructor type
```

But the important move is semantic.

Point A makes the graph recover meaning from an expression:

```text
annotation: Version
initializer expression: call Version(...)
```

Point B gives the graph the meaning directly:

```text
type: Version
construction: Version(...)
```

That is the whole reason I want this. The compiler should not have to notice that the annotation and the constructor happen to match, then reverse-engineer the intent. The source should say the intent.

Point A:

```text
the value is assigned
```

Point B:

```text
the binding is born
```

That is the move.

## The Model

At point B, the graph should represent the binding as born with construction data:

```text
binding version
  storage: let
  type: Version
  construction:
    target: Version
    inputs:
      0 -> 0.1.8
```

After constructor resolution, the graph can become more precise:

```text
binding version
  storage: let
  type: Version
  construction:
    target: Version
    inputs:
      value -> 0.1.8
```

This gives the graph a stable fact: construction belongs to the declaration. It is not nearby. It is not inferred later. It is not recovered from a call expression because the source shape already said it.

Assignment remains a different operation:

```neat
version = Version(0.1.9)
```

That models mutation:

```text
mutation
  target: version
  value:
    call Version
      value -> 0.1.9
```

One creates. One changes. If the graph erases that difference, tools have to guess, and I do not want tools guessing.

## The Property Case

The move matters more for properties.

At point A, a construct had this shape:

```neat
construct Package {
    let name: String = String("Neat")
    let version: Version = Version(0.1.8)
    let license: License = License(.mit)
}
```

String equals String. Version equals Version. License equals License. It is noisy, but noise is not the main problem. The real problem is that property defaults look like assignments.

At point B:

```neat
construct Package {
    let name: String("Neat")
    let version: Version(0.1.8)
    let license: License(.mit)
}
```

Now the construct reads as data:

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

The conclusion follows from the model. If properties are part of a construct's shape, their initial values should be represented as shape data: storage, type, construction.

That is enough for diagnostics. Enough for docs. Enough for editor hovers. Enough for package views. Enough for NeatCloud later, where constructs become shareable things with visible shape.

## The Boundary

Point B does not require the backend to become clever. Lowering can stay boring.

This Neat:

```neat
let version: Version(0.1.8)
```

can still lower to this Swift:

```swift
let version: Version = Version(0.1.8)
```

That is fine. The backend may want assignment-shaped initialization. But the source graph should not collapse into that shape early.

Source graph:

```text
declare binding with construction metadata
```

Swift backend:

```text
typed variable initialized by constructor call
```

Different layers. Different jobs. The source layer answers what the Neat program means. The backend layer answers how to emit that meaning somewhere else. The source layer comes first, because parser behavior, diagnostics, graph rendering, macros, editor tooling, and package metadata all need the point-B shape.

## The Path

The parser should recognize point B:

```neat
let name: Type(args)
```

as a typed construction initializer. It should not ask for `=`.

The AST should store the distinction:

```text
normal expression initializer
typed construction initializer
```

They may share call argument structures, but they should not share meaning too early. The graph builder should attach construction data to the binding or property node. First positional:

```text
0 -> value
```

Then resolved:

```text
label -> value
```

The semantic validator should check that the construction target matches the declared type. In this position:

```neat
let version: Version(...)
```

`Version` owns the call. The backend lowers later. Swift gets the constructor call. Neat keeps the declaration fact.

## The Result

The move is from point A to point B:

```text
point A: assignment-shaped initialization
point B: declaration-shaped construction
```

Point A repeated the type. Point A made initialization look like mutation. Point A taught the graph `slot, then value`.

Point B fixes the first story:

```neat
let version: Version(0.1.8)
```

The binding is born with construction data. The graph keeps the birth shape. Properties become key/value-shaped metadata about a construct. Assignment stays alive, but later, for mutation, not birth.

The diff is small, but the model moves:

```text
point A repeats
point B reveals
model separates
graph remembers
lowering continues
```
