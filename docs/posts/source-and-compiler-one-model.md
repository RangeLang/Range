# Source And Compiler One Model

Core types, macros, and markers point toward the same compiler surface.

## Observation

The compiler does not need a private concept for every language feature.

If core types describe the language world, macros consume typed compiler views, and markers project graph metadata, then source and compiler can share one model.

```neat
@syntax
construct Construct {
    let name: Identifier
    let lets: [Let]
    let functions: [Function.Declaration]
    let comments: [Comment]
}

marker namespace(): Construct -> Namespace {
    Namespace(
        name: target.name,
        functions: target.functions,
        description: target.comments.description
    )
}

#namespace
// Basic numeric helpers exposed through Math.
construct Math {
    function clamp(_ value: Int, min: Int, max: Int) -> Int
}
```

The comment is source.

The construct is source.

The marker receives a compiler view of that source.

The returned `Namespace` is graph data.

```text
source
  comment
  construct
  marker

compiler graph
  Construct view
  Comment view
  Namespace projection
```

## Shape

The useful stage is not raw syntax scraping. It is projection.

```text
parse source
collect declarations
build declaration graph
project typed graph views
evaluate markers
expand macros
validate
lower
```

Macros and markers can still ask for source-like access when they need it, but the default path is typed:

```neat
target.name
target.functions
target.comments
target.source.range
```

That gives Neat a Tree-sitter-like retrieval surface without making text retrieval the source of truth.

## Reason

This removes the split between compiler-only facts and source-only facts.

The source says the program. The graph exposes the program. Markers and macros move data through that graph with ordinary typed concepts.

That is where more abstract compiler features can be added without adding one private compiler path per feature.
