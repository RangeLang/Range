# Range Milestones

This file defines the order of major outcomes. It is intentionally smaller and
more stable than [TODO.md](TODO.md), which owns the actionable checkboxes for
the current milestone.

Milestones are ordered by dependency and leverage, not by how visible or
interesting they are. A later milestone may be explored early, but it is not
complete until every earlier dependency it relies on is complete.

## Current Snapshot — July 25, 2026

Range has a real self-hosted compiler kernel, not merely a language sketch:

- The Range-authored compiler contains approximately 34,500 lines across its
  Driver, Syntax, Body, Graph, and LLVM phases.
- The current Stage 2 compiler smoke gate emits, validates, and links a native
  compiler. The build-plan gate, focused String proof, and complete RootValue
  positive/rejection controls pass.
- The accepted-seed manifest is not currently reproducible:
  `check-seed-integrity` stops at a stale hash for
  `CompilerBodyMIR.range`. This is the first active baseline blocker.
- `CompilerIntTable` is already backed by `Buffer<Int>`, but phase code still
  performs approximately 3,787 numeric row/column reads and 285 raw appends.
  The problem is no longer the underlying allocation; it is the untyped schema
  and pervasive column-number programming.
- The native runtime is three C files totaling approximately 1,600 lines:
  `RangeCompilerHost.c`, `RangeRawBuffer.c`, and
  `RangeCompilerMetrics.c`.
- The compiler recognizes 44 runtime builtin IDs. C currently owns several
  different responsibilities: allocation and lifetime machinery, byte-buffer
  operations, String algorithms, file and process access, compiler metrics,
  and legacy dynamic-construct compatibility.
- The active fixture tree contains 54 focused Range programs. These are useful
  compiler proofs, but they are not yet a complete language conformance suite.
- The two largest compiler files are `CompilerFrontend.range` at roughly 7,000
  lines and `CompilerBodyOwnership.range` at roughly 4,500 lines. Splitting
  them by line count alone would only move complexity between files.

## Milestone 0 — Restore One Reproducible Baseline

This is the highest priority because every structural migration needs a trusted
before-and-after compiler.

Outcome:

- The seed manifest matches every accepted compiler and runtime input.
- The complete supported validation ladder passes from build-plan through
  compiler progression.
- Stage 2 and Stage 3 reproduce byte-identical LLVM and linked executables.
- The accepted candidate, its source inventory, its runtime inventory, and its
  hashes are recorded together.
- `TODO.md` contains no stale statements about gates that now pass.

This milestone does not redesign the compiler. It establishes the checkpoint
from which deletion and migration claims can be trusted.

## Milestone 1 — Automatic Lifetimes and Canonical Core Storage

String and Buffer must feel like language facilities before the compiler and C
runtime can be simplified around them.

Outcome:

- Normal code can write:

  ```range
  state value: String("Hello")
  value.append(text: String(" Range!"))
  ```

  without an explicit `value.destroy()`.
- The compiler inserts deterministic cleanup for every owned value still live
  at normal, early-return, branch, and loop exits.
- Explicit destroy operations remain an internal ownership/runtime mechanism,
  not a normal String API requirement.
- `String` has one canonical authored identity and
  `Buffer<Int<8, .unsigned>>` representation for construction, mutation,
  indexing, comparison, slicing, concatenation, and length.
- `Buffer<Element>` has one permanent layout and mutation model using the
  existing generic system. The deferred generic-parameter redesign is not
  pulled into this milestone unless it becomes a demonstrated blocker.
- Ownership proofs distinguish immutable literal views, mutable owned storage,
  borrowed storage, moves, aliases, and automatic destruction.

Exit proof:

- Focused pass and fail fixtures cover every lifetime boundary above.
- Compiler smoke and fixed-point progression pass with the authored String and
  Buffer implementation.

## Milestone 2 — Move Compiler Text and Scratch Storage onto Core

The compiler should become the largest real user of the same String and Buffer
facilities offered to Range programs.

Outcome:

- Function-local text builders use mutable authored String storage.
- The shared LLVM body, function, and global accumulators no longer use
  `RawBuffer` directly.
- Compiler-owned integer scratch storage uses `Buffer<Int>` through typed
  containers rather than runtime-specific helpers.
- Raw text materialization and repeated immutable concatenation are absent from
  hot compiler paths.
- Compile-time and peak-memory benchmarks guard the migration against the
  previously observed String-builder regression.

This milestone comes before full C cleanup because it removes the compiler's
largest consumer of raw byte-buffer entry points.

## Milestone 3 — Replace IntTable Programming with Typed Compiler Stores

The goal is not to ban dense integer storage. Dense buffers are appropriate for
many compiler graphs. The goal is to remove anonymous schemas and numeric
column access from phase logic.

Migration order:

1. Source files, declarations, members, functions, parameters, and type
   references.
2. Per-function syntax nodes, symbols, resolutions, and type instances.
3. CFG blocks, edges, schedules, regions, and control decisions.
4. Ownership paths, aliases, effects, return summaries, and memory facts.
5. MIR values, operations, operands, versions, and dependencies.
6. Reachability, specialization, ABI planning, and LLVM emission records.
7. Macro and Graph stores once the compiler's ordinary declaration/body path
   proves the typed-store pattern.

For each store:

- Introduce a named row or domain construct and typed accessors.
- Give IDs distinct domain meanings instead of treating every ID as a generic
  `Int` at every boundary.
- Keep compact structure-of-arrays or row-major storage where measurement
  justifies it.
- Delete the corresponding column constants and direct
  `compilerIntTableValue` calls in the same slice.
- Preserve deterministic serialization and fixed-point output.

Exit proof:

- Compiler phase code contains no direct numeric-column reads or partial-row
  appends.
- Any remaining dense-table primitive is private to the typed storage layer.
- Invalid cross-domain IDs fail at a typed boundary rather than producing a
  later negative sentinel.

## Milestone 4 — Shrink C to a Platform ABI

“Full C cleanup” means C no longer owns Range language semantics. It does not
necessarily mean zero C on the first supported platform: memory allocation,
process creation, and file access still require a platform boundary unless
Range emits those system calls or links them directly.

Migration order:

1. Delete the legacy name-keyed dynamic construct object and field lookup
   implementation after emitted LLVM proves no accepted path references it.
2. Move String algorithms and byte-buffer policy into authored Core code.
3. Move identity and transient lifetime policy into compiler-emitted or
   Range-authored runtime code, leaving only the allocator/system interface at
   the platform boundary.
4. Replace compiler metrics semantics with authored instrumentation; retain
   only clock and process primitives that genuinely require the host.
5. Reduce file and process support to explicit, documented platform ABI calls.
6. Remove runtime builtin IDs and C symbols in the same milestone that removes
   their last accepted caller.

Exit proof:

- No String, Buffer, construct-layout, ownership, or graph policy is
  implemented in C.
- The remaining native shim is small, platform-specific, and replaceable.
- Runtime symbols are generated from one ABI description rather than repeated
  across compiler tables, LLVM declarations, C definitions, and manifests.
- macOS and at least one non-Apple target pass the same language fixtures.

## Milestone 5 — Make Compiler Architecture Match Ownership

Only after typed stores exist should the largest files be split. The split
should follow data ownership and phase boundaries, not arbitrary line limits.

Outcome:

- Frontend responsibilities are separated into source loading, lexing,
  declaration parsing, macro expansion, indexing, and diagnostics.
- Body responsibilities are separated into typed syntax, name/type
  resolution, CFG, ownership/effects, MIR, and verification.
- LLVM emission consumes frozen typed inputs and does not reach backward into
  parser-era tables.
- Every phase has explicit inputs, outputs, invariants, destruction, and
  focused proofs.
- Temporary phase data is released after its last consumer rather than living
  in one compiler-wide arena.

Exit proof:

- No “megafile” is required to understand an unrelated phase.
- Dependency direction is enforced by source inventory or package boundaries.
- Compiler results and fixed-point hashes remain deterministic.

## Milestone 6 — Complete the Usable Language and Compiler Driver

This is the point at which a random developer can download Range, point it at a
project, and receive a native program without knowing about seed stages.

Outcome:

- The public CLI owns project discovery, source loading, diagnostics, LLVM
  emission, linking, and executable output.
- Core language fixtures cover constructs, enums, generics, collections,
  macros, ownership, control flow, functions, and errors as one supported
  surface.
- Collection traversal uses intent-bearing operations such as `map`, `filter`,
  `each`, and `reduce`; Range has no `for` statement, and `while` remains the
  explicit condition-driven control form.
- Array, Set, Dictionary, Sequence, and Collection share canonical Buffer-based
  storage and capability rules rather than special compiler cases.
- Diagnostics include stable source paths and spans instead of
  `path=unknown`/negative-sentinel fallbacks.
- Bootstrap/fixed-point commands remain maintainer tools, not the normal user
  workflow.

## Milestone 7 — Canonical Repository and Package Layout

The planned top-level `Compiler`, `Core`, `Foundation`, `Runtime`,
`Frameworks`, and `Bootstrap` ownership layout should happen after their
boundaries are real.

Outcome:

- `RangeCompiler/Sources` is removed in favor of the agreed top-level owners.
- Bootstrap artifacts are visibly separate from active compiler semantics.
- Core versus Foundation is decided facility by facility, not by folder count.
- RangeView is a sibling framework package and does not participate in
  compiler source discovery.
- Build artifacts, the Website, benchmarks, and editor support have explicit
  package boundaries.
- Every manifest, fixture, script, and seed path is migrated in one
  fixed-point-verified checkpoint.

Doing this earlier would create broad path churn while compiler/runtime
ownership is still changing.

## Milestone 8 — Remove Apple Toolchain Dependence

Removing semantic C code and removing Clang are related but separate goals.

Outcome:

- Range can assemble and link emitted LLVM without depending specifically on
  Apple Clang.
- The compiler has explicit target triples, data layouts, platform ABI
  selection, and linker discovery.
- Reproducible compiler and fixture gates run on macOS and Linux.
- Any future non-LLVM backend consumes the same frozen typed MIR/Graph inputs;
  it does not fork frontend or ownership semantics.

## Milestone 9 — Optimize the Crystalline Graph Machine

Graph scheduling, parallelism, hardware targeting, reflection, advanced
heterogeneous collections, and broader macro capabilities belong here only
after the ordinary compiler is typed, reproducible, and portable.

Outcome:

- Graph 0 dependencies and frontiers have a real deterministic consumer.
- Optimization claims are guarded by correctness fixtures, compiler metrics,
  runtime benchmarks, and memory measurements.
- Specialized storage and scheduling are derived from typed capabilities,
  never introduced as one-off compiler exceptions.

## Immediate Order of Work

The practical sequence from today is:

1. Repair seed integrity and re-establish the accepted fixed point.
2. Delete the obsolete string-record parser/summary/lowering path after
   proving that no supported command or fixture consumes it.
3. Implement automatic destruction so normal String code does not call
   `destroy()`.
4. Move surviving compiler text builders and LLVM accumulators off direct
   RawBuffer use.
5. Extract the retained macro-family representation facts and delete any
   unconsumed parallel SemanticGraph/MemoryGraph/TypedIR directive pipeline.
6. Begin typed-store migration with declarations and type references.
7. Measure derived tables and keep Graph 0 on the ordinary path only when it
   has a real consumer.
8. Delete obsolete dynamic-construct C compatibility.

This sequence creates deletion leverage at every step and avoids a rewrite in
which the same untyped tables and runtime semantics merely receive new names.
