# Macros

Current macro surface is split into:

- `CoreMacro`
- `Bodies`
- `Statements`
- `Expressions`
- `Types`
- `Implementations`

`Implementations/README.md` is the index of active bootstrap macro coverage and
the current implementation status of each macro target kind.

Current bootstrap rules:

- Macro declarations must explicitly declare the syntax target they apply to, for example `: Block`, `: Expression`, `: Parameter`, or `: Init`.
- `Block`-targeted macros are special-cased to accept an implicit trailing block payload.
- Extra arguments for block-targeted macros still use `(...)`.
- `Expression`-targeted macros are currently call-style.
- Expression macros may declare an expansion result type with `-> T`. Generic
  result types are resolved from macro argument types where possible.
- Macro parameters can use `capture T` to request call-site syntax capture for
  syntax-category types such as `Expression`. Plain `Expression` is not syntax
  capture.
- Parameter-targeted macros are bootstrap-executed from Neat macro bodies through `target.parameter.type.rewrite(...)` and `target.arguments.rewrite(...)`.
- `Init`-targeted macros are graph-driven declaration macros. A concrete initializer may carry them directly, and protocol initializer requirements may carry them onto conforming initializers through graph realization.
- For literal bridging, the base form is `#literal<T>` on `init(literal: T)`, where `T` is a compiler-recognized literal carrier type.
- The compiler recognizes carrier types and literal categories; the macro model defines how the bridge is realized on concrete initializers, with protocol carry as an extension of that same rule.
- Macro closures currently use only `target` and `diagnostics`; bootstrap work should not add extra bindings.
- For parameter-targeted macros, `target` may temporarily act as a contextual wrapper around the parameter and its invocation-side argument surface.
- Single-argument attached rewrites should read from the explicit plural surface, for example `target.arguments[0].expression`, with an enclosing emptiness check when needed.
- Rewrite and extension capability are modeled explicitly with macro-surface protocols such as `SupportsRewrite<T>` and `SupportsExtension<T>`.
- `FunctionType` is the type-surface model for callable types like `() -> Int`; `Closure` remains the expression/value form.
- `ArrayType` is the type-surface model for array types like `[Int]`.

Current `Init`-targeted status:

- Concrete `#literal<T>` attachment already participates in graph-backed literal bridge realization.
- Protocol init requirements are parsed and keep their carried macros.
- Conforming initializers inherit carried init macros through conformance matching.
- General `Init` macro body execution is still the missing piece; `literal` currently lowers through declaration-graph literal bridge semantics.

This is a temporary bootstrap shape. The surface is being promoted out of `Exploration` only when the model is settled enough to support real compiler behavior.
