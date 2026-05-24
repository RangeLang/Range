# Metatype Extras

Metatypes should not only point at runtime types. They should be able to carry language surfaces.

Range already wants declarations, macros, markers, syntax, packages, and files to participate in the same graph. That means the type system needs a way to talk about type-shaped things that are not ordinary values.

## Macro And Marker Surfaces

`@syntax` and `#Token` are not queries.

They are surfaces.

```range
let syntax: Array<@syntax>()
let tokens: Array<#Token>()
```

This has the same shape as an existential collection:

```range
let shapes: Array<Shape>()
```

The array does not ask the graph to find every shape. It says each element in the array must satisfy the `Shape` surface.

For Range, the spelling can stay explicit:

```range
Array<@syntax>()
Array<#Token>()
```

`@syntax` means the element satisfies the syntax macro surface. `#Token` means the element satisfies the token marker surface. The compiler may derive or populate those arrays from graph facts, but the type meaning is ordinary: a homogeneous collection of values that share one metatype surface.

## Target Algebra

Macro and marker attachment targets should compose like metatypes.

```range
open macro capture(): Parameter, Construct, Construct & Enum, Construct | Enum {
}
```

Comma and `|` mean any listed surface is allowed.

`&` means the target must satisfy both surfaces.

This lets a macro describe its attachment domain directly. It also keeps policy near the declaration instead of scattering it across parser branches.

## Token As Macro Surface

Tokens can be described through macros too.

```range
@token(,)
construct Comma {}

@token(->)
construct Arrow {}
```

The token macro receives the spelling and emits the token model. The raw character sequence is not a stringly rule hidden in Swift. It becomes a typed value attached to the declaration graph.

`@capture` is the same idea at the parameter level:

```range
open macro token(@capture spelling: TokenSpelling): Construct {
}
```

The macro declaration says the argument is captured. Call sites stay clean:

```range
@token(,)
construct Comma {}
```

The application does not repeat `@capture`; the parameter carries that behavior.

## Files As Functors

A Range file should be understood as a transform between program states.

```text
Program<A> -> Program<B>
```

A file can declare syntax, attach markers, run macros, add graph facts, validate requirements, and expose runtime behavior. That makes a file a typed graph transform, not just text waiting for a compiler.

This is why metatype extras matter. The compiler needs to describe the surfaces that a file consumes and produces:

```range
let input: Program<@syntax>
let output: Program<@syntax, #Token>
```

The exact spelling can evolve, but the direction is important: macro and marker surfaces are type-level facts, and files compose through those facts.

## Why This Matters

Without metatype extras, every new compiler axis becomes a special case:

- syntax boundary
- token declaration
- macro target
- marker proof
- captured argument
- file transform

With metatype extras, these become ordinary type operations over graph surfaces.

The language checks itself first. Then the compiler lowers those checked surfaces into whatever the host pipeline needs today.
