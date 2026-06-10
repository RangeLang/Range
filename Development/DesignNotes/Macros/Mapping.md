# Macros Mapping

## Definition

This document maps each macro target concept to the language-level structure it exposes.

## Expression And Block Targets

### Expression exposes

- the expression itself
- its syntax kind
- its callee if it is a call
- its arguments if it is a call

### Block exposes

- the block itself
- block invocation/splice with `block()`
- its statements if lower-level access is needed later

## Declaration Targets

### Construct exposes

- its values
- its states
- its bindings
- its deriveds
- its functions
- its initializers
- its conformances
- its identity surface

### Enum exposes

- its cases
- its associated values
- its conformances

### Protocol exposes

- its required graph bindings
- its required functions
- its required initializers
- its inherited protocols
- graph-backed applications to conforming declarations, modeled as
  `Protocol.Application<Construct.Declaration>`,
  `Protocol.Application<Enum.Declaration>`, or
  `Protocol.Application<Protocol.Declaration>`

### Extension exposes

- the target being extended
- the declarations introduced by the extension

### Let, State, Binding, and Derived expose

- its name
- its binding kind
- its type
- its owner
- its default value if present

### Parameter exposes

- its name
- its external label
- its type
- its owner

### Init exposes

- its parameters
- its arguments at the macro application site
- its owner

### Function exposes

- its parameters
- its arguments at the macro application site
- its return type
- its owner
- its body

## Notes

- This is the exposure map, not the final syntax for every field.
- Expression and block targets are syntax-first.
- Declaration targets are resolved semantic structures.
- Syntax values should follow the semantic ownership model described in
  [Syntax](../Syntax.md): granularize where the compiler graphs need stable
  meaning, and prefer owned nested forms such as `Array.Expression`,
  `Enum.Case.Expression`, and `Statement.Expression` over flat token-shaped
  names.
