# Syntax

Compiler-owned syntax and declaration surfaces live here.

This includes:

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

```range
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

```range
Array.Expression
Array.TypeReference
Enum.Case.Declaration
Enum.Case.Expression
Statement.Expression
Construct.Declaration
Construct.Application
Function.Declaration
Function.Call
Protocol.Declaration
Protocol.Application<Construct.Declaration>
```

over a flat namespace such as:

```range
ArrayExpression
ArrayTypeReference
EnumCaseExpression
ExpressionStatement
```

The broad protocols still matter. `Array.Expression` can conform to
`Expression`, and `Array.TypeReference` can conform to `StructuralTypeReference`.
The `` marker marks compiler-visible syntax surfaces. The nested
name records semantic ownership, while capability protocol conformance records
how the broader compiler pipeline can consume it.

The graph role does not have to be the nested type name. `Function.Call` is a
function application in the graph, but it should still use the domain word
`Call` at the syntax surface. `#GraphDeclaration` and `#GraphApplication` carry
that semantic role without forcing every syntax owner to name its children
`Declaration` and `Application`.

This same rule applies to property hooks. Getter and setter behavior is
function-like, but the macro surface currently exposes it as property-specific
rewrite hooks. Until the declaration graph or application graph needs standalone
getter/setter nodes, it is reasonable for `State`, `Let`, `Binding`, and related
property declarations to own those hooks directly.

In short:

- Granularize where the graphs need stable meaning.
- Nest syntax under the concept that semantically owns it.
- Use `` for compiler-visible syntax surfaces.
- Use capability protocols for consumption across the compiler.
- Do not promote punctuation or renderer details into syntax constructs.

## Graph-Backed Relationships

Not every field in the core syntax model describes inline parser storage.
Some fields describe graph-backed semantic projections.

Protocol conformance is one of those relationships. Source syntax may write a
nominal conformance reference, but the declaration graph resolves that edge
into a protocol application value:

```range
Protocol.Application<Construct.Declaration>
Protocol.Application<Enum.Declaration>
Protocol.Application<Protocol.Declaration>
```

The protocol owns the application vocabulary because the protocol is what
defines the requirements and carried macro semantics being applied. The
declaration graph owns the actual cross-link, so inverse views from a conformer
or from a protocol declaration should project the same graph edge rather than
duplicating relationship storage.
