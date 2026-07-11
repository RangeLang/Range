# Range Compiler Design Direction

Status: agreed architectural direction  
Date: 2026-07-10  
Audience: agents and contributors continuing the Range-authored compiler

## Purpose And Authority

This document consolidates the compiler and language-design direction agreed
while reviewing the `main`, `design`, and `development` branches, the
self-hosting work, and the TypeScript 7 native compiler.

It is an architecture document, not a claim that every layer already exists.
Use the live `development` branch as the implementation source of truth and
this document as the direction in which that implementation should converge.

For the current compiler port:

- preserve the working self-hosting fixed point;
- put new compiler semantics in Range-authored code;
- treat Stage 0 as frozen for language policy but movable for the smallest
  reusable runtime, ABI, lowering, linking, or validation substrate needed to
  unblock Stage 1;
- do not create a parallel Swift semantic compiler;
- do not return to the obsolete external chunk protocol described in
  `GPT56RangeSelfHostingHandoff.md`.

The chunk-specific status in that handoff was superseded by development commit
`3a309a8d` (`Switch LLVM compilation to direct parsing and threaded
temporaries`).

### Document precedence

| Source | Authority now |
| --- | --- |
| Live `development` branch and passing gates | Implementation truth |
| This document | Architecture and next execution direction |
| `RangeAuthoredCompilerPlan.md` | Historical route map; its eager function-body Slice 1 is superseded by span-backed lazy bodies plus caching |
| `RangeSelfHostingBootstrapSubstratePlan.md` | Historical diagnosis and reusable-substrate reference; its chunk-preservation and buffer-first execution phases are superseded by `3a309a8d` |
| `GPT56RangeSelfHostingHandoff.md` | Historical operational snapshot; its chunk instructions must not be resumed |
| `design` branch notes | Design evidence to adapt, not an implementation checklist |

An agent taking action now should read **Decisions In One Page**, **Current
Development Proof**, and **Immediate Recommended Slice For The Next Agent**
before following older checklist items.

## Decisions In One Page

1. **Compiler names the complete system**, from source loading and lexing
   through plotting, semantic derivation, lowering, and emission. There is no
   separate stage named “Compiler” after Plotter.
2. The high-level path is:

   ```text
   SourceStore
   -> Lexer
   -> Parser
   -> authored AST
   -> Plotter
   -> authored syntax graph
   -> declared syntax rewrites and macro graph deltas
   -> semantic graph views
   -> memory and reactivity derivations
   -> per-function IR
   -> backend lowering
   -> emission
   ```

3. The AST remains the authoritative compact definition of what was authored.
   The abstract syntax graph does not replace it; the graph is derived from it
   and connects syntax to ownership, declarations, applications, macros,
   types, memory, reactivity, IR, and provenance.
4. The stage between Parser and graph-aware compilation is called **Plotter**.
   It plots authored syntax into graph facts. It does not type-check, resolve
   names, execute macros, or lower LLVM.
5. The structural reader remains tiny. The preferred recursive shape is:

   ```text
   annotation* name (arguments)? { members* }
   ```

6. A thing owns its ordered members. An annotation is an application of a
   macro value to the thing; it is accessible from the thing but is not a
   member owned by the thing.
7. Macros and annotations are compile-time values and phase-scoped graph
   capabilities. `@graph` may grant a read-only graph query view; `@self` may
   grant access to the authored target syntax.
8. Protocols are not a separate future compiler mechanism. Their durable
   meaning is a macro-backed set of graph-validated requirements plus carried
   behavior. A `protocol` spelling may remain Foundation sugar.
9. Do **not** migrate to “everything is a macro” yet. Test that model inside
   the Range-authored compiler and Foundation first. Preserve explicit
   typed syntax nodes while the experiment is evaluated.
10. Physically, the graph must use dense typed stores, integer identities,
    interned strings, source spans, immutable snapshots, and small worker-local
    overlays. It must not be a heap of generic node objects and stringly typed
    edges.
11. Parallel work is divided by files, declarations, dependency components,
    macro applications, and functions—not arbitrary byte or gigabyte chunks.
12. Shared authored state is immutable. Workers own their mutable caches and
    return deterministic `GraphDelta` values. One bounded scheduler controls
    both concurrency and outstanding memory.
13. Incrementality is based on stable identities, explicit read sets, and
    separate hashes for source, public graph shape, macro dependencies, ABI,
    and function bodies.
14. The generic graph is not the final backend IR. Each function receives a
    specialized typed IR/CFG/SSA representation before LLVM emission.
15. Range does not adopt ARC, garbage collection, implicit reference counting,
    or another runtime ownership policy as its language memory model. The
    memory graph derives storage identity, ownership, borrowing, aliasing,
    mutation, escape, region, and lifetime facts; typed IR and lowering realize
    those decisions explicitly.

The narrow self-hosting proof path is:

```text
typed AST subset
-> Plotter
-> settled declaration/application facts
-> MemoryGraph v0
-> typed per-function IR
-> fixed-layout LLVM
```

This path is a closed proof over already-settled syntax and meaning. It is not
permission for memory analysis to guess unresolved semantics.

## Terminology

### Compiler

The complete dependency graph of compilation services and artifacts:

```text
inputs -> source -> syntax -> graph -> meaning -> IR -> artifact
```

Individual parts should use specific names such as `Lexer`, `Parser`,
`Plotter`, `MacroRuntime`, `SemanticDeriver`, `Lowerer`, and `Emitter`.

### AST

The authoritative compact record of authored syntax, not semantically settled
truth.

The AST may contain structural nodes such as raw statements and flat operator
runs. Declared syntax rewriting can derive a normalized syntax form while
retaining the authored AST and provenance.

### Plotter

The component that assigns stable structural identities and derives graph
facts from the AST. Its output is an authored graph delta, not a finished
semantic program.

### Program Graph

One canonical graph substrate containing facts from all phases. Declaration,
application, memory, and reactivity graphs are typed views or enrichment
layers over that root, not peer copies of the program.

### Graph Delta

A deterministic, bounded collection of nodes, edges, diagnostics, provenance,
and dependency reads produced by one task. Deltas are sorted and committed in
stable order.

## Structural Reader And Parser Boundary

The lexer cannot disappear: it is the base reader over source bytes and spans.
The parser should remain structural and independent from semantic resolution.

The reader may know:

- lexical categories and punctuation;
- source spans and balanced delimiters;
- annotations and argument clauses;
- blocks and statement boundaries;
- raw statements;
- flat expression runs;
- string quoting and escape rules.

The reader should not know:

- declaration lookup;
- type compatibility;
- macro realization;
- protocol or requirement satisfaction;
- operator meaning beyond preserving an operator run;
- memory, ownership, or backend rules.

Foundation declarations may later fold flat operator runs, match declared
surface patterns, and derive normalized syntax. Those are derivations, not
parser grammar extensions.

The parser must be independently runnable per source file and must never need
semantic resolver callbacks. This is necessary for deterministic caching,
parallel parsing, alternate Foundations, and self-hosting.

The default lexer interface should be a pull cursor over immutable source
spans. Do not materialize one project-wide token array. A file may retain a
compact token index when an editor or incremental parser benefits from it, but
tokens should reference source slices rather than own copied text.

## AST And Plotter Boundary

The AST should preserve:

- `FileID` and source span;
- syntax kind;
- ordered child roles;
- authored annotations;
- raw or flat authored forms where meaning has not been declared yet;
- enough declaration path facts to compute a stable identity later.

Plotter should derive:

- stable `NodeID` values for declarations and other graph-worthy syntax;
- `contains` and ordered `owns(role, ordinal)` edges;
- annotation application identities;
- annotation name references and `appliesTo` structural edges;
- source and provenance edges;
- declaration/application facet identities;
- a deterministic public-shape fingerprint;
- a `GraphDelta` scoped to a file or declaration.

Plotter should not:

- mutate the AST;
- discard the authored form;
- infer types or effects;
- execute macros;
- lower directly to LLVM;
- create token-level graph nodes for punctuation with no stable semantic role.

A later declaration/name resolver adds `resolvedBy` after macro declarations
are indexed. Plotter must not perform that resolution opportunistically.

## Ownership: Annotations, Things, And Members

The core shape is:

```text
annotation
thing {
    members
}
```

Its graph interpretation is:

```text
Annotation.Application --resolvedBy--> Macro.Declaration
        |
    appliesTo
        v
      Thing
        |
  owns(role, ordinal)
        v
      Member
```

Rules:

- `Thing` owns its ordered members.
- An annotation occurrence has source identity and provenance, but it is not
  an owned member of the target.
- The source/revision store owns the annotation application's storage lifetime.
  The target Thing only participates through `appliesTo` and effective-context
  relations.
- A macro declaration can be globally indexed; each annotation application is
  a local, source-located value.
- Parent-provided access is represented by explicit relations such as
  `carriedBy`, `inheritedFrom`, `effectiveOn`, or `grantsCapability`.
- Never implement parent behavior through repeated ambient ancestor scanning.
- Inverse views project the same edge; they do not duplicate relationship
  storage in both objects.

The effective annotation/capability environment should be interned as a
`ContextID`. A child reuses its parent context unless an annotation changes the
available capabilities. This makes “what is accessible here?” a compact graph
fact instead of a copied macro list or repeated ancestor traversal.

## Macros And Annotations As Values

A macro is a typed compile-time value with:

- a declaration identity;
- a target surface;
- an execution phase;
- explicit arguments;
- an allowed capability set;
- an explicit graph read set;
- a deterministic graph delta result.

Annotations are macro applications. Their role is both transformation and
capability gating.

### `@graph`

`@graph` should be expressible as a Foundation or user macro rather than a
large core special case. It grants a phase-appropriate, read-only graph query
view to code within the annotated target.

The compiler runtime issues the underlying capability. A macro may request or
project an allowed view, but it cannot mint capabilities, widen its authority,
or mutate committed graph storage.

The view must be selective:

- declaration macros receive declaration-facing facts;
- application macros receive application-facing facts;
- body macros receive syntax/body facts;
- no macro receives unrestricted mutable access to the compiler graph.

### `@self`

`@self` exposes the authored target identity and syntax view. It permits code
to inspect what was written without confusing authored syntax with settled
semantics.

### Macro execution contract

Compile-time macro execution must be:

- deterministic;
- terminating;
- I/O-free;
- closed over driver-provided inputs and a pinned Foundation;
- side-effect-free against committed graph storage;
- expressed as a returned delta plus diagnostics and read dependencies.

Host file and project I/O belongs to the driver and `SourceStore`, not inside
the compile-time runtime.

## Protocols Become Requirement Macros

The future language model should not maintain protocols and macros as two
independent mechanisms.

A protocol is fundamentally:

- a named collection of graph requirements;
- a validator over a target graph surface;
- optional carried macro behavior;
- explicit derived `satisfiesRequirement` facts.

Therefore:

- represent protocol meaning through a requirement macro value;
- allow `protocol` syntax to remain as Foundation-provided sugar if useful;
- validate requirements against declaration/application graph facts;
- record requirement satisfaction and carried behavior as explicit edges;
- keep runtime dispatch or witness representation as a separate lowering
  question, not proof that protocols need a separate front-end engine.

Existing Swift-hosted protocol machinery is migration compatibility, not the
target architecture. Do not add a second Range-authored protocol subsystem.

## “Everything Is A Macro” Is An Experiment, Not A Commitment

The design branch demonstrates that declared syntax and macro-carried meaning
can replace many compiler special cases. That direction is valuable, but the
complete “everything is a macro” model should first be tested in the native
Range compiler.

Until that experiment proves itself:

- keep the frozen structural reader;
- keep explicit authoritative AST node definitions;
- express new high-level behavior through macros where it is natural;
- avoid converting essential compiler invariants into interpreted macro code;
- measure compile time, memory, diagnostics, determinism, and debuggability;
- require a simpler typed representation before moving more meaning into the
  macro runtime.

## One Graph Root, Progressively Enriched Views

Use one canonical root substrate with these logical layers:

```text
AuthoredSyntaxGraph
        |
        v
DeclarationGraph
        |
        v
Realization / MacroGraph
        |
        v
ApplicationGraph
        |
        v
MemoryGraph
        |
        v
ReactivityGraph
```

These are views and derivation layers, not independently rebuilt worlds.

### Authored syntax facts

- source files and spans;
- syntax identities;
- containment and ordered ownership;
- annotations and arguments;
- authored/normalized provenance.

### Declaration facts

- what declarations exist;
- qualified identity and containment;
- declared members, types, signatures, and facets;
- requirements and satisfaction;
- macro declarations and carried macro relations.

### Application facts

- references and resolution;
- calls and construction applications;
- local scopes and use-site validation;
- dependency, alias, and mutation observations.

### Memory facts

- storage identity;
- owns, stores, borrows, aliases, mutates, and escapes;
- region and lifetime constraints;
- representation decisions after semantic settlement.

The language goal is native C/Rust-class layout and lifetime behavior without
forcing users to manually restate graph facts as routine ownership ceremony.
The compiler should derive the common case from the memory graph and require an
explicit annotation only when intent is genuinely ambiguous. This remains a
performance hypothesis until measured against representative C and Rust
programs.

### Memory model proof boundary

The memory graph is not a late optimization pass and must not be replaced by a
runtime ownership convention. A narrow `MemoryGraph v0` must be proven during
self-hosting as soon as stable typed identity and structural Plotter facts
exist.

For its initial supported subset, the graph must derive at least:

- storage identity and containing region;
- ownership and storage relations;
- read-only borrows and unique mutable access;
- alias and mutation observations;
- escape or non-escape from the declaring function;
- representation and destruction/transfer points.

The first proof uses a statically known construct with primitive fields, a
local value, and a read-only function application. The expected decision is a
fixed value layout with local non-escaping storage. Its emitted LLVM must not
use the linked name-keyed construct runtime and must not allocate the local
value on the heap.

ARC, garbage collection, implicit reference counting, or a universal heap
object model are explicitly rejected as substitutes for this derivation. A
stack slot, caller-owned result, explicit heap allocation, region allocation,
or destruction point may be selected by lowering after the graph establishes
the required facts; none of those mechanisms defines source-language meaning.

### Reactivity facts

- observes;
- invalidates;
- recomputes;
- dependency propagation and incremental scheduling.

Each later layer derives from earlier facts and retains provenance. No layer
reparses rendered strings or rebuilds a parallel semantic truth.

## Physical Representation

The logical graph can be rich while the physical representation remains close
to native C/Rust performance.

Use typed integer identities:

```text
RevisionID
SourceID
SourceSnapshotID
FileID
StringID
SyntaxID
NodeID
EdgeID
MacroID
ContextID
TypeID
FunctionID
IRValueID
```

Use dense, kind-specific stores:

- struct-of-arrays or compact typed tables for hot node families;
- contiguous adjacency ranges for common edge kinds;
- integer role and kind tags rather than relationship strings;
- interned identifiers, paths, labels, and type names;
- source slices `(FileID, start, end)` instead of copied token strings;
- per-file or per-revision arenas for authored syntax;
- per-task arenas for temporary derivations;
- explicit snapshot/reference lifetimes and revision reclamation.

Compiler implementation arenas or scratch buffers are permitted only as
bounded storage for already-owned compiler tasks. They are not Range's language
ownership model and must not hide missing memory-graph facts in emitted
programs.

Do not use one generic heap graph representation in hot loops. The API may
present a uniform graph view while the implementation dispatches to typed
stores.

### Source storage

The current low-memory self-hosting change proves the right basic ownership
shape:

- retain one original source backing store;
- keep declarations as spans into it;
- do not eagerly encode every function body;
- parse only bodies demanded by reachability/lowering.

Generalize this into:

```text
SourceStore
  SourceSnapshot
    FileTable[FileID] -> path, role, bundle range, line map, content hash
    immutable bytes
```

The current bundled source may remain a compact transport representation, but
the permanent model must recover `FileID` and file-local spans for diagnostics,
incremental reuse, and stable identity.

### Precompiled Foundation image

Compile the pinned Foundation once into a `FoundationImage` keyed by Foundation
source hash, compiler/schema version, target, and relevant compilation options.
It should contain direct lookup tables for:

- declared syntax patterns;
- operator levels;
- macro declarations and target surfaces;
- requirement macros;
- builtin declarations and runtime imports;
- schema validation rules.

Normal project compilation should not rediscover or reinterpret unchanged
Foundation declarations repeatedly.

## Concurrency And Determinism

Range already intends to provide Go-like structured concurrency with a
C/Rust-class memory model. TypeScript 7 validates that direction, but its most
useful compiler lesson is where ownership boundaries are placed.

### Work units

Use semantic work units:

- one source/file parse;
- one file or declaration plot;
- one macro application;
- one dependency strongly connected component;
- one function type/effect analysis;
- one function IR build;
- one module/object emission;
- one project in a dependency DAG.

Do not divide work by arbitrary byte counts or gigabyte chunks.

### Ownership model

- Authored source, AST snapshots, Foundation data, and committed graph facts
  are immutable and shared.
- Each worker owns its scratch arena, semantic caches, and uncommitted delta.
- A raw worker-local `TypeID` or mutable semantic handle never crosses into
  another worker context without canonicalization.
- Results cross boundaries as stable IDs, diagnostics, hashes, and graph
  deltas.
- Deltas are committed in deterministic `FileID`/`NodeID`/phase order.

### Scheduler

Use one bounded, memory-aware compiler scheduler with:

- a global concurrency limit;
- a global outstanding-memory budget;
- backpressure when queued deltas or IR exceed that budget;
- cancellation and request-scoped cleanup;
- phase priorities for interactive/LSP requests;
- a single-threaded deterministic/debug mode.

Whether the executor uses stable fixed partitions, work stealing, or a hybrid
is benchmark-driven. The invariant is deterministic ownership/commit plus a
bounded live set, not one scheduling algorithm.

Avoid nested `builder × checker × macro × emitter` pools whose counts multiply
peak memory.

Do not parallelize the current 10.10 GB compiler representation merely because
the runtime can. First make the per-task live set small and owned.

## Incremental Compilation

Track different kinds of change separately:

```text
SourceHash
AuthoredShapeHash
PublicShapeGraphHash
MacroCapabilityHash
MacroReadSetHash
BodySyntaxHash
BodyIRHash
ABIHash
FoundationHash
```

Suggested invalidation rules:

- source hash changed -> re-lex and reparse that file;
- authored shape changed -> replot affected declarations;
- public graph shape changed -> invalidate semantic dependents;
- macro read-set input changed -> rerun only observing macro applications;
- function body changed without ABI change -> reanalyze/re-emit that function
  and direct body dependents;
- ABI/public signature changed -> invalidate reverse dependency closure;
- Foundation hash changed -> select the appropriate broader invalidation
  boundary.

Cache immutable syntax snapshots by parse options, file identity, and content
hash. Track shared snapshot reachability across projects and editor requests,
then reclaim snapshots at explicit revision/request boundaries. This is
compiler-cache reclamation, not emitted-program memory semantics.

Stable declaration identity should be derived from declaration path facts
(container chain, kind, name, and an overload discriminator based on declared
signature shape such as labels, type shape, and generic arity). Body content is
excluded so an implementation edit preserves declaration identity. Function
bodies can initially invalidate at body granularity. Transient edit identity
must never influence emitted output.

## Semantic Analysis

Semantic analysis should consume graph facts, not parser callbacks or rendered
summaries.

Use:

- a scope graph for name visibility and resolution;
- explicit declaration and application edges;
- per-function or per-SCC type/effect contexts;
- canonical shared type identities only at context boundaries;
- diagnostics carrying authored spans and derivation provenance;
- typed query APIs over the root graph.

Complete memory and reactivity analysis comes after semantic settlement. The
early `MemoryGraph v0` proof runs only on a deliberately closed subset whose
declaration, type, member-layout, and call facts are already settled. It must
fail closed rather than guess unresolved meaning. Neither form belongs inside
the parser or a generic macro interpreter.

## Function IR And Emission

Do not lower the generic graph directly to textual LLVM.

For each reachable function:

1. select settled semantic nodes and MemoryGraph storage/lifetime decisions;
2. build typed high-level IR;
3. build control-flow blocks;
4. lower to SSA or another compact target-neutral mid-level IR;
5. validate IR invariants;
6. lower to LLVM records;
7. serialize LLVM only at the final boundary.

IR and backend lowering realize MemoryGraph decisions. They may not invent an
ARC, garbage-collected, implicit-refcount, or universal heap fallback when the
graph has not established storage and lifetime facts.

Per-function IR provides the natural unit for:

- caching;
- parallelism;
- memory reclamation;
- optimization;
- deterministic temporary numbering;
- object-level emission and linking.

Global and temporary identities must come from deterministic allocation ranges
or stable merge-time renumbering, never source-string offsets used as accidental
IDs.

## TypeScript 7 Lessons To Mirror

TypeScript 7 is a faithful native Go port rather than a clean-slate compiler
redesign. Its reported speed comes from native execution, shared-memory
parallelism, deterministic work partitioning, and focused allocation/caching
changes.

Mirror:

- per-file parsing, binding, and emission;
- deterministic fixed worker ownership;
- shared immutable syntax with worker-local semantic caches;
- content-addressed parse snapshots;
- dependency-DAG project scheduling;
- signature-based incremental invalidation;
- bounded worker controls and explicit single-thread mode;
- compatibility/parity gates during the port.

Do not copy:

- duplicated whole-program checker worlds;
- pointer-heavy AST and monolithic checker design;
- order-dependent results when worker count changes;
- nested pools that multiply memory;
- Go as a requirement—the Range runtime is intended to provide the substrate
  directly.

Official references:

- [Announcing TypeScript 7.0](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/)
- [Why Go? — Anders Hejlsberg](https://github.com/microsoft/typescript-go/discussions/411)
- [TypeScript checker pool](https://github.com/microsoft/typescript-go/blob/main/internal/compiler/checkerpool.go)
- [TypeScript parse cache](https://github.com/microsoft/typescript-go/blob/main/internal/project/parsecache.go)
- [TypeScript arena](https://github.com/microsoft/typescript-go/blob/main/internal/core/arena.go)

## Current Development Proof

Development commit `3a309a8d` established an important substrate:

- source sets retain one original bundled source;
- declaration body locations are bundle-global spans;
- declaration records do not eagerly contain every encoded function body;
- only reachable bodies are parsed lazily;
- ordinary native compilation uses the same bodyless parse/lazy lowering path;
- helper temporary/global IDs advance monotonically;
- obsolete per-file source splitting/appending was removed.

Relevant implementation points:

- `RangeCompiler/Range/Programs/Compiler/Compiler.range:67`
- `RangeCompiler/Range/Programs/Compiler/CompilerCore.range:523`
- `RangeCompiler/Range/Programs/Compiler/CompilerCore.range:527`
- `RangeCompiler/Range/Programs/Compiler/CompilerCore.range:2740`
- `RangeCompiler/Range/Programs/Compiler/CompilerCore.range:6455`

Reported fixed-point run evidence, with the resulting local artifacts verified:

```sh
/usr/bin/time -l scripts/range check-stage2-compiler \
  RangeCompiler/Range/Programs/Compiler
```

Artifacts:

```text
RangeCompiler/Range/Programs/Compiler/.range/Build/stage2/RangeCompiler.ll
RangeCompiler/Range/Programs/Compiler/.range/Build/stage2/RangeCompiler
RangeCompiler/Range/Programs/Compiler/.range/Build/stage3/RangeCompiler.ll
RangeCompiler/Range/Programs/Compiler/.range/Build/stage3/RangeCompiler
```

These measurements came from the successful development run; the repository
does not yet contain a dedicated checked-in benchmark record for them.

| Measurement | Before | After | Change |
| --- | ---: | ---: | ---: |
| Full fixed-point time | 436.71 s | 200.01 s | 54.2% lower, 2.18x throughput |
| Maximum RSS | 25.30 GB | 10.10 GB | 60.1% lower |
| Compiler LLVM size | 1,493,687 B | 1,309,617 B | 12.3% lower |

Verified at that checkpoint:

- Stage 2 and Stage 3 LLVM are byte-identical at
  `208a80777c24e0e285f85ce6959826f49a7cea3987bd485de2c0331f0cda80c1`;
- Stage 2 and Stage 3 native binaries are byte-identical;
- inventory and body-name checks pass;
- transitive `main -> helper -> leaf` compilation passes at both stages;
- delimiter-heavy strings and unique LLVM globals pass;
- LLVM parses, links with `clang`, and executes;
- arithmetic and function-call fixtures return `7`;
- printing emits `Hello from Range`;
- `git diff --check` passes.

This proves that the self-hosting blocker was principally eager representation
and allocation lifetime, not the basic Lexer/Parser concept and not a need for
larger chunks.

It does **not** mean the final representation is complete. Current debt still
includes:

- string-encoded declaration, statement, expression, name, and LLVM records;
- possible repeated lazy parsing of the same body for reachability and
  lowering;
- no permanent `FileID` table over the bundle;
- internal character-count chunks that materialize into parent buffers;
- an approximately 10.10 GB peak live set;
- an 8,000-line transitional `CompilerCore.range`;
- manual bootstrap root inventories;
- no Plotter or typed graph store yet.

That debt list describes the preserved `3a309a8d` baseline. The live branch now
has an opt-in typed authored store, structural Plotter delta, semantic graph,
and MemoryGraph v0 for the closed Pair proof subset. The current Range-owned
proof resolves 12 uses, types all 25 graph nodes, derives one read-only,
non-escaping parameter effect, selects an 8-byte/4-byte-aligned two-field
layout, assigns one local storage region, and emits seven ordered memory
decisions through deterministic destruction. Focused semantic and MemoryGraph
fixtures pass. At that point typed per-function IR, decision-driven
fixed-layout LLVM, and a new Stage 2/3 fixed-point checkpoint remained
outstanding.

The next checkpoint now closes that gap. Stage 2 and Stage 3 are byte-identical
after semantic settlement, MemoryGraph v0, decision-citing typed IR, and
fixed-layout LLVM were added. The fixed point completes in `337.26 s` at
`6.12 GB` maximum RSS; compiler LLVM is `2,117,938` bytes. The renamed `Duo`
fixture with reversed labels exits `7` from aggregate LLVM containing no
dynamic construct runtime or allocator dependency. MemoryGraph, typed-IR, and
proof-LLVM hashes are identical across Stage 2/3. Returned local storage fails
closed with exit `65` before placement.

The proven subset now owns the ordinary native compilation route as well. A
qualifying one-construct/one-local fixed aggregate is settled through the
typed graph before legacy lowering; after qualification it cannot fall back on
semantic or memory failure. The ordinary `Duo` module is byte-identical across
Stage 2/3 and exits `7`. The superseding ordinary-cutover fixed point is
`339.90 s`, `7.10 GB` maximum RSS, and `2,122,020` bytes of compiler LLVM, with
byte-identical Stage 2/3 compiler artifacts.

Returned fixed aggregates now use the same model across a function boundary.
MemoryGraph assigns storage only to the caller, marks the callee return as an
ownership transfer, selects aggregate-value return ABI, suppresses callee
destruction, records caller read accesses, and destroys once after the caller's
last use. Typed IR cites those exact decisions and LLVM emits an aggregate
`ret`/`call` with no dynamic construct runtime or allocator. A callee-local
aggregate return that lacks supported transfer placement fails closed. The
accepted fixed point is `357.69 s`, `4.83 GB` maximum RSS, and `2,177,259`
bytes of compiler LLVM, with identical Stage 2/3 compiler, MemoryGraph, typed
IR, and proof-module artifacts. The specialized native entry module now calls
the Range-authored diagnostic exit helper, so fail-closed results propagate as
native exit `65` rather than being printed with an incorrect success status.

The returned-value path is now rule-driven across call sites instead of being
shaped around one fixture. Each aggregate-returning application owns its own
`Transfer` decision and caller destination; typed IR iterates returned
functions and layout fields; and LLVM selects each callee from the function
identity carried by the call operation. The accepted proof has two distinct
returning functions, two caller storages, and a three-field variant, all with
one fixed aggregate ABI and no construct runtime or allocator. `let` and
`state` also survive typed capture as explicit immutable/mutable storage-policy
decisions and typed-IR operations. This proves compile-time policy selection,
not mutation checking: assignment/write effects, `binding` alias rules, and
`derived` dependency edges remain outside the accepted subset.

The superseding fixed point completes in `374.94 s`, emits `2,210,182` bytes
of compiler LLVM, and produces byte-identical Stage 2/3 compiler artifacts.
The ordinary no-directive two-helper/two-storage module is byte-identical from
Stage 2 and Stage 3 and exits `7`. Peak RSS was `6.40 GB`; because accepted runs
have ranged from `4.83 GB` to `7.10 GB`, this is deterministic-output evidence,
not evidence that peak compiler memory has improved.

State write enforcement now extends that same path without adding another
ownership model. Authored locals carry explicit `let` or `state` kind through
typed syntax. An assignment has typed target/value edges; SemanticGraph resolves
the target and emits a unique write effect; MemoryGraph permits the write only
for mutable storage and emits `Access(write, unique)`; and typed IR emits a
`Store` that cites that exact access decision. The permanent ordinary smoke
mutates a `state` aggregate and exits `7`; changing only that destination to
`let` fails closed with `invalidMemoryGraph` and native exit `65`.

The accepted state-write fixed point completes in `386.91 s` at `5.60 GB`
maximum RSS and emits `2,278,780` bytes of compiler LLVM. Stage 2/3 compiler
LLVM and binaries are byte-identical. During fixed-point hardening, the typed
assignment parser was also constrained so its disabled syntax sink delegates
identifier-led statements to the ordinary statement parser. This preserves
source-set call statements and avoids making typed proof capture a second
parser policy. The measurement proves deterministic output, not low-memory
compilation; the next memory work must reduce transient source/record lifetime
and then repeat the same measured gate.

The binding checkpoint now preserves authored member policy and introduces a
typed `$source` binding-reference node. A binding argument resolves to the
source local's existing `StorageID`; MemoryGraph emits one shared `Alias`
decision and deliberately emits no binding placement, initialization, escape,
or destruction. Multiple shared aliases to the same storage are accepted. A
unique state write while a shared alias is live fails closed with
`invalidMemoryGraph` and native exit `65`.

The superseding binding-write checkpoint is byte-identical across Stage 2/3 at
`398.24 s`, `5.70 GB` maximum RSS, and `2,323,183` bytes of compiler LLVM.
Member-target assignment now traces `user.pair` through the receiver local,
constructor argument, `$source`, and original `StorageID`. A write promotes
that binding instance to `Alias(unique)`; SemanticGraph records the original
storage owner, MemoryGraph emits `Access(write, unique)`, and typed IR emits a
`Store` citing that decision. One unique binding may write. Shared/shared is
accepted; direct-write/shared, shared/unique, and unique/unique combinations
fail closed with `invalidMemoryGraph` and native exit `65`.

Stage 2/3 compiler LLVM SHA-256 is
`0795e6fd2846758609a404ad10e781bd3752d9fd2788f1b47746e79640a803e3`;
the native binary SHA-256 is
`88b2fccad5613ad10f69dcebf76bdd0e664ff1ded7b4abdeaa9bd4f398760c62`.
The fixed LLVM renderer still accepts one aggregate type per proof program, so
the two-construct binding-member write is proven through typed IR rather than
claimed as executable LLVM. General multi-layout lowering is the next backend
blocker. The measured RSS is better than the previous `6.40 GB` sample but is
still not a causal low-memory result.

The focused Swift fixture harness fingerprints the Range compiler sources,
bootstrap executable or Swift sources, runtime C inputs, driver script, OS, and
Clang version. It publishes one isolated mirrored compiler atomically into the
user cache under a cross-process file lock. Fixtures in later Swift test
processes execute that compiler directly while every fingerprint input remains
unchanged.
The three binding checks measured `74.735 s`, `0.138 s`, and `0.130 s`
respectively (`75.005 s` test time total, down from roughly three compiler
builds), while the state positive/negative pair measured `73.568 s` and
`0.139 s`. This is feedback-loop caching only: it does not change compiler
semantics, does not reuse the repository build directory, and is never a
substitute for an uncached Stage 2/3 fixed-point gate.

The persistent-cache checkpoint measured `91.30 s` for a cold invocation that
also rebuilt the Swift test target, followed by `1.01 s` total for the identical
command in a new process; the cached executable fixture itself completed in
`0.369 s`. Cache publication requires a matching ready marker and executable,
and corrupt or incomplete entries rebuild under the same fingerprint lock.

## Stage 0 Boundary

Treat Stage 0 as **frozen semantics, movable substrate**.

Allowed when directly required for self-hosting:

- reusable runtime memory and collection primitives;
- ABI realization;
- generic lowering substrate;
- process invocation, temporary files, linking, and validation;
- parity/oracle tests.

Not allowed as the target direction:

- new Swift-owned Range language semantics;
- a Swift Plotter or second semantic graph model;
- RangeCompiler-specific policy hidden in runtime helpers;
- source-specific compiler shortcuts without an explicit deletion gate.

Stage 0 remains the behavior oracle while Stage 1 takes ownership one vertical
slice at a time. Stage 2/Stage 3 byte identity remains the permanent fixpoint
gate for deterministic compiler behavior.

### Capability transfer from Stage 0

Stage 1 will only become the real compiler when it owns the capabilities that
currently make the Swift-hosted path complete. Transfer them vertically rather
than copying Swift files line for line:

- deterministic project/source inputs and diagnostics;
- the complete structural Lexer/Parser subset used by the compiler;
- typed declaration, scope, name-resolution, and type/effect facts;
- generic buffers, arrays, strings, and runtime ABI operations;
- Foundation loading, declared syntax rewriting, and macro execution;
- requirement validation and carried macro realization;
- function IR, LLVM record construction, and deterministic serialization.

For each capability, add only the reusable Stage 0 substrate necessary to
compile a focused Range fixture, then implement the policy in Range and prove
that Stage 1 reproduces it. Stage 0 should shrink as those vertical slices turn
green.

## Ordered Implementation Direction

### Step 0: Preserve The Proven Fixed Point

- Keep commit `3a309a8d` behavior green.
- Record time, peak RSS, artifact hashes, and fixture results for every full
  fixed-point run.
- Never run concurrent Stage 2/Stage 3 gates.
- Do not restore external chunk directives or eager body records.

Gate: Stage 2 and Stage 3 remain byte-identical and execute the same fixtures.

### Step 1: Add Source And Stable Structural Identity

Introduce:

- `FileID` and file table over the bundled source;
- source roles (`core`, `foundation`, `project`, `generated`);
- file-local and bundle-global span conversion;
- content hashes and line maps;
- `DeclarationID`/`FunctionID` derived from deterministic path facts plus a
  stable overload discriminator based on declared signature shape.

Do this without changing emitted LLVM.

Gate: diagnostics and identities map deterministically back to the correct file
and Stage 2/Stage 3 output stays identical.

### Step 2: Cache Lazy Function Bodies

Add a cache keyed by at least:

```text
(SourceSnapshotID, FunctionID, BodySyntaxHash, ParserSchemaVersion, ParserOptionsHash)
```

Reachability, validation, plotting, and lowering must share the immutable
parsed body instead of reparsing it independently.

The structural parse cache must not depend on `FoundationHash`. Normalization,
macro, and semantic caches add `FoundationHash`, capability hashes, and macro
read-set hashes at their own boundaries.

Gate: each reachable body is parsed at most once per revision and peak memory
does not regress.

### Step 3: Introduce Typed AST Stores Vertically

Replace one complete string-record consumer chain at a time:

1. typed declaration records;
2. typed function/body statement records;
3. typed expression and call-argument records.

Keep string summaries only for diagnostics and snapshot tests. Delete each
encoder/decoder once its final semantic consumer moves to typed storage.

Do not migrate every AST family before testing the memory model. First build
the smallest typed construct/function/member/local/call subset needed by the
`MemoryGraph v0` fixture, prove it end to end, and then expand the stores
vertically.

That first typed subset contains only:

- construct declaration and stored member;
- function, parameter, local binding, and return;
- construct application, member read, and function call;
- integer literal and integer addition.

Gate: no migrated consumer reparses a summary or rendered record to recover
meaning.

### Step 4: Add The Plotter Skeleton

Plot declarations, members, annotations, source identity, and provenance into
typed graph deltas.

Begin with structural facts only:

- `contains`;
- `owns(role, ordinal)`;
- `appliesTo`;
- `facetOf`;
- `originatesFrom`.

Do not attach the full macro/type system yet.

Gate: stable graph snapshots and public-shape hashes are identical across
Stage 2 and Stage 3.

### Step 5: Prove MemoryGraph v0 Through Fixed-Layout Lowering

Use the typed declaration/function subset and Plotter identities to implement
one complete memory-aware compilation path before broadening the macro or
semantic system.

Begin with:

```range
construct Pair {
    let left: Int
    let right: Int
}

function sum(pair: Pair): Int {
    return pair.left + pair.right
}

@main {
    let pair: Pair(left: 3, right: 4)
    return sum(pair: pair)
}
```

Derive typed facts for `storage`, `owns`, `stores`, `borrows`, `aliases`,
`mutates`, `escapes`, and `region/lifetime`. Build the smallest typed
per-function IR needed to carry the resulting representation decision into
LLVM. For this fixture, `pair` is local, read-only across the call, and
non-escaping, so lowering must use a fixed aggregate/value representation
without the linked name-keyed construct runtime or heap allocation.

The source parameter remains a semantic value input. A shared-address ABI for
`sum` is permitted as copy-elision/read-only transport after MemoryGraph proves
the pass mode; it is not source-level aliasing or `binding` semantics.

Then add contrasting fixtures for returned ownership, unique mutation,
conflicting mutable aliases, shared immutable borrows, and an escaping stored
value. Ambiguous or unsupported cases fail with authored diagnostics rather
than silently selecting heap/reference semantics.

Gate:

- memory-graph snapshots are deterministic across Stage 2 and Stage 3;
- the fixture executes with exit status `7`;
- emitted LLVM contains a fixed construct layout;
- emitted LLVM contains no `rangeConstructCreate`, `rangeConstructSet*`, or
  `rangeConstructGet*` calls for the fixture;
- emitted LLVM contains no `malloc` for the non-escaping local value;
- Stage 2 and Stage 3 remain byte-identical;

This is an early proof over a settled subset, not the complete memory system.
The complete memory and reactivity views still expand after declaration,
application, macro, and semantic facts are stable.

After returned/stored values and escape placement are supported, dogfood the
same path on `CompilerBlock`. Existing compiler records are returned or
embedded, so requiring compiler dogfooding in the initial non-escaping proof
would silently broaden the slice. The later dogfood gate must improve or
preserve fixed-point time and peak RSS.

### Step 6: Add Minimal Declaration Resolution And Macro Values

- represent macro declarations and applications as typed graph values;
- index declaration names and target surfaces;
- resolve annotation name references into explicit `resolvedBy` edges;
- represent requirement macros and possible protocol sugar without executing
  them yet;
- keep execution capabilities and type/effect settlement out of this slice.

Gate: macro declaration/application identities and resolution edges are stable
and identical across Stage 2 and Stage 3.

### Step 7: Execute Macros And Move Semantic Facts Onto Graph Views

- complete scope/name resolution over declaration and application views;
- implement `@self` authored-syntax access;
- prototype `@graph` as a runtime-issued selective read-only capability;
- execute macros as deterministic graph deltas with explicit read sets;
- model requirement validation and protocol sugar experimentally;
- keep “everything is a macro” behind the experiment boundary;
- move type/effect facts into per-function or per-SCC overlays;
- add explicit requirement-satisfaction and carried-macro edges;
- stop using parser callbacks and summary parsing as semantic input.

Gate: semantic diagnostics are derived from graph facts and authored spans,
and repeated macro evaluation with identical inputs produces identical deltas,
hashes, diagnostics, and emitted output.

### Step 8: Generalize Per-Function IR

- build typed IR/CFG/SSA per reachable function;
- cache by body, semantic environment, and ABI hashes;
- lower typed IR to LLVM records;
- replace remaining string-encoded backend records with typed LLVM functions,
  blocks, instructions, globals, and declarations as a backend serialization
  cleanup behind the IR boundary;
- allocate deterministic temporary ranges or renumber deterministically at
  merge time;
- reclaim function scratch memory after commit/emission.

Gate: emitted LLVM remains byte-identical while functions can be rebuilt and
emitted independently.

### Step 9: Add Incremental Queries

- persist source, syntax, public-shape, macro read-set, body, IR, and ABI
  fingerprints;
- maintain reverse dependencies;
- invalidate only affected queries and graph views;
- track immutable syntax snapshot reachability across editor/project requests
  and reclaim at explicit revision/request boundaries without defining emitted
  program ownership semantics.

Gate: a body-only edit does not reparse or revalidate unrelated files and does
not invalidate unchanged public dependents.

### Step 10: Enable Bounded Parallelism

- parallelize per-file Lexer/Parser/Plotter work;
- parallelize macro applications whose read/write sets do not conflict;
- process independent dependency SCCs concurrently;
- analyze/lower/emit functions concurrently;
- enforce one global concurrency and memory budget;
- commit all outputs in stable order.

Gate: changing worker count never changes graph hashes, diagnostics, LLVM, or
program behavior; peak memory stays within the configured budget.

### Step 11: Complete Memory And Reactivity Graph Views

Once declaration/application semantics are stable, generalize the early
`MemoryGraph v0` proof across the language and derive reactivity from the same
root graph:

- derive storage identity, ownership, mutation, alias, and borrow facts;
- derive observation, invalidation, and recomputation from memory facts;
- keep both as views over the same root graph;
- use them to power diagnostics, optimization, and incremental scheduling.

Extend the same identities, typed stores, fact kinds, and snapshots proven by
`MemoryGraph v0`. Do not introduce a second memory graph or parallel ownership
engine, and preserve the original v0 fixtures/snapshots as permanent gates.

Gate: no memory or reactivity rule depends directly on raw parser structures.

## Immediate Recommended Slice For The Next Agent

Do not begin with concurrency or a universal macro conversion.

The next work is three vertical milestones:

1. **Complete typed authored storage:** implemented and fixed-point verified
   for the closed proof subset. The verified FileID and declaration checkpoint now
   shares its canonical statement/Pratt parser with an allocation-free disabled
   sink and a live borrowed sink that emits normalized body nodes/role edges for
   the closed proof fixture. No semantic string record is decoded. Instrument
   body parse counts before adding a cache; add one only if an active path proves
   duplicate parsing.
2. **Structural Plotter and semantic settlement:** implemented and fixed-point
   verified through the hardened graph checkpoint. `CompilerGraphDelta` consumes the live typed owner and
   emits dense nodes plus canonically ordered, single-direction ownership facts
   for declarations, ordered members/parameters, statements, applications,
   arguments, source identity, and provenance. It performs no name resolution,
   type inference, memory policy, or snapshot decoding.
   Post-review hardening separates the authored `@main` annotation from its
   entry and emits one `AppliesTo` fact, restores the legacy expression result
   shape through a typed parse-result wrapper, and validates graph
   correspondence plus forest reachability. The first migrated top-level
   symbol decoder and its summary scanners have been deleted. The subsequent
   semantic layer resolves the closed construct/function subset and derives
   explicit read/write/escape effects without moving resolution into Plotter.
3. **MemoryGraph v0 to LLVM:** implemented and Stage 2/Stage 3 fixed-point
   verified: fixed layout, local placement, caller-owned returned-value
   placement, per-call ownership transfer, aggregate return ABI, iterated
   returned functions and fields, immutable/mutable local storage policy,
   initialization, unique state writes, shared borrow, non-escape, by-value
   pass mode, and final destruction are explicit typed decisions. Typed IR
   cites them through fixed aggregate LLVM without the linked construct runtime
   or heap allocation. `binding` now references an existing `StorageID` with no
   placement or destruction. Member-target writes promote the selected binding
   to unique access; shared/shared is accepted while direct-write/shared,
   shared/unique, and unique/unique combinations are rejected. The next backend
   step is general multi-layout LLVM lowering for the already-proven two-type
   typed IR. `derived` dependency edges and longer-lived escaping-owner
   placement follow—not a second compiler or memory model.

Every milestone records fixture behavior, graph/identity snapshots, elapsed
time, peak RSS, and Stage 2/Stage 3 hashes. Current RSS measurements vary too
widely to claim a causal reduction. This sequence instead proves Range's memory
model inside the self-hosted compiler, then removes legacy string consumers so
the typed representation can produce an attributable efficiency result.

Focused fixture batches reuse an isolated, persistent, source/toolchain-
fingerprinted compiler across Swift test processes. Full fixed-point
measurements remain uncached and authoritative.

### 2026-07-10 fixed-point phase audit

The authoritative gate now reports stable phase labels with elapsed time, a
100 ms sampled Swift-process RSS peak, and the maximum raw child-process RSS.
The measurements do not enter generated artifacts or the Stage 2/3 identity
comparison.

The first instrumented fixed point took 479.86 seconds. Native Stage 2 LLVM
emission took 118.06 seconds and 6.50 GB child RSS; the Stage 3 self-rebuild
took 259.01 seconds and 9.00 GB. Stage 1 compilation took 75.95 seconds and
128 MB, while validation, linking, inventory, and smoke checks were all below
one second each. Therefore the direct blocker is Range-authored compiler
selection/lowering and its transient string state, not Swift compilation,
clang, or byte comparison.

Legacy Stage 1 AST/type/LLVM summary assertions no longer hard-root those
reporting paths in the native entry. Bootstrap diagnostics remain available
through `compileRangeSource`; ordinary source and the emitted compiler use the
same native program compilation path.

A measured experiment replaced the manual native root inventory with the
existing transitive reachability walk. It remained Stage 2/3 byte-identical
and reduced LLVM to 2,311,533 bytes, but regressed the gate to 515.30 seconds
and about 10.15 GB. The experiment was reverted. Reachability correctness and
reachability performance are separate concerns; the next optimization target
is selected-helper lowering and transient text construction, not another
compiler model or a weaker fixed-point gate.

The first explicit transient-string region is now active around each selected
helper lowering. Its rendered function and global records are copied into
owned `TextBuffer`s before the region resets. The C substrate tracks only
`stringConcat`, integer formatting, character extraction, and substring
allocations while a region is active; file input, construct storage, and
materialized text buffers remain outside this first boundary. The resulting
Stage 2/3 LLVM is byte-identical at 2,428,874 bytes with SHA-256
`19bb654dba929d87b8588e14b50810673f1ee3beb006683158683372a16689d0`.
The gate took 451.46 seconds. Stage 3 child RSS fell from the immediately prior
explicit-root measurement of 11.07 GB to 9.84 GB, while Stage 2 remained
10.86 GB because Swift-emitted string primitives do not yet allocate through
the region substrate. This proves the region boundary is viable but not yet
sufficient for low-memory bootstrap.

The focused compiler cache also fingerprints every Range core declaration.
Core ABI changes must never reuse a compiler keyed only by project compiler
sources or runtime C. The key hashes Swift sources and `Package.swift`
directly; it deliberately excludes the mutable prebuilt `range` executable,
because a cache build can relink that artifact and otherwise change its own
next-process key.

#### Region and record-processing result

Stage 0 now emits interpolated-string, character, and substring temporaries
through the same transient allocator used by the self-hosted compiler.
`textBufferMaterialize` also participates only while a region is active;
durable materializations outside a mark retain their prior lifetime. Generic
construct getters are non-mutating, and fresh construct objects, fields, and
copied names created during helper lowering share the helper region.

Sampling then found the main linked-runtime CPU multiplier: extracting a small
field from a declaration-record view called general `String.substring`, whose
length clamp scanned the complete multi-megabyte suffix. The audited
`stringSliceUnchecked` substrate is used only after delimiter search proves
`0 <= start <= end <= length`; general substring behavior remains unchanged.
Record encode/decode now classifies ordinary bytes before testing escape
sequences, avoiding five prefix calls per byte while keeping the encoding
policy in Range.

The retained fixed point takes 276.21 seconds with 4,504,305,664 bytes peak
RSS. Stage 2 emission is 88.67 seconds / 4.27 GB; Stage 3 self-rebuild is
113.74 seconds / 4.50 GB. Stage 2/3 LLVM remains byte-identical at 2,429,360
bytes with SHA-256
`95b1b1378bea94a2dd7a88233ff5adcc8d89c0858be7e9cad470b58dd8777e94`.
Relative to the first instrumented 479.86-second / 9.00 GB gate, this is about
42% faster and half the peak resident memory without ARC, GC, a second
compiler model, or a weaker identity gate. Direct field-marker lookup and
span-based decoding were measured and removed after regressing this baseline;
the worktree retains only the byte-classified decoder and bounded field slice.

#### Scalar storage checkpoint

MemoryGraph now assigns storage to authored `Int` locals without inventing a
scalar layout or declaration. The existing semantic identity is preserved as
`kind=Int, declaration=-1`. Scalar initialization is checked by semantic type;
identifier reads cite the owning storage; `state` assignment produces unique
write access; and the same assignment through `let` fails closed. This extends
the aggregate proof instead of adding a scalar-specific compiler model.

The three focused scalar fixtures pass in 0.51 seconds with the persistent
compiler cache warm. The full Stage 2/3 gate then passed in 280.95 seconds.
Both compiler LLVM artifacts are byte-identical at 2,437,516 bytes with
SHA-256
`dda331cd2513c52bf482aa100789af8173ce60a94157f8b39e068bb08fb75cc9`.
The ordinary no-directive smoke artifact now permanently checks real
caller-owned aggregate storage and a computed return, rather than the removed
`ret i32 0` stub behavior.

#### First control-flow lifetime checkpoint

Typed syntax and Plotter now carry one canonical fallthrough `if` shape:
an `If` statement owns its condition and a `LexicalRegion`, and that region
owns its nested statements. MemoryGraph uses this ownership tree directly as
the storage region; it does not inspect legacy statement records or construct
a second CFG. Destroy decisions are ordered by their actual lifetime endpoint.

The focused proof places an entry-local scalar in the entry region and destroys
it at the final return, while a branch-local scalar is placed in the lexical
region and destroyed at that region boundary. The same boundary is proven for
a branch-local aggregate, and a branch-local name used after the region fails
semantic resolution.

The checkpoint passed the full Stage 2/3 gate in 284.49 seconds. Both compiler
LLVM artifacts were byte-identical at 2,463,222 bytes with SHA-256
`28b3220256ab10b28084a2a5a7bfd59ac26a75f50ab2ecb02e3a4bef42c60d12`.
The superseding path-exit checkpoint derives terminal returns recursively from
the same Plotter ownership facts. Destroy is now one decision per applicable
`(storage, exit)` pair rather than one per storage. In the focused scalar
fixture, an entry-owned `outer` value destroys at both the branch return and
the final return; branch-owned `inner` destroys only at the branch return.
Both returns copy scalar values and both storages retain `Escape(0)`. Returning
a branch-local aggregate still fails `invalidMemoryGraph` because no caller
placement or transfer exists, and a statement after a terminal return fails
typed validation. The full Stage 2/3 gate passed in 285.08 seconds with
byte-identical 2,476,499-byte LLVM artifacts and SHA-256
`2f32401f8a74151448893c4c7406c74c9300faaab204ab4987aa6063fd266be8`.

#### Opaque compiler-handle checkpoint

Typed declaration capture now preserves leading `@language` provenance and
accepts signature-only ABI functions without fabricating Range bodies. The
first owned handle is the real Core `IntBuffer`: classification requires a
validated `@language` zero-field `IntBuffer` declaration plus exact
`intBufferCreate`, `intBufferDestroy`, and optional shared-read signatures.
Ordinary empty constructs are never inferred to be opaque.

MemoryGraph gives an owned IntBuffer local placement, initialization from its
validated factory, `Escape(0)`, source storage policy, and exactly one explicit
consuming destroy. It fails closed for missing destroy, double destroy,
use-after-destroy, malformed destructor ABI, and return without transfer.
Typed IR carries factory initialization as a call-receive citing `Initialize`
and the consuming call as `Destroy`; no bespoke opaque LLVM renderer was added.

The full Stage 2/3 gate passed in 291.97 seconds. Both compiler LLVM artifacts
are byte-identical at 2,522,104 bytes with SHA-256
`b08ad21f6b09606879edbbb7a7820e82cac84d6e8e66fb92ac013b5688e64cb5`.
The warm eight-fixture opaque/provenance matrix completes in about 1.35 seconds.

## Explicit Non-Goals And Rejected Directions

Do not:

- remove the Lexer;
- put semantic resolvers inside the Parser;
- graph every token or punctuation mark;
- mutate or replace authored syntax in place;
- discard provenance after desugaring or macro expansion;
- rebuild a fresh graph from expanded files;
- store the same relationship in forward and inverse object fields;
- use ambient parent scanning as the annotation inheritance model;
- make the macro interpreter the universal compiler engine;
- adopt “everything is a macro” before the native experiment is measured;
- create a separate protocol engine beside requirement macros;
- use encoded strings or rendered LLVM as semantic databases;
- lower the generic graph directly to LLVM without function IR;
- copy TypeScript’s duplicated full checker worlds;
- treat arbitrary byte chunks as compiler work ownership;
- spawn unbounded tasks or nested worker pools;
- add concurrency before per-task memory is bounded;
- use ARC, garbage collection, implicit reference counting, or a universal
  heap-object runtime as a substitute for memory-graph derivation;
- leak transient IDs into emitted output;
- add new Stage 0 language policy;
- sacrifice the working self-host fixed point for a broad rewrite.

## Permanent Invariants And Gates

### Correctness

- Stage 2 and Stage 3 are equivalent, preferably byte-identical.
- No reachable function is replaced with a placeholder.
- Unsupported syntax or semantics fail with precise authored diagnostics.
- Worker count never changes results.

### Representation

- Authored source and AST remain immutable.
- Meaning is stored in typed facts, not parsed from summaries.
- Derived nodes retain provenance.
- Every committed relationship has one storage authority.
- Final text exists only at serialization boundaries.

### Performance

- Every full gate records elapsed time and peak RSS.
- Memory is proportional to live source, committed graph state, active
  derivations, and active IR—not the history of string concatenations.
- Changed bodies do not invalidate unrelated public graph facts.
- Outstanding parallel work is bounded by both cores and memory.
- Stage 2 and Stage 3 MemoryGraph snapshots are identical.
- A statically known non-escaping construct lowers without linked-field
  runtime calls or heap allocation.

### Architecture

- Range-authored code owns compiler policy.
- Stage 0 owns only trusted substrate and orchestration.
- Parser remains structural.
- Plotter remains structural graph derivation.
- Macro and semantic passes return deltas/overlays.
- Memory and reactivity remain downstream graph views.
- Backend emission consumes settled semantics through per-function IR.
- MemoryGraph is the sole authority for emitted storage, ownership, alias,
  escape, region, and lifetime decisions.

## Source Material

Current branch:

- `Development/RangeAuthoredCompilerPlan.md`
- `Development/RangeSelfHostingBootstrapSubstratePlan.md`
- `Development/GPT56RangeSelfHostingHandoff.md` (historical operational
  snapshot; chunk guidance is superseded)
- `RangeCompiler/Range/Programs/Compiler/Compiler.range`
- `RangeCompiler/Range/Programs/Compiler/CompilerCore.range`
- development commits `85947e19` and `3a309a8d`

Useful design-branch material, to be adapted rather than copied wholesale:

- `design:Development/DesignNotes/Compiler/ShapeGrammar.md`
- `design:Development/DesignNotes/Compiler/CompilerPipeline.md`
- `design:Development/DesignNotes/Syntax.md`
- `design:Development/DesignNotes/Macros/Context.md`
- `design:Development/DesignNotes/Macros/Macros.md`
- `design:Development/DesignNotes/Macros/Phase.md`
- `design:Development/DesignNotes/Archive/STAGE_GRAPH_PLAN.md`

The architectural theme is consistent across them: preserve authored shape,
derive meaning, centralize graph truth, expose selective macro surfaces, and
lower only after semantic settlement. The changes in this document are the
addition of Plotter, macro values as graph gates, protocols as requirement
macros, the explicit performance/storage model, and the measured self-hosting
migration path.
