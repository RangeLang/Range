# C Core compiler reset handoff

## 2026-09-14: C-first iteration supersedes prototype template work

The active C compiler no longer loads graph-type or syntax templates and no longer
contains the ordinary-program interpreter. Normal invocations parse and resolve;
text output is optional inspection of that path. Core remains the source of
language-level definitions. Native emission is still unfinished. Retired components
are recoverable in `Development/DeferredCompiler/CPrototype`. Earlier sections
below describe historical milestones, not the current command contract.

Date: 2026-09-12

## Direction

Range Core remains written in Range. The compiler is now intended to be written
in C and to emit target bytes directly, without LLVM. The Range program graph is
the semantic representation consumed by target lowering. Compiler generations,
self-hosting, frozen seeds, and a separate recovery compiler are no longer part
of the active architecture.

Work is deliberately focused on integer representation. Collection storage must
not be resumed until the scalar representation path is coherent.

## Design conclusion — 2026-09-13

**Not everything is a macro. Everything in Core is abstract.**

Core describes constructs, members, values, relationships, and behavior. Macros
are one part of that description: they inspect and operate on the graph. A
construct does not have to become a macro to participate in the same model.

Here, abstract means that Core describes meaning independently of a particular
machine representation. It does not mean that values cannot become concrete,
that constructs cannot have instances, or that all behavior runs at compile
time. The C compiler resolves and evaluates the graph and will lower the
required behavior and storage to target bytes.

The graph is the shared representation. Its `@type` templates define available
fields and multiplicity; Core supplies the semantic rules. A member retains its
defining expression, while each macro application has its own resolution
context. Resolving a member does not replace its definition.

This closes the question of whether everything must be a macro. The remaining
work is implementing Core behavior through the graph. Field resolution and
graph-shape checks are implemented; full macro validation, expansion execution,
instance specialization, and target-byte emission remain unfinished.

The reset history below records the earlier checkpoint and handoff state.

## Checkpoint

The complete pre-reset workspace was committed before destructive restructuring:

```text
e0823c819 Capture Range Core design iteration
```

This commit contains all tracked and previously untracked work that existed at
the reset boundary.

## Current uncommitted reset

The working tree after the checkpoint contains the structural reset and is not
committed. At handoff time:

```text
342 files changed, 214 insertions, 58,636 deletions
338 status entries
```

The main changes are:

- Removed `Language/Bootstrap` and its compiler generations, manifests, seeds,
  generated compiler artifacts, and bootstrap tools.
- Removed the Range-written compiler formerly under `Language/Compiler`.
- Removed the old `Language/CLI`, distribution artifacts, installer, compiler
  fixtures, seed surgery code, self-host checks, and historical compiler plans.
- Promoted the C lexer, parser, evaluator, host support, and build tool to
  `Language/Compiler`.
- Renamed recovery tests and tools to compiler tests and tools.
- Removed the source manifest. Core consists of every `.range` file recursively
  under `Language/Core`, discovered directly by the C compiler's directory loader.
- Moved the other 64 Core sources and their meaning documents to
  `Development/DeferredCore`. Active Core contains only `DataTypes/Int.range`
  and `Macros/Integer.range`, alongside repository guidance.
- Updated the root README, `Language/README.md`, and the GitHub workflow for
  the C compiler architecture. Removed the redundant root `package.json`;
  checks run directly through their shell tools.
- Deferred old project declarations, inactive compiler fixtures, benchmark
  implementation, and inherited runtime under `Development/DeferredCompiler`.
  The active C build discovers `Source/*.c` and uses a small evaluator index
  buffer plus standard C output in place of the old host and metrics layers.
- Removed stale recovery/compiler paths from the active Core meaning documents.

The active structure is:

```text
Language/
  Core/          language semantics written in Range
  Compiler/      compiler implementation written in C
```

The ignored historical compiler outputs were moved, rather than permanently
deleted, to:

```text
/Users/george/.Trash/Range-old-compiler-e0823c81
```

That directory contains about 4.3 GB of former compiler builds, progression
artifacts, native seeds, bootstrap artifacts, and diagnostics. The tracked
pre-reset state is also recoverable from the checkpoint commit.

## Verification

The focused command is:

```sh
Testing/Tools/check-compiler-parser
Testing/Tools/check-compiler-evaluator
```

It currently passes with:

```text
compiler parser: sources=2 nodes=203 construct=1 enum=0 function=1 macro=1 main=0 failures=0 int-structure=pass malformed=pass directory=pass
compiler evaluator: ordinary passes=6 rejections=48
compiler evaluator: sanitized passes=6 rejections=48
```

Both staged and unstaged `git diff --check` pass. The parser check passes the Core
directory directly to the compiler. Directory inputs are recursive, sorted, and
deduplicated before all sources are parsed into the existing syntax graph.
The evaluator fixtures explicitly load deferred Byte, Bool, and String
declarations; their passing results do not prove execution of `@integer`.

## Integer design boundary

Current Core declarations:

```range
@integer
construct Int<let bits: 64, let signed: true> {
    let value: 0
}
```

The intended relationship is:

```text
target construct: Int specialization
payload member: value
width: effective bits argument
signed interpretation: effective signed argument
```

`let value` can still be physically represented. `let` governs mutation of the
member; it does not mean that the member has no storage. Mutation of an integer
held by another construct belongs to the outer `state` member.

The C compiler must eventually derive the integer relationship by executing Core,
then consume the resulting graph fact generically. It must not lower integers by
recognizing the spellings `Int`, `integer`, `value`, or `bits`.

The agreed representation is the relationship between `@integer` and each
concrete `Int` application. The macro validates the value against effective
width and signedness constraints. Its target and bindings remain available in
the graph for each application; no separate `IntegerRepresentation` result is
required. Executing this relationship and lowering it remain implementation
work. Do not resume Array/collection storage yet.

## Active files

- `Language/Core/DataTypes/Int.range`
- `Language/Core/Macros/Integer.range`
- `Language/Compiler/README.md`
- `Language/Compiler/Source/`
- `Language/Compiler/Tools/build-range-compiler`
- `Language/Core/` (all Range sources recursively)
- `Testing/Tools/check-compiler-parser`
- `Testing/Tools/check-compiler-evaluator`

## Previous assistant message

The following is the complete previous assistant response requested for this
handoff:

> Created checkpoint commit `e0823c81` (`Capture Range Core design iteration`).
>
> The structural reset is now in the working tree:
>
> - Removed `Language/Bootstrap`, the Range-written compiler, frozen seeds, LLVM/bootstrap tooling, old compiler fixtures, distribution artifacts, and historical compiler plans.
> - Promoted the C implementation to [Language/Compiler](/Users/george/Documents/Range/Language/Compiler/README.md).
> - Replaced the compiler manifest with [CoreSources.txt](/Users/george/Documents/Range/Language/CoreSources.txt), containing exactly the 66 current Core sources.
> - Renamed the build and validation paths around the C compiler.
> - Updated the root documentation, workflow, and npm test command.
> - Moved 4.3 GB of ignored compiler/seed artifacts to `/Users/george/.Trash/Range-old-compiler-e0823c81`, so they remain recoverable.
> - The reset currently removes 263 files and about 58,000 lines. It remains uncommitted for review.
>
> Validation passes:
>
> ```text
> Core parse: 66 sources, failures=0
> Int structure: pass
> Malformed syntax rejection: pass
> C evaluator: 6 passes and 48 rejections
> ASan/UBSan: 6 passes and 48 rejections
> git diff checks: clean
> ```
>
> The next integer decision is now isolated: should `@integer` return an explicit graph value such as `IntegerRepresentation`, making its signature conceptually:
>
> ```range
> macro integer(): Construct -> IntegerRepresentation
> ```
>
> with `value`, `bits`, and `signed` as its relationships? That is my recommendation because the C lowering can consume the result generically without recognizing `Int` or `integer` by name.
>
> <oai-mem-citation>
> <citation_entries>
> MEMORY.md:784-800|note=[Used the previous recovery boundary to identify architecture being superseded]
> MEMORY.md:7508-7512|note=[Used prior compiler audit to locate bootstrap and Range-written compiler surfaces]
> </citation_entries>
> <rollout_ids>
> 01a06de2-b37a-7850-a7bc-e1068b3de553
> </rollout_ids>
> </oai-mem-citation>
