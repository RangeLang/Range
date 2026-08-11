# DeltaDB + SpacetimeDB → Range persistent-graph handoff

**Date:** 2026-08-07
**Status:** accepted direction; implementation proceeds in focused batches

## Decision in one sentence

Every graph value is an identified, ordered Composition of identities. Flow
carries atomic Delta products through those compositions. The accepted head
plus its immutable Delta history is durable authority; checkpoints and indexes
are disposable, freeze-dried materializations.

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
- compositions receive stable identities, while their ordered component values
  can change;
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
- a compiler reducer consumes a Flow frontier and proposes a Delta product;
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

The semantic graph has one primitive:

```range
construct Composition {
    let identity: Identity
    let components: Array<Identity>
}
```

An identity names a stable authored or derived occurrence. Its components are
the current ordered value at a revision. A structural fingerprint may index
equal component sequences, but it is disposable and never replaces identity.
Two occurrences may therefore have identical components and distinct identity
or provenance.

Combining compositions creates another identified Range point:

```text
AB  -> [A, B]
ABC -> [AB, C]
```

`AB` is simultaneously a value, the anchored relationship between `A` and
`B`, and a point that later compositions can use. Many-to-many relationships
are sets of such anchors. N-ary component arrays are identified hyperedges.
Nodes and edges are typed views of Composition, not separate semantic stores.

Ordered syntax-identity paths are compositions too:

```text
construct fields   [User, name] [User, age]
function accesses  [User, name, .count] [User, age, .birthdate]
enum alternatives  [queued, Message, View] [pending, Message, View]
```

The coding constructs remain primary. Algebraic descriptions summarize their
observable shape:

```text
construct = product
enum       = sum
property   = field
function   = transformation
macro      = environment
delta      = product
flow       = carrier of deltas
```

Exact-sequence, prefix, component-position, extension, and reverse-membership
indexes are revision-keyed physical accelerators. Dense buffers, tries,
row-major layouts, inline two-to-four-component storage, and spill storage are
implementation choices, not additional graph authorities.

## Delta contract

Delta is an identified, atomic product of change compositions. It identifies
its accepted parent, origin/environment, observations, writes, diagnostics, and
provenance. It does not own traversal paths or requirement/provision routing;
those belong to Flow.

```text
RangeGraphDelta
  identity
  parent revision
  origin / environment
  observations
  ordered change composition identities
  diagnostics

RangeGraphFlow
  identity
  root
  environment
  frontier
  ordered syntax-identity composition paths
```

Commit is atomic. Before accepting a delta, the graph validates its parent and
observations against the accepted head, then validates identities, composed
values, and diagnostics. Failure appends nothing and leaves the accepted head
unchanged. Disjoint Delta products may commute; overlapping observation/write
products retain deterministic order or are re-derived from the new head.

`RangeGraphCheckpoint` is a freeze-dried Composition materialization and query
index that can be discarded and rebuilt by replay. It is deliberately not a
second revision format.

## Compiler lifecycle

The compiler is not permanently organized as a global
Shape→Usage→Ownership→Representation phase ladder. Those names may remain as
temporary typed views while the cutover is proven. The durable lifecycle is:

```text
source Composition change
        ↓
Flow frontier
        ↓
local reducer observes compositions
        ↓
atomic Delta product
        ↓
accepted composition revision
        ↓
target plot → build/link → run
```

Constructs carry field compositions, enums carry alternative case/payload
compositions, functions carry the compositions they consume/access/produce,
and macros carry the environment in which identities are available. Each
reducer proposes a Delta product; it is not itself durable phase state.

Compilation, building, and running remain distinct products:

- **compile** derives target-independent meaning and target LLVM text;
- **build** validates and links that compiled artifact with a target/runtime;
- **run** executes the linked artifact.

The committed delta history is the authority for meaning. LLVM remains one
target plot until a later cutover proves a different target representation.

## Local graph interaction model

Bend and HVM demonstrate how global computation can emerge from small local
graph interactions. Range should borrow that locality, not HVM's ephemeral
destructive graph or any unproven confluence claim.

The Range interaction pair is a requirement composition meeting a provision
composition along Flow. A reducer observes the surrounding compositions and
proposes a Delta product that satisfies, refines, diagnoses, or propagates that
interaction. Disjoint products can run independently; shared observations or
writes create a deterministic commit conflict and require re-observation.

Duplication and erasure are also graph facts: fan-out, ownership, and unused
values should remain explicit relationships or changes rather than hidden
control flow in a phase object.

## Function and target vocabulary

- A function carries the actual compositions it consumes, accesses, produces,
  moves, writes, destroys, or requires from its macro environment; a parallel
  effect summary is transitional.
- Facts capture becomes Composition derivation: a reducer observes identified
  compositions and proposes a Delta product; it does not freeze semantic phase
  state.
- Function emission becomes function plotting for a concrete target.
- The compiler-wide ABI plan is transitional. Caller and callee should share a
  stable call-boundary identity whose target Shape is plotted consistently at
  both ends. The external machine calling convention remains a target boundary,
  not a compiler-wide semantic authority.
- `freeze` is reserved for producing a freeze-dried checkpoint or other
  rebuildable cache. Committing a delta is `commit`; deriving a live view is
  `replay`, `fold`, or `materialize`.

## Current Range checkpoint

The repository already has the beginning of this design:

- The compiler work is now explicitly layered. V1 keeps typed syntax,
  resolution, CFG, ownership, MIR, Behavior, and target plotting authoritative
  while reducing measured reconstruction. Composition/Delta/Flow is an
  isolated V2 research lane; it does not replace those layers merely because a
  derived index beats a linear scan.

- Core defines the minimal `Composition(identity:components:)` value, and the
  compatibility `RangeGraphTopology` exposes a Composition lane beside its
  transitional node/relationship views. `scripts/range check-composition`
  proves ordered identity components, two identity-distinct anchors with equal
  structure, recursive anchor composition, LLVM validation/linking, and exit
  `7` through the accepted compiler.
- `scripts/range benchmark-composition` is the isolated unindexed query
  baseline. It constructs the current direct-field relationship shape and the
  Composition path once, then performs the same 20,000,000
  origin/role/destination accesses from a runtime-anchored loop. Runs on
  2026-08-07 measured Composition at `0.992x` to `1.078x` the direct-field
  time. There is therefore no measured
  primitive-level speedup yet; indexes and physical layout must earn that
  claim.
- The first compiler-owned `CompilerCompositionExactIndex` now derives a
  disposable bucket-and-collision-chain view over flattened ordered identity
  words. Fingerprints narrow candidates but full ordered identity comparison
  remains authoritative. `scripts/range check-composition` proves order,
  duplicate anchors, misses, and rebuild equivalence. Across four five-sample
  runs over 64 graph values and 500,000 exact lookups, the indexed query took
  `0.159x` to `0.163x` the direct relationship scan and `0.135x` to `0.137x`
  the unindexed Composition scan at `-O0`.
- The attempted use of that index inside the active graph plotter was stopped
  before validation and removed. The compiler continues using its accepted
  identity lookup path; the index remains owned only by the isolated
  Composition proofs.
- The layered V1 profiler now separates ABI probe multiplicity from the broad
  discovery/emission passes. Full accepted-bootstrap and current-candidate
  profiles both observed zero ABI probe passes, 3,033 discovery-side direct
  effect products, and 3,033 final emissions. The candidate-powered run took
  536,701 ms, reached 12,451,119,104 bytes maximum resident memory and
  15,689,364,368 bytes peak footprint. This ruled out an ABI-probe cache and a
  complete retained arena as the next V1 move.
- The first bounded syntax-retention experiment has been completed and
  removed. `CompilerFunctionSyntaxProducts` retained flattened syntax nodes,
  edges, and parent links under a 262,144-word budget; 216 of 3,052 functions
  reused it. In alternating same-candidate, same-source controls, disabled
  runs took 437,508 ms and 437,921 ms while enabled runs took 439,300 ms and
  437,004 ms. The enabled mean was 437.5 ms slower (about 0.10%) and had no
  memory advantage, so the product did not earn its compiler complexity.
- The next V1 experiment starts from a clean post-removal baseline and targets
  the size of `compilerBodyLLVMEmitterProcessOperation`, which alone takes
  about 52--54 seconds to compile in the current compiler-source profile. Its
  operation-family decomposition must preserve the typed layers and show an
  attributable cold-time or memory improvement before it is retained.
- That decomposition has now earned retention. The clean candidate-powered
  baseline took 445,031 ms with 9,767,469,056 bytes maximum resident memory;
  compiling the 539-line dispatcher consumed 56,041 ms. Moving its existing
  branches into aggregate/storage, call/string, and scalar/control helpers
  preserved the Compiler V1 linked `7`/`8` results. The first post-split
  profile took 404,994 ms with 4,990,402,560 bytes maximum resident memory.
  Its three helper compile times totaled 16,231 ms, a 39,810 ms reduction that
  accounts for nearly all of the 40,037 ms total improvement. This is a V1
  structural compilation win, not a Composition flattening or cache claim.
- A confirmation profile took 401,424 ms and the helpers totaled 16,291 ms.
  The two post-split runs produced the same artifact SHA-256 and average
  403,209 ms, 41,822 ms (9.4%) below the 445,031 ms baseline. Maximum resident
  memory remained between 4,990,402,560 and 5,674,303,488 bytes, versus
  9,767,469,056 bytes before the split. The next measured structural target is
  `compilerBodyMIRValidationCode`, now the largest function at
  45,325--46,050 ms.
- The operation-dispatch checkpoint was explicitly promoted through the
  canonical two-build proof. Candidate and reproduction LLVM matched at
  `5ed288a4ed11823c3456cbcb093b4070c6a7a4551130a73d9aac681e46f8455a`,
  executables matched at
  `941d9cddad2d874c3cd9180062f66847aa0b73fc0b888a2c9275766d94c6b6a2`,
  and accepted-bootstrap integrity passed.
- Work continued from that accepted authority by decomposing the 608-line
  MIR validator into a 123-line coordinator over exact call/macro,
  aggregate/storage, and optional/string/control validation families. The
  Compiler V1 linked `7`/`8` proof passed. Its first cold profile took 348,334
  ms, 54,875 ms (13.6%) below the 403,209 ms prior mean; the coordinator took
  994 ms and the largest helper 2,106 ms, while the other helpers fell below
  the top-50 duration cutoff. A confirmation run took 348,088 ms and produced
  the identical artifact hash. The 348,211 ms two-run mean is 54,998 ms
  (13.6%) below the prior mean. The next profile-selected target is
  `compilerBodyMIRBuildExpression` at 13,551--13,582 ms, but it should be split
  only if its `CompilerBodyMIRValueResult` propagation admits exact semantic
  family boundaries.
- The expression builder admitted that split: scheduled and optional-join
  results remain in a 17-line coordinator, while exact basic/reference,
  application/call, and operator branches moved to helpers. Compiler V1
  passed with linked `7`/`8` results. The first profile took 337,305 ms,
  10,906 ms (3.1%) below the 348,211 ms prior mean; application and basic
  helpers took 1,460 ms and 1,012 ms, while operator and coordinator functions
  fell below the top-50 cutoff. The confirmation took 337,415 ms with the same
  artifact hash. The 337,360 ms mean is 10,851 ms (3.1%) below the prior mean.
  The next profile-selected target is `compilerBodyArenaResolveExpression` at
  11,523--11,535 ms. The validation and expression splits are post-promotion
  intermediate work and are not yet a new fixed-point checkpoint.
- The accepted LLVM and executable still match the promoted manifest hashes,
  but `scripts/range check-compiler-integrity` now stops at the expected
  `CompilerBodyMIR.range` input-hash mismatch because work continued after
  promotion. The latest validation/expression candidate has Compiler V1
  evidence only; run the canonical candidate/reproduction proof before any
  later promotion.
- Memory-first profiling now records maximum resident memory at each compiler
  phase and at 64 MiB function high-water increments. The controlled
  development run rose from 1,686,192,128 bytes after artifact candidates to
  4,819,648,512 bytes after function-behavior facts; emission later reached
  5,320,802,304 bytes. The dominant memory problem is therefore behavior
  derivation, not the 8.9 MB final LLVM text.
- An exact resolver-family decomposition passed Compiler V1 but left the
  behavior boundary unchanged at 4,820,418,560 bytes and total time effectively
  neutral at 341,832 ms, so it was removed. `stringConcat` now avoids its
  second transient payload allocation and copy by transferring the already
  tracked joined allocation to the Range string header. Repeated profiles
  emitted identical LLVM and the same `fa91789d...` artifact; average peak
  footprint improved while timing and maximum-resident readings remained
  noisy. The runtime change is unpromoted and currently stops build-plan
  integrity at the expected runtime-source hash mismatch.
- The generated-candidate experiment now isolates the memory increase.
  Current RSS was 1,687,027,712 bytes before behavior derivation,
  1,687,339,008 bytes after effect closure, and 4,819,025,920 bytes after
  owned-return summaries; that subphase took 38,575 ms. The process
  construct-identity arena reserved only 10,747,904 bytes, and a diagnostic
  macOS allocator-pressure-relief call released zero bytes. The remaining
  live-buffer profile now accounts for only 7,252,381 raw-buffer bytes after
  owned-return reconstruction, while transient allocations return to zero
  after derivation. Corrected per-work-item attribution covered 381 items; the
  largest was only 99,392 bytes (`functionRow=1945`, `instanceID=2916`). The
  high-water is instead during function emission: 2,852,655,776 transient
  bytes globally, with the largest observed function increment at 893,450,800
  bytes in `compilerCoreLLVMLowerHelperFunctionTypedObserved` (function ID
  1975). The remaining work is its lowering-buffer retention and repeated-call
  allocation pattern, not owned-return reset semantics.
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
6. Each accepted graph revision is also appended under `deltas/<identity>.tsv`
   with its parent and deterministic ordinal. `delta-head.tsv` advances
   atomically after the compiled output and compatibility `revision.tsv`
   checkpoint are ready. Warm reuse and failed candidates do not append; an
   edited child retains its parent record byte-for-byte. Rebuilding a missing
   checkpoint by replaying this chain remains the next persistence cutover.

Compiler V1 also separates changing phase values from transitional identity
hash keys at the type level. Core `Identity` remains the authored graph
identity. The four-way reconciler remains deferred until UUID-backed structural
identity equality can confirm hash-index matches.

Execution is now a transient candidate operation: success commits staged LLVM
and revision artifacts, while failure emits diagnostics without replacing the
accepted graph. A legacy execution record is consumed once when migrating a v2
cache and is removed after success.

## Batched implementation

### Batch 1: authoritative delta contract

- Core `RangeGraphDelta` owns a stable identity, parent revision, versioned
  observations, ordered changes, diagnostics, and origin.
- Core `RangeGraphCheckpoint` makes the derived cache boundary explicit.
- No persistence format or compiler ABI behavior changes in this batch.

### Batch 2: remove semantic freezing vocabulary

- Rename body-memory build/freeze operations around the facts they derive.
- Replace `isFrozen` control flow with an explicit availability state for the
  transitional call-boundary data, without changing behavior.
- Prove the rename/state cut mechanically before changing representation.

### Batch 3: commit/replay persistence

- Make the accepted head and append-only ordered delta records authoritative.
- Rebuild `revision.tsv`-style topology and indexes as revision-keyed
  checkpoints; prove replay equivalence and last-known-good preservation.

### Batch 4: shared call boundaries

- Introduce stable call-boundary graph identities and target Shape facts.
- Plot caller and callee from the same boundary and retire the global ABI
  reconciliation plan incrementally, with focused direct/indirect/foreign-call
  proofs.

### Batch 5: local interaction scheduling

- Represent requirement/provision interactions and their observation/write
  sets explicitly.
- Batch disjoint deltas; reject stale overlapping deltas deterministically.

## Previous implementation slice

The earlier handoff proposed extending the syntax-fact artifact to full
reloadable pre-link syntax tables. That remains useful checkpoint work, but it
must not turn the cached tables into authority. Resume it only as part of the
commit/replay persistence batch above.

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
- [Bend](https://github.com/HigherOrderCO/Bend)
- [HVM2 paper](https://github.com/HigherOrderCO/HVM/blob/main/paper/HVM2.pdf)
- [Delta Lake — Protocol](https://github.com/delta-io/delta/blob/master/PROTOCOL.md)
- [Delta Lake — Change Data Feed](https://docs.delta.io/delta-change-data-feed/)
