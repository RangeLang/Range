# Macros

Current macro surface lives in `RangeCompiler/Core/Macro`.

Shipped macro implementations live in `RangeCompiler/Foundation/Macros`. They
are bundled with the compiler, but kept outside the core package surface.

Compiler-owned syntax surfaces now live in `RangeCompiler/Core/Syntax`:

- `Bodies`
- `Statements`
- `Expressions`
- `Types`
- `Declarations`

`RangeSyntax/Sources/RangeSyntax/Macros/Macros.Context.md` documents the current
target-surface model, including declaration-side and application-side macro
access where needed.

Current bootstrap rules:

- Macro declarations must explicitly declare the syntax target they apply to, for example `: Block`, `: Expression`, `: Parameter`, or `: Init`.
- `Block`-targeted macros are special-cased to accept an implicit trailing block payload.
- Extra arguments for block-targeted macros still use `(...)`.
- `Expression`-targeted macros are currently call-style.
- Expression macros may declare an expansion result type with `-> T`. Generic
  result types are resolved from macro argument types where possible.
- Macro parameters can use `@capture` to request call-site syntax capture for
  surfaces such as `Expression`. Plain `Expression` is not syntax capture.
- `@capture` is currently a bootstrap `Parameter` macro. The parser
  records it on the parameter as syntax-capture metadata; it does not rewrite
  the parameter application expression itself.
- Parameter-targeted macros operate through explicit declaration/application facets on `Parameter`, for example `target.declaration.type.rewrite(...)` and nested application-side expression rewrite paths such as `target.application.expression.rewrite(...)`.
- Function-targeted macros are graph-driven declaration macros.
- For literal carriers, the base form is `@literal` on the carrier construct. Concrete `literal(literal: T): Self` functions consume those carriers without carrying `@literal`.
- The compiler recognizes carrier types and literal categories from carrier constructs.
- Macro closures currently use only `target` and `diagnostics`; bootstrap work should not add extra bindings.
- Local bindings inside macro bodies are syntactically valid, for example
  `value declaration = target.declaration`, but bootstrap rewrite execution is
  currently path-driven and expects direct `target...rewrite(...)` paths for
  reliable behavior.
- Parameter now uses explicit declaration/application facet values on its macro surface.
- Function literal lowering now executes through explicit declaration/call facet semantics.
- Function-side attached rewrites should read from the call argument surface, for example `target.call.arguments[0].expression`, with an enclosing emptiness check when needed.
- Rewrite, expansion, and future omission capability are modeled explicitly with macro-surface protocols such as `SyntaxReplaceable<T>`, `SyntaxExpandable<Target>`, and `SyntaxOmittable`.
- Preferred target-surface design uses declaration/application facet values on
  target kinds such as `Init`, with nested `Declaration` and `Application`
  constructs defining those facet types.
- Callable and array type shapes now use concrete type-reference constructs, for example `FunctionTypeReference(...)` and `ArrayTypeReference(...)`; `Closure` remains the expression/value form.

Current function-targeted literal status:

- Concrete construct-level `@literal` attachment already participates in graph-backed literal bridge realization.
- Protocol init requirements are parsed and keep their carried macros.
- Conforming initializers inherit carried init macros through conformance matching.
- The `Function` surface models `target.declaration` and `target.call`,
  and `literal` is written in that shape in RangeCore.
- Literal bridge lowering can execute through the authoritative `Function`
  declaration/call rewrite path for `literal`; while `literal` is empty, a
  missing rewrite is treated as no-op.
- Full generalized `Init` macro execution for arbitrary init-targeted macros is
  separate from literal bridge realization.

This is a temporary bootstrap shape. The surface is being promoted out of `Exploration` only when the model is settled enough to support real compiler behavior.
