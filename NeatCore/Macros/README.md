# Macros

Current macro surface is split into:

- `CoreMacro`
- `Implementations`

Compiler-owned syntax surfaces now live in `NeatCore/Syntax`:

- `Syntax`
- `Bodies`
- `Statements`
- `Expressions`
- `Types`
- `Declarations`

`Implementations/README.md` is the index of active bootstrap macro coverage and
the current implementation status of each macro target kind.

`NeatSyntax/Sources/NeatSyntax/Macros/Macros.Context.md` documents the current
target-surface model, including declaration-side and application-side macro
access where needed.

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
- Parameter-targeted macros operate through explicit declaration/application facets on `Parameter`, for example `target.declaration.type.rewrite(...)` and nested application-side expression rewrite paths such as `target.application.expression.rewrite(...)`.
- `Init`-targeted macros are graph-driven declaration macros. A concrete initializer may carry them directly, and protocol initializer requirements may carry them onto conforming initializers through graph realization.
- For literal bridging, the base form is `#literal<T>` on `init(literal: T)`, where `T` is a compiler-recognized literal carrier type.
- The compiler recognizes carrier types and literal categories; the macro model defines how the bridge is realized on concrete initializers, with protocol carry as an extension of that same rule.
- Macro closures currently use only `target` and `diagnostics`; bootstrap work should not add extra bindings.
- Local bindings inside macro bodies are syntactically valid, for example
  `value declaration = target.declaration`, but bootstrap rewrite execution is
  currently path-driven and expects direct `target...rewrite(...)` paths for
  reliable behavior.
- Parameter now uses explicit declaration/application facet values on its macro surface.
- `Init` literal lowering now also executes through explicit declaration/application facet semantics.
- Init-side attached rewrites should read from the application argument surface, for example `target.application.arguments[0].expression`, with an enclosing emptiness check when needed.
- Rewrite and extension capability are modeled explicitly with macro-surface protocols such as `SupportsRewrite<T>` and same-type `SupportsExtension`.
- Preferred target-surface design uses declaration/application facet values on
  target kinds such as `Init`, with nested `Declaration` and `Application`
  constructs defining those facet types.
- Callable and array type shapes now use concrete type-reference constructs, for example `FunctionTypeReference(...)` and `ArrayTypeReference(...)`; `Closure` remains the expression/value form.

Current `Init`-targeted status:

- Concrete `#literal<T>` attachment already participates in graph-backed literal bridge realization.
- Protocol init requirements are parsed and keep their carried macros.
- Conforming initializers inherit carried init macros through conformance matching.
- The `Init` surface now models `target.declaration` and `target.application`,
  and `literal` is written in that shape in NeatCore.
- Literal bridge lowering now executes through the authoritative `Init`
  declaration/application rewrite path for `literal`, with an explicit
  diagnostic if that rewrite cannot be interpreted.
- Full generalized `Init` macro execution for arbitrary init-targeted macros is
  still a remaining step beyond `literal`.

This is a temporary bootstrap shape. The surface is being promoted out of `Exploration` only when the model is settled enough to support real compiler behavior.
