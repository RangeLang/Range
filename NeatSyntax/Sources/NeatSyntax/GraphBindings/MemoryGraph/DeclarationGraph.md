# Declaration Graph

## Definition

The declaration graph is Neat's static semantic graph of declarations and declaration-to-declaration relationships. It records what declarations exist, what they mean, and how they are connected before storage, ownership, or mutation reasoning begins.

## Role

The declaration graph is the compiler layer that resolves semantic structure such as protocols, conformances, requirements, satisfying declarations, attached macros, and literal bridge realization.

It exists between syntax and the memory graph:

- the AST records written source structure
- the declaration graph records resolved declaration semantics
- the memory graph records storage, ownership, aliasing, mutation, and derived dependencies

It also precedes backend adaptation:

- the declaration graph resolves what a program means in Neat
- a backend later adapts that semantic result to a target representation

## Mental Model

- The declaration graph is not a runtime graph. It is a compiler graph.
- The declaration graph is not the memory graph. It does not model ownership or storage.
- The declaration graph answers questions such as "what does this declaration conform to?" and "which initializer satisfies this requirement?"
- The memory graph answers different questions such as "who owns this storage?" and "what mutations or dependencies exist across this path?"
- Semantic features that depend on declaration relationships should be derived from the declaration graph rather than from ad hoc compiler tables.

## Properties

- Declarations appear as graph nodes.

```neat
construct Int { }
protocol ExpressableByIntLiteral { }
macro literal<T>: Attached<Init> { target, diagnostics in }
```

- Declaration relationships appear as graph edges.

```neat
construct Int: ExpressableByIntLiteral { }
```

This introduces a semantic conformance edge from `Int` to `ExpressableByIntLiteral`.

- Protocol requirements are first-class declaration facts.

```neat
protocol ExpressableByIntLiteral {
    #literal<IntLiteral>
    init(literal: IntLiteral)
}
```

The requirement itself is part of the graph, along with its attached macro semantics.

- Concrete declarations can satisfy protocol requirements.

```neat
construct Int: ExpressableByIntLiteral {
    init(literal: IntLiteral) { }
}
```

The graph records that this concrete initializer satisfies the protocol requirement.

- Attached macro carry should be derived from declaration relationships.

```neat
protocol ExpressableByIntLiteral {
    #literal<IntLiteral>
    init(literal: IntLiteral)
}
```

The `#literal<IntLiteral>` macro is carried by the requirement and becomes part of the realized semantics of any matching satisfying initializer.

- Literal acceptance should be derived from graph facts rather than destination tables.

```neat
construct Int: ExpressableByIntLiteral {
    init(literal: IntLiteral) { }
}
```

From the declaration graph, the compiler can derive that `Int` accepts `IntLiteral`.

- Default literal resolution should also be derived after declaration-graph realization.

If a literal has no contextual type, the semantic phase may choose a preferred destination such as an `@core` bridge. That is still part of Neat semantics, not backend behavior.

- The declaration graph precedes the memory graph.

```neat
construct User {
    state count: Int = 0
}
```

The compiler should know that `Int` is a valid declaration-level type before it reasons about `count` as owned mutable storage in the memory graph.

## Examples

- Literal bridge realization belongs in the declaration graph.

```neat
protocol ExpressableByStringLiteral {
    #literal<StringLiteral>
    init(literal: StringLiteral)
}

construct String: ExpressableByStringLiteral {
    init(literal: StringLiteral) { }
}
```

The relevant graph facts are:

- `String` conforms to `ExpressableByStringLiteral`
- the protocol has an initializer requirement
- that requirement carries `#literal<StringLiteral>`
- `String.init(literal:)` satisfies that requirement
- therefore `String` accepts `StringLiteral`

If source contains:

```neat
state title = "hello"
```

then the declaration graph and literal-resolution rules may derive a semantic result such as:

```neat
String(literal: "hello")
```

That semantic result is settled before any backend runs.

- Derived protocol semantics also belong in the declaration graph.

```neat
#equatable
protocol Equatable {
    function ==(lhs: Self, rhs: Self) -> Bool
}

construct Point: Equatable {
    value x: Int
    value y: Int
}
```

The graph should represent that `Point` conforms to `Equatable` and inherits the protocol-carried macro semantics attached to that conformance.

## Notes

- The declaration graph is the right layer for protocol semantics, conformance realization, attached macro carry, and similar declaration-to-declaration reasoning.
- The memory graph should consume declaration-graph results rather than re-resolving protocol and macro relationships itself.
- Backends should consume declaration-graph-derived semantic results rather than redefining literal compatibility or bridge meaning.
- The compiler's current dependency graph machinery can evolve toward this role, but the language model should be expressed in terms of declaration semantics rather than implementation-specific lookup tables.
