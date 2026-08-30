# Compiler Identity:Value Handoff

## Objective

Continue migrating Compiler V1 so each phase is modeled as an identified typed value connected through explicit graph edges:

```text
File -> Source -> Syntax -> Shape -> Behavior -> Compiled
```

The **Syntax -> Shape**, **Shape -> Behavior**, and **Behavior -> Compiled** slices are complete: every phase is now an identified projection over the previous one, and the identity chain is fully migrated.

## Current State

Latest commits (pushed to `development`):

```text
657e0089 Rewrite requirement-and-provision post around macros
9b6d5dea Mark homepage re-measure task complete
022ebd76 Document V1 compiled frozen lowering projection
8610b8f1 Promote bootstrap for frozen lowering compiled
c12e3f6e Verify V1 compiled as frozen behavior projection
ac677b44 Promote bootstrap for frozen lowering behavior
b3c18c5e Verify V1 behavior as frozen lowering projection
```

The Behavior -> Compiled slice is committed with this handoff update, followed by the unrelated
Website post and TODO edits, which were also committed and pushed. The working tree is clean.

Branch: `development`

Note: the GitHub remote reported that this repository has moved to
`https://github.com/RangeLang/Range.git`; the current push still succeeded against the old URL.

## Completed Work

### File -> Source

Commit:

```text
a7409c21 Model V1 source as identified graph values
```

Implemented:

- Identified File and Source values.
- Stable File and Source identities.
- Explicit File -> Source edge.
- Stable relationship identity.
- Source insert/reuse/update/delete classification.
- Inspection output for entities, edge, and Source delta.

### Source -> Syntax

Commit:

```text
c3a5d40d Model V1 syntax as identified graph values
```

Implemented:

- `CompilerV1SyntaxDelta`.
- Stable Syntax identity derived from Source identity.
- Explicit Source -> Syntax edge.
- Stable Source -> Syntax relationship identity.
- Syntax value fingerprint reconciliation.
- Syntax persistence in Compiler V1 execution state.
- Syntax entity, edge, and delta inspection output.
- Cold insert, warm reuse, and update reporting.
- Legacy version-1 execution compatibility for graph-cache migration.

### Syntax -> Shape

Commits:

```text
04d6a184 Verify V1 shape with frozen @syntax recipe
2157edf1 Promote bootstrap for frozen @syntax recipe shape
```

Shape is the **`@syntax` macro verification product (recipe)**, computed and frozen at capture time:

- `compilerV1SyntaxFacts` gained `snapshotEnd: Int` and `recipe: String`.
- `compilerV1SyntaxFactsCapture` runs `compilerMacroFinalizeApplications(tables:)` and
  `compilerSyntaxRecipeRender(tables:)` after typed capture; the recipe text is frozen in the facts.
- Encode was `version=2` with 16 header fields and a payload of two sections (snapshot, recipe).
- Integrity recomputed the shape fingerprint from the recipe text
  (`appendInt(syntaxIdentity, 3)`, tag 12).
- `compilerV1Shape` projected the recipe as its `snapshot` value when integrity holds.
- Facts consumers surfaced failure via `compilerV1SyntaxFactsErrorMessage`.

Fixtures added:

```text
Testing/Syntax/Pass/V1SyntaxRecipeVerification.range
Testing/Syntax/Fail/V1SyntaxRecipeUnknownCapture.range
```

### Shape -> Behavior

Uncommitted candidate became the accepted compiler (see Bootstrap below).

Behavior no longer recaptures Source. The full frontend pipeline (declaration capture, main-root
capture, macro finalize, macro link, and LLVM lowering) runs **once** at capture time and freezes the
LLVM lowering text in the facts; Behavior is now a pure projection of those facts:

- `compilerV1SyntaxFacts` gained `behaviorIdentity: CompilerIdentity`, `behavior:
  CompilerValueFingerprint`, and `behaviorText: String`.
- Capture runs `compilerMacroLink(tables: tables)` (which first finalizes applications; finalize is
  idempotent) and then `compilerNativeSourceSetLLVMTextForLinkedTables(...)`; the emitted LLVM text is
  frozen as `behaviorText`. Macro diagnostics surface as `invalidTypedBehaviorSnapshot`.
- Behavior identity is `appendInt(shapeIdentity, 4)`; Behavior product is tag 13 over the frozen
  behavior text (the identity chain `File -> Source(1) -> Syntax(2) -> Shape(3) -> Behavior(4) ->
  Compiled(5)` is unchanged).
- `compilerV1Behavior(facts:shape:before:)` is a projection: it reads `behaviorText` from the facts
  and produces the behavior snapshot and fingerprint without recapturing Source or re-linking.
- `compilerV1Compile` still checks `behavior.input == shape.after` (identity of the Shape product)
  before projecting the same behavior text as the Compiled product (tag 14).
- Encode is now `version=3` with 21 header fields ending in `bytes=`, `recipeBytes=`,
  `behaviorIdentityFirst/Second=`, `behaviorFirst/Second=`, `behaviorBytes=`; the payload has three
  sections: snapshot, recipe, behavior text.
- Decode validates the 21-field header and exact section bounds (`behaviorStart + behaviorBytes ==
  stringLength`).
- Integrity recomputes syntax (tag 16), shape (tag 12), and behavior (tag 13) fingerprints.
- Cold compile now runs the frontend once (`frontend x 1`) instead of `frontend x 2`.

Facts format remains free to change: `scripts/check-range-compiler-v1` pins only the function
signatures/projection lines; the graph-revision reducer parses header fields by name and byte-compares
the projected shape payload.

Graph-revision behavior on a literal-value edit is now:

- Source, Behavior, and Compiled phases derive new values; Syntax and Shape node values are reused
  (their fingerprints are unchanged) — the bounded invalidation frontier stays at 3 affected views.
- The syntax-facts **artifact** is rewritten because it now freezes the behavior product, so the
  graph-revision gate asserts the rewritten facts preserve the syntax/shape values while the behavior
  fingerprint changes, instead of asserting the artifact stays byte-identical.

### Behavior -> Compiled

Commits:

```text
c12e3f6e Verify V1 compiled as frozen behavior projection
8610b8f1 Promote bootstrap for frozen lowering compiled
```

Compiled is now the same identified projection over the accepted Behavior value that Behavior is over
Shape: it consumes Behavior's retained frozen lowering text and pins the product to a native snapshot,
with no source recapture, no re-link, and no second lowering pass.

- `compilerV1NativeCompiledSnapshot(identity:output:)` produces the `compilerV1Compiled\tvalid=true\tproduct=`
  line (tag 14), mirroring `compilerV1NativeBehaviorSnapshot` (tag 13).
- `CompilerV1CompiledDelta` gained a `snapshot` field; `compilerV1Compile` projects it from the same
  tag-14 product it already fingerprints, and the mismatch path carries the error text as its snapshot.
- `compilerV1CompiledExecutionReport` and `compilerV1BehaviorExecutionReport` reconcile the last two
  phases in the cold/updated paths, and the unchanged-reuse path now reports
  `compilerV1BehaviorExecution\toperation=reuse` and `compilerV1CompiledExecution\toperation=reuse`
  alongside the Syntax/Shape reuse lines.
- `inspect-v1` prints the compiled native snapshot after the Compiled delta.

Proofs added:

- Behavior and Compiled identities stay stable across Source provenance-only edits, and their input
  edges (Shape -> Behavior, Behavior -> Compiled) stay stable; Shape/Behavior and Behavior/Compiled
  identities remain distinct.
- Warm compilation reuses Compiled and its edge (explicit `operation=reuse` line plus the unchanged
  execution and LLVM hashes).
- Failed candidates preserve the accepted Behavior and Compiled state in the execution record.
- The literal-edit graph-revision proof now also asserts the compiled product changes while the
  syntax and shape node values stay reusable (still 3 affected views).

## Schemas

Compiler execution state is now:

```text
compilerV1Execution version=2
```

It persists:

- File identity
- Source fingerprint
- Syntax fingerprint
- Shape fingerprint
- Behavior fingerprint
- Compiled fingerprint

Syntax facts are now:

```text
compilerV1SyntaxFacts version=3
```

They persist:

- Syntax identity
- Source -> Syntax edge source identity
- Source -> Syntax relationship identity
- Syntax value fingerprint
- Shape identity
- Shape value fingerprint
- Behavior identity
- Behavior value fingerprint
- Typed syntax snapshot and `bytes` (byte length of the snapshot section)
- Recipe text (the `@syntax` verification product) and `recipeBytes`
- Behavior text (the frozen LLVM lowering) and `behaviorBytes`

Decoded Syntax facts retain encoded storage plus `snapshotStart`; `compilerV1SyntaxFactsSnapshot`
exposes the actual Syntax value, `compilerV1SyntaxFactsRecipe` exposes the Shape recipe, and
`compilerV1SyntaxFactsBehavior` exposes the Behavior product text.

Compiled is a `CompilerV1CompiledDelta` (identity, input, before, after, snapshot, output) where
`snapshot` pins the tag-14 product and `output` is Behavior's retained frozen lowering text.

Syntax reconciliation is reported separately:

```text
compilerV1SyntaxExecution
```

Behavior and Compiled reconciliation are reported as:

```text
compilerV1BehaviorExecution
compilerV1CompiledExecution
```

## Bootstrap

Promoted bootstrap:

```text
version=bootstrap-d93620129fe2
LLVM SHA-256=d93620129fe282e88ac3be5cfdff5588efe08cf0c5dd2e879aea4d9a399d9bce
executable SHA-256=ea36db743068412ad827225da9f5aaa5fac1609b7c6e9c4ec6d85c62af425a8b
```

Promotion followed the canonical candidate/reproduction proof: candidate compiled from the accepted
compiler, reproduction compiled from the candidate with the same source; both LLVM and linked
executables were byte-identical before promotion (`candidate_reproduction_llvm=byte-identical`,
`candidate_reproduction_executable=byte-identical`, `candidate_fixed_point=pass`).

## Verification

All passed before and after promotion (rerun sequentially against the new accepted bootstrap):

```text
scripts/range check-compiler-v1
scripts/range check-compiler-graph
scripts/range check-compiler-graph-revision
```

`check-range-compiler-v1` pins the Shape -> Behavior projection lines:

```text
snapshot: compilerV1NativeBehaviorSnapshot(identity: identity, output: behaviorText)
function compilerV1Behavior(facts: CompilerV1SyntaxFacts, shape: CompilerV1ShapeDelta, before: CompilerValueFingerprint)
let behaviorText: String(compilerV1SyntaxFactsBehavior(facts: facts))
behaviorText: compilerNativeSourceSetLLVMTextForLinkedTables(source: source.source.value, declarationTables: tables)
compilerMacroLink(tables: tables)
```

and the Behavior -> Compiled projection lines:

```text
function compilerV1Compile(shape: CompilerV1ShapeDelta, behavior: CompilerV1BehaviorDelta, before: CompilerValueFingerprint)
let output: String("\(behavior.compiledOutput)")
snapshot: compilerV1NativeCompiledSnapshot(identity: identity, output: output)
```

`check-range-compiler-graph-revision` proves the bounded literal-edit invalidation (3 affected views:
Source, Behavior, Compiled) with the syntax-facts artifact rewritten to carry the new behavior product
while the syntax and shape node values stay reusable.

Do not run candidate-building checks concurrently. A concurrent graph/revision test run caused a shared candidate-build race:

```text
candidate build plan source count is 56, expected 30
```

Sequential reruns passed.

## Next Slice

The identity chain `File -> Source -> Syntax -> Shape -> Behavior -> Compiled` is complete. Every
phase is an identified projection over the previous one, and the cold V1 path runs the frontend once.

The next concrete slice is to wire the **per-function artifact cache** into the V1 graph cold path so
a fingerprint-matched Behavior skips the effects/emission region:

1. Make the V1 capture/resume flow emit and consume `// range-function-artifact-input/output`
   directives (the mechanism `check-range-compiler-v1`'s closed-Behavior reuse proof exercises) so a
   full project compile that matches the frozen Behavior fingerprint bypasses `functionEffects`,
   `abiComponents`, and `functionEmission` entirely.
2. Prove on the full project that a matched compile reuses the 18MB artifact file byte-identically
   (measured: 548s -> 1.6s) and that a single-function edit reuses the emission text while still
   re-deriving the whole-graph `functionEffects` closure (measured: 548s -> 207s).
3. Decide whether `functionEffects` should become a per-function reusable product; it is currently
   the largest single remaining blocker (159s) after emission text reuse.
4. Run all focused checks, fixed-point verification, and bootstrap promotion.
5. Commit only scoped compiler, test, script, and bootstrap files.

This is deliberately separate from the identity-chain organization; the graph and facts schemas are
stable enough to support the artifact path without another phase-model change.

## Existing Shape Model

Current Shape declaration:

```range
construct CompilerV1ShapeDelta {
    let identity: CompilerIdentity
    let before: CompilerValueFingerprint
    let after: CompilerValueFingerprint
    let snapshot: String
}
```

Current production path:

```range
function compilerV1Shape(
    facts: CompilerV1SyntaxFacts,
    before: CompilerValueFingerprint
): CompilerV1ShapeDelta
```

Shape:

- Uses identity derived from Syntax.
- Projects `snapshot` = the `@syntax` recipe verification frozen in the facts (fallback to the recipe
  error text or `invalidCompilerV1SyntaxFacts`).
- Has persisted before/after fingerprints.
- Can be produced without recapturing Source (`compilerV1ShapeOnly`).

## Existing Behavior Model

Current Behavior declaration:

```range
construct CompilerV1BehaviorDelta {
    let identity: CompilerIdentity
    let input: CompilerValueFingerprint
    let before: CompilerValueFingerprint
    let after: CompilerValueFingerprint
    let snapshot: String
    let compiledOutput: String
}
```

Current production path:

```range
function compilerV1Behavior(
    facts: CompilerV1SyntaxFacts,
    shape: CompilerV1ShapeDelta,
    before: CompilerValueFingerprint
): CompilerV1BehaviorDelta
```

Behavior:

- Uses identity derived from Shape (`appendInt(shapeIdentity, 4)`).
- Reads the frozen LLVM lowering text from the facts via `compilerV1SyntaxFactsBehavior`; no Source
  recapture or macro re-link.
- Produces `after` = tag 13 over the behavior text, with `compiledOutput` carrying the same text.

## Relevant Files

```text
Language/Sources/Compiler/Driver/CompilerV1Graph.range
Language/Sources/Compiler/Driver/CompilerV1.range
scripts/compile-range-project
scripts/check-range-compiler-v1
scripts/check-range-compiler-graph
scripts/check-range-compiler-graph-revision
Language/Bootstrap/RangeCompilerBootstrap.json
Language/Bootstrap/RangeCompilerBootstrap.ll
Language/Bootstrap/range
```

Key supporting files:

```text
Language/Sources/Compiler/Syntax/CompilerParsing.range
Language/Sources/Compiler/Syntax/CompilerFrontend.range
Language/Sources/Compiler/Driver/CompilerCore.range
Testing/Syntax/Pass/V1SyntaxRecipeVerification.range
Testing/Syntax/Fail/V1SyntaxRecipeUnknownCapture.range
```
