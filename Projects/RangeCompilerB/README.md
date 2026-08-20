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
  target/result signatures are checked at each resolved application. Compiler
  B deliberately has no authored `{ environment in ... }` binder and no
  special `inspect` interpreter. A future executable macro body receives its
  compile-time context implicitly and runs through the same typed body/process
  representation used for ordinary functions.
- `let` and `state` now share a canonical `Member` facet with owner identity,
  keyword and identifier tokens, type token, and initializer token span.
  Ordered macro applications target those same member identities. Empty marker
  `macro print(): Member {}` applications are the graph fact: they resolve to
  the exact Macro declaration identity, relate to owned state and top-level let
  targets without executing a body. Applying the marker to a declaration
  rejects at the typed target boundary.
- Macro application resolution happens once during compilation. Every
  application stores its resolved Macro declaration identity, application
  identity, target identity, and ordinal as canonical graph relationships.
  Queries such as the eventual `functions.filter(all: @extern)` read those
  application relationships directly; B does not copy them into an attachment
  registry. Explicit `#environment: extern()` registration is not part of the
  model; ordinary typed queries over `#environment.graph` are.
- Collection transformations use that same relationship model. An empty
  `macro collectionModifier(): Function {}` marks functions such as
  `filter(named:)`; the function signature retains its `@many -> @any`
  cardinality mapping. Cardinality names are retained token identities rather
  than a closed compiler enum, so the same query also represents
  `@many -> @some` and `@some -> @many`. `map(transform:)` is collected through
  the same marker and preserves `@many -> @many` while its Function argument
  describes the element transformation. A qualified call retains the complete token path to its
  left as its predecessor root, so `Something.something.filter(...)` supplies
  `Something.something` to `#environment.target.root()` without a modifier
  registry or function-name dispatch. Executing the modifier body and
  materializing its bounded output remain a later process slice.
- The existing `many` macro now queries
  `#environment.graph.functions.filter(all: @collectionModifier)` and directly
  composes each canonical `#modifier` syntax value into an extension of its
  target identity. This is authored Range code, not a compiler-known
  collection registry or attachment helper. B retains the query as a canonical
  local call and `extension target { #source }` as a general member-composition
  facet. Executing the collection closure into deduplicated target-to-Function
  relationships is the next graph-expansion slice.
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
