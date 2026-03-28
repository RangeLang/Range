# Macros

Current macro surface is split into:

- `CoreMacro`
- `Bodies`
- `Statements`
- `Expressions`
- `Types`
- `Implementations`

Current bootstrap rules:

- `Freestanding<Block>` is special-cased to accept an implicit trailing block payload.
- Extra arguments for block freestanding macros still use `(...)`.
- `Freestanding<Expression>` is currently call-style.
- `Attached` remains part of the core macro surface, but attached macro execution is not implemented yet.

This is a temporary bootstrap shape. The surface is being promoted out of `Exploration` only when the model is settled enough to support real compiler behavior.
