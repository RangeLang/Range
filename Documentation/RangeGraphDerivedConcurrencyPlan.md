# Range Graph-Derived Concurrency Plan

## Decision

Range will not begin by adding `async`, `await`, `@background`, `@worker`,
channels, task handles, or another authored concurrency surface.

An authored Range program describes value, ownership, effect, and control
dependencies. Those facts define which graph applications are ready and which
may execute concurrently without changing observable behavior. Concurrency is
an adaptive execution strategy for that deterministic graph, not a separate
programming model.

```text
author describes dependencies
compiler proves legal parallelism
runtime chooses adaptive execution width
stable identities determine commit order
```

This decision applies first to the Range-authored compiler, where graph hashes,
diagnostics, LLVM, and executable behavior provide unusually strong
determinism gates. It may later generalize to compiled Range programs without
requiring new syntax.

## Required Invariants

Changing execution width, completion order, or host machine must not change:

- returned values or collection ordering;
- diagnostics, including their stable ordering;
- committed graph identities, rows, facts, or hashes;
- emitted LLVM or linked program behavior;
- ownership transfer, destruction, or resource lifetime;
- failure and cancellation boundaries.

A forced single-lane execution remains the reference behavior. If the compiler
cannot prove that concurrent execution is equivalent to that reference, the
work stays ordered.

## What The Compiler And Runtime Each Own

The compiler determines the legal execution graph from:

- value and control dependencies;
- stable file, declaration, function, application, and graph identities;
- read/write and ownership effects;
- alias and transfer facts;
- deterministic result and delta destinations;
- lexical lifetime and cancellation boundaries.

The runtime chooses how much legal parallelism to use from:

- available cores and current CPU saturation;
- ready, running, parked, completed, and cancelled work counts;
- observed work duration and queue depth;
- global outstanding-memory pressure;
- known blocking runtime operations;
- interactive or batch priority.

There is one global scheduler and one global memory budget. Compiler phases do
not create nested thread pools.

## Execution Model

Every schedulable application has:

- a stable work identity;
- zero or more prerequisite identities;
- immutable shared inputs;
- worker-local scratch storage;
- a bounded memory estimate or reservation;
- a deterministic result slot or graph delta;
- an effect summary;
- a lifecycle state.

```text
waiting -> ready -> running -> completed
                     |   ^
                     v   |
                   parked

waiting/ready/running/parked -> cancelled
```

Completion makes dependent applications ready. Completion order does not
control commit order. Results and deltas commit by stable authored identity and
phase order.

For indexed collection transformations, each input index owns its output slot.
The runtime may process indices in any order while the materialized collection
retains authored order.

## Blocking And Backpressure

Waiting for a graph dependency suspends the dependent application; it must not
busy-wait or occupy an execution lane.

Known blocking runtime operations should eventually park their application and
release its execution lane. The first implementation may use bounded blocking
lanes, but the scheduler state model must distinguish `running` from `parked`
from the beginning.

Submitting work is also bounded. When memory reservations or pending-result
budgets are exhausted, the producer is suspended until committed work releases
capacity. A large collection must not be expanded into an unbounded queue.

## Implementation Plan

### Phase 0: Lock The Sequential Reference

- Add one explicit compiler execution-width setting whose value `1` forces the
  reference schedule.
- Record current graph hashes, diagnostic streams, emitted LLVM hashes, linked
  exits, peak resident memory, and per-phase timings for representative gates.
- Keep Stage 2/Stage 3 fixed-point checks sequential while the scheduler is
  being introduced.

Gate: the reference corpus is reproducible across repeated single-lane runs.

### Phase 1: Materialize Readiness Without Parallel Execution

- Introduce a compact compiler work record keyed by stable identity.
- Derive prerequisites from existing phase, CFG, macro-read, ownership, and
  effect facts rather than from completion timing.
- Execute the ready queue on one lane.
- Add a deterministic schedule trace containing work identity, prerequisites,
  lifecycle transitions, memory reservation, and commit identity.
- Verify that replacing direct phase loops with the one-lane ready queue does
  not alter any reference artifact.

Gate: one-lane graph scheduling is byte-equivalent to the existing path.

### Phase 2: Add The Global Adaptive Runtime Scheduler

- Add one C runtime scheduler with ready, running, parked, completed, and
  cancelled states.
- Start with a conservative adaptive width bounded by available cores, ready
  work, a configured ceiling, and the global memory budget.
- Reserve memory before admission and release it after deterministic commit.
- Keep completion storage separate from commit ordering.
- Add a deterministic mode that fixes width to one and disables adaptive
  choices without changing the compiled program.

Gate: scheduler stress fixtures complete without leaks, duplicate execution,
lost wakeups, unbounded queues, or commit-order drift.

### Phase 3: Adopt External Independent Work First

- Route independent native compilation, linking, and test-process applications
  through the global scheduler.
- Preserve per-application stdout, stderr, status, and result identity.
- Replay or report process output in stable authored order.
- Replace fixed process-batch parallelism with scheduler admission rather than
  creating a second pool.

Gate: widths `1`, host-core count, and a higher bounded width produce identical
ordered results and diagnostics while demonstrating bounded resource use.

### Phase 4: Adopt Per-File Compiler Work

- Represent source loading, lexing, structural parsing, and plotting as
  file-identified applications.
- Share immutable source storage.
- Give each application owned scratch tables or an uncommitted graph delta.
- Commit token, syntax, diagnostic, and graph outputs in stable `FileID` order.
- Do not expose insertion-order row IDs from worker-local storage.

Gate: varying execution width never changes source inventories, syntax facts,
graph hashes, diagnostics, LLVM, or fixed-point results.

### Phase 5: Adopt Semantic Graph Work

Only after effect and ownership facts are complete enough to prove independence:

- schedule macro applications whose read/write sets do not conflict;
- schedule independent dependency components;
- analyze, lower, and emit independent functions;
- preserve canonical delta and LLVM commit ordering;
- park applications waiting on compiler-owned graph dependencies.

Gate: the full compiler corpus is single-lane equivalent, memory-bounded, and
faster on representative multicore workloads.

### Phase 6: Generalize To Range Programs

- Treat ordinary function applications and collection transformations as graph
  work when their effect and ownership summaries prove independence.
- Keep direct authored values as communication edges and dependencies as joins.
- Automatically choose sequential or concurrent evaluation without changing
  source semantics.
- Add explicit source syntax only if a real program requires behavior that
  cannot be expressed as deterministic finite graph evaluation.

Gate: emitted programs pass the same corpus at multiple scheduler widths with
identical observable behavior.

## Current Decision Checkpoint

The first implementation experiment placed stable work records around
source-inventory rendering. It proved that lifecycle traces and stable commits
fit the native compiler, but it selected a synthetic boundary: inventory
projection is already ordered formatting, not the real source-loading or build
work that the shell currently owns. That experiment has been removed rather
than adopted into the seed.

The stronger boundary is the existing shell-to-seed protocol. The shell is the
external executable template for the graph Range will progressively internalize:

```text
shell discovers sources       -> Range project/source graph
shell constructs bundles      -> Range immutable source snapshot
shell invokes stages          -> Range build applications
shell compares artifacts      -> Range deterministic equivalence gates
shell limits processes        -> Range global adaptive scheduler
```

The shell should remain the reference executor while each responsibility moves
behind the seed. It must not be replaced all at once, and its current behavior
must remain the equivalence oracle.

## First Build-Plan Checkpoint

Implemented on 2026-07-21 without changing execution ownership:

- Bash emits a canonical LF-terminated `rangeBuildPlan` version 1 artifact;
- the plan records target/runtime ABI, tool identity, accepted seed, ordered
  runtime inputs, ordered source roles/roots/paths/hashes/bytes, the source set,
  four Stage 2/Stage 3 artifacts, applications, dependency gates, and fixed-point
  assertions;
- all paths use logical `repo` or `candidate` roots, never absolute or temporary
  paths;
- Bash validates record order, indexes, hashes, byte counts, required graph
  shape, path safety, and plan immutability while remaining the executor;
- the Range-authored compiler strictly parses and validates the same plan and
  emits an authored-order normalized snapshot;
- repeated Stage 2 snapshots are byte-identical;
- unsupported versions and duplicate logical IDs reject deterministically;
- the existing shell-built source bundle remains the compilation input and
  equivalence oracle.

The candidate builds and the plan checkpoint passes before the broader audit
reaches the pre-existing `RootValue boundary-forward-mixed`
`invalidFunctionReachability` failure. Stage 3 plan equality and full
fixed-point adoption are therefore not yet claimed.

## Validation Ladder And Checkpoint Edges

Validation is intentionally split at graph edges so a local reader change does
not require an immediate full compiler audit:

1. `scripts/range check-build-plan` manifests the accepted seed and runtime,
   builds only `CompilerBuildPlan.range` plus seed-compatible support/CLI, and
   verifies the exact deterministic snapshot and focused rejection matrix. Its
   content-addressed executable cache is keyed by seed, runtime, reader, and
   harness/schema identities.
2. `scripts/range check-compiler-smoke [DIR]` discovers the real candidate
   sources, authors and validates their canonical plan, links the manifested
   seed, emits/validates/links Stage 2, and requires Stage 2 to read that plan.
   It exits before `audit_stage`.
3. `scripts/range check-compiler-candidate [DIR]` retains the complete Stage 2
   and Stage 3 audits and fixed-point comparisons.
4. Accepted-seed and progression commands remain the broad release proofs.

Every completed dependency edge emits an explicit checkpoint. A checkpoint is
narrow evidence: `stage2-linked`, for example, proves its preceding manifest,
plan, emission, and validation edges, but does not imply that Stage 2 plan read,
`audit_stage`, Stage 3, or fixed point ran. Automation and reports must name the
last passed edge rather than collapsing partial progress into a whole-gate
claim. This edge principle also supplies the future scheduler with stable units
of readiness, execution, and deterministic commit.

## Immediate Next Slice

1. Restore and record a green full-corpus sequential baseline by resolving the
   existing `boundary-forward-mixed` failure without weakening ownership proof.
2. Complete Stage 2/Stage 3 plan-snapshot equality and fixed-point gates.
3. Extend the Range plan reader into a loader that resolves logical roots, reads
   the listed source files, assigns stable `FileID`s, and materializes the same
   immutable source snapshot now assembled by Bash.
4. Run the old shell-bundled path and the Range-loaded plan path sequentially
   and require identical inventories, diagnostics, graph hashes, LLVM, exits,
   and fixed-point results.
5. Only after that real boundary is internalized should source-load applications
   gain lifecycle records and move behind the adaptive scheduler.

This order grows the seed from the shell template while proving one real
cutover boundary at a time.

## Explicit Non-Goals

- No concurrency keyword or standard-library task abstraction yet.
- No channels for finite graph value flow.
- No per-phase or nested executor pools.
- No completion-order graph mutation.
- No automatic parallelism for unknown, aliased, or ordering-sensitive effects.
- No performance claim without single-lane equivalence and memory measurements.
