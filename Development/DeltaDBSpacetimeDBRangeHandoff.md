# DeltaDB + SpacetimeDB → Range persistent-graph handoff

**Date:** 2026-08-04  
**Status:** architecture handoff; no compiler cutover is implied by this document

## Decision in one sentence

Borrow DeltaDB's operation-level history and stable identity, borrow
SpacetimeDB's transactional executable state, and combine them into a local,
durable Range compiler graph.

This does **not** mean that Range becomes a database server, uses SQL, or
stores only edges.

## What we actually borrowed

### DeltaDB: history is made of operations

Zed's DeltaDB is explicitly organized around fine-grained deltas rather than
waiting for commits. Each operation has a stable identity and can be addressed
as the worktree evolves; the edit and the conversation that produced it stay
linked. See [Zed's DeltaDB announcement](https://zed.dev/blog/introducing-deltadb).

The Range translation is:

- a source edit, macro application, relationship insertion, replacement, or
  removal is a first-class operation;
- line numbers and table row positions are not semantic identity;
- nodes and edges receive stable identities, while their values can change;
- a compiler revision is a durable history point, not merely a newly emitted
  LLVM file;
- the same history can explain why a graph fact exists and which later facts it
  invalidates.

The conflict-free replicated worktree aspect of DeltaDB is a possible future
collaboration feature, not a prerequisite for the local compiler.

### SpacetimeDB: the program is the state machine

SpacetimeDB places the application module, schema, and mutation logic in one
database-hosted unit. Tables hold state, reducers are the sanctioned mutation
boundary, and views expose derived read-only state. Its documentation also
describes an in-memory state backed by a durable commit log and replay on
restart. See [key architecture](https://spacetimedb.com/docs/intro/key-architecture/),
[reducers](https://spacetimedb.com/docs/functions/reducers/), and the
[persistence/view model](https://spacetimedb.com/docs/intro/faq/).

The Range translation is:

- the Range compiler is the executable module over its own graph;
- a compiler phase is a typed reducer over a graph revision;
- a graph query is a read-only view, not an additional semantic authority;
- a phase either commits its delta or leaves the prior accepted revision
  untouched;
- durable execution state can be loaded into memory and replayed or resumed;
- Core syntax and relationship registrations are schema facts that the
  compiler can query, rather than hidden compiler-only tables.

SpacetimeDB's table guidance is especially relevant: organize physical storage
by access pattern, keep logical queries stable, and let indexes change without
changing the semantic query. See [tables and physical/logical independence](https://spacetimedb.com/docs/tables/).

### Delta Lake: a secondary persistence analogy

Delta Lake is a different project from Zed's DeltaDB, but it provides a useful
storage discipline: each version is an atomic set of actions applied to the
prior snapshot, while MVCC preserves consistent reader snapshots. Its Change
Data Feed exposes row-level inserts, deletes, and updates. See the
[Delta protocol](https://github.com/delta-io/delta/blob/master/PROTOCOL.md) and
[Change Data Feed](https://docs.delta.io/delta-change-data-feed/).

Range should borrow the snapshot/action/checkpoint discipline, not Delta
Lake's files, Parquet layout, or table semantics.

## Range's resulting model

The graph is one logical graph with physically specialized stores:

```text
NodeSpace
  stable NodeID
  value fingerprint
  typed payload or lazy payload reference

EdgeSpace
  stable EdgeID
  source NodeID
  target NodeID
  relationship identity
  cardinality and ordinal
  add / remove / replace operation

Indexes and views
  incoming edges
  outgoing edges
  one / optional / many / exact-N lanes
  Shape
  Usage
  Ownership
  Representation
```

The cardinality split is a storage and query decision, not a second semantic
graph. One subsystem may specialize edge indexes; another may specialize node
payload lookup. Both address the same stable identities.

The rule is:

> Nodes are stable facts. Edges are the mutable history of relationships
> between those facts.

This is why “only save edges” is too strong. Edge deltas should be the hot
incremental path, but source text, declarations, types, literals, and emitted
values still need node payloads or durable references.

## Compiler lifecycle

The compiler should evolve toward this reducer chain:

```text
File / Source delta
        ↓
Shape reducer       → Shape delta
        ↓
Usage reducer       → Usage delta
        ↓
Ownership reducer   → Ownership delta
        ↓
Representation reducer → Compiled delta
        ↓
Build               → linked artifact
        ↓
Run                 → execution result
```

Each reducer receives an accepted revision plus an input delta and returns a
new delta. The commit boundary covers the graph artifact and its execution
record together. A failed candidate records a typed diagnostic but does not
replace the last-known-good revision.

Compilation, building, and running remain distinct products:

- **compile** derives target-independent meaning and target LLVM text;
- **build** validates and links that compiled artifact with a target/runtime;
- **run** executes the linked artifact.

The persistent graph is the authority for meaning; LLVM remains one output
format until a later cutover proves a different emitter.

## Current Range checkpoint

The repository already has the beginning of this design:

- `range compile-graph` is an opt-in persistent-graph command;
- `scripts/range check-compiler-graph` proves source-set identity, cold
  insertion, unchanged reuse, edited replacement, and recovery without a new
  LLVM emission;
- `scripts/range check-shape` proves a separate source-local Shape artifact;
- the V1 execution record carries stable phase identities and before/after
  value fingerprints;
- `CompilerGraphDelta` already exposes `nodes` and `facts`, although the
  implementation is still backed by dense integer tables.

Relevant implementation surfaces are
[`scripts/compile-range-project`](../scripts/compile-range-project),
[`scripts/range`](../scripts/range), and
[`CompilerParsing.range`](../RangeCompiler/Sources/Compiler/Syntax/CompilerParsing.range).

These are transitional proofs, not permission to delete the accepted compiler
oracle yet.

## Implemented revision checkpoint

The bounded revision cutover is implemented without rewriting Body/CFG/MIR:

1. Graph `revision.tsv` schema v4 owns parent identity, File fingerprint,
   Source profile, canonical input, compiler identity, Source and syntax-fact
   digests, accepted phase values, node changes, edge changes, view digests,
   and accepted status. Shape retains the source-only v2 subset.
2. Graph revisions persist the node index and typed edge-delta stream. The V1
   execution record is materialized transiently from the revision only while
   invoking the compatibility `resume-v1` command; it is not cached.
3. `source.tsv` is removed as a parallel authority. Reuse validates the actual
   Source bundle against the digest and provenance in `revision.tsv`.
4. `syntax-facts.tsv` persists the validated typed Shape snapshot and its
   syntax and Shape fingerprints. Source provenance remains on the revision's
   Source-to-syntax edge, so structurally identical facts remain byte-identical
   across non-structural edits. Shape decodes and projects this artifact without
   opening or recapturing Source. A transient binding pairs the current Source
   value with the accepted syntax value before `resume-v1-facts` runs.
5. Focused cold, warm, unchanged, edited, failed-candidate, and recovery proofs
   cover revision, Source, syntax-fact and LLVM preservation, phase costs,
   Source-free Shape projection, and affected-view counts.

Compiler V1 also separates changing phase values from transitional identity
hash keys at the type level. Core `Identifier` remains the authored graph
identity. The four-way reconciler remains deferred until UUID-backed structural
identity equality can confirm hash-index matches.

Execution is now a transient candidate operation: success commits staged LLVM
and revision artifacts, while failure emits diagnostics without replacing the
accepted graph. A legacy execution record is consumed once when migrating a v2
cache and is removed after success.

## Next implementation slice

Extend the syntax-fact artifact from the complete typed Shape snapshot to the
full reloadable pre-link syntax tables. Behavior currently recaptures those
downstream-only tables from Source before macro linking; it should instead load
the accepted syntax facts, then persist its own product for Compile.

The first success criterion is not byte identity. It is deterministic revision
identity, correct before/after values, bounded invalidation, and preservation of
the last accepted graph after a failed candidate. Existing byte-parity and
fixed-point gates remain compatibility evidence while this authority is being
cut over.

## Explicit non-goals

- No network database or SQL layer.
- No generic untyped graph blob replacing every typed representation.
- No unconditional logging of every keystroke inside the compiler.
- No edge-only storage that loses node payloads.
- No CRDT implementation until collaborative compiler editing is an actual
  requirement.
- No deletion of the legacy compiler path before the corresponding V1 artifact
  has positive and negative durable proofs.

## Source references

- [Zed — Software Is Made Between Commits](https://zed.dev/blog/introducing-deltadb)
- [SpacetimeDB — Key Architecture](https://spacetimedb.com/docs/intro/key-architecture/)
- [SpacetimeDB — Reducers](https://spacetimedb.com/docs/functions/reducers/)
- [SpacetimeDB — FAQ](https://spacetimedb.com/docs/intro/faq/)
- [SpacetimeDB — Tables](https://spacetimedb.com/docs/tables/)
- [Delta Lake — Protocol](https://github.com/delta-io/delta/blob/master/PROTOCOL.md)
- [Delta Lake — Change Data Feed](https://docs.delta.io/delta-change-data-feed/)
