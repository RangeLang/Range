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

The validation split now exists in code:

- [CompiledProgramValidationPass.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/CompiledProgramValidationPass.swift)
- [ProgramGraphValidator.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/ProgramGraphValidator.swift)
- [DeclarationGraphValidator.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/DeclarationGraphValidator.swift)
- [ApplicationGraphValidator.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/ApplicationGraphValidator.swift)
- [CompiledProgramValidator.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/CompiledProgramValidator.swift)

`CompiledProgramValidator` is now a small orchestrator over an ordered pass
list, not a catch-all implementation file.

The current active pass order is:

1. `ProgramGraphValidationPass`
2. `DeclarationGraphValidator`
3. `ApplicationGraphValidator`

What still remains is ongoing refinement of which checks belong to which pass,
not the basic pass structure itself.

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

## Current Validator Types

Current pass-oriented validator types:

- `ProgramGraphValidator`
- `DeclarationGraphValidator`
- `ApplicationGraphValidator`
- `CompiledProgramValidationPass`
- later `MemoryGraphValidator`
- later `ReactivityGraphValidator`

And keep:

- `CompiledProgramValidator`

Its role is now orchestration:

1. run root graph validation
2. run declaration validation
3. run application validation
4. later run memory validation
5. later run reactivity validation

## Current Protocolized Flow

The validation boundary is protocolized at the compiled-program pass level:

```swift
public protocol CompiledProgramValidationPass {
    var name: String { get }
    func validate(_ program: CompiledProgram) throws
}
```

This keeps the orchestration shape uniform without forcing the internal
validation logic of each graph pass into the same abstraction.

Current conformance shape:

- `DeclarationGraphValidator: CompiledProgramValidationPass`
- `ApplicationGraphValidator: CompiledProgramValidationPass`
- `ProgramGraphValidator` remains focused on `ProgramGraph` itself and is
  adapted into the compiled-program pass list via a small
  `ProgramGraphValidationPass`

This is intentional:

- protocolize the pass boundary
- do not over-protocolize the internal validation implementation

## Current Mapping

The current split now looks like this.

Declaration-side:

- `validatePrimaryDeclarations`
- `validateTopLevelStates`
- `validateCoreAttributeUsage`

Application-side:

- `validateControlFlow`
- `validateCallArgumentLabels`
- `validateCallableReturnSemantics`
- `validateLiteralBridgeCompatibility`
- binding reference resolution
- environment/state resolution
- value binding resolution

Root graph:

- entity/relation coherence checks in `ProgramGraphValidator`

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

Completed.

The explicit validator types exist, and `CompiledProgramValidator` delegates to
them through a pass list.

### Phase 3: Move Clearly Scoped Checks First

Completed.

The first obvious declaration/application checks have already moved.

- declaration uniqueness checks -> `DeclarationGraphValidator`
- top-level declaration/state checks -> `DeclarationGraphValidator`
- argument label and use-site resolution checks -> `ApplicationGraphValidator`

### Phase 4: Classify Mixed Checks

Largely completed for the currently implemented validation surface:

- control flow -> `ApplicationGraphValidator`
- callable return semantics -> `ApplicationGraphValidator`
- literal bridge compatibility -> `ApplicationGraphValidator`

### Phase 5: Reduce CompiledProgramValidator To Orchestration

Completed for the current graph stack.

- `CompiledProgramValidator` just sequences graph-pass validators
- pass-specific validator files own the actual validation logic

## Next Validation Slice

The next useful work is not another large split. It is one of:

1. add pass-level diagnostics/reporting metadata using the `name` field
2. introduce `MemoryGraphValidator` once the first memory-domain facts exist
3. decide whether graph substages also need lightweight protocol boundaries

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
