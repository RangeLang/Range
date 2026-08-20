# Compiler B

Compiler B is the new compiler. Build it out in small runnable slices.

- B owns file access, lexing, macros, graph construction, lowering, and emit.
- B has no explicit generic binders or generic type applications. Element
  identity, cardinality, and input/output correspondence are graph
  relationships; operations such as `filter` preserve or transform those
  relationships without authored `<Element>` parameters.
- The remaining `Buffer<Int>` and `Buffer<Byte>` spellings in B's implementation
  are accepted-Compiler-A bootstrap storage, not B language semantics. Replace
  them with graph-native cardinality storage before B parses and compiles its
  complete source set itself.
- Range owns ordinary runtime behavior. Use `@extern` only to declare an actual
  foreign ABI symbol such as a libc or operating-system function; do not place
  a second implementation of B behind a C wrapper.
- `Runtime/RangeCompilerHost.c` is a temporary bootstrap dependency inherited
  from A's generated runtime ABI, not Compiler B architecture. Remove it from
  B's link once the required memory, String, construct, process, and platform
  lowering is emitted as LLVM by the accepted bootstrap or by B itself.
- Compiler A only bootstraps B’s LLVM; do not reshape B around A’s tables or body arena.
- Each slice must compile, link, run, and show its result before expanding scope.
- Keep the entrypoint in `Sources/CompilerB/Main.range` until the next boundary is proven.
- The current frontend slice discovers a project’s first `.range` file and
  prints B-owned lexer and syntax rows.
- Lexing has one retained columnar store with concrete
  `CompilerBToken { id, kind, start, end }` values. Token identity compares
  `TokenID`; spelling equivalence compares source bytes over token ranges.
- Syntax parsing consumes those retained token values directly. General syntax
  nodes carry only source-derived `SyntaxNodeID` values and retained
  `TokenSpan`s. Revisions retain their token stores, so names and byte ranges
  are derived rather than copied into the common node.
- Function, Construct, Block, Macro.Application, function-signature, and Return
  information lives in separate facet stores owned by one syntax revision.
  Individual `Function.Declaration` and `Construct.Declaration` query functions
  provide nominal typing and resolve identity-token and body-syntax
  relationships. The parser discovers ordered declaration macro applications,
  function return-type tokens, and Return relationships once. Representation
  queries and the backend consume those facets; they do not rescan tokens for
  structural keywords. There is no central syntax-kind enum.
- Macro declarations are retained as their own declaration facet, and their
  target constraints are checked at each resolved application. Compiler
  B deliberately has no authored `{ environment in ... }` binder and no
  special `inspect` interpreter. A future executable macro body receives its
  compile-time context implicitly and runs through the same typed body/process
  representation used for ordinary functions.
- `@member` is an authored macro family, not a nominal `Member` construct. Its
  target alternatives are `Let | State | Derived | Binding`; transforms such
  as `macro print(): @member {}` resolve that family through the retained macro
  signature graph. The focused proof admits all four concrete property forms
  and rejects a Construct before macro-body execution. The parser retains each
  property's owner, concrete keyword, identity, type, and value span; the
  remaining shared property-row storage is an implementation detail to split
  into concrete facet stores, not a source-level `Member` type.
- Macro application resolution happens once during compilation. Every
  application stores its resolved Macro declaration identity, application
  identity, target identity, and ordinal as canonical graph relationships.
  Queries such as the eventual `functions.filter(all: @extern)` read those
  application relationships directly; B does not copy them into an attachment
  registry. Explicit `#environment: extern()` registration is not part of the
  model. The macro environment is the graph-scoped capability surface:
  `#environment.target`, `#environment.macros`, and
  `#environment.diagnostic(...)` are direct accesses rather than members of a
  second `#environment.graph` object. The process graph retains imperative
  calls as environment effects. Validation uses ordinary `if` control flow
  with direct `#environment.diagnostic(...)` effects; there is no separate
  diagnostic Macro or optional-fallback registration convention.
- Representation macros emit ordinary initializer applications inside
  target-owned `#environment` extensions. `LLVM(type: ...)` belongs to the
  target Declaration and `LLVM(value: ...)` belongs to its Application; there
  are no privileged `LLVM.type` / `LLVM.value` helper functions and no
  redundant `-> LLVM` result promise. Macro collection retains every authored
  Environment as a node containing ordered ordinary Range nodes. Resolving a
  Macro Application gives that Application ordered references to all of its
  Macro's Environments; LLVM lookup then walks those relationships rather than
  a special emission table.
- Temporary macro execution products are keyed by that canonical Application
  identity. They do not copy the target syntax or target token: emission walks
  from product to Application and then reads target/declaration relationships
  from the graph. Product rows therefore have no positional coupling to
  Application rows. The remaining scalar status/layout/value columns are an
  execution bridge until emitted products gain stable graph identities.
- Compiler B now retains authored collection production as graph data. In
  `@many state integers: @integer`, the collection resolves its selector to
  the exact `integer` Macro declaration; in
  `@many derived commands: integers -> LLVM`, the production resolves its
  source collection and output Construct identities. The selector Macro must
  contain an initializer Application whose identity matches that output
  declaration. LLVM execution is admitted
  only when a Macro Application feeds one of these resolved productions. A
  collection-production runner walks every Application selected from the AST,
  executes its Macro process, and appends a product carrying both Application
  and production identity. The derived `commands` collection is therefore
  populated before LLVM rendering, and the backend no longer mirrors every
  unrelated Macro Application into an empty product row. General execution of
  the macro body still owns the remaining scalar schema bridge.
- Compiler B's Core `UUID` is one immutable `@many(count: 16)` `let` property of
  `Byte`, replacing the transitional `String` backing and integer-returning
  byte accessor. The graph retains the exact count argument and relationship;
  composing that property product into an enclosing `[16 x i8]` LLVM aggregate
  remains general `@many` layout work rather than UUID-specific backend logic.
  UUID v4 generation is separate policy over this representation.
- Collection transformations use that same relationship model. An empty
  `macro collectionModifier(): Macro {}` marks macros such as
  `filter(named:)`; the macro signature retains its `@many -> @any`
  cardinality mapping. Cardinality names are retained token identities rather
  than a closed compiler enum. `map(transform:)` is collected through the same
  marker while its Function argument describes the element transformation.
  Calls and terminal projections are canonical Applications: each retains its
  own identity, predecessor Application, and resolved Function or Macro
  declaration. `Something.something.filter(...).map(...)` therefore becomes
  one root -> filter -> map identity chain, and a modifier receives its
  predecessor directly as `#environment.target`. Executing the modifier body
  and materializing its bounded output remain a later process slice.
- The existing `many` macro now queries
  `#environment.macros.filter(all: @collectionModifier)` and directly
  splices the plural `#modifiers` identity into an extension of its target
  Application. The splice cardinality handles none, one, or many identities;
  no authored `map`, collection registry, or attachment helper is involved. B
  retains the query and target/source-collection identities as one
  Application-provision facet. Materializing that collection into deduplicated
  target-to-Macro relationships is the next graph-expansion slice.
  Its element type is guaranteed declaration knowledge and is read directly
  from `#environment.target.Declaration.type`; it is not represented as an
  optional diagnostic binding.
- `Core/Extern.range` still exposes `ExternRegistration` only because accepted
  Compiler A compiles and links B today and recognizes that nominal result as
  its extern ABI registration. It is a bootstrap adapter, not the V3 model;
  B's resolved macro application relationships replace it once B owns
  compilation of those Core declarations.
- Parsing is side-effect free: `compilerBParse` returns rendered syntax and its
  validity summary as data. The command-line entry decides whether to print it.
- `CompilerBSyntaxRevision` retains one source and its syntax store. A typed
  revision operation accepts previous and current revisions and produces a
  `CompilerBSyntaxDelta` of added, removed, and changed signals. Each signal is
  a message containing only change kind, revision, and syntax identity; it does
  not copy nominal type, declaration name, or source range. `Revision.range`
  owns signal derivation, `Query.range` independently applies a nominal query
  function to the identity, and `Observation.range` composes the pipelines
  explicitly. The
  revision operation is currently a defunctionalized callable boundary; it can
  become a first-class transform once indirect function values are separately
  proven.
- The first diff key is declaration marker plus name. It survives source-offset
  shifts, but overload/signature identity and nested syntax deltas remain later
  slices.
- The first backend slice queries each Function identity, signature, body,
  Return relationship, represented type, and literal directly from one syntax
  revision, then emits LLVM. There is no copied Function index, parallel IR
  function store, duplicate discovery pass, or integer-literal registry. Its
  product links and exits without `RangeCompilerHost.c`; the bootstrap compiler
  process still uses the temporary inherited runtime.
- Console lowering will keep one genuine foreign boundary: Range owns typed
  inspection, formatting, value/revision events, and buffering; libc or the OS
  owns only the final byte write.

Run the current slice with:

```sh
scripts/run-compiler-b-bootstrap <route>
```
