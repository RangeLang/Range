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

---

# Session Addendum — July 25, 2026 (Claude)

Continues the work above. Progression advanced but is **not** at a fixed point,
and no seed has been promoted.

## Current blocker

```text
compilerError kind=invalidOwnedReturnSummary functionRow=2408
function=compilerCoreParseConstructDeclarationParts failureKind=proof
detail=407800314
```

Decoded: pathRow 6, root kind 1 (symbol), symbol ID 3, current state 1 (Live),
predecessor state 4 (Absent). Symbol 3 in that function is the alias-carrying
fallback token.

## Functions cleared this session

Reported order was `2378 → 2400 → 2408 → 1226 → 2391 → 2402 → 2408`. Note the
row number is a function-table index, not a progress counter; it is **not
monotonic** and a lower row does not mean regression.

## How to decode a proof detail

This was the single biggest time sink. Record it rather than re-deriving it.

- `Buffer<Int>` is **32-bit** (`rawBufferAppendInt`, stride 4). Any packed
  diagnostic above 2^31 is silently truncated. Do not widen the packing.
- For a real diagnostic, add a temporary `print(value: "...")` at the failure
  site. `print` is a runtime builtin usable anywhere in the compiler. This is
  minutes of work; integer archaeology is hours.
- Join failures from `CompilerBodyOwnership.range:4615` carry a **+1,700,000**
  offset added by the `failureStage` wrapper. Subtract it first, then decode:
  `400000000 + pathRow*1000000 + rootKind*100000 + rootID*100 + curr*10 + pred`.
  `rootID * 100` overflows into the rootKind field once rootID > 999, so a
  nonsensical rootKind means rootID is large.
- States: `0` Unknown, `1` Live, `2` Moved, `3` Consumed, `4` Absent.
  Root kinds: `1` Symbol, `2` Value.
- Alias failures now surface as `600000 + 10000 + code` (commit `c245e385`),
  where code is `1`, `1000+row`, `2000+row`, `3000+row`, or `4000+pathRow`.

## The two conflicting rules

A `??` fallback must satisfy both, and alias-carrying fallbacks currently
cannot:

| Fallback shape | Alias registration | Ownership join |
|---|---|---|
| Inlined into the `??` | **fails** if it constructs a `$source` alias | passes |
| Eager named local | passes | **fails** Live vs Absent |
| Named cursor + inlined token | **fails** | not reached |

Alias provenance is only recorded for **unconditionally constructed** values, so
moving a `$source`-carrying construction inside a `??` branch loses it. This is
why the general rule attempted in the earlier session broke
`compilerCoreParseFunctionParameterToken`.

**Rule to follow:** never inline a fallback whose construction carries
`$source`. Confirmed by experiment — restoring the eager form cleared
`compilerCoreParseMacroDeclarationParts`.

## Recommended next slice (small, unblocks the current failure)

`compilerFallbackToken` takes a cursor but reads only `cursor.index`. The cursor
is what drags in `$source`. Add a cursor-free variant:

```range
function compilerFallbackTokenAt(index: Int): RangeLexedToken {
    return RangeLexedToken(kind: .eof, start: index, end: index, text: String(""))
}
```

Then the alias-carrying sites become inlineable with no alias at all:

```range
let nameToken: RangeLexedToken(maybeName ?? compilerFallbackTokenAt(index: keyword.end))
```

This sidesteps both rules simultaneously. There are 12 such sites
(`CompilerParsing.range` 3, `CompilerFrontend.range` 9), currently in the eager
named form as `aliasFallbackToken*`.

## Recommended permanent fix (after a seed exists)

The lexer should be a **total function**. `lexNextRangeToken` returns `nil` for
two different reasons — end of source (`Lexer.range:124`) and an unrecognised
character (`Lexer.range:244`, `:255`) — and every caller collapses both into a
manufactured `.eof` token. `RangeTokenKind` already has `.eof` and `.unknown`.

Returning `RangeLexedToken` directly would:

- delete 225 `Optional<RangeLexedToken>` sites (60% of all optionals in the
  compiler) and all 101 `compilerFallbackToken` constructions;
- remove the dummy value entirely, so neither failing rule can apply;
- preserve *more* information than today, since `.unknown` stops being
  conflated with end-of-input;
- require no ownership-pass change.

This matches an idiom the compiler already uses elsewhere:
`compilerCoreMissingStatement`, `compilerCoreMissingExpression`, and
`compilerCoreMissingFunctionParameterTokenStep(found: false, ...)` are all total
values with a validity flag. The lexer is the outlier.

Remaining optionals after that change: `CompilerSourceRange` 60,
`CompilerExpression` 26, `CompilerTypeReference` 22, `CompilerStatement` 20.
Some have natural total values; `CompilerSourceRange` likely does not.

## Machinery that already exists — do not rebuild it

- `compilerBodyArenaOwnedPathRootEdgeExitsLexicalActivation`
  (`CompilerBodyOwnership.range:2589`) computes "this edge leaves the symbol's
  lexical region" and is wired into `BuildEdgeProjection` at `:2693`.
  Branch-exit expiry is **implemented**; the open question is why it does not
  fire for some symbol roots, not that it is missing.
- `compilerBodyArenaOwnedPathRefinesOptionalPayloadAbsent` (`:2601`) handles the
  `??` false edge for optional payloads.

## Process warnings

- **Commit one slice at a time.** ~110 fallback inlines were committed together
  with the prior checkpoint, so that batch cannot be bisected or reverted
  independently. Every later failure in those four files has ~110 candidate
  causes.
- **Snapshot before any bulk edit.** A scripted transform introduced the
  alias-in-branch defect, which stayed invisible until progression reached the
  affected function.
- **Verify scripted reverts by count.** An undo script over-matched and rewrote
  2 pre-existing sites; `git checkout <file>` restored them.
- **Standalone reproducers do not work.** Hand-written source bundles hit
  `representationSensitiveABICapabilityBlocked` on `Optional<T>` returns for
  both `RawBuffer` and `String`-carrying constructs, which the real build plan
  does not. A fast iteration loop needs to match the real build plan, which is
  its own task.
- Each `scripts/range compiler progression` run costs roughly 10 minutes.

## Repository state

- `HEAD` = `c245e385` on `development`; working tree clean.
- `913adda2` adds the CFG schedule action and MIR builder for the optional
  fallback branch, plus the one-use parser fallback inlines.
- `c245e385` surfaces binding-alias validation codes and restores the eager form
  for alias-carrying fallback tokens.
- The full validation ladder has **not** been rerun. Only `check-build-plan` and
  `compiler progression` were exercised this session.
