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
8. Protocol declarations and construct conformance syntax are retired from
   the target Range language. They remain Swift-hosted compatibility surface
   only while migration proceeds. Carried behavior is proved by successful
   macro emission followed by ordinary generated-declaration validation and
   use; a second protocol/conformance validator is not required to re-prove
   the emitted member.
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

## Protocol Surface Is Retired From The Target Language

The target language does not maintain protocols and macros as two independent
behavior mechanisms. Protocol declarations and construct conformance lists
are retired target syntax. The Swift-hosted compiler may continue to parse
and validate them as compatibility support during migration, but Range-authored
compiler policy must not add a protocol declaration table, conformance list,
requirement collector, `satisfiesRequirement` validator, witness table,
existential, or dynamic dispatch path.

The replacement is a behavior-carrying macro annotation. When a macro emits a
typed declaration and that declaration passes the normal generated-declaration
validation, declaration/member lookup, semantic, MemoryGraph, ABI, typed IR,
and LLVM paths, the emitted behavior is proved by the same pipeline as authored
behavior. Macro validation remains appropriate for prerequisites that the macro
does not generate; it must not redundantly validate a retired protocol surface.

Requirement-style macros may still be explored later for graph facts that are
not carried behavior, but they must extend the typed query/delta model rather
than recreate protocol syntax or a parallel protocol engine. A historical
protocol model was fundamentally a named collection of graph requirements, a
validator over a target graph surface, optional carried macro behavior, and
explicit derived `satisfiesRequirement` facts. That model is retained only as
migration context. Existing Swift-hosted protocol machinery is compatibility
support, not the target architecture.

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
/usr/bin/time -l scripts/range check-stage2-compiler-swift \
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

## Usable Self-Host Replacement Plan

This section supersedes any earlier ordering that treats the current typed
fixture renderer, encoded declaration records, or fixed-point name strings as
the scalable compiler implementation.  The migration is a sequence of
ownership transfers.  A migrated compiler concern has one Range-owned typed
authority; the corresponding record/string consumer is deleted before the
next concern is migrated.

### Corrected permanent phase order

The permanent pipeline is:

1. `SourceStore`: immutable source buffers and deterministic file identity.
2. Typed structural syntax: top-level declarations and lazy per-function body
   arenas with authored source ranges and provenance.
3. Declaration and scope indexes: stable source-order IDs, collision-checked
   name lookup, contiguous member/parameter ranges, and deterministic call
   identity.
4. `SemanticGraph`: resolution, types, callable summaries, and effect facts.
5. Typed per-function HIR and CFG: blocks, edges, regions, exits, and use/def
   facts.
6. Phased `MemoryGraph`:
   - layout and ABI;
   - storage and placement;
   - access, alias, and exclusivity constraints;
   - escape, transfer, and return;
   - CFG liveness and destruction on edges.
7. SSA/value numbering.
8. Typed generic per-function backend IR.
9. Bounded LLVM serialization through append-only buffers/sinks.

Layout and ABI may be derived before CFG construction.  Liveness, conflicting
access, transfer, and destruction may not: they consume real control-flow
facts.  The current source-order/lexical-parent lifetime reconstruction is a
bounded proof, not the final implementation for loops, joins, `break`,
`continue`, or path-sensitive initialization.

Persistent module state is limited to source, declaration/signature/type
indexes, stable identities, and compact call/effect summaries.  Body syntax,
local scopes, CFG, detailed MemoryGraph facts, SSA, and backend IR are owned by
one function compilation and released after that function is serialized.
Replacing strings with a whole-program permanently-live graph is explicitly
not acceptable.

### Corrected performance diagnosis

The retained native Stage 2/3 path currently selects helpers from an explicit
root inventory.  It does not run the transitive fixed-point reachability walk.
The fixed-point name-string algorithm remains a normal-program scaling defect,
but it is not an evidenced cause of the current retained native gate.

The active structural costs are instead:

- top-level declarations serialized into escaped records and decoded again;
- repeated full declaration scans for audit, selection, external declarations,
  return types, parameter types, constructs, and members;
- linear membership in delimited name strings;
- legacy local environments and instructions used as encoded databases;
- cumulative string construction during lowering and LLVM rendering.

The reported 291.97-second fixed-point result and the approximately 4.5 GB
peak-RSS checkpoint are useful baselines, but they were not captured as a
same-revision measurement pair.  Every accepted performance claim from this
point records commit, command, elapsed time, peak RSS, output size, output
hash, and compiler phase counters together.

### Ordered ownership transfers

#### Milestone 1: typed declaration store owns native compilation

Capture top-level constructs, functions, members, parameters, language
provenance, signature ranges, and body ranges once.  Bodies remain lazy.
Build deterministic indexes from names to collision-checked declaration IDs,
functions to signatures/body ranges, constructs to contiguous members, and
functions to contiguous parameters.  Source order—not hash-table order—owns
diagnostic and emission order.  Convert the manual native root inventory to a
FunctionID selection set once.

Route selected-helper audit/enumeration, external declaration rendering,
return/parameter lookup, construct/member lookup, and the legacy body
lowerer's global declaration queries through this store.

Deletion gate: native `compileRangeNativeSource` neither constructs nor scans
`CompilerProgram.declarationRecords`.  Native call graphs no longer contain
`compilerCoreDeclarationLookupRecords`, native uses of top-level declaration
record decoding, or declaration-record return/parameter/construct/member
lookups.  Unsupported native declarations diagnose; they never silently build
both declaration models.

#### Milestone 2: indexed call discovery and lazy typed bodies

Parse each selected body once into a per-function typed arena.  Resolve calls
to FunctionIDs and use a deterministic worklist/bitmap for reachability.
Cache only immutable signature summaries globally; release body detail after
emission unless an explicit incremental cache owns it.

Deletion gate: reachable functions and selected bodies are never represented
as semicolon-delimited names or recursively decoded statement/expression
records.  The manual native inventory remains only as seed roots until normal
entry discovery proves equivalent.

#### Milestone 3: one real compiler leaf family through CFG and backend IR

Take a bounded but real compiler leaf family through typed body syntax,
SemanticGraph, typed CFG, phased MemoryGraph, SSA, generic backend IR, and the
bounded emitter.  Choose by dependency shape and profiling, not by fixture
shape.  Typed ownership is decided before lowering; an unsupported construct
diagnoses instead of falling back after duplicate parsing.

Deletion gate: the migrated family has no legacy statement/expression record
lowering and no fixed-shape LLVM renderer.  `compilerTypedIRFixedLLVMRender`
must be deleted when its last coverage case is handled by the generic emitter,
not extended.

#### Milestone 4: expand vertical families and delete legacy lowering

Migrate control flow, calls, aggregates, mutation, aliases, transfers, and
opaque handles as general rules.  Each family deletes its old parser/lowerer
consumer before the next begins.  Complete the binding conflict matrix and
then add `derived` dependency facts without default storage.

Deletion gate: encoded statements, expressions, local environments,
instruction records, and rendered LLVM are no longer semantic databases.

#### Milestone 5: bounded generic module emission

Serialize functions as they settle into a bounded sink with deterministic
module ordering.  Globals, declarations, types, and functions have explicit
ordered inventories.  Transient IDs and hash iteration never affect bytes.

Deletion gate: cumulative module/function string concatenation and fixed-shape
module rendering are absent from the self-host path.

#### Milestone 6: daily self-hosting leaves Swift

This is a separate bootstrap/driver track and must not obscure compiler
architecture measurements.  Extract one checked-in runtime C implementation
shared by Swift-oracle and native builds.  Check in a Stage 2 LLVM seed with a
manifest containing its source inventory, toolchain/target assumptions, size,
and hash.  A small deterministic native driver verifies the manifest, builds
the seed, accepts the normal source-set interface, and performs Stage 2/3
identity checks.  Swift remains an explicit bootstrap oracle until seed
reproduction and rollback are proven; it stops owning ordinary developer
commands once interface and behavior parity pass.

Deletion gate: normal compile, focused test, and fixed-point commands do not
launch the Swift compiler.  Runtime C is not duplicated in Swift and native
drivers, and a seed rollover is reproducible and auditable.

### Acceptance gates

Every milestone must retain:

- focused positive and failure behavior matrices;
- zero reachable placeholder helpers;
- deterministic diagnostics and emission order;
- exact Stage 2/Stage 3 LLVM byte identity for the full gate;
- no dynamic construct runtime/allocator symbols for statically placed
  non-escaping aggregates;
- identical MemoryGraph snapshots where the gate covers them.

Performance acceptance is measured, never inferred.  Record wall time, CPU
time where available, peak RSS, bytes retained by persistent/per-function
arenas, declaration lookup count/probes, bodies parsed, record fields decoded,
bytes appended/materialized, and phase durations.  A performance change is
retained only when behavior and determinism pass and either elapsed time or
peak RSS improves without a material unexplained regression in the other.
Milestone budgets are set from the immediately preceding same-revision
baseline; no unmeasured speedup estimate is a completion claim.

### Declaration-store migration checkpoint

The first live ownership transfer now uses declaration-only typed capture for
native external function declarations.  It iterates declaration/function/
parameter tables in source order and renders names and types directly from
`SourceStore` spans; it does not decode top-level records or parameter-summary
strings for that decision.

The compiler now also has a permanent collision-checked declaration-name
index.  Hash buckets and chain links use bounds-checked `IntBuffer` mutation;
lookup verifies complete source names after matching the cached hash.  Manual
native root names are mapped once to a function-row bitmap for typed external
declaration exclusion.  Hash iteration never determines emission order.

The obsolete `compilerCoreDeclarationLookupRecords` copy and its record/program
rebuilders have been deleted.  Native parsing already omitted function bodies,
so that code was duplicating an already-bodyless declaration database.

Native selected-helper audit and enumeration now also iterate typed declaration
rows and the FunctionID selection bitmap.  Capability checks read body,
return-type, and parameter spans from typed tables.  Selected function bodies
are located by typed body spans, parameter locals are derived from typed
parameter rows, and helper signatures are rendered from typed spans.  This
removes native record scans and `CompilerTopLevelDeclaration` reconstruction
from selection while the selected body parser/lowerer remains temporarily
legacy-owned.

The declaration index now includes a second collision-checked index keyed by
construct `SyntaxID` and complete member name.  Function return-type and
construct-member-type accessors return authored type spans directly; they do
not create member summaries.  Native selected lowering now enters through a
borrowed `CompilerLLVMLoweringContext` containing the source program, typed
tables, and declaration index.  The entry owner alone destroys tables and
index buffers.  Recursive lowering will be migrated through this context so
source parsing remains available while global semantic queries stop using
`CompilerProgram.declarationRecords`.

This is partial Milestone 1, not its completion: legacy body-lowering
function/construct/member queries still consume the original encoded
declaration records.  The next ownership transfer must thread the typed
declaration/index context through those recursive lowering consumers; only
then can native top-level record construction itself be deleted.

#### Typed selection/index fixed-point measurement

The first full fixed-point gate after typed declaration rendering, indexed root
selection, typed audit/enumeration, member indexing, and the borrowed lowering
context passed exact determinism and behavior gates:

- Stage 2 and Stage 3 LLVM are byte-identical;
- each artifact is 2,599,184 bytes;
- SHA-256 is
  `7afe466ce15aa11b61e1ea964c5ab60c2f6883fb75181f8ba9855cbcbccbe375`;
- linked inventory, body-name, normal compile, and self-rebuild checks passed.

The measured performance is not acceptable as a retained optimization result:

- total elapsed: 322.85 seconds;
- peak RSS: 4,775,067,648 bytes;
- Stage 1 build: 78.104 seconds;
- Stage 2 LLVM emission: 103.808 seconds, 3,950,247,936-byte child peak;
- Stage 3 self-rebuild: 138.088 seconds, 4,775,067,648-byte child peak.

This checkpoint still constructs both typed declarations/indexes and the
legacy top-level record database needed by recursive body lowering.  It proves
the ownership direction and exact fixed point, but it does not satisfy the
performance acceptance rule and must not be described as a speedup.  The next
accepted deletion checkpoint must remove the recursive lowerer's record fact
queries and native declaration-record construction; if that does not recover
both time and memory, the typed representation itself must be profiled before
expansion.

#### Record-free native declaration milestone

The recursive expression, statement, direct-linear, structured-control, and
legacy-control lowerers now borrow one `CompilerLLVMLoweringContext`.  Function
existence/returns, construct existence, and member types are resolved through
collision-checked typed indexes.  Native selected functions use that context
directly; ordinary program roots use explicit owners that capture typed
declarations, build the index, lower, and destroy it.  No lowering path uses a
global context, optional record fallback, or typed-to-record adapter.

`compilerNativeSourceSetProgramForLLVM` now sets `declarationRecords` to the
empty string and performs no top-level record parse.  Typed tables own native
declaration identity, signatures, body spans, audit, selection, global fact
queries, and external declarations.  Native diagnostic selection/statistics
also use the typed pipeline and report `declarationRecordsLength=0`.

The corrected full fixed-point gate passed:

- total elapsed: 290.97 seconds;
- peak RSS: 4,263,608,320 bytes;
- Stage 1 build: 80.148 seconds;
- Stage 2 LLVM emission: 87.885 seconds, 4,095,246,336-byte child peak;
- Stage 3 self-rebuild: 118.162 seconds, 4,263,608,320-byte child peak;
- Stage 2 and Stage 3 LLVM are byte-identical at 2,603,767 bytes;
- SHA-256 is
  `486bbc224dd3abbd2fb4849d5caf824f3a45987c297780cc05b1371cf54473b9`;
- inventory, body-name, normal compile, validation/link, smoke, and self-rebuild
  checks passed.

Compared with the immediately preceding dual-model checkpoint, this deletion
recovered about 31.9 seconds and 511 MB peak RSS.  Compared with the earlier
working approximately 292-second/4.5 GB baseline, elapsed time is essentially
restored while peak RSS is lower by roughly 240 MB.  This is the first accepted
Milestone 1 performance result.  It does not prove that ordinary compilation,
statement/expression records, local-value records, or backend instruction
records are finished; those remain subsequent deletion milestones.

#### Shared compiler host runtime checkpoint

The Darwin compiler-host/runtime C previously embedded in
`SwiftBootstrap.stage2RuntimeSupportSource()` now lives once in the checked-in
`RangeCompiler/Runtime/RangeCompilerHost.c`.  Stage 2 linking consumes that
file directly alongside `RangeString.c`, `RangeTextBuffer.c`, and
`RangeIntBuffer.c`; Swift no longer materializes a generated `RangeRuntime.c`
copy.  The source separates host/process and legacy dynamic-construct support
from compiler policy, and it can be consumed unchanged by the forthcoming
native seed driver.

`clang -fsyntax-only` passes for the extracted source, the Swift package builds,
and the shared IntBuffer runtime/link test passes.  This extraction is a
bootstrap consistency prerequisite, not itself a compiler performance claim.

#### Verified native seed checkpoint

`RangeCompiler/Bootstrap/RangeCompilerSeed.ll` is now a checked-in fixed-point
seed with `RangeCompilerSeed.json` as its provenance and integrity manifest.
The manifest fixes:

- seed and expected Stage 3 byte length and SHA-256;
- canonical ordered compiler source paths and hashes;
- shared runtime ABI version, paths, and hashes;
- Darwin arm64 pointer/target assumptions;
- producer Clang identity and Swift-oracle regeneration command.

`scripts/verify-range-compiler-seed` verifies every manifest input, links the
seed directly with the checked-in runtime, constructs the canonical four-file
compiler source bundle, rebuilds the compiler with the Range-owned executable,
and requires byte-for-byte equality with the seed.  The verified artifact is
2,619,518 bytes with SHA-256
`99248cfc74e544d6df93fc32ff452c49f53565140523cc272de8d36dd82918dd`.

The native verification path completed in 117.58 seconds with 4,380,688,384
bytes peak RSS.  The same-revision Swift-orchestrated full gate completed in
289.31 seconds with 4,230,234,112 bytes peak RSS.  Native verification therefore
removes about 171.7 seconds of wall time by eliminating Stage 1 and the duplicate
Stage 2 emission, at a measured roughly 150 MB higher process peak for this
single run.  It preserves exact compiler bytes and is retained as the normal
self-host verification path; memory remains a backend/compiler target rather
than being hidden by the driver cutover.

`scripts/range check-stage2-compiler` now invokes the verified native seed.
The prior Swift route remains available explicitly as
`scripts/range check-stage2-compiler-swift [DIR]` for recovery, oracle checks,
and seed rollover.  This removes Swift from normal fixed-point verification
without deleting the trusted bootstrap escape hatch.

#### Native single-file developer driver checkpoint

`scripts/range-native` now owns manifested-seed linking, validated LLVM
emission, atomic executable linking, and execution for one `.range` source
file.  `scripts/range emit-llvm`, `compile-executable`, and `run` use this
native driver by default.  `RANGE_DRIVER=swift` remains an explicit oracle
override; there is no silent fallback when native input is unsupported.

The driver verifies seed and runtime hashes before use, caches the linked seed
binary by seed hash, rejects non-file/non-Range inputs, turns compiler-error
output into a failing command, validates LLVM with Clang before committing it,
and links ordinary programs against the same four checked-in runtime sources.

A cold native `compile-executable` measurement for `ReturnInteger.range`
completed in 0.86 seconds with 60,620,800 bytes peak RSS.  The same command
through the Swift override completed in 4.23 seconds with 47,267,840 bytes peak
RSS.  The native path is about 3.37 seconds faster on this small case while
using about 13 MB more peak memory.  The permanent regression test compiles and
runs a temporary program through the native driver and verifies exit status 7;
it completed in about one second with a warm linked-seed cache.

The native driver now also supports general multi-file project directories
through a distinct `compilerProjectSourceSetLLVMText` directive.  It recursively
discovers `.range` files while pruning `.git`, `.range`, and `.build`, sorts
bytewise relative paths, rejects path whitespace not representable by the
current marker grammar, and transports every file through an authored
`compilerSourceFile` identity marker.  The project directive invokes the
general source-set lowerer; it is not aliased to the compiler-specific manual
root inventory.

A cold nested two-file project compile completed in 1.13 seconds with
60,047,360 bytes peak RSS and executed with exit 7.  Two independent emissions
were byte-identical.  Permanent single-file and nested multi-file native-driver
tests both pass in under one second each with a warm linked-seed cache.

The source-manifest change passed the full Swift-oracle fixed point in 289.62
seconds with 4,379,197,440 bytes peak RSS.  Stage 2 and Stage 3 remained
byte-identical, and the rolled manifested seed reproduced itself through the
native verifier.  Normal file and directory emit/link/run workflows are now
off Swift; Swift remains explicit oracle/recovery infrastructure.

### Canonical per-function body arena checkpoint

The first literal-return arena experiment established that selected bodies can
avoid `CompilerStatement` and `CompilerExpression` record construction, but its
private node vocabulary, eligibility-derived counters, and direct LLVM return
renderer were not accepted as permanent architecture. They bypassed the
canonical parser and the future semantic, CFG, MemoryGraph, and MIR pipeline.

That experiment has been replaced by the beginning of the canonical
function-owned body pipeline. The arena now uses the shared syntax kind and
role vocabulary and the canonical body-node column layout. It owns dense local
nodes, edges, and failures while borrowing persistent source and declaration
tables. A lexical-region root, generic statement parser, Pratt-shaped
expression entry, canonical edges, graph validation, and generic node-driven
lowering form the growth point for subsequent body families. No encoded
statement or expression record is created for a migrated body.

The migration boundary still performs a shallow, non-owning lexical support
probe so unsupported bodies remain on the legacy path before arena allocation.
It retains no spans or syntax facts and must disappear as the canonical parser
absorbs all selected bodies. Once a function commits to typed parsing, failure
is deterministic and cannot fall back to records.

Telemetry is propagated from executed helper lowering rather than inferred by
a separate eligibility scan. It records typed parse attempts and successes,
legacy parses, arena creation and destruction, encoded record bytes, and
committed failures. The focused migrated-body gate observed two attempts, two
successes, zero legacy parses, two creations, two destructions, zero record
bytes, and zero committed failures with deterministic repeated output. The
unsupported-shape gate observed one legacy parse and zero typed attempts or
arena allocations. After correcting destroy-failure accounting, the migrated
gate passed in 87.167 seconds. These are correctness and ownership proofs, not
yet evidence of a compiler-wide time or RSS improvement.

The next accepted migration is not another recognized expression shape. It is
a profiled, nontrivial straight-line compiler family carried through the same
canonical arena, resolution to stable IDs, typed CFG, explicitly phased
MemoryGraph, SSA/MIR, and generic emission. At that gate the corresponding
record encoders, decoders, local-value strings, legacy lowering branch, and
fallback are deleted together. Before another full fixed point, phase timing,
per-function parse counts, record encode/decode bytes, transient live bytes,
string copy volume, dynamic-construct activity, and serialization
materialization must be observable. The 117.58-second native rebuild and
289.62-second Swift gate remain baselines because the current compiler source
no longer matches the manifested seed.

### Opt-in compiler cost telemetry checkpoint

The checked-in shared runtime now has one opt-in compiler-metrics substrate,
linked identically by Swift bootstrap, the native driver, and the seed
verifier. Normal compilation leaves it disabled. The explicit
`compilerNativeSourceSetCostStats` directive resets and enables counters only
around the real selected-function pipeline, disables them before reporting,
and never places observations or variable values in emitted LLVM.

The runtime counts actual string-concatenation calls and copied bytes,
substring calls plus scanned source and copied result bytes, dynamic construct
objects, fields, copied name bytes and field-list probes, and TextBuffer append
and materialization calls and bytes. TextBuffer growth reports reallocations
and the live bytes at each growth as the strongest portable copy-pressure
proxy; `realloc` does not expose whether it moved an allocation.

Each selected FunctionID is reported in stable selection order with its name
as a label, actual legacy parse count and encoded record bytes, and deltas for
the string and TextBuffer counters observed while that function was lowered.
Function names do not affect compiler behavior. Begin/end ownership is located
in the selected-function loop, so all returns from typed or legacy lowering
rejoin before the active metric scope is closed. Timing is deliberately absent
from this deterministic report.

Focused runtime coverage observed exact controlled concat, substring,
construct, lookup, append, materialization, and growth counts. The compiler
coverage observed one typed function with zero record bytes and one actually
executed legacy function with 335 record bytes, deterministic repeated cost
reports, and byte-identical ordinary LLVM across repeated metrics-disabled
runs with no metrics symbols in the output. The final compiler-level gate
passed in 83.866 seconds; this is selection evidence, not a performance
improvement.

`scripts/range-compiler-cost-report` then ran the directive over the real
four-file compiler source set through a current Swift-built compiler. The
instrumented run completed in 181.05 seconds with 3,750,264,832 bytes peak RSS.
It discovered 979 functions, selected 932, compiled 129 through typed arenas,
and compiled 803 through legacy records. Legacy bodies produced 513,007,418
final record bytes. The runtime observed 2,390,754,344 TextBuffer appends,
5,204,276,878 appended/materialized bytes, and a 4,548,715,504-byte
reallocation live-byte proxy. Counter overhead makes this a diagnostic run,
not a replacement performance baseline.

The report identified one decisive first migration family. The near-clone
`compilerCoreExpressionSummaryRangeTypeForLLVM` and
`compilerCoreInferExpressionSummaryType` bodies independently produced about
166 MB of final records and 1.79 GB of append volume each. These are exclusive
selected-function observations, not nested rows. Expression records embed and
escape complete child records, call arguments re-encode expressions,
statements re-encode expressions and nested bodies, and each embedding escapes
the previous payload again. Roughly ten kilobytes of authored body therefore
grows to roughly 166 MB of transient semantic text per clone.

Their shared syntax closure defines the next vertical gate: typed immutable
locals, sequential regions, repeated `if` with early returns, final return,
identifiers, String literals, grouping, direct calls with labeled arguments,
nested calls, and eager equality and boolean operators. The family moves
through canonical typed parsing, stable local and global symbol IDs, explicit
CFG, phased MemoryGraph, SSA/MIR, and generic emission. Immutable String `let`
values remain SSA/provenance facts unless semantics require addressable
storage; this migration must not manufacture stack storage or ARC behavior.
Exact branch order, eager `&&` and `||`, argument order, literal-global order,
and temporary numbering are identity gates. Once the structural family
commits, fallback is forbidden. Shared record helpers are deleted only when
their last legacy consumer reaches zero.

The canonical parser checkpoint now covers that closure on the actual compiler
source without activating lowering. `compilerCoreExpressionSummaryRangeTypeForLLVM`
parses into 577 dense nodes and 576 canonical edges;
`compilerCoreInferExpressionSummaryType` parses into 570 nodes and 569 edges.
The actual-source diagnostic created and destroyed all 998 function arenas.
The parser uses one record-free cursor/result API, sequential region iteration,
typed immutable `let`, `if` regions, early/final return, and a shared Pratt core
for literals, identifiers, grouping, nested direct calls, labeled arguments,
and eager equality/boolean operators. Failures retain their original cursor and
source token. Symbol, resolution, CFG, MemoryGraph, and MIR buffers are owned by
the arena but empty at this checkpoint; their names are not evidence until
typed passes populate and validate them.

The next checkpoint populated those tables without activating LLVM lowering.
Both bodies now have stable parameter and lexical-let SymbolIDs, identifier
resolutions, direct-call resolutions to authoritative FunctionIDs, exact
argument-label and arity validation, and deterministic CFGs with condition,
return, and fallthrough terminators. The first body has 18 symbols, 166
resolutions, 43 CFG blocks, and 46 edges; the second has 18, 164, 43, and 46.

MemoryGraph derivation is explicitly ordered and frozen: value/provenance,
placement, access verification, pass/escape/transfer, then lifetime/destruction.
The first body produces 814 facts (595 value/provenance, zero placement, 83
access, 136 pass/escape, zero lifetime); the second produces 805
(588, zero, 82, 135, zero). Both have zero transfer and destruction facts.
This proves that immutable String lets remain SSA/provenance values in this
family rather than becoming stack storage or ARC-managed objects.

Validated deterministic MIR is also populated from syntax, resolutions, CFG,
and frozen MemoryGraph only. The first body has 236 values, 43 MIR blocks, 275
operations, and 301 operands; the second has 232, 43, 271, and 296. Operations
carry an explicit target kind plus target ID so builtin IDs, SymbolIDs, and
FunctionIDs cannot alias semantically. MIR refuses unfrozen MemoryGraph input.
LLVM emission and family activation remain deliberately inactive until generic
MIR emission is byte-identical to the legacy function/global output.

That exact emitter gate now passes. A generic MIR emitter owns numeric
ValueID-to-operand and MIRBlockID-to-label maps plus final serialization
buffers. It inventories String globals in deterministic evaluation order,
resolves calls by FunctionID, preserves eager boolean operations, and assigns
labels and renders blocks through the same CFG depth-first projection. This
keeps numeric CFG identity stable while matching the legacy nested-branch text
order. For multi-block functions, outer return-summary metadata uses the LLVM
type default while concrete returns remain in rendered blocks, matching the
existing generic block contract.

A test-only dual path independently lowered the same parsed bodies through the
legacy record pipeline and the typed syntax-to-MemoryGraph-to-MIR pipeline with
identical initial counters. Both real hot functions now have no differing byte
in rendered functions, instruction records, or globals; temporary counts,
branch counts, and return metadata are identical. The first function emits
11,286 bytes and 16,450 record bytes with temporary 187 and branch 21; the
second emits 11,144 and 16,153 with temporary 183 and branch 21. The focused
dual gate passed in 153.417 seconds. Normal lowering is still unchanged at this
checkpoint; activation must make this structural family typed-only and remove
its normal legacy parse/fallback path before performance is claimed.

The transition gate was then generalized without names, FunctionIDs, source
spans, signature counts, or fixture-shaped statement counts. The canonical
body parser now has a borrowed recognition mode that executes the same
statement, Pratt, postfix, and argument decisions while suppressing all fact
emission. Recognition retains no arena tables. Declaration-index checks reject
unresolved and construct call targets before arena allocation; supported
return types are `Int`, `Bool`, and `String`, and interpolated String literals
remain an explicit unsupported emitter feature. CFG fallthrough selects the
legacy-control outer return-summary default; fully returning direct-control
bodies expose the actual final operand. Concrete LLVM returns are unchanged.

On the actual selected compiler set, recognition admitted 408 FunctionIDs and
all 408 completed typed parsing, semantics, CFG, frozen MemoryGraph, MIR, and
generic emission. A test-only exact-name adapter resolved requested names once
to an exact FunctionID bitmap. Eleven independent dual-oracle processes (40
FunctionIDs per process, with a final partial batch) proved all 408 fully exact:
zero rendered-function, instruction-record, global, counter, or metadata
differences. The broader pre-filter run had identified 28 genuine content
mismatches, all attributable to interpolated String literals, and 363
metadata-only mismatches before the structural CFG fallthrough rule.

Normal activation of those 408 functions was attempted and rejected by the
measured retention gate. Correctness-focused typed/legacy routing tests passed,
but the real instrumented compiler report took 191.93 seconds and reached
10,016,800,768 bytes peak RSS. It lowered 408 functions through typed arenas
and 742 through legacy records, reducing final legacy record bytes to
152,517,090. However, TextBuffer appended/materialized volume increased to
8,886,507,089 bytes and the reallocation live-byte proxy increased to
9,578,345,168 bytes. Against the 181.05-second, 3,750,264,832-byte baseline,
this is slower and roughly 2.7 times the RSS, so the activation was rolled
back. The prior single-integer normal slice remains active; the 408-function
capability and exact oracle remain proof infrastructure only. There was no seed
rollover and no Stage 2/Stage 3 fixed-point run.

The focused `compilerSourceSetLLVMText` formatting regression remained after
the activation rollback: output includes runtime declarations before helpers
and uses globally offset temporary numbers where the older test expects helper
text at byte zero and `%r0`. Because rollback did not change that result, it is
not evidence caused by the rejected 408-function activation. The assertion is
left failing and unchanged pending separate project-source output isolation.

The next blocker is therefore inside the typed pipeline's serialization and
accumulation strategy, not semantic coverage. Record elimination succeeded,
but per-operation String records, per-block buffers, repeated materialization,
and final helper/global accumulation more than replaced the removed legacy
volume. The next retained change must make MIR/emission write compact numeric
data and final LLVM directly into bounded sinks, avoiding duplicated
instruction-record and rendered-block text, before the 408-function activation
is retried.

That streaming checkpoint is now implemented and changes the diagnosis. Typed
MIR instructions serialize exactly once into one per-function sink; there is no
typed instruction-record buffer and no per-block materialization. String
globals retain compact temporary/source-NodeID/byte-count descriptors, runtime
requirements are numeric, and selected helper assembly appends each function's
typed or legacy global text immediately in selected declaration order before
destroying its transient state. The final module never rescans typed rendered
text or recreates typed instruction records.

The two original hot functions remain byte-exact. Regenerating the current
reachable capability inventory produced 414 candidates rather than the older
408 because the streaming/module substrate added selected functions. Eleven
bounded processes proved 414/414 exact final functions, globals, runtime bits,
counters, and metadata. The stale recovered candidate manifest included
`compileRangeNativeSourceDirectiveOutput`; current shared recognition correctly
excludes it as `unsupportedBodyCapability` because it contains interpolation.

A guarded normal activation passed ordinary LLVM correctness but was not
retained. It improved wall time to 99.74 seconds, but still reached
9,586,507,776 bytes maximum RSS, 8,893,209,852 appended/materialized TextBuffer
bytes, and a 9,583,118,205-byte reallocation proxy. The prior narrow selector
was restored because this remains far above the 3,750,264,832-byte memory
baseline.

Per-function attribution proves the streaming emitter is not responsible for
that pressure. All 414 typed functions together account for only 406,316
append/materialize bytes and 109,911 reallocation bytes. The 748 legacy
functions account for 8,889,499,614 append/materialize bytes and 9,578,889,346
reallocation bytes. `compilerBodyArenaIsValid` alone contributes
7,407,541,424 append/materialize bytes and 8,590,897,556 reallocation bytes;
`compilerMemoryGraphIsValid` contributes 205,297,648 bytes and
`compilerCoreIsBinaryOperator` 147,607,765 bytes. Only about 3.30 MB lies
outside per-function lowering, so helper/global/module accumulation is no
longer the dominant blocker. The next performance slice must eliminate the
legacy parser/record amplification in the large validator/control bodies,
starting with `compilerBodyArenaIsValid`, while preserving the one typed model.

### Current broad typed-oracle checkpoint

The current source has 1,350 functions, of which 836 satisfy the canonical
transition capability. The bounded audit is partitioned without changing
compiler behavior: three known legacy incompatibilities have dedicated
regressions, and the two record-expansion hot inference declarations have a
permanent exact final-artifact oracle. Exact declaration names are resolved to
current FunctionIDs only inside the test diagnostic.

Across the remaining 831 functions, the current broad oracle reports 693 exact
functions and 138 structurally classified legacy loop-phi defects, with zero
typed invalid functions, placeholders, typed instruction records, post-lowering
phi mismatches, or unclassified differences. Coverage closes exactly:

`831 broad + 2 dedicated exact + 3 dedicated incompatibility = 836 supported`.

The current authoritative middle range peaked at 67,682,304 bytes RSS and the
high range at 457,080,832 bytes; neither needed a resource split after the two
record-expansion declarations moved to the dedicated exact partition. The
current dedicated two-function final-artifact oracle passed in 103.782 seconds
with 3,654,811,648 bytes maximum RSS. That deliberately expensive oracle is
kept separate from the bounded broad batches rather than hidden behind a
production heuristic.

The
legacy phi preflight is structural rather than name-based: it detects a CFG
backedge with a live immutable parameter or prior lexical `let`. This matches
the legacy lowerer's unconditional loop-local phi behavior and runs before
legacy records are constructed. A separate generic CFG-region/statement-ordinal
continuation lookup also removed the previously unclassified `after-1` label
without fixture-shaped function logic.

### Broad typed activation and first bounded fixed point

The current transition capability was activated for normal selected helper
lowering after the bounded current-source audit closed exactly. The broad gate
classified 831 functions: 693 byte-exact and 138 differences caused solely by
the legacy unwritten-value loop-phi defect. Two record-expansion hot functions
passed their separate exact final-artifact oracle, and three validator
functions remain covered by the dedicated legacy-incompatibility regression.
Together these account for all 836 functions admitted by that audit, with zero
typed-invalid bodies, placeholders, typed instruction records, unclassified
differences, or resource-unverified functions.

Normal activation initially measured 175.79 seconds and 335,970,304 bytes peak
RSS, versus the retained pre-activation baseline of 181.05 seconds and
3,750,264,832 bytes. It reduced final legacy record bytes from 513,007,418 to
63,144,207, TextBuffer append/materialize volume from 5,204,276,878 to
696,323,200 bytes, and the reallocation proxy from 4,548,715,504 to
452,086,506 bytes. Runtime fixed-point execution then exposed two proof
boundaries that text identity alone could not establish:

- scalar functions that call aggregate-returning functions must remain on the
  legacy path until general aggregate caller ABI and ownership transfer are
  proved; the transition predicate now rejects them by semantic declaration
  kind rather than by function name;
- accumulated telemetry was allocated inside a per-function transient region
  and retained after reset. The loop now copies its scalar facts, resets the
  region, and constructs the accumulated value in the surviving region.

The canonical runtime-call ABI now contains 34 checked entries, including the
five optional compiler-metrics calls. The Stage 2 source-set closure also
contains the newly reachable typed-pipeline helpers; these manual name lists
remain bootstrap debt and should be replaced by transitive typed call-edge
reachability.

With those fixes, the full Swift-oracle gate completed successfully. Stage 2
emitted and linked, passed inventory, body-name, and normal executable smoke
checks, then rebuilt Stage 3. The gate's exact Stage 2/Stage 3 LLVM comparison
passed. Total wall time was 336.03 seconds and peak RSS was 681,279,488 bytes;
Stage 2 LLVM emission took 78.071 seconds with 335,953,920 child peak RSS, and
the linked Stage 2 compiler produced Stage 3 in 152.271 seconds with
681,279,488 child peak RSS. This is the first broadly activated fixed point
with bounded memory, but it is not yet a retained speed victory over the old
289.62-second full-gate baseline.

The post-boundary normal cost report measured 190.23 seconds and 367,394,816
bytes peak RSS. It selected 799 reachable typed functions and 512 legacy
functions, with 69,389,942 legacy record bytes, 787,622,704 TextBuffer bytes,
and a 504,612,145-byte reallocation proxy. Memory is about 90 percent below the
old normal baseline, but wall time is about nine seconds slower than 181.05
seconds. Do not roll the seed at this checkpoint. The next retained slice must
recover that time while preserving the fixed point and bounded RSS. Current
telemetry points first to general expression statements in scalar functions
and then to aggregate-return lowering: `compilerBodyArenaAppendNode` alone
accounts for 10,490,537 legacy record bytes and 68,409,597 TextBuffer bytes,
while the next largest legacy bodies primarily return aggregates and therefore
belong to the aggregate caller-placement proof rather than a name-based
exception.

The first follow-up slice added general bare call expression statements without
a wrapper syntax kind or a second lowering route. An existing Application node
may now appear directly on a region's Statement edge; semantics resolves it,
CFG treats it as an ordinary nonterminator, MemoryGraph reuses its CallValue
and ArgumentPass facts, and MIR builds the existing DirectCall operation while
discarding only the returned SSA value. A focused final-artifact dual oracle
passes with zero typed records or placeholders. This moved
`compilerBodyArenaAppendNode` from 10,490,537 legacy record bytes and
68,409,597 TextBuffer bytes to zero legacy records and 10,163 TextBuffer bytes.
The normal cost report now selects 843 typed and 469 legacy reachable
functions, with 52,178,967 legacy record bytes, 640,170,762 TextBuffer bytes,
and a 391,577,089-byte reallocation proxy. Peak RSS fell again to 302,481,408
bytes. Wall time improved only from 190.23 to 189.45 seconds, so the seed remains
unrolled and the time gate remains open.

The following one-pass admission slice removed the production non-retaining
recognition parse. Normal lowering now performs only cheap signature and
aggregate-call ABI preflight, creates one retained arena, and carries that same
arena through parsing, semantics, CFG, MemoryGraph, MIR, and LLVM. Unsupported
syntax or a currently unsupported later typed phase destroys the attempted
arena and uses legacy lowering; audited transition coverage remains the hard
gate that prevents a migrated function from disappearing silently. Arena
parsing now also requires full body consumption, interpolation rejection lives
in the real parser rather than only the deleted probe path, and LLVM emission
is never invoked after an earlier typed phase fails. Telemetry therefore counts
both successful typed bodies and attempted arenas that safely fall back.

The retained normal cost report is now 172.17 seconds with 323,960,832 bytes
peak RSS. It reports 844 successful typed bodies, 970 typed attempts, and 470
legacy bodies; 126 candidates perform one real typed attempt before explicit
fallback. This beats the original 181.05-second normal baseline while retaining
the roughly 91 percent RSS reduction from 3,750,264,832 bytes. Legacy record
bytes are 52,205,659, TextBuffer volume is 640,375,826 bytes, and the
reallocation-pressure proxy is 391,662,427 bytes.

The exact Swift-oracle fixed point also passes after this change. Total time is
310.27 seconds with 612,745,216 bytes peak RSS, compared with 336.03 seconds and
681,279,488 bytes at the prior fixed point. Stage 2 LLVM emission fell from
78.071 to 66.961 seconds and its child peak RSS from 335,953,920 to 307,216,384
bytes. The linked Stage 2 compiler produced Stage 3 in 136.257 seconds rather
than 152.271 seconds. Stage 2 and Stage 3 LLVM remain exactly identical; both
link, and the inventory, body-name, and normal executable smoke gates pass.
The next deletion frontier is typed FunctionID call-edge reachability replacing
the manual semicolon-delimited function-name inventory.

The first reachability implementation now exists beside the retained selector.
It resolves the two native-main roots (`compileRangeNativeSource` and
`compilerNativeOutputExitCode`) to FunctionIDs, follows calls with a stable
bitmap/FIFO worklist, records compact owner/target FunctionID edges, and emits
later in declaration order. On the live compiler source, it discovers no
function absent from the manual inventory; the inventory contains 136
additional functions with no discovered path from the real roots. A permanent
focused parity gate checks this direction explicitly.

Two attempted production cutovers were rejected by the retention gate. Parsing
complete legacy statement records to recover calls inside interpolated strings
completed the exact fixed point but regressed it to 370.16 seconds and
1,570,947,072 bytes peak RSS. Limiting recovery to direct interpolation
expression scanning removed that bridge, but the monolithic Range-authored
reachability builder itself still returns an aggregate and therefore lowered
through the legacy record path; compiling that large body amplified to
11,080,810,496 bytes and the linked Stage 2 rebuild terminated. Normal
selection was restored to the proven bitmap populated from the inventory. The
graph and parity diagnostic remain. Before the next cutover, the builder must
be decomposed into small scalar-returning typed functions (or aggregate caller
placement must become available) so the compiler compiles its own reachability
engine through the new pipeline rather than creating a new legacy hot body.

The first decomposition attempt separated target recording, range scanning,
interpolation scanning, root seeding, worklist expansion, and construction.
That was structurally smaller but did not cross the typed admission boundary:
the range scanner still calls `lexNextRangeToken`, whose
`Optional<RangeLexedToken>` result is an aggregate. The aggregate-call ABI
preflight therefore kept the scanner on legacy lowering. Two bounded attempts
to select the decomposed family were stopped after the live compiler process
reached roughly 7.2–7.5 GB RSS before producing output. The diagnostic wiring
was removed again, so the retained production selector remains the proven
manual bitmap path.

This makes aggregate-return caller placement a prerequisite for reachability
cleanup, not an unrelated feature expansion. Replacing the lexer with a second
character-level call scanner would create a fragile semantic side channel and
is rejected. The next implementation must let a typed caller provide storage
for an aggregate-returning callee, make MemoryGraph own the placement and
transfer decision at that call site, carry the destination through MIR, and
lower the ABI without restoring encoded records. Once the real lexer call is
typed, the decomposed FunctionID worklist can be measured again.

The first aggregate-caller layer is now implemented below the ABI boundary.
BodyArena local declarations parse complete type references rather than one
token, and each arena interns canonical type text into deterministic TypeIDs.
Function-call resolutions retain the callee return TypeID, including generic
types such as `Optional<Box>`, instead of recording `-1`. Nominal member lookup
now follows the type instance to its declaration rather than treating TypeID
as a declaration row.

For an aggregate-returning call used as a local initializer, MemoryGraph now
creates one explicit caller storage row and requires exactly one placement,
initialization, return-transfer, and destruction fact. MIR carries that
StorageID on the direct-call operation and rejects an aggregate function call
without the matching transfer fact. A focused `Optional<Box>` caller reaches
valid semantics, CFG, MemoryGraph, and MIR with one storage, two placement-
phase facts (placement plus initialization), one transfer, one destruction,
and aggregate validation code zero. The ABI preflight still deliberately
rejects production activation, so the current LLVM emitter cannot mistake its
existing pointer call for completed caller placement.

An initial validator integration accidentally failed MemoryGraph for every
typed scalar function, causing the cost run to climb past 3.35 GB; that run was
stopped and rejected. Aggregate validation is now isolated behind a nonzero
storage count while the original scalar validator remains its exact fast path.
The retained post-isolation cost report is bounded at 175.23 seconds and
318,717,952 bytes peak RSS, with 875 typed successes, 470 legacy bodies,
52,209,216 legacy record bytes, and no invalid selected pipeline. This is a
small wall-time regression from 172.17 seconds and remains subject to the final
non-regression gate rather than being treated as the finished milestone.

The next layer is one shared indirect-return ABI query consumed by typed
function declarations, definitions, and call emission. Nontrivial layouts must
be emitted structurally, callers must pass their proven storage as `sret`, and
callees must initialize that destination. The aggregate-call preflight remains
in place until all three sites agree; a pointer slot around the existing
dynamic object ABI is not accepted as caller-owned aggregate placement.

The native compiler no longer uses the manual semicolon-delimited function
inventory for production selection. A deterministic FIFO worklist is seeded by
the two native roots, lowers one FunctionID at a time, records typed call edges
from BodyArena resolutions, and records the remaining legacy call edges by
walking the already-parsed statement/expression records directly. Functions
are marked when enqueued, so each reachable body is lowered once and output
order is stable. A rejected experiment scanned rendered LLVM for calls; it
missed semantic edges and failed the fixed-point gate, so rendered text is not
used as a reachability database.

The obsolete `compilerSourceSetBodyFunctionNames` directive and its complete
manual inventory block have now been deleted. The older source-set and audit
selectors no longer inject compiler-helper names into reachability. The two
superseded legacy edge collectors (semicolon name-list construction and
rendered-LLVM scanning) are also deleted. After this destructive cut, linked
Stage 2 and Stage 3 LLVM are byte-identical at SHA-256
`2db9419cc1e91d69ad87ab0cb0983be6bc055882864f7648943a3a88a70f09f7`.
The retained self-rebuild measured 133.14 seconds and 533,348,352 bytes peak
RSS, versus 150.23 seconds and 556,204,032 bytes for the preceding exact
direct-edge build and 136.257 seconds for the earlier best checkpoint. The
production directive dispatcher no longer exposes the parse-stat, BodyArena
stat, dual-lowering, selected-scan, reachability-comparison, or cost probes;
their implementations and the obsolete selection-analysis aggregate were
physically deleted so declaration capture no longer indexes them. Remaining
reachable legacy body lowering is the next measured time frontier rather than
a completed migration milestone.

Typed-body admission now has one ownership rule instead of silent post-
admission fallback. The cheap ABI preflight runs first and the retaining
BodyArena parser runs once. A structural parse rejection may use the legacy
lowerer. If a partial arena reaches a later pipeline failure, the conservative
recognition pass is run only for that ambiguous body: a rejected capability may
use legacy, while a body recognized as transition-supported fails closed.
Thus semantics, CFG, MemoryGraph, MIR, LLVM, and typed call-edge failures can no
longer fall back after admission. The full arena audit reported 870 transition-
supported bodies and 870 valid complete pipelines with zero stage failures.
The retained native compiler contains zero emitted placeholder comments, and
the ordinary no-directive `@main { return 7 }` regression links and exits 7
with LLVM SHA-256
`c164c3bd807150fec743cc3240be45ac2a8749a11ca6dd1975d9766fc5d9f272`.

Aggregate ABI classification now has one module-stable authority keyed by the
typed function row and declaration index. It classifies `Int`, `Bool`, and
`String` as direct returns, fixed nominal constructs as indirect returns, and
everything without a proven layout as no ABI. Both return preflight and lexical
aggregate-call detection consume this query instead of separately comparing
type-name strings. Generic applications such as `Optional<T>` deliberately
remain unclassified until specialization gives them stable layout identity.
This changes no production signature yet: the aggregate preflight remains
closed because BodyArena still lacks construct-initializer resolution,
structural aggregate MIR values, callee return-destination facts, and a nominal
LLVM layout renderer. Declaration, definition, and call sites must all consume
the shared query before indirect returns are activated.

The fixed nominal substrate now crosses the next deterministic checkpoint.
Supported nominal constructs receive module-level LLVM layouts in declaration
order, construct initializers resolve against their declared field order, MIR
retains nominal TypeIDs, and structural construction lowers through a sequence
of `insertvalue` operations. MemoryGraph also creates a distinct callee-owned
return destination and requires aggregate return exits to initialize it. A
first activation attempt exposed and rejected a mixed-ABI error: applying a
nominal LLVM type to ordinary pointer-shaped parameters made callers pass a
value where existing definitions expected `ptr`. Nominal value typing is now
kept structural until declarations, definitions, calls, and returns switch to
the indirect-result ABI together.

The compiler generation that first contains the corrected nominal layout and
construction emitter reproduces the next generation byte-for-byte at SHA-256
`b8e1a313f6cfc45ff8565172fe0e90a40979c49339f5b3b9e6d9cde7b86efc79`.
Adjacent self-rebuilds measured `138.57 s` / `537,542,656` bytes and `138.60 s`
/ `535,707,648` bytes peak RSS. This proves deterministic, bounded nominal
layout emission; it does not yet activate aggregate returns. The activation
gate remains closed until the shared ABI query controls all four signature
sites and any function requiring that ABI is forbidden from falling back to
legacy lowering.

An attempted atomic ABI activation implemented the intended `sret` declaration,
definition, caller allocation/load, callee store, and structural member-read
surfaces, but it was rejected rather than retained. Globally enabling every
fixed scalar-layout construct admitted foundational compiler records at once;
the first fail-closed run reported 22 unsupported typed functions and reached
about 5.06 GB RSS. A structural source scan and then a cached classification
did not solve the ownership boundary: later runs accumulated 13--19 GB, and a
live sample showed the compiler spending its time in legacy encoded-record
field parsing, with one run observing a 76.3 GB peak footprint before it was
stopped. The entire signature/call activation was removed, and the exact
bounded checkpoint above was restored at `136.55 s` / `537,444,352` bytes for
the producing generation and `138.94 s` / `536,592,384` bytes for its exact
self-rebuild.

The conclusion is narrower than "aggregate ABI is too expensive." The ABI
instructions were not the measured hot path. Activation introduced new helper
reachability and weakened the cheap unknown-call preflight, causing more work
to enter the legacy record model. The next cutover must therefore store ABI
capability beside the typed FunctionID reachability decision, reuse that O(1)
decision in all four LLVM sites, and fail closed without lexically rescanning
bodies or adding a legacy-lowered signature-helper chain. Only after that
authority is typed and bounded should caller allocation and `sret` emission be
reactivated.

The first part of that authority is now retained. `CompilerReachableLLVMState`
owns a FunctionID-indexed ABI-capability bitmap. While processing a reachable
function whose classified return is a fixed nominal aggregate, the compiler
runs only the retaining BodyArena, resolution, CFG, MemoryGraph, and MIR
pipeline, destroys the arena inside the existing transient region, and records
one capability bit when every middle-layer validator succeeds. It deliberately
does not alter declarations, definitions, calls, returns, or ordinary typed
admission yet, so capability discovery cannot create a mixed ABI.

This checkpoint is byte-identical across consecutive generations at SHA-256
`c8090771a7d97684cc4dc61a8fe1040a316ec8100ac21381d1223e20ebd034bf`.
The producing generation measured `136.85 s` and `541,884,416` bytes peak RSS;
the self-rebuild measured `139.26 s` and `538,787,840` bytes. The next step is
to close this candidate bitmap over incoming typed call edges: an aggregate
callee may be activated only when every reachable caller proves its caller
placement path. That closure, rather than a lexical body scan or global nominal
switch, becomes the single O(1) ABI decision consumed by all four LLVM sites.

Caller closure is now implemented as a second FunctionID bitmap. A reachable
function is probed after its real call edges are known when it either returns a
classified indirect nominal or calls one. Failed probes retain their first
middle-pipeline stage in the capability slot. The closure seeds only capable
indirect-return functions, rejects a callee with any incapable incoming
caller, and propagates rejection through aggregate-return callers until stable.
No LLVM signature consumes the activation bitmap yet.

A temporary non-empty audit then established an important correction: the
current reachable compiler graph contains zero functions classified into this
fixed-nominal ABI family. The audit reported `functionRow=-1, stage=0`, meaning
no probe was attempted, rather than every probe failing. `rangeToken` is emitted
as a reachable pointer-returning helper and `%Range.RangeLexedToken` has a
fixed layout, but the compiler-facing lexer edge remains
`lexNextRangeToken -> Optional<RangeLexedToken>`. Generic applications are
still deliberately classified as no ABI, so that edge cannot seed the fixed
nominal closure. The temporary failing audit was removed; stage-coded slots
and deterministic caller closure remain ready for a real candidate.

The restored usable checkpoint is byte-identical at SHA-256
`0ac952aa4ce380c9511e86c63cd60b5481aa514bab9845f83fc011af1b0f569b`.
The two generations measured `140.02 s` / `539,656,192` bytes and `141.34 s` /
`539,394,048` bytes peak RSS. The actual prerequisite for activating the lexer
family is therefore deterministic generic layout identity or specialization
for `Optional<RangeLexedToken>`, not another fixed-nominal signature switch.

### Optional ownership family and non-empty ABI closure

The prerequisite is now implemented structurally. Concrete
`Optional<FixedNominal>` types receive stable named layouts containing a tag
and payload, and fixed nominal layouts may contain other acyclic fixed nominal
layouts through bounded recursive validation. This admits compiler types such
as `CompilerProgram { mainBlock: CompilerBlock, ... }` without a
`CompilerProgram` special case. Cyclic or unsupported field graphs remain
unclassified rather than silently becoming pointers.

The typed body pipeline now represents all three Optional operations required
by the first lexer/caller family. `nil` becomes `OptionalNone`; returning a
payload from an Optional-returning function creates an explicit
`OptionalInjection` MemoryGraph fact and `OptionalSome` MIR operation; and
`left ?? fallback` resolves to the payload TypeID. Coalescing preserves lazy
semantics in MIR by evaluating only the Optional operand and retaining the
fallback syntax node as a deferred branch target. It is not lowered as an
eager generic binary operation or copied from the legacy `i32 == 0`
implementation. LLVM lowering still needs present/fallback/join blocks before
this operation can become an emitted typed-only function.

Caller placement, return transfer, callee return destination, Optional
injection, and MIR validation now share `compilerFunctionReturnABI` as their
single admission decision. This fixed two inconsistencies: MemoryGraph and MIR
previously demanded storage for every construct-valued call even when no
indirect ABI existed, while placement could create storage that transfer
correctly refused. MemoryGraph phase construction is now sequential and
stage-coded, so a failed value, placement, access, pass/escape, lifetime, or
final-validation phase cannot execute later phases through Range's eager
boolean operators. The ordinary typed lowering gate was corrected in the same
way. FunctionID edge collection likewise appends only actual function
resolutions; eager boolean evaluation can no longer manufacture edges from
locals, members, or builtins.

The reachable ABI capability bitmap and incoming-caller closure are now both
non-empty on the real compiler source. This proves a coherent Optional-return
family through BodyArena, resolution, CFG, MemoryGraph, and MIR. It does not
yet mean LLVM consumes the activation bitmap: definitions, declarations,
calls, returns, `OptionalSome`, `OptionalNone`, and lazy coalescing must switch
together before legacy lowering for the family can be deleted.

After removing the temporary lexer-name and packed storage diagnostics, two
linked self-generations are byte-identical at SHA-256
`2f4e81ef0f13ee7a3dfc995ed0c92f3c4df3139a6797974715ee91aeb7311a66`.
They measured `158.67 s` / `543,637,504` bytes and `160.26 s` /
`548,585,472` bytes peak RSS. This is a retained capability/closure
checkpoint, not the performance milestone: the remaining roughly 160-second
cost still comes from emitted legacy lowering and must fall when the proven
family becomes typed-only and its encoded-record consumers are deleted.

### Legacy reachability recovery deletion checkpoint

The obsolete record-based reachability recovery slice is now deleted: ordinary
FunctionID call edges come only from typed BodyArena resolutions and MIR. The
diagnostic and legacy lowering record model remains in place for its remaining
callers; ordinary discovery no longer contains a legacy edge path or legacy
parse activity.

The authoritative Stage 2/3 gate passed validation/link, inventory, normal
smoke, mixed aggregate-ABI rejection before emission, and self-rebuild. Stage 2
LLVM emission measured `29.937 s` with `70,402,048` bytes child RSS; Stage 3
self-rebuild measured `29.904 s` with `71,139,328` bytes child RSS. The outer
`/usr/bin/time -l` gate measured `181.85 s` real time and `171,507,712` bytes
peak RSS. Stage 2 and Stage 3 LLVM are byte-identical at SHA-256
`9771e9668e939b06cb58f05f5b0774597e81669c6c67ddcc85e29328722ddfa9` and
`2,971,047` bytes; their executables are byte-identical at SHA-256
`5bb6eca32b44b8ba156e0e9157246caf6badffd56e828af0ced06727e433c541` and
`1,447,840` bytes.

### Native seed rollover checkpoint

Immediately before the rollover, the Stage 2 and Stage 3 candidate LLVM
artifacts were byte-identical at `2,971,047` bytes and SHA-256
`9771e9668e939b06cb58f05f5b0774597e81669c6c67ddcc85e29328722ddfa9`.  The
checked-in seed now exactly matches that Stage 2 artifact.  The manifest also
records the current four compiler-source hashes while retaining the verified
runtime ABI, runtime inputs, target assumptions, Clang provenance, and native
fixed-point command.

`/usr/bin/time -l scripts/range check-stage2-compiler` verified every manifest
input, linked the seed with the shared five-file runtime, rebuilt the canonical
four-source bundle without invoking Swift, and reproduced the seed byte for
byte.  It completed in `27.81 s` real time with `71,286,784` bytes maximum RSS
and reported SHA-256 `9771e9668e939b06cb58f05f5b0774597e81669c6c67ddcc85e29328722ddfa9`
at `2,971,047` bytes.  The normal native run of
`RangePlayground/Examples/LLVM/ReturnInteger.range` exited with status `7`.

Swift is no longer needed for normal seed reproduction/daily fixed-point
verification, but remains an explicit recovery/oracle path pending a separate
deletion slice.

### Native compiler-evolution checkpoint

`/usr/bin/time -l scripts/range check-compiler-candidate` now builds from the
checked-in seed while intentionally ignoring `compilerSources.*` hashes, so
native compiler evolution no longer needs Swift. The verified run completed in
`58.80 s` real time with `73,039,872` bytes maximum RSS. Dynamic inventory,
deterministic aggregate smoke, mixed aggregate-ABI rejection before emission,
Stage 2/3 validation and linking, and the no-Swift path all passed. Stage 2
and Stage 3 LLVM are byte-identical at SHA-256
`9771e9668e939b06cb58f05f5b0774597e81669c6c67ddcc85e29328722ddfa9` and
`2,971,047` bytes; linked executables are byte-identical at SHA-256
`c815cf8d1d6922c10e32d3ae064a91a1650616879fb940cf0ab876fc59ac5f74` and
`1,447,840` bytes. The command does not mutate the seed or manifest, so seed
rollover remains explicit. Role-aware Core loading and native macros are the
next slices; Swift is not yet removable because macro and tooling parity is
incomplete.

### Source roles and canonical Core checkpoint

Source roles are now first-class in the self-hosted compiler source model:
`core=0`, `foundation=1`, `generated=2`, and `project=3`. The legacy
`compilerSourceFile\tpath` transport remains valid and decodes as `project`.
Explicit role markers are decoded centrally into deterministic path and content
boundaries, and those boundaries feed source inventory, identity, typed syntax,
fingerprints, and source-set handling. Unknown or malformed roles fail closed.

The authoritative `/usr/bin/time -l scripts/range check-compiler-candidate`
run completed in `61.31 s` real time with `73,580,544` bytes maximum RSS and no
Swift invocation. Stage 2 and Stage 3 both passed the explicit-role, legacy
project, malformed-marker, deterministic identity/fingerprint, and ordinary
smoke audits. The canonical proof read the checked-in
`RangeCompiler/Range/Core/System/Memory/IntBuffer.range` as `role=core`, loaded
a project source as `role=project`, validated and linked the emitted LLVM, and
executed with exit status `7` in both stages.

Stage 2 and Stage 3 LLVM are byte-identical at SHA-256
`fdec0503efbcd2ac37961eee0a0029640e32ace9e42953d52ae49ccc02481c9b` and
`2,992,386` bytes. Their linked executables are byte-identical at SHA-256
`459dc4b9dc3f19a3fd48bdc356bd66a4b79a50f9c19313c6e184171c2ca0d6c0` and
`1,464,976` bytes. The seed and manifest were not changed; seed rollover
remains explicit and Swift is not yet removable.

This proves first-class roles and one supported canonical Core leaf usable from
project code. Full Core/Foundation loading and macro declaration/application
values remain subsequent slices; macros are not implemented by this checkpoint.

### Native typed macro linking checkpoint

The native compiler now stores macro declarations, macro parameters, macro
applications, and one authoritative edge table directly in `CompilerSyntaxTables`.
Rows retain role-aware `FileID` provenance, authored and semantic spans,
source-backed names and target surfaces, compact fingerprints, and stable
ordinals. The shared typed capture path recognizes general macro declarations
and arbitrary declaration/member/parameter annotations. Linking validates the
target surface and records `appliesTo` and `resolvedBy` edges without executing
macro bodies or emitting expansions.

The focused native gate proves a cross-role Core declaration to project
application graph with four declarations, one macro parameter, five
applications, five `appliesTo` edges, and five `resolvedBy` edges; repeated
snapshots and Stage 2/Stage 3 snapshots are identical. A second positive bundle
puts the macro-free Foundation file first and compares a reorder-stable
identity projection over stored identity pairs and per-file ordinals; the raw
graph digest remains a table/provenance observer and is not claimed reorder
invariant. Unresolved, duplicate/ambiguous, malformed declaration, malformed
application, and target-surface mismatch fixtures reject before emission.
`/usr/bin/time -l scripts/range check-compiler-candidate` completed in
`66.22 s` real time with `80,134,144` bytes maximum RSS and no Swift
invocation. Stage 2 and Stage 3 LLVM are byte-identical at SHA-256
`6a6101f94193256b898f8845bb0bce7d09ca19938ee99b8164b5094c3dc98fe5` and
`3,200,790` bytes. Their linked executables are byte-identical at SHA-256
`356b5a5ea5b8d0c070576cad3a617e49394a252ee4d1ef69fdf29c1fd35d3ffd` and
`1,701,488` bytes. Ordinary aggregate smoke still exits `7`, and mixed
aggregate-ABI rejection still exits `65` before emission in both stages.

This is a linking/modeling proof only. Macro-body execution, target/
diagnostics/graph capabilities, `@self` and `@graph` realization, expansion,
requirement/protocol evaluation, full Foundation loading, Swift deletion, and
seed rollover remain deferred. The required Stage 1 source walk passes parsing
and semantic validation but still reports the pre-existing obsolete
`compilerNativeSourceSetSelectedScanStats` post-pass audit as
`invalidEntryReachability stage=2`; that directive is absent from both the
live source and `HEAD` and was not added here.

### Native diagnostic-only macro execution checkpoint

Resolved cross-role applications can now create a typed application-phase
invocation with stable application/declaration identities, target provenance,
three driver-issued capability handles, an explicit 64-step budget, staged
diagnostic events, zero read dependencies, and an empty `GraphDelta`. The
handles are authority frames, not dependency rows; the authored capability header is
captured structurally; its executable span is parsed through the ordinary
retained `BodyArena`, symbol/resolution, semantic/MemoryGraph, and canonical
body-MIR phases. A bounded evaluator consumes that shared MIR and admits
literal diagnostic operations, return, and closed capability denial. It does
not emit ordinary LLVM for macro bodies, allocate runtime strings, access I/O,
or mutate the graph.

The focused gate proves arbitrary informational and warning macros, multiple
invocation ordinals, source-attributed error events, direct native LLVM
pre-emission rejection for error severity, explicit graph capability denial,
fuel exhaustion, malformed and duplicate capability headers, repeated positive
determinism, and byte-identical Stage 2/Stage 3 execution snapshots. A second
ordinary native integration fixture runs the same arbitrary diagnostic macro
and application alongside `@main { return 7 }`, validates and links LLVM, and
exits `7` in both stages with byte-identical output. Existing macro-linking
negatives, canonical Core, aggregate smoke, mixed-ABI rejection, and fixed-
point checks remain green.

`/usr/bin/time -l bash scripts/check-range-compiler-candidate
RangeCompiler/Range/Programs/Compiler` completed in `76.08 s` real time with
`91,635,712` bytes maximum RSS and `swift_invocation=none`. Stage 2 and Stage 3
LLVM are byte-identical at SHA-256
`126e50b67b99113bfd23d119d1debedecc17a1152f9e3740f35933db66f94a0f` and
`3,388,196` bytes. Their linked executables are byte-identical at SHA-256
`10940f4ade6a3a5183f555031e2cc9a75cd3ee1dde8dd41e3558fff1893aaf94` and
`1,954,384` bytes. The required Stage 1 source walk still reaches the known
obsolete `invalidEntryReachability stage=2` post-pass after successful source
processing; no Swift or legacy audit restoration was made.

The ordinary integration LLVM is byte-identical at SHA-256
`11700b9c2a06c8179a54b5025e5b476dcc07181126cb043d90b3bff077d3cbcc` and
`1,185` bytes; its linked executable is byte-identical at SHA-256
`6527f4bf00ebcda8f8a140faad0ea1d734fcac90a6db5546924ebc13927c53cc` and
`38,336` bytes.

### Native read-query and committed omission-expansion checkpoint

The graph capability now has one selective read-only operation:
`graph.declarationCount(kind, name)`. The bootstrap surface accepts the
literal declaration selectors `Construct` and `Function`, resolves the call
through the ordinary macro `BodyArena` and canonical MIR, and produces an
`Int` value. Every observation records an exact dependency row containing the
numeric declaration kind, queried name identity, observed count, and an
observation fingerprint over matching stable declaration identities. A
zero-result query still records the absent bucket. This makes both positive
and negative observations incrementally meaningful without granting macros a
mutable or unrestricted graph view.

The target capability now admits the existing `SyntaxOmittable` shape
`target.omit()`. Execution stages the target syntax node with source
provenance and a typed `omitted` expansion fact in a non-empty
`CompilerGraphDelta`; it does not rewrite source text. Expansion requests are
transactional across the macro run. Repeating omission for the same target is
rejected as `macroGraphDeltaInvalid`, and no partial delta is returned.
Unknown graph and target operations remain capability-denied. The graph
capability remains read-only; only the target capability can stage a target-
scoped expansion fact.

Focused Stage 2 and Stage 3 gates prove repeated query and expansion
determinism, dependency stability when an unrelated source file changes file
ordering, dependency-digest changes when the observed bucket changes,
zero-result dependencies, invalid-query rejection before LLVM, combined query
plus omission, transactional duplicate rejection, and denied unknown target
operations. The ordinary native integration also executes a graph query
before LLVM validation/link and still exits `7`. The complete fixed-point
gate passes with no Swift invocation.

Successful omission deltas are now committed for ordinary compilation through
a second declaration index that owns a compact omission overlay. Authored
syntax tables remain immutable. The expanded index excludes omitted
declarations and members from name/member lookup, nominal-layout rendering,
and unselected function declarations. The ordinary commitment fixture omits
the complete `Hidden` construct and one stored member from `Retained`; emitted
LLVM contains no `Hidden` layout and contains exactly
`%Range.Retained = type { i32 }`, then validates, links, and exits `7`.
Repeated Stage 2 and Stage 3 expansion LLVM is byte-identical at SHA-256
`ed7a269089d5bf5fe33a746f58c303ef2f9763e083a734135e0f399de1ec9759`
and `1,217` bytes; the linked executables are byte-identical at SHA-256
`2aaad69ee5925273b9245c3754ee850147429ad09cf066f9b89e939c8098a32e`
and `38,336` bytes.

The complete compiler remains at a fixed point: Stage 2 and Stage 3 LLVM are
byte-identical at SHA-256
`7acaed4a1e2d02e70648258a0af0b6c80436236eca78cadbf02b09b70d4439ad`
and `3,473,799` bytes; their linked executables are byte-identical at SHA-256
`dbc1342b779e2c352a8f31da0306a39f9c17dc1456578c1ff80584fe80dcccb6`
and `2,039,312` bytes.

This is real delta commitment for typed omission, not a general expansion
scheduler. Generated nodes/declarations, replacement values, carried behavior,
multi-round macro scheduling, and conflict resolution beyond duplicate
omission remain unimplemented. Likewise, declaration counting alone is not
protocol validation. Protocols-as-requirement-macros are now close enough to
build on this substrate, but they still need selective target/member/
requirement queries, macro evaluation that follows typed CFG conditions, and a
typed derived `satisfiesRequirement` fact or carried behavior delta. Those
features must extend this query/delta model rather than create a separate
protocol engine.

Arrays, closures, `where`, generic `Macro.Application` values, generated and
replacement expansion scheduling, requirements/protocol evaluation, `@self`,
Foundation `@graph`, the authored `Project` macro, general compile-time
control flow, runtime calls, and full Foundation execution remain outside this
slice.

### Native target member-count and typed CFG checkpoint

The target capability now has the frozen read-only surface
`target.memberCount("memberName") -> Int`. It counts direct authored member
declarations with that name on a construct application target. The lookup uses
the immutable pre-expansion declaration/member snapshot, so in-flight
`GraphDelta` state and macro invocation order cannot change the answer. It does
not enumerate members, mutate source or declarations, allocate storage, or
stage a delta. The ordinary `@main` finder walks `lexNextRangeToken` through
`compilerCursorPeek` and accepts only an exact `macroAttribute` token, so string
contents cannot shadow the real entry attribute. The current lexer has no
comment token. Non-construct targets and malformed calls—including wrong
arity and non-`String` names—are rejected as the focused
`macroGraphQueryInvalid` diagnostic with exit `65` before ordinary LLVM
emission.

The valid target-query MIR contract is exactly one receiver plus one `String`
name argument. Malformed surface calls are carried as an explicit invalid
target-query resolution so MIR validation still checks the typed shape and maps
that failure to the focused query diagnostic rather than generic
`macroBodyInvalid`.

Each executed member query records one exact read-dependency row, including a
zero result. The `macroReadDependency` table has 18 columns in this order:
`row`, `invocationRow`, `operation`, `kindTag`, `fileID`, `kindStart`,
`kindEnd`, `nameStart`, `nameEnd`, `observedCount`,
`applicationIdentity.first`, `applicationIdentity.second`,
`targetIdentity.first`, `targetIdentity.second`, `queryIdentity.first`,
`queryIdentity.second`, `observation.first`, and `observation.second`. The
renderer exposes those four fingerprint pairs explicitly. Application identity
is derived from the source-file path/role, authored application text, and
same-file occurrence of that text; target identity is derived from the target
declaration's source-file path/role, kind, authored declaration text, and
same-file occurrence. No absolute source offset, transient syntax ID, or parser
row ordinal is part of that identity. The focused gate compares the complete
dependency rows—not only the aggregate digest—after inserting an unrelated
source file, and repeated executions are byte-identical. The canonical
aggregate digest retains operation, kind, count, and observation semantics while
excluding invocation-local identity; the exact row and execution digest include
all explicit identity columns. The aggregate digest therefore does not make an
unstable row identity acceptable.

Macro evaluation now follows the retained typed CFG/MIR from its canonical
entry block. Only reachable blocks execute. Typed boolean conditions select
the recorded true/false successors, `return` terminates the current path, and
diagnostics, queries, denied operations, and graph deltas in an untaken path do
not execute. Fuel is consumed by actually executed MIR operations and
terminators, bounding cycles and malformed CFGs without a fallback linear
scan. The minimal scalar support is sufficient for a member-count comparison
to select a diagnostic error path or a success path. The focused negative
fixture also applies the query from a `Function`-target macro and verifies that
runtime target-kind enforcement rejects it before dependency recording or LLVM
emission.

The focused candidate gate proves present-member success and positive exact
dependency recording, missing-member zero dependency and pre-emission exit
`65`, an untaken denied target operation, malformed-query rejection, repeated
output/dependency/LLVM determinism, zero-argument and non-`String` malformed
query rejection, non-construct target-kind rejection, ordinary LLVM
validation/linking with conventional exit `7`, and byte-identical Stage 2/Stage
3 results. Existing
`declarationCount` positive/zero, omission commit/rollback, capability-denial,
fuel, macro-linking, aggregate ABI, and fixed-point checks remain part of the
same gate.

The final bounded command, `/usr/bin/time -l scripts/range
check-compiler-candidate`, passed in `87.54 s` real time (`83.57 s` user,
`2.20 s` system) with `93,372,416` bytes maximum RSS and
`swift_invocation=none`. The four-file inventory passed. Stage 2 and Stage 3
compiler LLVM are byte-identical at SHA-256
`5896a802f4bf44c5cb2e7ec06782e9615314639b41e8a64ab290f38fe4c77cae` and
`3,541,481` bytes; their linked executables are byte-identical at SHA-256
`ce998274af1f814962f7179fbd6e65e79f70556ec8e76cd8d9524771d6425680` and
`2,073,328` bytes. The present-member native LLVM is byte-identical at
SHA-256 `34c7fac1433e82a488f305be3a185674c5403a1dbacd0818665c546bd5212ca5`
and `1,215` bytes; its linked executable is byte-identical at SHA-256
`7103dfbf8ac592bc655ea8a8508b3efbd11171f63bd241f05ceaea34307dae94` and
`38,344` bytes. Stage 2/Stage 3 focused snapshots and the candidate fixed
point all passed.

This is a validation substrate, not protocol support. It adds no protocols,
conformance checking, witness tables, generated declarations or behavior,
requirement enumeration, arrays, closures, `where` clauses, member
enumeration, runtime macro behavior, or protocol-specific validator. A future
requirement-macro slice must extend these selective typed queries and CFG/delta
semantics rather than introduce a separate protocol engine.

### Native typed generated-function emission checkpoint

The canonical native deferred-declaration surface is the contextual
`@expand` operation inside a macro executable body:

```range
macro registrable(): Construct { target, diagnostics in
    @expand {
        function create(): Int {
            return 7
        }
    }
}
```

`@expand` is compiler-known and is rejected outside a macro body. Its block is
captured at macro-declaration parse time as typed deferred function templates;
it is never rendered to source or reparsed. Execution instantiates the
templates into the attached construct's pending `CompilerGraphDelta`. The
bounded implementation supports zero parameters, an `Int` return, and the
existing scalar `return integer` body shape. Template ordinals are lexical and
generated identities derive from macro application identity, target identity,
ordinal, and structural template data rather than source-table rows or
absolute offsets.

Generated records carry their function kind, owner construct, source ranges,
signature/body template, macro declaration/application/target provenance, and
stable identity. Validation is transactional: duplicate generated names and
authored/generated collisions reject before commitment with the focused
`generatedFunctionCollision` diagnostic, and no partial delta commits. A
successful delta is materialized as an ordinary typed function declaration and
member owner in the expanded declaration view. Lookup, semantic analysis,
MemoryGraph, ABI planning, typed MIR, and LLVM lowering therefore use the same
paths as authored functions. The post-commit overlay validator is idempotent:
it ignores only the already-materialized generated row whose owner/name and
declaration fingerprint match that delta stable identity, while a different
same-owner/name row remains a collision.

The focused candidate gate proves two data-driven generated members, absence
from authored construct syntax, ordinary member calls, native LLVM
validation/linking, executable exit `7`, repeated byte identity, stable
identity/provenance under unrelated source insertion, collision rejection
before LLVM, and rejection of `@expand` outside a macro. Stage 2 and Stage 3
focused snapshots/artifacts and the complete compiler fixed point are required
to remain byte-identical. This slice does not add generic generated functions,
arbitrary types or bodies, generated constructs, replacement expansion,
recursive or multi-round macro scheduling, source rewriting, or protocol
syntax/validation.

The final accepted command, `/usr/bin/time -l bash
scripts/check-range-compiler-candidate`, passed in `96.20 s` real time
(`90.84 s` user, `2.74 s` system) with `102,236,160` bytes maximum RSS and
`swift_invocation=none`. The four-file inventory, Stage 2/Stage 3 fixed point,
focused snapshots, LLVM validation/linking, executable exit checks, collision
transactionality, and outside-macro rejection all passed. Stage 2 and Stage 3
compiler LLVM are byte-identical at SHA-256
`96c969b6184792c4a29ae53386f40edf83a915143527704721512d6425ac635e` and
`3,696,725` bytes; their linked executables are byte-identical at SHA-256
`2fb43c4e80aea4b4ddbd2a363254953760eb372002273f8924b589ce9061e1e7` and
`2,257,504` bytes.

### Explicit deferrals

Do not add compiler concurrency before one-function memory is bounded and
phase telemetry exists.  Defer incremental cross-build caching, advanced
optimizer work, whole-program specialization, protocols-as-macros expansion,
and `derived` runtime scheduling until they block a migrated vertical family.
Do not implement ARC, garbage collection, a universal heap object model, or a
second compiler representation to ease the transition.

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
