# Typed `@expand` Splice Validation Plan

This document captures the shortest bootstrap path for adding typed splice validation to `@expand` without pushing a large amount of new modeling into `NeatCore` yet.

## Goal

Keep the current:

- emitted code template model
- text rendering
- ordinary reparse of emitted Neat

But add one validation layer before rendering so the compiler can reject clearly invalid splice usage earlier.

Examples:

- `extension #(target.declaration.self) { ... }` should pass
- `function #(target.declaration.self)() -> ...` should fail before reparse

## Scope

This pass should stay mostly in Swift.

Do **not** try to:

- redesign `NeatCore` syntax ownership yet
- make every grammar position splice-aware
- replace the render-and-reparse architecture
- build a full fragment runtime

The purpose of this pass is to make the current system sharper and safer with minimal cost.

## Stage 1: Add A Small Swift-Side Category Enum

Introduce a bootstrap interpolation category enum in the macro expansion layer.

Suggested shape:

```swift
enum EmittedSyntaxKind {
    case declaration
    case expression
    case typeReference
    case nominalTypeReference
    case callableName
}
```

This is intentionally small and local to `@expand`.

## Stage 2: Make Splices Carry Expected Kind

Update the emitted code template model so a splice stores:

- the macro expression
- the expected syntax kind for the slot where it appeared

Suggested shape:

```swift
enum EmittedCodePart {
    case text(String)
    case splice(expression: Expression, expected: EmittedSyntaxKind)
}
```

This is the key structural change.

## Stage 3: Capture Expected Kind From Parser Context

Do not require manual annotations.

Instead, teach a few parser entry points to recognize `#(...)` and automatically tag it with the expected category for that parse position.

Suggested first helpers:

- `parseSpliceableNominalTypeReferenceNode(...)`
- `parseSpliceableTypeReferenceNode(...)`
- `parseSpliceableCallableName(...)`

Each helper should:

- parse ordinary syntax normally
- if it encounters `#(...)`, produce a typed splice tagged with that helper’s syntax kind

The parser already knows which slot it is parsing. Use that fact.

## Stage 4: Wire Only The Highest-Value Slots First

Start narrow.

First-pass slots:

1. extension target -> `nominalTypeReference`
2. conformance entry -> `nominalTypeReference`
3. callable return type -> `typeReference`
4. callable name -> `callableName`

Do **not** try to make every expression and statement position typed in the first pass.

## Stage 5: Add A Narrow Splice Result Classifier

During macro expansion, after binding substitution, classify what a splice expression can produce.

Examples:

- `target.declaration.self` -> `nominalTypeReference`
- `target.declaration.type` -> `typeReference`
- plain identifier/string used as a generated function name -> `callableName`

This classifier can stay intentionally bootstrap-specific.

It does not need to solve every possible macro expression yet.

## Stage 6: Validate Before Rendering

Before converting a splice to emitted text:

1. classify the substituted splice expression
2. compare actual kind with expected kind
3. reject mismatches immediately

Examples:

- expected `nominalTypeReference`, actual `nominalTypeReference` -> accept
- expected `callableName`, actual `nominalTypeReference` -> reject

This is the point of the pass.

## Stage 7: Preserve The Current Render-And-Reparse Pipeline

If validation succeeds:

- render splice to source text
- insert into emitted code
- reparse emitted code as ordinary Neat
- continue through ordinary validation

Do not change this architecture yet.

## Stage 8: Improve Diagnostics

Add explicit splice-category diagnostics.

Examples:

- `Interpolation in extension target position must produce a nominal type reference.`
- `Interpolation in function name position must produce a callable name.`

These should replace downstream generic parse failures when possible.

## Stage 9: Add Focused Fixture Coverage

Add one success and one failure fixture for each first-pass slot.

Minimum useful coverage:

- success: interpolated extension target
- success: interpolated callable return type
- failure: interpolated function name with `target.declaration.self`
- failure: invalid conformance splice kind

## Why This Is The Right Bootstrap

This path gives:

- earlier and clearer failures
- automatic slot awareness from parser context
- minimal disruption to the current `@expand` design
- no large `NeatCore` expansion yet

It also sets up the later move into `NeatCore` cleanly:

- today: Swift owns the slot/category bridge
- later: `NeatCore` can become the source of truth for those categories

## Follow-Up After This Pass

Once this works well, the next migration steps would be:

1. add `Declaration` to `NeatCore`
2. move more slot expectations into core-owned syntax metadata
3. reduce Swift-side ad hoc category mapping

But none of that is required to make typed `@expand` splice validation useful today.
