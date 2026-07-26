# TODO

Priority and dependency order live in [MILESTONES.md](MILESTONES.md). This file
owns the actionable checkboxes for the active and deliberately deferred work.

## Website

- [x] Position the homepage 0-to-1 measure on a zero-safe logarithmic scale.
  - [x] Use those non-linear positions for canvas marks and verify the rendered
    endpoint alignment.
  - [x] Replace the detached pointer pinch with direct dragging of the authored
    `0` endpoint.
    - [x] Pull nearby marks by logical value with a compact falloff, keep every
      dash the same length, and spring the zero endpoint home on release.
- [x] Add an interactive concentric nucleus graph to the Svelte homepage.
  - [x] Render one shared source nucleus with persistent concept branches.
  - [x] Add an explicit `Shape(1, 2, 4)` branch and expand the radial
    canvas to use the available content width.
  - [x] Verify Svelte diagnostics, production build, server rendering, and
    concept-picker interaction.
  - [x] Play one short low sine note every `1.8s + (1.8s / 3)`, or 2.4
    seconds.
    - [x] Advance Shape → Ownership → Capability on the same boundary that
      triggers each note.
    - [x] Leave silence between the short note and the next interval.
    - [x] Keep one fixed A2 note in an audible low register with enough gain
      for laptop speakers, independent of the active concept.
    - [x] Send the note through a strong five-second stereo reverb tail that
      overlaps and layers beneath multiple 2.4-second pulses.
      - [x] Mix the output at 90% wet reverb and 10% direct dry tone.
      - [x] Filter the wet return through a rumble cut and a resonant low-pass
        that moves one scale step above the base pulse: A2 → B2.
      - [x] Use a smooth exponential tail and restrained resonance so
        overlapping sine-bass pulses do not pump or rumble.
  - [x] Place every branch node on a shared concentric numeric scale where the
    `8 → 16` ring interval is twice `4 → 8`, which is twice `2 → 4`.
  - [x] Add a toggleable synchronized spiral track through the existing
    `4 → 8 → 16` nodes.
    - [x] Follow an expanding value-derived spiral and advance a rising
      B2 → D3 → E3 sine phrase once per 2.4-second clock step.
  - [x] Render straight radial connectors from value-aware dash segments whose
    lengths and gaps expand with the local base-2 logarithmic magnitude.
  - [x] Keep numeric labels on the top SVG layer with a glyph-shaped paper
    knockout so rings and connector marks cannot overlap their text.
  - [x] Highlight the active branch line, concept label, and numeric labels
    directly in a darker, higher-chroma playback accent while leaving every
    inactive branch muted.
    - [x] Restart its OKLCH color envelope on every interval boundary and
      match the animation duration to the 2.4-second playback clock.
    - [x] Keep that rhythmic envelope within a brighter playback range while
      retaining its chromatic contrast.
    - [x] Alternate two distinct OKLCH rhythm contours instead of repeating
      the same color pulse shape.

## Baseline Integrity

- [ ] Move unsized scalar defaults into the `@project` macro.
  - [x] Add the host-backed target pointer-width builtin and a bootstrap-safe
    resolver hook for missing `integer`/`bool` defaults.
  - [x] After seed promotion, make the resolver hook call
    `targetPointerBits()` directly instead of its accepted-seed 64-bit value.
  - [x] Define lowercase `project` in Range and execute its real macro body.
    - The macro records exact `integer` and `bool` member reads, then uses
      `@expand` to add only the missing `state integer: Int` and
      `state bool: Bool` declarations.
    - Focused fixtures prove the empty-project expansion and preservation of
      an explicit `state integer: Int<4>` override.
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
  - [x] Define and validate text literal facts as semantic `Character`
    elements encoded as UTF-8 with unsigned 8-bit physical code units.
    - [x] Prove the exact text descriptor, missing text storage, and invalid
      physical storage through supported fixtures.
    - [ ] Replace `String`'s bootstrap `@builtin(.storage)` annotation with
      `@storage(.text(...))` after the formula-capable macro sources enter the
      reproducible seed manifest.
  - [ ] Synthesize signed and unsigned integer representations from
    `signedness` and `bits`, including unary minus only for signed storage.
  - [ ] Replace the native integer literal and LLVM lowering branches with
    macro-produced representation facts.
  - [ ] Add the Range-authored `Signedness`, `Int`, `storage`, and `literal`
    sources to the bootstrap manifest after the parser-capable seed is
    reproducibly promoted.
  - [ ] Expose compiler declarations through one canonical typed meta-model.
    - [x] Define lowercase `member` for `Declaration | Member` and annotate the
      direct `Let`, `State`, `Binding`, `Derived`, nested `Construct`,
      `Function`, `Enum`, and `Extension` syntax representations.
    - [x] Replace `Construct.Declaration`'s parallel per-kind arrays with the
      canonical `members: [@member]` collection.
    - [x] Prove one macro-family representation retains mixed authored
      `let`, `state`, `construct`, and `function` values.
    - [x] Normalize parser-backed declaration envelopes in the direct syntax
      model.
      - [x] Carry leading macro applications on function, enum, and parameter
        declarations alongside their authored identifiers and callable shape.
      - [x] Keep `let`, `state`, `binding`, and `derived` as stored declaration
        variants with macro applications, identifier, type, and value/body
        storage instead of inventing a callable parameter list.
    - [ ] Execute typed views such as
      `members.filter(all: Let) { lets in ... }` over those same values without
      copying them into a second representation.
    - [ ] Make the direct syntax values the semantic witnesses consumed by
      macros and lowering, leaving integer tables as an internal compact
      backing store rather than a parallel public model.
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
  - [x] Prove the change advances `scripts/range compiler progression` past
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
- [x] Reconcile the accepted seed manifest with the current compiler inputs.
  - The accepted seed and its complete manifested input set pass
    `scripts/verify-range-compiler-seed`.
- [ ] Run the complete validation ladder and promote one reproducible accepted
  seed after the manifest is repaired.
  - [x] `scripts/range check-build-plan`
  - [x] `scripts/range check-root-value --controls`
  - [x] `scripts/range check-compiler-smoke`
  - [x] `scripts/range check-compiler-candidate`
  - [ ] `scripts/range check-stage2-compiler`
  - [x] `scripts/range compiler progression`
- [x] Resolve accepted-seed Stage 2 once per compiler-source change.
  - [x] Share one content-addressed resolver between root-value, smoke, and the
    ordinary compiler-candidate path; keep bootstrap-bridge production
    separate because it has a different producer.
  - [x] Key the immutable artifact by the accepted seed, ordered runtime set,
    compiler source bundle and inventory, target/toolchain identity, and exact
    Clang invocation flags.
  - [x] Keep root-value and smoke proofs independent while reusing the same
    Stage 2 executable and cache key.
    - The final verified shared-cache reuse completed root-value in 3.49
      seconds and smoke in 3.72 seconds with cache key
      `22ef98c2c4267c598b7677af4ff9725b46e831fbe705632aeda60b2f25586660`.
  - [ ] Remove the labeled schema-1 executable-only compatibility lookup after
    the next compiler-source miss publishes the first schema-2 LLVM plus
    executable entry; bound cleanup of quarantined invalid entries then.
  - [ ] Consider per-function compiler-output caching only after artifact-level
    reuse proves insufficient.
- [ ] Promote the latest accepted seed as the runnable `range` compiler.
  - [ ] Make `range compile <folder>` discover the project, Core, Foundation,
    framework, and generated source graph and compile it with the immutable
    accepted compiler artifact.
    - [x] Add the supported `range compile <file-or-folder>` bootstrap path
      with deterministic recursive project discovery, accepted Core sources,
      and the shared immutable compiler artifact.
    - [ ] Move Foundation, framework, generated-source, and dependency graph
      discovery behind the Range-authored project macro.
  - [ ] Give the artifact a compiler version plus content hash, target, runtime
    ABI, and source-manifest identity; keep its LLVM as reproducibility
    evidence rather than the only usable seed.
  - [ ] Make compiler generation N produce the candidate executable for
    generation N+1, then promote only after the fixed-point and candidate
    gates pass.
  - [ ] Reuse the same content-addressed executable in the public command and
    all proof gates without reusing proof results.
- [ ] Remove Clang as a compiler-semantic dependency.
  - [x] Stop requiring the consumer's exact Clang version to equal the
    producer version recorded in the accepted-seed manifest.
  - [ ] Keep fixed-point LLVM generation independent of the installed C
    compiler; test runtime linking as a separate target-toolchain capability.
  - [ ] Move the remaining C runtime surface into Range-authored Core/runtime
    code.
  - [ ] Replace the temporary Clang LLVM validation/link provider with a
    versioned, replaceable object/link backend.

## Repository Layout

- [ ] Adopt the proposed top-level ownership layout.
  - [ ] Move the accepted compiler seed and manifest from
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
  - [ ] Reach a Stage 2/Stage 3 byte-identical fixed point, promote the
    path-aware seed, and independently reproduce it before completing the
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

## Compiler Storage

- [ ] Replace the compiler's direct RawBuffer dependency incrementally.
  - [x] Add `Buffer.range` to the compiler's manifested Core source set.
  - [x] Migrate `CompilerIntTable.values` from `RawBuffer` to `Buffer<Int>` as
    the first compiler-owned table.
  - [x] Prove the migrated table through the full fixed-point gate and promote
    the independently verified accepted seed.
  - [ ] Widen the migration to the compiler's remaining integer and text
    buffers in separately proven slices.
    - [x] Migrate the function-selection bitmap to `Buffer<Int>` and promote
      its independently verified fixed-point seed.
    - [x] Migrate function-call edge owner/target storage, including probe,
      typed, and emission edge pairs, to `Buffer<Int>` and promote its
      independently verified fixed-point seed.
    - [x] Migrate every remaining compiler-owned integer buffer, including
      syntax indexes, failure vectors, Body/ownership scratch state, LLVM
      reachability state, ABI plans, and instance-edge storage, then promote
      and independently verify the byte-identical fixed-point seed.
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
        - [x] Restore the broader `check-root-value` gate and its complete
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
        - [x] Promote the baseline into the accepted self-hosted seed and
          verify candidate Stage 2/Stage 3 byte identity, accepted-seed
          integrity, and compiler progression fixed point.
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
            accepted seed and independently verify compiler progression.
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
          prove nested RootValue and Array mutation use the direct link.
        - [x] Promote and independently verify a byte-identical Stage 2/Stage 3
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
          - [x] Promote the target-cell checkpoint into the accepted seed and
            verify seed reproduction plus LLVM/executable progression fixed
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
          - [x] Promote the arena-aware compiler seed after proving the extra
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
            interfaces, and Range once callable protocol values have a real
            runtime surface; do not mix dispatch cost into allocation results.
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
