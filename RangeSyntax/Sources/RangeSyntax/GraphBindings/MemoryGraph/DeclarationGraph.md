# Declaration Graph

## Compiler Pipeline

Range's compiler pipeline should be understood in this order:

1. `Lexer`
2. `Parser`
3. `AST`
4. `Declaration Graph`
5. `Semantic Resolution`
6. `Memory Graph`
7. `Reactivity Graph`
8. `Backend Lowering`
9. `Emission`

This ordering matters:

- the AST records what was written
- the declaration graph resolves declaration meaning
- semantic resolution derives settled language facts from that graph
- the memory graph and reactivity graph build on already-resolved semantics
- backends adapt settled Range meaning to a target representation

The declaration graph is therefore in front of backend lowering. A backend may still need AST structure for bodies and source layout, but it should not treat raw AST as the final semantic source of truth.

## Definition

The declaration graph is Range's static semantic graph of declarations and declaration-to-declaration relationships. It records what declarations exist, what they mean, and how they are connected before storage, ownership, or mutation reasoning begins.

## Role

The declaration graph is the compiler layer that resolves semantic structure such as protocols, conformances, requirements, satisfying declarations, declaration-targeted macros, and literal bridge realization.

It exists between syntax and the memory graph:

- the AST records written source structure
- the declaration graph records resolved declaration semantics
- the memory graph records storage, ownership, aliasing, mutation, and derived dependencies

It also precedes backend adaptation:

- the declaration graph resolves what a program means in Range
- a backend later adapts that semantic result to a target representation

## Mental Model

- The declaration graph is not a runtime graph. It is a compiler graph.
- The declaration graph is not the memory graph. It does not model ownership or storage.
- The declaration graph answers questions such as "what does this declaration conform to?" and "which initializer satisfies this requirement?"
- The memory graph answers different questions such as "who owns this storage?" and "what mutations or dependencies exist across this path?"
- Semantic features that depend on declaration relationships should be derived from the declaration graph rather than from ad hoc compiler tables.

## Properties

- Declarations appear as graph nodes.

```range
construct Int {
    @literal<IntLiteral>
    function literal(literal: IntLiteral): Self
}

macro literal<T>(): Function { target, diagnostics in }
```

- Literal bridge macros are first-class declaration facts.

```range
construct Int {
    @literal<IntLiteral>
    function literal(literal: IntLiteral): Self
}
```

The graph records that `Int.literal(literal:)` accepts `IntLiteral`.

- Literal acceptance should be derived from graph facts rather than destination tables.

```range
construct Int {
    @literal<IntLiteral>
    function literal(literal: IntLiteral): Self { }
}
```

From the declaration graph, the compiler can derive that `Int` accepts `IntLiteral`.

- Default literal resolution should also be derived after declaration-graph realization.

If a literal has no contextual type, the semantic phase may choose a preferred destination such as an `` bridge. That is still part of Range semantics, not backend behavior.

- The declaration graph precedes the memory graph.

```range
construct User {
    state count: Int = 0
}
```

The compiler should know that `Int` is a valid declaration-level type before it reasons about `count` as owned mutable storage in the memory graph.

## Examples

- Literal bridge realization belongs in the declaration graph.

```range
construct String {
    @literal<StringLiteral>
    function literal(literal: StringLiteral): Self { }
}
```

The relevant graph facts are:

- `String` declares a concrete literal bridge function
- that function carries `<StringLiteral>`
- therefore `String` accepts `StringLiteral`

If source contains:

```range
state title = "hello"
```

then the declaration graph and literal-resolution rules may derive a semantic result such as:

```range
String(literal: "hello")
```

That semantic result is settled before any backend runs.

- Derived protocol semantics also belong in the declaration graph.

```range

protocol Equatable {
    function ==(lhs: Self, rhs: Self): Bool
}

construct Point: Equatable {
    let x: Int
    let y: Int
}
```

The graph should represent that `Point` conforms to `Equatable` and inherits the protocol-carried macro semantics attached to that conformance.

For inherited protocols, carried macro semantics should compose through the
protocol graph rather than being reimplemented by each derived macro. For
example, `Hashable: Equatable` means a future protocol-carried ``
macro should synthesize only the hash witness, while the inherited
`Equatable` conformance realizes the protocol-carried `` macro for
the equality witness. Any current `` implementation that emits
equality directly is a bootstrap bridge until protocol-carried macro
realization handles inherited conformances.

## Notes

- The declaration graph is the right layer for protocol semantics, conformance realization, declaration-targeted macro carry, and similar declaration-to-declaration reasoning.
- The memory graph should consume declaration-graph results rather than re-resolving protocol and macro relationships itself.
- Backends should consume declaration-graph-derived semantic results rather than redefining literal compatibility or bridge meaning.
- The compiler's current dependency graph machinery can evolve toward this role, but the language model should be expressed in terms of declaration semantics rather than implementation-specific lookup tables.
