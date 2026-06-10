# Types, Metatypes, And Set Theory

Range types and metatypes can be understood as sets of things that exist in the
program. This gives the language a small, mathematical model for ordinary type
checking, macro validity, reflection, type narrowing, and filtering without
importing the complexity of a Swift-style existential system.

The model should not be biased toward macros. Macro targets are one application
of the same idea, not a separate kind of reasoning.

## Core Idea

A type is a set.

Examples:

```range
Int
String
User
@syntax
@property
Function.Declaration
Construct.Declaration
Enum.Declaration
```

Each type describes the values or meta-values that satisfy it:

```text
Int                  = all integer values of that type
User                 = all User values
@syntax              = all syntax-facing meta-values
@property            = all transform-capable property declaration meta-values
Function.Declaration = function declarations
Construct.Declaration = construct declarations
```

The useful primitive is membership:

```text
value is in Int
value is in User
value is in @property
value is in Function.Declaration
value is in @syntax
```

This is a database-like view of the type system: a type names a collection of
valid rows or entities, and type operations ask how those collections relate.

For metatypes and syntax reflection, this is protocol-like classification, but it
does not need full existential behavior by default. Most code only needs to ask
whether a value satisfies a type or surface and then narrow it if it does.

## Target Composition

Macro target declarations are one place where type-as-set expressions become
visible.

Union:

```range
macro inspect(): @property | Function.Declaration { target, diagnostics in
}
```

This means the macro is valid for values in either type set.

Intersection:

```range
macro inspect(): @syntax & @property { target, diagnostics in
}
```

This means the macro is valid only for values that satisfy both type sets.

The compiler can reason about validity by checking whether the target set and the
actual value's type set overlap.

## Filtering

Array filtering by type is set intersection over the array.

```range
let members: [@syntax] = target.declaration.members
let properties: [@property] = members.filter(@property)
let functions: [Function.Declaration] = members.filter(Function.Declaration)
let nested: [Construct.Declaration] = members.filter(Construct.Declaration)
```

The operation is failable per element, not failable as a whole:

```text
for each element:
  if element is in the requested type set, keep it
  otherwise drop it
```

So:

```range
members.filter(@property)
```

means:

```text
members intersect @property
```

If no elements satisfy the requested type, the result is an empty array.

## Narrowing

The array result should be statically narrowed:

```range
[@syntax].filter(@property) -> [@property]
[@syntax].filter(Function.Declaration) -> [Function.Declaration]
[@property].filter(State) -> [State]
```

Single-value narrowing can use the same model but return an optional:

```range
let property: @property? = member.as(@property)
```

This is similar to Swift's `as?`, but the type relationship is part of Range's
type model rather than an existential cast.

## Validity

The compiler needs a satisfiability relation:

```text
Can values of A ever satisfy B?
```

Examples:

```range
[@syntax].filter(@property)              // valid
[@syntax].filter(Function.Declaration)   // valid
[@property].filter(State)                // valid
[@property].filter(Function.Declaration) // known impossible
```

For known-impossible intersections, Range should prefer a compile-time error
over silently returning an always-empty array. Empty arrays are useful when the
input may or may not contain matching elements; they are less useful when the
type relationship itself proves matching can never happen.

## Members Versus Properties

This model suggests that "member" should be a relationship, not necessarily a
special type surface.

For example:

```range
target.declaration.members: [@syntax]
```

Then code can narrow to the category it actually needs:

```range
let properties: [@property] = target.declaration.members.filter(@property)
let functions: [Function.Declaration] = target.declaration.members.filter(Function.Declaration)
let constructs: [Construct.Declaration] = target.declaration.members.filter(Construct.Declaration)
```

In this framing:

- `member` is a graph/declaration relationship.
- `@syntax` is the broad syntax meta-value universe.
- `@property` is a semantic category for transform-capable property declarations.

There is no separate `@field` surface for now. Broad member lists should use
graph or syntax collections plus narrowing. `@property` remains the semantic
category for transform-capable property declarations.

## Property Surfaces

`@property` should represent transform-capable property declarations:

```text
Let
State
Binding
Derived
```

These are the declarations that can support property macro hooks such as:

```range
initializer(transform:)
getter(transform:)
setter(transform:)
```

Functions and nested constructs may be members, and they may be syntax values,
but they should not satisfy `@property` unless the language deliberately gives
them property-like transform behavior.

## Why This Avoids Existential Weight

Swift-style existentials bundle several concerns together:

- membership in a protocol
- dynamic dispatch through an erased value
- storage representation
- cast syntax
- generic constraints

Range metatypes and macro reflection do not need all of that for the common case.
They mostly need:

- membership checks
- optional narrowing for one value
- filtered narrowing for arrays
- target-set validation for macros

That can be modeled directly with types and surfaces as sets.

## Open Questions

- Should `filter(Type)` be separate from predicate filtering, or should
  it overload `filter`?
- Should impossible intersections be compile-time errors everywhere, or only in
  strict contexts?
- Should there be a spelling for set difference, such as `reject(@property)` or
  `filter(!@property)`?
- Should broad member lists use `[@syntax]` plus filtering, or should the graph
  expose a dedicated member relationship view?
- Should type expressions support explicit difference, for example
  `@syntax - @property`?
- How should graph identities participate in narrowing: as direct values, lazy
  declarations, or typed views over graph entities?

## Working Rule

The guiding rule:

```text
Types are sets of values or meta-values.
Macro targets are type-set expressions.
Filtering is set intersection.
Single-value narrowing is optional membership.
Array narrowing returns the matching subset.
```

This keeps the model small and makes macro reflection feel like ordinary type
reasoning instead of a separate casting system.
