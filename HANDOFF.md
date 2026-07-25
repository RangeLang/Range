# Codex Handoff — July 25, 2026

## Goal

Reach a trustworthy self-hosted compiler fixed point after the recent
String/Buffer, identity-layout, ownership, and parser-source changes. Do not
promote or rewrite the accepted seed until `scripts/range compiler progression`
passes and produces the exact fixed-point artifacts expected by the seed
workflow.

Range assignment syntax remains:

```range
cursor: compilerCursorAdvance(cursor: cursor, token: token)
```

No source-level `=` assignment syntax was intentionally reintroduced.
`Assignment` is only the compiler's internal syntax-node name.

## Current state

The worktree is intentionally uncommitted and contains a broad in-progress
compiler checkpoint. The accepted seed has **not** been updated.

The latest authoritative command was:

```sh
scripts/range compiler progression
```

It advanced through the earlier ownership failures and currently stops at:

```text
compilerError kind=invalidOwnedReturnSummary functionRow=2378 function=compilerCoreParseTypeReferenceScanningUntil failureKind=proof detail=412800414
```

This is the next active boundary.

## Work completed in this checkpoint

- Changed compiler source/cursor relationships to binding-backed String views
  and updated direct cursor construction to pass bindings such as `$source`.
- Added nested binding-alias provenance and propagation for constructs that
  carry aliases inside stored members.
- Extended aggregate moves, return summaries, and ownership validation to
  understand nested alias leaves.
- Added tracked Optional payload/result ownership paths and branch-aware
  lowering for `payload ?? fallback`.
- Added automatic destruction facts and terminal cleanup for owned mutable
  String storage while retaining literal/non-owning String views.
- Added recursive return-summary cycle handling for reachable construct-return
  dependencies.
- Replaced a recursive String-rendering path with an iterative implementation.
- Cleaned up LLVM entry lowering so owned aggregate moves and branch merges are
  emitted once.
- Improved ownership diagnostics so failures expose the exact path, root,
  state, and predecessor state rather than a generic proof failure.
- Removed several eager parser fallback locals by constructing their fallback
  token directly inside `??`.

The broad modified-file set currently includes:

- `RangeCompiler/Sources/Compiler/Body/CompilerBodyCFG.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyMIR.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyModel.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyOwnership.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyParsing.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyTypes.range`
- `RangeCompiler/Sources/Compiler/Driver/CompilerCore.range`
- `RangeCompiler/Sources/Compiler/Driver/CompilerSources.range`
- `RangeCompiler/Sources/Compiler/Driver/CompilerTextSupport.range`
- `RangeCompiler/Sources/Compiler/LLVM/CompilerBodyLLVM.range`
- `RangeCompiler/Sources/Compiler/LLVM/CompilerLLVMPlan.range`
- `RangeCompiler/Sources/Compiler/Syntax/CompilerFrontend.range`
- `RangeCompiler/Sources/Compiler/Syntax/CompilerParsing.range`
- `RangeCompiler/Sources/Core/System/Process.range`
- `TODO.md`
- `MILESTONES.md`

Preserve these edits and inspect their diffs before making overlapping changes.

## Diagnostics already cleared

Progression initially stopped at:

```text
functionRow=1216
function=compilerCoreFindMainAttributeToken
detail=407800314
```

The cause was an eagerly created named fallback:

```range
let fallback: RangeLexedToken(compilerFallbackToken(cursor: cursor))
let token: RangeLexedToken(maybeToken ?? fallback)
```

The fallback was live on the optional-present edge and moved on the fallback
edge, so the ownership join saw incompatible states. It is now branch-local:

```range
let token: RangeLexedToken(
    maybeToken ?? compilerFallbackToken(cursor: cursor)
)
```

Progression then exposed and cleared the same pattern in:

- `compilerCoreParseMacroNameAfterKeyword`
- `compilerCoreParseDeclarationNameAfterKeyword`
- `compilerCoreParseFunctionNameAfterKeyword`
- `compilerCoreParseAngleRangeAfterName`

An attempted general rule that consumed an unselected named `let` fallback was
reverted. It broke `compilerCoreParseFunctionParameterToken`, which legitimately
reuses `colonFallback`. Keep the distinction:

- an inline fallback expression is a branch-local temporary;
- a named immutable value remains reusable and must not be silently consumed.

A speculative loop-backedge lexical-lifetime special case was also reverted.
The original row-1216 failure was optional-coalescing ownership, not loop
ownership.

## Exact next slice

Open:

```text
RangeCompiler/Sources/Compiler/Syntax/CompilerParsing.range
```

The immediate failing code is in
`compilerCoreParseTypeReferenceScanningUntil`:

```range
let tokenFallback: RangeLexedToken(
    compilerFallbackToken(cursor: scanState.cursor)
)
let token: RangeLexedToken(maybeToken ?? tokenFallback)
```

Make the fallback branch-local:

```range
let token: RangeLexedToken(
    maybeToken ?? compilerFallbackToken(cursor: scanState.cursor)
)
```

Then review the neighboring type-reference and balanced-range helpers for the
same one-use eager fallback pattern. Do not mechanically inline a fallback that
is used more than once; `colonFallback` in
`compilerCoreParseFunctionParameterToken` is the known counterexample.

After the bounded edit, run:

```sh
scripts/range check-build-plan
scripts/range compiler progression
```

If progression advances, continue from the newly reported exact function and
proof detail. Do not seed merely because an intermediate function moves
forward.

## Validation evidence

Passed during the latest slice:

```text
scripts/range check-build-plan
checkpoint build-plan:complete: pass
```

Three progression runs demonstrated forward movement:

1. row 1216 — `compilerCoreFindMainAttributeToken`
2. row 2396 — `compilerCoreParseMacroNameAfterKeyword`
3. row 2378 — `compilerCoreParseTypeReferenceScanningUntil` (current)

The complete validation ladder has not been rerun on the present worktree.
After progression reaches fixed point, run the ladder in `AGENTS.md` from the
narrowest relevant gate through:

```sh
scripts/range check-build-plan
scripts/range check-root-value --controls
scripts/range check-compiler-smoke
scripts/range check-compiler-candidate
scripts/range check-stage2-compiler
scripts/range compiler progression
```

Only after all required gates and exact artifact comparison pass should the
accepted seed be promoted.
