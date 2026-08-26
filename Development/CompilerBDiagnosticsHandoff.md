# Compiler B diagnostics and self-hosting handoff

## 2026-08-24

## Current direction

Compiler B now reports *where* and *why* a project source fails, and reports
every failing source in one run instead of aborting on the first. That turned
the open-ended "make B self-host" program into a finite, empirically derived
gap list.

Running B against its own source tree is the measurement:

```sh
scripts/run-compiler-b-bootstrap Projects/RangeCompilerB
```

## The gap list

```text
Projects/RangeCompilerB/Project.range:2:1: unable to store syntax node
.../Core/Macros/Member.range:1:1: unable to store syntax node
.../Core/Project/LLVM.range:69:1: Compiler B does not accept generic syntax; express the relationship through the graph
.../Core/Project/Revision.range:1:1: unable to store syntax node
.../Core/Representation.range:1:1: unable to store syntax node
.../Core/String.range:2:1: unable to store syntax node
.../Core/String/String.range:3:1: unable to store syntax node
.../Core/Syntax/Declaration.range:15:1: unable to store syntax node
.../Core/Syntax/Parser.range:2142:1: Compiler B does not accept generic syntax; express the relationship through the graph
.../Core/Syntax/Query.range:598:1: unable to store syntax node
.../Core/Syntax/Token.range:22:1: unable to store syntax node
.../Core/System/Memory/Buffer.range:2:1: Compiler B does not accept generic syntax; express the relationship through the graph
projectSyntax	valid=false	failures=12
```

Twelve failures, three causes:

- **Ten are `Buffer<...>` generics.** Generics in a member (`let kinds: Buffer<Int>`)
  surface as `unable to store syntax node`; generics in a signature
  (`syntaxIDs: Buffer<Int>`) surface as the explicit generic rejection. One
  blocker wearing two messages. The rejection is deliberate design — the
  diagnostic itself says "express the relationship through the graph."
- **`Core/Macros/Member.range`** uses union return syntax
  (`macro member(): Let | State | Derived | Binding -> Value`), which the parser
  does not admit.
- **`Core/String/String.range`** is the aspirational `@many`-based String
  (`construct String { @many state value: Unicode }`).

## Consequence for dropping Compiler A

B's self-hosting blocker is `Buffer<Element>` — the same fake-generic wrapper
that `@many` is meant to replace. Every `Buffer` operation bottoms out in
`@builtin` declarations that are holes into `RangeRawBuffer.c`:

```range
@builtin(.storage) construct RawBuffer {}
@builtin(.create)  function rawBufferCreate(capacity: Int, stride: Int): RawBuffer
@builtin(.write)   function rawBufferAppendInt(buffer: RawBuffer, value: Int): Int
```

`Buffer<Element>` is not truly generic — `append`, `element`, and `update` all
call the `...Int` variants. It is scaffolding wearing a type parameter.

Dropping the C runtime and dropping Compiler A remain **separate** projects: B
can self-host while still linking `RangeRawBuffer.c`. But the `@many` migration
is *not* optional for dropping A, contrary to an earlier reading in this
session — it is the critical path.

The migration is currently blocked. B's source performs:

```text
 417  .element(index:
 363  .append(
 238  .count
```

1,018 call sites, and `@many` supplies none of those operations yet.

## Design conclusions reached

**`count` is a member, not a verb.** `%Range.Many.T = type { ptr, i64, i64 }`
already carries count as field 1. Reading it is ordinary construct member
access, not a special operation and not an LLVM escape hatch.

**Transformations are authored in Range, not in LLVM strings.** `Bool.range`
already shows the form:

```range
@collectionModifier
macro isEmpty(): @many -> Bool {
    #environment.target.count == 0
}
```

A proposal to add `LLVM(instructions: ...)` for verb bodies was rejected as
making the escape hatch the mechanism instead of making the language richer.

**Macro versus function splits on what the thing operates on.** Syntax
(declarations, members, applications) is macro territory, evaluated at
expansion. Values (a live `%Range.Many.Int`) are function territory, evaluated
at execution. This dissolves the `.count` ambiguity — the compile-time form
lives on `#environment`, the runtime form is member access — rather than
requiring disambiguation machinery.

**Ordering should be derived, not hand-sequenced.** A materialization/macro
graph derived once from the retained declaration and application graph
determines emission order. Tagging collected products with a kind and sorting
them is the wrong shape for the same reason the LLVM strings were.

## Open decisions

- **`i32` -> `i64`** on the Many struct. Written in exactly one place, in
  `Core/Macros/Many.range`. Element stride math is `shl nsw i64 %cap, 3`;
  `i32` counts truncate past 2GB. Cheap now, invasive after call sites exist.
- **By reference or by value.** Growth mutates ptr, count, and capacity
  together. By reference makes every verb GEP-shaped; by value makes `count`
  an `extractvalue` and `append` return a whole new struct. This determines the
  shape of all four verbs and is forced by the 1,018 call sites above.
- **Where a `@many -> Bool` transformation lands.** Only two emission channels
  exist today, `channel=Declaration` and `channel=Application`. A transformation
  consumes a value and yields a value and is neither. Open whether that is a
  genuine third channel or falls out of the materialization graph as an
  ordinary call once member access works.
- **`#environment` versus `Graph`.** All of the above is written against
  `#environment.target.Declaration`. If the single `Graph` construct is
  landing, this work should target that spelling rather than entrench
  `#environment` deeper.

## Naming settled

`@collectionModifier`, no dot. `Bool.range` was the lone holdout using
`@collection.modifier` and declared no marker at all, so its five applications
resolved to nothing. It now declares `macro collectionModifier(): Macro {}` and
matches `Many.range` and `ApplicationExecution.range`. Composition and
namespacing are deferred.

## Compiler A ownership-prover constraints

Learned the hard way while writing the diagnostics; all three cost real time:

- A received `String` parameter **cannot be forwarded** as an argument to
  another function (`invalidFunctionReachability`).
- An accumulator **cannot be returned** from a function that also parses a
  revision (`invalidOwnedReturnSummary`). Build the text in a function that
  only reads, or report through `print` and return an `Int`.
- `source` **cannot be read after** the parser consumes it. Read it back
  through `revision.source`.

The working shape is: return `Int`, print located messages as they are found,
and read source text through the revision.

## Suite state

`scripts/check-range-compiler-b` **was already red at HEAD** (`8c97da54`),
failing at the collection modifier assertion. It was not green before this
session and is not green now.

What changed is that failures became visible. The single-file route previously
exited `0` on an invalid verdict; routing through the project entry propagates
`65`. That exposed four layers of latent breakage in a row:

1. Two macro-resolution assertions expecting the old `diagnostic=` render field.
2. `Testing/CompilerB/Pass/MemberMacroTarget.range` declared
   `macro values(): @member -> String {}` with an empty body, while a collection
   production requires its selector macro to emit an application matching the
   output identity. Failing at HEAD too, silently. Fixed by giving it an
   emitting `#environment` body, mirroring `CollectionProduction.range`.
3. Two member facet assertions predating the `initializer=` / `body=` fields.
4. **Eleven rejection-fixture invocations that never captured their exit code.**
   Under `set -euo pipefail`, a correctly-rejected fixture returning 65 killed
   the script before its own assertion ran. Guarded with `|| true`; the
   following `grep` still asserts the exact diagnostic.

## Unresolved at handoff

- `compilerError kind=invalidFunctionDiscovery functionRow=89
  function=compilerBRenderSourceTemplate failureCode=1` — A failing to compile
  `Core/Representation.range`, which is unmodified and in the compiled
  manifest. Appeared only after the earlier layers cleared; not present at HEAD
  or in the previous run. A `bash -x` trace was running at handoff to identify
  the triggering invocation.
- The process graph is empty for `MemberMacroTarget.range` in the working tree
  where HEAD emitted `application`, `processLocal`, `processExecution`, and
  `processResult` rows. It did not cause the collection production failure, but
  it is a real representational change from the members-to-facets work and has
  not been confirmed intentional.

## Files changed

Compiler:

- `Core/Syntax/Parser.range` — `diagnosticStart` tracked at each in-loop failure
  site, carried through the single revision construction site.
- `Core/Syntax/Declaration.range` — `diagnosticStart: Int` on
  `CompilerBSyntaxRevision`.
- `Core/Project/Revision.range` — fail-soft population returning a failure
  count; `compilerBProjectReportSyntaxDiagnostics` and
  `compilerBProjectReportResolutionDiagnostics` as read-only reporting passes;
  packed-status decoders removed.
- `Main.range` — both project entry points rewired.
- `Core/Macros/Bool.range` — `@collectionModifier` spelling plus the marker
  declaration.

Tests:

- `scripts/check-range-compiler-b` — located-diagnostic assertions, member facet
  fields, `|| true` on 11 rejection fixtures, modifier count 2 -> 4, undotted
  spelling.
- `Testing/CompilerB/Pass/MemberMacroTarget.range` — emitting macro body.

Nothing committed.

## Suggested next step

Fix the `compilerBRenderSourceTemplate` compile failure first — it blocks the
suite entirely. Then settle the by-reference/by-value question, since it gates
every verb template, and widen the Many struct to `i64` while it is still a
one-line change.
