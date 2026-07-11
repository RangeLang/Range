# Range Memory Graph Self-Hosting Plan

Status: active execution plan  
Date: 2026-07-10  
Authority: `RangeCompilerDesignDirection.md` plus the live `development` branch

## Objective

Prove Range's memory model inside the self-hosted compiler by taking one closed,
typed language subset through:

```text
authored source and stable identity
-> typed AST subset
-> Plotter structural facts
-> settled declaration/application facts
-> MemoryGraph v0
-> typed per-function IR
-> fixed-layout LLVM
```

The proof must demonstrate that compiler-derived memory facts—not ARC, garbage
collection, implicit reference counting, or a universal heap-object runtime—are
the sole policy source for storage, ownership, borrowing, aliasing, escape,
region, lifetime, transfer, and destruction decisions.

## Current Implementation Status

- Milestone 1: implementation-complete and fixed-point verified for the first
  typed-body checkpoint. File and declaration identity remain fixed-point
  proven; the live typed owner now also captures the closed proof body.
- First substrate slice: completed and fixed-point verified. It adds reusable
  contiguous `IntBuffer` storage with geometric growth, bounds-checked indexed
  reads, explicit destruction, and no compiler policy in C.
- First Range-owned identity slice: completed and fixed-point verified. It adds
  a five-column dense file table, ordered FileIDs for framed bundles, FileID 0
  fallback for ordinary source, global-to-file-local offset mapping, explicit
  destruction, and the read-only `compilerSourceIdentity` snapshot directive.
- Second Range-owned identity slice: completed and fixed-point verified. It
  adds opt-in, one-owner typed capture for construct declarations, stored
  members, functions, and parameters; distinct dense `SyntaxID`/`FunctionID`
  domains; authored file-local spans; body-independent structural
  fingerprints; cross-table validation; and fail-closed duplicate detection.
  Ordinary legacy parsing allocates no typed sidecars.
- Third Range-owned slice: implemented and focused-fixture verified. The same
  statement/Pratt parser now writes normalized body nodes and role edges for
  entry blocks, local bindings, returns, unresolved applications, labeled
  arguments, identifiers, member reads, integer literals, and addition. A
  tagged disabled sink uses the existing null `IntBuffer` contract and performs
  no heap allocation; the live sink borrows the one top-level table owner.
  No statement/expression record is decoded into typed meaning.
- The exact proof spelling `let pair: Pair(left: 3, right: 4)` is recognized
  generically as an application of the declared type; there is no `Pair` name
  or literal special case.
- Dead `functionSummary` propagation has been removed from `CompilerProgram`
  and lowered blocks while its explicit diagnostic producer remains.
- The first deletion gate is real: top-level `compilerCoreSymbols` now renders
  declarations, stored members, functions, and parameters from a
  declaration-only typed capture policy. The old top-level symbol decoder and
  its member/parameter summary scanners have been physically deleted. Legacy
  body-symbol decoding remains only for the unsupported control-flow fixture.
- Milestone 2: first live implementation is fixed-point verified. The
  `compilerPlotter` boundary captures and validates typed tables, constructs a
  bounded `CompilerGraphDelta` before those tables are destroyed, and then
  releases graph and syntax ownership in reverse order. The exact Pair fixture
  first checkpoint emits 24 NodeID rows and 21 canonically ordered `Owns`
  facts. Node rows retain
  SyntaxID, declaration identity, FileID, authored span, and facet kind;
  member, parameter, annotation, and body relationships are stored once.
- Milestone 3 semantic settlement and MemoryGraph v0 derivation are now live
  for the closed proof subset. `compilerSemantics` resolves construct/function
  applications, constructor labels, locals, parameters, member reads, node
  types, and parameter read/write/escape effects directly from authored spans
  and graph facts. `compilerMemoryGraph` then derives fixed layout, local
  storage, initialization, shared borrowing, non-escape, by-value parameter
  transport, and deterministic destruction. Neither layer decodes legacy
  summaries or rendered snapshots. Minimal typed IR and decision-driven LLVM
  lowering remain pending.

- Scalar authored storage is now part of the same MemoryGraph model. `Int`
  locals use their existing semantic identity `(kind=Int, declaration=-1)`;
  they do not receive a fabricated aggregate declaration or layout. `let Int`
  proves placement, initialization, non-escape, destruction, immutable policy,
  and scalar read access. `state Int` additionally proves unique write access,
  while the identical write through `let` fails with `invalidMemoryGraph`.
  The three focused fixtures complete in about 0.51 seconds after the shared
  compiler cache is warm.
- The scalar checkpoint is Stage 2/3 fixed-point verified. The authoritative
  Swift gate passed in 280.95 seconds; both compiler LLVM artifacts are
  2,437,516 bytes with SHA-256
  `dda331cd2513c52bf482aa100789af8173ce60a94157f8b39e068bb08fb75cc9`.
  The ordinary no-directive smoke program also emits and executes its real
  caller-owned aggregate-storage flow rather than a stub return.
- The first control-flow lifetime slice is implemented without a parallel CFG.
  Typed syntax owns explicit `If` and `LexicalRegion` nodes, Plotter carries
  those exact ownership facts, and MemoryGraph uses the lexical region as the
  branch-local storage and destruction boundary. Scalar and aggregate locals
  both destroy at that boundary; entry locals still destroy at the entry
  return; and using a branch-local name afterward fails semantic resolution.
  The Stage 2/3 gate passed in 284.49 seconds with identical 2,463,222-byte
  compiler LLVM artifacts and SHA-256
  `28b3220256ab10b28084a2a5a7bfd59ac26a75f50ab2ecb02e3a4bef42c60d12`.
  Path-specific scalar early return is now implemented from those same facts:
  destroy cardinality is per applicable `(storage, exit)` pair, so an
  entry-owned scalar destroys on both early and final returns while a
  branch-owned scalar destroys only on its branch return. Scalar return copies
  the value and keeps `Escape(0)`. Branch-local aggregate return remains an
  `invalidMemoryGraph` failure without caller placement and transfer, and
  statements following a terminal return fail typed validation. This
  superseding Stage 2/3 gate passed in 285.08 seconds with identical
  2,476,499-byte compiler LLVM artifacts and SHA-256
  `2f32401f8a74151448893c4c7406c74c9300faaab204ab4987aa6063fd266be8`.
- Opaque compiler runtime handles are now proven first through the real Core
  `IntBuffer` ABI. Typed syntax preserves `@language` provenance and captures
  signature-only ABI functions. Opaque classification requires that provenance,
  the zero-field IntBuffer declaration, and exact factory/destructor/shared-read
  signatures; ordinary empty constructs remain invalid. MemoryGraph requires
  exactly one explicit consuming destroy and rejects missing/double destroy,
  use after destroy, malformed ABI, and return without transfer. Typed IR cites
  the matching Initialize and Destroy decisions without adding a separate LLVM
  model. The full Stage 2/3 gate passed in 291.97 seconds with identical
  2,522,104-byte LLVM artifacts and SHA-256
  `b08ad21f6b09606879edbbb7a7820e82cac84d6e8e66fb92ac013b5688e64cb5`.

Accepted direct Pair semantic/MemoryGraph proof:

- semantic graph: 12 resolutions, 25 node types, and 1 parameter-effect row;
- `sum(pair:)` effect: read, no write, no escape;
- fixed `Pair` layout: 2 fields, 8 bytes, 4-byte alignment;
- one local storage in the `@main` entry region;
- seven ordered decisions: layout, local placement, initialization, shared
  borrow, non-escape, by-value pass mode, and destruction at the final return;
- two independent direct compiler runs produced identical MemoryGraph snapshot
  SHA-256 `af6b091cc58b204cbed762f742b3a018ca455d5e280654dd5c9a24923770cb34`;
- the semantic and memory focused Swift fixtures both pass (`68.32 s` and
  `68.13 s` respectively);
- the layer fails closed when semantic or memory evidence is incomplete.

Accepted semantic/MemoryGraph/typed-IR/fixed-LLVM checkpoint:

- full Stage 2/Stage 3 fixed point: `337.26 s`;
- measured maximum RSS: `6.12 GB` (`6,116,540,416` bytes);
- Stage 2/3 LLVM SHA-256:
  `1ea0a7bd707bd960dabcce8a6a9154167897ed1359f1e10c61ef1eb3446b5791`;
- Stage 2/3 binary SHA-256:
  `2186898314f8ea699f739742bc357034c32f4a4949623aad983e9e3e55436a05`;
- compiler LLVM: `2,117,938` bytes;
- direct Stage 2/3 MemoryGraph snapshot SHA-256:
  `af6b091cc58b204cbed762f742b3a018ca455d5e280654dd5c9a24923770cb34`;
- direct Stage 2/3 typed-IR snapshot SHA-256:
  `01176436e026fa84f105e8006ad8cf76357c0cbb2b562da424d6e81183ad89da`;
- direct Stage 2/3 fixed-layout LLVM SHA-256:
  `116f017051ed692e633b567325b63d29a630f673b0cf279ffbaf535fdecf081e`;
- the renamed `Duo` fixture with reversed constructor-label order compiles
  through the same generic path, clang accepts the emitted module, and the
  executable exits `7`;
- emitted proof LLVM uses a named `{ i32, i32 }` aggregate, `alloca`,
  `insertvalue`, `store`, `load`, aggregate by-value call, and `extractvalue`;
  it contains no `rangeConstruct*`, `malloc`, or `calloc` declaration or call;
- returned local aggregate is rejected before placement with native compiler
  exit `65`, proving non-escape is derived rather than asserted;
- Stage 2 inventory, body-name coverage, normal compilation, Stage 3 linking,
  and Stage 2 self-rebuild all pass;
- time is 26.2% above the hardened Plotter checkpoint and compiler LLVM is
  16.5% larger. This is recorded as the accepted first complete Range-owned
  memory-model and fixed-layout-lowering capability cost. Measured RSS is
  12.2% lower, but one run is evidence rather than causal attribution.

Accepted ordinary-native-path cutover checkpoint (supersedes the compiler
artifact hashes and measurements immediately above):

- the migrated one-construct/one-local fixed-layout subset is attempted before
  legacy native lowering; once it qualifies, semantic or memory failure is
  fatal and cannot fall back to the dynamic construct runtime;
- unrelated/unmigrated syntax still uses the transitional legacy path, so this
  is one vertical compiler with an explicit ownership boundary rather than a
  directive-only second model;
- full Stage 2/Stage 3 fixed point: `339.90 s`;
- measured maximum RSS: `7.10 GB` (`7,104,299,008` bytes);
- Stage 2/3 LLVM SHA-256:
  `3c4ecbd0280d759446257dbf1c623b912f1affce58fe285014c5f5729fae3ffd`;
- Stage 2/3 binary SHA-256:
  `6c58d32c1e1a22d8583637d72753eed3ae444835b16e6875e396534722a0d01c`;
- compiler LLVM: `2,122,020` bytes;
- ordinary renamed/reordered-label `Duo` LLVM is identical across Stage 2/3
  at SHA-256
  `21cd129b0f23fc3182eadfc06b4a8ebf668e0708f50850a85508f0d3aa87b74a`;
- clang accepts that ordinary output and the executable exits `7`; it contains
  fixed aggregate operations and no `rangeConstruct*`, `malloc`, or `calloc`;
- time is 0.8% above the directive proof checkpoint. RSS is 2.0% above the
  hardened Plotter checkpoint and remains within the accepted 10% capability
  ceiling; no causal memory-improvement claim is made.

Accepted generalized returned-aggregate and storage-policy checkpoint
(supersedes the compiler artifact hashes and measurements below):

- ownership transfer is derived per aggregate-returning call application, not
  once per callee; two calls to different returning functions therefore own
  two independent caller destinations and two `Transfer` decisions;
- typed IR iterates every returned function row and every layout field, and a
  call operation carries the callee identity used by LLVM lowering;
- focused executable proofs cover two distinct returned functions, two caller
  storages, and three `Int` fields. Reordered labeled initializers still lower
  by semantic field ordinal and the executable exits `7`;
- `let` and `state` locals both own storage, but MemoryGraph now emits an
  explicit policy decision (`1` immutable, `2` mutable) for each storage and
  typed IR cites it with a storage-policy operation;
- this is compile-time storage-policy proof only. Mutation/write-effect
  validation, non-owning `binding` aliases, alias-conflict rejection, and
  `derived` dependency edges are not yet implemented;
- the permanent ordinary no-directive Stage 2/3 smoke uses two returning
  functions, one `let` destination, one `state` destination, and two member
  reads. Both stage compilers emit byte-identical LLVM and the linked program
  exits `7` without `rangeConstruct*`, `malloc`, or `calloc`;
- full Stage 2/Stage 3 fixed point: `374.94 s`;
- measured maximum RSS: `6.40 GB` (`6,400,917,504` bytes);
- compiler LLVM: `2,210,182` bytes;
- Stage 2/3 LLVM SHA-256:
  `bd1b2ac9477a2be281ac2004add54e0a80f81b0beeca0d359ebbb23e9a7be61f`;
- Stage 2/3 binary SHA-256:
  `85566c6fa5f8e41a838bb8583d2474a9d51234f9a3732f87f73595b35c79f882`;
- ordinary no-directive proof LLVM SHA-256 from both stages:
  `2ccec65db3b40e6d15c36056df5e1e18efd91f85d3e8f9e5290919502d2f6908`;
- output determinism is proven for this checkpoint. Peak RSS is not yet
  deterministic: this run is 32.6% above the preceding `4.83 GB` measurement
  but below the earlier `7.10 GB` measurement, so no memory-efficiency claim is
  made from the single sample.

Accepted unique `state` write checkpoint (supersedes the compiler artifact
hashes and measurements above):

- local authored kind is explicit typed syntax: `let` selects immutable owned
  storage and `state` selects mutable owned storage;
- assignment syntax owns typed target and assigned-value edges. SemanticGraph
  resolves the destination local and emits a unique write effect;
- MemoryGraph derives `Access(write, unique)` only when the destination's
  storage policy is mutable. The same authored assignment to `let` fails with
  `compilerError kind=invalidMemoryGraph` and native exit `65`;
- typed IR emits `Store` only while citing that access decision; aggregate LLVM
  builds `%updated` field values and stores them into the existing entry-owned
  storage, without new placement, transfer, destruction, or runtime ownership;
- the permanent no-directive smoke mutates a returned aggregate in `state`,
  links, and exits `7`. Its LLVM is 1,722 bytes at SHA-256
  `9993168a3605c42615d2e41ab7de9bcaba917ecbd3aece8df8712fc09385a098`
  and contains no `rangeConstruct*`, `malloc`, or `calloc`;
- a fixed-point blocker exposed by this slice was a parser-boundary error, not
  a memory-policy error: identifier-led statements were routed through typed
  assignment capture even with its syntax sink disabled. Disabled capture now
  delegates to the ordinary statement parser, preserving self-hosted call
  statements while live typed capture remains fail-closed;
- full Stage 2/Stage 3 fixed point: `386.91 s`;
- measured maximum RSS: `5.60 GB` (`5,595,299,840` bytes);
- compiler LLVM: `2,278,780` bytes;
- Stage 2/3 LLVM SHA-256:
  `a4348772927c880c9246be1e7b85d336b9ed8de8e5451033ab618e9759c1ce53`;
- Stage 2/3 binary SHA-256:
  `e1f01212cc7fd3b87d3fe6fb476cf05b328633fc991ce59caf01e3c34231c307`;
- Stage 2 and Stage 3 LLVM and binaries are byte-identical. This proves
  deterministic state-write compilation, not low-memory compilation. The next
  semantic slice is `binding` as a non-owning reference to an existing
  `StorageID`, followed by shared/shared acceptance and shared/write plus
  write/write rejection. `derived` remains storage-free dependency structure.

Accepted non-owning binding-alias checkpoint (supersedes the compiler artifact
hashes and measurements above):

- construct members preserve explicit `let`, `state`, or `binding` policy in
  typed syntax, and `$source` is a typed binding-reference expression;
- a binding constructor argument resolves to the source local's existing
  `StorageID`. MemoryGraph emits `Alias(shared)` and creates no storage,
  placement, initialization, escape, or destruction for the binding itself;
- binding members are excluded from fixed physical layout. Stored `let` and
  `state` members remain the only layout fields;
- two shared aliases to storage `0` are accepted and produce two deterministic
  alias decisions;
- a unique write to storage `0` while a shared alias is live fails closed with
  `compilerError kind=invalidMemoryGraph` and native exit `65`;
- full Stage 2/Stage 3 fixed point: `390.97 s`;
- measured maximum RSS: `6.40 GB` (`6,403,768,320` bytes);
- compiler LLVM: `2,306,211` bytes;
- Stage 2/3 LLVM SHA-256:
  `2316797ee8cf145f5eb2f1c5270d898ac226f4ca744023c6085ddc98e8e6ec5c`;
- Stage 2/3 binary SHA-256:
  `e277911205f63e774134d5bd02746e9cd515a3c28d7b70e388f8d886a0d53362`;
- output determinism is proven; low-memory compilation is not. This run is
  above the prior `5.60 GB` state-write sample and remains within the older
  observed range, so it does not establish a memory reduction;
- member-target assignment traces a binding use through its receiver local,
  constructor argument, `$source`, and original `StorageID`;
- one binding-member write promotes that binding instance to `Alias(unique)`,
  emits `Access(write, unique)`, and produces a typed-IR `Store` citing the
  access decision without placing or destroying binding storage;
- shared/shared is accepted. Direct-write/shared, shared/unique, and
  unique/unique aliases are rejected with `invalidMemoryGraph` and exit `65`;
- the eight-test binding/state matrix passes in `72.895 s`: the initial
  compiler build takes `71.552 s` and every reused semantic fixture takes less
  than `0.5 s`;
- full Stage 2/Stage 3 fixed point: `398.24 s`;
- measured maximum RSS: `5.70 GB` (`5,696,176,128` bytes);
- compiler LLVM: `2,323,183` bytes;
- Stage 2/3 LLVM SHA-256:
  `0795e6fd2846758609a404ad10e781bd3752d9fd2788f1b47746e79640a803e3`;
- Stage 2/3 binary SHA-256:
  `88b2fccad5613ad10f69dcebf76bdd0e664ff1ded7b4abdeaa9bd4f398760c62`;
- the two-construct binding write is typed-IR proven but not yet emitted by the
  fixed LLVM renderer, whose proof-candidate gate still requires exactly one
  aggregate type. General multi-layout LLVM lowering is the next backend
  blocker. `derived` remains afterward as storage-free dependency structure.

Focused-test feedback-loop checkpoint:

- the Swift fixture harness fingerprints compiler sources, the bootstrap
  executable or Swift sources, runtime inputs, driver, OS, and Clang version;
  it atomically publishes one isolated mirrored compiler under a cross-process
  lock and reuses it across later Swift test processes;
- three binding checks complete in `75.005 s` total: the initial compiler build
  takes `74.735 s`, while the two reused fixtures take `0.138 s` and `0.130 s`;
- the state positive/negative pair completes in `73.707 s`: `73.568 s` for the
  initial build and `0.139 s` for the reused fixture;
- the cache never uses the repository compiler build directory and never
  participates in the full Stage 2/3 fixed-point gate. It accelerates semantic
  iteration but is not evidence of lower compiler time or memory.
- a cold invocation including Swift test recompilation measured `91.30 s`; the
  identical command in a fresh process measured `1.01 s` total, with the cached
  fixture itself completing in `0.369 s`.

Historical first returned-aggregate ownership-transfer checkpoint:

- `function makeDuo(): Duo { return Duo(...) }` constructs a typed aggregate
  value without creating callee storage;
- the caller local owns the sole storage row and receives the returned value;
- MemoryGraph emits nine decisions: layout, caller placement, call
  initialization, non-escape, caller destruction, ownership transfer,
  aggregate return mode, and two caller read accesses;
- the original checkpoint attached `Transfer` to the callee return and no
  `Destroy` decision;
  destruction occurs exactly once at the caller's final return;
- typed IR has 15 operations. Callee field insertion cites layout, transfer
  cites `Transfer`, caller receipt cites initialization, caller reads
  cite access decisions, and caller destruction cites `Destroy`;
- LLVM uses a fixed aggregate return ABI (`define %Range.Fixed`, aggregate
  `ret`, aggregate `call`), stores the received value into caller storage, and
  contains no `rangeConstruct*`, `malloc`, or `calloc`;
- the ordinary no-directive executable exits `7`;
- a callee-local aggregate returned without supported transfer placement fails
  closed with exit `65`, preventing dual callee/caller ownership;
- focused MemoryGraph, executable, and negative fixtures pass in `72.31 s`,
  `72.27 s`, and `72.09 s`;
- native compiler diagnostics are transported through the Range-authored
  `compilerNativeOutputExitCode`; the specialized native entry module calls it
  and returns its result instead of hardcoding success;
- full Stage 2/Stage 3 fixed point: `357.69 s`;
- measured maximum RSS: `4.83 GB` (`4,825,956,352` bytes);
- compiler LLVM: `2,177,259` bytes;
- Stage 2/3 LLVM SHA-256:
  `739405a9183f67185b88684a0ae6532da19f806fb36584626217f36486654cf0`;
- Stage 2/3 binary SHA-256:
  `fd47130e708ab03e60f7322abce50bb189383c875762c6314389d0f2edc93981`;
- returned-value MemoryGraph snapshot SHA-256:
  `a9c2e48b84d21c7395d34a9a536e62cb60334c333c64f37bc46f16ed2f94b093`;
- returned-value typed-IR snapshot SHA-256:
  `834a28956b015f8dcae47d169c99d5458b8b0fecc5ba7500a47b15feb18e0043`;
- framed directive LLVM SHA-256:
  `65bbc91ec484b1a4e1fb44cef78a384d3db1d43764ac9af98afd299c62665d72`;
- ordinary no-directive LLVM SHA-256:
  `e46b9b26a9101ffa6a21e255534591d9a09a054e249c6515e3b941c2dfb72eb5`;
- every snapshot/module hash matches independently between Stage 2 and Stage
  3. The ordinary and framed LLVM hashes differ only because stable declaration
  fingerprints include their different source-identity contexts;
- time is 5.2% above the prior ordinary-path checkpoint and LLVM size is 2.6%
  larger. Measured RSS is 32.1% lower, but it remains one-run evidence rather
  than a causal optimization claim.

Accepted first typed-body/Plotter fixed-point checkpoint:

- 24 total SyntaxIDs: the prior 5 declaration-side IDs plus 19 body nodes;
- 18 normalized role edges with one physical direction;
- function and `@main` bodies cover construct application, member reads,
  function call, labeled arguments, integer literals, addition, local binding,
  and return;
- body edits change the body snapshot while preserving the function's
  body-independent declaration fingerprint;
- the three-fixture body/signature test passes in `186.07 s`; the exact Pair
  focused snapshot and stricter edge/cardinality validator also pass.
- full fixed point: `264.41 s`;
- measured maximum RSS: `6.28 GB`;
- Stage 2/3 LLVM SHA-256:
  `b088d90c5806d1594a8e1a752734e5e3f7a9aed103d27db26ec3d8fb7c48521e`;
- Stage 2/3 binary SHA-256:
  `0537e1cf8813ce11889f0257b7384db9f57d8c14cc971025c4defaa3ba559811`;
- compiler LLVM: `1,771,309` bytes;
- direct linked Stage 2/3 typed snapshot SHA-256:
  `0722529f83209a776e6b9f18bc03e018c132abf5fdb06b00c07140c8afcb0e47`;
- direct linked Stage 2/3 graph snapshot SHA-256:
  `0daba32538c5c1245a93e0eec0a83075ae989f6b79e89b1f9f4e5a1d20ad2bfa`;
- time is 14.1% above the declaration-only checkpoint and LLVM is 10.7%
  larger. This is an explicit body/Plotter capability cost, not an efficiency
  claim. The first top-level symbol consumer has therefore moved to a
  declaration-only typed policy; its old decoder is no longer on that live
  path.

Post-checkpoint hardening restores the exact legacy `CompilerExpression`
shape through a `{ expression, SyntaxID }` parser result, adds a disabled-sink
guard, normalizes binary singleton ordinals, distinguishes application and
annotation facets, adds a distinct authored `@main` annotation plus one
`AppliesTo` fact (25 nodes, 22 graph facts), and strengthens graph
correspondence/reachability checks.

Accepted hardened typed-body/Plotter checkpoint:

- full fixed point: `267.23 s`;
- measured maximum RSS: `6.96 GB`;
- Stage 2/3 LLVM SHA-256:
  `9ed0e0cab2082da6f5bd77bbb7ac887969a7ad81a6c24ff4b32733f138ef0944`;
- Stage 2/3 binary SHA-256:
  `12a0e076f759001575396012f0cd3b29b2f73abe91d151d5dfb32f0fc758834e`;
- compiler LLVM: `1,818,321` bytes;
- direct linked Stage 2/3 typed snapshot SHA-256:
  `e5df209a5dcdbf8adcc675b3c748b3f7b8ad349faa574363d109c88f40ce9391`;
- direct linked Stage 2/3 graph snapshot SHA-256:
  `10719e3fd0b60e4dec8566a33ffab2207548746c8152bb0dd8b1bf1b61cb4877`;
- time is 1.1% above the first body/Plotter checkpoint. The hardened snapshot
  has 25 nodes, 22 graph facts, distinct application/annotation facets, and a
  real `AppliesTo` fact; its migrated top-level symbol decoder is deleted.

Accepted IntBuffer checkpoint:

- full fixed point: `202.49 s`;
- reported maximum RSS: `7.57 GB` (recorded, but not attributed to IntBuffer
  because compiler tables do not consume it yet);
- Stage 2/3 LLVM SHA-256:
  `f9556a71dcd67343f9ba30f6b24ac23324ca518779ade3122338ceda8e839739`;
- Stage 2/3 binary SHA-256:
  `a1f35b6cf93ab810cdc01e55c1c5c6951183c0367e18596a6954fe13f98f8e18`;
- compiler LLVM: `1,318,366` bytes;
- strict C build, Swift emitter ABI, linked runtime execution, native compiler
  lowering, inventory/body checks, transitive smoke, and Stage 2/3 byte
  equality all pass.

Accepted source-identity checkpoint:

- bundled two-file and ordinary-source identity fixtures pass;
- direct Stage 2 snapshot reports deterministic FileIDs, path/content spans,
  and local offset zero at each content start;
- full fixed point: `205.73 s`;
- reported maximum RSS: `6.38 GB` (recorded as run evidence, not attributed as
  an optimization result);
- Stage 2/3 LLVM SHA-256:
  `77b6c4f44ca5af9d7b2ddf9a2421a679482328056df2b57bf8953340d54c6013`;
- Stage 2/3 binary SHA-256:
  `54594b75e37c74cfc19af341170d1878dc237490cb4993d0e0ad51dac719820f`;
- compiler LLVM: `1,342,915` bytes;
- inventory/body checks, transitive normal compile, self-rebuild, direct Stage
  2 identity snapshot, and byte equality all pass.

Verified typed-declaration checkpoint (bounded capability exception):

- bundled Pair capture produces 5 dense syntax rows, 2 declarations, 2 stored
  members, 1 function row, and 1 parameter row with correct FileID-local
  authored spans;
- at this declaration-only checkpoint, body-only edits preserved the full
  snapshot and function fingerprint. With typed body rows now present, body
  edits correctly change the full snapshot while preserving the declaration
  fingerprint; signature edits change the function fingerprint; unrelated
  declaration reorder changes dense rows without changing the target
  fingerprint;
- duplicate declaration fingerprints poison capture and return a structured
  invalid-snapshot diagnostic;
- direct linked Stage 2/3 typed snapshot SHA-256:
  `baadb048d1053268dbdde6fc03f290548d261cdb3646d395e633fe2b593f3f8e`;
- full fixed point: `231.72 s`;
- measured maximum RSS: `10.55 GB`;
- Stage 2/3 LLVM SHA-256:
  `1fb6d3b9339630a5599e016baf27570113cefb0fa1018ffc5c5b478f2f0f1d49`;
- Stage 2/3 binary SHA-256:
  `ea8b898171e7d443997b627377294cbd80b39adc0afc7a211dc8f39a5e952f27`;
- compiler LLVM: `1,599,738` bytes;
- time is 12.6% above the source-identity checkpoint, exceeding the nominal
  10% gate. This is recorded as a direct typed-identity capability cost, not
  an efficiency win. The bridge must pay that cost down by moving a real
  consumer to typed rows and deleting its string-record path before broad
  feature expansion;
- RSS is within 10% of the preserved `10.10 GB` source-lazy baseline. As with
  earlier RSS readings, a single run is evidence, not causal attribution.

## Preserved Baseline

The starting implementation is development commit `3a309a8d`.

Permanent baseline evidence:

- Stage 2 and Stage 3 LLVM SHA-256:
  `208a80777c24e0e285f85ce6959826f49a7cea3987bd485de2c0331f0cda80c1`;
- Stage 2 and Stage 3 native binaries are byte-identical;
- full fixed point: `200.01 s`, `10.10 GB` maximum RSS;
- compiler LLVM: `1,309,617` bytes;
- transitive `main -> helper -> leaf` smoke passes;
- arithmetic and function call fixtures return `7`;
- printing emits `Hello from Range`;
- delimiter-heavy strings, unique LLVM globals, clang validation, linking, and
  execution pass.

Every milestone must preserve the previous milestone's fixtures and record:

- elapsed time and maximum RSS;
- Stage 2 and Stage 3 LLVM and binary hashes;
- identity, Plotter, and MemoryGraph snapshot hashes when those layers exist;
- fixture exit status/stdout/diagnostics;
- placeholder, unresolved-helper, malformed-LLVM, and link failures.

Do not run Stage 2 and Stage 3 gates concurrently.

## Permanent Rules

- Range-authored code owns compiler and memory policy.
- Stage 0 may provide only reusable runtime, ABI, lowering, process, linking,
  validation, and test substrate required by the vertical slice.
- Authored source and AST are immutable.
- Parser remains structural and does not resolve names, settle types, or make
  memory decisions.
- Plotter emits structural graph facts and provenance, not memory policy.
- MemoryGraph is the only authority for emitted storage/lifetime decisions.
- Typed IR carries settled decisions and cannot invent a heap, ARC, GC, or
  refcount fallback.
- Final text is produced only at serialization boundaries.
- Unsupported or ambiguous cases fail closed with authored diagnostics.
- No second Swift semantic compiler, parallel memory engine, or external chunk
  protocol may be introduced.

## The First Proof Fixture

```range
construct Pair {
    let left: Int
    let right: Int
}

function sum(pair: Pair): Int {
    return pair.left + pair.right
}

@main {
    let pair: Pair(left: 3, right: 4)
    return sum(pair: pair)
}
```

Required settled interpretation:

- `Pair` has a deterministic two-field fixed layout;
- `pair` has local storage in `main`;
- construction initializes both owned fields;
- `sum` observes/borrows the value without mutation;
- the call does not transfer ownership;
- the value does not escape `main`;
- the selected representation is a fixed value/aggregate with local lifetime.

The source parameter remains a semantic value input. A shared-address
`sum(ptr)` ABI is permitted as copy-elision/read-only transport only after
MemoryGraph proves that pass mode; it is not source-level `binding` aliasing.

Required emitted proof:

- executable returns `7`;
- LLVM contains a fixed Pair layout/value representation;
- LLVM contains no `rangeConstructCreate`, `rangeConstructSet*`, or
  `rangeConstructGet*` call for Pair;
- LLVM contains no `malloc` or `calloc` for the local Pair value;
- Stage 2 and Stage 3 identity, graph, MemoryGraph, IR, and LLVM snapshots are
  identical.

## Accelerated Proof Track

The core memory-model hypothesis must be proven before completing every
eventual compiler service. Use three bounded implementation patches:

1. **Dense identity substrate:** build `CompilerIntTable` over `IntBuffer`, map
   the existing bundled source framing to minimal `FileID`/source spans, and
   produce deterministic source/identity snapshots without changing target
   program LLVM. Declaration/member/function/parameter capture is an opt-in
   bridge in this patch: it shares token/type grammar with legacy parsing,
   owns and destroys its tables exactly once, and may not become a permanent
   parallel representation.
2. **Typed proof graph:** parse only the Pair proof subset into typed tables;
   Plotter emits structural facts; Application/Semantic v0 settles the closed
   references/types/effects; MemoryGraph emits deterministic memory decisions.
   This patch is implemented and focused-fixture verified; Stage 2/3 snapshot
   equality is still required before accepting its fixed-point checkpoint.
3. **Decision-driven lowering:** implemented and fixed-point verified for any
   equivalent two-`Int`-field construct. Typed operations cite exact
   MemoryGraph rows; aggregate LLVM contains no dynamic construct runtime or
   allocator dependency. Renamed/reordered-label, returned-local rejection,
   executable, unique `state` mutation, immutable-write rejection, non-owning
   shared and unique `binding`, shared/shared acceptance, direct-write/shared,
   shared/unique, and unique/unique rejection, and Stage 2/3 snapshot gates
   pass. General multi-layout LLVM lowering, `derived` dependencies,
   shared-borrow lifetime precision, and escaping-owner placement remain
   follow-on expansions of the same graph and IR, not alternate models.

The accelerated track may defer full Foundation identity, editor line maps,
in-compiler content-hash persistence, StringID interning, body caching without
duplicate-parse evidence, macros, arrays, generics, broad semantic settlement,
the full parity sweep, and compiler dogfooding. It may not defer authored spans,
snapshot-local dense row IDs, a body-independent structural fingerprint, typed
proof identities, settled proof-subset meaning, deterministic snapshots, or
fail-closed behavior.
It must not special-case the name `Pair` or recover proof facts from rendered
LLVM/string summaries.

## Milestone 1: Stable Identity And Typed Authored Storage

### Scope

Introduce the minimum durable substrate needed by Plotter and MemoryGraph:

- `SourceSnapshotID` and one immutable bundled backing source;
- `FileID` and a file table containing path, role, bundle range, file-local
  range conversion, content hash, and line-map ownership;
- `DeclarationID` and `FunctionID` derived from stable declaration path and
  declared signature shape, excluding body content;
- typed records for the proof subset:
  - construct declaration;
  - stored member;
  - function and parameter;
  - local binding and return;
  - construct application, member read, and function call;
  - integer literal and addition;
- a `SyntaxID` and authored source span on every typed node;
- typed lookup APIs for declarations, members, parameters, syntax nodes, and
  applications;
- parse-count instrumentation for lazy bodies.

Body caching is evidence-gated. Add a cache only if instrumentation proves an
active path parses the same `(SourceSnapshotID, FunctionID, BodySyntaxHash,
ParserSchemaVersion, ParserOptionsHash)` more than once. Do not make cache
construction a prerequisite when no duplicate exists.

### Physical requirements

- IDs are typed integers, never record offsets exposed as durable identity.
- File and typed AST tables are contiguous, ID-indexed stores.
- Names and paths use interned `StringID` values once interning exists.
- Tokens and AST nodes refer to source spans rather than copied source text.
- Do not implement the new stores as delimiter-encoded semantic databases or
  linked name-keyed construct fields.
- Plotter, semantic settlement, and MemoryGraph may not recover meaning by
  decoding `memberSummary`, `parameterSummary`, `statementRecords`,
  `expressionRecord`, or `localValues` strings.
- If current Stage 0 cannot realize the table ABI, add only a reusable generic
  contiguous buffer/slot substrate with geometric capacity.

### Gate

- stable identity snapshots are identical across repeated runs and Stage 2/3;
- body-only edits preserve declaration/function identity;
- declared-signature edits change the appropriate identity/fingerprint;
- every proof node maps back to the correct file and authored span;
- emitted LLVM and fixture behavior remain unchanged;
- fixed-point time/RSS do not regress by more than 10% without an explicitly
  accepted architectural capability gain.

### Deletion gate

When the final consumer of a migrated declaration record uses the typed store,
delete that string field, encoder, decoder, and lookup path. Do not leave dual
semantic representations indefinitely.

The opt-in `compilerTypedSyntax` path is a proof/serialization boundary, not a
future semantic API. Plotter must consume live typed tables. Once the first
declaration/body consumer moves, delete the equivalent summary/record decoder
rather than teaching both representations new semantics.

## Milestone 2: Structural Plotter Delta

### Scope

Plot the typed proof subset into deterministic graph identities and facts:

- `Node(kind, SyntaxID, DeclarationID, FileID, span)`;
- `Owns(owner, child, role, ordinal)`;
- `Origin(node, SyntaxID, span)`;
- `Facet(facet, syntax)` where declaration/application facets differ;
- annotation `AppliesTo` for `@main` and later authored annotations;
- declaration, member, function, parameter, local, application, and return
  identities required by the fixture.

Plotter must return a bounded `GraphDelta`. It does not mutate AST storage,
resolve names opportunistically, infer types/effects, execute macros, or lower
LLVM.

Application syntax nodes are structural and unresolved at this phase.
Canonical snapshot order is `FileID`, `NodeID`, role, then ordinal.

### Gate

- graph delta ordering is deterministic;
- graph snapshots and public-shape hashes match across Stage 2/3;
- every fact retains authored provenance;
- no relationship is physically stored twice for forward/inverse access;
- unresolved or ambiguous proof-subset references fail with authored
  diagnostics;
- current LLVM remains unchanged until Milestone 3 consumes the graph.

## Milestone 3: MemoryGraph v0, Typed IR, Fixed LLVM Layout

### Application/Semantic v0

Before MemoryGraph runs, settle the proof subset through a narrow typed
application/semantic layer that resolves:

- `Pair` construction to its declaration;
- constructor argument labels to stored members;
- the `sum` call to its function declaration;
- `pair.left`/`pair.right` to fixed members;
- local and parameter references;
- `Int` field, addition, and return types;
- per-parameter read/write/escape effects.

These are explicit typed enrichment facts after Plotter. Plotter does not
resolve names or types, and MemoryGraph does not guess missing semantic facts.
Unsupported or ambiguous cases fail closed before memory derivation.

The native compiler process must propagate a Range-owned failure result as a
nonzero exit status. Printing `compilerError` while the generated NativeMain
returns `0` is not an acceptable negative proof. Stage 0 may transport the
status but does not decide the diagnostic or policy.

### Facts

Derive typed, provenance-bearing facts for:

- `Region`, `Storage`, and `Value` identity;
- `Owns` and `Stores`;
- `Access(read/write)` and `Borrow(shared/unique)`;
- unique mutable access;
- semantic and lowering `Alias` facts kept distinct;
- `Escape` or non-escape;
- `LifetimeConstraint`;
- `LayoutDecision`, `PlacementDecision`, and `PassMode`;
- transfer and `DestroyPoint`.

MemoryGraph may run only after the proof subset's declaration, type, layout,
call, mutation, and escape inputs are settled. Missing inputs produce a
diagnostic; they never select an implicit heap/reference fallback.

### Typed per-function IR

Build the minimum typed IR required to carry the proof:

- fixed-layout value construction;
- local storage identity;
- field initialization and read;
- read-only borrow/call parameter;
- integer addition;
- return;
- explicit storage/transfer/destruction operations selected by MemoryGraph.

IR validates that every storage-affecting operation cites a MemoryGraph
decision. Backend lowering only realizes those operations.

### Contrasting fixtures

After the non-escaping Pair fixture, add:

1. returned Pair with explicit ownership transfer to the caller;
2. unique mutation accepted and recorded;
3. conflicting mutable aliases rejected precisely;
4. multiple shared immutable borrows accepted;
5. Pair stored into an escaping owner with a derived longer-lived region.

### Gate

- all proof and contrasting fixtures have deterministic graph/IR snapshots;
- non-escaping Pair uses fixed layout without construct-runtime calls,
  `malloc`, or `calloc`;
- alias/mutation diagnostics point to authored spans and derivation facts;
- negative fixtures return a nonzero native compiler status;
- Stage 2/3 remain byte-identical;
- no current parity fixture regresses;
- keep the slice only if it preserves correctness and either improves the
  measurements or establishes the accepted reusable memory-model capability
  within the 10% regression ceiling.

### Deletion gate

For migrated constructs, delete linked field-name globals and dynamic
`rangeConstructCreate/Set/Get` lowering. The generic runtime may remain only
for unmigrated language cases until their own typed vertical slices land.

### Follow-on dogfood gate

Do not require a compiler-owned construct in the initial non-escaping Pair
proof. Existing small compiler records are returned or embedded. After the
returned/stored-value and escape-placement fixtures pass, migrate
`CompilerBlock` through the same path and then measure fixed-point time/RSS.

## Supporting Gate: Native Parity Matrix

Before changing the default driver, run the already-built Stage 2 compiler over
all entries in `RangePlayground/Examples/LLVM/run-manifest.tsv` and classify:

- pass;
- compiler diagnostic;
- malformed LLVM;
- unresolved link symbol;
- executable crash;
- wrong exit status;
- wrong stdout/stderr.

Compare observable behavior, not Swift/native LLVM text. Native compiler errors
must produce nonzero status before clang is invoked.

This matrix is a permanent regression gate but does not block the narrow
MemoryGraph proof from beginning.

## Work Order

### Current performance blocker (2026-07-10)

Per-phase measurement proves that the MemoryGraph fixtures and fixed-point
orchestration are not the long pole. Stage 1 is about 72--76 seconds and
128 MB; native Stage 2 emission and the Stage 3 self-rebuild consume roughly
375 seconds and 6.5--10+ GB. Validation, linking, inventory, and executable
smoke checks are sub-second.

The native entry no longer retains legacy Stage 1 AST/type/LLVM summaries.
Those remain bootstrap diagnostics and are not self-hosting identity inputs.
A transitive-reachability experiment stayed byte-identical but increased cost
to 515.30 seconds and about 10.15 GB, so it was reverted. Before adding the
remaining control-flow and escape fixtures, reduce transient memory in
selected-helper lowering/text construction while retaining the explicit,
proven native root set and the byte-identity gate.

The first selected-helper transient region now proves a concrete lifetime:
lower one helper, copy its rendered function and global records into durable
buffers, retain the scalar next-temporary value, then destroy the helper's
temporary string region. Stage 2/3 remain byte-identical at 2,428,874 bytes.
Stage 3 peak child RSS fell from 11.07 GB to 9.84 GB in adjacent explicit-root
measurements, but Stage 2 remained 10.86 GB because Stage 0's emitted string
operations do not yet use the tracked allocator. The next slice is to make
Stage 0 realize the same explicit region ABI, then separately audit the
lifetime of `textBufferMaterialize` results. Do not broaden the reset to file
input, construct storage, or materialized buffers without a MemoryGraph-backed
escape proof.

The bounded region work now covers both generations. Stage 0 string emission,
active-region text materialization, and fresh helper-local construct wrappers
use the same mark/reset substrate. Construct reads no longer create fields.
The authoritative retained gate is 276.21 seconds / 4.50 GB, down from 479.86 seconds /
9.00 GB, with Stage 2/3 LLVM byte-identical at SHA-256
`95b1b1378bea94a2dd7a88233ff5adcc8d89c0858be7e9cad470b58dd8777e94`.

This is a real hierarchical lifetime proof, not general ownership completion:
compiler inputs outlive the selected-helper region; helper output is copied to
durable buffers; only scalar progress crosses reset. General file buffers,
arbitrary user strings, escaping constructs, and opaque runtime handles still
require explicit MemoryGraph decisions. Continue from fresh profiles rather
than broadening the dynamic region by convention.

1. Check in the architecture and this plan.
2. Implement Milestone 1 source/file identity and proof-subset typed records.
3. Prove identity determinism and unchanged LLVM at the fixed point.
4. Implement Milestone 2 Plotter facts for the proof subset.
5. Prove deterministic graph snapshots and authored provenance.
6. Implement Milestone 3 MemoryGraph v0 and typed function IR.
7. Switch only the Pair proof fixture to fixed-layout lowering.
8. Add contrasting ownership/alias/escape fixtures.
9. Dogfood one compiler construct and measure.
10. Expand vertically; never replace the working compiler in one rewrite.

## Completion Definition

This plan is complete when Range's self-hosted compiler can prove, snapshot,
and reproduce the Pair fixture's storage/ownership/borrow/alias/escape/lifetime
facts; carry them through typed per-function IR; emit a fixed non-heap layout;
execute correctly; and reproduce identical MemoryGraph and LLVM output at
Stage 2 and Stage 3 without ARC, GC, implicit refcounting, or Swift-owned
memory policy.
