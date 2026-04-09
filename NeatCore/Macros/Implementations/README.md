# Macro Implementations

This directory holds the active bootstrap macro definitions that are part of the
loaded `NeatCore` surface.

The goal of this folder is not only to store macro declarations, but also to
make it obvious from one place:

- which macro target kinds currently have active implementations
- which concrete macros exist for each target kind
- which parts are truly executed from macro bodies today
- which parts are still modeled by compiler-side bootstrap behavior

## Current Coverage

### `Expression`

Implemented macros:

- `stringify`
- `unwrap`

Current status:

- Expression-targeted macro bodies are actively interpreted by the compiler.
- Result types declared with `-> T` participate in macro result inference.
- Generic result substitution is supported, for example `unwrap<T>(...) -> T`.
- Syntax-category parameters such as `capture Expression` are supported.

### `Block`

Implemented macros:

- `lock`
- `trace`

Current status:

- Block-targeted macro bodies are actively interpreted by the compiler.
- Trailing block payload is part of the current bootstrap invocation model.

### `Parameter`

Implemented macros:

- `autoclosure`
- `variadic`

Current status:

- Parameter-targeted macros currently work through bootstrap-interpreted rewrite
  operations from macro bodies.
- They already use declaration plus application-side behavior:
  the macro is attached to a parameter declaration, while expansion rewrites the
  callable signature and the invocation arguments together.

### `Init`

Implemented macros:

- `literal`

Current status:

- Direct `#literal<T>` attachment on a concrete initializer participates in
  graph-backed literal bridge realization.
- Protocol initializer requirements may also carry `#literal<T>` onto
  conforming initializers through declaration-graph realization.
- General `Init` macro body execution is not implemented yet.
- `literal` currently works through declaration-graph literal bridge semantics
  rather than a fully generalized init-macro execution path.

## Current Rule Of Thumb

- `Expression` and `Block` are the most complete macro targets today.
- `Parameter` is real, but still bootstrap-shaped.
- `Init` has real language surface and real graph participation, but not yet a
  generalized body-execution model.

## Important Separation

Some target types expose structural surface directly in `NeatCore`, for example:

- `Expression`
- `Block`
- `Parameter`
- `Init`

Some expansion-time information does not belong to the declaration or syntax
node itself. That information is contextual and is still mostly compiler-owned.

Examples of contextual information include:

- captured invocation arguments
- matched construction or call application
- expected type during expansion

This is the main remaining design gap for normalizing `Init` and future
declaration-targeted macros.

## Gaps To Cover Next

These are the main macro-target areas that still need clearer coverage or
implementation work:

- Normalize expansion context as an explicit concept separate from the target
  itself.
- Generalize `Init` macro execution beyond literal bridge realization.
- Decide whether callable-targeted macros such as `Function` should become part
  of the active surface.
- Decide whether state-, construct-, derived-, or enum-targeted macros should
  move from exploration into the active bootstrap surface.
- Document the mapping between each macro target kind and the structural versus
  contextual API it receives during expansion.

## Why This Index Exists

Macro design is now large enough that implementation status should be visible
without reading the compiler internals first.

This file is the index for that status.
