# Native compiler proof fixtures

This folder contains only focused inputs consumed by the self-hosted compiler
candidate verifier. It is not a general language conformance suite.

- `SelfHosting/MacroFamilyMemory` protects candidate graph and macro-family
  memory behavior.
- `SelfHosting/ArrayWriteOutOfBounds.range` protects a native bounds failure.
- `CompileFail/Collections/ImmutableArrayIndexedAssignment.range` protects the
  one retained negative collection diagnostic used by candidate verification.

The retained `RangePlayground/Examples/LLVM` programs are likewise candidate
lowering checks, not evidence that the complete Foundation or project language
surface is operational. Run the supported validation ladder from cheapest to
broadest:

```sh
# Focused, low-memory Range-authored build-plan reader/source loader; cached after first build.
scripts/range check-build-plan

# Focused RootValue ownership regression using a content-addressed Stage 2 cache.
scripts/range check-root-value

# Complete neighboring RootValue positive and rejection controls, same cache.
scripts/range check-root-value --controls

# Manifest, candidate source plan, seed link, Stage 2 build/link, and plan read.
scripts/range check-compiler-smoke

# Full Stage 2/Stage 3 candidate audits and fixed-point checks.
scripts/range check-compiler-candidate

# Accepted-seed integrity/fixed-point and compiler progression proofs.
scripts/range check-stage2-compiler
scripts/range compiler progression
```

The focused build-plan gate also proves that Range resolves the plan's logical
`repo` and `candidate` roots, loads sources in contiguous plan/FileID order,
checks their declared byte lengths, and materializes a source bundle that is
byte-identical to the shell-authored bundle. The candidate smoke gate repeats
that comparison with the real compiler source set; the full candidate then uses
the Range-loaded bundle as the Stage 3 input.

The transitional compiler source layout keeps source-marker decoding, source
roles, stable `FileID` mapping, source-store access, and inventory/identity
snapshots in `CompilerSources.range`. `CompilerCore.range` retains shared model
types plus the lower-level body and backend phases. The contiguous pre-graph typed
syntax, body capture, macro linking, and macro-execution implementation lives
in `CompilerFrontend.range`. Graph construction, Plotter, and semantic
settlement live in `CompilerGraph.range`. MemoryGraph construction, ownership
decisions, layout, placement, and validation live in `CompilerMemory.range`.
Top-level LLVM orchestration, reachable-function discovery, ABI-plan freezing,
and helper selection live in `CompilerLLVMPlan.range`.
Typed-syntax snapshots, macro summaries and diagnostics, source-to-program
handoff, and declaration/type parsing helpers live in `CompilerParsing.range`.
Decision-citing typed IR and its fixed-aggregate LLVM proof renderer live in
`CompilerTypedIR.range`. These temporary boundaries are accepted only at
individually verified fixed points.

Source-wide invariants such as typed-only lowering are audited across the full
compiler source directory rather than assuming they remain in one file.

Each gate prints explicit checkpoint edges. A reported edge proves only that
edge and its prerequisites; it must not be interpreted as evidence that later
edges in the ladder ran or passed. The build-plan gate stores its
content-addressed reader executable under the user cache directory (override
with `RANGE_BUILD_PLAN_CACHE_DIR`). The RootValue gate similarly stores a Stage
2 compiler keyed by the accepted seed, runtime, tool, and complete compiler
source snapshot (override with `RANGE_STAGE2_CACHE_DIR`). Neither focused gate
runs the full candidate audits.

Add a fixture only when it protects behavior implemented by the Range-authored
compiler and is wired into a native proof command.
