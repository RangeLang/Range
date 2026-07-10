# Range Authored Compiler Plan

This is the working plan for moving the compiler toward:

```text
Range source -> Range-authored AST -> Range-authored LLVM -> native RangeCompiler
```

Swift remains stage-zero bootstrap plumbing until the Range-authored compiler can
compile itself. It may invoke, build, link, and validate the compiler program,
but new compiler semantics should move into
`RangeCompiler/Range/Programs/Compiler`.

## Goal

Build a `RangeCompiler` program authored in Range that can load Range source,
parse it into structural AST records, validate the supported subset, lower that
typed AST directly to LLVM records, render LLVM text, and link a native compiler
binary. The self-host ladder is:

1. Stage 0: SwiftBootstrap builds the Range-authored compiler.
2. Stage 1: the produced RangeCompiler compiles the same RangeCompiler sources.
3. Stage 2: the Stage 1 compiler output is compared against the next compiler
   output closely enough to retire matching stage-zero branches.

## Current Baseline

- `SwiftBootstrap` is the trusted stage-zero compiler target.
- The active execution path is LLVM, `clang`, and a linked executable.
- `RangeCompiler/Range/Programs/Compiler` is the Range-authored compiler
  program.
- The Range compiler program has an entrypoint, lexer coverage, early parser
  checkpoints, AST summaries, type summaries, and first LLVM output checks.
- String IR should not come back as an alternate backend. Text emission is only
  the final rendering step for LLVM records.

## Phase 1: Source Loading And Program Shape

- Load all compiler source files in deterministic order.
- Preserve file identity, source text, byte offsets, and line/column mapping.
- Keep source loading independent from syntax meaning.
- Add diagnostics that can point back to file and span.
- Gate: a compiler run can list loaded files and emit stable source inventory
  records without consulting Swift parser semantics.

## Phase 2: Lexer Completion

- Keep the Range-authored lexer aligned with the Swift bootstrap lexer corpus.
- Cover identifiers, keywords, attributes, literals, comments, punctuation,
  operators, string escapes, and source spans.
- Make lexer output the parser input for compiler sources.
- Keep Swift lexer comparison tests only as stage-zero parity checks.
- Gate: the Range-authored lexer token stream matches the bootstrap stream for
  RangeCompiler sources and focused syntax fixtures.

## Phase 3: Structural Parser

- Parse declarations structurally before attaching type or graph semantics.
- Cover constructs, functions, parameters, attributes, `@main`, local
  declarations, blocks, and source body ranges.
- Parse statements: `let`, `state`, assignment, expression statements, return,
  if, while, break, and continue.
- Parse expressions: literals, names, calls, labels, member access, prefix,
  infix, grouping, optional/default operators, and constructor-shaped calls.
- Treat bare Swift-like statements as bootstrap compatibility input until
  Range-authored statement macro surfaces own them.
- Gate: parser tests assert AST records for the compiler program without
  source-rescanning recognizers.

## Phase 4: AST And Declaration Model

- Define Range-authored AST records for program, file, declaration, block,
  statement, expression, type reference, parameter, and attribute.
- Keep AST construction separate from LLVM lowering.
- Build a small declaration table from parsed AST records.
- Resolve names, local scopes, functions, parameters, and return types for the
  supported compiler subset.
- Do not require the full declaration graph, macro graph, or application graph
  before this structural subset is useful.
- Gate: RangeCompiler sources produce stable AST, declaration, and scope
  summaries from Range-authored code.

## Phase 5: Type Validation Subset

- Validate explicit function return types.
- Validate local declarations, assignment compatibility, branch return shape,
  builtin call signatures, and basic expression result types.
- Model required builtins as explicit declarations or runtime imports:
  command-line arguments, file I/O, strings, arrays, diagnostics, process/build
  hooks, and LLVM/runtime support.
- Avoid special-case semantic shortcuts such as matching one function name or
  one return literal. Add general type rules for the supported subset instead.
- Gate: invalid compiler-source fixtures fail with diagnostics from
  Range-authored validation records.

## Phase 6: Direct LLVM Records

- Lower typed AST directly into LLVM module, function, block, instruction,
  value, type, global, and declaration records.
- Render LLVM text only from those records.
- Support integer, bool, pointer/string, optional pointer-shaped bootstrap
  values, calls, returns, locals, branches, loops, and global strings.
- Keep runtime imports explicit in the module.
- Delete replaced source-string scanner and old string IR paths as soon as the
  AST-backed lowerer owns their cases.
- Gate: LLVM for the compiler program is emitted from AST records and no longer
  depends on source-rescanning recognizers.

## Phase 7: Native RangeCompiler Binary

- Have the RangeCompiler program compile Range source to LLVM text.
- Link the emitted LLVM with the required runtime support using `clang`.
- Keep SwiftBootstrap responsible only for invoking the compiler, materializing
  temporary files, linking, and test orchestration.
- Add a command that builds and runs the Stage 1 compiler against selected
  Range inputs.
- Gate: Stage 0 builds a native RangeCompiler that emits LLVM for the compiler
  program through the Range-authored path.

## Phase 8: Stage 1 To Stage 2

- Use the Stage 1 RangeCompiler to compile the same compiler sources.
- Compare loaded-source inventory, token summaries, AST summaries, declaration
  summaries, LLVM module shape, and linked execution behavior.
- Add `check-stage1-compiler` and `check-stage2-compiler` style gates when the
  pipeline is concrete enough.
- Retire stage-zero branches only after the equivalent Range-authored behavior
  is active and checked.
- Gate: Stage 1 can build a Stage 2 compiler artifact with explainable diffs or
  stable equivalence for the supported subset.

## Phase 9: Cleanup Rules

- Keep Swift as active generic bootstrap plumbing only.
- Delete unsupported Swift-owned compatibility paths once Range-authored
  surfaces replace them.
- Do not keep dead alternate emitters, placeholder backends, or source-rescan
  recognizers around after their AST-backed replacement lands.
- Keep `scripts/range` as a compatibility shim if useful, but avoid adding new
  compiler semantics to Bash.
- Keep docs aligned with the active path, not historical plans.

## Validation Gates

Run focused gates after each slice:

- `swift test --package-path RangeCompiler --filter RangeScriptTests`
- `scripts/range check-bootstrap-compiler`
- Focused Stage 1 checks as they are added.
- `git diff --check`
- Stale-reference sweeps for deleted emitters, parser fixtures, and old string
  IR names.
- Process sweeps when long-running compiler checks are interrupted.

## Fast Execution Plan

This is the implementation queue. Each slice should either remove a
source-rescan/string-summary dependency or produce a stronger Stage 1 artifact.

### Slice 1: Function Bodies Belong To Declarations

- Add parsed body statement records and statement summaries to function
  declaration records.
- Make function type summaries consume declaration-owned statement records.
- Make helper reachability consume declaration-owned statement records.
- Make helper LLVM lowering consume declaration-owned statement records.
- Gate: focused function AST/type/LLVM tests pass, and no helper path reparses
  `bodyStart`/`bodyEnd` source spans for function bodies.

### Slice 2: Structured Expression Records

- Add expression records for literals, identifiers, calls, call arguments,
  prefix, binary, member, and index expressions.
- Keep summaries only for debug/report output.
- Make call-argument traversal and called-function discovery consume expression
  records instead of parsing strings like `call(identifier(...))`.
- Gate: AST tests show stable expression records, and LLVM call lowering works
  without summary-string call parsing.

### Slice 3: AST-Owned Type Validation

- Validate local declarations, assignment compatibility, returns, branch
  conditions, loops, and calls from AST/declaration records.
- Add explicit builtin declarations or imports for command-line arguments, file
  reads, strings, arrays, diagnostics, process/build hooks, and runtime support.
- Remove one-off return/type shortcuts as general rules cover them.
- Gate: valid compiler-source fixtures report matching types, invalid fixtures
  produce Range-authored diagnostics, and builtin signatures are visible in the
  declaration/type model.

### Slice 4: Direct LLVM Records Only

- Lower typed AST into LLVM module, function, block, instruction, value, type,
  global, and declaration records.
- Keep text rendering as final serialization only.
- Remove lowerer code that depends on source substring recognition or encoded
  expression summaries once record lowering owns the case.
- Gate: `compilerLLVMText` and `compilerSourceSetLLVMText` emit from LLVM
  records, and stale-reference sweeps do not find old string IR emitter paths.

### Slice 5: Real RangeCompiler Source-Set Artifact

- Load all `RangeCompiler/Range/Programs/Compiler` files into one deterministic
  source-set program.
- Run source inventory, lexing, parsing, declarations, type validation, and LLVM
  lowering on that program.
- Emit raw combined LLVM text as the primary artifact, not a report envelope.
- Gate: `compilerSourceSetLLVMText` emits raw LLVM for the compiler source set
  with `@main`, selected helper definitions, declarations, globals, and runtime
  imports.

### Slice 6: Link Native Stage 1

- Keep SwiftBootstrap limited to invoking the Range compiler, materializing
  `.ll` files, invoking `clang`, linking runtime support, and running checks.
- Link the source-set LLVM into a native Stage 1 `RangeCompiler` binary.
- Gate: Stage 0 builds a native Stage 1 compiler and the binary can compile
  selected Range inputs through the Range-authored path.

### Slice 7: Stage 1 Produces Stage 2 Candidate

- Run Stage 1 against the same RangeCompiler sources.
- Compare source inventory, token summaries, AST summaries, declaration/type
  summaries, LLVM module shape, and linked behavior against Stage 0 output.
- Add explicit `check-stage2-compiler` style gates once the artifact shape is
  stable enough.
- Gate: Stage 1 produces a Stage 2 candidate artifact with stable equivalence
  or explainable diffs.

### Slice 8: Delete Replaced Paths

- Delete old string IR branches, source-rescan recognizers, unsupported Swift
  compatibility paths, and stale docs/tests after their AST-backed replacement
  is active and checked.
- Keep `scripts/range` as compatibility wrapper only if useful.
- Gate: stale-reference sweeps find no active references to removed emitters,
  parser fixtures, or unsupported bootstrap branches.
