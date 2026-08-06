# Compiler Identity:Value Handoff

## Objective

Continue migrating Compiler V1 so each phase is modeled as an identified typed value connected through explicit graph edges:

```text
File -> Source -> Syntax -> Shape -> Behavior -> Compiled
```

The **Syntax -> Shape** slice and the **Shape -> Behavior** slice are complete; the next slice is **Behavior -> Compiled**.

## Current State

Latest commits:

```text
2157edf1 Promote bootstrap for frozen @syntax recipe shape
04d6a184 Verify V1 shape with frozen @syntax recipe
```

The Shape -> Behavior slice is committed with this handoff update.

Branch: `development`

Only unrelated user edits remain uncommitted:

```text
TODO.md
Website/src/routes/posts/requirement-and-provision/+page.svelte
```

Do not modify, stage, or revert those files.

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

Syntax reconciliation is reported separately:

```text
compilerV1SyntaxExecution
```

## Bootstrap

Promoted bootstrap:

```text
version=bootstrap-3ec2b7de1452
LLVM SHA-256=3ec2b7de14527ba19f2235b9faa603feda1306075c078ef5f2e9b1ee123c1a19
```

Promotion followed the canonical candidate/reproduction proof: candidate compiled from the accepted
compiler, reproduction compiled from the candidate with the same source; both LLVM and linked
executables were byte-identical before promotion.

## Verification

All passed:

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

`check-range-compiler-graph-revision` proves the bounded literal-edit invalidation (3 affected views:
Source, Behavior, Compiled) with the syntax-facts artifact rewritten to carry the new behavior product
while the syntax and shape node values stay reusable.

Do not run candidate-building checks concurrently. A concurrent graph/revision test run caused a shared candidate-build race:

```text
candidate build plan source count is 56, expected 30
```

Sequential reruns passed.

## Next Slice

Implement **Behavior -> Compiled**:

1. Reconcile the Compiled phase as an identified projection over the accepted Behavior value (it
   already projects the same frozen behavior text; give it the same projection treatment as
   Behavior received in this slice).
2. Prove Compiled identity stays stable across Source provenance-only edits.
3. Prove warm compilation reuses Compiled and its edge.
4. Prove failed candidates preserve accepted Compiled state.
5. Run all focused checks, fixed-point verification, and bootstrap promotion.
6. Commit only scoped compiler, test, script, and bootstrap files.

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
RangeCompiler/Sources/Compiler/Driver/CompilerV1Graph.range
RangeCompiler/Sources/Compiler/Driver/CompilerV1.range
scripts/compile-range-project
scripts/check-range-compiler-v1
scripts/check-range-compiler-graph
scripts/check-range-compiler-graph-revision
RangeCompiler/Bootstrap/RangeCompilerBootstrap.json
RangeCompiler/Bootstrap/RangeCompilerBootstrap.ll
RangeCompiler/Bootstrap/range
```

Key supporting files:

```text
RangeCompiler/Sources/Compiler/Syntax/CompilerParsing.range
RangeCompiler/Sources/Compiler/Syntax/CompilerFrontend.range
RangeCompiler/Sources/Compiler/Driver/CompilerCore.range
Testing/Syntax/Pass/V1SyntaxRecipeVerification.range
Testing/Syntax/Fail/V1SyntaxRecipeUnknownCapture.range
```
