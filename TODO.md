# TODO

Priority and dependency order live in [MILESTONES.md](MILESTONES.md). This file
owns the actionable checkboxes for the active and deliberately deferred work.

- [ ] Recognize source shape from Core-authored, queryable syntax rules before
  usage, type, ownership, and representation analysis.
  - [x] Define identifier start and alphanumeric continuation rules beside
    `Identifier` in Core and make Range-authored syntax-template derivation
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
      inputs/before/after values while Core `Identifier` remains semantic
      identity. The paired value token remains identity-scoped and is not a
      cross-identity payload-interning key.
    - [ ] Wire the four reconciliation outcomes (reuse, update, insert, delete)
      only after UUID-backed `Identifier` lookup confirms structural equality;
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
        `environment.diagnostics` when any capture is unknown.
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
  `environment.target.declaration...` to
  `environment.target.Declaration...`; expansion target splices now use
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
    `environment.graph.addNode(role:additionalRole:)` and uses implicit `nil`
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
    - [x] Parse current `{ environment in` macro bodies before applying syntax
      captures, so keyword and string highlighting does not depend on
      Tree-sitter error recovery.

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
      - [x] Standardize executable macro bodies on one authored
        `{ environment in }` binding. `Macro.Environment<Target>` owns the
        target and diagnostics/graph query views; the compiler records one
        capability handle and models each view as an explicit environment
        projection rather than an ordinary local symbol.
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
          execute `environment.target.Declaration.members.count` through lazy,
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
            `environment.graph.addNode(role:additionalRole:)`; then delete
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
        `Identifier` carrying its nominal `name`, stable `id`, direct
        `parent: Identifier?`, and
        a canonical `source: @syntax?` witness; declarations no longer expose
        parallel
        `identity`, `parent`, and `identifier` values.
        - The owning declaration's existing `type` is the named value's
          representation (`state count: Int` means nominal `Count` represented
          by `Int`); the source syntax provides `State`, `Let`, and other
          metadata without duplicating either fact in `Identifier`.
      - [ ] Derive stable `Identifier` hashing through `@hashable` without
        making the hash the semantic identity.
        - [x] Make `@hashable` synthesize a target-owned `hash() -> Int`
          directly from the canonical `id` declaration instead of emitting an
          inert `HashableRegistration` value.
          - `@hashable` discovers `id` through the target's typed
            `Declaration.members` rather than the legacy
            `environment.target.memberCount(name)` shortcut.
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
      - [ ] Materialize every syntax-facing `Identifier` directly from the
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
                  - An anchor is an introducer or literal plus an `Identifier`;
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
      ownership/effect reconstruction only for marked development source sets.
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
        - `per-function-artifacts-v1` requires a bundle on every source-key
          miss; missing or malformed artifact state is a hard failure.
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

## Compiler Simplification Execution Plan

- [ ] Simplify the compiler in dependency order from one reproducible
  checkpoint.
  - `CompilerIntTable` already stores its values in `Buffer<Int>`; do not
    replace dense integer storage merely to rename it.
  - Keep `RawBuffer` as a private Core/runtime allocation substrate until
    authored Buffer and String own allocation, growth, and destruction.
  - Require each deletion or representation slice to remove its superseded
    path in the same checkpoint instead of retaining parallel compiler models.
  - [ ] Phase 0: restore a reproducible current compiler baseline.
    - `scripts/range check-build-plan` passes, but the current accepted-bootstrap
      verifier reports changed compiler inputs across Syntax, Body, Driver,
      and LLVM; the accepted artifact is not proof of the current source tree.
    - [x] Re-run the manifest integrity check and record the exact current
      mismatched input set before changing compiler semantics.
      - The accepted manifest differs from 13 current compiler inputs:
        `CompilerBodyCFG`, `CompilerBodyMIR`, `CompilerBodyModel`,
        `CompilerBodyOwnership`, `CompilerBodyParsing`, `CompilerBodyTypes`,
        `CompilerCore`, `CompilerDirectives`, `CompilerBodyLLVM`,
        `CompilerLLVMPlan`, `CompilerFrontend`, `CompilerParsing`, and
        `Lexer`; all manifested Core and runtime inputs still match.
    - [ ] Resolve the current source capability blocker through the narrowest
      relevant value-ownership proof, including its exact rejection controls.
      - The current development build now treats undeclared built-in target
        category markers as scalar syntax metadata rather than macro-family
        storage, and ownership construction ignores compile-time projection
        values before requiring runtime tracked-storage metadata.
      - The focused value-ownership run passes the uppercase/lowercase inline
        projection pair, typed collection closures, Codable, rollback, and
        typed macro parameter defaults. The unimplemented `@shared`
        macro-on-macro marker was removed from the graph capability fixture
        and Core surface so graph validation can proceed without inventing a
        macro-declaration target model.
      - Graph capabilities and both missing-role controls now pass. value-ownership
        next stops at the existing Range-native project macro boundary with
        `diagnosticKind=macroExecutionBodyInvalid`, `pipelineStatus=1`, and
        `pipelineFailureCode=1`; generated project configuration remains the
        next independent capability slice.
      - Keep the proof boundary explicit: value-ownership and its controls must pass
        before advancing to smoke, candidate reproduction, or accepted-bootstrap
        integrity verification.
    - [x] Run the supported ladder in order: build plan, ordinary value with
      controls, compiler smoke, compiler candidate/reproduction, and accepted
      bootstrap integrity verification.
      - [x] Build plan, complete value-ownership controls, Compiler V1, and
        compiler smoke pass on the current source snapshot.
      - [x] The optimized candidate passes the complete candidate audit and
        reproduction compile/validate/link boundary.
      - [x] Promote the independently verified candidate/reproduction artifact
        and rerun accepted-bootstrap integrity verification.
        - Promotion rebuilt the manifest from the live Core inventory and all
          29 current compiler sources instead of retaining its stale 26-entry
          source list.
        - `scripts/range check-compiler` reproduced LLVM SHA-256
          `90f3adabfc443c33860451a869ce7302bdcc17449bee0ce046f810a3b8423882`
          at 8,536,584 bytes and executable SHA-256
          `e7bfc578bcf5f2fd1b4faf4a7b0e8450d51776f2ac8e43dea80c455f5be3b6a1`
          at 3,522,096 bytes in 818.31 seconds without Swift.
        - The post-promotion candidate completed in 866 seconds: 23 seconds
          bootstrap linking, 819 seconds Range LLVM emission, 2 seconds
          validation, and 22 seconds linking. Its candidate and reproduction
          LLVM were byte-identical to the accepted bootstrap; its two executables
          were byte-identical at SHA-256
          `12252dcd0c72aed205657df039841f75c4d1dc8b4a9b992365ae229b470162cf`.
      - [x] Remove `scripts/range compiler progression` from the required
        promotion ladder. Keep it only as an optional convergence diagnostic;
        candidate/reproduction equality is the complete fixed-point proof.
    - [x] Confirm fixed-point LLVM and executable identity and promote the
      complete 29-source inventory only after explicit approval.
  - [ ] Phase 1: delete the obsolete string-record compiler path.
    - [ ] Audit every supported command, proof script, and compiler directive
      for consumers of the legacy `CompilerProgram` record fields and the
      summary/legacy LLVM entry points.
    - [ ] Classify the current static deletion candidates, including
      `compilerCoreASTSummary`, the symbol/type/declaration summaries,
      `compilerCoreLLVM`, `parseCompilerProgramForLLVMNamedBodies`,
      `parseCompilerStatementLegacy`, and the old TypedIR LLVM helper.
      - [x] Delete the four independently unreachable leaf entry points
        `compilerCoreASTSummary`, `compilerCoreLLVM`,
        `parseCompilerProgramForLLVMNamedBodies`, and
        `parseCompilerStatementLegacy` after a repository-wide reference audit
        found no callers.
        - The slice removed 172 Range lines and no direct RawBuffer calls.
          Native compiler smoke rebuilt in 672 seconds (668 emission, 2 LLVM
          validation, 2 linking), and the linked candidate executable remained
          byte-identical at SHA-256
          `1ebc06443ced5d0349ee76a2e4210fc5d7f6f243bd005c49101ad91fee77e427`.
    - [ ] Remove only a complete unreachable chain: its record
      encoders/decoders, parser/lowering functions, fields, column helpers,
      and RawBuffer builders must leave together.
    - [ ] Prove supported CLI behavior and compiler fixtures are unchanged,
      record the compiler line-count and direct RawBuffer-call reduction, and
      reproduce the fixed point.
  - [ ] Phase 2: complete deterministic automatic String destruction.
    - [ ] Complete the automatic-destruction slice under Compiler Storage for
      normal fallthrough, early returns, branches, loops, moves, and aliases.
    - [ ] Keep explicit destroy as an internal ownership effect while removing
      it from ordinary authored String code.
    - [ ] Do not migrate shared compiler text across function boundaries until
      the ownership proofs and fixed point pass.
  - [ ] Phase 3: remove direct RawBuffer use from the surviving compiler.
    - [ ] Migrate function-local text builders to mutable authored String
      storage first and guard compile time and peak memory against the rejected
      immutable-concatenation regression.
    - [ ] Migrate the shared LLVM block, function, global, and artifact-text
      accumulators after cross-function String ownership is proven.
    - [ ] Delete each compiler-facing raw text operation after its last
      accepted caller disappears; retain the lower-level runtime primitive
      while Buffer or String still lowers through it.
  - [ ] Phase 4: collapse the parallel semantic/representation pipeline.
    - [ ] Identify the exact macro-family representation and member-layout
      facts still consumed from `CompilerMemoryGraph`.
    - [ ] Move member-representation proof onto the same BodyArena/type-layout
      decision used by ordinary native compilation.
    - [ ] Extract the smallest retained macro-family representation component,
      then delete the unconsumed general SemanticGraph, MemoryGraph, and
      TypedIR directive chain.
    - [ ] Preserve focused macro-family, inline/identity/transparent storage,
      native compilation, and fixed-point proofs.
  - [ ] Phase 5: replace anonymous IntTable programming with typed stores.
    - [ ] Complete the generated-member delta store cutover.
      - [x] Make macro expansion construct a named
        `CompilerGeneratedMemberDelta`, and make validation, collision checks,
        commit, and diagnostics consume its named fields.
      - [ ] Replace the private 24-column backing table and pending-table copy
        with a typed delta store and an explicit resolved-member product.
        - The development candidate compiler accepted the 18-field scalar delta
          aggregate; canonical-target and project macro fixtures committed one
          and two generated members respectively through that boundary.
      - [ ] Record delta provenance and observations as typed identities rather
        than integer rows before making generated-member products reusable
        across compiler runs.
    - [ ] Pilot declarations, members, functions, parameters, and type
      references behind named store operations while retaining private
      `Buffer<Int>` row-major or structure-of-arrays storage.
    - [ ] Fold parallel fields such as function ownership into their domain
      store when doing so removes an independently maintained invariant.
    - [ ] Delete the corresponding public column constants, partial-row
      appends, and direct `compilerIntTableValue` calls in the same slice.
    - [ ] Keep `syntaxIndex` as a typed derived index rather than replacing
      constant-time lookup with scans.
    - [ ] Apply the proven store pattern in order to Body syntax and types,
      CFG, ownership, MIR, reachability/ABI/LLVM, and finally macro/Graph
      stores.
  - [ ] Phase 6: measure and reduce derived compiler state.
    - [ ] Mark each schedule, parent map, selection map, and expression-value
      map with its producer, last consumer, and reconstruction cost.
    - [ ] Release or rebuild phase-local derived state after its last consumer
      instead of retaining it for the complete compile.
    - [ ] Decide whether Graph 0 regions, dependencies, and frontiers remain on
      the ordinary compile path only after measuring their time/RSS cost and
      identifying a real scheduler consumer.
    - [ ] Do not delete canonical syntax, resolution, type, CFG, ownership,
      MIR, reachability, or macro-result facts merely because they use dense
      integer storage.

## Compiler Storage

- [ ] Implement the persistent graph revision model described in
  [DeltaDBSpacetimeDBRangeHandoff.md](Development/DeltaDBSpacetimeDBRangeHandoff.md).
  - Keep stable node identities and typed edge deltas as one logical graph,
    with cardinality-specialized physical indexes.
  - Commit each compiler view atomically; preserve the last accepted revision
    on a failed candidate and measure load, delta-apply, query, and
    invalidation-frontier costs before promoting a new authority.
  - [x] Persist a Range-shaped revision artifact as the accepted graph authority.
    - `range compile-graph` now writes revision schema v4: deterministic
      revision identity over parent + File fingerprint + Source provenance + node values + status,
      a 5-node index (source/syntax/shape/behavior/compile with
      before/after/changed value fingerprints), the 4 cardinality-one pipeline
      edges (add/replace operations), and 5 view digests.
    - A failed candidate never writes a revision; the last accepted revision
      is preserved. Unchanged input reuses the artifact without rewriting it.
    - `scripts/range check-compiler-graph-revision` proves cold insertion,
      same-location determinism, warm reuse, parent chaining (updated
      node.before equals the prior accepted node.after), bounded literal-edit
      invalidation with measured affected-view counts, failed-candidate
      last-known-good preservation, and recovery.
    - The accepted File and phase fingerprints live in `revision.tsv`.
      `execution.tsv` is synthesized only as a temporary `resume-v1` command
      input and is never persisted in a graph cache. Existing v2 caches consume
      and remove their legacy execution record after one successful migration.
    - The V1 File identity derives from the source bundle path, so the
      revision is deterministic per location; content-addressed node
      identity is the next Range-owned cutover.
  - [x] Shape consumes the persisted Source artifact and reports per-stage
    load, delta-apply, query, and materialization costs.
    - The graph and Shape lines consume the persisted bundle only when the
      Source provenance in `revision.tsv` matches its profile, canonical input,
      compiler, and actual bundle digest. `source.tsv` is no longer written or
      read; successful migration removes a legacy copy if present.
    - A warm reuse rewrites neither the revision nor the bundle (verified by
      inode). A failed candidate preserves both accepted artifacts.
    - Each graph run reports `rangeGraphMetrics`: `sourceMs`/`syntaxMs`/`loadMs`/
      `reducerMs`/`queryMs`/`materializeMs` wall costs, `viewsAffected`,
      `sourceArtifact`/`syntaxArtifact`, and per-phase `consumed`/`derived` flags. A phase
      whose before/after values are equal consumed the persisted revision; a
      phase that commits a new value derived its product.
    - On a literal edit the report shows `source=derived`, `syntax=consumed`,
      `shape=consumed`, `behavior=derived`, `compile=derived`, and
      `viewsAffected=3`: the syntax and Shape stages leave the prior accepted
      values untouched and emit no delta, so
      the shape value is a projection of persisted syntax facts rather than a
      fresh Source capture.
    - `syntax-facts.tsv` persists the validated typed Shape snapshot plus its
      syntax and Shape fingerprints; Source provenance remains in revision v4.
      The proof makes Source unavailable,
      runs `project-shape-v1` using only those facts, and obtains the exact
      `compile-shape` bytes and revision Shape value with no Behavior or LLVM.
      `resume-v1-facts` also requires a transient Source-to-syntax binding, so
      stale facts from another generation at the same path fail closed.
    - `compilerV1Shape` now only projects persisted facts. Behavior retains a
      transitional Source recapture for the complete pre-link macro/lowering
      tables; serializing and loading those tables is the next storage cutover.
  - [x] Add the Shape-only reducer as its own compiler command.
    - `compilerV1ShapeOnly` captures the typed declarations and main root,
      renders only the shape snapshot, and stops; `range compile-shape`
      consumes a Source artifact and emits only the shape delta. No macro
      link, no LLVM emission, no behavior product.
    - Because the capture sequence and render point match `compilerV1Shape`
      exactly, the reducer's `after` fingerprint and snapshot are
      byte-identical to the shape value the full V1 pipeline persists: the
      proof asserts the emitted `after` equals the revision shape node and the
      payload equals the `inspect-v1` shape region, with no LLVM or downstream
      phase deltas.
    - The graph line now persists the equivalent payload in
      `syntax-facts.tsv`; `project-shape-v1` owns the facts-only projection.

- [x] Add the first Range-authored compiler-description values.
  - Core now defines `PhaseRegistration` and `CompilerRegistration` as
    ordinary typed macro results. `@phase` returns its function target without
    emitting syntax, while `@compiler` collects the construct's ordered
    `Array<@phase>` and rejects a compiler with no phases.
  - The focused proof registers `shape` and `usage` in source order, excludes
    an unannotated helper, observes both phase result values, and checks the
    exact missing-phase diagnostic.
  - [ ] Add explicit phase dependencies and derive a schedule as another
    graph value; do not hardcode the five illustrative compiler phases.
  - [ ] Let a compiler registration select its source/project inputs and
    invoke the described pipeline before synthesizing command-line behavior.
  - [ ] Route scheduled graph domains into typed dense storage partitions
    only after profiling identifies their producers, consumers, and costs;
    dense buffers remain physical storage, not the semantic compiler model.
  - [x] Carry the description through one executable Compiler V1 slice.
    - `@main` now exposes `compile-v1` and `inspect-v1`. The V1 runner loads an
      explicit input file as a stable `Identity : FileValue` source Delta,
      produces inspectable Source, Shape, Behavior, and Compiled Deltas through
      named phase functions, then delegates LLVM emission to the current native
      compiler path.
    - `scripts/range check-compiler-v1` proves the V1 plot artifact is
      byte-identical to the legacy output for an ordinary Range program,
      validates and links that LLVM, executes it with exit `7`, inspects the
      shape/behavior/plot artifacts, and checks the typed missing-input error.
    - [x] Expose the persistent graph line as an opt-in compiler command.
      - `range compile-graph <FILE-OR-DIR>` resolves the current Range-authored build
        producer and runs its `compile-v1` File -> Source -> Syntax -> Shape -> Behavior ->
        Compiled pipeline; ordinary `range compile` remains the accepted
        bootstrap oracle while the cutover is compared. The durable cache
        boundary implemented today reaches persisted Syntax and facts-only Shape.
      - `scripts/range check-compiler-graph` proves direct legacy LLVM parity,
        project source-set parity, Source/Shape/Behavior/Compiled inspection,
        cold insertion, unchanged reuse, and edited replacement in 7 seconds
        without rebuilding LLVM.
      - Graph project bundles carry the explicit `// range-development-compiler`
        marker already used by the V1 generation proof. This is a Source
        artifact consumed by later Shape derivation; it does not yet make graph
        compilation the default or remove the bootstrap oracle.
      - [x] Give the graph source-set a stable File identity and persistent
        File -> Source artifact.
        - `scripts/compile-range-project --graph` stores the canonical source-set
          bundle, accepted revision, and compiled artifact under an ignored
          Source cache keyed by the project path. It derives transient
          `resume-v1` input from the revision. The bundle also carries the graph
          compiler hash, so a producer change invalidates the value.
        - Cold, warm, edited, failed-candidate, and recovery paths are covered
          by `scripts/range check-compiler-graph`; a failed candidate restores
          the previous accepted bundle before returning its typed error.
      - [ ] Derive and persist canonical Shape as a separate graph artifact.
        Shape begins after Source: Core `@syntax` and syntax-template rules must
        derive the typed declaration, member, relationship, and cardinality
        facts from the Source artifact. The current `resume-v1` record contains
        only phase fingerprints for inspection; its Shape fingerprint is not a
        durable Shape authority, and lowering still uses V1's in-process tables.
        Add an independent Shape validation/proof before routing later phases
        through it.
        - [x] Persist the first graph-level V1 syntax-fact artifact and make
          Shape a pure projection over it. Revision v4 owns its digest and
          value; warm reuse preserves its inode, literal edits preserve its
          value when structure is unchanged, failed candidates preserve its
          accepted bytes, and `project-shape-v1` reproduces Shape with Source
          unavailable.
        - [ ] Extend the artifact from the complete typed Shape snapshot to all
          reloadable pre-link syntax tables so Behavior no longer recaptures
          Source before macro linking and lowering.
        - [x] Persist the first source-local syntax Shape artifact through
          `range shape <FILE-OR-DIR>`. The versioned artifact contains the
          Core-authored `@syntax` recipe order, literals, typed captures, and
          one/many/zero-or-one cardinality, with no Behavior or LLVM rows.
          `scripts/range check-shape` proves cold insertion, warm reuse, an
          edited literal, invalid-candidate isolation, and recovery.
          - [x] Make Shape consume the persisted File -> Source bundle when
            its input/compiler provenance matches, and promote a changed
            Source bundle only after Shape succeeds. The focused proof now
            inspects the Source bundle and its source-set hash in the Shape
            artifact, so Shape no longer rebuilds an accepted Source value on
            every invocation.
        - [ ] Extend Shape input from the source-local proof to the complete
          Core/project Source artifact after the accepted Core syntax package
          has a complete recipe-finalization boundary. The current accepted
          Core manifest is intentionally not forced through that finalizer by
          the first Shape command.
    - [ ] Separate compilation from building as explicit products and phases.
      - Compilation consumes source, Shape, and Behavior and ends at a typed
        compiled-program artifact containing target-independent meaning plus
        target LLVM emission. It does not validate, link, or execute.
      - Building consumes compiled artifacts, the selected target, runtime and
        dependency inputs, and a `LinkPlan`; it validates and links an
        executable artifact. Execution remains a separate run operation.
      - Rename the current V1 Plot result to the compiled artifact, introduce
        a build artifact around the existing authored `LinkPlan`, and update
        `scripts/check-range-compiler-v1` to assert compile, build, and run as
        distinct boundaries without changing their verified byte output.
    - [x] Prove the first input boundary as an ordinary Range function returning a
      source Delta.
      - `compilerV1Load(input:) -> CompilerV1SourceDelta` now owns the explicit
        file read. The Delta pairs one path-derived canonical
        `CompilerFingerprint` with one `FileValue(path:source:)`; the duplicate
        V1 identity type and copied hash implementation have been removed.
      - [x] Separate stable phase identity from changing phase value identity.
        - Source, Shape, Behavior, and Compiled Deltas retain a stable identity
          derived from their owning File and phase, carry explicit `before` and
          `after` value fingerprints, and connect each phase input to the prior
          phase's `after` fingerprint.
        - Changing File contents preserves the File identity while changing its
          value fingerprint. Shape and later phases are now capable of update
          semantics instead of treating each changed value as a new graph node.
        - The development candidate rebuilt all 2,952 function artifacts and
          passed the complete value-ownership gate in 654 seconds: 651 seconds
          Range LLVM emission, 2 seconds validation, and 1 second linking.
          `scripts/check-range-compiler-v1` then passed stable phase identities,
          exact Source -> Shape -> Behavior -> Compiled value-fingerprint
          chaining, legacy LLVM byte parity, validation, linking, execution
          with exit `7`, and the typed missing-input error.
      - [x] Load each prior value fingerprint from persistent execution state so
        an update carries its real `before` value instead of the cold-start
        `0:0` absence marker.
        - `resume-v1 <execution.tsv> <input.range> <output.ll>` stores the File,
          Source, Shape, Behavior, and Compiled fingerprints in one Range-owned
          versioned record. A cold execution inserts every value; an unchanged
          execution verifies both the current source and cached LLVM fingerprints
          without rewriting either file; an edited execution loads the exact
          prior phase values before replacing them.
        - State for another File identity rejects. Malformed state is an invalid
          cache value: it is rebuilt and replaced rather than becoming a program
          error. Output and state writes are independently atomic; add a shared
          transaction boundary before treating the pair as one durable commit.
        - [x] Preserve the last-known-good execution across a failed candidate.
          - The focused V1 gate inserts a valid generation, attempts an edited
            source that fails with a typed compiler error, proves both the
            accepted execution record and LLVM artifact remain byte-unchanged,
            then advances them with the next valid source generation.
        - The complete value-ownership gate passed after rebuilding 2,967
          function artifacts in 667.06 seconds: LLVM emission consumed 652
          seconds, validation 1 second, and linking 2 seconds. The focused V1
          gate then passed in 4.46 seconds, including cold insertion, unchanged
          no-rewrite reuse, exact prior-value update, File-identity rejection,
          malformed-cache repair, LLVM validation/linking, and exits `7`/`8`.
        - The current command reads the one state record repeatedly through
          scalar helpers because aggregate ownership joins remain unsupported.
          Replace that workaround with one loaded persistent project graph after
          the ownership boundary can carry the decoded aggregate safely.
      - The existing `CompilerMemoryGraph.runtimeValues` rows are specialized
        for macro-family applications and are found by table scans. Do not call
        this source Delta a MemoryGraph insertion or random-access value until
        the identity/value storage boundary is generalized without a File-name
        special case or a second graph.
      - Prove the source Delta inspection, legacy LLVM byte parity, linked
        execution, and missing-input error through `scripts/check-range-compiler-v1`.
      - The focused V1 gate passed after a development candidate cache miss:
        LLVM emission took 711 seconds, validation 1 second, and linking 2
        seconds; 12 function artifacts were reused and 2,913 rebuilt. The V1
        LLVM was byte-identical to the legacy path, linked, and ran with exit
        `7`; changing only File contents preserved its path-derived identity.
    - [ ] Generalize the existing MemoryGraph identity/value storage boundary.
      - Remove macro-application rows and syntax IDs from the minimum runtime
        value identity contract, then layer macro-family provenance on top.
      - Add identity lookup and replacement without introducing another graph,
        copied fingerprint implementation, or File-named compiler special case.
    - [ ] Replace the handwritten V1 command branch only after the direct
      loader function is green.
      - The candidate surface is `@commands(.global)`: on a function it
        registers that function; on a construct it collects eligible member
        functions. Keep this as a graph-registration design choice until one
        target shape and generated argv dispatch have focused proofs.
    - The verified follow-up compiler build emitted in 663 seconds, reused
      1,617 function artifacts, rebuilt 1,306, validated in 1 second, linked
      in 2 seconds, and completed in 666 seconds. Reuse is still too late to
      avoid semantic reconstruction.
    - [ ] Make `@compiler` and `@phase(after:)` registrations drive the V1
      runner instead of retaining a manually ordered entry adapter.
    - [ ] Ratchet Compiler V1 into authority one artifact domain at a time.
      - Keep the current compiler as the accepted oracle while a V1 phase runs
        in comparison mode over the same input identity.
      - Promote a V1 phase only after its accepted and failed-candidate paths
        are durable; then delete the superseded legacy producer in that same
        checkpoint instead of retaining two semantic authorities.
      - A failed candidate records diagnostics without replacing the accepted
        graph. A valid candidate commits one new generation atomically and
        becomes the input identity for the next phase.
      - [x] Prove a complete V1 compiler generation reaches its own fixed point.
        - `scripts/range check-compiler-v1-generation` materializes the
          canonical compiler source bundle, has the current V1 producer emit
          and link Compiler V2, requires byte-identical V1/V2 LLVM and
          executables, and runs the ordinary exit-7 fixture through both
          generations. Because V1 was built from the same canonical source,
          reproducing itself is the fixed-point check; a redundant V3 would
          repeat the same cold proof. The expensive result is
          content-addressed so an unchanged proof can be reused.
        - The first full-bundle attempt exposed V1 Shape eagerly capturing
          every function body and aborting inside statement parsing before
          LLVM emission. V1 now follows the normal retained-graph boundary:
          capture declarations and main once, then let reachable lowering
          discover bodies from that same table instead of forcing all bodies
          into Shape.
        - Declaration-first capture completed reachable LLVM lowering, but V1
          then rejected the product because its separate whole-program
          `CompilerSemanticGraph` cannot represent the compiler. That legacy
          graph is no longer V1 Behavior authority: successful reachable
          lowering produces a stable Behavior-product fingerprint, including
          body-only changes, while failed lowering remains a typed error. The
          fingerprint is transitional until the persisted per-function
          Behavior graph becomes the directly retained product.
        - The next cold V1 self-emission completed in 2,580 seconds and
          reproduced byte-identical V2 LLVM. Its first gate revision then
          rejected executable bytes because it linked under the basename
          `CompilerV2`; the repository links as `RangeCompiler.tmp` and moves
          that file, and Mach-O UUID/ad-hoc signing includes that identifier.
          The corrected gate reproduces the repository link contract and may
          consume the validated development function-artifact graph; the cold
          LLVM identity result is not discarded or mislabeled as a cache hit.
        - The corrected proof passed: V1 emitted V2 in 2,116 seconds, and both
          LLVM artifacts were byte-identical at 8,630,963 bytes with SHA-256
          `872d36b31f76bb7ba0d8a64ce6b1e9f0a1631f5ea9e5d217549bd0e7ba984ab4`.
          The linked V1/V2 executables were byte-identical at SHA-256
          `5fbb05e0084d0ed2c1950c6ab180598a176b6bb4c9df460df23e330cc225a8ca`,
          and each compiled, linked, and ran the ordinary fixture with exit 7.
          The function-artifact input reduced the repeat from the observed
          2,580-second cold emission to 2,116 seconds, but did not provide a
          closed-module short circuit; most reconstruction still ran.
        - [ ] Move the validated module cache ahead of reachable-body discovery.
          - [x] Version 8 records a canonical source identity (ignoring only
            input/output cache-directive paths), root Behavior integrity, and
            the complete persisted artifact-record/text integrity. An exact
            module match returns before reachable-body discovery; malformed,
            stale-root, stale-callee, and source-mismatched caches fall back to
            the existing checked path.
            - The focused Compiler V1 gate passed in 51.62 seconds and proved
              cold insertion, closed-module reuse without discovery/candidate/
              effects/ABI/emission phases, root and callee tamper rejection,
              malformed-cache repair, and legacy LLVM/runtime parity.
            - The native current cold build emitted LLVM in 656 seconds and
              completed in 659 seconds (`2,981` artifacts rebuilt). The
              unchanged warm invocation was a cache hit in 3.94 seconds with
              identical LLVM hash `2c2783799b1524d7d9423a2a9caac430eb9a168878d2307ad018cf365174603e`
              and executable hash
              `929a33f21ec6c05595c366300b53854dafc20020dd743f34792bddb66e60b424`.
          - [ ] Run the full candidate/progression ladder before promoting the
            new cache schema or bootstrap.
          - The first post-edit native smoke probe reached the normal LLVM
            producer at roughly 10.7 GB resident memory after 3:37 and was
            stopped before completion; the completed v8 run stayed within the
            observed safe resource envelope.
    - [x] Replace the three independent source rebuilds with one persistent
      project graph whose shape and behavior deltas flow between phases.
      - [x] Make V1 Shape own one typed-syntax capture and derive both the
        inspectable Shape snapshot and Behavior snapshot from its live tables.
        - `compilerV1Behavior` no longer accepts source or invokes an
          independent semantic summary; it consumes only the frozen
          Shape-owned Behavior snapshot. The focused V1 gate enforces this
          source boundary, preserves legacy LLVM parity and failed-candidate
          isolation, and validates, links, and runs exits 7/8.
        - Native smoke rebuilt the changed compiler in 663 seconds: 659
          seconds emitting LLVM, 2 seconds validating, and 2 seconds linking.
      - [x] Make the Compiled phase consume retained Shape and Behavior
        products directly.
        - Shape now invokes the linked-table native LLVM boundary while its
          single captured syntax graph is alive and freezes that output beside
          its Shape and Behavior snapshots. Compiled accepts no source value
          and only commits the retained output after verifying that Behavior
          consumes the exact Shape generation.
        - Raw source remains the backing storage for body spans during this
          lowering; declarations and syntax are not captured a second time.
          Persistence across process runs still stores fingerprints and LLVM,
          not the live typed graph, so changed input performs one complete
          capture on its next execution.
        - The focused V1 gate preserves legacy LLVM parity, failed-candidate
          isolation, exact prior phase values, malformed-cache repair, and
          linked exits `7`/`8`. Producing the changed development compiler
          still took 830 seconds: 827 seconds emitting LLVM, 1 second
          validating it, and 2 seconds linking, with 0 of 2,977 function
          artifacts reused. The retained phase cutover removes duplicated V1
          capture but does not yet solve whole-compiler reconstruction.
    - [ ] Delete ABI and effect-summary phases from Compiler V1.
      - Shape owns physical value representation and carried identity.
        Behavior is the composable graph mapping from input shapes to output
        shapes plus capability edges such as read, write, move, destroy, and
        platform access; it is not a separately reconstructed effect table.
      - Compose behavior along call/relationship edges and invalidate it from
        observed identity changes. Select the target calling convention once
        during plotting from the frozen boundary shape.
      - Keep the current compiler's ABI/effect machinery only as the parity
        oracle until V1 shape/behavior plotting passes the same focused native
        controls; then delete the superseded reconstruction path.
      - [x] Remove disposable LLVM emission from the ABI capability probe.
        - The probe now stops after its graph-producing work and MIR
          validation. Authoritative entry/helper lowering owns the only two
          remaining `compilerBodyLLVMEmit` call sites; the focused V1 gate
          rejects any return of the `abi.emit` probe.
        - Removing the dead source reduced the immediately adjacent bootstrap-
          producer miss from 827 seconds to 668 seconds, with validation and
          linking taking 2 seconds each. That measures the accepted producer
          compiling a smaller next compiler; it is not the new compiler's own
          runtime improvement.
        - At this intermediate checkpoint the persisted V1 execution suite
          passed, and the dedicated mixed aggregate-return fixture still
          rejected before LLVM output with
          `representationSensitiveABICapabilityBlocked` at capability stage
          `52001`; the subsequent Shape-authority cut below moves that body
          failure out of ABI planning.
      - [x] Make captured function discovery the ABI capability authority and
        remove ABI component planning's second body reconstruction.
        - Discovery publishes capability only after the function's captured
          body, signature, call edges, CFG, owned paths, direct Behavior, and
          representation-sensitive targets are valid. ABI component planning
          consumes that Shape result instead of reparsing and rebuilding
          ownership/MIR merely to decide participation.
        - A full cold profile executed by the newly built compiler completed
          the current compiler source set successfully in 496,221 ms and
          emitted 8,630,832 LLVM bytes. Every `abi.parse`, `abi.resolve`,
          `abi.cfg`, `abi.ownership`, `abi.mir`, `abi.validate`, `abi.emit`, and
          `abi.cleanup` counter was exactly zero.
        - The profile used 11,680,858,112 maximum resident bytes and reported a
          15,090,461,784-byte peak footprint. The newly exposed dominant work
          is function-effect construction at 140,391 ms followed by roughly
          317 seconds between the frozen ABI plan and completed function
          emission/module assembly. The largest observed function totals were
          49,317 ms in `compilerBodyLLVMEmitterProcessOperation` and 38,951 ms
          in `compilerBodyMIRValidationCode`.
        - Invalid aggregate-return bodies now remain out of ABI shape planning
          and reject at authoritative typed-body lowering with
          `unsupportedReachableLowering`, `function=brokenPair`, and
          `typedBodyPipelineFailure stage=52001`, before any LLVM definition or
          call is returned.
      - [x] Make V1 Plot accept the frozen Shape and Behavior artifacts,
        reject a mismatched Shape-to-Behavior identity chain, and expose the
        Behavior identity consumed by Plot for inspection and future cache
        lookup.
      - [x] Persist the closed Behavior mapping with each function artifact.
        - Artifact schema version 2 records the pre-lowering function-instance
          and body identity as Behavior input, then closes its output over the
          proven ABI identity, effect dependencies, and observed call edges.
          Cache reuse requires both ends of that mapping to match; superseded
          artifact schemas are ignored safely and rebuilt.
      - [x] Move candidate lookup ahead of ownership/ABI reconstruction.
        - After reachability discovery freezes function-instance signatures
          and observed call edges, each work item records a candidate only when
          its cached Behavior input and edge fingerprint match. Final reuse
          still requires the same row's closed output, ABI, and effect proofs.
      - [x] Close the reachable candidate graph over instance-level dependency
        outputs.
        - Artifact schema version 3 fingerprints each function Behavior output
          together with the exact specialized instances it calls and their
          outputs. Closure is checked and timed before effect reconstruction;
          late reuse must reproduce the same closure from current proofs.
      - [x] Collect the unique `@main` root from captured syntax before
        evaluating its Behavior.
        - Later entry consumers now follow the captured
          `mainAnnotation -> appliesTo -> entry` graph instead of reparsing
          source text to rediscover main.
      - [x] Make main the first ordinary Behavior root: let its evaluation own
        body verification and callee discovery, persist its input/output, and
        include its reachable function outputs in graph closure.
        - Function artifact schema v4 stores a root Behavior record before the
          per-function records. A cached graph is closed only when the captured
          main body, its discovered instance edges, every function candidate,
          and the root closure over those function outputs all match.
      - [x] Bypass ownership/effect/ABI reconstruction when the complete main-
        rooted Behavior graph matches, while retaining exact rejection proofs
        for a changed main body, changed root edge, and changed callee output.
        - Artifact schema version 5 stores the complete emitted module after
          the root Behavior record. A closed hit returns it before
          ownership/effect/ABI reconstruction and does not rewrite the output
          artifact; mismatched main input, root output, or callee output each
          fail closed and rebuild.
        - Ordinary and native source-set compilation now capture an `@main`
          root shell into the shared syntax graph immediately after declaration
          capture; the later entry path no longer reparses source to rediscover
          it. Executable statements still use the current BodyArena parser.
        - `scripts/check-range-compiler-v1` passes legacy/V1 LLVM byte parity,
          validate/link/run exit `7`, the closed-module hit, all three cache
          rejection controls, inspectable Shape/Behavior/Plot artifacts, and
          the typed missing-input error.
        - The final compiler miss reused 2,947 of 2,948 function artifacts but
          still spent 350 seconds emitting LLVM, 2 seconds validating, and 2
          seconds linking. The next performance slice must skip module-wide
          reconstruction across compiler-source cache keys, not merely raise
          the late function-reuse count.
        - [ ] Re-prove a warm artifact hit on the complete compiler source set
          after the module-wide producer is separated from the development
          path. A direct `range-function-artifact-input` experiment was
          bounded at 1,373.49 seconds in `compilerBodyLLVMEmit`, emitted zero
          LLVM bytes, and wrote no artifact before interruption; the supported
          V1 gate's small closed-Behavior fixture remains the valid cache-hit
          proof.
          - `scripts/range compiler profile` now always requests an artifact
            output and can persist it with `RANGE_COMPILER_PROFILE_ARTIFACT_OUTPUT`.
            Its next run can consume that exact file through
            `RANGE_COMPILER_PROFILE_ARTIFACT_INPUT`; a successful closed hit is
            reported as `compilerArtifact status=reused` and retains the full
            authored phase/function trace for comparison.
          - `scripts/check-range-compiler-v1` proves the profiler path with a
            cold artifact write followed by a warm artifact reuse. The cold
            trace reaches effects, ABI components, and function emission; the
            closed warm trace reaches artifact candidates but contains none of
            those three stages. The focused proof completed in 52.09 seconds.
          - A live complete-source profile was bounded after 16:28 at roughly
            9 GB RSS, before it could write its cold artifact. Its trace reached
            repeated ABI ownership/MIR work and
            `compilerBodyLLVMEmitterProcessOperation`; retain frozen typed body
            and ABI products before attempting another full cold-to-warm run.
        - A subsequent one-function parser change reused 2,948 of 2,949
          artifacts and still spent 350 seconds emitting LLVM, versus 1 second
          validating and 2 seconds linking. This independently reproduces the
          same late-reuse bottleneck.
      - [x] Retire the candidate harness's obsolete
        `environment.target.memberCount(...)` oracle.
        - The self-compiled compiler rejects that removed magic API during
          macro body resolution before recording a graph dependency. The
          candidate now preserves that deterministic negative boundary; typed
          member discovery is authored as
          `environment.target.Declaration.members.filter(all: ...)`.
        - The Project defaults macro and its focused fixtures now use typed
          `State` filtering plus authored String equality. Exact read-
          dependency recording for structural syntax collection remains a
          separate graph-observation slice; the current collection evaluator
          reports no legacy string-key graph reads.
        - [ ] Give an unresolved call to removed String magic such as
          `stringLength` or `stringByteAt` a named unregistered-capability
          diagnostic. It currently rejects deterministically during entry
          resolution as `invalidEntryReachability`, stage `2`; do not restore
          either name as a compiler builtin merely to improve that message.
      - [x] Keep generated declarations distinct from a standalone emitted
        value inside `#environment`.
        - Only the first expansion token may select the direct `Value(...)`
          form. After `function`, `construct`, an attribute, or another syntax
          token, a later `identifier(` is ordinary generated syntax rather than
          a second attempt to parse the whole expansion as one expression.
        - The focused generated-function suite now passes snapshot stability,
          native LLVM validation/link/run, target-owned member placement, and
          its collision/malformed-splice rejection controls.
    - [ ] Support moving an owned construct extracted from a success enum
      payload into the next function. The first direct `Result`-shaped V1
      runner rejected at `compilerV1Run` with
      `invalidFunctionReachability`, `detail=811`; the vertical adapter keeps
      nominal artifacts and converts legacy string diagnostics into
      `CompilerV1Error` until that general ownership boundary is proven.
    - [ ] Locate the nearest `Project.range`, gather its complete source set,
      and represent project/file locations as graph values rather than
      limiting V1 to one explicit input file.

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
- [ ] Complete compiler-owned `@commandGroup` dispatch after the generated-declaration checkpoint.
  - [x] Prove a target-owned generated `Command` enum, generated callable `runCommandLine()` fallback, linked execution, and exact empty-group rejection through `scripts/range check-value-ownership`.
  - [x] Stop RangeView from participating in this compiler checkpoint; RangeView remains idealized example code, not validation input.
  - [ ] Support statement arrays produced by `#commands.map` inside generated function bodies without aborting native compilation, then prove argv key comparison and `self.<command>()` dispatch.
  - [ ] Support fieldless construct values as method receivers so a command group does not need a stored control field solely to make `CLI()` representable.
  - [ ] Replace the focused harness reflection prelude with canonical Core declaration envelopes only after their wider dependencies compile in the supported bundle.

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
