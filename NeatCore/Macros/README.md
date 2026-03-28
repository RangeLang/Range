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
- Attached parameter macros are bootstrap-executed from Neat macro bodies through `target.parameter.type.rewrite(...)` and `target.arguments.rewrite(...)`.
- Macro closures currently use only `target` and `diagnostics`; bootstrap work should not add extra bindings.
- For attached parameter macros, `target` may temporarily act as a contextual wrapper around the attached parameter and its invocation-side argument surface.
- Single-argument attached rewrites should read from the explicit plural surface, for example `target.arguments[0].expression`, with an enclosing emptiness check when needed.
- Rewrite and extension capability are modeled explicitly with macro-surface protocols such as `SupportsRewrite<T>` and `SupportsExtension<T>`.
- `FunctionType` is the type-surface model for callable types like `() -> Int`; `Closure` remains the expression/value form.
- `ArrayType` is the type-surface model for array types like `[Int]`.

This is a temporary bootstrap shape. The surface is being promoted out of `Exploration` only when the model is settled enough to support real compiler behavior.
