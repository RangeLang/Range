# TODO

Priority and dependency order live in [MILESTONES.md](MILESTONES.md). This file
owns the actionable checkboxes for the active and deliberately deferred work.

## Website

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
    - [x] Present the newest writing in a responsive homepage strip of
      animated OKLCH shader cards, led by `Codability under 100`.
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
    - [x] Keep inspectable macro nodes flat and non-interactive, and navigate
      the five explanations explicitly through a trailing numbered chapter rail.
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
              block chapter such as `environment.expand` is selected.
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
        - [x] Align the query passage's `2` badge beside its indented `let`
          line, matching the `3` and `4` chapter badges.
      - [x] Show step 4's complete `#environment.target.declaration.self`
        mention in the inspector accent and explain `#` as interpolation from
        a macro-time value into code that executes later.
      - [x] Keep the generated `encode` function inline in the target extension
        and use one `[@stored]` query for immutable fields and state.
      - [x] Lead with inspector explanations, place accented syntax beneath
        them, and remove Phase/Produces metadata from every inspector.
        - [x] Separate the concepts cleanly: chapter 3 owns ordinary validated
          Range code inside `environment.expand`, while chapter 4 owns only the
          highlighted `#environment.target.declaration.self` splice.
          - [x] Explain that `extension` expects a nominal value and the
            environment supplies one, making the spliced extension valid Range
            code.
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
  - [x] After seed promotion, make the resolver hook call
    `targetPointerBits()` directly instead of its accepted-seed 64-bit value.
  - [x] Define lowercase `project` in Range and execute its real macro body.
    - The macro records exact `integer` and `bool` member reads, then uses
      `environment.expand` to add only the missing `state integer: Int` and
      `state bool: Bool` declarations.
    - Focused fixtures prove the empty-project expansion and preservation of
      an explicit `state integer: Int<4>` override.
  - [x] Remove `project` name-based collection from compiler semantics.
    - Successful macro invocations materialize generic typed result rows with
      invocation, target, nominal type, scalar, and child-count provenance.
      The Range-authored macro returns `ProjectDefaults()`, and lowering
      resolves that value only after ordinary macro execution.
    - `compilerFormulaExecuteApplication` has no `project` branch; project
      defaults are selected by the returned `ProjectDefaults` nominal rather
      than by the attached macro's spelling.
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
      - [x] Standardize executable macro bodies on one authored
        `{ environment in }` binding. `Macro.Environment<Target>` owns the
        target and diagnostics/graph query views; the compiler records one
        capability handle and models each view as an explicit environment
        projection rather than an ordinary local symbol.
        - [x] Make `environment.expand { ... }` the only tracked authored
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
            Stage 2/Stage 3 fixed point.
        - [x] Route every direct call on the environment's `target`, `graph`,
          and `diagnostics` projections through capability resolution,
          including denied operations, while leaving deeper source-backed
          syntax paths to ordinary Range member resolution.
          - Verification: the compiler candidate proves an untaken denied
            `target` operation is path-sensitive and an executed denied
            `graph` operation emits `macroCapabilityDenied`.
      - [x] Declare the Range-authored generic projection surface as
        `function filter<T>(all: T): [T]` on the single `Array<Element>`
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
          `key: String?(nil)` and `exclude: Bool(false)`.
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
        - `environment.expand` is an ordinary delta-producing capability call instead of an
          implicit return at the end of every nested block; the authored
          function-boundary `return` now carries the result through the shared
          continuation.
        - `Testing/Macros/Pass/BranchJoinReturn.range` and the Range-authored
          `project` macro prove the shared return after conditional expansion.
      - [ ] Treat `[@member]` as a deferred compile-time collection: collect
        the complete conforming child set before synthesizing its physical
        storage.
        - [x] Intern macro-family member types as deferred `Array` views and
          execute `environment.target.declaration.members.count` through lazy,
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
            `compilerFormulaExecuteApplication` into the Range-authored
            `graph` body once macro targets expose direct nested declarations,
            then delete the name-based compiler bridge.
        - [x] Remove the remaining parallel declaration/application fields
          from `Function`, `Parameter`, and `Enum`; normalize function calls as
          `Function.Application`.
        - [x] Delete the unused `GraphSyntax`/`GraphEntry` container model;
          graph roles now live only as capabilities attached to syntax
          families.
        - [x] Remove nominal-reference, protocol, and conformance storage from
          syntax declarations; declaration and application capabilities are
          expressed by attached macros instead of inherited nominal contracts.
          - [ ] Promote the source removal through the accepted bootstrap seed
            after compiler progression reaches the corresponding checkpoint;
            do not hand-edit the generated LLVM snapshot.
        - [ ] Materialize construct macro targets directly as
          `Construct.Declaration` and remove the compatibility
          `environment.target.declaration` projection.
      - [x] Define the Range-authored bidirectional `SyntaxTemplate` value
        model with fixed written elements, member-linked captures,
        one/optional/many cardinality, canonical syntax bindings, matching,
        and rendering.
        - `Construct.range` now authors declaration and application templates
          directly in its `@syntax` body, including ordered macro/member
          captures and optional generic groups.
      - [ ] Execute `@syntax` by matching its raw template body against the
        annotated construct's members, materializing a canonical value, and
        using the same template to render values consumed by
        `environment.expand`.
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
          - [x] Remove the seed-compatible `#(...)` spelling and reject it
            structurally. Compile-time values use only prefix mentions such
            as `#properties.map` and
            `#environment.target.declaration.self`; no braced splice program
            form exists.
        - [x] Materialize macro applications retained inside generated
          function bodies as child applications of the parent expansion.
          - The construct-attached Codable proof records one parent and two
            child invocations. Each helper now executes `environment.expand`
            and produces a source-backed syntax artifact instead of remaining
            unexecuted template text.
          - [x] Make `Block` the canonical ordered body syntax relationship
            before composing generated bodies.
            - [x] Define the Range-authored surface as
              `Block.syntax: [@syntax]`; do not use physical lines or a
              statement-only parallel hierarchy as the semantic container.
            - [x] Capture every authored/generated function and entry body as
              one `body` edge to a `Block`, with the block owning its ordered
              syntax children and nested control-flow bodies using the same
              block kind.
              - The typed-body replay now requires two `block` nodes and two
                role-31 `body` edges; RootValue validates, links, and executes
                the resulting compiler output.
            - [x] Preserve authored source spans and generated
              macro-application provenance independently from containment.
              - Expansion templates retain their parent macro declaration and
                application while each fragment retains its own file-local
                span, parent fragment, and source ordinal.
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
            flatten their `environment.expand` artifact values, and join them
            into the parent's uncommitted graph delta.
            - [x] Execute ready scalar-result children in source order and
              persist their recursively materialized return values.
              - `CodableConstructCollection.range` now proves three
                invocations and two helper results of `2`.
            - [x] Treat child syntax artifacts as replacement fragments and
              merge nested expansion graph deltas before commit.
              - The source store appends immutable generated files through
                in-place String storage growth, avoiding unsupported stored
                String reassignment in the accepted seed.
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
          non-stored `@field` members.
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
          actual `Core/Macro/Codable.range` source by `check-root-value`; one
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
  - [x] `scripts/range check-stage2-compiler`
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
  - [x] Add a profile-sensitive development Stage 2 for root-value and smoke.
    - Keep the accepted-seed producer optimized, but validate and link the
      disposable Stage 2 with `-O0` and no LTO. Candidate, fixed-point, and
      promotion paths retain `-O2` plus ThinLTO.
    - Key the profile and both producer/output flag sets into the immutable
      cache, so development artifacts cannot satisfy optimized gates.
    - Emit phase timings on cache misses. The first measured development miss
      spent 18 seconds linking the optimized seed, 593 seconds emitting LLVM,
      1 second validating LLVM, and 2 seconds linking Stage 2.
  - [ ] Make compiler LLVM emission incremental or cacheable below the full
    source-bundle key.
    - Phase timings show self-emission, not Clang or linking, dominates a
      compiler-source cache miss; preserve full candidate/fixed-point proofs.
    - The `@stored` selector proof measured 916 seconds emitting LLVM, 2
      seconds validating it, and 2 seconds linking Stage 2. The identical
      follow-up root-value run reused the immutable artifact and completed in
      about 4 seconds.
    - [x] Add a validated rolling development producer and skip the duplicate
      ownership/effect reconstruction only for marked development source sets.
      - Root-value publishes a development compiler as a future producer only
        after all focused proofs pass. Optimized candidate, fixed-point, and
        promotion gates continue from the accepted seed and retain the full
        independent effect-validation pass.
      - The producer identity is part of the immutable cache key; the normal
        source snapshot remains unchanged and the marker exists only in the
        disposable emission bundle.
    - [x] Measure a marker-aware cache miss and record the new phase timings.
      - The strict bootstrap miss emitted LLVM in 777 seconds. The validated
        marker-aware forced miss emitted LLVM in 650 seconds, validated in 1
        second, linked in 2 seconds, and passed the focused RootValue suite.
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
      - [x] Pin development producers explicitly and remove the legacy
        `single-pass-v1` producer fallback.
        - Normal successful development gates no longer advance the producer.
          `RANGE_STAGE2_ADVANCE_DEVELOPMENT_PRODUCER=1` is required after a
          focused validation pass.
        - `per-function-artifacts-v1` requires a bundle on every source-key
          miss; missing or malformed artifact state is a hard failure.
      - [ ] Persist a stable `[@syntax]` artifact graph and store unchanged
        LLVM fragments as immutable chunks.
        - Fingerprint each syntax value independently, including blocks,
          functions, local and stored bindings, macro applications,
          constructs, and enumerations. Key its phase artifacts by the syntax
          fingerprint, compiler/seed/toolchain identity, and the fingerprints
          of dependencies actually observed by that phase.
        - Invalidate the changed syntax values plus their reverse dependency
          closure. Functions remain LLVM-fragment owners, but are no longer
          the only reusable compiler unit.
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
- [ ] Promote the latest accepted seed as the runnable `range` compiler.
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
    - [ ] Add a `range backend` boundary that consumes emitted LLVM and
      produces a target object without routing through the Clang driver.
      - The current machine has `/usr/bin/ld` but no `llc`, `llvm-as`, or
        `opt`; `ld` cannot consume LLVM IR, so this requires a shipped LLVM
        target backend or a Range-owned Mach-O/object writer.
    - [ ] Invoke the platform linker directly with a deterministic,
      manifest-recorded SDK/runtime link plan after object production.
    - [ ] Replace `Core/Package/LinkPlan.range`'s authored `clang` process with
      that backend plus direct-link plan.
    - [ ] Remove Clang identity and flags from Stage 2 cache/build-plan keys
      only after object generation, runtime compilation, validation, and
      linking have independent versioned owners.

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
      - Promoted accepted seed `bootstrap-154b7b1459b9`; its manifest-driven
        Stage 3 reproduces LLVM hash
        `154b7b1459b90de1b3d38fb5d8ba28e97810407b0d225ecc77e0e369019dc7a3`.
