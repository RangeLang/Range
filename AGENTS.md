# Guidance

George wants one compilation entry point: build the graph, materialize nodes,
apply macros, resolve dependencies. Range defines types and capabilities;
C implements mechanisms and explicit primitives, without hardcoded concrete types.

- Reuse the language's constructs and relationships. Use `Array<T>` for collections.
- Each attached macro declares one target type; its name and target type select
  the declaration. `#field` accesses that application's target fields directly.
- Distinguish implemented behavior, accepted design, and proposals. Explain choices
  plainly with Range examples; report verification and remaining failures briefly.
- Report missing declarations, unimplemented behavior, and remaining C shortcuts.
  Do not invent definitions or hide gaps to make compilation appear successful.
- This is the sole repository guidance file. Keep it high-level; use source and
  tests for current behavior. Do not add duplicate READMEs, handoffs, or status docs.
- Deferred material and saved benchmarks are historical references, not evidence
  of current compiler support or performance.
