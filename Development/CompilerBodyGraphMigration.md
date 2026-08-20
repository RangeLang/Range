# Compiler body graph migration

## Status: historical Compiler A post-mortem

This document preserves the inventory and measurements that exposed Compiler
A's duplicate body parsing. Its former in-place migration is frozen. We will
not extend A's `Function.Declaration` capture with arrays, closures, switches,
jumps, CFG derivation, or additional compatibility carriers.

Compiler A now only builds runnable Compiler B slices. Compiler B lives under
`Projects/RangeCompilerB/Sources/CompilerB/` and is being grown from a minimal
B-owned lexer/parser rather than from copied A phases. The arena inventory below
records what was learned from A. It is not an active migration sequence and is
not an instruction to copy, refactor, or dual-run those phases inside B. See
`Development/CompilerForkArchitecture.md` for the active plan.

Everything below this status section is historical design evidence. Statements
about a migration, dual runner, or replacement order describe the abandoned
in-place Compiler A plan unless they are separately adopted by a current B
checkpoint.

## Historical construction boundary

The typed body tables currently demonstrate the desired vocabulary and CFG
shape, but their contents are not yet canonical parse products.
`compilerTypedSyntaxCaptureBlockContents` reopens each function body's source,
calls `parseCompilerStatement`, and then asks the
`compilerBodySyntaxCapture*Record` family to reconstruct child nodes from the
legacy serialized expression and statement records. The later
`compilerExecutableDeclarationDeriveLegacy` path parses the same body again
into `CompilerBodyArena`. Consequently the existing array, interpolation, and
control-flow fixture equality is transitional product evidence, not proof that
source rediscovery has been removed.

The corrected boundary is executable production, not syntax exchange. A turns
B's Range sources into an executable. B then opens the product source and
introduces the declaration's Block, body nodes, ordered relationships, slot
occurrences, and source gaps itself. B does not consume A's serialized
`CompilerExpression`, `CompilerStatement`, syntax facts, or arena state.

## Durable lesson

`CompilerBodyArena` is not the future function-body representation. The typed
syntax graph is the authority for body identity, nesting, roles, and source
locations. Resolution, CFG, ownership, and MIR are independently derived graph
products attached to that authority.

The arena remains part of frozen Compiler A behavior. Compiler B does not copy
it as a legacy runner. When B eventually derives equivalent products, this
inventory may inform focused comparisons, but it does not prescribe B's
implementation sequence.

## Why the current boundary is expensive

`compilerBodyArenaCreateForBodyWithTypeTables` allocates every table required
by parsing, resolution, CFG, ownership, and MIR before it knows which product
the caller needs. `compilerBodyArenaParseFunction` then creates a second,
arena-local node identity and copies source ranges and parent relationships
already represented by `CompilerSyntaxTables.bodyNodes` and `bodyEdges`.

There are currently twelve direct parse call sites. Function-instance bodies are
parsed independently during ABI capability probing, reachability discovery,
LLVM lowering, and ownership/effect discovery. Compile-time functions, macros,
closures, and the entry block add more parse paths. This means later phases are
not merely deriving different lenses over one retained body fact; they are
reconstructing the body on demand.

| Current parse caller | Purpose |
| --- | --- |
| `compilerMacroExecutionEvaluateClosure` | Execute one compile-time closure body. |
| `compilerMacroExecutionEvaluateFunction` | Execute one ordinary function at compile time. |
| macro invocation pipeline in `CompilerFrontend.range` | Execute one macro declaration body. |
| typed syntax CFG snapshot in `CompilerParsing.range` | Construct the legacy comparison product. |
| `compilerReachableLLVMStateProbeCandidateFunction` | Probe ABI capability for one function instance. |
| `compilerReachableLLVMStateDiscoverFunction` | Discover calls, instances, direct effects, and representation sensitivity. |
| `compilerReachableLLVMStateEvaluateMainBehaviorRoot` | Derive entry behavior during reachability planning. |
| `compilerCoreLLVMLowerEntryTyped` | Lower the entry body. |
| `compilerCoreLLVMLowerHelperFunctionTypedObserved` | Lower one reachable function instance. |
| `compilerReachableLLVMStateBuildOwnedReturnSummaryForWorkItem` | Derive one owned-return summary. |
| `compilerReachableLLVMStateValidateFunctionInstanceEffectsForWorkItem` | Validate retained effects for one function instance. |
| `compilerReachableLLVMStateValidateEntryOwnedPaths` | Validate entry ownership paths. |

## Arena inventory and replacement ownership

| Arena contents | Current fields | Graph-native owner |
| --- | --- | --- |
| Compiler and owner context | `tables`, `declarationIndex`, `ownerKind`, `ownerDeclarationSyntaxID`, `ownerFunctionRow`, `ownerFunctionInstanceID`, receiver type IDs, `fileID`, body offsets, `rootNodeID` | A lightweight function-body identity and specialization context. The root syntax identity points into the shared syntax graph. |
| Copied source shape | `nodes`, `edges`, `parentNodes`, `parentRoles` | Shared `bodyNodes` and `bodyEdges`, plus reusable indexes keyed by stable syntax identity. No body reparse and no second semantic node identity. |
| Name and type analysis | `symbols`, `resolutions`, `typeInstances`, `typeArguments` | `CompilerFunctionResolution`, keyed by function/specialization identity and source syntax identity. |
| Representation classification caches | `transparentStorageBaseTypeIDs`, `opaqueStorageRepresentationStatuses`, `trackedStorageStatuses`, `optionalTypeStatuses` | Source-graph or type-product indexes keyed by canonical type identity, not one arena allocation. |
| Control flow | `cfgBlocks`, `cfgEdges`, `cfgSchedule`, `controlDecisions`, `controlRegions`, `graphZeroCFGRegions` | `CompilerFunctionCFG`, derived from source nodes and role edges. Block rows may be dense physical indexes, but source syntax identities remain their anchors. |
| Ownership and memory | `storages`, `ownedPaths`, `bindingAliases`, `runtimeCallContracts`, `ownedReturnTransfers`, `memoryFacts`, `memoryState` | `CompilerFunctionOwnership`, derived from resolution plus CFG and retained as one function behavior product. |
| MIR | `mirValues`, `mirBlocks`, `mirOperations`, `mirOperands`, `mirVersions`, `mirExpressionValues`, `graphZeroMIRDependencies`, `graphZeroMIRFrontiers`, `graphZeroState`, `mirTraversal` | `CompilerFunctionMIR`, derived from resolution, CFG, and ownership. |
| Diagnostics | `failures` | Diagnostics emitted by the phase that owns the rejected fact, carrying the stable source syntax identity. |

The direct arena consumers span `CompilerFrontend.range`,
`CompilerParsing.range`, every file under `Compiler/Body/`, and LLVM planning
and lowering. This is why deleting fields one control form at a time would only
move the coupling around.

## Target derivation

```text
 Function.Declaration ──body──▶ Block
              │                  │
              │          nested syntax roles
              │                  │
              └─────────┬────────┘
                        ▼
       specialization / receiver context
                    │
                    ▼
        CompilerFunctionResolution
                    │
                    ▼
            CompilerFunctionCFG
                    │
                    ▼
         CompilerFunctionOwnership
                    │
                    ▼
             CompilerFunctionMIR
                    │
                    ▼
                  LLVM
```

This is one graph with multiple queryable products. The arrows describe data
dependencies, not new parsers. Dense tables remain valid physical indexes when
they make a query cheap; their rows do not replace the stable syntax identity
of the fact they index.

## Historical dual-run proposal

The abandoned in-place migration proposed three execution modes at one central
function-body derivation seam:

- `legacy`: run only the arena pipeline. This preserves the current product and
  supplies the timing baseline.
- `graph`: run only the graph-native products. This is the timing candidate and
  must never create or parse a `CompilerBodyArena`.
- `verify`: derive both from the same syntax tables and specialization context,
  normalize their products by stable identities, compare every phase, and fail
  closed on the first mismatch.

`verify` is correctness evidence, not performance evidence, because it pays for
both runners. Performance comparisons must run `legacy` and `graph` as separate
processes over the same accepted compiler, source inventory, target, and probe
configuration. Record at least wall time, maximum resident memory, body count,
and per-phase totals for source view/indexing, resolution, CFG, ownership, MIR,
LLVM planning, and LLVM emission.

Phase equality is checked at these boundaries:

1. body root, node identities, nesting roles, ordinals, and literal/source
   spans;
2. symbol and call resolutions plus specialized type identities;
3. CFG block anchors, terminators, ordered successors, and statement schedule;
4. storage/path identities, aliases, call contracts, return transfers, and
   memory facts;
5. MIR blocks, values, operations, operands, versions, dependencies, and
   traversal;
6. emitted function artifact and LLVM.

Local row numbers and allocation order are not semantic equality. Each
comparison normalizes rows by its stable source, type, function-instance, path,
or operation identity before comparing values and ordered relationships.

## Historical migration order

This order is retained as evidence, not as the active Compiler B plan:

1. Use the existing `Function.Declaration` syntax identity and its `body` edge
   as the central runner input. Route all twelve parse callers through it
   without changing legacy behavior; keep specialization as separate context.
2. Retain the already-proven syntax-derived CFG as the first graph product, but
   stop expanding it case by case as an isolated project.
3. Move resolution as a whole product, then make the graph CFG consume it.
4. Move ownership as a whole product, including the existing retained function
   behavior facts and call-boundary products.
5. Move MIR as a whole product and make LLVM lowering consume the retained
   graph products.
6. Run isolated `legacy` and `graph` timing trials plus `verify` equality over
   the supported compiler workload.
7. Switch authority only after all phase products and emitted artifacts match.
   Then delete arena parsing, arena-local source identity, duplicate parse call
   sites, and finally `CompilerBodyArena` itself.

The corrected first implementation slice uses the existing function or entry
syntax identity directly; no compiler-only function-body wrapper exists. All
twelve callers enter one legacy derivation boundary, and all arena construction
is now behind declaration, function-instance, entry, macro, or closure legacy
adapters. Ordinary functions and entries validate their declaration-to-Block
edge, file, and exact source span before the remaining parse. Specialization
identity, receiver type, and type arguments are passed independently rather
than being folded into source identity.

Function legacy derivation now accepts only the `Function.Declaration` syntax
identity as its source input. The adapter resolves the disposable function-table
row internally and fails closed when the identity has no function facet. Callers
no longer pass a positional `functionRow` beside the declaration identity;
function-instance identity, receiver key, and type-key tables remain separate
specialization context.

Typed declaration capture now always records the function-to-Block identity
during the early source graph pass, even when block contents are not requested.
Full contents capture remains an explicit policy until its grammar reaches
parity with the legacy runner; an unsupported statement must not erase the
declaration's body identity or reject an otherwise valid legacy compilation.
A development candidate proved canonical Core plus local, member,
returned-binding, and multi-alias-return bodies. That run also proved the
general postfix correction for binding-reference member chains, then stopped at
the known missing `if` else-region capture. After separating Block identity from
contents completeness, the rebuilt development candidate passed the complete
binding-reference and value-ownership suites, macro linking and execution,
native macro integration, generated functions, Registrable, committed macro
expansion, macro arrays, exact typed body replay, and native smoke. The broader
audit stopped at the checkout's existing direct-`@many` unresolved-macro
boundary; no reproduction or fixed point ran.
Macro and closure executable bodies remain explicit legacy-only boundaries
until Core gives those surfaces declaration-to-Block relationships. They must
not acquire manufactured syntax identities from arena rows.

The shared capture now retains nested `if`/`else` and `while` regions, grouping,
prefix operations, doubles, indexing, and every binary operator accepted by the
shared expression parser. `FunctionDeclarationBodyCoverage.range` proves 69
syntax identities, 61 body nodes, and 61 role edges across that surface. The
syntax-derived CFG now consumes local bindings, assignments, complete shared
expression evaluation order, `if`/`else` merges, and `while` backedges as one
product. `FunctionDeclarationCFG.range` normalizes to the legacy product at 7
blocks, 8 edges, and 22 scheduled actions with one backedge. The comparison
normalizer deliberately ignores arena-local Block ordinals: shared Block
identity is its stable source span and relationship role, while the legacy
parser's `else = 1` ordinal is disposable allocation detail.

CFG snapshot failure telemetry now distinguishes construction failure from
product mismatch. A mismatch retains both graph and legacy block, edge, and
schedule tables instead of collapsing the evidence into one generic error.
Array literals now enter through the shared expression parser as one
`ArrayLiteral` identity with ordered `arrayElement` relationships. The focused
body-coverage fixture proves three retained elements followed by an index
expression; legacy `[Element]` collection types remain intentionally rejected,
so the fixture uses canonical `Array<Element>`.

Interpolated strings now retain one source-backed `InterpolatedString` identity
with ordered `interpolationPart` relationships. Literal spans become
`StringSegment` identities directly; embedded expressions use the existing
shared expression parser within their delimited source span. This deliberately
avoids adding a second recursive owned-String record path to the transitional
`CompilerExpression` carrier. The normalized product exactly matches the legacy
one-block, zero-edge, six-action CFG.

The remaining source-capture boundary is explicit: `break`, `continue`,
`switch`, trailing closures, and macro executable bodies still enter only
through the richer legacy parser and therefore keep the graph runner from
becoming authority.
