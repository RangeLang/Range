# Syntactic Graph vs Semantic Graph

Syntax records the written shape.

Semantics records what the program means after declarations, macros, storage roles, requirements, and applications have been connected.

## Feature

Range treats the semantic graph as the durable compiler surface.

The parser can tell that two nodes are next to each other. The declaration graph can tell whether that relation matters.

## Example

```range
construct Editor {
  state document: Document
  binding selection: Selection

  derived title: String {
    return document.title
  }

  function rename(title: String) {
    document.title = title
  }
}
```

The syntax graph sees a construct body with properties and functions.

The semantic graph sees storage, live binding, derived dependency, mutation, and callable application boundaries.

## Reason

Compiler work gets weaker when every phase rebuilds meaning from raw syntax.

Range's direction is the opposite: parse the source, expand macro-owned syntax, then keep pulling language facts into graph-owned relations.

That is why declaration facts, application facts, future memory facts, and future reactivity facts should stay connected instead of becoming separate lookup tables.

The syntax graph is regular because grammar is regular.

The semantic graph is bent because meaning is not evenly spaced.
