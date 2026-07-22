# Range Handoff: Cutover, Graph-Derived Concurrency, Build Plans, And Checkpointed Validation

## Repository And Branch State

Repository:

```text
/Users/george/Documents/Range
```

Canonical branches:

- `production`
- `development`

GitHub default branch: `production`.

Both branches were deployed at:

```text
ab3e0e62e7fb37b4cf8bcf89efdfacdf59ba1e4c
Add checkpointed compiler validation ladder
```

At the time of this handoff, `development` is checked out. The working tree is
**not clean**: `RangeCompiler/Range/Programs/Compiler/CompilerCore.range` has an
uncommitted, partially applied ownership fix described below. Treat it as WIP,
not accepted behavior.

Start by running:

```sh
git status --short --branch
git diff -- RangeCompiler/Range/Programs/Compiler/CompilerCore.range
```

Do not discard that diff without reviewing it.

## Git And Native Cutover Work Completed

The repository originally had diverged `main`/`development` branches and two
Codex branches. The histories and an external dirty worktree were preserved and
merged rather than force-discarded.

Important commits:

```text
f116e773 Add native process batching and linking
06e5ad38 Merge native-only operational cutover into development
89697b74 Merge remaining process/linking work into development
d4b734f2 Add one-lane compiler source scheduler
ab3e0e62 Add checkpointed compiler validation ladder
```

Temporary `codex/*` branches and remote `main` were removed. `main` was replaced
by `production`. Both canonical branches were aligned with the native-only
cutover.

`f116e773` preserved previously uncommitted work from the removed Codex worktree,
including native process batching, linking, seed changes, and tests.

## Concurrency Design Decision

The design discussion began with explicit `@background`, `@channel`, and
`@worker<N>` concepts. It progressed through workers as typed mailboxes and
worker functions applied over collections.

The final architectural conclusion is stronger:

> Range should not begin with authored concurrency syntax. Ordinary value,
> control, ownership, and effect dependencies already define legal parallelism.
> The compiler proves what may run concurrently; one adaptive runtime scheduler
> decides how much of that legal parallelism to use.

Core model:

```text
author describes dependencies
compiler proves legal parallelism
runtime adaptively schedules ready graph applications
stable identities determine commit order
```

Implications:

- Dependencies are joins.
- Returned values are communication edges.
- Indexed collection results commit by input index, not completion order.
- Waiting consumers suspend as graph nodes rather than blocking threads.
- Known blocking runtime operations should eventually park applications.
- A forced single-lane mode remains the semantic reference.
- Concurrency may be introduced only when behavior is unchanged.
- No `async`, `await`, tasks, workers, or channels are required for finite graph
  evaluation unless a future real workload proves otherwise.

Relevant documents:

- `Documentation/RangeGraphDerivedConcurrencyPlan.md`
- `Documentation/GraphDerivedConcurrencyPost.md`
- `Documentation/RangeCompilerDesignDirection.md`

The short post is titled **“Range May Not Need Concurrency Syntax.”**

## Important Correction: The Shell Is A Growth Template

The shell around the accepted LLVM seed is not merely disposable glue. It is the
external executable template that Range should internalize one edge at a time.

Mapping:

```text
Shell today                    Range tomorrow
────────────────────────────────────────────────────
discover source files          derive ProjectGraph inventory
assign source roles            package/source graph facts
construct source bundle        materialize immutable source snapshot
invoke seed/stages             activate compiler applications
run validation fixtures        execute validation graph
compare artifacts              deterministic equivalence gates
track temporary artifacts      scoped application ownership
limit processes                one global adaptive scheduler
manifest runtime inputs        package/toolchain capability graph
```

Migration ladder:

```text
1. Shell authors and executes the plan
2. Range reads and validates the shell-authored plan
3. Range authors the plan; shell executes it
4. Range authors and executes the plan
5. Shell only launches Range and reports status
```

Do not remove the shell prematurely. Keep it deterministic, explicit, bounded,
and structurally isomorphic to the future Range execution graph.

## Build-Plan Checkpoint Implemented

Commit `ab3e0e62` added a canonical shell-authored build plan and a
Range-authored reader.

Canonical generated plan:

```text
RangeCompiler/Range/Programs/Compiler/.range/Build/RangeCompiler.build-plan.tsv
```

Header:

```text
rangeBuildPlan<TAB>version=1
```

The plan records:

- target platform, architecture, pointer width, and runtime ABI;
- tool identity;
- accepted seed path/hash/bytes;
- ordered runtime inputs;
- source set;
- ordered sources with role, logical root, path, hash, and byte count;
- four Stage 2/Stage 3 artifacts;
- Stage 2/Stage 3 applications;
- dependency and validation gates;
- fixed-point byte-identity assertions.

Paths use logical `repo` and `candidate` roots. The plan must not contain
absolute paths, temporary paths, timestamps, PIDs, pointers, or durations.

The shell remains the executor. The plan is currently descriptive and validated,
not executable.

Range reader:

```text
RangeCompiler/Range/Programs/Compiler/CompilerBuildPlan.range
```

Integration:

- `Compiler.range` dispatches `rangeBuildPlan` before ordinary compiler
  directives.
- `CompilerDirectives.range` recognizes the plan header.
- The reader validates strict actual-tab TSV with LF records.
- The reader uses scalar/String state and source rescanning rather than owned
  `CompilerIntTable`/`RawBuffer` state because the accepted seed exposed
  ownership/discovery limitations for the latter in this new call graph.
- No semicolon-separated multi-statement inline blocks are used because the
  accepted typed body parser rejects them even when declaration parsing accepts
  them.

Successful snapshot header:

```text
buildPlan<TAB>version=1<TAB>valid=true<TAB>...
```

Invalid plans produce deterministic diagnostics such as:

```text
compilerError<TAB>kind=invalidBuildPlan<TAB>reason=unsupportedVersion<TAB>line=1
```

## Checkpointed Validation Ladder

The previous development loop repeatedly ran the full self-hosting candidate
suite for tiny reader changes. That was the main reason iteration took minutes
and hundreds of MiB.

Three validation levels now exist.

### 1. Focused build-plan gate

```sh
scripts/range check-build-plan
```

Implementation:

```text
scripts/check-range-build-plan
```

It compiles only `CompilerBuildPlan.range` plus a minimal seed-compatible
harness. It uses a persistent content-addressed cache keyed by:

- accepted seed hash;
- runtime hashes;
- reader hash;
- harness hash;
- schema version.

It validates:

- manifest integrity;
- reader build or validated cache hit;
- exact repeated positive snapshot;
- unsupported version rejection;
- duplicate logical ID rejection;
- malformed field-count rejection;
- unsafe path rejection;
- noncontiguous source-index rejection.

Measured performance:

```text
cold:   24.12 s, approximately 538 MiB peak RSS
cached: 0.41–0.66 s, approximately 7–8 MiB peak RSS
```

Expected output edges include:

```text
checkpoint build-plan:manifest: pass
checkpoint build-plan:cache-hit: pass
checkpoint build-plan:positive-snapshot: pass
checkpoint build-plan:unsupported-version: pass
checkpoint build-plan:duplicate-logical-id: pass
checkpoint build-plan:malformed-field-count: pass
checkpoint build-plan:unsafe-path: pass
checkpoint build-plan:noncontiguous-source-index: pass
checkpoint build-plan:complete: pass
```

### 2. Stage 2 integration smoke gate

```sh
scripts/range check-compiler-smoke
```

Equivalent internal command:

```sh
scripts/check-range-compiler-candidate --checkpoint stage2-plan
```

It stops after:

```text
plan authored
-> seed linked
-> Stage 2 emitted
-> Stage 2 LLVM validated
-> Stage 2 linked
-> Stage 2 reads and snapshots the build plan
```

Measured performance:

```text
153.33 s, approximately 535 MiB peak RSS
```

This passed through:

```text
checkpoint compiler-candidate:stage2-plan-complete: pass
```

### 3. Full candidate/fixed-point gate

```sh
scripts/range check-compiler-candidate
```

This is the expensive release/acceptance gate. It continues through complete
Stage 2 audits, Stage 3 build/link/audits, and fixed-point comparisons. Do not
run it for every small edit.

Each printed checkpoint proves only that edge and its prerequisites, not later
edges.

Documentation:

- `Testing/README.md`
- `Documentation/RangeGraphDerivedConcurrencyPlan.md`

## Why The Full Gate Is Slow And Memory-Heavy

The full candidate command is effectively a release pipeline:

1. Link the approximately 5.4 MB accepted seed LLVM.
2. Bundle roughly 2.6 MB of compiler source.
3. Emit the whole Stage 2 compiler.
4. Validate and ThinLTO-link Stage 2.
5. Run many fixtures, repeatedly emitting and linking native executables.
6. Emit, validate, and link Stage 3.
7. Repeat audits.
8. Compare Stage 2/Stage 3 LLVM and executables byte-for-byte.

The compiler is still string-heavy and non-incremental, with a large monolithic
`CompilerCore.range`, repeated scans, large semantic/ownership tables, and
megabytes of LLVM text. The build-plan reader itself is not responsible for the
large memory use.

Use the cheapest checkpoint that protects the edited edge.

## Current Full-Gate Blocker

The full candidate reaches Stage 2 and passes:

- canonical build-plan generation and shell validation;
- Stage 2 candidate compilation and linking;
- deterministic Stage 2 Range-authored build-plan snapshot;
- nine-file source inventory;
- role and SourceGraph audits;
- canonical Core;
- binding-reference suite;
- several RootValue ownership fixtures.

It then fails at:

```text
RootValue boundary-forward-mixed
compilerError kind=invalidFunctionReachability stage=2
```

Fixture generation:

```text
scripts/check-range-compiler-candidate
write_root_value_bundle
case boundary-forward-mixed
```

The fixture is valid. It returns a three-leaf aggregate containing:

1. a boundary-forwarded owned `RawBuffer`;
2. a borrowed/binding alias `RawBuffer`;
3. a locally created owned `RawBuffer`.

The caller destroys exactly the two returned owned leaves and the original
borrowed owner. Expected creates/destructions are both three.

Two-leaf combinations succeed. Reordering the three members still fails. Directly
returning the same constructor succeeds. The trigger is specifically a local
aggregate carrier combining boundary-forward, boundary-alias, and local-create
leaves.

### Localized compiler failure

The public `stage=2` diagnostic collapses the underlying failure.

Temporary diagnosis localized it to:

```text
compilerBodyArenaBuildOwnedPathTables
-> compilerBodyArenaBuildBindingAliasTopologyForConstruct
-> compilerBodyOwnedPathFindChild(localRootPathID, borrowed memberRow)
```

The constructor application-value root has the borrowed member and alias
provenance. The corresponding local aggregate symbol root is missing that child,
so alias projection fails before return-summary construction.

This is a compiler shape-projection bug, not a return-summary or fixture bug.

Do not “fix” it by:

- skipping a missing local alias;
- weakening binding-alias validation;
- treating the borrowed member as owned;
- suppressing the failure;
- changing the fixture to direct return, which would remove valid local-carrier
  coverage.

## Current Uncommitted WIP In CompilerCore.range

A canceled sub-agent partially applied a proposed fix. The working diff adds:

```text
compilerBodyArenaTypeInstancesAreEquivalent
compilerBodyArenaEnsureLocalAggregateOwnedPathDescendants
```

It also modifies:

```text
compilerBodyArenaBuildBindingAliasTopologyForConstruct
compilerReachableLLVMStateBuildFunctionInstanceEffects
```

Intended behavior:

- reconcile the local aggregate root with the complete tracked descendant shape
  of `resultTypeID` before alias projection;
- append only missing tracked children;
- validate existing root/member/type/policy relationships;
- recursively ensure nested descendants;
- preserve binding alias policy/provenance;
- fail closed on real mismatches;
- preserve more classification failure identity/detail instead of collapsing all
  failures to `-2`.

This WIP is **not validated**. Review it carefully before keeping it. Specific
risks to inspect:

- it rewrites equivalent local type IDs to `resultTypeID` in the owned-path
  table;
- recursive type/cycle handling may be too strict;
- policy assumptions for local roots and nested binding descendants need proof;
- success must preserve all existing positive and negative ownership fixtures;
- diagnostics must not accidentally change unrelated accepted failures.

The last canceled delegated task session was:

```text
a49ea59a-1cbf-49c8-a3db-7ad83fdf6adb
```

That is a Zed sub-agent session ID, not a transferable Codex thread ID.

## Recommended Immediate Work

### A. Add a focused RootValue checkpoint

Do not run the full candidate for every ownership edit.

A diagnosis agent recommended extracting shared candidate helpers into a
sourceable library and adding a focused command that uses a validated cached
Stage 2 compiler. Relevant existing functions:

```text
write_root_value_bundle
audit_root_value_positive
validate_llvm
link_llvm
runtime_inputs
run_capture
require_successful_output
```

The focused checkpoint should:

1. Resolve a content-addressed Stage 2 compiler for current seed/compiler/runtime
   inputs.
2. Generate only `boundary-forward-mixed` using the canonical fixture writer.
3. Emit LLVM twice and compare byte-for-byte.
4. Check layout, definition/call markers, create/destroy counts.
5. Validate LLVM.
6. Link with manifested runtimes.
7. Run and require exit `7`.
8. Print one checkpoint edge per transition.

Do not silently use a stale Stage 2 executable selected by mtime.

### B. Review and validate the WIP fix

Minimum control set:

- `boundary-forward-mixed` must pass.
- forwarded + created must still pass.
- borrowed + created must still pass.
- forwarded + borrowed must still pass.
- direct three-leaf return must still pass.
- nearby negative alias/duplicate/destroy fixtures must still reject.

Then run:

```sh
scripts/range check-build-plan
scripts/range check-compiler-smoke
scripts/range check-compiler-candidate
```

The full gate should advance beyond `boundary-forward-mixed` before any seed
rollover is considered.

### C. After The Baseline Is Green

1. Complete Stage 2/Stage 3 build-plan snapshot equality.
2. Roll the accepted seed only after fixed-point equivalence.
3. Extend the Range plan reader into a loader that:
   - resolves logical `repo`/`candidate` roots;
   - reads listed source files;
   - assigns stable `FileID`s;
   - materializes the same immutable source snapshot currently assembled by
     Bash.
4. Run old shell-bundled and Range-loaded paths sequentially and require
   identical inventories, diagnostics, graph hashes, LLVM, exits, and fixed
   point.
5. Only after that real boundary is internalized should source loading gain
   lifecycle records and adaptive scheduling.

## Useful Commands

```sh
# Current state
git status --short --branch
git diff --check

# Fast reader gate
scripts/range check-build-plan

# Stage 2 integration boundary
scripts/range check-compiler-smoke

# Full candidate/fixed point; expensive
scripts/range check-compiler-candidate

# Accepted seed integrity/fixed point
scripts/range check-seed-integrity
scripts/range check-stage2-compiler

# Compiler progression
scripts/range compiler next --cached-only
scripts/range compiler progression --cached-only
```

## Validation Already Observed

- Focused build-plan gate: passed cold and cached.
- Cached build-plan gate: approximately 0.4–0.66 seconds and 7–8 MiB RSS.
- Stage 2 build-plan smoke checkpoint: passed in approximately 153 seconds and
  535 MiB RSS.
- Full candidate: passes through multiple Stage 2 ownership fixtures, then stops
  at `boundary-forward-mixed`.
- No seed rollover was performed after the build-plan/checkpoint work.

## Working Principles

- Every execution edge should have an explicit checkpoint.
- A passed checkpoint proves only that edge and prerequisites.
- Use focused cached gates for local edits.
- Use Stage 2 smoke for integration.
- Use the full candidate/fixed-point gate only for acceptance.
- Preserve single-lane deterministic equivalence before introducing adaptive
  execution.
- Keep shell and Range graphs structurally aligned during gradual cutover.
- Never weaken ownership checks merely to make a fixture pass.

## Continuation Baseline (2026-07-22)

The accepted compiler has advanced beyond the older validation snapshot above.
It is still a 24-source Range compiler, and the accepted seed is now
5,504,129-byte LLVM with SHA-256
`5317f0f40aec05c3d3f2fd31cfb4981e0d57c89d6f297979be38834e461157b8`.

The newly accepted slice permits bounds-checked indexed mutation through one
mutable construct field, for example `box.values[index]: value`, when both the
local owner and the Array field are `state`. An immutable owner or field is
rejected before LLVM. Ordinary construct fields now use the compiler's
structural type-reference identities; macro-family fields such as
`[@component]` remain in their existing distinct macro model.

The full candidate gate passed through Stage 2 and Stage 3 with byte-identical
LLVM and executables and `typed_only_lowering=pass`.
Accepted-seed integrity and the independent accepted-seed fixed-point check also
pass.

The next accepted slice extends that same operation through arbitrary-depth
mutable construct fields. `root.leaf.values[index]: value` succeeds only when
the root and every field are `state`; an immutable intermediate field rejects
before LLVM. Stage 2 and Stage 3 reproduce byte-identical 5,503,762-byte LLVM
with SHA-256
`68db0983014046fee2e13a6d6aad4993c7051a9c4d9b50befcd432aab9756252`, and
`typed_only_lowering=pass`. Binding-based mutation
remains the next separate proof boundary.
