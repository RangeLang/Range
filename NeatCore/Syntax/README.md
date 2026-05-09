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

## Granularity

Syntax self-description should be driven by the compiler graphs, not by raw
grammar production rules alone.

A syntax concept deserves a named construct when the declaration graph,
application graph, macro target builder, diagnostics, LSP, or backend lowering
needs to reason about it as a stable semantic node. If a grammar detail is only
surface punctuation, it should usually stay in the parser/renderer instead of
becoming its own syntax construct.

For example:

```neat
return [.loading, .ready]
```

is structurally meaningful as:

```text
Return
  expression: Array.Expression
    elements:
      Enum.Case.Expression(identifier: loading)
      Enum.Case.Expression(identifier: ready)
```

The `return` affects control flow and return validation. The array expression
affects expression typing and array literal lowering. Each enum case expression
affects enum case resolution. The leading `.` in `.loading` is not its own
semantic node; it is syntax for an enum case expression.

This gives a useful middle point: granular enough for the graphs to understand
the program, but not so granular that token-level details become language
concepts.

## Semantic Ownership

Related syntax should be owned by the concept it describes when that ownership
matches the semantic graph.

Prefer:

```neat
Array.Expression
Array.TypeReference
Enum.Case.Declaration
Enum.Case.Expression
Statement.Expression
Construct.Declaration
Construct.Application
```

over a flat namespace such as:

```neat
ArrayExpression
ArrayTypeReference
EnumCaseExpression
ExpressionStatement
```

The broad protocols still matter. `Array.Expression` can conform to
`Expression`, and `Array.TypeReference` can conform to `StructuralTypeReference`.
The important part is that the nested name records semantic ownership, while the
protocol conformance records how the broader compiler pipeline can consume it.

This same rule applies to property hooks. Getter and setter behavior is
function-like, but the macro surface currently exposes it as property-specific
rewrite hooks. Until the declaration graph or application graph needs standalone
getter/setter nodes, it is reasonable for `State`, `Let`, `Binding`, and related
property declarations to own those hooks directly.

In short:

- Granularize where the graphs need stable meaning.
- Nest syntax under the concept that semantically owns it.
- Use broad syntax protocols for consumption across the compiler.
- Do not promote punctuation or renderer details into syntax constructs.
