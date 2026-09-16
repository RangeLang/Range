# C-first compiler handoff

Date: 2026-09-14
Checkout: `/Users/george/Documents/Range`
Branch: `development`; observed HEAD: `c87c20cfc`.

The work described here is uncommitted. The worktree contains earlier changes
from this conversation as well as the latest simplification; preserve them.
No commit or push was made by the cleanup or this handoff.

## Decision and motivation

George wants fast native-program iteration so he can test memory management and
other language behavior. Self-hosting, seed verification, and compiler fixed-point
proofs are no longer goals for the normal development loop. His old multi-minute
loop included seed verification and staged self-compilation; do not present that
as a measured cost of compiling a small Range program.

Keep C as the compiler implementation. Keep Core as the source of language-level
definitions and rules. Stop building a runtime self-description system before
there is a usable native path. Self-hosting is deferred, not promised to be a quick
or automatic transition later.

## Active pipeline

`Range sources → C parser → Core-backed graph resolution → optional text dump`

Native ARM64/Mach-O emission is **not implemented**. Successful resolution does
not create a runnable executable. The old `result=42` demonstration came from an
interpreter that has now been retired; do not use it as native-compilation proof.

- Normal invocation now performs graph resolution, not just parsing.
- `--emit-graph DIRECTORY` uses the same resolution path, then formats its result.
- `--tree` intentionally remains a raw parser inspection command.
- `--match-literal MACRO TEXT` remains a separate recognition-only diagnostic.
- `--run` and `--graph-types` are removed and rejected as unsupported options.
- Core is supplied explicitly as an input; it is not automatically added.

## What was retired

- Runtime-loaded `Language/Compiler/Types` definitions for Construct, Function,
  Macro, Member, and Return.
- The type-template parser and Return syntax-template matching. Return syntax is
  recognized directly by C again.
- The ordinary-program interpreter, its execution helpers, and evaluator gate.
- Template-only tests and automatic schema-definition text emission.

Recovery copies are under `Development/DeferredCompiler/CPrototype/`. Its
`compiler.c` is a snapshot from before interpreter removal. Nested Language and
Testing directories preserve retired templates, template fixtures, and the
evaluator script. They are historical files, not active build inputs or runnable
gates. Earlier evaluator fixtures elsewhere in Testing are not native proof.

The old top-level generated schema views were moved from `Language/.range/Build`
to `Language/.range/Build/RetiredSchemaViews`. Historical nested build directories
may also contain stale views; they are not authoritative.

Core's `Int.range`, `Integer.range`, and `Literal.range` were kept. The draft
`macro integer(value: @literal)` was already reverted with George's approval;
the current declaration is parameterless and retains `@literal("[0-9]+")`.

## What remains implemented

- C-owned reflective field descriptions, initialized by `rangeGraphInitTypes` in
  `model.c`. These retain structural checks and query permissions without loading
  Range template files. Some internal names/diagnostics still use graph-type
  terminology; that is not an external template dependency.
- Per-application resolution of parameterless macros attached to constructs.
  Original definitions and selected member-node identities are preserved.
- `#target`, member/generic selection, `filter(named:)`, `first`, and member values.
- Macro-body resolution views: `#body.members` and `#body.environment`. The old
  root-level `#members` and `#environment` queries are no longer supported.
  `#environment { ... }` block syntax remains unchanged. Other macro statements
  stay parsed and deferred, rather than being executed by this view.
- Plain output names on top-level non-generic functions link to loaded top-level
  constructs. Missing names, specialization, and nested-scope lookup are deferred.
- C-backed POSIX extended regex recognition from Core's literal macro, requiring
  a whole-input match. Recognition is separate from conversion.
- A literal-bearing Core macro must have exactly one attached top-level Core
  construct as its default. Project attachments do not override it. Missing or
  duplicate defaults and overlapping matches are rejected.
- Parsed number/boolean nodes can link to that Core default, including literals
  within the construct itself. Linking does not recursively instantiate it.
  Bool behavior is covered by fixtures; this work did not add Bool to active Core.
- Source-only graph views show functions, returns, macro resolution, and plain
  numeric/boolean literals. Resolved members still have `Member { ... }` wrappers;
  simplifying those wrappers was discussed but not implemented.

## Code map

- `Language/Compiler/Source/lexer.c`: tokenization.
- `parser.c`: source syntax and node construction; no graph-template parser.
- `model.c` / `model.h`: arena, shared nodes, C-owned shapes and field adapters.
- `compiler.c`: source loading, resolution, literal rules/defaults, CLI. The
  remaining `Resolver` context is not an ordinary-program interpreter.
- `graph.c`: optional formatting of the same graph, never compiler input.
- `Language/Compiler/README.md`: current command contract and limits.

## Verification and local timing

These passed after the cleanup:

```sh
Testing/Tools/check-compiler-parser
Testing/Tools/check-compiler-graph
Testing/Tools/check-compiler-literal
git diff --check
```

Graph and literal gates run ordinary and AddressSanitizer/UndefinedBehaviorSanitizer
builds. Coverage includes pointer identity, macro context isolation, normal-command
resolution errors, retired-command rejection, no schema files in fresh graph
output, literal defaults, and regex successes/rejections. CI now runs these gates,
not the retired evaluator gate. Shell syntax checks passed too.

One local measurement: rebuilding the C compiler took 0.70 seconds. Resolving Core
plus the two function fixtures (five sources total) rounded to 0.00 seconds with
`time -p`. This is a small resolution measurement, **not native compilation time**
or a throughput benchmark.

## Resume commands

```sh
Language/Compiler/Tools/build-range-compiler Language/.range/Build/range-compiler
Language/.range/Build/range-compiler Language/Core Testing/Compiler/Graph/Functions
Language/.range/Build/range-compiler --emit-graph Language/.range/Build Language/Core Testing/Compiler/Graph/Functions
```

The normal command reports `resolved-sources=... failures=0`. The graph command
writes Int.txt, Integer.txt, Literal.txt, Start.txt, and Returns.txt for these inputs;
it does not emit compiler schema files.

## Next milestone

Finish one real graph-to-native path:

```range
function start(): Int {
    return 42
}
```

Consume the resolved output construct and integer macro relationships, validate
the actual returned value against the representation, emit ARM64 instructions
and an executable, and run it. The declaration's default `0` is not the returned
`42`. Do not replace this with an interpreter result or a hardcoded constant stub
that bypasses Core, and do not rebuild the template/self-hosting machinery first.

General macro execution, validation statements, literal conversion, return-type
compatibility, memory-management semantics, and native emission are still missing.
Surface any required Core semantic decision before inventing it. Keep subsequent
proofs narrow, measured, and explicit about which of those gaps they actually close.
