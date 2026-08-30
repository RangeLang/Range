# Range Milestones

This file defines the dependency order of major outcomes. [TODO.md](TODO.md)
owns the actionable checkboxes. Historical compiler timings, intermediate V1
phase designs, and completed migration evidence belong in the relevant
development handoff rather than becoming parallel roadmaps.

Range is defined first by executable coding constructs. Algebraic descriptions
are useful observations about those constructs, not a mathematical ontology
that the implementation must imitate.

## Current Direction — August 7, 2026

The accepted compiler remains the only bootstrap authority, and candidate plus
reproduction equality remains the promotion proof. Work proceeds through
compiler generations rather than requiring V1 to embody the final ontology:

```text
V1  retain typed semantic layers; measure and remove repeated function work
V2  place Composition, Delta, and Flow beneath those layers and prove equivalence
V3  delete only semantic or ABI authorities that V2 evidence makes redundant
```

The meta-model research vocabulary remains:

```text
Composition  identified ordered composition of identities
Delta        atomic product of identified changes
Flow         system that carries deltas through composition paths
Checkpoint   freeze-dried materialization and query indexes
```

The language forms are interpreted through the same coding model:

```text
construct = product
enum       = sum
property   = field
function   = transformation
macro      = environment
delta      = product
```

This does not flatten typed syntax, resolution, CFG, ownership, MIR, Behavior,
or target plotting in V1. The meta-model may eventually replace independently
maintained semantic authorities, but only after later-generation equivalence,
invalidation, and performance proofs.

## Milestone 0 — Preserve One Reproducible Compiler Authority

Status: complete and continuously enforced.

Outcome:

- The committed bootstrap LLVM, executable, and manifest are the only accepted
  compiler authority.
- The accepted compiler builds one candidate and that candidate builds one
  reproduction from the same source.
- Candidate/reproduction LLVM and executables must be byte-identical before an
  explicitly approved promotion.
- Focused gates prove only their own boundary; cache hits and generated
  artifacts are never reported as a broader fixed-point proof.

This invariant applies to every later milestone.

## Active compiler node — Graph-native Range Compiler

Status: active, pre-self-hosting.

`Language/` is the sole compiler source authority. The checked-in native
arm64 seed is transitional generation zero; Compiler A, LLVM emission, custom
entry builds, and the duplicate Compiler B project are retired.

Current checkpoint: replace statement-shaped `if`/`switch` lowering with one
condition-valued Application topology. Body exposes declaration and Application
views over one retained source body. Enum declarations carry the condition
relationship, all possible case successors materialize as `Execution.next`,
and execution follows only the case selected by the resolved value. A condition
reached inside a branch is another graph node, not nested-control ownership.

Exit proof:

- bridge candidate G1 contains the general non-empty singular capture rule and
  generic brace-form Application retention;
- condition syntax is supplied only through `@syntax`, with exhaustive enum
  validation and no source-name parser switch;
- Apple lowering consumes only the resulting execution relationships; and
- candidate and reproduction assembly, objects, executables, and focused output
  are byte-identical before the checked-in seed changes.

The frozen seed's current diagnostic remains evidence of generation zero, not a
reason to extend its statement-shaped conditional lowerer.

## Milestone 1 — Reduce Typed Function Reconstruction in V1

Status: historical Compiler A work; frozen unless reactivated through the
Compiler A escape valve.

Outcome:

- Preserve the existing typed compiler layers and language distinctions.
- Measure discovery, ABI probe, and final function emission passes on the same
  source bundle.
- Test only one bounded reconstruction or decomposition change at a time; do
  not optimize ABI probe repetition when the profile reports none.
- Compare cold emission and peak memory before retaining or expanding a change.

Exit proof:

- A focused profile reports typed-pass multiplicity and stage time.
- The focused compiler proofs preserve emitted behavior and the accepted
  caller/callee boundary behavior.
- A controlled profile proves a time or memory improvement before a retained
  product, decomposition, or memory-budget expansion becomes part of V1.

Current proof: splitting the 539-line LLVM operation dispatcher along its
existing operation families reduced the first controlled candidate-powered
cold profile from 445,031 ms to 404,994 ms. The moved branches passed the
Compiler V1 linked behavior gate, and their three compile times fell from
56,041 ms for the monolith to 16,231 ms combined. No bootstrap promotion is
part of this checkpoint. A second run took 401,424 ms with a 16,291 ms helper
sum and produced the same artifact hash; the post-split mean is 403,209 ms,
41,822 ms (9.4%) below the clean baseline.

That checkpoint was subsequently promoted by an explicit maintainer request:
candidate/reproduction LLVM and executables were byte-identical and accepted
bootstrap integrity passed. Iteration then continued from the promoted
authority. The first MIR-validation decomposition profile took 348,334 ms,
54,875 ms (13.6%) below the 403,209 ms prior mean, with the V1 linked behavior
gate passing. Its confirmation took 348,088 ms with the same artifact hash;
the 348,211 ms mean is 54,998 ms (13.6%) below the prior mean. This later
change is not yet another promotion checkpoint.

The next profile-selected expression-builder decomposition also passed the V1
linked behavior gate. Its first cold profile took 337,305 ms, 10,906 ms (3.1%)
below the 348,211 ms prior mean. Its confirmation took 337,415 ms with the same
artifact hash; the 337,360 ms mean is 10,851 ms (3.1%) below the prior mean.

Memory profiling now takes precedence over another source-size split. Coarse
RSS telemetry attributes roughly 3.13 GB of the development compiler's
high-water growth to function-behavior derivation. Splitting
`compilerBodyArenaResolveExpression` did not move that boundary and was
removed. Runtime string concatenation now adopts its first joined payload
instead of allocating and copying a duplicate; repeated profiles preserved
LLVM bytes and function-artifact identity, reduced average peak-footprint
readings, and showed neutral timing. This runtime checkpoint is not promoted;
the canonical proof remains open. Candidate-powered subphase measurement now
places the full increase in owned-return reconstruction: effect closure moved
current RSS by only about 0.3 MB, while owned-return summaries moved it from
1.687 GB to 4.819 GB in 38.6 seconds. The construct-identity arena accounts for
only 10.7 MB and allocator pressure relief released nothing, so the next slice
must account for live raw-buffer and transient-string ownership inside each
owned-return work item before changing the graph representation. Live-buffer
telemetry now shows raw buffers at 7.3 MB while transient allocations return to
zero after derivation. Corrected per-work-item attribution covered 381 items;
the largest was only 99,392 bytes (`functionRow=1945`, `instanceID=2916`). The
high-water is instead during function emission. Lowering-buffer attribution is
now complete: the full profile finished in 553,983 ms with 2,802,238,800 peak
transient bytes and a 5.41 GB peak footprint. Across 3,065 lowered functions,
memory derivation consumed 89.9 seconds, MIR construction 61.0 seconds, and
LLVM emission 93.7 seconds. Within emission, rendering consumed 49.5 seconds
and planning 26.3 seconds, while final buffer materialization consumed only
0.034 seconds. The largest current function is
`compilerCoreLLVMLowerHelperFunctionTypedObserved` (function ID 1982): its
4.209-second lowering spends 3.497 seconds in memory derivation and 3.023
seconds in owned-path validation, where live transient storage grows by about
1.96 GB. The next optimization slice is therefore owned-path validation
work-unit attribution and bounded allocation removal, not graph flattening or
final LLVM buffer materialization.

The first bounded experiment made returned-alias preparation an explicit
inline `CompilerOwnedPathTopology` prerequisite and removed its hidden second
invocation. Compiler V1 passed, and the controlled profile reduced aggregate
memory derivation from 89.9 to 82.6 seconds and peak transient allocation from
2.80 to 2.65 GB. The same single run increased the complete compilation from
553,983 to 560,804 ms and maximum resident memory from 3.75 to 4.00 GB. That is
a mixed result, not evidence that constructs are heap-backed: this four-scalar
construct lowers as an inline aggregate with caller stack storage. The
prototype was removed pending repeated comparison against a direct arena phase
invariant; witness tables are warranted only if the prerequisite becomes
variable-sized graph data.

The stronger follow-up now retains that prerequisite as an inline
`CompilerOwnedPathPreparation` with arena-issued and once-consumed generation
numbers. All four owned-path validation paths require the value, and the raw
returned-alias preparation has one producer. Compiler V1 passed. Its first
full retained profile completed in 547,671 ms, 6,312 ms below the restored
553,983 ms baseline; aggregate memory derivation fell from 89.9 to 81.3
seconds, peak transient allocation fell from 2.80 to 2.65 GB, and maximum
resident memory was effectively flat at 3.75 GB. In the former largest helper,
owned validation fell from 3.023 to 2.673 seconds and its complete memory stage
from 3.497 to 3.143 seconds. One confirmation profile remains before treating
the improvement as promotion-quality evidence.

Owned-path validation now exposes first-class nested telemetry rather than one
lossy phase interval. The Range-authored `CompilerProbe` token carries exact
function, instance, block, node, ordinal, and item context through the graph;
the profiling runtime supplies parent/depth identity, nanosecond timing,
operation deltas, resident snapshots, and allocation-event-driven local raw
and transient peaks. A full candidate workload completed in 724,644 ms with
311,479 balanced probe pairs, no malformed/open pairs, and no failed results.
The new attribution makes block evaluation the next bounded knot: 123.27 of
156.02 aggregate owned-validation seconds, alongside 119.20 million substring
operations over 10.12 TB of reported source bytes. Terminal handling is a
distant second at 19.21 seconds. This instrumented run is diagnostic evidence,
not the pending uninstrumented confirmation profile.

The semantic split then isolated repeated type-storage classification inside
local bindings, construct moves, optional branches, assignments, and return
transfer. `CompilerBodyArena` now memoizes transparent-storage bases,
opaque-representation status, and recursive tracked-storage status by its
arena-local type identity. Compiler V1 passes. On the same instrumented
candidate workload, total compilation fell from 1,122,239 to 484,553 ms,
maximum RSS from 3.23 to 2.04 GB, and peak footprint from 5.22 to 2.40 GB. The
trace retained 721,902 balanced probe pairs with no failures or malformed/open
records. Local binding fell from 73.10 to 0.43 aggregate seconds, construct
move from 70.37 to 0.30, optional branching from 37.32 to 0.06, assignment
from 32.05 to 0.14, and return transfer from 25.16 to 1.29. Block merge is now
the next bounded owned-validation knot with 955,116 substring calls and 2.33
aggregate seconds. No bootstrap promotion is part of this checkpoint.

The first CFG-substrate slice replaces the three loose predecessor buffers
consumed by owned-path validation with an arena-scoped
`CompilerControlFlowRelationships` product. Its predecessor adjacency stores
exact `cfgEdges` row identities; block selection, merge, and backedge checks
query those relationships and resolve their source block component from the
authoritative edge. Optional classification is now cached by arena-local type
identity. Compiler V1 passes. On the balanced profile, block merge fell from
2.33 to 1.17 aggregate seconds and its substring operations from 955,116 to
171,400; relationship construction itself consumed only 40.5 ms across 3,910
arenas. Maximum RSS fell from 2.04 to 1.81 GB, but total instrumented time rose
from 484,553 to 640,057 ms amid broad MIR/emitter variance and one 49.2-second
expression-resolution outlier. This proves the bounded relationship consumer,
not a whole-compiler speedup. The remaining merge slices must become one
canonical Optional declaration-identity relationship per source graph before
the CFG product is widened toward the shared Composition substrate.

## Milestone 2 — Establish Composition as the V2 Graph Substrate

Outcome:

- Core defines one minimal identified ordered Composition value.
- Identity remains stable across value revisions and remains distinct from a
  structural fingerprint used for lookup.
- Combining compositions creates another identified Range point that can be
  referenced by later compositions.
- Construct fields, enum cases, function access paths, properties, macro
  environments, and delta products are proven as typed Composition views.
- Many-to-many relationships are sets of identified composition anchors;
  n-ary compositions provide the same mechanism for hyperedges.
- Authored nesting is preserved. Flattening or associativity is introduced only
  by an explicit typed normalization law.

Exit proof:

- Focused fixtures query exact, nested, repeated, and structurally equal but
  identity-distinct compositions.
- The proof covers the representative construct, enum, property, function,
  macro, and delta forms without a second node/edge ontology.

## Milestone 3 — Make Flow Carry Delta Products

Outcome:

- Delta is an atomic product of identified changes, not the flow and not the
  act of traversal.
- Flow owns root, environment, frontier, ordered syntax-identity paths, and
  scheduling.
- A rooted walk unfolds the shared graph as a tree while retaining global
  identity sharing.
- Constructs carry field paths, enums carry alternative case paths, functions
  carry consumed/accessed/produced paths, and macros carry their available
  environment.
- Reducers observe a Flow frontier and propose a Delta; successful commit moves
  the accepted head, while failure leaves it unchanged.
- Disjoint observation/write products may be scheduled together. Conflicting
  products retain deterministic order or are re-derived from the new head.

Exit proof:

- Deterministic rooted traversal, atomic commit, stale-observation rejection,
  disjoint batching, conflict retry, and last-known-good preservation pass as
  executable Range behavior.

## Milestone 4 — Make Delta History Authoritative and Indexes Disposable

Outcome:

- The accepted head plus its immutable parent-linked Delta compositions are
  the durable authority.
- Current graph values and topology can be rebuilt by deterministic replay.
- Exact sequence, prefix, component-position, extension, and reverse-membership
  queries use revision-keyed derived indexes.
- Checkpoints and indexes can be deleted and rebuilt without changing graph
  meaning.
- Common two-to-four-component compositions may use measured inline physical
  storage while the language model remains `Array<Identity>`.

Exit proof:

- Deleting the compatibility checkpoint and indexes followed by replay
  reproduces their bytes and logical query results.
- Cold load, warm load, replay, delta application, lookup, invalidation
  frontier, compile time, and peak memory are measured on the same machine and
  source revision.

## Milestone 5 — Cut V2 Compiler Dependencies Over to Composition and Flow

Outcome:

- Functions retain the actual identity compositions they consume, access,
  produce, move, write, destroy, and require from their macro environment.
- Caller and callee share one call-boundary Composition; target plotting chooses
  a machine convention consistently at both ends.
- Compiler-wide ABI planning and separately reconstructed function-effect
  summaries disappear.
- Changed source invalidates the first changed composition prefix and only its
  reverse-composition closure.
- Cache lookup happens before body reconstruction. Cached state is a
  freeze-dried Composition checkpoint, never a second semantic graph.
- Compilation, target plotting, building/linking, and execution are distinct
  products.
- Superseded phase records, node/edge stores, numeric schemas, and legacy
  parser/lowering chains are deleted with their last supported consumers.

Exit proof:

- Focused ownership, enum payload, macro environment, call-boundary, aggregate
  return, runtime, cache invalidation, and rejection controls pass.
- Candidate and reproduction remain byte-identical.
- A changed compiler source demonstrates early reuse and a materially smaller
  reconstruction frontier than a cold build.

## Milestone 6 — Canonical Core Storage and Automatic Lifetimes

Outcome:

- String, Buffer, aggregate values, and Composition indexes have deterministic
  automatic cleanup across fallthrough, return, branch, loop, move, and alias
  boundaries.
- The compiler becomes the largest real consumer of canonical authored String
  and Buffer facilities.
- Dense buffers and structure-of-arrays remain available as private measured
  index implementations; compiler logic does not program anonymous numeric
  schemas directly.
- Raw runtime entry points disappear after their last accepted Core or
  compiler caller, leaving an explicit replaceable platform boundary.

This is no longer a prerequisite for beginning the graph machine. It proceeds
through and supports the Composition implementation.

## Milestone 7 — Complete the Usable Language and Driver

Outcome:

- The public CLI owns project discovery, source loading, diagnostics,
  compilation, target plotting, building, and executable output without
  exposing bootstrap mechanics.
- Constructs, enums, properties, functions, macros, generics, collections,
  ownership, and control flow share the same Composition/Flow model.
- Collection traversal uses intent-bearing operations such as `map`, `filter`,
  `each`, and `reduce`; Range does not introduce a `for` statement.
- Diagnostics identify stable syntax compositions and source provenance rather
  than anonymous rows or negative sentinels.

## Milestone 8 — Portability and Canonical Package Ownership

Outcome:

- Compiler, Core, Foundation, Runtime, Frameworks, Bootstrap, Website, and
  tooling ownership follows real dependency boundaries.
- macOS and Linux execute the same language and Composition/Flow fixtures.
- Platform calls and target conventions are explicit replaceable boundaries.
- A future non-LLVM target consumes the same target-independent Composition and
  Flow values rather than forking frontend semantics.

Repository path migration happens only when these ownership boundaries are
real; it is not an independent churn milestone.

## Immediate Order of Work

1. Define and prove the minimal Core `Composition` value and its identity/value
   invariant.
2. Encode representative construct, enum, property, function, macro, and Delta
   compositions without deleting the accepted graph path.
3. Extract Flow routing from the current Delta model and prove rooted ordered
   syntax-identity paths.
4. Make the append-only Delta head replay into disposable checkpoints and
   indexes.
5. Cut one function/call-boundary slice over to retained compositions and
   measure cold versus changed-source work.
6. Delete each superseded node/edge, phase-product, effect-summary, ABI-plan, or
   numeric-schema path with its final consumer.
7. Continue automatic lifetime, Core storage, runtime, driver, and portability
   work through the Composition model rather than as competing architectures.
