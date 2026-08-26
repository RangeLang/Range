# TODO

- [x] Establish standalone project roots: `Projects/RangeView/` owns the
  RangeView framework and example entrypoint, while `Projects/RangeCompilerB/`
  owns Compiler B. Remove the obsolete GPUCanvas and native-triangle example
  projects.

Priority and dependency order live in [MILESTONES.md](MILESTONES.md). This file
owns the actionable checkboxes for the active and deliberately deferred work.

## Website search discoverability

- [x] Make the Website self-contained and publish one 11-route SEO contract
  with canonical metadata, structured data, `robots.txt`, `sitemap.xml`, and
  production draft/private-route indexing guards.
- [x] Release the verified Website snapshot to `production` and deploy it at
  `https://rangelang.org` with the pinned Sveltely submodule and a rollback
  image retained.
- [x] Point `www.rangelang.org` at the production server and verify its
  permanent path-and-query-preserving redirect to the apex origin.
- [x] Verify the domain in Google Search Console, submit the sitemap, and add
  the four priority URLs to Google's crawl queue.
- [ ] Import the verified property into Bing Webmaster Tools and submit its
  sitemap and priority URLs.
- [ ] Inspect Google and Bing sitemap and URL processing after 48 hours and
  seven days.

## Active compiler work

- [ ] Grow Compiler B as a greenfield compiler through bounded runnable slices;
  follow `Development/CompilerForkArchitecture.md`.
  - [x] Freeze Compiler A as the accepted bootstrap and reference
    implementation. A builds B but does not supply syntax or later products for
    B to consume.
  - [x] Reduce `Projects/RangeCompilerB/` to its B-owned entry, lexer/parser,
    minimal Core, selected low-level dependencies, and runtime; remove the
    copied A compiler tree and unused copied Core/Foundation sources.
  - [x] Remove explicit generic binders and generic type applications from
    Compiler B's accepted language model.
    - Element identity, cardinality, and input/output correspondence come from
      graph relationships instead of authored `<Element>` parameters.
    - [ ] Replace the remaining accepted-A `Buffer<Int>` and `Buffer<Byte>`
      bootstrap storage spellings with B-owned graph-native cardinality storage
      before the complete Compiler B source set becomes a self-source fixture.
  - [x] Establish `scripts/range check-compiler-b` as the focused runnable B
    gate.
    - It proves file and directory routes, a
      write/append/read/copy/move/remove round trip, lexer output, and the
      current function/construct/Block syntax rows.
    - It does not prove B self-compilation, candidate/reproduction identity,
      the complete language, or bootstrap promotion.
  - [ ] Complete the self-source lexical and syntax checkpoint.
    - The coarse parser currently reports function and Block rows for B's
      `Main.range` and `Lexer.range`; this is baseline observation only.
    - [x] Add typed `TokenID` and retained token storage with kind and exact
      source range; rendered token text must not be the parser's input.
    - [ ] Make lexing string- and comment-aware, including escaped string
      delimiters, so braces and declaration-like text inside lexical regions
      cannot become syntax.
      - [x] Retain quoted strings, including escaped delimiters, as single
        tokens so macro query labels, diagnostic messages, and interpolated
        LLVM templates cannot leak braces or declaration words into parsing.
        Comment regions remain pending.
    - [x] Make parsing consume retained token identities instead of rescanning
      raw source for declaration keywords and balanced braces.
    - [ ] Extend `scripts/range check-compiler-b` to parse B's own `Main.range`
      and `Lexer.range` and assert their exact expected top-level declarations
      and Block relationships.
  - [x] Add stable `SyntaxNodeID` values before adding more syntax marker or
    relationship columns; buffer rows remain physical locations, not semantic
    identity.
    - [x] Establish the first typed `TokenID` -> `SyntaxNodeID` backend path for
      no-parameter functions whose complete body is `return <integer>`.
      Declaration discovery deliberately runs twice through one canonical
      identity index, but emits exactly one LLVM function definition.
    - [x] Add B's first literal scalar data unit: `Byte` is one unsigned
      eight-bit value, `String` owns `Buffer<Byte>`, and integer lowering
      carries byte count explicitly (`Byte = 1`, current `Int = 4`) through
      indexing and IR. The focused runtime-free products prove `Byte` lowers
      to LLVM `i8`, `Int` lowers to LLVM `i32`, and both execute with exit 42.
    - [x] Replace Compiler B Core UUID's transitional String storage with one
      immutable `@many(count: 16) let bytes: Byte` relationship.
      - The focused graph proof retains the Byte `let` property, typed count argument,
        and exact `@many` Application relationship. General nested `@many`
        product composition must prove the eventual `[16 x i8]` LLVM layout;
        do not special-case UUID in the backend. UUID v4 generation remains a
        separate operation over the 16-byte representation.
    - [x] Replace Byte's bootstrap `Int<.unsigned, 8>` field and backend
      type-name matching with a resolved `@integer` relationship, canonical
      `let bits: Int(...)` / `let signed: Bool(...)` property facets, and a
      parser-materialized integer-literal identity -> token -> value relation.
      Runtime-free Byte and Int products derive nominal LLVM aggregate types
      and values from graph queries; invalid widths and overflowing literals
      reject before emission without a parallel representation store.
    - [x] Execute the Range-authored `@integer` macro body over the stable graph
      and make its emitted LLVM products the backend input.
      - Function and macro declarations share one canonical process/expression
        graph. Macro execution reads application, target, and optional value
        facts by walking each resolved Macro Application's ordered Environment
        relationships and their ordinary `LLVM(type: ...)` and
        `LLVM(value: ...)` initializer Application nodes,
        validates each product, and appends it to the transitional generic
        product store. The backend selects products by target identity and
        never by the `integer` macro name; returned LLVM aggregates and
        redundant `-> LLVM` promises are not execution paths.
    - [ ] Replace the bootstrap-bounded `Buffer<Int>` scalar value column in
      the canonical Return facet with a canonical arbitrary-precision value
      identity. Token and literal identities are already separate; this is
      required before integer literals can exceed the accepted compiler's Int.
    - [x] Replace the disposable/backend lexer split with one retained token
      store and concrete `CompilerBToken { id, kind, start, end }` values.
      Identity equality compares `TokenID`; lexical equality compares source
      bytes over retained ranges without allocating token text.
    - [x] Move stable source-derived identities into the general syntax store;
      Block parent relationships now reference declaration `SyntaxNodeID`
      values rather than physical rows.
    - [x] Reduce the common syntax node to `SyntaxNodeID + TokenSpan`; retain
      the token store for the lifetime of each syntax revision so byte ranges,
      names, and rendered locations are derived from token identities instead
      of copied into every node.
    - [x] Materialize the first separate Core-shaped facets for
      `Function.Declaration`, `Construct.Declaration`, and `Block`. Function
      and Construct queries resolve identity-token and body-syntax
      relationships through individual typed functions; no central syntax-kind
      enum owns those nominal types.
    - [x] Retain independently owned previous and current syntax revisions and
      apply a typed difference operation that produces added, removed, and
      changed signals. Each signal carries only change kind, revision, and
      syntax identity. Separate `Function.Declaration` and
      `Construct.Declaration` query pipelines resolve nominal facts such as
      identity and body; query results and source ranges are not copied into
      the signal. Declaration matching uses its current semantic key (nominal
      facet plus identity token), so source-offset shifts do not turn an
      existing declaration into remove-plus-add.
    - [ ] Make the program entry point a declared graph relationship instead of
      an inherited filename convention. An entry macro (for example `@main`)
      attaches to one function; the backend selects the entry by that
      relationship, and `scripts/run-compiler-b-bootstrap` stops special-casing
      `Main.range` / `FocusedEntry.range` bundle order.
      - Exactly one entry per program is a graph fact: zero or multiple entry
        applications reject at declaration time with a focused Fail fixture.
    - [x] Reshape syntax observation as a revision pair. An observation is two
      instances of the same declaration bracketing the difference step, not a
      single-revision lookup.
      - The delta store records each signal's counterpart identity at
        difference time (semantic matching stays in the revision operation);
        observation resolves both halves without re-matching. Each signal
        renders one `observation` row with explicit before/after halves whose
        pair shape agrees with the change kind; absence is a pair half, so no
        diagnostic channel and no standalone `found=false` row remain. One
        kind-reporting helper over the shared `CompilerBDeclarationFacetStore`
        replaced the Function/Construct render cascade, and the
        `SyntaxRevisionDifference` fixture plus
        `scripts/check-range-compiler-b` assertions moved in lockstep with the
        changed signal asserting both halves.
    - [ ] Extend pair observation from declaration presence to facet-level
      deltas: a changed pair renders which facets differ (identity name, body,
      members) as the recorded trace of one structural comparison walk.
      - Equality is the same walk short-circuited to a Bool; surgical update
        emission is the same walk made constructive. Implement the walk once;
        the projections must not fork into independent comparison code.
      - Observation code keeps no diagnostic channel: both sides of the step
        are already-valid graphs, so every rendered fact is graph knowledge.
    - [ ] Sweep the remaining Core macros (`Bool.range`, `Integer.range`) for
      the Many.range diagnostic principle: graph-known
      facts are read without diagnostic fallbacks; only value-level facts the
      graph cannot know emit `#environment.diagnostic(...)`.
      - Extend `scripts/check-range-compiler-b` with per-macro assertions
        mirroring the existing Many.range checks (no optional String fallback
        on guaranteed knowledge, diagnostics through ordinary `if` control
        flow and the environment gate).
    - [ ] Rebuild the Compiler B gate around one produced compiler instead of
      per-fixture entry compilation.
      - [ ] Route fixtures into a B executable as input data (a parse/emit
        route per fixture file) instead of appending each fixture to the
        bundle as a compiled-in focused entry. This is the same capability as
        the self-source parse checkpoint aimed at smaller files first.
      - [ ] Memoize the A -> B build in the gate's work directory keyed by a
        content hash of the bootstrap binary, the source inventory, the
        runtime C sources, and the clang flags. The cache is derived
        memoization only; never commit a B binary as a second compiler
        authority.
      - [ ] Until fixtures are inputs, run the independent per-fixture
        bootstrap invocations through a bounded parallel job pool; a failing
        fixture must still fail the whole gate with its exact message.
      - Standing-graph direction note: every run currently constructs the
        complete revision graph from text and destroys it. The end state
        constructs only the empty graph (the identity value of the graph)
        and everything after is applied deltas — parsing a source is itself
        the observation `(empty, parsed)`, an all-added pair, making the
        parser a special case of the observation machinery rather than a
        separate constructor. Entry (`@main`) is the designated observation
        point where batch-time callers ask the standing graph for a value,
        not where execution begins.
    - [ ] Complete the macro-family target model promoted ahead of the
      self-source syntax checkpoint:
      - [x] Retain macro target unions and use them for admission before body
        execution. `@member` is authored as
        `Let | State | Derived | Binding`, and a transform targeting `@member`
        resolves that signature through the graph rather than matching a
        nominal `Member` spelling.
      - whether `target` should be a derived query over the environment gate
        (for example `#environment.filter(type: Self)`) rather than an
        intrinsic, leaving the gate itself as the single macro intrinsic;
      - whether the paths a macro body mentions should be its constraints, so
        a mentioned path that exists on no admitted materialization rejects at
        declaration time without a separate constraint syntax;
      - [ ] Split the current shared property-row storage into concrete Let,
        State, Derived, and Binding facets and retire its `kindCodes` column.
        The source-level abstraction is already `@member`; this remaining
        storage cleanup must not reintroduce a nominal Member target.
      - [ ] Invert the family from enumerated to accumulated: the concretes
        become declarations and `@member` becomes a conformance marker
        targeting them (`@member construct Let`), so the property family is
        the open set of declarations carrying the @member relationship rather
        than the closed union authored in `member()`'s signature.
        - Conformance is application: a transform constrains by the @member
          relationship (the `filter(all: @collectionModifier)` pattern in
          Many.range), so extending the family is one new declaration plus
          one application, with no union edited anywhere.
        - Requires the previous storage split: `Let`, `State`, `Derived`, and
          `Binding` must exist as declarations before anything can attach to
          them. Until then the union-authored `member()` marker stays the
          accepted checkpoint, and `scripts/check-range-compiler-b` asserts
          its exact current form.
      - [ ] Give conformance an attachment scope: the `@member` application
        carries where the concrete may attach (`@member(target: Construct)`
        on `construct Let`), verified as a graph query at every ownership
        edge.
        - Scope is declared where underived and derived where derivable:
          `Let` and `State` imply nothing about their owners, so their scope
          is a genuine declared fact; `Derived` mentions sibling members and
          `Binding` references another's `State`, so their scope derives from
          their own semantics. Where both exist, declared must agree with
          derived. An omitted `target:` argument is the identity value — the
          unconstrained or derived scope — so the argument appears only when
          it says something.
      - Composition-algebra note for the scope rules: a construct is a
        product (all members coexist) and an enum is a sum (one case
        active), so product citizens (`Let | State | Derived | Binding`)
        cannot sit in a sum, and `case` is the sum citizen — to `Enum` what
        member is to `Construct`, suggesting a dual `@case` marker.
        Algebras nest freely while citizens do not cross: an enum cannot own
        `state`, but a case can own a product (associated values are a
        product nested in a sum arm).
      - Acceptance case for the unified generic parameters review
        (`AGENTS.md`): the pair-observation renderer
        (`compilerBRenderSyntaxSignalObservation` and its declaration-only
        resolver) must collapse to one kind-anonymous declaration — pair
        resolution, presence, and change-kind agreement written once, with
        the facet family, per-half facts, and rendering supplied by each
        concrete through its family conformance. If the generics design
        cannot express that collapse, the design is wrong. Do not hand-write
        per-kind observation resolvers (members, macro applications) in the
        meantime beyond what a slice's proof requires.
    - [ ] Replace the defunctionalized syntax revision operation with a
      first-class `(previous, current) -> product` transform after indirect
      function values have their own focused accepted-compiler proof.
      - The accepted bootstrap currently proves individual owned revision
        values, but this slice deliberately avoids nesting two Buffer-owning
        revisions inside another owned aggregate.
    - [ ] Collect the remainder of each rich Core syntax representation into
      facets and relationships: parameters, rich type references,
      members, and complete Block contents.
      - [x] Make the parser the sole structural token interpreter for the first
        lowering slice. One syntax revision now owns ordered declaration macro
        applications, function-signature return-type tokens, and Return
        relationships; representation execution and backend indexing consume
        those facets without rescanning tokens for `function` or `return`.
      - [x] Remove the temporary V3 `{ environment in ... }`/`inspect` model.
        - Macro declarations and target/result signatures remain canonical.
          Empty marker applications are graph relationships, while executable
          macro bodies will receive compile-time context implicitly through the
          shared typed body/process pipeline. B has no special self-returning
          macro interpreter.
      - [x] Execute the first real macro body through a shared typed process
        representation without an authored environment binder.
        - The bounded first process retains Return, call, labeled argument, and
          environment-projection expressions once for both functions and
          macros. `@integer` proves target/member/value reads and generic LLVM
          product emission; locals, branches, and additional operations remain
          later process slices.
      - [ ] Complete independent macro execution products for representation
        functions.
        - [x] Retain Macro Environments as plural graph relationships containing
          ordinary Range nodes. Macro collection records every authored
          Environment; each resolved Macro Application carries ordered
          references to its Macro's Environments. `@integer` and
          `@many(count:)` contain independent
          `LLVM(type: ...)` and `LLVM(value: ...)` values inside extensions of
          the target Declaration and Application; qualified helper calls,
          returned LLVM aggregates, `-> LLVM` result promises, and the flattened
          environment-emission table are retired.
        - [ ] Bind typed macro arguments and Member element-type queries from
          canonical graph facets, then compose `@many(count:)` into enclosing
          LLVM aggregate layouts and many-valued application emission.
          - [x] Retain required labeled macro parameters and application
            arguments as canonical signature/application facets; validate
            missing, duplicate, unknown, and mistyped `Int`, `Bool`, and
            `String` bindings, and expose bound scalar values to LLVM source
            template interpolation without macro-name dispatch.
      - [x] Retain the first validation-driven local process graph from the
        canonical `Core/Macros/Integer.range` source.
        - Two direct local graph queries resolve by
          application/declaration/target identity. Ordinary `if` operations
          guard two direct environment diagnostic effects; the redundant
          diagnostic annotation applications, optional String fallback values, and
          `diagnostic` Macro are removed. A bootstrap-only empty `integer`
          signature lets frozen Compiler A build B without making it the V3
          macro authority.
        - [x] Lower the canonical macro's independent `LLVM(type: ...)` and
          `LLVM(value: ...)` Environment nodes through graph identity. `\(bits)`
          resolves the local query to one Member and renders its scalar
          initializer, while target identity and application value projections
          transfer their retained facts into the template. Runtime-free Int
          and Byte products now use this canonical Core macro, link, and exit
          42; local Void diagnostic applications remain non-emitting graph
          effects.
      - [x] Retain `let` and `state` as canonical Member facets and permit
        ordered macro applications to target their shared syntax identities.
        - Members retain owner, keyword, identifier, type, and initializer
          token span. Empty marker `macro print(): Member {}` resolves both
          owned state and top-level let relationships; applying it to a Construct
          rejects at the typed target boundary without executing a macro body.
      - [x] Resolve macro applications once as canonical graph relationships.
        - Every resolved application stores its exact Macro declaration syntax
          identity alongside application and target identities. Relationship
          queries read those columns directly without an attachment registry,
          rescanning source, re-resolving names, or executing marker macros.
        - Empty `macro extern(): Function {}` applications relate directly to
          two Function targets without body execution. Explicit
          `#environment: extern()` registration is not part of this
          architecture; ordinary macro graph queries remain available.
      - [x] Collect collection modifiers as canonical macro relationships and
        retain their cardinality transforms on Applications.
        - `@collectionModifier` resolves to the exact marked Macro identity;
          `filter(named:)` is a macro retaining `@many -> @any` as its
          input/output
          cardinality mapping rather than a generic parameter or name-keyed
          compiler rule.
        - `map(transform:)` uses the same marker and retains its cardinality;
          element transformation is expressed by its Function input while the
          graph carries cardinality and predecessor correspondence.
        - Cardinalities remain source-token identities rather than a closed
          compiler enum.
        - [x] Stabilize member access and chained execution as one canonical
          Application relationship.
          - Every Application retains its own syntax identity, predecessor
            Application, and resolved Function or Macro declaration identity.
            `Something.something.filter(...).map(...)` proves the exact
            root -> filter -> map identity chain and reads `many -> any -> many`
            from the resolved Macro declarations.
          - A terminal projection such as `filter(...).first` is another
            Application, while optional fallback remains a separate expression.
            Token-root reconstruction, function-modifier rows, and copied
            callee-segment storage are retired.
        - [x] Author direct modifier provision in the existing `many` macro.
          - `many` queries `#environment.macros` for every
            `@collectionModifier` and splices the resulting plural `#modifiers`
            identity directly into an extension of the target Application.
            The splice cardinality materializes none, one, or many identities;
            there is no authored traversal, attachment helper, or copied
            modifier declaration.
          - Compiler B retains the graph query as a canonical local call and
            the direct target/source-collection identities as one
            Application-provision facet. Materializing the selected identities
            into deduplicated graph relationships remains pending.
          - [x] Make the macro environment itself the graph capability surface.
            - Graph collections and effects are direct `#environment` members:
              `#environment.macros` and `#environment.diagnostic(...)`. The
              parser retains calls as environment effects instead of a
              conflicting `graphEffects` lane. `many` reads its guaranteed
              declaration element type directly and no longer marks that query
              with a diagnostic annotation or an optional String fallback.
        - [ ] Execute the modifier process over the selected graph collection
          and materialize its bounded `@any` output; this checkpoint proves
          collection and query shape, not `while`/`append` evaluation.
      - [ ] Remove the A-facing `ExternRegistration` bootstrap adapter once B
        compiles its own Core extern declarations. Until then accepted Compiler
        A requires the nominal macro result to register the foreign ABI; B's
        own resolved macro application relationships are the V3 model.
      - [x] Lower the first scalar Function products directly from graph queries.
        - Removed the copied Function index, identical IR function store,
          duplicate discovery pass, and integer-literal registry. LLVM emission
          now queries Function, signature, Block, Return, represented type, and
          literal facts from the canonical revision per declaration.
        - [x] Key temporary macro execution products by canonical Application
          identity and remove their copied target syntax/token columns. Product
          lookup no longer assumes Application rows and execution-product rows
          share an index; target and declaration relationships are read back
          through the Application graph facet.
        - [x] Retain the first authored collection-to-collection production and
          route LLVM macro execution through it.
          - `@many state integers: @integer` resolves its selector to one Macro
            identity, while `@many derived commands: integers -> LLVM` resolves
            its source collection and output Construct identities. An authored
            Environment node must initialize that output declaration; a
            mismatch is a focused syntax rejection. The backend executes
            matching Macro Applications through this relation rather than the
            `integer` name or a declared result promise.
          - [x] Run the resolved production and populate its derived product
            collection by walking every selected AST Macro Application.
            - Products retain both source Application and destination
              production identity. A focused two-Construct proof produces two
              LLVM collection products, while unrelated `@many` Applications
              produce no placeholder rows. This also
              removes the former Application-row/product-row alignment
              dependency.
        - [ ] Move the remaining execution outputs (`status`, emitted LLVM,
          integer layout, and application value) into stable graph products as
          their syntax identities and invalidation behavior are implemented.
      - [ ] Lower the first `@print` value event through Range-owned formatting
        and buffering to one true libc/OS byte-write extern; do not move
        inspection or timeline policy into the foreign shim.
    - [ ] Give macro expansion products stable syntax identities before
      broadening body syntax or relationships.
  - [ ] Route calls through `FileManager` receivers once a focused fixture
    proves construct member calls with `String` parameters and returns across
    the accepted Compiler A ABI/discovery boundary; until then B calls the same
    Range-owned `fileManager...` implementations directly.
  - [ ] Remove `Runtime/RangeCompilerHost.c` from Compiler B's link; Range must
    own ordinary runtime behavior and generated LLVM must call true libc/OS
    symbols directly.
    - [x] Prove direct authored `opendir`, `readdir`, and `closedir` declarations
      and remove the C-owned directory wrapper, copied path, recursive policy,
      and close operation. This is only a partial boundary proof while the host
      file remains linked.
    - [ ] Replace A-generated calls to the inherited String, RawBuffer,
      construct-storage, argv, process, file, and transient-allocation runtime
      ABI with Range-owned/native LLVM definitions before deleting the host.
    - [x] Emit, link, and execute the first B-owned runtime-free LLVM product:
      `function answer(): Int { return 42 }` becomes nominal `%Range.Int`
      type/value LLVM plus a native `main`, links without any runtime source,
      and exits `42`.
    - Do not replace C with a hand-authored `.ll` runtime; that changes the
      frontend spelling without making Range the implementation authority.
  - [ ] Add resolution, CFG, ownership, MIR, and emission only as later B-owned
    products derived from retained syntax identities, each with its own
    runnable focused proof.
  - [ ] Attempt B self-compilation only after those required products exist. At
    that milestone, require byte-identical candidate/reproduction LLVM and
    executables before describing B as self-hosting.
  - [ ] Use the Compiler A escape valve only for a concrete focused blocker,
    with no architecture-preserving B solution, and only after explicit
    maintainer approval of the general A change and bootstrap promotion.

## Deferred and historical backlog

Compiler A implementation tasks below are frozen reference work, not active
compiler direction. Reactivate one only through the documented Compiler A
escape valve. RangeView remains deferred unless it is explicitly reintroduced.

- [ ] Finish the RangeView app-to-window entry hook.
  - [x] Make `@app` emit the single top-level `@main` block through
    `#environment`, with root-graph duplicate-main rejection.
  - [x] Have the emitted main call the application backend, which performs
    SDL setup, window creation, the event loop, and SDL teardown.
  - [ ] Hand the resolved route/page tree to the window runtime instead of
    rendering the current fixed Stack example.
  - [ ] Prove `@component` modifier accumulation with focused macro fixtures.
    - `@component` now emits one ordered `@many modifiers: @modifier`
      relationship in the idealized RangeView source; compiler-backed proof
      still needs positive member-access accumulation and duplicate-slot
      rejection fixtures.

- [ ] Replace name-keyed compiler runtime bridges with authored Core `@extern`
  declarations while keeping `@builtin` roles as independent semantic tags.
  - [x] Make `@extern @builtin(.target)` classify as an external implementation
    with target-role metadata, and suppress the legacy LLVM declaration when
    the same foreign declaration was authored in source.
    - Verify one `targetPointerBits` declaration, one call, linked exit `42`,
      plus the unmigrated fallback fixture linked exit `64`.
  - [x] Prove the generalized legacy-declaration filter, which now removes any
    runtime-prelude or metrics declaration already supplied by authored source
    instead of accumulating one suppression special case per foreign symbol.
  - [x] Promote the declaration-filter checkpoint before admitting any authored
    compiler extern into the accepted compiler's own source inventory.
    - The first promotion attempt correctly refused the checkpoint because the
      candidate and reproduction LLVM differed; candidate auditing and both
      LLVM validations passed, and the accepted bootstrap remained unchanged.
    - The retained artifacts differ only in placement of the single identical
      `targetPointerBits` declaration: removing that line from each makes the
      LLVM byte-identical. The generalized filter preserves legacy declaration
      order while no authored replacement exists, so promote it alone first;
      do not include the first authored compiler extern in this checkpoint.
    - Accepted as `bootstrap-34a59bd53f2b` after byte-identical LLVM and
      executable reproduction plus accepted-bootstrap integrity verification.
  - [x] Add `Core/Macro/Extern.range` and `Core/System/Target.range` to the
    canonical live compiler Core inventory without rewriting accepted-bootstrap
    provenance, author `targetPointerBits` there, and delete its legacy runtime
    declaration fallback after the migrated fixed-point proof.
  - [ ] Migrate the remaining scalar bridges in small proven slices; defer
    ownership-sensitive Buffer and String pointer APIs until their foreign ABI
    representations are explicit.
    - [x] Author and focused-link `targetPointerBits`,
      `commandLineArgumentCount`, `stringTransientRegionMark`,
      `stringTransientRegionReset`, `compilerMetricsReset`, and
      `compilerMetricsFunctionEnd` as external implementations with independent
      builtin roles: one canonical declaration and call each, native exit `42`.
    - [x] Canonicalize foreign parameter declarations as ABI types without
      declaration-local LLVM names, matching the legacy runtime signatures and
      preserving names only at call/definition sites where they carry values.
    - [x] Remove all six migrated spellings, intrinsic IDs, and ABI special
      cases from the runtime-builtin model while preserving its numeric slots
      as sparse compatibility holes; the extern declarations now own identity.
    - [x] Move target, process, and String declarations to their natural Core
      owners after admitting `Core/Macro/Extern.range`; keep compiler metrics
      declarations project-owned because they are not general Core APIs.
    - [x] Delete the six migrated legacy LLVM declaration fallbacks only after
      the Core-owned intermediate source passed byte-identical candidate and
      reproduction LLVM/executable proof.
    - [x] Promote the fallback-free extern checkpoint as
      `bootstrap-4f46e685e0e2` and verify the single accepted bootstrap LLVM,
      executable, and manifest authority.
    - [x] Teach authored extern signatures and MIR calls that `String` has a
      pointer-shaped foreign ABI; prove one declared/direct String identity
      call through native C linking and exit `42`, then prove byte-identical
      candidate/reproduction LLVM `6abddedb0bb6` and executables `35f067e1abcf`.
    - [x] Promote the String extern ABI checkpoint as
      `bootstrap-6abddedb0bb6`.
    - [x] Promote the general transient extern-`String` ownership checkpoint as
      `bootstrap-344d8be76525`, then move `commandLineArgument`, `runProcess`,
      and `runProcessBatch` into `Core/System/Process.range` and delete their
      runtime-builtin identities and legacy LLVM declarations.
      - Candidate/reproduction LLVM are byte-identical at `344d8be76525`,
        executables at `683f072b3b56`, accepted-bootstrap integrity passes,
        and the fallback-free focused extern suite links and exits `42`.
      - The Process-owned cleanup now also passes the focused build plan after
        admitting `Core/System/Process.range` to that source bundle, plus the
        compiler smoke gate and a fresh candidate/reproduction fixed point:
        LLVM `247cbafa8a1a`, executable `b6b99fb1700f`. This source checkpoint
        is proven but has not replaced the accepted bootstrap.

- [ ] Reduce full compiler checkpoint latency before using it as an inner edit
  loop.
  - [x] Allow a retry to reuse a preserved bootstrap-bridge proof only when its
    immutable Phase1 source bundle and two LLVM emissions compare byte for byte;
    revalidate both LLVM files, relink the bridge, and rerun its capability
    audits before candidate production.
  - [ ] Profile the measured optimized LLVM-emission phase, now 737 seconds for
    the Process-cleanup candidate, and make
    focused extern bundles the ordinary development proof; reserve one full
    candidate/reproduction comparison for a completed migration checkpoint.
    - [x] Attribute lowering and emitter buffer work without changing compiler
      semantics or accepted runtime inputs. The full compiler profile completed
      in 553,983 ms with a 5.41 GB peak footprint: memory derivation consumed
      89.9 seconds, MIR construction 61.0 seconds, and LLVM emission 93.7
      seconds. Emitter rendering consumed 49.5 seconds and planning 26.3
      seconds, while final buffer materialization consumed only 0.034 seconds.
    - [ ] Reduce the owned-path validation cost of
      `compilerCoreLLVMLowerHelperFunctionTypedObserved` as one bounded slice.
      - Its 4.209-second lowering spends 3.497 seconds in memory derivation and
        3.023 seconds in owned-path validation, where live transient storage
        grows by about 1.96 GB. Its entire emitter path appends only 43,468
        bytes and materializes 43,070 bytes, so do not optimize the final LLVM
        buffer copy as the cause of this hotspot.
      - [x] Test an explicit inline `CompilerOwnedPathTopology` construct as
        the prerequisite to owned-path validation. Compiler V1 passed. One
        controlled profile took 560,804 ms versus the 553,983 ms baseline and
        maximum resident memory rose from 3.75 GB to 4.00 GB, while memory
        derivation fell from 89.9 to 82.6 seconds and peak transient allocation
        fell from 2.80 to 2.65 GB. The mixed single-run result is inconclusive;
        the prototype was removed pending a repeated controlled comparison.
      - [ ] Compare the inline construct witness against a direct arena phase
        invariant over repeated identical profiles. Do not replace the value
        with witness tables unless the prerequisite itself becomes variable-
        sized graph data.
        - [x] Implement the stronger inline preparation witness with issued and
          consumed arena generations. All four validation paths require it,
          returned-alias preparation has one producer, Compiler V1 passes, and
          the first retained profile completed in 547,671 ms. Versus the
          553,983 ms restored baseline, memory derivation fell from 89.9 to
          81.3 seconds, peak transient allocation fell from 2.80 to 2.65 GB,
          and maximum resident memory remained effectively flat at 3.75 GB.
        - [ ] Confirm the retained witness profile once before treating the
          measured improvement as a promotion-quality performance result.
        - [x] Add first-class nested probe telemetry to owned-path validation.
          Every probe carries a unique token plus parent/depth, function,
          instance, block, node, ordinal, item-count, status, and result
          context; the profiling runtime records true nanosecond duration,
          operation deltas, resident snapshots, and allocation-event-driven
          local raw/transient peaks. The full candidate profile completed in
          724,644 ms with 311,479 balanced probe pairs, zero malformed or open
          probes, and zero failed probe results. The retained authority is
          `range-compiler-profile.jW9S2k/Trace.tsv` (454,121,822 bytes).
        - [x] Split block evaluation at its semantic helper boundaries before
          changing storage. The balanced profile attributed the dominant work
          to local binding, construct moves, optional branches, assignment,
          and return transfer; application lookup and reference checks were
          not the substring source.
        - [x] Cache transparent-storage bases, opaque-representation status,
          and recursive tracked-storage status by arena-local type identity.
          Compiler V1 passes. On the same instrumented candidate workload,
          compilation fell from 1,122,239 to 484,553 ms, maximum RSS from
          3.23 to 2.04 GB, and peak footprint from 5.22 to 2.40 GB. The former
          semantic knots fell from 25-73 aggregate seconds apiece to at most
          1.29 seconds; local binding, optional branches, assignment, and
          return transfer performed zero substring operations.
        - [x] Make block merge consume an arena-scoped CFG relationship
          product. Forward adjacency now stores exact `cfgEdges` row identities
          and selection, merge, and backedge validation query those identities
          instead of carrying a second loose copy of predecessor block IDs.
          Cache Optional classification by arena-local type identity. Compiler
          V1 passes; block merge fell from 2.33 to 1.17 aggregate seconds and
          from 955,116 to 171,400 substring calls. The relationship product
          itself costs 40.5 ms across 3,910 arenas.
        - [ ] Replace block merge's remaining Optional name checks with one
          canonical declaration-identity relationship per source graph. Do not
          generalize local CFG edge row IDs into global identities: their exact
          identity is the owning function instance plus edge row. Confirm the
          complete profile separately; the first relationship profile reduced
          maximum RSS from 2.04 to 1.81 GB but regressed total instrumented
          time from 484,553 to 640,057 ms because of broad MIR/emitter variance
          and a 49.2-second `compilerBodyArenaResolveExpression` outlier.

- [ ] Recognize source shape from Core-authored, queryable syntax rules before
  usage, type, ownership, and representation analysis.
  - [x] Establish the smallest declared/applied control-flow graph baseline.
    `DeclaredAppliedIf.range` retains four declared functions, the outer and
    nested `render` blocks, one `If`, and the `ready`, `draw`, and `present`
    applications as exact typed nodes and role edges; the paired runtime
    fixture retains one conditional branch and exits 7. The source-miss
    candidate measured 575 seconds in Range LLVM emission versus 2 seconds in
    LLVM validation.
  - [x] Derive the same fixture's CFG from its typed body-node/body-edge
    artifact in shadow mode and compare block membership, successor edges,
    statement order, and call identities against the legacy body arena.
    `compilerTypedSyntaxCFGSnapshot` proves three syntax-identified blocks,
    true/false/fallthrough edges, six scheduled operations, and
    `legacyMatch=true`; lowering authority remains on the legacy arena.
    - [x] Research the Bend/HVM lineage, including Bend2's move from HVM2's
      ultra-eager reducer to HVM4's optimal lazy model, and record the
      transferable mechanisms, evidence boundaries, and limitations in
      `Development/BendHVMRangeResearch.md`.
      - [ ] Build one sequential demand-driven reducer over an existing typed
        compiler product: start from the requested product identity, derive only
        its dependency closure, prove exact product equality, and measure avoided
        plus executed semantic work before parallel frontier scheduling. Do not
        add another parser, IR authority, or evaluator.
  - [x] Define identifier start and alphanumeric continuation rules beside
    `Identity` in Core and make Range-authored syntax-template derivation
    and matching query them; no separate `IdentifierShape` wrapper exists.
  - [ ] Load Core syntax shapes into an immutable early source-shape graph and
    make declaration recipes consume it before member type linking and macro
    semantic evaluation.
  - [ ] Reduce the native lexer rules to a verified bootstrap encoding derived
    from the same Core shapes, then delete `isRangeIdentifierStart` and
    `isRangeIdentifierPart` as independent semantic authorities.
  - [ ] Cache the source-shape graph by source identity so later compiler
    phases consume and diff it instead of rescanning source text.

- [ ] Make persistent graph identity a first-class UUID value.
  - [x] Model `UUID.bytes` as an exact `@many(16)` relationship of
    `Int<.unsigned, 8>` values, and make `Identifier.id` carry `UUID` rather
    than exposing Buffer or String as its semantic identity.
  - [x] Execute Core relationship macros before the dedicated macro-graph
    snapshot and project every `admission:any` registration into one typed
    relationship-values slot on its target member.
    - `@contents` remains represented by the established block-contents slot;
      it is not duplicated as a generic relationship-values slot.
    - The focused value-ownership gate proved four deterministic slots,
      including UUID's ordered exact cardinality of sixteen, and completed in
      673 seconds: 669 seconds emitting LLVM, 2 seconds validating, and 2
      seconds linking.
  - [ ] Add an authored UUID creation operation backed by one private random
    byte capability; remove UUID generation from public `RawBuffer` APIs.
  - [x] Materialize macro-visible `Identifier.id` values as a nested UUID with
    sixteen deterministic bytes derived from the syntax/application source
    fingerprint instead of pretending one integer scalar is a String.
  - [x] Materialize each UUID element through a checked compiler byte boundary
    as `Int<.unsigned, 8>` / `compilerBodyTypeUnsigned8()` rather than storing
    ordinary Int values inside byte storage.
  - [ ] Crystallize exact finite relationship cardinality into graph
    occurrences with a stable ordinal and sixteen identity bytes derived from
    the target member fingerprint.
    - The first compiler-internal occurrence table reached
      `representationSensitiveABICapabilityBlocked` in
      `compilerRelationshipRegistrationsAreStructurallyValid` at capability
      stage `1780130`; it was removed from the compilable checkpoint while the
      authored `@many(16)` UUID shape and focused fixture remain.
  - [ ] Prove UUID copy, move, equality, hashing, formatting, and stable graph
    serialization before replacing the compiler's paired integer
    fingerprints and row-local identities.
    - [x] Separate changing Compiler V1 values from transitional identity hash
      keys at the type level. `CompilerValueFingerprint` now owns phase
      inputs/before/after values while Core `Identity` remains semantic
      identity. The paired value token remains identity-scoped and is not a
      cross-identity payload-interning key.
    - [ ] Wire the four reconciliation outcomes (reuse, update, insert, delete)
      only after UUID-backed `Identity` lookup confirms structural equality;
      do not treat a paired hash match as semantic or value equality.
  - [ ] Expose `.count`, `map`, `filter`, and related operations as direct
    queries/transforms over crystallized relationship values in Compiler V1;
    do not route them back through body resolution, CFG, or MIR.

- [ ] Finish declaration-gating the String read ABI.
  - [x] Reject direct use of undeclared String read builtins in ordinary code,
    declare `stringLength` and `stringByteAt` explicitly as neutral `@builtin`
    Core functions, and flatten `processArgumentRecord` so registered calls do
    not remain nested inside interpolation.
    - The cached candidate compiler compiled the complete current source graph
      through this boundary, exited `0`, and produced 8,536,874 bytes of LLVM
      with SHA-256
      `0be0ae3777cae8721e7e209679b6ff853884cda1b98a27b8c914ff7c5c1eb6fa`;
      Clang validation passed.
  - [ ] Upgrade those registered reads to `@builtin(.read)` after shared-read
    effects compose through aggregate-return summaries.
    - The typed read registration gets through discovery after flattening the
      process argument length, then fails first in
      `compilerBuildPlanLoadSourceBundle` with `detail=802`; migrating that
      caller exposes the same instance-effect failure in aggregate-return
      helpers, including `compilerBuildPlanValidateRecord` with
      `detail=12600022`. Keep the neutral registration as the compilable bridge
      rather than restoring undeclared magic or weakening ownership globally.
  - [x] Move Core clients onto the authored `String.count` / `String.byte`
    surface where that lowering is already proven.
    - `Process.processArgumentRecord` now uses `value.count`; `@hashable`
      already uses `id.count` and `id.byte(index:)`. The raw reads remain only
      as the transitional implementation behind `String` itself.

- [ ] Move `String` from encoded-byte identity to authored characters.
  - [x] Define the semantic boundary in
    [UnicodeTextModel.md](Development/UnicodeTextModel.md): a scalar is one
    valid Unicode code point excluding surrogates; a Character is one nonempty
    extended-grapheme sequence of scalars; a String is ordered Characters; and
    UTF-8 is an explicit external encoding boundary rather than String's
    identity.
  - [ ] Represent `UnicodeScalar` as a first-class code-point value and one
    independently addressable `Character` as an ordered relationship of those
    scalars. Character is the public extended-grapheme value; there is no
    competing public `Grapheme` construct.
    - [x] Declare `Character.scalars` as `@many UnicodeScalar`, not
      `Buffer<Int>`.
      - The focused Core bundle now includes the relationship declaration and
        its isolated prerequisites; `check-value-ownership --controls` proves
        that it compiles and registers alongside the literal-storage surface.
      - Active compiler `String` remains byte-backed until aggregate
        relationship lowering is proven.
  - [ ] Make `Character.scalars` and `String.characters` authored `@many`
    relationships rather than exposing Buffer as their semantic type.
  - [ ] Make authored relationship semantics available before typed member
    linking and storage validation.
    - Premature adoption first rejected as `unresolvedMacro`, then reached the
      relationship-occurrence capability blocker above after its Core source
      dependencies were added.
    - Extend the canonical Core source graph with those dependencies, execute
      `@many`, and retain its `RelationshipRegistration` as an early graph fact
      consumed by type, ownership, and representation planning. Do not recover
      by restoring Buffer as the authored member type.
  - [x] Keep the active compiler String model explicitly byte-backed until
    ordered Character storage has permanent aggregate lowering; this avoids
    presenting intended Core syntax as current runtime proof.
  - [x] Keep construct members directly in lexical scope; the new String model
    does not introduce or require a `self` receiver spelling.
  - [x] Remove the remaining `self.` receiver spelling from authored Core;
    implicit member binding is now the required compiler behavior.
  - [ ] Add permanent aggregate-element creation, indexing, mutation, and
    ownership lowering for `Buffer<Character>`.
    - The current concrete Buffer ABI only creates `Buffer<Int>` and
      `Buffer<Int<.unsigned, 8>>`; changing active String storage before this
      would make the C string shim interpret aggregate character records as
      UTF-8 bytes.
  - [ ] Remove `stringLength`, `stringByteAt`, `stringAppendStorage`, and
    `stringDestroy` from the authored String model.
    - Delegating `String.count` and `String.byte(index:)` directly through its
      authored Buffer first stopped macro evaluation at `pipelineFailureCode`
      `773462634`; the lower raw-buffer bridge then stopped at `9201002`.
      The proven checkpoint therefore restores the byte-backed transitional
      String implementation while aggregate relationship lowering is built.
  - [ ] Make UTF-8 an explicit `TextEncoding` boundary for files, processes,
    hashing, and other byte-oriented platform APIs.
  - [ ] Delete the superseded String byte builtins and C implementations after
    the compiler compiles and reproduces itself through the character model.
  - [ ] Prioritize graph-derived aggregate Buffer lowering in Compiler V1.
    - Replace `compilerBodyElementLayoutByteSize(typeKind:)`, which currently
      recognizes only one-byte unsigned integers and four-byte integers, with
      recursive representation derived from the element declaration graph.
    - Derive `Buffer<UnicodeScalar>`, `Buffer<Character>`, and nested owned
      element stride, alignment, initialization, move, and destruction from
      their authored construct relationships rather than builtin-name tables.
    - Let macros validate or synthesize typed representation artifacts, but
      keep the final physical lowering as an ordinary consumer of those graph
      values; do not hide another name-keyed lowering table inside a macro.
    - Replace `bufferCreateInt` / `bufferCreateUnsigned8` selection with one
      typed Buffer creation path. Keep only allocation, growth, and release as
      private platform ABI operations until Range emits those directly.
    - Remove public/compiler-authored `RawBuffer` calls from Compiler V1 after
      typed Buffer covers compiler tables and text emission. There is no live
      `TextBuffer`; retain the candidate audit that rejects its return.

- [ ] Migrate compiler failures to typed `@error` values at phase boundaries.
  - [x] Add the validation-only construct-level `@error` macro, require exactly
    one member named `message`, and provide the general concrete
    `Error(message:)`.
  - [x] Annotate `EncodingError` and `DecodingError` with the same macro.
  - [ ] Constrain the required message declaration to `String` once generic
    syntax-member selection is supported in compiler-executed macros.
  - [ ] Let generic constraints require a registered error capability so
    boundaries can express `Result<Value, Failure: @error>` without naming a
    privileged error base type.
  - [ ] Replace cross-function and cross-phase negative integers, packed
    arithmetic failure codes, and late diagnostic strings with nominal error
    values. Keep private local sentinels only inside bounded algorithms.
  - [ ] Retain typed compiler errors with their product observations and reuse
    or invalidate them through the same graph dependency rules as successful
    phase products.

- [ ] Move declaration parsing toward Core-owned `@syntax` recipes.
  - [x] Make compiler-owned `@capture` bind a macro application's balanced raw
    body directly to a declared `String` parameter without expression parsing.
    - The focused proof preserves recipe-shaped `$identifier` and `$members`
      text with nested braces, and rejects non-`String` captures and missing
      application bodies at macro parameter materialization.
  - [x] Adopt that boundary in Core as
    `macro syntax(@capture template: String)` and store the raw source on
    `SyntaxTemplate`; `Closure.Literal` is no longer the transport type for a
    freeform syntax recipe.
  - [x] Collect body and argument recipes from the existing macro-application
    graph, preserve lexer token boundaries, and bind `$field` captures to the
    annotated declaration's members with type-derived cardinality.
  - [x] Model closure literals, trailing applications, parameter clauses, and
    value-producing invocations as separate compositional Core syntax nodes.
  - [x] Replace `SyntaxTemplate`'s obsolete raw function field.
    - A later design pass briefly modeled the field as `Closure.Literal`; the
      compiler-backed `@capture String` boundary supersedes that transport.
  - [x] Resolve optional and collection-wrapped nominal captures to the nested
    declaration's own `@syntax` recipe.
  - [ ] Move recipe derivation into the Range-authored `syntax` macro.
    - [x] Materialize captured macro `String` values with their byte-backed
      storage and execute Core-authored `String.count` and `String.byte`
      through the macro evaluator.
      - The focused proof preserves exact recipe equality, a byte count of 34,
        and the expected bytes at the first character, both `$`/`{` capture
        boundaries, and the closing brace.
    - [x] Have the Range-authored `syntax` macro construct and return its typed
      `SyntaxTemplate` value.
      - `SyntaxTemplate` owns the captured recipe `String` and the target
        construct declaration's `[Let]` member syntax handles. It stores the
        first two resolved capture members plus their derived
        prefix/separator/suffix boundaries; it does not expose compiler table
        rows or raw-buffer spans.
      - The focused macro-execution proof observes the template value, exact
        captured recipe bytes, three typed member syntax handles, the resolved
        capture identifier, and its derived literal bounds.
    - [x] Resolve every recipe `$name` against the declaration's real `Let`
      members in the Range-authored `syntax` macro.
      - The macro scans the captured recipe once, compares each capture with
        `member.identifier.name`, and reports an error through
        `#environment.diagnostics` when any capture is unknown.
      - Macro syntax identifiers now materialize their names as byte-backed
        `String` values instead of hash-only placeholders, so Range-authored
        matching can use ordinary `String` reads.
      - The focused value-ownership proof covers both a two-capture recipe and the
        exact unknown-capture rejection boundary.
    - [x] Populate a single-capture `SyntaxTemplate.Match.capture` from an input
      `@syntax`
      value.
      - [x] Expose compiler-known `syntaxText(source:)` and
        `syntaxSlice(source:start:end:)` primitives to Range-authored macro
        execution.
        - The focused proof stringifies a declaration target, slices its
          source-backed `name` fragment, materializes the exact four bytes, and
          rejects a literal mismatch through macro diagnostics.
      - [x] Execute the required-match success path through the Range-authored
        member-function boundary and retain its populated `Capture.values`.
        - `@syntax` derives the resolved capture member and literal bounds;
          `matchRequired` stringifies the input, materializes a typed local
          source slice, and returns a populated `Match`/`Capture`.
        - The focused proof observes the referenced `Let`, one syntax value,
          and its exact source-backed span. The mismatch path still rejects
          through the Range-authored `match` diagnostics.
      - [x] Align template captures with declaration members instead of the
        unrelated property `Binding<T>` model.
        - `SyntaxTemplate` retains the resolved `Let` handles directly, and
          `Capture.member` is the identifier authority instead of duplicating
          its name as a `String`.
      - [ ] Generalize `Match.capture` to ordered captures only after
        multi-capture and cardinality semantics have their own focused proof.
        - [x] Derive and retain two ordered capture members and their literal
          separator bounds in the Range-authored `syntax` macro.
        - [ ] Materialize ordered `Capture` values in `[Capture]` on the
          returned `Match`.
          - Two directly constructed `Capture` fields on `Match` compile and
            execute successfully, so multiple capture children are not the
            blocker.
          - An inline `[Capture]` argument fails the called Range function's
            array-literal resolution with `pipelineFailureCode=9504010`, with
            either one or two elements. The propagated detail is `504`, which
            decodes to an expected `@syntax` element kind versus the actual
            nominal `Capture` construct kind. Moving an explicitly typed
            `[Capture]` into a local advances past resolution but fails later with
            `pipelineFailureCode=11372010`; two `Capture` locals similarly
            reach `11362010`.
          - Upgrade contextual array-of-nominal resolution and the subsequent
            local aggregate MIR path before adding the ordered-capture fixture.
      - [ ] Prove the successful value-bearing `Parsed<Match>` return path;
        the current success fixture intentionally uses the required-match
        boundary while the rejection fixture exercises `match`.
        - Direct return, a typed local, and explicit `Optional.exists` all
          reach the same Range-function preparation boundary
          (`pipelineFailureCode=9504010`).
      - Move nested member/cardinality selection out of the temporary
        `compilerSyntaxRecipes` observer after this source-binding layer has
        equivalent positive and rejection proofs.
    - [x] Restore the downstream Range-native project macro fixture without
      `environment.system.defaults.map`.
      - The Range-authored macro now emits only the missing `integer` and
        `bool` states onto its project target and returns the typed
        `ProjectDefaults` marker. The focused gate preserves an explicit
        `Int<4>` override and passes the complete project-defaults section.
  - [ ] Use the proven recipe graph for declaration recognition before
    retiring the corresponding compiler-owned validation path.
    - The first `Construct.Declaration` integration must preserve the bootstrap
      boundary: Core recipe declarations are collected first, and later
      declarations may consume them without invoking macro finalization during
      syntax capture.
    - Direct integration currently stops at the native ownership gate.
      Extending `compilerCoreParseConstructDeclarationParts` invalidated its
      owned aggregate-return proof (`detail=600011`); a scalar helper and an
      in-place recognizer both reached
      `representationSensitiveABICapabilityBlocked` at capability stage
      `14111`, which decodes to the unsupported owned-path move case
      `10000 + 411`. Upgrade that ownership path before routing authoritative
      declaration capture through recipes.

## 2026-07-29 Inline Representation Handoff

- [x] Migrate Core macro paths and focused fixtures from
  `#environment.target.declaration...` to
  `#environment.target.Declaration...`; expansion target splices now use
  `#environment.target.Declaration.identifier`.
- [ ] Finish the general uppercase inline-construct projection without
  regressing bounded candidate production.
  - The current draft adds resolution kind
    `compilerBodyResolutionInlineConstructProjection`, resolves a directly
    nested construct by parent syntax ID and name, interns its construct type,
    and reuses the macro-environment MIR projection with an encoded nested
    syntax ID.
  - Runtime materialization preserves the same source syntax handle while
    changing its nominal type to the selected nested representation.
  - `Testing/Macros/Fail/LowercaseInlineConstructProjection.range` and the
    updated canonical-target fixture are wired into
    `check-range-value-ownership`, but neither proof has completed.
- [x] Restore a bounded native producer run before continuing semantics work.
  - The first attempt failed quickly with
    `representationSensitiveABICapabilityBlocked` for
    `compilerBodyMIRBuildExpression` at capability stage `1780729`.
  - Extracting the full projection helper then failed with the same diagnostic
    for `compilerBodyArenaResolveInlineConstructProjection` at stage
    `1780096`.
  - Reusing the existing MIR environment projection removed those new
    aggregate-return helpers, but subsequent producer runs stayed at full CPU
    for several minutes and were manually interrupted. A cross-layer call
    from body resolution to the frontend graph helper was removed; the latest
    local body lookup draft was interrupted at the user's request and remains
    unverified.
  - Run `scripts/range check-build-plan`, then
    `scripts/range check-value-ownership`; do not infer later-gate success from the
    build-plan result.
  - The uninterrupted recovery run completed the development candidate producer
    in 583 seconds (`llvm-emission=580`, `llvm-validation=2`,
    `current-link=1`; 17 artifacts reused and 2,639 rebuilt).
  - `check-value-ownership` then reached the inline-projection proofs: the uppercase
    canonical-target fixture passed, and the lowercase fixture correctly
    exited 65 with empty stderr and
    `diagnosticKind=macroExecutionBodyInvalid`.
  - [x] Correct the harness's stale `diagnosticKind=bodyInvalid` expectation to
    the canonical `macroExecutionBodyInvalid` spelling, then rerun
    `scripts/range check-value-ownership`.
  - [x] Keep expansion authority on `Macro.Environment` by removing
    `expand` from `Construct.Declaration` and `Enum.Declaration`, then delete
    the unused `SyntaxExpandable` wrapper.
  - [x] Replace stale `let declaration: ConstructDeclaration` macro snapshots
    with the direct nested `Construct.Declaration` representation consumed by
    the uppercase projection.
  - [x] Remove the redundant `@field` marker, its unused Foundation macro, and
    its compiler target alias; declaration bodies already expose `[@member]`,
    while `@property` and `@stored` describe the meaningful subsets.
    - The development candidate rebuilt one artifact and reused 2,655, completed
      in 324 seconds, and passed every affected macro/Codable fixture before
      reaching the unchanged graph-capability `macroMissingTarget` boundary.
  - [x] Remove declaration-owned `replace` methods from
    `Construct.Application` and `Function.Application`; syntax values describe
    applications rather than owning graph mutation.
  - [x] Make `#environment { ... }` the canonical macro expansion boundary,
    remove `Macro.Environment.expand`, migrate authored macros and fixtures,
    and reject the legacy callable spelling.
  - The focused rerun now passes canonical target members, typed collection
    closures, inline mapped syntax, stored defaults, the actual Core Codable
    surface, composite rollback, and typed parameter defaults. value-ownership next
    stops in the separate graph-capability draft with
    `macroMissingTarget`; do not fold that graph work into this cleanup.
- [ ] Complete generated project configuration as a value/artifact.
  - The current `Project.range` directly emits missing default states onto the
    project target and returns `-> ProjectDefaults`; it does not yet emit a
    standalone generated project-configuration artifact.
  - Compiler lowering still recognizes only persisted macro-result nominals,
    and root expansion currently records arbitrary root constructs as opaque
    artifacts rather than committing them into the declaration graph.
  - `check_range_native_project_macro` still asserts the older synthesized
    `state integer` / `state bool` extension and read-dependency behavior; it
    must be rewritten only after the generated construct has a supported
    compiler data path.
- [ ] Execute the Range-authored graph body directly.
  - `Graph.range` now authors
    `#environment.graph.addNode(role:additionalRole:)` and uses implicit `nil`
    for the optional second role.
  - The unimplemented `@shared` macro-on-macro marker and its unused
    shared/private value model were removed; reintroduce sharing only with a
    concrete cross-module graph ownership requirement and a focused proof.
  - The bootstrap `compilerFormulaExecuteApplication` graph-name bridge still
    performs role validation; `addNode` is not yet a supported ordinary graph
    capability operation.
- [x] Delete `RangeCompiler/Sources/Core/Macro/Storage.range` and remove the
  value-ownership script's direct attempt to concatenate that deleted file.
  - Storage descriptor fixtures still declare their own focused legacy macro,
    and `Int.range` still carries `@storage`; decide that remaining semantic
    migration separately rather than treating file deletion as proof that the
    storage formula path is gone.
- [ ] Reconcile concurrent workspace edits before the next patch.
  - The worktree also contains unrelated README, Website, GPU canvas, example,
    and script changes. Preserve them and inspect overlapping compiler/Core
    files before editing.
  - Last completed validation in this run was `scripts/range
    check-build-plan`; it passed before the latest overlapping edits.
    `scripts/range check-value-ownership` has not passed.

## Concurrency

- [ ] Add the first structured-concurrency compiler checkpoint without
  restoring the obsolete `background` statement.
  - [x] Delete the orphaned authored `Background` syntax declaration; it had
    no compiler consumer or focused fixture.
  - [ ] Outline and execute one noncapturing closure as an ordinary runtime
    callable, independent of the existing collection-transform and macro
    closure paths.
  - [ ] Represent an explicitly joined `Task<Value>` over that callable;
    settle the authored start/join syntax only after the callable proof.
  - [ ] Prove two independent tasks execute and join deterministically in a
    focused `Testing/Concurrency/Pass/` fixture.
  - [ ] Reject mutable captures at the task boundary until ownership transfer
    and isolation are modeled and proven.
  - Existing `runProcessBatch` support is bounded host-process parallelism,
    not proof of in-language task or shared-memory concurrency.

## Website

  - [x] Redesign the sound opening sheet around hover discovery.
    - [x] Activate mouse entry on hover and snap the exploration point to the
      pointer while retaining touch and keyboard entry.
    - [x] Reveal a glitter-surface shader sphere whose surface becomes more
      concrete as the pointer visits each exploration segment.
    - [x] Make fisheye directional during transitions: outward while the
      sphere expands and inward while it collapses.
  - [x] Compose the onboarding exit as one viewport-centered expanding sky
    sphere with a concentric inner website cutout.
    - [x] Keep the sky in its normal circular shader mask while its diameter
      expands to the measured viewport diagonal.
    - [x] Grow the inner cutout from the sphere center on the same normalized
      timeline, then finish without a lingering overlay.
    - [x] Defocus the entire sky layer across the shared exit tail, including
      the transparent cutout edge, so the handoff resolves as one blur.
    - [x] Shorten the cutout motion and add one audible low sine swell that
      rises at exit start and fades with the same leave envelope.
    - [x] Start the page fade reveal with the 600ms circular cutout so the two
      handoff layers overlap without a competing page blur or scale motion.
    - [x] Use one shared growth curve for the expanding sky sphere and its
      concentric inner website cutout.
    - [x] Keep the page reveal as a centered opacity handoff and remove the
      full-page blur/scale pass so it does not travel vertically or paint in
      pieces.
    - [x] Keep the fisheye one-way and outward-facing through breathing, with
      a positive floor instead of an inward cave-in.
    - [x] Make the onboarding machine own the small, medium, and fullscreen
      stages so the exit uses the measured viewport diagonal without overshoot.
    - [x] Keep a quiet audible breathing floor and drive its level from the
      sphere's actual anchor-stage size envelope.
  - [x] Add a source-first Command Group macro breakdown at
    `/features/macros/command-group-registration`.
    - Show the complete live Core macro, a representative annotated command
      group, and the discovery, validation, generated-enum, and still-deferred
      dispatch boundaries.
  - [x] Remove the Cardinality heading and explanatory copy from the homepage.
    - Keep its sound generator and graph, with one black/accent start-stop
      toggle.
  - [x] Set the homepage description in the site monospace face.
  - [x] Preserve the homepage optical-alignment contract through the Sveltely
    stack refactor by targeting its rendered semantic page attribute.
    - [x] Re-measure before first reveal and after font or measured-descendant
      geometry changes so a cold Vite start matches a refresh.
  - [x] Keep “Range Has a Dual Shape” hidden from the public Website.
    - Remove its homepage card and make its former route return 404.
  - [x] Render the benchmark run procedure as a minimal top-down tree, with
    generated source branching into six optimized builds before the shared
    run, validation, and median-result trunk.
  - [x] Remove the stale static compiler-status block from the benchmarks page.
  - [x] Remove the initial static benchmark so feature charts come only from
    the latest generated benchmark artifact.
  - [x] Publish separate “50% Declarative, 50% Imperative” and “Somewhere,
    Sometime, Some-here” essays with dedicated routes, homepage entries, and
    rendered-route assertions.
  - [x] Add a production Docker image, Compose service, health endpoint, and
    deployment instructions for the standalone SvelteKit website.
  - [x] Add Caddy automatic HTTPS, private Docker-network proxying, persistent
    certificate storage, and configurable domain/port deployment settings.
    - [x] Harden production containers with dropped capabilities, read-only
      filesystems, no-new-privileges, and bounded local log rotation.
    - [x] Replace benchmark-only default metadata with a language-level SEO
      title and description across search and social previews.
    - [x] Register each legacy site-shell custom element with its own
      constructor so production route navigation stays console-clean.
  - [x] Remove the redundant Benchmarks and Strings Go Fast link cards from
    the homepage while retaining their primary navigation and post links.
  - [x] Add a `/benchmarks/history` performance-observation landing page.
    - [x] Plot `100k → 1m → 5m → 10m` operations on X and logarithmic runtime
      milliseconds on Y, with one scaling line per measured language.
    - [x] Treat each benchmark date as one sustained scaling snapshot so future
      observations append comparable charts without mixing old implementation
      checkpoints into the current result.
    - [x] Give both axes explicit visible and accessible labels and provide the
      complete cross-language values in a screen-reader table.
  - [x] Move the codability walkthrough from the homepage into a dedicated
    `/features/macros/codability-under-100` long-form article, with a concise
    homepage entry point.
    - [x] Present the newest writing in a responsive homepage strip of OKLCH
      shader cards, led by `Codability under 100`, with one synchronized,
      visible-only noise field sampled through card-shaped cutouts at their
      actual layout coordinates.
      - [x] Generate a distinct shader palette for every post from an unbounded
        golden-angle OKLCH seed instead of reusing named color variants.
      - [x] Store each post’s measured complementary text palette with at
        least 4.5:1 contrast instead of repeating GPU readback and candidate
        analysis at runtime.
      - [x] Give the post grid one canonical Range-accent cursor that travels
        instantly between cards for hover and forward/reverse keyboard focus
        and retains its last position between selections.
  - [x] Modulate the continuous Cardinality hum’s low-pass cutoff from homepage
    scroll proximity without changing its pitch, rhythm, or volume.
  - [x] Add a homepage codability sheet sourced from the Range-authored macro.
    - [x] Tighten the Declaration/Usage picker padding and control height.
    - [x] Reduce the inspector track to the smallest bounded height that still
      accommodates the longest chapter description.
    - [x] Advance the seven declaration chapters from seven equal slices of
      the centered scroll plateau.
    - [x] Inline the small encode and decode property switches into their
      respective field-map bodies and remove the standalone helper macros.
    - [x] Add an explicit Story mode that applies chapter focus, advances in
      equal plateau slices, and centers each highlighted code block; keep the
      non-Story overview unfiltered with continuous parent-driven code scroll.
      - [x] Hold a manually selected Story chapter through focus and resize
        frames, returning ownership to the plateau only after a subsequent
        deliberate page-scroll movement.
    - [x] Use the complete generated `decode` function as chapter seven,
      including its field map, inline result handling, assignments, and return.
  - [x] Move the String optimization article to
    `/optimizations/general/strings-go-fast` and title it “Strings Go Fast.”
  - [x] Humanize the benchmark heading’s keyboard effect with a deterministic
    learned-style keystroke timing model and subtle gesture-unlocked Web Audio
    key transients.
    - [x] Phase each synthesized key to the digraph transition that produced
      it, soften fast pairs, and smooth overlapping clicks through a filtered
      compressed output bus.
  - [x] Use Range's editor-owned light syntax palette and semantic token roles
    for keywords, types, declarations, functions, macros, members, and values.
    - [x] Share one reusable `RangeCode` renderer across plain source blocks,
      and share its Range syntax theme with the interactive Codable walkthrough.
      - Preserve authored whitespace and indentation; syntax token spans must
        remain inline rather than becoming accidental line boxes.
    - [x] Keep inspectable macro nodes flat and non-interactive, and navigate
      the seven explanations explicitly through a trailing numbered chapter rail.
      - [x] Re-anchor all seven chapters to the current generic Codable source
        and align their numbered markers in one indentation-independent gutter.
    - [x] Rebalance the preview away from a single purple identifier bucket:
      reserve the luminous Range blue for keywords, then use project teals,
      property/declaration blue, vivid salad-green callables, amethyst-lilac macro
      applications, and neutral local values.
    - [x] Keep string literals black and light, with soft-gray punctuation and
      darker structural curly braces.
    - [x] Color nominal type names and macro declaration names with the same
      project blue used for properties.
  - [x] Show a concrete `User` Usage example, the exact codable Declaration,
    and one focused Field helper from
    `RangeCompiler/Sources/Core/Macro/Codable.range`.
    - [x] Make enum payload patterns bind bare identifiers, so focused helpers
      use `case .failure(error)` and reject the redundant `let` spelling.
    - [x] Show an immutable `let` and a `state` member in the usage example,
      with both entering the unified `@stored` coding surface.
  - [x] Explain the collect → map → expand mechanism without presenting the
    deferred complete encoder/decoder runtime surface as finished.
  - [x] Present canonical macro expressions in a prominent full-width code
    workspace with explicit numbered chapter inspection.
    - [x] Route the code viewport’s vertical progression through the parent
      page scroll so the full-screen stage never competes with a nested Y scroller.
    - [x] Hide the code viewport’s horizontal scrollbar chrome while retaining
      its horizontal scrolling behavior.

## Editor

  - [x] Restore source-first go-to-definition through a Range-owned language
    server launched by `scripts/range lsp`.
    - [x] Cache a scoped workspace graph across requests, overlay unsaved open
      documents, and rebuild the derived graph only when a file generation
      changes.
    - [x] Build and cache shortest-path jump links from symbol occurrences
      through lexical scope, file, and workspace nodes to compatible
      declarations.
    - [x] Prove `@component`, `Header()`, nearest lexical binding, graph reuse,
      and unsaved navigation with focused fixtures in `Testing/Editor/Pass`.
  - [x] Replace the generated Zed Xcode-style syntax theme with the website
    Codability palette.
    - [x] Keep neutral functions, declarations, variables, and strings while
      carrying across Range-blue keywords, cyan types and properties, magenta
      attributes, violet macro splices, and differentiated punctuation.
    - [x] Generate named light and dark Codability variants and point the Range
      Zed extension at the renamed theme artifact.
    - [x] Parse executable macro bodies before applying syntax captures, so
      keyword and string highlighting does not depend on Tree-sitter error
      recovery.

## RangeView

  - [x] Establish `@app`, `@component`, and `@page` as the minimal
    framework marker surface.
  - [x] Move every foundational macro into `Macros/Core.range` and make
    `Macros/` the ownership boundary for future concern-specific RangeView
    macro files.
  - [ ] Emit `.html`, `.css`, and `.js` files from ordinary Range strings once
    that backend has a compiler-owned artifact boundary.
  - [ ] Add an executable RangeView command only after the relevant framework
    source has focused compiler fixtures; do not make RangeView itself a test
    input.
  - [ ] Prove the first executable `VStack` lowering through compiler-owned
    component fixtures, without using the idealized framework as validation.
  - [x] Replace the prototype declaration with the intended declaration-first
    surface, even though compiler support remains pending:
    `state spacing: Float` plus
    `binding _ children: () -> [@component]`.
  - [ ] Make `@app` discover `@page` declarations and generate the site entry
    point once framework dependencies and emitted artifacts have a supported
    project-graph consumer.
    - [x] Declare the source-first `Route` model and one derived route tree on
      the example app, with paths owned by routes rather than `@page`.
    - [x] Declare the `@app` contract requiring exactly one
      `derived routes: Route`, with distinct missing, duplicate, and wrong-type
      diagnostics.
    - [ ] Execute the typed `Derived<Route>` query and its missing, duplicate,
      and wrong-type diagnostics through the current macro compiler.
    - [ ] Recover route-builder expression, block, optional, either, and array
      collection without restoring the old Swift result-builder runtime.
    - [ ] Resolve nested prefixes and build both path-to-page and page-to-path
      graph facts before artifact emission.
      - [ ] Let each `Route` normalize its local segment and derive its resolved
        canonical matcher signature from the parent prefix.
      - [ ] Make `@app` reject duplicate matcher signatures across the complete
        tree, treating parameter-name-only differences as the same matcher.
      - [ ] Make `@app` reject a repeated page declaration so reverse lookup
        has one canonical path; add aliases later through an explicit route
        declaration if needed.
  - [ ] Make `@component` generate or select its artifact lowering so callers
    express `VStack` composition without invoking framework lowering functions.
    - [x] Declare the macro contract requiring exactly one
      `derived body: [@component]` on every component and page.
    - [ ] Execute the typed `Derived<[@component]>` query and its missing,
      duplicate, and wrong-type diagnostics through the current macro compiler.
    - [ ] Admit constructing `VStack(spacing:)` and projecting its spacing into
      the renderer; the first local instance attempt currently rejects during
      `renderHomePage` function discovery with failure code `6595`.
    - [ ] Recover the general builder operations proven by the earlier Neat
      model: expression, block, optional, either, and array collection.
    - [ ] Make `VStack { ... }` collect component values through those builder
      operations without reparsing source or naming `VStack` in compiler code.
      - [ ] Add independent external and local names to stored/binding
        declarations so `binding _ children` parses; the literal form currently
        rejects during top-level declaration capture.
      - [ ] Admit a builder closure binding with type `() -> [@component]`;
        `() -> [Int]` currently parses but rejects during enum-payload type
        linking, while direct `[@component]` reaches
        `invalidMacroFamilyMemoryGraph`.
      - [ ] Consume the component-family result as compile-time child syntax
        before runtime layout instead of storing it in every `VStack`.
  - [ ] Add one unified 2D `Geometry` intent shared by components and pages.
    - [ ] Expose `.geometry { geometry in ... }` as the observation and
      transform boundary without a modifier registry or per-function macros.
    - [ ] Support size and shape transforms, including rectangle-to-circle,
      before lowering the final geometry into HTML, CSS, and JavaScript.
  - [ ] Add `@styleModifier` declarations that produce backend-neutral style
    transforms and chain on every component and page.
    - [ ] Implement `.padding(10)` as the first modifier and merge it into the
      target node rather than emitting a wrapper component.
    - [ ] Lower static style transforms to CSS and reserve JavaScript for
      observed or runtime-dependent values.
  - [ ] Pass app values with owned dynamic strings through component and page
    render boundaries after representation-sensitive aggregate calls are
    admitted by the accepted compiler proof boundary.

## RangeStore

  - [x] Implement a first Range-authored durable document store.
    - [x] Persist an atomic append-only metadata revision log with immutable
      per-revision document body sidecars.
    - [x] Support stable integer IDs, latest-revision lookup, updates,
      tombstone deletion, restoration, and bodies containing delimiters/newlines.
    - [x] Prove compile, link, persistence, reopening, and body round-trip with
      `scripts/range check-document-store`.
  - [ ] Add a stateful store handle once owned dynamic-string aggregate returns
    are admitted by the accepted compiler proof boundary.
  - [ ] Layer typed collection schemas, indexes and query predicates over the
    revision core before adding auth, realtime subscriptions, or an HTTP API.
      - [x] Treat the macro declaration/context line and stored-field graph query
        as inspectable semantic passages instead of isolated keyword nodes.
      - [x] Frame chapter 1 as declaring a construct-attached macro, the basic
        shape for drafting behavioral relationships.
        - [x] Name the usage inspector action “Attaching a macro.”
        - [x] Describe the resulting `User` construct as carrying `@codable`
          behavior.
        - [x] Explain the standard declaration pattern as naming the macro,
          choosing its target, and gaining access to the surroundings.
          - [x] Collapse the repeated chapter 1 prose into one concise lead-in
            and three short bullets.
      - [x] Number declaration, graph query, expansion, and the first
        code-splicing passage as steps `1 → 2 → 3 → 4`.
        - [x] Inline the encode/decode field maps in the main macro and use the
          ordinary `encode` function declaration and keyed-container setup as
          step `5`.
          - [x] Preserve the complete encode-side `#fields.map` synthesis
            closure as step `6`.
        - [x] Make every numbered badge and its complete code passage select
          the corresponding inspector chapter.
          - [x] Hide the chapter rail and chevrons while the Usage pane is
            selected.
        - [x] Dim every non-selected code segment while a chapter is active and
          let a second click clear the chapter to restore full highlighting.
          - [x] Fade complete source lines rather than partial syntax fragments
            so each chapter reads as one coherent focused passage.
            - [x] Keep every numbered chapter badge fully opaque while its
              surrounding source line is dimmed.
            - [x] Give nested lines a secondary context opacity when a parent
              block chapter such as `#environment` is selected.
            - [x] Apply the same brace-delimited context treatment to the macro
              declaration, extension, and property-helper chapters.
              - [x] Keep the two-line chapter 5 `encode` function setup fully
                highlighted as one ordinary Range code unit.
                - [x] Retain the rest of the `encode` function as softer
                  nested context through its closing brace.
                - [x] State the function’s `Result<Void, EncodingError>`
                  return contract in the chapter 5 description.
            - [x] Recede nested block context to a lower-lightness `34%`
              layer with a restrained `0.3px` blur.
            - [x] Treat chapter 7 as one complete closure and keep its entire
              property-helper macro fully highlighted.
              - [x] Include both encode and decode property-helper macros in
                the chapter 7 highlighted synthesis unit.
          - [x] Remove the inspector from layout when chapter selection is
            cleared so the source expands across the complete workspace.
          - [x] Keep the codability interaction in one permanent vertical
            hierarchy: breadcrumb and picker, full-width code, then a
            horizontal chapter description.
        - [x] Add the failure-aware encode helper as step `6` to show that a
          macro can encapsulate one piece of control flow or logic.
        - [x] Position step badges outside multiline source flow so continuation
          lines retain their authored indentation.
        - [x] Preserve absolute authored indentation for every continuation line
          inside clickable multiline chapter controls.
        - [x] Convert authored four-space levels to semantic tabs and size each
          tab from the code viewport width with compact bounds.
        - [x] Center each scaled step badge vertically against its first code
          line rather than its smaller internal text box.
        - [x] Include the query passage's shared leading indent inside its
          multiline inspection token so its opening and closing lines align.
        - [x] Align every chapter badge in one source gutter independent of
          the annotated line's authored indentation.
      - [x] Show step 4's complete `#environment.target.Declaration.identifier`
        mention in the inspector accent and explain `#` as interpolation from
        a macro-time value into code that executes later.
      - [x] Keep the generated `encode` function inline in the target extension
        and use one `[@stored]` query for immutable fields and state.
      - [x] Lead with inspector explanations, place accented syntax beneath
        them, and remove Phase/Produces metadata from every inspector.
        - [x] Separate the concepts cleanly: chapter 3 owns ordinary validated
          Range code inside `#environment`, while chapter 4 owns only the
          highlighted `#environment.target.Declaration.identifier` splice.
          - [x] Explain that `extension` receives the target's canonical
            declaration identifier as a spliced compile-time value.
      - [x] Give those passages a concentrated glyph drop shadow without an
        overlay, broad blur, or underline; keep single-token mentions
        underline-only.
      - [x] Derive nominal-type and member-access syntax roles from the primary
        OKLCH hue, stepping chroma down from the solid keyword accent.
      - [x] Give `@` macro mentions and `#` code splices distinct amethyst and
        violet hues as the two special compile-time syntax roles.
        - [x] Give `#` splice roots semibold weight so their compile-time
          boundary remains legible beside the derivative blue member chain.
      - [x] Classify `@stored` as a plural nominal selector rather than a macro
        application, matching the nominal-type color used by `Construct`.
      - [x] Render declared function and macro names in normal black while
        retaining semantic color for macro applications, properties, types,
        and keywords.
      - [x] Render function and method references in normal black as well,
        removing the remaining green callable-name role.
      - [x] Keep nominal types stronger than member access while preserving the
        exact primary accent hue across the full semantic chain.
        - [x] Deepen both derivative blue tiers and classify dotted `.self` as
          member access so only actual keywords use the solid accent.
    - [x] Keep the inspector focused on its explanation and metadata without
      repeating the active expression in a separate token pill.
    - [x] Remove the inspector eyebrow row and interaction-hint copy.
    - [x] Remove the redundant Range-authored-source eyebrow from the preview
      header and let the active filename stand alone.
    - [x] Keep the code canvas and line-number gutter on a pure white
      background.
      - [x] Use near-white, trace-chroma OKLCH shell surfaces so the display
        stays subtly luminous without reading as a colored panel.
  - [x] Turn the workspace into a scroll-linked focus stage that expands to
    the full viewport across a stable center band.
    - Keyboard focus within the workspace also holds the fullscreen state;
      reduced-motion users receive the full display without interpolation.
    - [x] Hold a `60vh` fullscreen plateau around vertical-center alignment,
      then ease symmetrically through the entry and exit falloffs.
    - [x] Keep the code surface at a fixed scale and map its internal scroll
      exclusively across the centered plateau.
    - [x] Keep the code viewport scroll-locked while the page enters the stage,
      then enable its own scrolling only at the centered fullscreen state.
    - [x] Drive the focus stage through explicit entering, focused, and exiting
      states with hysteresis, using direct frame-synced transforms.
    - [x] Keep interaction focus from forcing visual progress to fullscreen;
      it may only hold an already-focused stage inside a bounded geometry band.
    - [x] Keep the inspector body at one stable full width and height across
      every pane and chapter variant.
      - [x] Pin every inspector title to the same top-aligned title track,
        independent of description length or title wrapping.
    - [x] Replace the landscape inspector's content-sized `auto` row with one
      stable viewport-relative track so chapter switches cannot move the split.
- [x] Position the homepage 0-to-1 measure on a zero-safe logarithmic scale.
  - [x] Use those non-linear positions for canvas marks and verify the rendered
    endpoint alignment.
  - [x] Let mouse hover move the logarithmic spacing origin through the scale,
    using the authored `0` position as its resting state.
    - [x] Distort mark positions without changing dash length or adding a
      separate pinch control.
    - [x] Ease into hover focus and ease back toward `0` when hover is lost,
      without overshoot or backlash.
    - [x] Synthesize subtly varied, fine-toothed soft-metal detents through Web
      Audio as the pointer hovers and moves across the scale, without requiring
      a press or introducing a broad card-like noise tail.
      - [x] Rate-limit fast pointer passes and route every detent through one
        conservative compressor/output bus so overlapping ticks cannot peak.
        - [x] Attenuate ticks as pointer speed rises, cap the train below 39 Hz,
          and keep less than one tick interval of scheduling backlog.
      - [x] Master the scale detents, learned typing clicks, and Cardinality
        sound through protected unity-gain outputs so the operating system owns
        the final listening volume without quiet site-level attenuation.
        - [x] Raise the fine-toothed waveform itself to an audible level and
          wait for its audio context to resume before emitting the first click.
        - [x] Collapse stale audio-start requests and cap fast movement below
          19 Hz so resuming audio cannot release a clustered click burst.
        - [x] Fade the entire detent waveform toward silence as pointer speed
          rises, clearing accumulated distance so fast passes cannot sound like
          a repeating electrical pulse.
        - [x] Replace coherent oscillator partials with one short band-limited
          noise tooth, a sub-millisecond gain envelope, varied cooldowns, and
          immediate-only triggering so fast input cannot create a pitched buzz.
        - [x] Make the noise tooth reliably audible by unlocking its private
          AudioContext on scale press, playing one confirmation tooth, and
          replacing the over-aggressive compressor with a safety envelope.
        - [x] Preserve the continuous, broadly filtered brushed-noise surface
          as the reusable Hashing sound rather than leaving it on the scale.
        - [x] Trigger one rounded Digital Crown-style tick when pointer motion
          crosses each logarithmic scale detent, with no queued tick burst.
- [x] Let the homepage title sound taper over a 1.2-second pointer-exit release
  and render its horizontal axis as a bounded, mirrored gradient.
- [x] Register one root-owned Web Audio manager/master bus and route title,
  nucleus, rhythm, scale, and typed-text sounds through named bus inputs.
- [x] Add an interactive concentric nucleus graph to the Svelte homepage.
  - [x] Render one shared source nucleus with persistent concept branches.
  - [x] Center the concept picker above the graph, remove its selected fill,
    and omit the per-concept explanatory sentence.
  - [x] Add an explicit `Shape(1, 2, 4)` branch and expand the radial
    canvas to use the available content width.
  - [x] Verify Svelte diagnostics, production build, server rendering, and
    concept-picker interaction.
  - [x] Map the Range `0 → 1 → 2 → 4` progression into loop timing, treating
    zero as the silent origin and multiplying audible values by `0.6s`.
    - [x] Advance Shape → Ownership → Capability on the same boundary that
      triggers each note, using the authored six-step loop
      Shape → Ownership → Capability → Shape → Ownership → Shape.
    - [x] Keep the authored timing in the visual concept changes and quiet air
      swells without restarting the underlying voice on each step.
    - [x] Hold one persistent, gently detuned A2 voice in an audible low
      register, with a very slow breath that does not share the loop period.
      - [x] Raise the persistent voice and direct presence enough for the hum
        to remain audible on laptop speakers without sharpening its tone.
    - [x] Send the continuous voice through a strong five-second stereo reverb
      tail so it reads as one source heard from afar.
      - [x] Keep a quiet direct tone beneath a diffuse reverb return.
      - [x] Filter the wet return through a rumble cut and a broad low-pass
        without emphasizing an individual bass frequency.
      - [x] Use a smooth tail and low-Q filtering so overlapping sine-bass
        pulses do not pump or ring.
  - [x] Place every branch node on a shared concentric numeric scale where the
    `8 → 16` ring interval is twice `4 → 8`, which is twice `2 → 4`.
    - [x] Keep the concentric marks unlabelled and preserve node values only as
      semantic/audio metadata, without visible numeric annotations.
  - [x] Keep a permanently visible synchronized spiral track through the
    existing `4 → 8 → 16` nodes without a redundant toggle control.
    - [x] Follow the expanding value-derived spiral with quiet, overlapping
      near-unison air around A2 instead of a rising melodic phrase.
    - [x] Move the dash geometry continuously outward, growing its length and
      physical spacing with radius while hiding each endpoint recycle.
    - [x] Run the outward flow only during playback at a lazy 16-second cycle,
      growing from fine Shape-side marks into long Capability-side dashes and
      falling back to a static progressive spiral when stopped.
  - [x] Render straight radial connectors from value-aware dash segments whose
    lengths and gaps expand with the local base-2 logarithmic magnitude.
  - [x] Replace the visible numeric node labels with restrained value dots,
    using a thin paper knockout so rings and connector marks stay distinct.
  - [x] Highlight the active branch line, concept label, and value dots directly
    in a darker, higher-chroma playback accent while leaving every inactive
    branch muted.
    - [x] Snap the active color directly at each concept boundary without a
      tween or pulsing color envelope.
    - [x] Animate the spiral at one constant linear speed, independent of the
      authored concept and audio-window durations.
    - [x] Keep that rhythmic envelope within a brighter playback range while
      retaining its chromatic contrast.
    - [x] Alternate two distinct OKLCH rhythm contours instead of repeating
      the same color pulse shape.

## Baseline Integrity

- [ ] Move unsized scalar defaults into the `@project` macro.
  - [x] Add the host-backed target pointer-width builtin and a bootstrap-safe
    resolver hook for missing `integer`/`bool` defaults.
  - [x] After bootstrap promotion, make the resolver hook call
    `targetPointerBits()` directly instead of its accepted-bootstrap 64-bit value.
  - [x] Define lowercase `project` in Range and execute its real macro body.
    - The authored macro uses `#environment { ... }` as its contextual
      expansion boundary and maps `environment.system.defaults` into generated
      `let` members of one canonical `ProjectDefaults` construct.
    - [ ] Make `#environment { ... }` the executable contextual expansion
      boundary, then migrate the remaining authored macros from
      `#environment { ... }`.
    - [ ] Materialize the `system.defaults` environment projection and prove
      generated defaults plus preservation of explicit project overrides.
  - [ ] Resolve emitted `ProjectDefaults` artifacts as compiler configuration
    data.
    - The Range macro now emits the canonical construct and the bootstrap
      bridge preserves target overrides, but lowering still keys its fallback
      lookup from the `project` application until opaque root construct
      artifacts are committed into the declaration graph.
  - [x] Allow `state integer: Int<4>` and full signed-width forms to override
    the project integer default without an `override` keyword.
  - [ ] Route every bare and partially specialized `Int` use through the
    resolved project default instead of LLVM `i32` literals.
  - [ ] Resolve bare `String` through a project-provided encoding default.
    - Model an explicit override as `String<.utf8>` (and later other
      `TextEncoding` cases) while keeping logical String elements semantic
      characters rather than physical code units.
  - [ ] Materialize and validate the complete predefined scalar-member set.
  - [x] Prove default, override, duplicate, wrong-binding, and wrong-type
    behavior through supported compiler fixtures.
- [ ] Move primitive scalar identity and literal syntax into Range-authored
  lowercase macros.
  - [x] Accept annotated compile-time generic values without the redundant
    `let` spelling, including
    `Int<signedness: Signedness, bits: Int>`.
  - [x] Capture and validate empty `@storage` declarations plus
    `@literal(.numeric)` and
    `@literal(.numeric.decimal(separator: "."))` registrations.
  - [x] Reject literals without storage, invalid numeric storage shapes,
    duplicate literal registrations, and storage constructs with instance
    members through supported fixtures.
  - [x] Execute lowercase `@storage` and `@literal` applications as compiler
    formula invocations and consume their emitted facts for descriptor
    validation.
  - [x] Delete the shared Core `Macro/Storage.range` declaration; focused
    legacy descriptor fixtures remain self-contained while physical
    representation moves into generated configuration data.
  - [x] Define and validate text literal facts as semantic `Character`
    elements encoded as UTF-8 with unsigned 8-bit physical code units.
    - [x] Prove the exact text descriptor, missing text storage, and invalid
      physical storage through supported fixtures.
    - [ ] Replace `String`'s bootstrap `@builtin(.storage)` annotation with
      `@storage(.text(...))` after the formula-capable macro sources enter the
      reproducible bootstrap manifest.
  - [ ] Synthesize signed and unsigned integer representations from
    `signedness` and `bits`, including unary minus only for signed storage.
  - [ ] Replace the native integer literal and LLVM lowering branches with
    macro-produced representation facts.
  - [ ] Add the Range-authored `Signedness`, `Int`, and `literal` sources to
    the bootstrap manifest after the parser-capable bootstrap is reproducibly
    promoted.
  - [ ] Expose compiler declarations through one canonical typed meta-model.
    - [x] Define lowercase `member` for `Declaration | Member` and annotate the
      direct `Let`, `State`, `Binding`, `Derived`, nested `Construct`,
      `Function`, `Enum`, and `Extension` syntax representations.
    - [x] Replace `Construct.Declaration`'s parallel per-kind arrays with the
      canonical `members: Array<@member>` collection.
    - [x] Make `Array<Element>` the sole compiler-backed collection type
      spelling and reject legacy `[Element]` during typed syntax capture.
      - Core and compiler fixtures use explicit declaration initializers such
        as `Array<Int>([1, 2, 3])`; brackets remain the value payload and index
        operators, not a competing type or inferred declaration form.
      - Verification: `scripts/range check-value-ownership` passes the canonical
        nested-generic, macro-family, recipe-cardinality, indexing, and focused
        legacy-rejection proofs.
    - [x] Prove one macro-family representation retains mixed authored
      `let`, `state`, `construct`, and `function` values.
    - [x] Normalize parser-backed declaration envelopes in the direct syntax
      model.
      - [x] Carry leading macro applications on function, enum, and parameter
        declarations alongside their authored identifiers and callable shape.
      - [x] Keep `let` and `state` as value-generic stored variants with macro
        applications, identifier, and value; keep `binding` and `derived` with
        their direct type and accessor/body storage instead of inventing a
        callable parameter list.
      - [x] Align the canonical declaration-envelope proof with value-generic
        `Let<Value>` and `State<Value>` by checking their direct `value`
        witness without expecting a parallel `type` field.
    - [ ] Execute typed views such as
      `members.filter(all: Let) { lets in ... }` over those same values without
      copying them into a second representation.
      - [x] Standardize executable macro bodies on the implicit
        `#environment` context. `Macro.Environment<Target>` owns the target and
        diagnostics/graph query views; the compiler records one hidden
        capability handle and models each view as an explicit environment
        projection rather than an ordinary local symbol.
        - [x] Make every nonempty macro body executable, reject the retired
          `{ environment in ... }` binder as a malformed header, and require
          context access through `#environment.target`, direct forwarded
          diagnostics such as `#environment.error(...)`, or
          `#environment.graph`.
        - [x] Make `#environment { ... }` the only tracked authored
          expansion boundary and lower it through the environment's expansion
          authority into the existing transactional graph-delta operation.
          - Core Project, Core Codable, Foundation macros, and focused fixtures
            no longer use the compiler-special `@expand` spelling.
        - [x] Materialize that environment as a graph-backed compile-time
          value, bind it to the macro frame's real MIR parameter, and resolve
          `target`, `diagnostics`, and `graph` by projecting children from the
          passed value instead of consulting the invocation out of band.
          - Verification: the root environment and canonical-target-members
            fixtures pass, and the compiler candidate remains a byte-identical
            candidate/reproduction fixed point.
        - [x] Retain the complete environment aggregate through an ordinary
          compile-time Range call and compare the returned value with the
          current `#environment` by execution identity.
          - Verification: `Testing/Macros/Pass/EnvironmentValue.range` emits
            `environment retained` only after the value survives the call and
            the equality branch succeeds.
        - [ ] Define recursive structural equality and diff values for
          `@syntax`, environment snapshots, and graph deltas.
          - Current compile-time equality compares the stored syntax or
            capability identity. It does not recursively compare children or
            produce a typed change set, so do not describe it as a structural
            diff yet.
        - [x] Route every direct call on the environment's `target`, `graph`,
          and `diagnostics` projections through capability resolution,
          including denied operations, while leaving deeper source-backed
          syntax paths to ordinary Range member resolution.
          - Verification: the compiler candidate proves an untaken denied
            `target` operation is path-sensitive and an executed denied
            `graph` operation emits `macroCapabilityDenied`.
      - [x] Declare the Range-authored generic projection surface as
        `function filter<T>(all: T): Array<T>` on the single `Array<Element>`
        primitive.
      - [x] Execute fluent exact nominal selection over source-backed member
        views and preserve original order.
        - Verification: `Testing/Macros/Pass/CanonicalTargetMembers.range`
          proves that `members.filter(all: Let).count` selects two `let`
          members while excluding one `state` member.
      - [x] Execute source-backed `filter` and `map` closures over exact
        nominal views, with `map` returning each closure result as a typed
        collection element.
        - Verification: `Testing/Macros/Pass/CollectionClosureExecution.range`
          proves chained source-backed collection transforms;
          `Testing/Macros/Pass/ApplicationValue.range` separately proves
          recursively persisted macro-application result values.
      - [x] Persist member macro results before declaration-level macros query
        `Macro.Application.value`.
        - The current two-pass scheduler preserves source order within member
          and non-member applications. Replace it with dependency-driven delta
          scheduling once graph observations can trigger selective reruns.
      - [x] Materialize Bool, String, and optional String macro arguments and
        defaults through the generic macro-value boundary.
        - Canonical parameter defaults use typed value syntax:
          `key: String?` implicitly defaults to `nil`, while non-optional
          typed defaults remain explicit, such as `exclude: Bool(false)`.
        - The redundant `String?(nil)` spelling is rejected as a malformed
          macro declaration instead of allocating a second default-value slot.
        - `Testing/Macros/Pass/TypedParameterDefaults.range` keeps this proof
          independent from Codable now that construct-attached Codable does
          not require per-field discovery.
        - Legacy `= value` recognition remains temporarily bootstrap-compatible,
          but canonical Core, Framework, and test macro sources no longer use it.
      - [ ] Infer a function-owned generic type value from a nominal `all:`
        argument and carry that specialization through the return type.
      - [ ] Execute ordinary Range-authored function calls from compile-time
        macro programs; the current macro interpreter handles scalar MIR and
        compiler queries but rejects direct calls.
        - [x] Execute scalar direct calls through recursively built ordinary
          Range CFG, ownership, and MIR frames and preserve their typed return
          values in the compile-time value store.
        - [ ] Execute construct, enum, array, closure, and syntax-valued calls
          through the same frame path.
          - [x] Preserve construct returns and member projections across an
            ordinary Range call, and execute macro-local array
            literal/count/index operations in the same typed value store.
          - [ ] Supply compile-time ownership return summaries for
            Range-authored functions that return tracked arrays.
          - [ ] Execute enum payloads, closures, and syntax-valued returns.
      - [x] Preserve a compile-time construct result created after a
        side-effecting conditional branch join.
        - `#environment` is an ordinary delta-producing capability boundary instead of an
          implicit return at the end of every nested block; the authored
          function-boundary `return` now carries the result through the shared
          continuation.
        - `Testing/Macros/Pass/BranchJoinReturn.range` and the Range-authored
          `project` macro prove the shared return after conditional expansion.
      - [ ] Treat `Array<@member>` as a deferred compile-time collection: collect
        the complete conforming child set before synthesizing its physical
        storage.
        - [x] Intern macro-family member types as deferred `Array` views and
          execute `#environment.target.Declaration.members.count` through lazy,
          source-backed syntax handles in original member order.
        - [x] Store the canonical syntax ID in every source-backed syntax
          handle and resolve compact member-table rows only at the internal
          filtering boundary.
        - [ ] Record the complete observed member set as a macro read
          dependency and expose each handle through its exact syntax nominal.
      - [ ] Lower the heterogeneous values into a nominally partitioned
        multibuffer with one concrete child buffer per conformee, using the
        maximum conformee population as the shared multibuffer capacity bound.
      - [ ] Preserve one source-ordered buffer of `(nominal, partitionIndex)`
        references so partitioned physical storage does not change logical
        member order or graph identity.
      - [x] Filter `all: Let`, `all: State`, `all: Binding`,
        `all: Derived`, and other `@member` nominals by their exact direct
        syntax nominal, not by the broad `Member` target mask.
        - The bootstrap lowering recognizes the canonical stored member
          nominals; generalized authored conformee lookup remains part of the
          deferred-view specialization work above.
      - [ ] Return a typed deferred view that preserves order, parent, source,
        written syntax, graph identity, and macro applications, and record the
        complete observed member set as a macro read dependency.
    - [ ] Make the direct syntax values the semantic witnesses consumed by
      macros and lowering, leaving integer tables as an internal compact
      backing store rather than a parallel public model.
      - [ ] Flatten syntax nominal families so their nested declaration and
        application constructs are the graph values, not simultaneous fields
        of an artificial outer instance.
        - [x] Define an inline declaration as a declaration nested directly in
          another declaration body: it inherits the parent graph identity,
          remains addressable by its qualified name, and adds no
          instance-storage edge to the enclosing value.
        - [x] Remove the parallel `declaration` and `application` fields from
          `Construct`; `Construct.Declaration` and `Construct.Application` are
          now its direct nested value representations.
        - [x] Define `graph` once on each outer syntax family with explicit
          declaration/application roles, require the matching nested
          constructs, and let each nested representation own its `@syntax`.
          - A syntax template remains an independent attached value. It does
            not copy its parent's name, and `graph` does not absorb or require
            the template; attachment identity can connect them when needed.
          - `@syntax { ... }` is the universal language-level builder surface:
            fixed Range syntax and captures belong directly to the represented
            value and can be reused outside graph declaration/application
            roles.
          - [ ] Move the bootstrap nested-role validation from
            `compilerFormulaExecuteApplication` into execution of the
            Range-authored shared `graph` body, which now authors
            `#environment.graph.addNode(role:additionalRole:)`; then delete
            the name-based compiler bridge.
        - [x] Remove the remaining parallel declaration/application fields
          from `Function`, `Parameter`, and `Enum`; normalize function calls as
          `Function.Application`.
        - [x] Delete the unused `GraphSyntax`/`GraphEntry` container model;
          graph roles now live only as capabilities attached to syntax
          families.
        - [x] Remove nominal-reference, protocol, and conformance storage from
          syntax declarations; declaration and application capabilities are
          expressed by attached macros instead of inherited nominal contracts.
          - [ ] Promote the source removal through the accepted bootstrap
            after the candidate/reproduction proof reaches the corresponding checkpoint;
            do not hand-edit the generated LLVM snapshot.
        - [x] Materialize construct macro targets through path-addressable
          inline representations such as `Construct.Declaration`; uppercase
          projections preserve the attached syntax value under the nested
          representation type, and lowercase compatibility projection is
          rejected.
      - [x] Define the Range-authored bidirectional `SyntaxTemplate` value
        model with a first-class syntax closure, member-linked captures,
        one/optional/many cardinality, canonical syntax bindings, matching,
        and rendering.
        - `Construct.range` now authors declaration and application templates
          directly in its `@syntax` body, including ordered macro/member
          captures and optional generic groups.
        - Every template capture uses `$field`, where `field` is the exact
          member identifier on the construct carrying `@syntax`; capture
          cardinality comes from that member's declared type.
      - [x] Remove the parallel `WrittenSyntax`, `WrittenExpression`, and
        macro `rawBody` text representations; typed syntax values and the
        syntax macro closure are the language model, while source offsets
        remain compiler-internal diagnostic/query indexes.
        - [x] Remove redundant authored `replace(with:)` members from syntax
          value declarations; replacement is supplied by the macro
          environment rather than declared independently by each shape.
        - [x] Model non-generic `Assignment` as the canonical `@stored`
          key/value pair: `identifier` is key slot 0 and the `@stored`-typed
          `value` is slot 1.
          - [x] Author its captured form directly as
            `@syntax { $identifier: $value }`.
          - [ ] Enforce the shared `identifier + @stored value` key/value shape for every
            `@stored` construct through canonical member metadata; `stored`
            is now a non-generic structural role rather than an unexecuted generic
            validator body.
        - [x] Normalize the statement capability macro and every Core
          application to lowercase `@statement`.
        - [x] Delete the authored `ExpressionStatement` wrapper; a value
          carrying `@statement` is already a statement.
        - [x] Delete the orphaned authored `Background` statement; concurrency
          will use an explicit execution model rather than this obsolete body
          wrapper.
        - [x] Delete the orphaned authored `For` statement and stop reserving
          `for`; collection traversal states intent through operations such as
          `map`, `filter`, `each`, and `reduce`, while `while` remains the
          explicit general control form.
          - [x] Reject the removed `for element in elements` spelling at its
            exact identifier-led entry-body syntax boundary.
          - [ ] Complete ordinary runtime collection operations through the
            existing closure, generic specialization, and ownership work;
            compile-time macro transforms do not prove the runtime surface.
            - [ ] Fix the optimized candidate's Array out-of-bounds trap
              boundary: emitted read/write LLVM contains `icmp ult i32` and
              `llvm.trap`, and both linked ARM64 executables lower `main` to
              `brk #0x1`, but trap termination is nondeterministic in the current
              environment. One run spun in the read fixture; the bounded rerun
              trapped on read and timed out on write. Keep the new five-second
              harness deadline so this boundary fails explicitly instead of
              consuming CPU forever. All preceding macro, graph, ownership, and
              body-replay candidate sections passed.
        - [x] Generalize `Return<Value>` over its carried value; an absent
          return value defaults the generic payload to `Nil`.
      - [x] Remove the separate `Generic`, `TypeGeneric`, and `ValueGeneric`
        syntax declarations; construct, enum, function, and macro generic
        clauses now collect ordinary `Parameter.Declaration` bindings.
        - [x] Remove authored `open macro` and `closed macro` modifiers for
          now; every declaration uses the single `macro` spelling and the
          legacy forms are rejected.
        - A bare parameter is an unconstrained compile-time value binding, an
          optional type constrains that value, and an optional default is any
          syntax value; a type is one possible compile-time value.
        - [ ] Collapse the compiler's separate type/value generic parameter
          kinds onto this authored parameter model while preserving
          specialization identity, labels, defaults, and graph requirements.
      - [x] Represent every enum case as the same
        `Case { identifier, value? }` shape; an enum declaration collects
        those cases directly without a nested payload wrapper.
        - [x] Mark `Enum.Case` as stored syntax, a property, and an enum
          member; its inline storage is the case identifier plus optional
          syntax value.
        - [x] Delete the parallel top-level `EnumCaseExpression`; `Enum.Case`
          is the nested inline syntax/storage value for a declared option,
          while an application selects it by identifier.
        - [x] Add `Enum.Application { identifier, selectedCase? }` as the
          application graph role, rendered as
          `$identifier.$selectedCase`.
        - Runtime enum tags and payload layout remain lowering details; the
          syntax model does not expose `associatedValues` or `Payload`
          shapes.
        - [ ] Materialize compile-time enum results through this case shape:
          resolve the case identifier, package zero or more MIR operands as
          the optional payload value, and preserve that value through generic
          macro result persistence and projection.
      - [ ] Execute `@syntax` by matching its captured template closure
        against the annotated construct's members, materializing a canonical
        value, and using the same template to render values consumed by
        `#environment`.
        - [x] Delete the obsolete Foundation `syntax` implementation that
          expanded a second macro through lowercase target projections; the
          replacement must consume the first-class closure directly.
        - [ ] Compile each declaration's Range-authored `@syntax` witness into
          one source-query plan whose captures retain member identity, type,
          and one/optional/many cardinality.
        - [ ] Route source-backed macro projections through that plan and
          reject missing, duplicated, mistyped, or out-of-order captures
          before materializing a Range value.
          - The parser's integer tables remain compact query indexes; they are
            not an independently authored declaration-shape model.
      - [x] Model every macro update as one transactional `RangeGraphDelta`.
        - The delta carries ordered insert/replace/remove/relationship changes,
          observed graph dependencies, and diagnostics with the invoking macro
          application as its origin.
        - `Macro.Execution<Value>` pairs ordinary Range return-value flow with
          the graph delta; `expand` and `omit` return deltas instead of being
          privileged hidden mutations.
      - [x] Give every macro-attachable declaration an ordered
        `macros: [Macro.Application]` source shape.
      - [x] Unify authored identifier and semantic graph identity as one
        `Identity` carrying its nominal `name`, stable `id`, direct
        `parent: Identifier?`, and
        a canonical `source: @syntax?` witness; declarations no longer expose
        parallel
        `identity`, `parent`, and `identifier` values.
        - The owning declaration's existing `type` is the named value's
          representation (`state count: Int` means nominal `Count` represented
          by `Int`); the source syntax provides `State`, `Let`, and other
          metadata without duplicating either fact in `Identity`.
      - [ ] Derive stable `Identity` hashing through `@hashable` without
        making the hash the semantic identity.
        - [x] Make `@hashable` synthesize a target-owned `hash() -> Int`
          directly from the canonical `id` declaration instead of emitting an
          inert `HashableRegistration` value.
          - `@hashable` discovers `id` through the target's typed
            `Declaration.members` rather than the legacy
            `#environment.target.memberCount(name)` shortcut.
          - The focused positive proof observes exactly one generated `hash`
            function returning `Int`; the negative proof rejects a target
            without exactly one `id` declaration. The broader value-ownership
            gate passes this slice and later stops at the independent
            construct-attached Codable collection boundary.
        - [ ] Include the parent chain deterministically, then confirm
          structural equality after every hash-index match.
        - [ ] Make graph insertion idempotent for the same identity and value,
          reject the same identity with a different value, and allow equal
          names under different identities.
        - [ ] Derive generated identities from macro application, target,
          emitted role, ordinal, and nominal type rather than allocation order
          or reconstructed source text.
      - [ ] Materialize every syntax-facing `Identity` directly from the
        compiler's existing stable fingerprint, parent relationship, and
        canonical syntax node when its source-backed view is projected; do not
        reconstruct identity from the name or copy source text into a parallel
        representation.
        - Lower `parent` as an indirect stable graph handle internally so the
          recursive language-facing relationship does not imply recursive
          inline storage.
      - [ ] Project those ordered macro applications from the source-backed
        syntax handles and record the complete observed application set as a
        macro read dependency.
        - [x] Materialize ordered `Macro.Application` values from a
          source-backed member and reconstruct each application's recursively
          persisted generic `value`.
          - Macro results retain every construct/array/enum child with a
            stable parent row and child ordinal instead of flattening the
            result to a root descriptor and child count.
          - `Testing/Macros/Pass/ApplicationValue.range` proves one member
            macro consumes another's `Metadata(number: 7)` result through
            `Macro.Application.value`.
        - [ ] Record the complete observed application set as a read
          dependency and materialize the remaining identifier/source fields
          from their canonical graph values rather than placeholders.
    - [ ] Restore self-hosted lowercase `@codable` synthesis.
      - [x] Add the modernized Range-authored `Codable.range` implementation
        to Core, using canonical `members.filter(all: Let)` instead of the
        removed Swift-hosted `target.declaration.lets` projection.
        - `@codable` attaches only to the construct and automatically treats
          its stored `let` members as the coding surface; it does not discover
          or execute a second `@codable` application on every property.
      - [ ] Execute compile-time predicate `map`/`filter`, nested macro calls,
        and syntax-array splicing in the Range-authored macro interpreter.
        `target.declaration.members` and exact nominal filtering are proven.
        - [x] Materialize every supported compile-time value referenced by a
          top-level `#expression` through the typed macro CFG/MIR boundary.
          - [x] Persist and compose scalar, array, optional, and source-backed
            syntax value trees without a Codable-specific splice path.
          - [x] Treat a mapped closure body in syntax position as a
            source-backed syntax value so `#fields.map { ... }` can compose
            heterogeneous generated statements through the same boundary.
            - `Testing/Macros/Pass/InlineMappedSyntax.range` proves the
              closure runs once per compile-time element and substitutes its
              exact source-backed initializer into the generated function.
        - The canonical Core source bundle now links `@syntax`,
          `@syntax?`, `[@syntax]`, and qualified nested names such as
          `Macro.Application`; `Application<Value>` defaults to `Nil`.
        - [x] Parse chained and nested trailing closures into an explicit
          closure node with ordered parameters and a lexical body.
          - `Codable.range:110` now crosses the former postfix parse boundary;
            closure typing, capture materialization, CFG/MIR, and compile-time
            invocation remain independently verifiable steps.
        - [x] Type closure parameters and captures, lower closure CFG/MIR, and
          invoke predicate `filter`/`map` closures at compile time before
          nested macro calls and syntax splicing.
        - [x] Add macro-time `#value.member` prefix chains at expansion
          boundaries without introducing an `@splice` macro or special
          collection operation.
          - [x] Remove the bootstrap-compatible `#(...)` spelling and reject it
            structurally. Compile-time values use only prefix mentions such
            as `#properties.map` and
            `#environment.target.Declaration.identifier`; no braced splice program
            form exists.
        - [x] Materialize macro applications retained inside generated
          function bodies as child applications of the parent expansion.
          - The construct-attached Codable proof records one parent and two
            child invocations. Each helper now executes `#environment`
            and produces a source-backed syntax artifact instead of remaining
            unexecuted template text.
          - [x] Make `Block` the canonical ordered body syntax relationship
            before composing generated bodies.
            - [x] Parameterize the Range-authored surface as
              `Block<Value, shape: DelimiterPair>` and forward the same
              identity parameters through `Closure.Literal`.
              - `DelimiterPair` provides `parentheses`, `braces`, `brackets`,
                and `angles`; the focused proof retains the authored opener,
                closer, and pair value without deriving collection semantics
                from the delimiters.
              - Bodyless functions no longer synthesize an empty `Block`.
            - [ ] Replace `Block.values: Array<Value>` with the core occurrence
              relationship: one identity owns zero, one, or many value edges.
              - [x] Name the source relationship `contents` and register it with
                Core `@contents`; `Array<Value>` is currently only the parser's
                storage transport, not the authored cardinality model.
              - [x] Decode executed `RelationshipRegistration` values into a
                typed compiler table keyed by the target-member and result
                identities.
                - `@value`, `@many`, and `@contents` now reach the same
                  projection without a macro-name branch.
                - `@many` and `@contents` return their registrations directly;
                  they do not emit syntax through `#environment` or create
                  `macroContribution` rows merely to expose typed metadata.
                - [x] Let an authored `@block` registration select a
                  member-owned `contents` relationship and materialize it onto
                  the physical `{}` source slot.
                  - The selection is a typed `BlockRegistration` result joined
                    to the relationship row, not a compiler branch on `Block`
                    or on a macro name. Bootstrap slot values remain only until
                    that source registration is available.
                  - `Testing/Macros/Pass/BlockRelationshipReification.range`
                    proves the actual typed source slot retains the authored
                    ordered, unbounded, braced, block-admitted relationship.
                - [ ] Generalize the one braced physical block registration
                  into delimiter-keyed source forms, so `()`, `[]`, `{}`, and
                  `<>` can each be described by a Range-authored relationship
                  without compiler-owned collection or closure cases.
              - [x] Add the Core `@value` member-relationship marker and annotate
                the first value-owning syntax surfaces (`Block`, `Let`, `State`,
                macro execution/application, closure invocation, and `Parsed`).
              - [x] Define the canonical non-generic relationship registration
                model and make `@value` return its one-to-one default.
                - Multiplicity is an independent minimum/maximum bound with an
                  explicit unbounded case. Ordering, separator syntax identity,
                  and delimiter enclosure are independent representation facts.
                - `RangeGraphRelationship` now relates origin, role, and
                  destination identities through that registration instead of
                  storing a compiler-defined `kind` string.
                - The focused macro proof executes `@value`, persists the full
                  typed registration, and reads its lower bound through a later
                  macro application.
              - [x] Make macro-family filtering select through the linked
                `appliesTo` and `resolvedBy` graph edges instead of rescanning
                raw macro-application target/declaration columns.
                - The focused proof selects exactly one directly `@value`-related
                  member while excluding an unmarked sibling.
              - [x] Make selected compiler values retain the relationship that
                justified their graph query match.
                - Macro-family filtering copies the syntax value with its exact
                  `appliesTo` relationship row; persisted results keep that
                  provenance so later compiler work can recover multiplicity,
                  ordering, separator, enclosure, and the producing application
                  without changing the source-facing value type.
                - Macro-family filtering, source collection literals, closure
                  filtering/mapping, counting, and expansion now use one
                  compiler-only `many` execution shape rather than separate
                  `Array` and `selection` collection kinds. Selected syntax
                  values retain their individual relationship rows.
              - [x] Register declaration membership once as an ordered
                syntax-to-syntax relationship, then use it for both macro
                `members` projection and semantic graph ownership facts.
                - Parser member indexes remain lexical/facet indexes only;
                  they no longer define the macro-visible or plotted ownership
                  relation.
                - Direct nested `construct`, `enum`, and `function`
                  declarations register through that same relation, so macro
                  filtering does not fall back to a declaration-table scan.
              - [ ] Merge macro application relationships into the canonical
                plotted graph so declarations, applications, members, and body
                syntax are one queryable node/relationship soup rather than a
                plot plus a parallel macro-edge table.
                - [x] Replace the macro-only edge schema with the shared
                  identity-to-identity relationship table.
                  - Every relationship now records its role, typed origin and
                    destination identities, ordinal, multiplicity bounds,
                    ordering, separator identity, and delimiter enclosure.
                    Existing macro-link relationships use the canonical
                    one-to-one registration rather than leaving cardinality to
                    a later compiler inference.
                  - Authored and generated macro applications both register
                    `appliesTo` and `resolvedBy` through the same append path;
                    execution and macro-family selection read that graph.
                  - The old `macroEdges` field and helper family no longer exist.
                - [x] Make the semantic plotter consume these relationships
                  directly instead of reconstructing macro nominal references
                  from application spelling and target proximity.
                  - Macro linking records name candidates through the
                    `references` role alongside `appliesTo` and `resolvedBy`.
                    The plotter now derives the application owner, successful
                    declaration, ambiguity, missing target, and mismatch from
                    those relationships plus the linked diagnostic identity.
                - [x] Plot the registered relationships as canonical graph
                  identities and edges.
                  - `CompilerGraphDelta.identities` contains every syntax
                    identity plus macro-declaration and macro-application
                    identities; `relationships` projects the shared registration
                    rows with their exact ordinal, bounds, ordering, separator,
                    and enclosure metadata.
                  - The semantic syntax-node/fact projection remains a lowering
                    adapter for now, so macro identities cannot be misread as
                    runtime syntax by MIR or memory analysis.
                  - value-ownership graph proofs cover resolved, missing,
                    target-mismatched, and ambiguous macro applications, plus an
                    ordered many member relationship.
              - [ ] Move every containment relationship onto named slots before
                retiring the remaining direct/table-local representations.
                - [x] Establish named slots as the canonical registration for
                  declarations and callable shapes.
                  - The active slice registers a reusable `owner → slot →
                    occurrence` graph shape. `members`, function `parameters`,
                    and enum-case `payloads` carry their own ordered-many bounds,
                    separator, and enclosure metadata; the old direct
                    member/parameter edges are derived compatibility projections.
                  - Slot lookup is idempotent by owner identity plus canonical
                    slot name. A future persistent graph index can make that
                    filter a cache lookup without changing the registration API.
                  - `Testing/Graph/Pass/SlotRegistration.range` now proves the
                    slot identities and owner-to-slot-to-occurrence projection;
                    `scripts/range check-value-ownership` passes it alongside the
                    declaration-envelope graph.
                - [x] Move `Block → contents` and its source-layout gaps from
                  block-owned tables to one enclosed containment slot.
                  - The slot carries ordered-many bounds, its delimiter pair,
                    and an admission environment; a syntax form declares the
                    environments it can inhabit. The legacy body `statement`
                    edge remains a lowering adapter until body parsing is fully
                    slot-native.
                  - [ ] Generalize the same slot registration to `()`, `[]`, and
                    `<>` once their parser paths emit occurrence-backed syntax.
                - [ ] Represent every syntax form as ordered anchors and shaped
                  child slots.
                  - An anchor is an introducer or literal plus an `Identity`;
                    a slot is a role identity, delimiter enclosure, and nested
                    syntax child. `@foo() {}` and `#environment {}` must use
                    this same representation.
                  - Derive prefix, postfix, infix, and circumfix views from the
                    anchor's position among slots instead of storing separate
                    parser kinds.
                  - Keep slot enclosure independent from multiplicity,
                    ordering, separator, admission, identity, and runtime
                    representation.
                  - [ ] Prove the smallest Core `SyntaxForm` model through a
                    focused graph fixture, record its first compiler rejection,
                    and upgrade only that general boundary.
                    - [x] Add `SyntaxFormAnchor`, `SyntaxFormSlot`, and the
                      ordered-many `SyntaxForm.parts` model to Core; the
                      canonical declaration-envelope proof compiles it with
                      `@hashable Identifier` and preserves every declared field.
                    - [ ] Commit root `#environment` values as typed graph
                      contributions before querying relationship registrations
                      by type and target identity.
                      - The first live rejection is the old
                        `Macro.Application.value` observer after `@many` stops
                        returning its registration:
                        `macroExecutionBodyInvalid`,
                        `pipelineFailureCode=9012007`, at
                        `registration.multiplicity`. The `@many` producer is
                        not the failing application; `@observeMany` is.
                      - Replace the observer with a graph query only after the
                        contributed `RelationshipRegistration` has a typed node
                        identity. Do not restore the persistent return channel
                        merely to satisfy the old fixture.
              - [ ] Expose type and metatype filtering over that plotted graph,
                then make `@syntax`, `@value`, and nominal selection use the same
                query operation and occurrence-backed result instead of
                `Array<...>` materialization.
                - [ ] Make indexed access require an explicitly ordered many
                  relationship; current source-member indexing remains a
                  compatibility adapter until member ordering is plotted.
              - A many-valued relationship records the syntax separating
                adjacent values; it is not a `Variadic` type or an `Array`
                inference.
              - Remove `VariadicTypeReference` as a semantic concept instead
                of adding an ellipsis-backed compiler path.
              - [x] Reclassify postfix `?` in typed syntax as a zero-or-one
                occurrence relationship whose child retains the underlying
                identity; syntax recipes now report `occurrence=zeroOrOne`
                instead of optional cardinality.
                - The body compiler still lowers this relationship through
                  its built-in Optional sentinel as a compatibility adapter.
              - [ ] Remove the built-in Optional sentinel after stored values,
                parameters/results, calls, pattern matching, ownership, and
                LLVM lowering consume zero-or-one occurrence directly.
              - Model array syntax as element occurrences enclosed by `[]`
                and separated by `,`; argument lists, parameter lists, syntax
                captures, and blocks must reuse the same occurrence machinery.
              - Delimiter shape and separator syntax are independently
                swappable representation knowledge and must not choose value
                identity, runtime layout, or collection type.
            - [x] Capture every authored/generated function and entry body as
              one `body` edge to a `Block`, with the block owning its ordered
              syntax children and nested control-flow bodies using the same
              block kind.
              - The typed-body replay now requires two `block` nodes and two
                role-31 `body` edges; value ownership validates, links, and executes
                the resulting compiler output.
            - [x] Preserve authored source spans and generated
              macro-application provenance independently from containment.
              - Expansion templates retain their parent macro declaration and
                application while each fragment retains its own file-local
                span, parent fragment, and source ordinal.
            - [x] Capture source-layout gaps as a first-class ECS-style syntax
              table before formatting or projecting presentation into the graph.
              - Each row is anchored by its enclosed containment slot and its
                surrounding syntax identities, retains its exact source span, and records line
                breaks plus independent space and tab indentation counts.
              - The first proof covers typed block statements and empty blocks;
                comments, width wrapping, and user-facing formatter macros stay
                separate from semantic containment.
              - Do not encode `none`/`spaces`/`tabs`/`mixed` as a compiler
                enum. A later Range macro may derive that presentation view from
                the independent table properties.
          - [x] Replace the generated function body's single contiguous
            source range with an ordered expansion-artifact fragment list.
            - A fragment is either authored template syntax, a `#` boundary
              value with its observed dependency, or a child macro result;
              `map` remains an ordinary producer of ordered fragment values.
            - `Testing/Macros/Pass/CodableConstructCollection.range` proves
              two generated functions as eight ordered fragments: four
              authored ranges, two child macro applications, and two nested
              `#properties` boundaries.
          - [x] Persist each boundary value referenced by a generated
            artifact under its parent invocation and lexical binding identity.
            - `#properties` must materialize the actual source-backed `[Let]`
              value after the parent evaluator returns; it must not be
              reconstructed from the spelling `properties`.
            - The Codable fixture now retains two recursive three-row values:
              one `[Let]` root and two source-backed syntax children for each
              helper call.
          - [x] Register each retained macro application with parent
            invocation, fragment ordinal, inherited target/expansion
            authority, and explicit boundary arguments.
            - Expansion-only macros resolve as nested calls rather than fake
              attributes while inheriting the parent construct as their
              `Macro.Environment.target`.
          - [x] Execute ready children in dependency order, recursively
            flatten their `#environment` artifact values, and join them
            into the parent's uncommitted graph delta.
            - [x] Execute ready scalar-result children in source order and
              persist their recursively materialized return values.
              - `CodableConstructCollection.range` now proves three
                invocations and two helper results of `2`.
            - [x] Treat child syntax artifacts as replacement fragments and
              merge nested expansion graph deltas before commit.
              - The source store appends immutable generated files through
                in-place String storage growth, avoiding unsupported stored
                String reassignment in the accepted bootstrap.
              - `CodableConstructCollection.range` proves two opaque child
                artifacts replace the helper calls before the generated
                encode/decode functions are parsed and committed.
          - [x] Reparse and validate only the completed composite function
            body, then commit the parent and all child artifacts atomically.
            - [x] Reparse the completed generated source and reject malformed
              composite declaration ranges before graph-delta commit.
            - [x] Stage all completed bodies before mutating syntax tables so
              a later body failure cannot leave an earlier generated function
              committed inside the discarded compilation transaction.
              - Malformed child syntax is rejected at the completed
                graph-delta boundary before any generated function is exposed;
                commit-time table snapshots and `bufferTruncateInt` restore
                every syntax/type/body buffer if a later mutation fails.
            - A child diagnostic rejects the whole parent transaction; no
              partially generated `encode` or `decode` declaration survives.
      - [x] Restore the Range-authored `Result`, encoder/decoder container,
        coding error, and JSON surfaces needed by generated implementations.
        - `Encoder<Format>`, `Decoder<Format>`, and their keyed containers are
          transport-neutral ordinary Range constructs.
        - `JSON` is an ordinary `@encoding` format with a recursive authored
          value model; the compiler does not discover or special-case it.
        - Runtime JSON parsing/rendering and concrete keyed-container behavior
          remain a separate implementation slice.
      - [x] Make stored-member discovery a Range-authored macro relationship.
        - `Let` and `State` carry `@stored`; `Binding` and `Derived` remain
          non-stored `@property` members.
        - `members.filter(all: @stored)` resolves the declared macro family and
          selects members through their annotated syntax nominal.
      - [ ] Make property constructs the canonical authored syntax IR.
        - [x] Express `Let<Value>` and `State<Value>` directly as attached
          macro applications, an identifier, and one value-producing
          initialization edge.
        - [x] Author `@stored` as a generic structural validator requiring one
          `identifier: Identifier` field and one `value: Value` field.
          - `Array.filter(named:)` is the authored identifier-query surface;
            compiler execution remains part of the template-engine slice.
        - [ ] Teach `@syntax` `$field` templates to parse, validate, and render
          the same construct representation, including plural macro
          applications.
        - [ ] Route boundary-value splicing through the destination template
          instead of compiler-owned `identifier`, `type`, and `value`
          projection cases.
      - [x] Preserve written stored-member defaults through Codable synthesis.
        - [x] Capture `let` and `state` initializer syntax in the canonical
          member graph and include it in declaration fingerprints.
        - [x] Materialize `property.value: Expression?` as an exact
          source-backed macro value and pass it to generated decode calls.
        - Field key overrides and transient/exclusion policy remain deferred.
      - [x] Represent a macro boundary result as one enum value.
        - `CompilerMacroResult` is either `.value(...)` or `.noValue`; evaluation
          and invocation outcomes no longer transport a boolean plus parallel
          result fields.
      - [x] Prove construct-attached automatic fields and generated
        encode/decode bodies through supported fixtures before adding the
        source to the accepted compiler manifest.
        - `Testing/Macros/Pass/InlineCodable.range` is combined with the
          actual `Core/Macro/Codable.range` source by `check-value-ownership`; one
          macro invocation generates exactly `encode` and `decode` without
          nested helper macros.
        - Treat field key overrides and exclusion as separate future coding
          policy features rather than requirements for baseline `@codable`.
    - [ ] Make authored `keyword + name` declarations the graph's canonical
      nominal sources.
      - [x] Cover macros, constructs, enums, authored functions, members,
        enum cases, and ordinary local `let`/`state` declarations without
        inventing a source for payload labels.
      - [x] Preserve references from parsed type positions and macro
        applications, using target-compatible macro resolution and no casing
        heuristic.
      - [x] Emit exact-path/span warnings for missing, ambiguous, and
        target-mismatched references while retaining each reference as a
        syntax witness for tools.
      - [ ] Replace the compact graph tables as the public macro-facing model
        only after the direct syntax values consume these proven identities.
- [ ] Represent project remotes as ordinary Range values.
  - [ ] Add parser and type-system semantics for variadic parameters; the
    lexer already recognizes the `...` token.
  - [ ] Define `Remote` and `Remotes` in Range, then replace the placeholder
    `[Remote]([])` project field with a variadic value such as
    `Remotes("https://github.com/...", "...")`.
- [ ] Remove source-alias ownership conflicts from parser fallback tokens.
  - [x] Replace the enum-payload and balanced-range loop token/cursor
    aggregates with scalar token coordinates and cursor indices.
  - [x] Prove the change advances the candidate/reproduction proof past
    `compilerCoreParseConstructDeclarationParts`.
  - [x] Remove representation-sensitive Optional ABI boundaries from the
    single-character operator and bracket lexer classifiers.
  - [x] Normalize function-boundary return validation for optional and
    transient values.
    - `nil` carries zero owned payload leaves, and transient/non-owning
      function results use the callee return summary instead of re-inferring
      ownership from the nominal `String` type.
  - [x] Keep synthesized runtime calls from inheriting a source function
    call's indirect-return storage merely because they share its source node.
  - [x] Lower cleanup traversal through a synthetic Optional payload as
    `OptionalPayload` MIR instead of a nominal stored-member read.
    - MIR validation now derives the payload type from the operand's Optional
      specialization, so the projection is valid outside `??` syntax.
  - [x] Prove the repaired compiler reaches a stable second/third generation.
    - The cleaned generation 2 and generation 3 LLVM are byte-identical at
      `c85943e4944e6ef1c281783f33b41a07876d2a3fad4d90c91a37e827700a1651`.
- [ ] Give optional coalescing an ownership phi for tracked aggregate values.
  - The value CFG already joins `payload ?? fallback`, but the ownership graph
    must move the selected branch's owned leaves into one joined result and
    destroy only the unselected branch's live leaves.
  - Prove both locally created and boundary-forwarded payload/fallback pairs,
    including aggregates with multiple independently owned String leaves.
- [x] Reconcile the accepted bootstrap manifest with the current compiler inputs.
  - The accepted compiler and its complete manifested input set pass
    `scripts/range check-compiler-integrity`.
- [x] Run the complete validation ladder and promote one reproducible accepted
  compiler after the manifest is repaired.
  - [x] `scripts/range check-build-plan`
  - [x] `scripts/range check-value-ownership --controls`
  - [x] `scripts/range check-compiler-smoke`
  - [x] `scripts/range check-compiler-candidate`
  - [x] `scripts/range check-compiler-integrity`
  - Accepted compiler + source produces the candidate; candidate + the same
    source produces the reproduction. Byte-identical LLVM and executables
    authorize promotion. A third build is redundant after equality.
  - Promotion replaces the accepted compiler; prior checkpoints remain in Git
    history instead of continuing as active authorities.
  - [x] Expose `scripts/range compiler promote --approve` as the single
    promotion command. It runs the candidate/reproduction proof, promotes only
    byte-identical LLVM/executables, and finishes with integrity verification
    instead of compiling a third generation.
  - [x] Rename disposable build artifacts to `.range/Build/candidate` and
    `.range/Build/reproduction`, including build-plan IDs, checkpoints, cache
    metadata, benchmark discovery, and focused proof consumers.
- [x] Resolve the accepted-bootstrap candidate once per compiler-source change.
  - [x] Share one content-addressed resolver between value-ownership, smoke, and the
    ordinary compiler-candidate path; keep bootstrap-bridge production
    separate because it has a different producer.
  - [x] Key the immutable artifact by the accepted bootstrap, ordered runtime set,
    compiler source bundle and inventory, target/toolchain identity, and exact
    Clang invocation flags.
  - [x] Keep value-ownership and smoke proofs independent while reusing the same
    candidate executable and cache key.
    - The final verified shared-cache reuse completed value-ownership in 3.49
      seconds and smoke in 3.72 seconds with cache key
      `22ef98c2c4267c598b7677af4ff9725b46e831fbe705632aeda60b2f25586660`.
  - [x] Add a profile-sensitive development build for value-ownership and smoke.
    - Keep the accepted-bootstrap producer optimized, but validate and link the
      disposable development build with `-O0` and no LTO. Candidate, fixed-point, and
      promotion paths retain `-O2` plus ThinLTO.
    - Key the profile and both producer/output flag sets into the immutable
      cache, so development artifacts cannot satisfy optimized gates.
    - Emit phase timings on cache misses. The first measured development miss
      spent 18 seconds linking the optimized bootstrap, 593 seconds emitting
      LLVM, 1 second validating LLVM, and 2 seconds linking the candidate.
  - [ ] Make compiler LLVM emission incremental or cacheable below the full
    source-bundle key.
    - [ ] Make compiler performance observable at authored phase and work-unit boundaries.
      - [x] Add exact monotonic begin/end duration for every emitted function
        without changing the compiler/runtime ABI, and expose it through
        `scripts/range compiler profile` alongside the existing phase trace.
      - [ ] Add Range-owned work counters for repeated arena construction,
        parsing, resolution, CFG, ownership, MIR, ABI probing, and emission so
        time can be compared with exact units of work rather than wall time alone.
        - The first matched development profile spent 308,982 of 393,134 ms in
          ABI components and 61,356 ms in effects/return summaries. Declaration
          capture plus macro linking/execution took 1,103 ms. Treat this as
          evidence that graph cutovers did not remove typed-body recomputation.
        - Instrument ABI probes as parse, resolution, CFG, ownership, MIR,
          validation, emission, and cleanup intervals, then rank both aggregate
          stages and individual specialized functions.
      - [ ] Eliminate repeated per-function ownership reconstruction only after
        the profile proves which reusable frozen facts preserve specialization,
        effect, return-summary, and ABI dependencies.
        - The graph owns identity, observations, dependency edges, and reverse
          invalidation. It does not recreate resolved bodies, CFG, ownership,
          MIR, ABI proofs, or LLVM. Retain those typed products explicitly and
          make later phases consume them.
        - [x] Build the direct effect/return product on the resolved discovery
          arena instead of reparsing the same function during the later
          effects phase.
          - Discovery now resolves, assigns instances, builds CFG/owned paths,
            and records direct effects plus the non-tracked return summary
            before it destroys that arena. The later effects phase only closes
            and validates the accumulated product before owned-return summary
            construction.
          - `scripts/range check-value-ownership --controls` passed after a
            development self-emission of 663 seconds (666 seconds total), and
            `scripts/check-range-compiler-v1` passed in 47.37 seconds with a
            cold `bodyProduct.directEffects` trace assertion. This removes one
            parse/resolve/CFG/owned-path reconstruction per reachable function;
            it does not yet retain ABI-dependent ownership/MIR products across
            ABI probes.
      - [ ] Represent compiler errors as typed, retainable phase products.
        - [ ] Introduce stable error identity, nominal kind, phase/operation,
          subject identity, source witness, expected/observed fields, optional
          cause, and observed dependency fingerprints.
        - [ ] Make one narrow phase return an explicit success-product or
          error-product outcome and render its existing diagnostic only at the
          outer CLI boundary.
        - [ ] Persist and invalidate failed outcomes by the same observation
          rules as successful products so unchanged failures do not rerun the
          complete phase.
        - [ ] Replace cross-boundary arithmetic codes and overloaded negative
          IDs incrementally; keep private local sentinels only where they cannot
          escape their typed algorithm boundary.
        - The current compiler stores failures in `Buffer<Int>`, multiplexes
          reachability errors through shared counter slots, encodes ownership
          and MIR context into decimal ranges, and reconstructs the diagnostic
          later. This loses error identity and prevents safe failed-product
          reuse.
      - An 8-second live sample of the frozen reproduction run placed 6,377 of 6,468
        samples in per-function emission, 3,420 in memory construction, and
        3,259 in owned-path validation; the sampled process had reached a 16.9
        GB peak physical footprint. Treat this as hotspot evidence, not an
        exact whole-build phase total.
    - Phase timings show self-emission, not Clang or linking, dominates a
      compiler-source cache miss; preserve full candidate/fixed-point proofs.
    - The `@stored` selector proof measured 916 seconds emitting LLVM, 2
      seconds validating it, and 2 seconds linking the candidate. The identical
      follow-up value-ownership run reused the immutable artifact and completed in
      about 4 seconds.
    - [x] Add a validated rolling development producer and skip the duplicate
      ownership/Behavior-fact derivation only for marked development source sets.
      - value-ownership publishes a development compiler as a future producer only
        after all focused proofs pass. Optimized candidate, fixed-point, and
        promotion gates continue from the accepted bootstrap and retain the full
        independent effect-validation pass.
      - The producer identity is part of the immutable cache key; the normal
        source snapshot remains unchanged and the marker exists only in the
        disposable emission bundle.
    - [x] Measure a marker-aware cache miss and record the new phase timings.
      - The strict bootstrap miss emitted LLVM in 777 seconds. The validated
        marker-aware forced miss emitted LLVM in 650 seconds, validated in 1
        second, linked in 2 seconds, and passed the focused value ownership suite.
        This proves the duplicate effects pass was removed but is only a 16%
        improvement; do not describe it as the feedback-loop fix.
    - [ ] Cache immutable LLVM fragments per specialized function and reuse
      unchanged fragments across compiler-source misses.
      - Key each fragment by the function body, generic specialization, and
        referenced ABI/layout/effect dependencies. Invalidate only the changed
        function and its graph dependents.
      - The marker-aware sample is dominated by
        `compilerBodyLLVMEmit` and
        `compilerBodyLLVMEmitterRenderCFGDepthFirst`, including repeated
        nominal-declaration and syntax-row resolution while rebuilding the
        complete LLVM text.
      - [x] Make function artifacts the only module-assembly input.
        - Reset SSA temporary numbering per function instance and namespace
          emitted String globals by function-instance identity, removing
          emission-order coupling between otherwise independent fragments.
        - Record each specialized function's body/specialization identity,
          dependency fingerprint, function/global text ranges, runtime
          requirements, and emitted call-edge range in the canonical artifact
          table. Assemble the module only by consuming that table; do not
          append lowered functions directly to the module buffers.
      - [x] Persist the canonical artifact table/text bundle beside the
        validated development producer.
        - Exact matches are keyed by body/specialization identity, ABI/effect
          dependencies, and outgoing-edge fingerprints. The bundle is
          capability-scoped, loaded before lowering, and atomically replaced
          only after the completed LLVM module validates.
        - A one-function capacity delta reused 2,631 artifacts, rebuilt exactly
          1, validated LLVM in 2 seconds, and linked in 1 second. Total compiler
          emission still took 326 seconds, so artifact correctness is proven
          but the feedback loop is not yet fast.
      - [x] Fail closed when positional artifact edges come from a different
        complete source graph.
        - Adding two declarations shifted function rows while a stale cached
          `processArgumentRecord` artifact still named its callees by row; the
          shifted edge resolved to `compilerBodySymbolTypeEndColumn` and
          produced the false `failureCode=4123` diagnostic.
        - Function-artifact storage is now additionally scoped by the exact
          source-bundle hash. This preserves same-source reuse and prevents
          cross-source row aliasing until edges are serialized by identity.
      - [ ] Replace positional function-row artifact edges with stable
        identities, then recover safe reuse across source-graph changes.
        - The latest broad Core change reused only 11 artifacts and rebuilt
          2,939; Range LLVM emission took 633-634 seconds while validation took
          1 second and linking 2 seconds. Semantic reconstruction and emission,
          not LLVM validation or linking, remain the dominant cost.
        - The independent optimized candidate measured 714 seconds for Range
          LLVM emission, 1 second for validation, 22 seconds for linking, and
          755 seconds total before its complete candidate audit passed. The reproduction
          then compiled, validated, and linked the full 29-file compiler, but
          required about 25 minutes of CPU in the same global emission path.
        - Candidate and reproduction executables were byte-identical at SHA-256
          `12252dcd0c72aed205657df039841f75c4d1dc8b4a9b992365ae229b470162cf`
          and 3,522,096 bytes even though their LLVM differed. The reproduction
          and an explicit diagnostic rebuild were byte-identical at SHA-256
          `90f3adabfc443c33860451a869ce7302bdcc17449bee0ce046f810a3b8423882`
          and 8,536,584 bytes; the diagnostic rebuild also passed Clang validation. That
          independently reproduced artifact is now the accepted bootstrap at
          version `bootstrap-90f3adabfc44`.
      - [x] Pin development producers explicitly and remove the legacy
        `single-pass-v1` producer fallback.
        - Normal successful development gates no longer advance the producer.
          `RANGE_BUILD_ADVANCE_DEVELOPMENT_PRODUCER=1` is required after a
          focused validation pass.
        - The original `per-function-artifacts-v1` producer required a bundle
          on every source-key miss; missing or malformed artifact state was a
          hard failure. `function-derivations-v2` replaces that source-keyed
          layout with a producer-keyed rolling checkpoint after schema v9
          proved stable call-boundary identity across declaration-row shifts.
      - [ ] Persist typed phase products and use the graph only for observation
        identity and reverse invalidation.
        - Fingerprint each syntax value independently, including blocks,
          functions, local and stored bindings, macro applications,
          constructs, and enumerations. Retain resolved-body, CFG, ownership,
          MIR, ABI-proof, and LLVM products under the syntax/function-instance
          identity plus the fingerprints actually observed by that phase.
        - Invalidate the first changed product plus its reverse dependency
          closure. Functions remain LLVM-fragment owners, but later phases
          consume retained typed predecessors rather than reconstructing them
          from source and graph tables.
        - The exact-hit run still reparses/replans the complete compiler and
          reconstructs an approximately 8.3 MB artifact/module String.
          Dense instance indexing and unchecked string slices preserved the
          2,631/1 reuse boundary but did not reduce the 326-second emission
          time.
        - Rebuild only changed source facts and their reverse dependency
          closure; assemble unchanged fragment files without reserializing
          their contents through interpreted Range loops.
      - [ ] Delete the whole-bundle development emission path after delta
        persistence proves unchanged, body-only, ABI, layout, and transitive
        caller invalidation controls.
  - [ ] Remove the labeled schema-1 executable-only compatibility lookup after
    the next compiler-source miss publishes the first schema-2 LLVM plus
    executable entry; bound cleanup of quarantined invalid entries then.
  - [x] Confirm artifact-level reuse is insufficient for compiler-source
    misses; pursue the per-function fragment task above.
- [ ] Promote the latest accepted bootstrap as the runnable `range` compiler.
  - [ ] Make `range compile <folder>` discover the project, Core, Foundation,
    framework, and generated source graph and compile it with the immutable
    accepted compiler artifact.
    - [x] Add the supported `range compile <file-or-folder>` bootstrap path
      with deterministic recursive project discovery, accepted Core sources,
      and the shared immutable compiler artifact.
    - [ ] Move Foundation, framework, generated-source, and dependency graph
      discovery behind the Range-authored project macro.
  - [x] Give the artifact a compiler version plus content hash, target, runtime
    ABI, and source-manifest identity; keep its LLVM as reproducibility
    evidence rather than the only usable bootstrap.
  - [ ] Make compiler generation N produce the candidate executable for
    generation N+1, then promote only after the fixed-point and candidate
    gates pass.
    - [x] Separate accepted compiler artifact verification from child
      compiler/runtime inputs in the development generation path.
      - `compiler next` and the producer side of `compiler progression` now
        execute the manifest-verified accepted executable directly. Changed
        compiler and runtime sources remain content-addressed child inputs;
        ordinary accepted-compiler commands retain full manifested-runtime
        verification.
    - [ ] Record the child compiler source revision, producing compiler
      artifact, and compilation application as identified Composition values.
    - [ ] Make the exact child compiler compile RangeView as the normal product
      proof without requiring a candidate/reproduction fixed point.
  - [ ] Reuse the same content-addressed executable in the public command and
    all proof gates without reusing proof results.
- [ ] Remove Clang as a compiler-semantic dependency.
  - [x] Stop requiring the consumer's exact Clang version to equal the
    producer version recorded in the accepted-bootstrap manifest.
  - [ ] Keep fixed-point LLVM generation independent of the installed C
    compiler; test runtime linking as a separate target-toolchain capability.
  - [ ] Move the remaining C runtime surface into Range-authored Core/runtime
    code.
  - [ ] Replace the temporary Clang LLVM validation/link provider with a
    versioned, replaceable object/link backend.
    - [ ] Add a `range backend` boundary that consumes emitted LLVM and
      produces a target object without routing through the Clang driver.
      - The current machine has `/usr/bin/ld` but no `llc`, `llvm-as`, or
        `opt`; `ld` cannot consume LLVM IR, so this requires a shipped LLVM
        target backend or a Range-owned Mach-O/object writer.
    - [ ] Invoke the platform linker directly with a deterministic,
      manifest-recorded SDK/runtime link plan after object production.
    - [ ] Replace `Core/Package/LinkPlan.range`'s authored `clang` process with
      that backend plus direct-link plan.
    - [ ] Remove Clang identity and flags from candidate cache/build-plan keys
      only after object generation, runtime compilation, validation, and
      linking have independent versioned owners.

## Repository Layout

- [ ] Adopt the proposed top-level ownership layout.
  - [ ] Move the accepted compiler bootstrap and manifest from
    `RangeCompiler/Bootstrap` to `Bootstrap`.
  - [ ] Move the Range-authored compiler phases from
    `RangeCompiler/Sources/Compiler` to `Compiler`.
    - [ ] Keep `Body`, `Driver`, `Graph`, `LLVM`, and `Syntax` as the explicit
      compiler implementation roots.
    - [ ] Make compiler discovery read only those implementation roots instead
      of recursively treating adjacent libraries as project sources.
  - [ ] Move the C runtime from `RangeCompiler/Runtime` to `Runtime`.
  - [ ] Move `RangeCompiler/Sources/Core` to the root `Core` folder.
  - [ ] Move `RangeCompiler/Sources/Foundation` to the root `Foundation`
    folder.
  - [ ] Move `RangeCompiler/Sources/Frameworks` to the root `Frameworks`
    folder, with RangeView at `Frameworks/RangeView`.
  - [ ] Update `Project.range`, source manifests, build-plan logic, scripts,
    fixtures, and documentation to the canonical paths.
  - [ ] Reach a candidate/reproduction byte-identical fixed point, promote the
    path-aware bootstrap, and independently reproduce it before completing the
    checkpoint.

- [ ] Review the Core and Foundation boundary without collapsing it by folder
  count alone.
  - Core contains the facilities required to describe and bootstrap the basic
    language, including macro machinery and contracts.
  - Foundation currently contains concrete reusable macros such as `Field`,
    `Property`, `Registrable`, and `Syntax`.
  - [ ] Decide macro by macro whether each Foundation facility is fundamental
    enough to move into Core.
  - [ ] Collapse Foundation only if the dependency distinction no longer
    represents a real compilation or package boundary.

## Composition and Flow Compiler Plan

This is the single active architecture plan for compiler graph, storage,
incrementality, scheduling, and cold-start work. Historical V1 timings and
superseded phase plans live in
[DeltaDBSpacetimeDBRangeHandoff.md](Development/DeltaDBSpacetimeDBRangeHandoff.md),
not as competing active checklists here.

The implementation order is layered. V1 keeps the typed syntax, resolution,
CFG, ownership, MIR, Behavior, and target-plotting products authoritative while
removing measured repeated work. Composition, Delta, and Flow remain an
isolated meta-model research lane until a later compiler generation proves
equivalent typed queries and an incremental benefit. A faster Composition
index is not evidence that flattening the semantic layers accelerates compiler
emission.

- [ ] V1: reduce measured typed-function reconstruction without changing the
  language ontology.
  - [x] Remove the unvalidated `CompilerCompositionExactIndex` lookup cutover
    from the active graph plotter; keep the index and Composition fixtures as
    isolated experiments.
  - [x] Report ABI reconstruction multiplicity from the existing profiler:
    probe passes, final emission passes, extra probes, repeated function rows,
    and the most-probed function.
    - The 2026-08-07 accepted-bootstrap and current-candidate profiles both
      reported zero ABI probe passes. Do not optimize or retain products for a
      repetition that the current compiler-source workload does not perform.
  - [x] Report discovery-side typed products beside final emission passes.
    - Both full profiles observed 3,033 `bodyProduct.directEffects` passes and
      3,033 final function emission passes: one broad discovery pass and one
      broad emission pass per reachable function instance.
  - [x] Test one bounded parsed-syntax discovery product through final
    emission without retaining a complete live arena, then remove it when the
    controlled profile showed no improvement.
    - The candidate-powered profile completed in 536,701 ms, with Behavior
      facts ending at 172,781 ms, call-boundary shapes at 181,678 ms, and final
      function emission at 526,444 ms. Maximum resident memory was
      12,451,119,104 bytes and peak footprint was 15,689,364,368 bytes, so a
      full-arena retention experiment is not acceptable without a tighter
      physical product.
    - The full candidate-powered workload retained and reused 216 of 3,052
      function syntax products (7.1%). It completed in 543,000 ms, with
      11,469,324,288 bytes maximum resident memory and 14,258,926,504 bytes
      peak footprint. Because the compiler source grew and the earlier run was
      not a same-source disabled control, this proves bounded consumption but
      not a speed or memory improvement.
    - The alternating same-candidate, same-source disabled/enabled control
      settled the experiment: disabled runs were 437,508 ms and 437,921 ms;
      enabled runs were 439,300 ms and 437,004 ms. The enabled mean was 437.5
      ms slower (about 0.10%) and showed no memory win. The product, its
      profile switch, and its focused reuse requirement were removed.
  - [x] Establish a clean post-removal cold baseline, then split
    `compilerBodyLLVMEmitterProcessOperation` along existing operation-family
    boundaries and repeat the same candidate-powered profile.
    - The current profile attributes about 52--54 seconds of compiler-source
      emission to compiling this single function. The change must preserve
      typed layers and earn retention through an attributable time or memory
      improvement.
    - Clean baseline: 445,031 ms total, 9,767,469,056 bytes maximum
      resident memory, and 56,041 ms compiling the 539-line dispatcher.
    - The aggregate/storage, call/string, and scalar/control helpers preserve
      the moved operation branches exactly; the Compiler V1 gate passes with
      linked `7`/`8` results.
    - First post-split profile: 404,994 ms total (40,037 ms or 9.0% faster)
      and 4,990,402,560 bytes maximum resident memory. The three helper compile
      times sum to 16,231 ms, 39,810 ms below the monolith and therefore almost
      exactly accounting for the full cold-time improvement.
  - [x] Confirm the operation-family decomposition with a second cold profile.
    - The second run took 401,424 ms with 5,674,303,488 bytes maximum resident
      memory; helper compile time totaled 16,291 ms. Both post-split runs wrote
      the identical artifact SHA-256.
    - The 403,209 ms post-split mean is 41,822 ms (9.4%) faster than the clean
      445,031 ms baseline. Reported maximum resident memory stayed between
      4,990,402,560 and 5,674,303,488 bytes, below the 9,767,469,056-byte
      baseline.
  - [x] Promote the proven operation-dispatch checkpoint with the canonical
    candidate/reproduction proof.
    - Candidate and reproduction LLVM matched at
      `5ed288a4ed11823c3456cbcb093b4070c6a7a4551130a73d9aac681e46f8455a`;
      executables matched at
      `941d9cddad2d874c3cd9180062f66847aa0b73fc0b888a2c9275766d94c6b6a2`.
      Accepted-bootstrap integrity passed after replacement.
  - [x] Apply the same one-change decomposition experiment to
    `compilerBodyMIRValidationCode` from the newly promoted bootstrap.
    - It is now the largest compiler-source function at 45,325--46,050 ms per
      cold profile. Establish its semantic branch families before moving code,
      preserve exact validation failures, and compare against the 403,209 ms
      post-dispatch mean.
    - The 608-line validator is now a 123-line coordinator over exact
      call/macro, aggregate/storage, and optional/string/control families. The
      Compiler V1 gate passes with linked `7`/`8` results.
    - First post-split profile: 348,334 ms total, 54,875 ms (13.6%) below the
      403,209 ms prior mean. The coordinator compiled in 994 ms and the largest
      helper in 2,106 ms; the remaining helpers were below the profile's
      top-50 duration cutoff.
  - [x] Confirm the MIR-validation decomposition with a second cold profile.
    - The confirmation took 348,088 ms and wrote the identical artifact
      SHA-256. The 348,211 ms two-run mean is 54,998 ms (13.6%) below the
      403,209 ms prior mean, with essentially identical per-function timings.
  - [x] Inspect and decompose
    `compilerBodyMIRBuildExpression`, now the largest compiler function at
    13,551--13,582 ms. Preserve `CompilerBodyMIRValueResult` failure and block
    propagation exactly, then rerun Compiler V1 and the cold profile.
    - Scheduled and optional-join results still short-circuit in the 17-line
      coordinator. Exact basic/reference, application/call, and operator
      branches moved to helpers; recursive construction still returns through
      the coordinator. Compiler V1 passes with linked `7`/`8` results.
    - First post-split profile: 337,305 ms, 10,906 ms (3.1%) below the 348,211
      ms prior mean. Application and basic helpers compiled in 1,460 ms and
      1,012 ms; operator and coordinator functions were below the top-50
      duration cutoff.
  - [x] Confirm the expression-builder decomposition with a second cold
    profile.
    - The confirmation took 337,415 ms and wrote the identical artifact
      SHA-256. The 337,360 ms two-run mean is 10,851 ms (3.1%) below the
      348,211 ms prior mean, with stable helper timings.
  - [x] Measure memory before continuing the
    `compilerBodyArenaResolveExpression` decomposition.
    - Profiler-only phase RSS telemetry places the dominant increase inside
      function-behavior derivation: 1,686,192,128 bytes after artifact
      candidates and 4,819,648,512 bytes after behavior facts in the
      controlled development profile. Function emission then raised the
      high-water mark to 5,320,802,304 bytes.
    - The exact reference/application/literal/operator resolver split passed
      Compiler V1, but a controlled development profile remained effectively
      neutral at 341,832 ms and 4,820,418,560 bytes after behavior facts. The
      split was removed; smaller source functions did not reduce the dominant
      behavior-memory boundary.
  - [x] Remove the duplicate transient payload allocation from runtime string
    concatenation.
    - `stringConcat` now transfers its already tracked joined allocation into
      the transient Range string header instead of copying the same bytes into
      a second allocation. Repeated development profiles produced identical
      8,900,408-byte LLVM and the same function-artifact SHA-256
      (`fa91789d...`). Time remained neutral within run variance. Across the
      two direct before/after pairs, average reported peak footprint fell from
      about 4.67 GB to 3.74 GB; maximum-resident readings were noisier.
  - [x] Profile behavior-effect closure and owned-return-summary construction
    with the generated candidate as the running compiler.
    - The candidate-powered development profile measured 1,687,027,712 bytes
      before derivation, 1,687,339,008 bytes after effect closure, and
      4,819,025,920 bytes after owned-return summaries. Effect closure added
      only about 0.3 MB; owned-return reconstruction added about 3.13 GB and
      took 38,575 ms.
    - Current-resident telemetry confirmed the pages remained live at the
      owned-return boundary. The process construct-identity arena reserved
      only 10,747,904 bytes, and macOS allocator pressure relief released zero
      bytes, ruling out both construct identities and immediately reclaimable
      allocator cache as the explanation.
    - Repeated candidate runs emitted identical 8,901,595-byte LLVM and the
      same function-artifact SHA-256 (`8602ec1f...`). The profiler command
      returns status 1 in the managed sandbox only because `/usr/bin/time`
      cannot query `kern.clockrate`; compilation reached `sourceSet.end`.
  - [x] Account for live raw-buffer and transient-string bytes during owned
    return reconstruction.
    - Owned raw buffers were only 7,252,381 bytes live after the phase, with a
      7,889,620-byte peak. Transient allocations returned to zero but reached
      a 2,511,148,512-byte peak during the phase. This is temporary allocator
      churn inside owned-return work items, not retained behavior facts.
    - Repeated candidate output remained identical: 8,901,595-byte LLVM and
      artifact SHA-256 `8602ec1f...`.
  - [x] Attribute transient peak bytes per owned-return work item and move the
    diagnostic boundary to the emitter after the work-item peak was shown not
    to be causal.
    - The corrected candidate/reproduction profile covered 381 work items; the
      largest was only 99,392 bytes (`functionRow=1945`, `instanceID=2916`).
      Owned-return summaries still ended around 4.82 GB RSS, but their
      transient peak was about 40.8 MB; the 2,852,655,776-byte transient
      high-water was reached during `functionEmission`.
    - Function-level transient attribution identified the largest observed
      increment as 893,450,800 bytes in
      `compilerCoreLLVMLowerHelperFunctionTypedObserved` (function ID 1975).
      The next slice should inspect its lowering buffers and repeated-call
      retention before changing graph or reset semantics.
    - Emitter experiment: `compilerBodyLLVMEmitterAppendInstruction` now
      appends instruction components directly to `renderedBlocks`, avoiding
      one interpolated temporary per instruction. Candidate/reproduction
      output converged (`LLVM 8,906,270 bytes`, artifact SHA
      `dc25ce79655d...`), but the function-emission transient high-water stayed
      around 2.852 GB, so this change is currently inconclusive rather than a
      measured memory win.
    - Materialization experiment: transferring `renderedBlocks` ownership into
      the transient region avoided the final copy in isolation, but the
      function-emission high-water remained about 2.852 GB. The ownership
      transfer was reverted; the next target is operation-processing churn.
    - Emitter stage trace: planning peaked at 919,072 bytes, CFG rendering at
      7,156,784 bytes, materialization at 81,968 bytes, and global rendering at
      728,096 bytes. These are not large enough to explain the enclosing
      helper's roughly 1 GB transient increment; pre-emitter parse/memory/MIR
      boundaries are now instrumented and need a fresh candidate build to
      bypass the prior artifact cache.
    - Fresh candidate/reproduction attribution now identifies
      `compilerBodyMemoryDerive` as the dominant bounded stage: 394,109,040
      bytes peak, versus 75,152,880 for lowering emission and 30,882,096 for
      MIR construction. The next slice should split `compilerBodyMemoryDerive`
      across owned-path construction, value/placement/access/pass-escape,
      validation, and lifetime phases.
    - [x] Add `scripts/profile-range-compiler-suspects` as a repeatable TSV
      matrix harness for owned-return, function-emission, raw-buffer,
      per-function, and per-work-item suspects. It preserves artifact identity
      and separates measured deltas from run-to-run RSS noise.
      - Baseline run (`current-emitter`) completed with status 0, LLVM size
        8,906,270, artifact SHA `dc25ce79655d...`, 5,643,960,320-byte maximum
        resident set, 2,852,023,312-byte function-emission transient peak,
        7,889,620-byte raw-buffer peak, and an 893,474,784-byte peak in
        `compilerCoreLLVMLowerHelperFunctionTypedObserved`.
    - Current proof boundary: the runtime optimization changes accepted
      runtime-source hashes, so `check-build-plan` intentionally stops at the
      manifest mismatch until a deliberate candidate/reproduction checkpoint.
      The optimized runtime has profile/output equivalence evidence, not a new
      Compiler V1 or fixed-point proof.
- [ ] V2: introduce Composition/Delta/Flow beneath the typed semantic products
  and prove query equivalence plus invalidation behavior before any cutover.
- [ ] V3: reconsider which semantic distinctions and compiler-wide ABI
  authorities can actually be deleted after V2 evidence exists.

The coding model is authoritative; algebraic names describe observable shapes
but do not replace the executable Range constructs:

```text
construct = product
enum       = sum
property   = field
function   = transformation
macro      = environment
delta      = product
flow       = carrier of deltas
```

The core invariant is:

> Every graph value is an identified, ordered composition of identities.
> Combining compositions creates another identified Range point which can
> itself participate in later compositions.

- [ ] Milestone 1: make `Composition` the semantic graph primitive.
  - [x] Define the minimal Core value:

    ```range
    construct Composition {
        let identity: Identity
        let components: Array<Identity>
    }
    ```

    - `RangeGraphTopology.compositions` exposes the first compatibility view;
      existing node/relationship fields remain until equivalent queries are
      proven and their consumers can be deleted together.
    - `scripts/range check-composition` compiles, validates, links, and runs a
      focused fixture. Two anchors retain distinct identities over the same
      ordered components, and a third composition recursively consumes the
      first anchor identity; the executable exits `7`.

  - [ ] Keep identity, current value, and structural fingerprint distinct.
    - An identity names a stable authored or derived occurrence.
    - `components` are its current value at a revision.
    - A disposable fingerprint indexes structural equality; it never replaces
      identity, so two occurrences may have equal components and different
      identities.
  - [ ] Prove ordered syntax-identity compositions for the representative
    language forms before generalizing storage:
    - construct member products such as `[User, name]` and `[User, age]`;
    - enum case sums such as `[queued, Message, View]` and
      `[pending, Message, View]`;
    - function access/transformation paths such as
      `[User, name, .count]`;
    - property identities as fields rather than a separate projection value;
    - macro identities as the available compile-time environment; and
    - delta identities as an atomic product of change compositions.
  - [ ] Prove composition anchoring and recursive composition.
    - Combining `A` and `B` produces an identified anchor `AB -> [A, B]`.
    - Many-to-many relationships are sets of such anchors, not a separate
      table kind or cardinality ontology.
    - Multiple anchors may share `[A, B]` while retaining distinct occurrence
      identity and provenance.
    - N-ary component arrays are identified hyperedges; another composition
      may use their identity as an ordinary component.
  - [ ] Decide explicit normalization laws rather than assuming associativity.
    - `(A x B) x C`, `A x (B x C)`, and `[A, B, C]` retain authored identity
      unless a typed view explicitly proves them equivalent.
  - [ ] Replace `RangeGraphNode`, `RangeGraphRelationship`, and their parallel
    semantic stores only when Composition fixtures prove equivalent queries
    and the old model is deleted in the same checkpoint.

- [ ] Milestone 2: represent Delta as a product of identified changes.
  - [ ] Move rooted paths and requirement/provision routing out of Delta; they
    belong to Flow.
  - [ ] Encode insert, replace, remove, and relationship change as ordinary
    change compositions carrying target, observed version or prior value, and
    next value where applicable.
  - [ ] Encode one Delta as an ordered composition of those change identities,
    with parent revision, origin/environment, observations, diagnostics, and
    provenance represented through compositions rather than a second graph
    schema.
  - [ ] Commit the complete Delta product atomically or leave the accepted head
    unchanged.
  - [ ] Prove the batching law operationally: disjoint Delta products may
    commute; overlapping observation/write sets must retain order or be
    re-derived from the new head.
  - [x] Append each accepted compatibility revision as an immutable
    parent-linked record and advance `delta-head.tsv` atomically. Warm reuse
    and failed candidates append nothing, and an edited child preserves its
    parent bytes.

- [ ] Milestone 3: implement Flow as the system carrying Delta compositions.
  - [ ] Define Flow independently from Delta with an identity, root,
    environment, frontier, and ordered composition paths.
  - [ ] Make an access path an ordered array of actual syntax identities, not
    a parallel path-node taxonomy or a list of storage-table rows.
  - [ ] Treat the whole graph as shared compositions while a walk rooted at one
    composition unfolds as a tree.
  - [ ] Make the language forms carry their natural paths:
    - constructs carry declared field compositions;
    - enums carry alternative case/payload compositions;
    - functions carry consumed, accessed, and produced compositions; and
    - macros carry the environment in which those identities are available.
  - [ ] Make each reducer consume a Flow frontier and propose a Delta product;
    the reducer is not itself durable state.
  - [ ] Schedule deterministic rooted frontiers and run only interactions whose
    observation and write compositions are disjoint.
  - [ ] Derive binding, fan-out, erasure, ownership, and target requirements as
    explicit compositions carried by Flow rather than implicit upward or
    compiler-global phase state.

- [ ] Milestone 4: derive cheap indexes and freeze-dried checkpoints.
  - [x] Establish a like-for-like primitive query baseline before adding
    indexes.
    - `scripts/range benchmark-composition` constructs each representation
      once, performs 20,000,000 runtime-anchored origin/role/destination
      matches, and reports five-sample alternating medians at `-O0`.
    - Runs on 2026-08-07 placed unindexed Composition path access at `0.992x`
      to `1.078x` the direct-field time. This verifies no
      primitive-level speed improvement yet; the performance claim belongs to
      derived indexes and measured physical layout.
  - [ ] Implement disposable exact-sequence, prefix, component-position,
    extension, and reverse-membership indexes over Composition identities.
    - [x] Implement the first exact-sequence lane as a compiler-owned,
      disposable buffer index without changing the logical `Composition`
      model.
      - The index stores ordered two-word identity representations, uses a
        fingerprint only to select a collision chain, and confirms every hit
        through full ordered identity comparison.
      - `scripts/range check-composition` proves order sensitivity, two
        identity-distinct anchors for one component sequence, misses, and
        equivalent results after rebuilding the index.
      - Across four runs of 64 graph values and 500,000 exact lookups, indexed
        lookup took `0.159x` to `0.163x` the direct relationship scan and
        `0.135x` to `0.137x` the unindexed Composition scan at `-O0`.
    - [ ] Add prefix, component-position, extension, and reverse-membership
      lanes only as concrete compiler consumers require them.
  - [ ] Keep the language model as `Array<Identity>` while measuring an inline
    physical representation for the common two-to-four-component case and a
    spill path for longer compositions.
  - [ ] Make index and checkpoint storage replaceable without changing logical
    queries; dense buffers, row-major stores, tries, and structure-of-arrays
    remain physical choices rather than semantic authorities.
  - [ ] Rebuild a missing or stale compatibility checkpoint by replaying the
    accepted Delta chain, then make replay rather than `revision.tsv` presence
    the load authority.
  - [ ] Measure exact lookup, prefix traversal, reverse invalidation, delta
    apply, replay, checkpoint load, compile time, and peak RSS before claiming
    the representation is cheaper.

- [ ] Milestone 5: cut the compiler over to Composition and Flow.
  - [x] Retain schema-v9 function derivations across declaration-row shifts and
    use stable call-boundary identities for artifact dependencies.
  - [x] Group ownership paths, calls, and returns under one transitional
    `CompilerFunctionBehaviorFacts` entity and reserve freeze vocabulary for
    disposable checkpoints.
  - [ ] Replace per-function reconstructed facts with the actual compositions
    each function consumes, accesses, produces, moves, writes, destroys, or
    requires from its environment.
  - [ ] Represent each caller/callee boundary as a shared Composition. Plot the
    target machine convention consistently at both ends without a
    compiler-wide semantic ABI plan.
  - [ ] Delete `CompilerCallBoundaryPlan` and parallel global effect summaries
    once focused ownership, aggregate-return, call, and runtime controls pass
    through the Composition path.
  - [ ] Make changed source produce a Delta at the first changed composition
    prefix and invalidate only its reverse-composition closure.
  - [ ] Move cache lookup before body reconstruction and make the rolling
    producer-keyed cache a freeze-dried Composition checkpoint rather than an
    alternative semantic artifact graph.
  - [ ] Make compilation consume target-independent Composition/Flow values;
    make target plotting, build/link, and execution distinct products.
  - [ ] Delete superseded Source/Shape/Behavior/Compiled phase records,
    node/edge stores, numeric-column accessors, and legacy parser/lowering
    chains only when their last supported consumer moves in the same proven
    checkpoint.

- [ ] Milestone 6: simplify physical storage and runtime after the semantic
  cutover.
  - [ ] Complete deterministic automatic lifetimes for Composition-owned
    String, Buffer, and aggregate values.
  - [ ] Move compiler text and scratch storage onto canonical authored Core
    facilities without repeating the immutable-concatenation regression.
  - [ ] Keep dense integer storage private behind measured Composition indexes;
    do not create a milestone whose goal is merely renaming Int tables.
  - [ ] Remove raw runtime and platform entry points only after their final
    accepted Composition/Core caller disappears.

Discarded roadmap assumptions:

- Shape, Usage, Ownership, Representation, ABI, and LLVM are not a permanent
  compiler-wide phase hierarchy. They may remain temporary typed views while
  the Composition cutover is proven.
- Nodes, binary edges, relationship cardinality tables, function-effect
  tables, and ABI plans are not separate semantic graph authorities.
- Typed-store migration is not an end in itself; typed views and physical
  indexes exist to serve Composition queries.
- The graph machine is not a late optimization milestone after compiler
  cleanup. Composition, Delta, and Flow are the current organizing model; safe
  deletion and performance work proceed through that model.

## Compiler and Runtime Follow-ups

- [x] Collapse the accidental `RootValue` taxonomy into ordinary value
  ownership.
  - Ownership paths now distinguish binding roots from evaluation roots
    without introducing a separate language value category.
  - Expansion parsing names an ordinary emitted expansion value, and the
    focused proof surface is `scripts/range check-value-ownership`.
  - The cutover deliberately preserves ownership, LLVM, runtime, and
    deterministic-rejection behavior; it changes representation vocabulary,
    not accepted value semantics.
  - The changed Range-authored compiler emitted in 363 seconds, validated in
    2 seconds, linked in 2 seconds, and completed its development candidate
    build in 367 seconds while reusing 2,895 of 2,917 function artifacts.
  - [ ] Re-run the complete value-ownership fixture set after the independent
    construct-attached Codable collection accepts its retained `Array<@stored>`
    child-macro argument; the gate now passes Core `@many`/`@contents`, block
    relationship reification, collection closures, inline syntax, stored
    defaults, and the Core coding surface before stopping with
    `macroExecutionBodyInvalid`, `pipelineStatus=2`, `pipelineFailureCode=1`.
- [ ] Replace the compiler's direct RawBuffer dependency incrementally.
  - [x] Add `Buffer.range` to the compiler's manifested Core source set.
  - [x] Migrate `CompilerIntTable.values` from `RawBuffer` to `Buffer<Int>` as
    the first compiler-owned table.
  - [x] Prove the migrated table through the full fixed-point gate and promote
    the independently verified accepted bootstrap.
  - [ ] Widen the migration to the compiler's remaining integer and text
    buffers in separately proven slices.
    - [x] Migrate the function-selection bitmap to `Buffer<Int>` and promote
      its independently verified fixed-point bootstrap.
    - [x] Migrate function-call edge owner/target storage, including probe,
      typed, and emission edge pairs, to `Buffer<Int>` and promote its
      independently verified fixed-point bootstrap.
    - [x] Migrate every remaining compiler-owned integer buffer, including
      syntax indexes, failure vectors, Body/ownership scratch state, LLVM
      reachability state, ABI plans, and instance-edge storage, then promote
      and independently verify the byte-identical fixed-point bootstrap.
    - [ ] Replace the remaining byte-oriented text builders with a typed
      `Buffer<Int<8, .unsigned>>`-backed `String`.
      - [ ] Move function-local compiler text builders only after mutable
        String append is canonical.
        - A direct immutable-String migration was rejected: the same 2.65 MB
          source-set compile rose from about 120 seconds to more than 385
          seconds, even though it remained semantically valid.
        - [x] Add in-place `stringAppendStorage` and `stringDestroy`
          operations over the canonical `Buffer<Int<8, .unsigned>>`
          representation, with a focused runtime proof that distinguishes
          immutable literal views from owned mutable `state` text.
        - [x] Forward write and destroy effects through authored transparent
          `String` methods, including automatic owned storage for
          `state value: String("Hello")`.
        - [x] Restore the broader `check-value-ownership` gate and its complete
          positive/rejection control set.
        - [ ] Insert deterministic automatic destruction for owned String
          storage at every valid scope exit.
          - Remove the normal-code requirement for `value.destroy()` while
            retaining destruction as an internal ownership effect.
      - [ ] Replace the three shared accumulators for LLVM body blocks,
        functions, and globals after mutable String storage can cross function
        boundaries without falling back to RawBuffer.
      - [ ] Make the builtin String type and an authored
        `String { state bytes: Buffer<Int<8, .unsigned>> }` declaration share
        one canonical type identity, layout, construction path, and member
        surface.
        - [x] Add the pointer-ABI `String.range` baseline, resolve authored
          members through that canonical declaration without changing the
          primitive runtime type identity, and prove `"Range".byte(index: 0)`
          dispatches through the authored method.
        - [x] Promote the baseline into the accepted self-hosted bootstrap and
          verify candidate/reproduction byte identity, accepted-bootstrap
          integrity, and candidate/reproduction fixed point.
        - [x] Replace the pointer-compatible shell with a transparent
          `Buffer<Int<8, .unsigned>>` field while preserving the one-pointer
          String ABI.
          - [x] Emit literal, transient, command-line, file, interpolation,
            conversion, and metrics Strings as Buffer descriptors; reject the
            former raw `char *` representation at the runtime boundary.
          - [x] Replace the String-named lowering exception with a structural
            transparent-storage rule: a `.storage` construct with one stored
            `.storage` member aliases that member's handle for construction,
            projection, and ownership.
          - [x] Classify stored members as inline core values, identity-bearing
            ordinary constructs, or transparent storage projections, and
            protect all three decisions with one focused compiler proof.
          - [x] Promote the generalized representation checkpoint into the
            accepted bootstrap and independently verify compiler reproduction.
          - [ ] Forward receiver effects through arbitrary transparent derived
            members so `storage.count` is as ownership-complete as the
            explicit `storage.bytes.count` projection.
        - [x] Give member functions owner-qualified LLVM symbols and prove
          `String.count` can coexist with the generic `Buffer.count`.
      - [x] Cut identity-bearing ordinary construct members over from
        recursively embedded LLVM aggregates to the canonical ID/reference
        representation.
        - [x] Store one direct typed pointer per ordinary construct
          relationship; box at construction and state replacement, then use
          direct typed loads for reads and nested mutation.
        - [x] Reject the legacy name-keyed `rangeConstructGet*` lookup path and
          prove nested value ownership and Array mutation use the direct link.
        - [x] Promote and independently verify a byte-identical candidate/reproduction
          fixed point.
        - [x] Make mutation target the final stored cell rather than requiring
          every traversed identity relationship to be `state`.
          - [x] Allow `let` roots and intermediate `let` identity links to
            reach a final `state` Array member while preserving rejection for
            a final `let` Array or immutable binding source.
          - [x] Extend direct member assignment beyond implicit `self`, prove
            `let editor` can update `state name`, and reload identities with
            graph-recorded member writes so later reads observe the update
            without forcing every compiler member read through storage.
          - [x] Promote the target-cell checkpoint into the accepted bootstrap and
            verify bootstrap reproduction plus LLVM/executable fixed-point
            point.
        - [x] Move identity allocation from the temporary host `malloc`
          baseline into a compiler-owned arena with an explicit bulk lifetime.
          - [x] Allocate max-aligned, zeroed identities from 64 KiB bump
            chunks and release all chunks at the generated program boundary.
          - [x] Keep identity storage separate from transient String regions
            and prove a String-region reset cannot invalidate live identities.
          - [x] Emit one arena begin at `main` entry and an arena destroy before
            every return, while retaining lazy allocation only as a bridge for
            pre-arena bootstrap seeds.
          - [x] Promote the arena-aware compiler bootstrap after proving the extra
            bootstrap turn reaches a byte-identical LLVM fixed point.
        - [ ] Benchmark representative shallow, deeply nested, and
          mutation-heavy construct workloads before claiming a universal
          runtime speedup.
          - [x] Add the raw inline-struct race, eight-level identity chain,
            shared binding mutation, and repeated child replacement to the
            canonical speed runner.
          - [x] Link identical Range LLVM against both the arena and the
            benchmark-only legacy `malloc` allocator, recording allocation and
            chunk telemetry for each successful Range row.
          - [x] Make loop-carried mutation through a construct binding lower
            correctly, including observing an indexed write through the
            original owner path.
          - [ ] Add a separate dynamic-dispatch matrix for C function pointers,
            C++ virtual calls, Rust trait objects, Swift protocols, Go
            interfaces, and Range once callable macro-attached capabilities
            have a real runtime surface; do not mix dispatch cost into
            allocation results.
          - [x] Run and publish a stable multi-sample Constructs evaluation
            before choosing another chunk size or claiming a speedup.
      - [ ] Move length, indexing, comparison, slicing, concatenation, and
        append behavior onto the authored String surface, then cut their
        compiler runtime builtin cases over.
      - [x] Remove `RangeCompiler/Runtime/RangeString.c` from the runtime
        manifest and every proof link.
        - Its transient allocation and legacy byte/search compatibility
          entry points temporarily live in `RangeCompilerHost.c`; this removes
          the standalone String runtime owner without claiming those entry
          points are Range-authored yet.
  - [ ] Delete raw runtime entry points only after no accepted compiler or Core
    path consumes them.
  - [ ] Make Optional a Range-authored generic enum with a value-bearing
    absence branch.
    - [x] Support ordered default type arguments on nominal declarations, so
      `Optional<Value, None = Nil>` accepts `Optional<Value>`.
    - [x] Specialize local generic enum case payload types through the enum
      instance's positional type arguments.
    - [ ] Carry specialized generic enum layouts across function ABI
      boundaries.
    - [x] Define canonical `Nil` and `Optional` Core enums and lower `T?`
      through the authored `Optional<Value, None = Nil>` declaration.
    - [ ] Lower bare `nil` and contextual `.nil` through the authored
      `Optional.none(value: Nil.nil)` case.
    - [x] Prove explicit custom absence values, the default `Nil` spelling,
      generic arity rejection, LLVM emission, and the compiler fixed point.
      - Promoted accepted bootstrap `bootstrap-154b7b1459b9`; its manifest-driven
        reproduction produces LLVM hash
        `154b7b1459b90de1b3d38fb5d8ba28e97810407b0d225ecc77e0e369019dc7a3`.

## GPU Drawing

- [ ] Establish Range-authored native FFI as the substrate for GPU and window APIs.
  - [x] Add an `@extern` function macro whose typed `ExternRegistration` result
    drives foreign declaration and direct-call lowering without extending the
    hardcoded runtime-builtin table.
  - [x] Make one post-macro `FunctionImplementation` classification authoritative
    for Range bodies, external symbols, runtime intrinsics, and invalid mixed
    declarations across resolution, reachability, MIR validation, and LLVM.
  - [ ] Prove the first boundary with top-level, bodyless, non-generic `Int`
    signatures, exact LLVM `declare`/`call` output, native linkage, execution,
    and focused rejection controls.
  - [x] Add typed `@link` requirements whose persisted macro values produce
    deterministic linker metadata and drive one native-library link proof.
  - [ ] Add opaque pointers, C strings, `Void`, callbacks, aggregate ABI rules,
    and project-owned library/framework requirements only through subsequent
    focused compiler proofs.
    - [x] Prove Range-authored nominal `@opaque` handles as distinct borrowed C
      pointer tokens before adding nullable pointers or ownership behavior.
- [ ] Prove the first macro-lowered GPU drawing application.
  - [x] Lower a construct-attached Range macro into an ordinary generated
    function that writes a self-contained WebGPU/WGSL application.
  - [x] Add the general `scripts/range run <FILE-OR-DIR>` implementation,
    expose it as `range run`, and make `range run GPUCanvas` generate and
    launch its drawing with no application arguments.
  - [x] Compile, link, and run the generated function, then validate the
    generated JavaScript and WebGPU/WGSL artifact markers.
  - [ ] Verify in a browser that the application obtains a WebGPU adapter and
    presents the triangle.
- [ ] Add a native typed GPU/runtime consumer only after its shader values,
  resource ownership, effects, and Graph 0 scheduling boundary are explicit.
  - [x] Open an SDL2 native window from Range-owned declarations, create an
    accelerated renderer, draw and present a triangle outline, and prove typed
    pointer, unsigned-byte, integer, and Void foreign calls without a host
    wrapper, including renderer, window, and SDL lifecycle cleanup. This is a
    native drawing checkpoint, not the wgpu-native backend.
    - [x] Lift the hardcoded edge coordinates into an ordinary Range-authored
      `Triangle` value and a `rangeViewDrawTriangle(renderer:triangle:)`
      primitive. Prove its by-value Range ABI, one primitive call, exactly three
      SDL edge calls, native window execution, and exit `42`.
    - [x] Make the minimal Triangle application runnable through the public
      `scripts/range run` path. Keep its `Main.range` separate from framework
      source, compose the real native framework with repeatable `--source`, and
      require an explicit unpromoted compiler path while the accepted bootstrap
      is not the current compiler authority.
    - [x] Confirm that the explicit SDL show/raise and event-pump revision
      visibly presents the native Triangle window on the maintainer desktop;
      linked execution and exit `42` alone did not prove presentation.
    - [x] Model `Window` and `WindowRenderer` as distinct Range-authored
      `@opaque` resource identities, route Triangle drawing through the typed
      renderer, and add a `Window` close query for SDL quit events.
    - [x] Remove the ten-second diagnostic lifetime so a RangeView native app
      remains alive until its window closes or its process is terminated.
    - [x] Introduce backend-neutral `Point`, `Size`, and `DrawingSpace` values,
      and source the native window dimensions from its drawing space.
    - [x] Render one collection-driven gallery from `Array<Shape>` and a
      concrete color-representation array, with shape-specific lowering for a line, filled rectangle,
      filled circle, and five-point polygon; prove LLVM emission, SDL linking,
      event-driven lifetime, and visible native presentation.
      - [ ] Add runtime closure-backed `Array.map` so the authored page can map
        the shape collection into displayed values instead of using the current
        indexed `while` lowering.
      - [ ] Admit stored `Array<Point>` in ordinary project constructs, then
        replace the five-field native Polygon proof with variable-cardinality
        point and edge relationships.
    - [x] Define source-first `Matrix<Element>`, `MatrixPosition`,
      `RectangleRepresentation`, and `ForEachRepresentation` so lists, tables,
      grids, and kanbans project from one multidimensional model.
      - [x] Display the twelve-color palette in the native example as a 6 by 2
        rectangle matrix using the current explicit SDL adapter.
      - [ ] Materialize ordinary relationship-backed members from `@many`, then
        let the executable backend consume `ForEachRepresentation` instead of
        spelling out twelve adapter cells. Do not add Matrix-specific lowering.
        - The intended generic closure surface currently rejects during
          project top-level capture as `invalidTypedDeclarations`; preserve the
          RangeView design and add its compiler fixture with that implementation
          slice rather than weakening the representation.
      - [ ] Resolve whether the fully generic language zone lets `Matrix` omit
        an explicit `<Element>` binder while still giving its `@many` member a
        stable local compile-time type identity. Keep this in the deferred
        unified generic-parameters review rather than special-casing RangeView.
    - [x] Define the source-first `@shape` contract, `ShapeRepresentation`, and
      a `Triangle` with `@many(3)` points. This describes the intended RangeView
      surface; fixed-cardinality runtime construction is not compiler-backed.
    - [ ] Route fixed-cardinality `@many(3)` through the same general
      relationship-backed member materialization, then replace the temporary
      three-field `NativeTriangle` adapter with semantic `Triangle`.
    - [x] Define semantic `Color` as OKLCH plus alpha, add the magenta, red,
      yellow, green, cyan, and blue hue-cycle presets plus neutral colors, and
      declare source-first `@styleModifier` fill and line transforms.
      - [ ] Give every `@color` representation an explicit RGBA projection and
        make the SDL adapter consume that lowering product while authored
        collections can remain `Array<Color>`.
        - `toRGBA(color: OKLCH)` is source-authored, but the temporary Float
          foreign-conversion declaration is not accepted by the current extern
          macro execution path yet.
      - [ ] Admit reachable aggregate-return member calls, then allow the same
        operation to be spelled `color.toRGBA()` without a framework-specific
        compiler path.
      - [x] Add the six adjacent-pair derivatives: rose, orange, lime, spring
        green, azure, and violet.
      - [x] Keep `Color` as ordinary open data and compose named values as
        homogeneous `Color` enum cases such as `case red: OKLCH(...)`.
      - [x] Add the general `@color` capability marker for concrete
        representations and the composed Color enum; focused ordinary
        compilation accepts `@color` on `RGBA` and `OKLCH`.
      - [ ] Admit homogeneous value enum cases generally, making
        `Color.red` an `@color` value and the enum's ordered case field directly
        mappable without `@iterable` or a separately maintained collection.
        - [x] Capture `case name: expression` through the existing enum-case
          `value: @syntax?` slot and admit cases added by enum extensions.
          - The unpromoted compiler candidate compiles
            `Testing/RangeView/Pass/ColorValues.range` to LLVM with `main`
            returning `42`; the missing-value rejection fixture exits `65` at
            `topLevelCapture`.
        - [ ] Evaluate the captured value and forward its capabilities so a
          composed case is itself usable wherever `@color` is required.
          - Enum macro execution cannot yet project
            `#environment.target.Declaration.cases`; a focused validation
            attempt reaches type derivation failure `211`, so `@color` remains
            the honest capability marker until enum-case graph projection is
            available.
    - [ ] Attach ordered style transforms to shape values and define how fill
      and line composition reaches each rendering backend.
    - [ ] Introduce ordered drawing layers in discrete checkpoints: layer
      identity/composition, a transparent baseline, then blur after offscreen
      render-target semantics are explicit.
    - [ ] Support passing borrowed opaque parameters through Range-authored
      `Void` wrapper functions. The current compiler rejects that wrapper
      boundary during evaluation-temporary expiration at stage `13`, so the
      proven one-window lifecycle calls show, present, and destroy directly.
    - [ ] Let RangeView `@app` own one explicit native-window lifecycle before
      modeling multiple windows. Add a window collection only after each
      window's identity, renderer/resource ownership, event routing, and close
      behavior are explicit.
  - [ ] Pin and resolve wgpu-native, then add the C-layout descriptors,
    callbacks, out parameters, and platform surface bridge required for a
    direct Range-authored wgpu render pass.
    - [x] Pin wgpu-native `v29.0.1.1`; the macOS arm64 release archive is
      `wgpu-macos-aarch64-release.zip` with SHA-256
      `a5797a37b1adf720bcd5dcffb291edbbd5b7b14be0a3874c28e6393a655a7a3e`.
    - [x] Extend contextual `nil` resolution to `@opaque` foreign parameters
      and lower it as LLVM `ptr null`. Prove `wgpuCreateInstance(nil)` and
      `wgpuInstanceRelease(instance:)` before introducing aggregate C ABI.
      - A disposable compiler linked the pinned macOS arm64 dylib, created and
        released a real wgpu instance, queried its version, and exited `42`.
        The accepted bootstrap was not modified.
    - [x] Complete the focused proof for inferred call bindings spelled
      `let instance: wgpuCreateInstance(descriptor: nil)`; do not retain a
      redundant explicit result type or introduce `=` assignment syntax.
      - A final disposable compiler compiled the unchanged inferred opaque-call
        and tracked wgpu-instance fixtures, emitted their exact nullable pointer
        calls, linked both native executables, and observed exit `42`. The
        accepted bootstrap was not promoted; the supported ownership gates
        remain pending until bootstrap/runtime provenance is reconciled.
    - [ ] Add aggregate-by-value and callback ABI support for
      `WGPURequestAdapterCallbackInfo` and the returned `WGPUFuture`; adapter
      acquisition must remain outside the nullable-pointer checkpoint.
- [ ] Complete compiler-owned `@commandGroup` dispatch after the generated-declaration checkpoint.
   - [x] Prove a target-owned generated `Command` enum, generated callable `runCommandLine()` fallback, linked execution, and exact empty-group rejection through `scripts/range check-value-ownership`.
   - [x] Stop RangeView from participating in this compiler checkpoint; RangeView remains idealized example code, not validation input.
   - [ ] Support statement arrays produced by `#commands.map` inside generated function bodies without aborting native compilation, then prove argv key comparison and `self.<command>()` dispatch.
   - [ ] Support fieldless construct values as method receivers so a command group does not need a stored control field solely to make `CLI()` representable.
   - [ ] Replace the focused harness reflection prelude with canonical Core declaration envelopes only after their wider dependencies compile in the supported bundle.

- [x] Add `@test` / `@testGroup` macros (Core/Macro/Test.range) so Range-authored tests can be written using macros; modeled on @commandGroup so tests can live alongside and trigger Range-authored CLI (@commandGroup etc.) constructs.
   - [x] Added marker + group macro, Pass/Smoke and Fail/EmptyTestGroup fixtures under Testing/Test/.
   - [x] Wired validation (generated Test enum + runTests, empty rejection, linked run returning 0) into check-range-value-ownership via inlined decls for snapshot.
   - [ ] Make Test.range part of default core sources for `range run` of authored tests without manual bundle.
   - [ ] Implement real test collection/dispatch (beyond stub return) and `range test` driver entry once CLI is more Range-owned.

## Compiler Observability

- [ ] Grow the local Compiler Scope from a live instrument into a historical
  regression tracker.
  - [x] Stream the supported compiler profiler's process-tree CPU and resident
    memory measurements into a moving localhost graph, compare the heaviest
    neighboring task, and expose an explicit bounded stop operation.
  - [ ] Persist completed run summaries by source revision and machine so the
    dashboard can compare like-for-like compiler trends without presenting
    unlike hosts as a regression.
  - [ ] Add focused compiler-stage presets only when each preset maps to a
    supported proof command and labels the exact boundary it measures.
  - [ ] Consider a native macOS shell after the localhost workflow and stored
    history establish which always-on process metrics are useful.
