# Gradient Status And Working Checklist

This is the current working checklist for aligning Gradient's implementation with
the current compiler, editor, and packaging direction.

The older notes remain useful context, but this file should be the first place
to look when deciding what to do next.

The older docs and posts have been published elsewhere; this checklist is the
implementation tracking surface.

## Where We Stand

### Implemented Enough To Treat As Current Baseline

- [x] `CompiledProgram` is the compiler pipeline artifact, not the graph root.
- [x] `ProgramGraph` is the canonical graph storage root.
- [x] `DeclarationGraph` is built from expanded files and exposes `programGraph`.
- [x] `ApplicationGraph` is derived downstream from `DeclarationGraph`.
- [x] Validation is staged through `ProgramGraphValidator`,
      `DeclarationGraphValidator`, and `ApplicationGraphValidator`.
- [x] `DeclarationGraph` has first-class registries or query views for
      constructs, protocols, enums, macros, markers, extensions, namespaces,
      package spaces, top-level callables, operators, top-level states,
      construct states, bindings, deriveds, values,
      initializers, and parameters.
- [x] Namespace-backed attribute facts are graph-owned through
      namespace attribute names and attachments.
- [x] Namespace-shaped configuration can be declared through `#namespace`
      constructs and through registered marker applications.
- [x] Direct construct application surfaces are declaration-backed and tested.
- [x] Project source cannot declare explicit `init`; construction is still
      modeled from stored declarations and allowed core/bootstrap surfaces.
- [x] Macro diagnostics feed the compiler diagnostic channel.
- [x] Macros and construct-applied markers can receive graph access through
      `target`, `diagnostics`, and `graph` bindings.
- [x] Macro graph access uses `Graph.Identity` for nested members, avoiding
      recursive declaration expansion by default.
- [x] Syntax-producing macros exist, including syntax templates, splices, and
      macro-to-macro invocation.
- [x] `#codable` uses string-keyed encode/decode generation and marker metadata.
- [x] Protocol-carried initializer macro behavior exists for realized init
      macro targets.
- [x] LSP semantic tokens cover types, functions, variables, parameters,
      members, macros, markers, nil, enum cases, package syntax, and namespace
      syntax.

### Partially Implemented, Still Architectural Debt

- [ ] `ProgramGraph` has broad entity/relation storage, but declaration facts
      are still partly duplicated as typed registries rather than uniformly
      projected from one graph relation model.
- [ ] Declaration metadata is not yet uniform across every category. The graph
      can answer many category-specific questions, but there is no single
      declaration descriptor surface for kind, core/project role, container,
      declared type, signature, and source identity.
- [ ] Requirement declarations and requirement satisfaction are validated, but
      `satisfiesRequirement` is not yet an explicit graph relation.
- [ ] Carried macro behavior exists, but `carriesMacro` is not yet an explicit
      graph relation.
- [ ] Declaration/application facets are documented and partially surfaced, but
      `facetOf` is not yet an explicit graph relation.
- [ ] Literal compatibility uses declaration-backed literal bridge facts in
      important places, but `BootstrapLiteralType` still carries too much
      expression/type meaning through parser and validator code.
- [ ] Operators are declared in `GradientCore`, but precedence defaults and some
      operator typing behavior still live in Swift-side compiler logic.
- [ ] `ApplicationGraphValidator` uses declaration queries for many existence
      checks, but it still carries substantial transient type-flow and
      accessible-type state as `BootstrapLiteralType` maps.
- [ ] The Swift backend still emits and ships runtime/support code with
      Foundation-heavy and host-oriented behavior.
- [ ] The CLI is intentionally host-bound, but the compiler/backend boundary is
      not yet clean enough for a serious Embedded Swift build lane.
- [ ] Memory graph and reactivity graph remain design documents, not concrete
      compiler stages.

## Working Checklist

### 1. Lock The Current Baseline

- [ ] Keep this checklist updated whenever a planned item is implemented.
- [ ] Add focused tests for any existing graph behavior that is only covered
      indirectly by broad compile fixtures.
- [x] Add a small declaration graph snapshot test for current registry/query
      coverage: enums, macros, markers, extensions, states, values,
      initializers, parameters, namespace attributes, and package spaces.
- [ ] Add an application graph snapshot test that proves declaration projection
      plus application edges stay downstream from the declaration graph.

### 2. Make Declaration Metadata Uniform

- [ ] Introduce one declaration descriptor/query surface that can represent:
      kind, name, core/project role, container, source location, declared type,
      signature shape, and relevant attributes/markers/macros.
- [ ] Back the descriptor with existing `DeclarationGraph` registries first,
      without redesigning storage.
- [ ] Replace category-specific source-location and kind lookups with the new
      descriptor where it reduces duplication.
- [ ] Add tests proving the descriptor works for constructs, enums, protocols,
      macros, markers, extensions, callables, initializers, parameters, and
      properties.

### 3. Promote Missing Relations To Graph Facts

- [ ] Add explicit `facetOf` relation support.
- [ ] Model declaration/application facet links for `Init`, `Function`, and
      `Parameter` surfaces.
- [ ] Add explicit `satisfiesRequirement` relation support.
- [ ] Record protocol requirement satisfaction during declaration validation or
      declaration graph enrichment.
- [ ] Add explicit `carriesMacro` relation support.
- [ ] Record carried macro facts for protocol conformance and initializer macro
      carry.
- [ ] Rebuild the relevant macro/requirement query views on top of those
      relations once the facts are present.

### 4. Shrink Bootstrap Literal Meaning

- [ ] Inventory every remaining `BootstrapLiteralType` use by role:
      parse-time literal category, default destination choice, expression type,
      local accessible type, operator compatibility, return compatibility, and
      backend lowering.
- [ ] Pick one narrow path, preferably return compatibility or argument
      compatibility, and route it through declaration graph facts plus
      `GradientCore` literal bridge protocols.
- [ ] Keep Swift-side literal logic only for literal categories, parser sugar,
      lowering/runtime hooks, and transitional diagnostics.
- [ ] Repeat for operator compatibility after declaration-backed literal
      compatibility is proven.

### 5. Move Operator Meaning Toward GradientCore

- [ ] Replace parser-owned precedence defaults with explicit Gradient operator and
      precedence declarations.
- [ ] Ensure operator lookup and precedence resolution read declaration graph
      facts.
- [ ] Shrink Swift-side scalar/operator typing rules after literal bridge
      compatibility is less bootstrap-driven.
- [ ] Add fixtures for custom precedence, overload selection, and failure
      diagnostics.

### 6. Define The First Memory Graph Slice

- [ ] Define the minimal first `MemoryGraph` node and relation vocabulary from
      current declaration and application graph facts.
- [ ] Start with storage identity and mutation facts for `state`, `binding`,
      `derived`, `let`, and local mutation.
- [ ] Keep `MemoryGraph` derived from declaration plus application meaning, not
      raw parser structures.
- [ ] Add one compiler pass that produces a memory projection without changing
      diagnostics yet.
- [ ] Add proof/snapshot fixtures before using memory facts for rejection rules.

### 7. Keep Macro And Metadata Work Honest

- [ ] Harden generic marker access without adding one-off fields like
      `property.codingKey`.
- [ ] Make property marker targets owner-qualified in graph identity, so
      `let`, `state`, `binding`, and `derived` marker graph access has the same
      fidelity as construct marker graph access.
- [ ] Decide and implement the operational `@macro` vs descriptive `#marker`
      surface. Current implementation still accepts macro applications through
      the older `#` path in several places.
- [ ] Keep config, sharing, and sensitive-value design at the property
      marker/macro layer, without committing to concrete `@provided` or
      `#secret` spellings yet.
- [ ] Expand syntax-producing macro coverage for function bodies, initializer
      bodies, blocks, switches, assignments, and declaration lists.
- [ ] Decide the syntax block story around future `# { ... }` blocks.
- [ ] Move marker value handling beyond primitive-only checks when rich marker
      values become necessary.
- [ ] Replace renderer/parser-loop syntax production with structural syntax
      builders only when the current approach becomes a real blocker.
- [ ] Complete the `SyntaxOmittable` story for conditional redaction,
      region-style macros, or compiler-macro style conditional syntax.

### 8. Grow GradientCore Deliberately

- [ ] Add `Sequence` and `Collection` protocols before broadening
      collection-like APIs across storage types.
- [ ] Revisit `ComponentStorage` and `Vector<let dimensionality, Scalar>` after
      value-generic application support is less transitional.
- [ ] Keep namespace-shaped domain surfaces as `#namespace construct ...` when
      they carry namespace behavior or configuration.
- [ ] Keep representation/storage constructs ordinary unless they are actually
      namespace-shaped.
- [ ] Continue moving foundational language-visible surfaces into `GradientCore`
      instead of Swift-only mirrors.

### 9. Embedded Swift And Backend Boundary

- [ ] Split pure backend lowering/emission from host file/project operations.
- [ ] Isolate generated runtime support that depends on Foundation, classes,
      locks, file/process APIs, or other host-only behavior.
- [ ] Audit `GradientSyntax` Foundation usage and replace easy cases where the
      standard library is enough.
- [ ] Add an Embedded Swift feasibility build lane when the local toolchain and
      SDK setup can support it.
- [ ] Keep CLI host adapters outside the compiler core boundary.

### 10. Tooling And Editor Parity

- [ ] Add semantic origin modifiers for project vs core/external symbols.
- [ ] Map origin-aware semantic token rules such as `type.gradient.project` and
      `type.gradient.other`.
- [ ] Split constants from mutable variables where declaration graph facts know
      immutability.
- [ ] Split globals, locals, and properties where symbol scope is known.
- [ ] Add semantic attribute classification instead of relying only on fallback
      syntax highlighting.
- [ ] Add documentation comment and documentation markup token categories once
      doc comments are formalized.

### 11. Product And Publishing

- [ ] Decide whether GradientCloud is a real product direction for packages,
      articles, examples, and language-design notes.
- [ ] Treat `.env` as only one local provider for typed config/secret
      declarations. The source of truth should be graph-visible declarations
      with property metadata and behavior attached through markers/macros.

## Immediate Next Slice

1. Make property marker targets owner-qualified in graph identity.
2. Introduce the uniform declaration descriptor surface on top of the existing
   registries.
3. Promote one missing relation to a first-class graph fact, starting with
   `facetOf` because it clarifies macro target surfaces without changing
   runtime behavior.
4. Route one literal compatibility path through declaration graph facts and
   `GradientCore` bridge protocols.
5. Define the smallest non-diagnostic `MemoryGraph` projection pass.

## Verification Snapshot

Last reviewed on 2026-05-19.

- `GradientSyntax`: `swift test` passed with 43 tests.
- `GradientCLI`: `swift test` passed with 36 tests.
- `GradientBackendSwift`: `swift test` builds, but exits with `no tests found`
  because the package has no test target.
- Fixture inventory at review time:
  - `CompilePass`: 94 fixtures.
  - `CompileFail`: 46 fixtures.
