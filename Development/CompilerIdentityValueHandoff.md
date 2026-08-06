# Compiler Identity:Value Handoff

## Objective

Continue migrating Compiler V1 so each phase is modeled as an identified typed value connected through explicit graph edges:

```text
File -> Source -> Syntax -> Shape -> Behavior -> Compiled
```

The **Syntax -> Shape** slice is complete; the next slice is **Shape -> Behavior** (drop the transitional Source recapture).

## Current State

Latest commit:

```text
c3a5d40d Model V1 syntax as identified graph values
```

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

Identity chain now uses:

```text
File
  -> Source: append 1
  -> Syntax: append 2
  -> Shape: append 3
  -> Behavior: append 4
  -> Compiled: append 5
```

### Syntax -> Shape

Uncommitted (candidate cache key `a165ced9fa73e89e...`, 30 sources).

Shape is now the **`@syntax` macro verification product (recipe)**, computed and frozen at capture time:

- `compilerV1SyntaxFacts` gained `snapshotEnd: Int` and `recipe: String`.
- `compilerV1SyntaxFactsCapture` runs `compilerMacroFinalizeApplications(tables:)` and
  `compilerSyntaxRecipeRender(tables:)` after typed capture; the recipe text is frozen in the facts.
- `compilerV1SyntaxFactsRecipe` exposes the recipe field (ordinal 9).
- `compilerV1SyntaxFactsErrorMessage` reports the recipe error text when the recipe is a
  `compilerError` (surface failure), otherwise the typed-syntax snapshot.
- Encode is now `version=2` with 16 header fields ending in `bytes=` and `recipeBytes=`, and a
  payload of exactly two sections separated by a double newline: snapshot, then recipe.
- Decode parses the 16-field header, derives `snapshotEnd`/`recipeStart` from the exact lengths,
  and returns the recipe as a substring of the encoded bytes.
- Integrity now recomputes the shape fingerprint from the **recipe** text
  (`appendInt(syntaxIdentity, 3)`, tag 12, relationship tag 18).
- `compilerV1Shape` projects the recipe as its `snapshot` value when integrity holds, and falls back
  to the recipe error text otherwise (or `compilerError\tkind=invalidCompilerV1SyntaxFacts`).
- `inspect-v1` prints the typed-syntax snapshot after the `phase=syntax` delta and the shape product
  after the `phase=shape` delta.
- All facts consumers (`capture-syntax-v1`, `compile-shape`, `project-shape-v1`, decode, integrity)
  surface failure via `compilerV1SyntaxFactsErrorMessage`.

Facts format remains free to change: `scripts/check-range-compiler-v1` pins only the function
signature `function compilerV1SyntaxFactsCapture(source: CompilerV1SourceDelta)` and the projection
line `snapshot: recipe`; other consumers parse header fields by name.

New fixtures:

```text
Testing/Syntax/Pass/V1SyntaxRecipeVerification.range
Testing/Syntax/Fail/V1SyntaxRecipeUnknownCapture.range
```

Scalar stored member types only: the V1 light capture rejects generic stored member types such as
`Array<String>` / `Array<Int>` with `invalidTypedSyntaxSnapshot` (pre-existing limitation).

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
compilerV1SyntaxFacts version=2
```

They persist:

- Syntax identity
- Source -> Syntax edge source identity
- Source -> Syntax relationship identity
- Syntax value fingerprint
- Shape identity
- Shape value fingerprint
- Typed syntax snapshot
- `snapshotEnd` (byte length of the snapshot section)
- Recipe text (the `@syntax` verification product) and its `recipeBytes`

Decoded Syntax facts retain encoded storage plus `snapshotStart`; `compilerV1SyntaxFactsSnapshot`
exposes the actual Syntax value and `compilerV1SyntaxFactsRecipe` exposes the Shape recipe.

Syntax reconciliation is reported separately:

```text
compilerV1SyntaxExecution
```

This separate record avoids exceeding current compiler owned-aggregate lowering limits in the existing execution report function.

## Bootstrap

Promoted bootstrap:

```text
version=bootstrap-23edc6ec8cd7
LLVM SHA-256=23edc6ec8cd725f7f5bb7741bfc4b0c1ef5b14dd37a3be8ef6659e59775f9bf1
executable SHA-256=a08c13ef3386eac68d069db55eaa6357d6e252afcbafb32d0cd5e7161498836a
```

## Verification

All passed:

```text
scripts/range check-compiler-v1
scripts/range check-compiler-graph
scripts/range check-compiler-graph-revision
scripts/range check-compiler-candidate
scripts/verify-range-compiler
```

Candidate and reproduction LLVM and executables were byte-identical.

The uncommitted Syntax -> Shape checkpoint passes the focused gates against the working candidate
(cache key `a165ced9fa73e89e...`):

```text
scripts/check-range-compiler-v1
scripts/check-range-compiler-graph
scripts/check-range-compiler-graph-revision
```

`check-range-compiler-v1` adds a shape-value stability proof (the recipe product is byte-stable
under Source provenance-only edits) and an `@syntax` verification proof: the pass fixture freezes
`recipeCount=1` with resolved captures, the fail fixture rejects at the recipe boundary with
`compilerError kind=syntaxRecipeUnknownCapture` (exit 65) on both `capture-syntax-v1` and
`inspect-v1`. Bootstrap promotion is deferred to a deliberate stable checkpoint.

Do not run candidate-building checks concurrently. A concurrent graph/revision test run caused a shared candidate-build race reporting:

```text
candidate build plan source count is 56, expected 30
```

Sequential reruns passed.

## Next Slice

Implement **Shape -> Behavior**: remove Behavior's transitional Source recapture.

1. Persist enough Syntax tables (declaration graph, macro applications) in the frozen facts so
   Behavior consumes the accepted Syntax/Shape products directly instead of recreating
   `CompilerSyntaxTables` from Source.
2. Route Behavior through a `compilerV1Shape` value that holds the recipe verification product.
3. Prove Behavior identity stays stable across Source provenance-only edits (same Shape product).
4. Prove warm compilation reuses Behavior and its edge.
5. Prove failed candidates preserve accepted Behavior state.
6. Run all focused checks, fixed-point verification, and bootstrap promotion.
7. Commit only scoped compiler, test, script, and bootstrap files.

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

Shape now:

- Uses identity derived from Syntax.
- Projects `snapshot` = the `@syntax` recipe verification frozen in the facts (fallback to the recipe
  error text or `invalidCompilerV1SyntaxFacts`).
- Has persisted before/after fingerprints.
- Can be produced without recapturing Source (`compilerV1ShapeOnly`).

The next change is to make Behavior consume this accepted Shape product directly, not to redesign
Shape parsing.

## Later Boundary

Behavior must stop recapturing Source:

Currently `compilerV1Behavior` still:

- Creates `CompilerSyntaxTables` from Source.
- Repeats declaration and main capture.
- Links macros from the recreated tables.

The next cutover should persist and reload sufficient Syntax tables so Behavior consumes accepted
Syntax/Shape products directly, with Shape's frozen recipe as the verification boundary.

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
