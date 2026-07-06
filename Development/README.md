# Range Status And Working Checklist

This is the current working checklist for aligning Range's implementation with
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
- [x] Validation is staged through `ProgramGraphValidator`,
      `DeclarationGraphValidator`, and the source/declaration validation pass
      currently named `ApplicationGraphValidator`.
- [x] `DeclarationGraph` has first-class registries or query views for
      constructs, protocols, enums, macros, extensions, namespaces,
      package spaces, top-level callables, operators, top-level states,
      construct states, bindings, deriveds, values,
      initializers, and parameters.
- [x] Namespace-backed attribute facts are graph-owned through
      namespace attribute names and attachments.
- [x] Namespace-shaped configuration can be declared through `@namespace`
      constructs and registered macro applications.
- [x] Direct construct application surfaces are declaration-backed and tested.
- [x] Project source cannot declare explicit `init`; construction is still
      modeled from stored declarations and allowed core/bootstrap surfaces.
- [x] Macro diagnostics feed the compiler diagnostic channel.
- [x] Macros can receive graph access through
      `target`, `diagnostics`, and `graph` bindings.
- [x] Macro graph access uses `Graph.Identity` for nested members, avoiding
      recursive declaration expansion by default.
- [x] Syntax-producing macros exist, including syntax templates, splices, and
      macro-to-macro invocation.
- [x] `@codable` uses string-keyed encode/decode generation and macro metadata.
- [x] Protocol-carried initializer macro behavior exists for realized init
      macro targets.
- [x] LSP semantic tokens cover types, functions, variables, parameters,
      members, macros, nil, enum cases, package syntax, and namespace
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
- [ ] Declaration/application facets are documented and partially surfaced in
      declaration queries, but `facetOf` is not yet an explicit graph relation.
- [ ] Literal compatibility uses declaration-backed literal bridge facts in
      important places, but `BootstrapLiteralType` still carries too much
      expression/type meaning through parser and validator code.
- [ ] Operators are declared in `RangeCore`, but precedence defaults and some
      operator typing behavior still live in Swift-side compiler logic.
- [ ] `ApplicationGraphValidator` no longer depends on a materialized
      `ApplicationGraph`, but it still carries substantial transient type-flow
      and accessible-type state as `BootstrapLiteralType` maps.
- [x] The old Swift backend package has been removed from the active layout.
- [x] The script runner is intentionally host-bound and the active execution
      path is the current LLVM path: Range source goes through the range
      compiler host, LLVM emission, `clang`, and the linked executable.
- [x] `SwiftBootstrap` is the explicit stage-0 compiler target. It owns the
      temporary Swift-hosted `Range source -> LLVM IR` path until a
      Range-authored compiler binary can replace it.
- [x] `SwiftBootstrap` owns stage-0 executable construction: build directory
      cleanup, LLVM IR materialization, and `clang` linking.
- [x] `SwiftBootstrap` owns direct stage-0 execution for `range run`; Bash no
      longer launches the linked executable for that command.
- [x] `SwiftBootstrap` owns LLVM run-manifest validation and execution checks;
      Bash no longer parses manifest rows, expected exits, stdin, args, or
      expected stdout.
- [x] `SwiftBootstrap` owns emit-only LLVM example corpus checks; Bash no
      longer walks the example directory or manages temporary IR outputs.
- [ ] The compiler/emission boundary still needs to shrink: Swift remains the
      compiler host and owns substantial parser/type/lowering machinery.
- [ ] Memory graph and reactivity graph remain design documents, not concrete
      compiler stages.

## Working Checklist

### 1. Lock The Current Baseline

- [ ] Keep this checklist updated whenever a planned item is implemented.
- [ ] Add focused tests for any existing graph behavior that is only covered
      indirectly by broad compile fixtures.
- [x] Add a small declaration graph snapshot test for current registry/query
      coverage: enums, macros, extensions, states, values,
      initializers, parameters, namespace attributes, and package spaces.
- [x] Remove the disconnected materialized `ApplicationGraph` projection; keep
      validation on the active declaration/source pipeline.

### 2. Make Declaration Metadata Uniform

- [ ] Introduce one declaration descriptor/query surface that can represent:
      kind, name, core/project role, container, source location, declared type,
      signature shape, and relevant attributes/macros.
- [ ] Back the descriptor with existing `DeclarationGraph` registries first,
      without redesigning storage.
- [ ] Replace category-specific source-location and kind lookups with the new
      descriptor where it reduces duplication.
- [ ] Add tests proving the descriptor works for constructs, enums, protocols,
      macros, extensions, callables, initializers, parameters, and
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
      `RangeCore` literal bridge protocols.
- [ ] Keep Swift-side literal logic only for literal categories, parser sugar,
      lowering/runtime hooks, and transitional diagnostics.
- [ ] Repeat for operator compatibility after declaration-backed literal
      compatibility is proven.

### 5. Move Operator Meaning Toward RangeCore

- [ ] Replace parser-owned precedence defaults with explicit Range operator and
      precedence declarations.
- [ ] Ensure operator lookup and precedence resolution read declaration graph
      facts.
- [ ] Shrink Swift-side scalar/operator typing rules after literal bridge
      compatibility is less bootstrap-driven.
- [ ] Add fixtures for custom precedence, overload selection, and failure
      diagnostics.

### 6. Define The First Memory Graph Slice

- [ ] Define the minimal first `MemoryGraph` node and relation vocabulary from
      current declaration facts plus active source-flow validation.
- [ ] Start with storage identity and mutation facts for `state`, `binding`,
      `derived`, `let`, and local mutation.
- [ ] Keep `MemoryGraph` derived from declaration plus validated application
      meaning, not raw parser structures.
- [ ] Add one compiler pass that produces a memory projection without changing
      diagnostics yet.
- [ ] Add proof/snapshot fixtures before using memory facts for rejection rules.

### 7. Keep Macro And Metadata Work Honest

- [x] Collapse legacy metadata access into macro applications without adding one-off fields like
      `property.codingKey`.
- [x] Keep property macro targets owner-qualified in graph identity, so
      `let`, `state`, `binding`, and `derived` macro graph access has the same
      fidelity as construct macro graph access.
- [x] Use `@` as the single authored macro surface. `#` is reserved for syntax
      splices such as `#(...)`.
- [ ] Keep config, sharing, and sensitive-value design at the property
      macro layer, without committing to concrete `@provided` or
      `@secret` spellings yet.
- [ ] Expand syntax-producing macro coverage for function bodies, initializer
      bodies, blocks, switches, assignments, and declaration lists.
- [ ] Decide the syntax block story around future `# { ... }` blocks.
- [ ] Move macro value handling beyond primitive-only checks when rich macro
      values become necessary.
- [ ] Replace renderer/parser-loop syntax production with structural syntax
      builders only when the current approach becomes a real blocker.
- [ ] Complete the `SyntaxOmittable` story for conditional redaction,
      region-style macros, or compiler-macro style conditional syntax.

### 8. Grow RangeCore Deliberately

- [ ] Add `Sequence` and `Collection` protocols before broadening
      collection-like APIs across storage types.
- [ ] Keep namespace-shaped domain surfaces as `@namespace construct ...` when
      they carry namespace behavior or configuration.
- [ ] Keep representation/storage constructs ordinary unless they are actually
      namespace-shaped.
- [ ] Continue moving foundational language-visible surfaces into `RangeCore`
      instead of Swift-only mirrors.

### 9. LLVM Emission And Host Boundary

- [x] Make the script-driven LLVM executable path the active checked baseline.
      `scripts/range check` validates the full LLVM example corpus through
      emission, `clang`, process exit, and declared stdout.
- [x] Introduce `SwiftBootstrap` as the stage-0 compiler boundary used by the
      `range` executable.
- [x] Move native executable construction out of the Bash script and into
      `SwiftBootstrap`.
- [x] Move direct `run` execution out of the Bash script and into
      `SwiftBootstrap`.
- [x] Move `check-llvm-runs` manifest validation and execution assertions out of
      the Bash script and into `SwiftBootstrap`.
- [x] Move `check-llvm-examples` corpus emission out of the Bash script and into
      `SwiftBootstrap`.
- [ ] Split pure LLVM lowering/emission from remaining host file/project
      operations.
- [ ] Isolate runtime support that depends on Foundation, classes, locks,
      file/process APIs, or other host-only behavior.
- [ ] Audit `RangeCompiler` Foundation usage and replace easy cases where the
      standard library is enough.
- [ ] Keep script/host adapters outside the compiler core boundary.

### 10. Tooling And Editor Parity

- [ ] Add semantic origin modifiers for project vs core/external symbols.
- [ ] Map origin-aware semantic token rules such as `type.range.project` and
      `type.range.other`.
- [ ] Split constants from mutable variables where declaration graph facts know
      immutability.
- [ ] Split globals, locals, and properties where symbol scope is known.
- [ ] Add semantic attribute classification instead of relying only on fallback
      syntax highlighting.
- [ ] Add documentation comment and documentation markup token categories once
      doc comments are formalized.

### 10a. Experimental Syntax Notes

- Range declarations should remain line-scoped: one declaration begins on one
      physical line, with wrapping reserved for the declaration's continued
      header, argument lists, generic clauses, conformances, or body. This keeps
      code prediction and editor wrapping deterministic because a formatter or
      language server can tell whether a line starts a new declaration or
      continues the current one.
- Freestanding expansion syntax should use `@expand { ... }` blocks directly:
      `@expand { construct Generated { ... } }`. Macro authors should not need
      to write `target.declaration.expand { ... }` for normal declaration
      emission. `@expand` blocks are graph-visible children of the surrounding
      context, including macro declarations. A macro with no `@expand` children
      is a valid equilibrium state, not a diagnostic.
- An `@expand` block should also create a background compiler processing unit
      for the block contents. That unit runs with reduced enforcement and no
      required emission path: its first job is validation and feedback. This lets
      the compiler report back on expansion candidates, for example "hey, this
      generated construct is malformed", without forcing the block to become
      emitted program syntax immediately.

### 11. Product And Publishing

- [ ] Decide whether RangeCloud is a real product direction for packages,
      articles, examples, and language-design notes.
- [ ] Treat `.env` as only one local provider for typed config/secret
      declarations. The source of truth should be graph-visible declarations
      with property metadata and behavior attached through macros.

## Immediate Next Slice

1. Keep fixtures honest after the metadata-to-macro collapse.
2. Introduce the uniform declaration descriptor surface on top of the existing
   registries.
3. Promote one missing relation to a first-class graph fact, starting with
   `facetOf` because it clarifies macro target surfaces without changing
   runtime behavior.
4. Route one literal compatibility path through declaration graph facts and
   `RangeCore` bridge protocols.
5. Define the smallest non-diagnostic `MemoryGraph` projection pass.

## Verification Snapshot

Last reviewed on 2026-07-06.

- `RangeCompiler`: `swift build --package-path RangeCompiler` passes.
- `SwiftBootstrap`: the `range` executable routes `emit-llvm`, native
  executable construction/execution, run-manifest checks, and emit-only corpus
  checks through the stage-0 compiler target.
- `scripts/range check` emits LLVM, links with `clang`, and runs all 148
  `RangePlayground/Examples/LLVM/*.range` examples with expected exit/stdout
  checks.
- `swift test --package-path RangeCompiler --filter RangeScriptTests` passes
  and guards the script manifest/coverage contract.
- Fixture inventory at review time:
  - `CompilePass`: 94 fixtures.
  - `CompileFail`: 46 fixtures.
