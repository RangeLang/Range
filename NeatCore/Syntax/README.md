# Syntax

Compiler-owned syntax and declaration surfaces live here.

This includes:

- `Syntax`
- `Bodies`
- `Statements`
- `Expressions`
- `Types`
- `Declarations`

These surfaces are broader than macros. Macros may target them, rewrite them,
or attach behavior to compiler-known syntax nodes, but they are not owned by
the macro system itself.
