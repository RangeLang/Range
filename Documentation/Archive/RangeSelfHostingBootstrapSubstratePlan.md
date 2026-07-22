# Range Self-Hosting Bootstrap Substrate Plan

## Status And Authority

This is the working implementation plan for replacing the temporary chunked
self-hosting path with a bounded-memory, single-process compiler pipeline.

Stage 0 is no longer frozen. It may change wherever doing so directly unblocks
self-hosting. Those changes must remain minimal and must converge toward one
Range-authored compiler model rather than creating a second Swift semantic
implementation that must be maintained in parallel.

Prefer reusable runtime, ABI, and lowering substrate. If temporary Stage 0
compatibility plumbing is unavoidable, pair it with the Range-authored owner
and remove it as soon as Stage 1 reproduces the capability. Compiler policy,
selection policy, parser policy, and LLVM module policy remain Range-authored.

## Target

```text
Stage 0 SwiftBootstrap
-> builds Stage 1 RangeCompiler
-> Stage 1 compiles the same RangeCompiler sources
-> links Stage 2 RangeCompiler
-> Stage 2 compiles the same sources
-> links Stage 3 RangeCompiler
-> compare Stage 2 and Stage 3
```

The successful end state is not merely a linked binary. It requires:

- bounded compilation memory;
- no chunk directives;
- no fake helper implementations;
- typed semantic compiler collections;
- direct Range-authored LLVM records;
- deterministic Stage 2 and Stage 3 behavior.

## Non-Negotiable Boundaries

1. Stage 0 may change only for a direct self-hosting blocker, and only by the
   smallest useful amount.
2. Prefer shared runtime functions, ABI realization, generic lowering,
   invocation, temporary-file handling, linking, and validation over
   RangeCompiler-specific machinery.
3. Do not create or preserve parallel Swift and Range semantic compiler models.
   Any unavoidable compatibility bridge must have a deletion gate.
4. Stage 1 owns the converging parser, typed records, validation, reachability, lowering,
   ordering, and LLVM module structure.
5. The current chunk protocol remains only until a single-process replacement
   is green. It must not grow into the permanent architecture.
6. A Stage 2 artifact containing a default-return placeholder is a failed
   artifact even if it parses, links, or runs a smoke program.

## Measured Checkpoint

The current chunk work proves useful parts of the self-hosting path:

- Stage 1 builds.
- Native source-set parsing succeeds.
- Reachability succeeds.
- The source-set declaration record is split into 14 emission chunks.
- All 14 Stage 1 chunk processes completed in the first full assembly attempt.
- The assembled Stage 2 LLVM passed LLVM parsing.
- Native linking then failed because nine reachable Range helper functions were
  emitted only as unresolved declarations.

The first full attempt recorded:

```text
command: /usr/bin/time -l scripts/range check-stage2-compiler \
         RangeCompiler/Range/Programs/Compiler
elapsed: 1410.35 seconds
maximum resident set size: 18049695744 bytes
result: LLVM parsed; native link failed on missing helper definitions
```

The missing helper audit identified twelve bodies that needed to be retained:
the nine linker-reported helpers plus three immediate transitive dependencies.
The body inventory was expanded, but the next full run was intentionally
stopped before completion so the substrate direction could be reviewed.

This is sufficient evidence to stop spending time on repeated full chunk gates
until the focused substrate and correctness gates below are green.

## Diagnosis

The active problem is not fundamentally lexer or parser correctness. Stage 1
represents many collections and intermediate structures as serialized strings:

- declaration records;
- statement records;
- expression records and summaries;
- local-value records;
- reachable-function name lists;
- LLVM instruction and global records;
- rendered helper functions.

The bootstrap runtime currently allocates a new buffer for concatenation,
substring extraction, and character extraction without completing temporary
ownership. Repeated accumulation therefore creates quadratic copying and retains
the complete allocation history.

Chunking shortens the lifetime of each allocation history by using multiple
processes, but every chunk reparses the complete source set, recomputes
reachability, and rebuilds intermediate records. It avoids one failure mode
without fixing the representation.

There is a separate correctness problem: reachable helpers currently receive a
default-return implementation when their statement records are absent, their
signature is unsupported, or their body exceeds the active size limit. Those
placeholders can make an incomplete compiler look linked and executable.

## Vertical-Slice Rule

Every new facility must complete this loop before RangeCompiler source depends
on it broadly:

```text
1. Define the smallest reusable Range-facing capability.
2. Stage 0 compiles and runs a focused fixture using it.
3. Stage 1 parses, validates, and lowers the same capability.
4. A Stage 1-produced native fixture proves the observable behavior.
5. RangeCompiler adopts the capability in one bounded consumer chain.
6. Stage 1 reproduces that consumer while compiling itself.
```

Do not land half of this loop and compensate with a Swift source-specific
special case.

## Substrate Decision 1: Growable Text Or Byte Buffer

The first substrate facility is an opaque growable buffer with geometric
capacity growth. It must not copy the complete accumulated output on append.

The first Range-facing call shape must match the subset Stage 1 can already
lower. In particular:

- use ordinary free-function calls;
- pass the buffer explicitly;
- require at least one argument per call;
- use explicit non-`Void` return values;
- avoid overload resolution;
- avoid generic member dispatch.

An illustrative ABI is:

```range
@builtin
construct TextBuffer {}

function textBufferCreate(capacity: Int): TextBuffer
function textBufferAppend(buffer: TextBuffer, text: String): Int
function textBufferAppendInt(buffer: TextBuffer, value: Int): Int
function textBufferMaterialize(buffer: TextBuffer): String
function textBufferDestroy(buffer: TextBuffer): Int
```

The exact declaration spelling must be proven by the focused Stage 0 and
Stage 1 fixtures before it becomes RangeCore API.

Required behavior:

- capacity grows geometrically;
- append is amortized linear across the complete output;
- materialization performs at most one final full-size copy;
- destruction is explicit where the current subset can express it;
- failure returns a deterministic status or empty result;
- byte length and string encoding assumptions are documented;
- Stage 1 emits calls to the same ABI when building Stage 2.

The first compiler migration target is not only the final module string. It is
the measured selected-helper chain:

1. rendered helper accumulation;
2. LLVM instruction-record accumulation;
3. LLVM global-record accumulation;
4. function declaration accumulation;
5. final module serialization.

Streaming directly to a file or stdout is deferred until buffer-based ordering
and deterministic materialization are proven. A buffer is easier to compare,
validate, and reuse while Stage 1 is still stabilizing module assembly.

## Substrate Decision 2: Collection ABI Before Compiler Arrays

The current Array surface is not suitable for compiler-scale append workloads.
Its native representation carries count and storage but no capacity. Each
append allocates exactly the new size and copies the complete previous buffer.
Repeated append is therefore quadratic in copying and retained bytes.

Before Stage 1 migrates serialized records to typed arrays, the generic
collection substrate must define:

- count, capacity, and storage representation;
- geometric capacity growth;
- target-correct element size, stride, and alignment;
- deterministic bounds behavior for indexed reads and writes;
- explicit copy, alias, and mutation semantics;
- pass/return behavior;
- ownership and destruction behavior;
- safe arrays of mixed-layout constructs.

The preferred result is a reusable RangeCore/LLVM array-storage ABI, not a
RangeCompiler-only vector implemented in Swift.

If ownership is not complete, retaining old geometrically grown buffers inside
an explicitly scoped bootstrap allocation domain is temporarily acceptable:
the retained total remains linear. It is not acceptable to add `free` or
`realloc` while shallow aliases can still observe the old storage.

Required collection fixtures:

- repeated large append;
- count and indexed access;
- deterministic index failure;
- mixed-layout records such as pointer plus integer fields;
- arrays of compiler-shaped constructs;
- copy then mutate;
- pass to and return from functions;
- deterministic while-based iteration;
- mutation during iteration rejection or defined behavior.

## Substrate Decision 3: No Silent Reachable Placeholders

Placeholder removal starts before the broad lowering work.

The immediate change is fail-fast behavior:

- inventory every reachable helper;
- classify missing statement records, unsupported signatures, unsupported AST
  cases, and body-size exclusions;
- emit a precise Stage 1 diagnostic containing the function and reason;
- refuse to materialize a Stage 2 candidate while any reachable placeholder
  remains.

Later phases implement the missing lowering cases and remove the size cutoff,
but no intermediate artifact may silently substitute a default return.

## Substrate Decision 4: Defer A Compiler-Wide Arena

A single arena destroyed only after compilation does not reduce the current
peak: it preserves the same allocation lifetime until process exit.

Do not add a compiler-wide arena as the first memory fix. Consider phase-local
arenas only after the compiler has explicit phase boundaries and measurements
show that scratch values can be discarded safely between parsing, validation,
lowering, and rendering.

## Stage 1 Typed Representation Direction

Typed compiler records remain the destination:

```range
CompilerProgram.declarations: [CompilerTopLevelDeclaration]
CompilerBlock.statements: [CompilerStatement]
CompilerCall.arguments: [CompilerCallArgument]
CompilerLLVMFunction.blocks: [CompilerLLVMBasicBlock]
CompilerLLVMBasicBlock.instructions: [CompilerLLVMInstruction]
CompilerLLVMModule.functions: [CompilerLLVMFunction]
CompilerLLVMModule.globals: [CompilerLLVMGlobal]
```

Migrate one complete consumer chain at a time:

1. parser or lowerer produces typed records;
2. downstream validation and selection consume typed records;
3. rendering consumes typed records;
4. summaries remain output-only diagnostics;
5. delete the replaced string encoder, decoder, and summary parser.

Use typed constructs plus a small integer or string tag before generalized enum
lowering is ready. Do not block the first typed LLVM collection on final tagged
union design.

Source-backed slices remain desirable for tokens and identifiers:

```range
construct CompilerSourceSlice {
    let file: Int
    let start: Int
    let end: Int
}
```

Move source slices earlier only if measurement after the buffer and collection
slices shows substring/character allocation is the next dominant cost.

## Implementation Phases

### Phase 0: Preserve Evidence And Enforce Correctness

- Preserve the current chunk implementation and measured attempt.
- Add a short checkpoint report with command, elapsed time, peak RSS, exit
  status, failing phase, and missing helper list.
- Record selected, lowered, excluded, and placeholder helper counts.
- Replace reachable placeholder emission with a precise hard diagnostic.
- Preserve the body-size classification temporarily, but make it fail rather
  than generate a fake implementation.
- Keep the twelve newly identified helper bodies in the body inventory.
- Do not run another full Stage 2 gate in this phase.

Gate:

- the checkpoint report is reproducible;
- unsupported reachable helpers are listed deterministically;
- no code path can emit a silent reachable placeholder.

### Phase 1: Implement The Buffer ABI

- define the smallest free-function buffer ABI;
- implement geometric growth and materialization in generic runtime plumbing;
- add focused Stage 0 compile-and-run fixtures;
- add Stage 1 type recognition, ordinary-call lowering, and runtime declarations;
- add a Stage 1-produced native fixture;
- exercise append-string, append-int, materialize, destroy, and failure paths.

Gate:

- a Stage 1-produced fixture builds and verifies multi-megabyte deterministic
  output;
- measured growth is linear rather than quadratic;
- no RangeCompiler-specific logic exists in Stage 0.

### Phase 2: Migrate The Hot LLVM Output Chain

- Convert selected-helper rendered output to `TextBuffer`.
- Convert instruction and global accumulation to `TextBuffer`.
- Convert declaration and final module serialization to `TextBuffer`.
- Keep ordering and selection entirely in Range-authored code.
- Retain the chunk protocol as a fallback while measuring the new path.
- Compare byte-for-byte focused LLVM fixtures before and after migration.

Gate:

- focused selected-helper rendering completes in one process with documented
  bounded memory;
- the output parses as LLVM;
- existing focused emitted module text is equivalent;
- no migrated output chain performs repeated whole-output string concatenation.

### Phase 3: Implement The Generic Collection ABI

- define count/capacity/storage and target layout rules;
- define copy, alias, mutation, pass/return, and destruction behavior;
- implement geometric growth;
- add bounds handling;
- add the required mixed-layout and ownership fixtures;
- prove current ordinary Array examples continue to behave correctly.

Gate:

- repeated append has linear retained growth and amortized behavior;
- mixed-layout records use correct target stride;
- copy/mutation behavior is explicit and tested;
- invalid indices fail deterministically;
- no compiler-specific array runtime exists in Swift.

### Phase 4: Teach Stage 1 The Minimal Array Subset

Stage 1 already parses part of `[T]` type syntax. Complete the semantic and
lowering subset in this order:

1. classify array types and element types;
2. preserve the base and index expression in typed index records;
3. empty-array construction;
4. array literals needed by focused fixtures;
5. count;
6. indexed access and assignment;
7. append;
8. arrays of constructs;
9. pass and return arrays;
10. deterministic while-based iteration.

Do not begin broad compiler collection migration until the Stage 1-produced
native fixtures prove the needed operations.

Gate:

- Stage 1 compiles and runs all focused array fixtures through the generic ABI;
- negative fixtures diagnose unsupported or invalid operations;
- no source-specific Stage 0 special cases are needed.

### Phase 5: Convert Typed LLVM Collections

- Introduce typed arrays of LLVM functions, blocks, instructions, globals, and
  declarations.
- Make lowering append typed LLVM values rather than encoded record strings.
- Make rendering consume typed LLVM values through `TextBuffer`.
- Stop parsing LLVM instruction strings to recover operation fields.
- Delete replaced LLVM record encoders/decoders as each chain becomes complete.

Gate:

- focused LLVM fixtures emit from typed records;
- active LLVM consumers do not parse rendered LLVM or encoded instruction
  records;
- output remains deterministic and LLVM-valid.

### Phase 6: Convert Parser And Declaration Collections As Needed

- Re-measure source-set parsing, declaration construction, reachability, and
  type validation after Phases 2 and 5.
- Convert top-level declarations and block statements to typed arrays.
- Convert call arguments and expressions to typed records.
- Move reachability and type validation onto those structures.
- Introduce source slices if substring and character allocation remains a
  dominant measured cost.
- Keep summaries output-only.

Gate:

- semantic compiler collections are typed values;
- reachability and validation do not recover meaning by parsing summaries;
- source-set phases complete within a documented memory budget.

### Phase 7: Complete Reachable Lowering

- Remove the body-size cutoff.
- Implement every statement, expression, call, construct, and runtime case
  required by reachable RangeCompiler helpers.
- Keep fail-fast diagnostics for any unsupported reachable feature.
- Require zero placeholders and zero unresolved Range helper declarations.

Gate:

- every reachable helper has a real lowered definition;
- LLVM parsing and native linking report no unresolved Range helper symbols;
- focused compiler behavior fixtures pass.

### Phase 8: Single-Process Stage 2

- Disable chunk assembly for the primary gate without deleting fallback code.
- Parse, resolve, lower, render, and materialize Stage 2 in one Stage 1 process.
- Validate LLVM, link Stage 2, and run inventory plus normal compile checks.
- Record phase timings and peak RSS.

Gate:

- Stage 1 emits and links Stage 2 in one process;
- Stage 2 compiles and runs the focused smoke input;
- memory is bounded and documented;
- no reachable placeholder exists.

### Phase 9: Stage 2 To Stage 3

- Run Stage 2 against the identical deterministic compiler source set.
- Emit and link Stage 3.
- Compare source inventory, tokens, typed AST/declaration/type summaries, LLVM
  module structure, and observable compiler behavior.
- Prefer exact normalized LLVM equality when deterministic naming allows it.
- Explain and isolate any expected nondeterminism.

Gate:

- Stage 2 produces a linked Stage 3;
- Stage 2 and Stage 3 are equivalent for the supported compiler subset;
- both compile and run the same focused fixtures.

### Phase 10: Delete Bootstrap Scaffolding

After the single-process Stage 2 and Stage 3 gates pass, remove:

- `compilerNativeSourceSetLLVMChunkText<N>` and related directives;
- bounded 50/100/200/300 selection diagnostics;
- chunk assembly in SwiftBootstrap;
- serialized encoders/decoders with no remaining consumers;
- summary parsers used as semantic input;
- reachable-helper placeholder generation;
- replaced source-rescan compatibility paths;
- temporary checkpoint-only instrumentation.

Keep `scripts/range` as a thin compatibility wrapper if useful. Keep focused
diagnostics that are valuable to normal compiler development.

## Validation Discipline

Use focused gates while a long-running self-host gate is not active:

- `git diff --check`;
- focused `RangeScriptTests`;
- focused Stage 0 substrate fixtures;
- focused Stage 1-produced native fixtures;
- `scripts/range check-bootstrap-compiler` only after the focused slice is green;
- Stage 1 compiler gate after each complete vertical slice;
- Stage 2 gate only after the relevant phase gates are green;
- process sweep after every interruption.

For every full self-host attempt, record:

- exact command;
- commit or working-tree identity;
- elapsed time;
- peak RSS;
- exit status;
- last completed phase or chunk;
- selected/lowered/excluded/placeholder counts;
- artifact paths.

Never run concurrent Stage 2 or Stage 3 gates.

## Files Likely In Scope

Range-authored implementation:

- `RangeCompiler/Range/Programs/Compiler/Compiler.range`
- `RangeCompiler/Range/Programs/Compiler/CompilerCore.range`
- `RangeCompiler/Range/Programs/Compiler/Lexer.range`
- `RangeCompiler/Range/Core/`

Direct-blocker Stage 0 plumbing:

- `RangeCompiler/Sources/RangeEmission/LLVMModuleEmitter.swift`
- `RangeCompiler/Sources/SwiftBootstrap/SwiftBootstrap.swift`

Validation and command surfaces:

- `RangeCompiler/Tests/RangeCompilerTests/RangeScriptTests.swift`
- focused Range fixtures under the existing testing layout
- `scripts/range`

## Non-Goals

Do not block self-hosting on:

- the full declaration graph;
- the memory graph or reactivity graph;
- generalized macro self-hosting;
- concurrency;
- metatype set algebra;
- the complete standard library;
- final package and module distribution;
- a line-for-line port of every Swift compiler subsystem;
- final generalized ownership design beyond the explicit bootstrap ABI needed
  for safe buffer and collection behavior.

## Completion Criteria

This plan is complete when:

- Stage 1 emits Stage 2 in one process without chunk directives;
- peak memory is measured and bounded;
- retained string concatenation and substring histories are no longer dominant;
- semantic compiler collections are typed Range values;
- final LLVM text is produced only at serialization boundaries;
- every reachable compiler helper has a real implementation;
- Stage 2 emits and links Stage 3;
- Stage 2 and Stage 3 are equivalent for the supported subset;
- SwiftBootstrap owns invocation, temporary files, linking, and validation only;
- generic Stage 0 substrate additions contain no RangeCompiler-specific policy;
- temporary chunking, bounded-selection diagnostics, and placeholder scaffolding
  are deleted.

## Immediate Next Actions

1. Complete Phase 0 without changing Stage 0:
   - save the measured checkpoint;
   - add deterministic selected/lowered/excluded/placeholder counts;
   - replace silent reachable placeholders with hard diagnostics.
2. Do not run another full Stage 2 gate yet.
3. Implement the Phase 1 buffer fixture vertically through Stage 0 and Stage 1.
4. Migrate only the selected-helper output chain first and measure it before
   beginning the collection ABI.
