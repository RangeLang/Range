# Stage Graph Plan

## Objective

Collapse the current split between `DeclarationGraph` and `DependencyGraph` into
one staged semantic graph substrate that is enriched over time.

The key rule is:

- the compiler should progressively read the program into more settled meaning
- later stages should enrich earlier graph facts, not rebuild parallel models
- `NeatCore` should remain the language-visible source of truth for macro target
  surfaces such as `Init`, `Init.Declaration`, and `Init.Application`

This plan is intended to align Swift-hosted compiler internals with the same
declaration/application model exposed by `NeatCore`, reduce bespoke compiler
logic, and make the self-hosting path cleaner.

## Current State Audit

### What Exists Today

- `DeclarationGraph` in
  `NeatSyntax/Sources/NeatSyntax/Core/DeclarationGraph.swift`
- `DependencyGraph` in
  `NeatSyntax/Sources/NeatSyntax/Core/DependencyGraph.swift`
- declaration-driven macro target docs in
  `NeatSyntax/Sources/NeatSyntax/Macros/Macros.Context.md`
- declaration-graph intent docs in
  `NeatSyntax/Sources/NeatSyntax/GraphBindings/MemoryGraph/DeclarationGraph.md`

### What The Current Pipeline Actually Does

The current pipeline already behaves like staged reading:

1. parse `NeatCore`
2. discover project declarations with a lighter parse
3. build an early declaration-level view
4. parse project files with declaration-level help
5. macro-expand parsed files
6. rebuild declaration-level semantics from expanded files
7. validate
8. optionally build a structural dependency graph

This means the compiler already needs staged enrichment. The main issue is that
those stages are currently represented by multiple overlapping models rather
than one shared graph substrate.

### Where The Current Split Is Weak

- `DeclarationGraph` is still mostly AST-shaped declarations plus a few
  compiler-owned derived tables.
- `DependencyGraph` already carries declaration structure such as containment,
  conformance, macro application, and macro target edges.
- macro support is still partly bespoke through collector functions and
  resolver-style helpers.
- `MacroExpander` still owns graph-derived state and semantic glue that should
  come from graph views.

### Why The Split Happened

The original split was useful as a bootstrap convenience:

- declaration semantics needed to exist before full body/dependency analysis
- Swift-side compiler code kept AST declarations as the easiest internal truth
- `NeatCore` defined the language-facing model, but Swift internals did not
  fully align with it

That was acceptable early on, but it is now a limiting factor for macro work,
graph clarity, and self-hosting alignment.

## Target Model

Use one semantic graph substrate with staged enrichment passes.

The split that should remain is:

- declaration stage
- dependency stage
- memory/reactivity stage

The split that should go away is:

- separate core storage models for declaration semantics and dependency facts

### Core Principle

The graph starts with simple structural nodes and edges. Later passes add
meaning:

- declaration meaning
- conformance meaning
- macro realization meaning
- expansion meaning
- dependency/use meaning
- memory/reactivity meaning

This is procedural reading, not replacement.

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

This stage should be enough to answer:

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

New edges or normalized relations:

- `satisfies_requirement`
- `inherits_macro`
- `supports_capability`
- `facet_of`

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
- `AttachedMacroView`
- `RewriteSurfaceView`
- `MemberResolutionView`
- `OperatorSignatureView`
- `MacroExpansionSignatureView`

This stage should answer:

- what literal bridges exist?
- what init macro targets are realized?
- what parameter, function, init, or construct macros apply to this callable or declaration?
- what rewrite-capable member paths exist from a target surface?
- what member and callable signatures are available?

This is where current ad hoc collector logic should move.

### Stage 4: Expansion

Input:

- parsed files
- realization-stage graph views

Purpose:

- execute macro bodies against settled target surfaces

Expansion should consume:

- macro declarations
- applicable attachments
- target surfaces
- rewrite-capable paths
- realized declaration/application targets

Expansion should own only:

- substitution
- payload interpretation
- rewrite execution
- phase ordering

Expansion should not own:

- target surface discovery
- attachment discovery
- protocol carry discovery
- rewrite capability discovery

### Stage 5: Dependency

Input:

- expanded files
- declaration and realization graph layers

Purpose:

- record usage and dependency relationships in bodies

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

This is where the current `DependencyGraph` should land as a view or projection,
not as a separate core model.

### Stage 6: Memory

Input:

- expanded files
- declaration/realization/dependency graph layers

Purpose:

- ownership, mutation, aliasing, and reactivity

Add:

- `mutates`
- `aliases`
- `owns`
- `observes`

This may remain a later specialized layer even if the underlying storage is
shared.

## Views, Not Separate Graph Types

Instead of separate top-level graph systems, expose views over one substrate:

- `StructuralView`
- `DeclarationView`
- `MacroView`
- `RewriteSurfaceView`
- `DependencyView`
- `MemoryView`

The CLI can render whichever projection is relevant.

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

This is important for:

- macro surface correctness
- reduced semantic drift between compiler internals and `NeatCore`
- easier self-hosting
- smaller expander and resolver code

## What Current Code Maps To

### Current Pipeline Mapping

The existing compiler pipeline already maps fairly well to the stage model:

- `discoverProjectDeclarationFiles` -> Stage 1 seed input
- early `DeclarationGraph(files: ...)` -> Stages 1-2 partial
- `MacroExpander.expand(files:)` -> Stage 4
- final `DeclarationGraph(files: expandedFiles)` -> Stages 2-3 settled
- `DependencyGraphBuilder().build(files: expandedFiles)` -> Stage 5

The ordering is not the main problem. The storage model split is.

### Current Types That Should Become Graph Views

These are useful, but they should become graph-backed views instead of parallel
semantic models:

- `DeclarationSyntaxResolver`
- `DeclarationMemberResolver`
- `DeclarationOperatorResolver`
- `DeclarationMacroExpansionResolver`
- `collectRealizedLiteralBridges`
- `collectRealizedInitMacroTargets`
- `collectAttachedParameterCallables`
- `collectAttachedFunctionCallables`

### Current File Roles

- `DeclarationGraph.swift`
  should move toward graph storage plus reusable semantic views
- `DependencyGraph.swift`
  should become a projection or rendering-oriented view of the shared graph
- `MacroExpander.swift`
  should consume explicit graph context rather than storing graph-derived static
  state
- `SemanticProgram.swift`
  should orchestrate staged enrichment rather than bouncing between separate
  models

## Migration Plan

### Phase 1: Name The Architecture Correctly

- Keep `DeclarationGraph` as the semantic name for the main graph substrate.
- Reframe `DependencyGraph` as a dependency projection over the same graph.
- Update docs so they describe one staged semantic graph rather than two
  competing graph models.

### Phase 2: Split Storage From Views

- Refactor the current `DeclarationGraph` into:
  - base graph storage
  - graph-backed derived views
- Stop letting resolver structs act like semi-independent semantic stores.

### Phase 3: Promote Macros To First-Class Graph Facts

- Model macro declarations and macro applications as first-class graph entities.
- Represent target relations, attachment relations, carried-macro relations, and
  realized macro-target relations explicitly.
- Replace current ad hoc macro collectors with graph views.

### Phase 4: Make Rewrite Surfaces Fully Graph-Derived

- Expose a graph-backed `RewriteSurfaceView`.
- Derive paths such as `target.application.rewrite` from target-surface
  declarations and capability conformance.
- Remove remaining hardcoded or target-kind-specific rewrite-surface logic from
  expansion.

### Phase 5: Make MacroExpander A Pure Consumer

- Build an explicit `MacroExpansionContext` from graph views.
- Pass that context through expansion instead of using static mutable state.
- Remove graph-discovery logic from the expander.

### Phase 6: Collapse DependencyGraph Into A View

- Rebuild the current dependency graph output from the shared graph substrate.
- Keep CLI rendering and structural visualization, but make them projections
  rather than separate graph construction systems.

### Phase 7: Reassess Memory Graph Layering

- Decide whether the memory graph should remain a separate late-layer model or
  become another view/enrichment phase over the same substrate.
- Do not force this collapse too early; declaration and macro alignment is the
  higher-priority architectural debt.

## Immediate Next Slice

If continuing immediately, implement in this order:

1. document the unified staged graph architecture in compiler docs
2. introduce a graph-backed macro view layer for:
   - target-kind macro lookup
   - realized init macro targets
   - rewrite-capable target paths
3. replace `MacroExpander` static state with explicit expansion context
4. decide whether `DependencyGraph` storage should be merged into
   `DeclarationGraph` internals or rebuilt as a projection over shared graph
   entities

## Decision

Keep the stage separation.

Collapse the storage split.

The compiler should have:

- one staged semantic graph substrate
- multiple enrichment passes
- multiple projections/views

It should not keep:

- one declaration-semantic model
- another dependency graph model
- plus separate resolver mini-models

That duplication is the real source of drift and unnecessary compiler code.
