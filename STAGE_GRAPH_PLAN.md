# Stage Graph Plan

## Objective

Center the compiler on a graph-first architecture with one root graph substrate
and progressively derived domain views.

The current intended stack is:

- `ProgramGraph`
- `DeclarationGraph`
- `ApplicationGraph`
- `MemoryGraph`
- `ReactivityGraph`

Where:

- `ProgramGraph` is the canonical graph storage root
- `DeclarationGraph` is the declaration-domain graph view and enrichment layer
- `ApplicationGraph` is the application/use-site graph view and enrichment layer
- `MemoryGraph` is a later layer derived from declaration + application facts
- `ReactivityGraph` is a later layer derived from memory facts

The key rule is:

- the compiler should progressively read the program into more settled meaning
- later stages should enrich earlier graph facts, not rebuild parallel models
- `NeatCore` should remain the language-visible source of truth for declaration
  and application surfaces such as `Init`, `Init.Declaration`, and
  `Init.Application`

## Current Architecture

### What Exists In Code Now

Core files:

- [ProgramGraph.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/ProgramGraph.swift)
- [DeclarationGraph.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/DeclarationGraph.swift)
- [ApplicationGraph.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/ApplicationGraph.swift)
- [CompiledProgram.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/CompiledProgram.swift)
- [CompiledProgramValidator.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/CompiledProgramValidator.swift)

Macro graph view files:

- [DeclarationGraph+MacroViewModels.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/DeclarationGraph+MacroViewModels.swift)
- [DeclarationGraph+MacroViews.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/DeclarationGraph+MacroViews.swift)

Supporting docs:

- [Macros.Context.md](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/Macros.Context.md)
- [DeclarationGraph.md](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/MemoryGraph/DeclarationGraph.md)

### Current Roles

`ProgramGraph`

- owns canonical graph entity/relation vocabulary and root storage
- is the graph-root concept the rest of the stack should hang off

`DeclarationGraph`

- owns declaration-side graph construction and declaration query views
- exposes `programGraph`
- exposes declaration-backed views such as syntax/member/operator/macro views
- is the declaration-domain interpretation layer over `ProgramGraph`

`ApplicationGraph`

- is the application/use-site graph projection built from:
  - `DeclarationGraph` facts
  - expanded files
  - application-local flow and resolution analysis
- is the successor to the old dependency graph concept

`CompiledProgram`

- is not a graph
- it is the pipeline/container artifact
- it carries:
  - source inputs
  - parsed files
  - expanded files
  - `declarationGraph`
  - derived accessors for `programGraph` and `applicationGraph`

This split is important:

- `ProgramGraph` is the semantic graph root
- `CompiledProgram` is the compiler pipeline result object

### Current Pipeline

The current pipeline already behaves like staged graph enrichment:

1. parse `NeatCore`
2. discover project declarations with a lighter parse
3. build an early declaration graph
4. parse project files with declaration-backed help
5. macro-expand parsed files
6. rebuild declaration graph semantics from expanded files
7. validate
8. derive an application graph from expanded files plus declaration facts

This means staged enrichment is already real in the compiler. The work now is
to keep making the graph stack explicit and reduce parallel models.

## Graph Domains

There is a larger language graph domain conceptually, but we do not need a
concrete `LanguageGraph` type right now.

The practical structure is:

- `ProgramGraph` as the root graph
- declaration/application as one major semantic domain
- memory/reactivity as one later runtime/behavior domain

Operational dependency order:

- `ProgramGraph` -> `DeclarationGraph`
- `DeclarationGraph` -> `ApplicationGraph`
- `DeclarationGraph` + `ApplicationGraph` -> `MemoryGraph`
- `MemoryGraph` -> `ReactivityGraph`

Conceptually, declaration and application are paired halves of the language
model. Operationally, application depends on declaration because use-site
resolution only makes sense after declaration facts exist.

## Why Application Depends On Declaration

This is the validation boundary.

Examples:

- declaration says `User` has member `name`
- application says `user.firstName`
- boundary validation says the member does not exist

Or:

- declaration says `User.name: String`
- application says `User(name: 3)`
- boundary validation says the application is type-incompatible

So `ApplicationGraph` is not just “extra structure after parsing.” It is the
resolved use-site interpretation of the program against declaration facts.

## Current State Audit

### What Is Better Than Before

- old `DependencyGraph` naming is gone from the active source surface
- the root graph vocabulary lives in `ProgramGraph.swift`
- declaration-side graph logic lives in `DeclarationGraph.swift`
- application-side graph logic lives in `ApplicationGraph.swift`
- macro realization and rewrite-surface logic now lives on graph-backed context
  and graph-backed macro views rather than in expander-owned static state
- `CompiledProgram` is now clearly the pipeline/container layer rather than a
  graph root

### What Is Still Transitional

- `DeclarationGraph` still carries more responsibility than a pure view because
  it also builds the current root graph facts
- `ApplicationGraph` still owns some application-local analysis artifacts such
  as local flow/indexing state
- `MemoryGraph` and `ReactivityGraph` are architectural targets, not active
  code yet
- some docs and comments elsewhere in the repo may still reflect the older
  declaration-vs-dependency phrasing

## Stage Graph Model

### Stage 1: Structural

Input:

- parser output
- declaration-discovery parser output

Purpose:

- record what declarations and attachments exist
- avoid settling semantic meaning too early

Core entities:

- file
- module
- construct
- protocol
- enum
- extension
- macro declaration
- macro application
- callable
- initializer
- parameter
- state
- environment
- binding
- derived
- value
- type surface declaration such as `Init.Application`
- type reference

Core edges:

- `contains`
- `declares`
- `has_parameter`
- `has_member`
- `targets`
- `applies`
- `conforms_to`
- `extends`
- `has_type`
- `has_return_type`
- `has_facet`
- `references_type`

This stage should answer:

- what exists?
- what is nested under what?
- what macros are declared?
- what macros apply where by target kind?
- what target type does a macro declare?

### Stage 2: Declaration

Input:

- structural graph
- `NeatCore` declaration surfaces

Purpose:

- settle declaration-to-declaration meaning

Add:

- qualified declaration identity
- conformance closure
- requirement declarations
- requirement satisfaction relations
- declaration/application facet relations
- protocol-carried macro relations
- capability relations such as `SupportsRewrite`

This stage should answer:

- which declaration satisfies this protocol requirement?
- which macros are carried through protocol conformance?
- which target-surface declarations are rewrite-capable?
- what is the declaration/application structure of `Init`, `Parameter`,
  `Function`, `Construct`, and future targets?

### Stage 3: Realization

Input:

- declaration stage

Purpose:

- derive reusable semantic views from declaration facts

Derived views:

- `LiteralBridgeView`
- `InitMacroTargetView`
- `MacroRealizationView`
- `RewriteSurfaceView`
- `MemberResolutionView`
- `OperatorSignatureView`
- `MacroExpansionContext`

This stage should answer:

- what literal bridges exist?
- what init macro targets are realized?
- what parameter, function, init, or construct macros apply to this declaration?
- what rewrite-capable member paths exist from a target surface?
- what member and callable signatures are available?

### Stage 4: Expansion

Input:

- parsed files
- declaration/realization graph views

Purpose:

- execute macro bodies against settled target surfaces

Expansion should consume:

- macro declarations
- realized macro targets
- target surfaces
- rewrite-capable paths
- explicit macro expansion context

Expansion should own only:

- substitution
- payload interpretation
- rewrite execution
- phase ordering

Expansion should not own:

- target surface discovery
- macro realization discovery
- protocol carry discovery
- rewrite capability discovery

### Stage 5: Application

Input:

- expanded files
- declaration and realization graph layers

Purpose:

- record usage and application relationships in bodies

Add:

- `references`
- `calls`
- `resolves_to`
- `depends_on`
- local alias/use edges

This stage should answer:

- what does this call resolve to?
- what declarations does this body depend on?
- which local values alias or depend on outer declarations?
- which application paths are valid against declaration facts?

This is the current role of `ApplicationGraph`.

### Stage 6: Memory

Input:

- declaration graph
- application graph

Purpose:

- ownership, mutation, aliasing, and storage identity

Likely facts:

- `mutates`
- `aliases`
- `owns`
- `stores`

This should be treated as a downstream layer derived from declaration +
application facts rather than invented as a separate root model.

### Stage 7: Reactivity

Input:

- memory graph

Purpose:

- observation, invalidation, and propagation

Likely facts:

- `observes`
- `invalidates`
- `recomputes`

## Views, Not Parallel Root Models

The compiler should expose domain views over one graph root, not rebuild
parallel top-level graph truths.

The intended interpretation layers are:

- `ProgramGraph`
- `DeclarationGraph`
- `ApplicationGraph`
- later `MemoryGraph`
- later `ReactivityGraph`

And the non-graph container is:

- `CompiledProgram`

That distinction should remain explicit.

## Alignment With NeatCore

The compiler graph should mirror the same declaration/application surfaces that
`NeatCore` exposes.

Examples:

- `Init`
- `Init.Declaration`
- `Init.Application`
- `Function.Declaration`
- `Function.Application`
- `Parameter.Declaration`
- `Parameter.Application`

The graph should treat these as real declaration-surface entities and
relationships, not as hidden compiler conventions.

This matters for:

- macro surface correctness
- reduced semantic drift between compiler internals and `NeatCore`
- easier self-hosting
- smaller expander and resolver code

## What Current Code Maps To

### Current Pipeline Mapping

The existing compiler pipeline maps to the graph stages like this:

- `discoverProjectDeclarationFiles` -> structural seed input
- early `DeclarationGraph(files: ...)` -> structural + declaration partial
- `MacroExpander.expand(files:)` -> expansion
- final `DeclarationGraph(files: expandedFiles)` -> declaration + realization
- `ApplicationGraphBuilder().build(...)` -> application

The ordering is already mostly correct. The main job is to keep tightening the
graph boundaries and stop inventing parallel semantic stores.

### Current Types That Should Keep Becoming Graph Views

These are useful, but they should remain graph-backed views rather than
semi-independent semantic models:

- `DeclarationSyntaxResolver`
- `DeclarationMemberResolver`
- `DeclarationOperatorResolver`
- `DeclarationMacroExpansionResolver`
- macro realization views in `DeclarationGraph+MacroViews.swift`
- rewrite-surface validation and decoding in
  `DeclarationGraph+MacroViewModels.swift`

### Current File Roles

- `ProgramGraph.swift`
  owns root graph vocabulary and storage concepts
- `DeclarationGraph.swift`
  owns declaration graph construction and declaration-side query views
- `ApplicationGraph.swift`
  owns application graph construction and application-side projection logic
- `CompiledProgram.swift`
  orchestrates pipeline artifacts and exposes graph accessors
- `CompiledProgramValidator.swift`
  validates the compiled program using declaration/application graph facts

## Migration Plan

### Phase 1: Establish The Root Graph Stack

Completed or largely completed:

- introduce `ProgramGraph` as the root graph type
- split `DeclarationGraph` and `ApplicationGraph` into separate files/concepts
- make `CompiledProgram` the explicit container artifact rather than another
  graph root

### Phase 2: Keep Declaration Graph As The Source For Declaration Facts

Continue:

- keep moving declaration-side semantic queries behind `DeclarationGraph`
- keep reducing declaration reconstruction elsewhere
- keep making macro-related declaration/application surfaces graph-derived

### Phase 3: Keep Application Graph Downstream From Declaration Graph

Continue:

- build application/use-site facts from:
  - expanded files
  - declaration graph facts
  - application-local flow analysis
- keep application-local transient analysis state out of declaration storage
- keep stable declaration facts in declaration views

### Phase 4: Prepare The Memory Graph Boundary

Next major design step:

- identify which declaration + application facts should feed `MemoryGraph`
- define stable memory-domain relations without prematurely introducing another
  parallel storage model

### Phase 5: Prepare The Reactivity Graph Boundary

Later:

- derive reactivity from memory facts
- avoid coupling reactivity directly to parser- or AST-shaped structures

## Immediate Next Slice

If continuing immediately, implement in this order:

1. keep declaration/application architecture docs aligned with the current code
2. continue pulling declaration-side semantic queries behind `DeclarationGraph`
3. decide the first concrete `MemoryGraph` inputs from:
   - declaration facts
   - application facts
4. design memory-domain relations before adding storage

## Decision

Keep the stage separation.

Keep the graph stack explicit.

Use:

- `ProgramGraph` as the root graph substrate
- `DeclarationGraph` as the declaration-domain graph
- `ApplicationGraph` as the application-domain graph
- `CompiledProgram` as the pipeline/container artifact

Do not reintroduce:

- a second peer root graph model
- a dependency-named graph concept as a separate semantic authority
- graph-independent resolver mini-models where graph-backed views will do

That duplication is what causes drift, unnecessary compiler code, and weaker
alignment with `NeatCore`.
