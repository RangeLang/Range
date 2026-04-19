# Graph Validation Plan

## Objective

Split validation by graph pass instead of keeping one large mixed validator.

The intended rule is:

- each graph layer validates the facts it owns
- each graph layer also validates the boundary between what it depends on and
  what it adds
- `CompiledProgramValidator` should become an orchestrator, not the long-term
  home of every validation rule

This fits the current graph architecture:

- `ProgramGraph`
- `DeclarationGraph`
- `ApplicationGraph`
- later `MemoryGraph`
- later `ReactivityGraph`

## Current State

Today, validation is still centralized in
[CompiledProgramValidator.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/CompiledProgramValidator.swift).

It currently mixes:

- structural/declaration uniqueness checks
- declaration-side semantic checks
- post-expansion control-flow checks
- call and label validation
- literal bridge compatibility
- binding/environment/value resolution

That file is still useful, but architecturally it is acting as a catch-all.

## Target Validation Split

### 1. ProgramGraph Validation

Owns validation of root graph coherence.

Responsibilities:

- entity IDs are unique
- relation IDs or relation tuples are well-formed
- relations only point at existing entities
- base containment structure is coherent
- graph storage invariants hold

Questions it should answer:

- is the root graph structurally valid?
- do all root graph references point at real nodes?
- did graph construction produce malformed base records?

This layer should not care yet whether a use-site is valid against declarations.

### 2. DeclarationGraph Validation

Owns declaration-side validation.

Responsibilities:

- primary declaration uniqueness
- top-level declaration legality
- top-level state legality
- conformance declarations are structurally valid
- required members/declarations exist
- declared member/type surfaces are coherent
- macro target declarations are structurally valid
- declaration/application facet surfaces are valid

Questions it should answer:

- does this declaration exist?
- is it declared more than once?
- is this construct/protocol/member surface coherent on its own?
- are declaration-side macro surfaces and conformance relationships valid?

Examples:

- duplicate primary declarations
- duplicate top-level states
- malformed declaration-side macro target surfaces

### 3. ApplicationGraph Validation

Owns use-site validation against declaration facts.

This is the main declaration/application boundary.

Responsibilities:

- referenced declarations actually exist
- member access resolves against declared members
- callable/init resolution succeeds against declarations
- argument labels/counts match declaration-side expectations
- use-site type compatibility checks that depend on declaration facts
- macro applications are valid against declaration-side target surfaces
- unresolved references are surfaced here

Questions it should answer:

- can this declaration be used here?
- does `user.firstName` resolve against the declared `User` surface?
- does `User(name: 3)` match the declared initializer/type expectations?
- does this application path exist against the declaration graph?

Examples:

- `User` must exist before it can be referenced
- `user.firstName` fails if only `name` is declared
- invalid argument labels belong here

### 4. MemoryGraph Validation

Future layer.

Responsibilities:

- mutation legality
- ownership/storage consistency
- aliasing legality
- mutable vs immutable rules

Questions it should answer:

- is this mutation allowed?
- does this aliasing relationship violate storage rules?
- does the storage/update model remain coherent?

### 5. ReactivityGraph Validation

Future layer.

Responsibilities:

- invalid dependency cycles
- invalid observation chains
- impossible recomputation or invalidation topology

Questions it should answer:

- is the reactive dependency graph coherent?
- are there impossible or unsupported propagation relationships?

## Proposed Validator Types

Introduce explicit pass validators.

Initial target names:

- `ProgramGraphValidator`
- `DeclarationGraphValidator`
- `ApplicationGraphValidator`
- later `MemoryGraphValidator`
- later `ReactivityGraphValidator`

And keep:

- `CompiledProgramValidator`

But reduce its role to orchestration:

1. run root graph validation
2. run declaration validation
3. run application validation
4. later run memory validation
5. later run reactivity validation

## Near-Term Mapping From Current Validator

The current [CompiledProgramValidator.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/CompiledProgramValidator.swift)
should be decomposed by responsibility.

Likely declaration-side candidates:

- `validatePrimaryDeclarations`
- `validateTopLevelStates`
- declaration-surface legality checks

Likely application-side candidates:

- `validateCallArgumentLabels`
- binding reference resolution
- environment/state resolution
- value binding resolution
- use-site compatibility checks

Mixed or transitional candidates:

- `validateControlFlow`
- `validateCallableReturnSemantics`
- `validateLiteralBridgeCompatibility`

These should be classified explicitly during refactor rather than moved blindly.

## Validation Boundary Rule

Use this rule during the split:

- if the check can be answered from declaration facts alone, it belongs in
  `DeclarationGraphValidator`
- if the check requires a use-site to be resolved against declaration facts, it
  belongs in `ApplicationGraphValidator`
- if the check is only about root graph coherence, it belongs in
  `ProgramGraphValidator`

Examples:

- duplicate declaration names: declaration
- missing member on a use-site path: application
- broken entity/relation references in root graph storage: program

## Migration Plan

### Phase 1: Write The Boundary Down

Completed by this doc.

The immediate goal is clarity before code movement.

### Phase 2: Introduce Validator Shell Types

Add empty or lightly wired types:

- `ProgramGraphValidator`
- `DeclarationGraphValidator`
- `ApplicationGraphValidator`

Keep `CompiledProgramValidator` delegating to them.

### Phase 3: Move Clearly Scoped Checks First

Move the easiest unambiguous checks first:

- declaration uniqueness checks -> `DeclarationGraphValidator`
- top-level declaration/state checks -> `DeclarationGraphValidator`
- argument label and use-site resolution checks -> `ApplicationGraphValidator`

### Phase 4: Classify Mixed Checks

Audit and split the harder validations:

- control flow
- callable return semantics
- literal bridge compatibility

Some of these may stay temporarily in `CompiledProgramValidator` until their
graph ownership becomes clearer.

### Phase 5: Reduce CompiledProgramValidator To Orchestration

The long-term goal:

- `CompiledProgramValidator` just sequences graph-pass validators
- pass-specific validator files own the actual validation logic

## Immediate Next Slice

If continuing immediately, implement in this order:

1. add validator shell types
2. move declaration uniqueness checks into `DeclarationGraphValidator`
3. move obvious use-site resolution checks into `ApplicationGraphValidator`
4. leave mixed checks in `CompiledProgramValidator` until their ownership is
   explicit

## Decision

Validation should follow the graph passes.

Use:

- `ProgramGraphValidator` for root graph coherence
- `DeclarationGraphValidator` for declaration facts
- `ApplicationGraphValidator` for declaration/application boundary checks
- later `MemoryGraphValidator`
- later `ReactivityGraphValidator`

Keep `CompiledProgramValidator` only as the orchestrator over those passes.
