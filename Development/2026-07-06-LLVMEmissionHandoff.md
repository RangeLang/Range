# LLVM Emission Handoff - 2026-07-06

## Current Direction

The active execution path is:

```text
Range source
-> Range script runner (Bash)
-> SwiftBootstrap compiler host (Swift)
-> Range compiler pipeline (Swift)
-> Range LLVM emitter (Swift)
-> LLVM IR
-> SwiftBootstrap clang link
-> SwiftBootstrap native executable launch
```

The goal is still active. `SwiftBootstrap` is the stage-0 compiler target:
Swift remains the current compiler host, but generated Swift package workspace
execution is no longer the desired or active program execution path.

## Latest Work Completed

- Removed the stale checked-in artifact snapshot surface:
  - `RangePlayground/.range/Artifacts/03-graph.txt`
  - `RangePlayground/.range/Artifacts/04-graph.html`
  - `RangePlayground/.range/Artifacts/Package/01-tokens.txt`
  - `RangePlayground/.range/Artifacts/Package/02-ast.txt`
  - `RangePlayground/.range/Artifacts/Playground/01-tokens.txt`
  - `RangePlayground/.range/Artifacts/Playground/02-ast-error.txt`
  - `RangePlayground/.range/Artifacts/Playground/02-ast.txt`
- Removed `CompilationArtifactsEmitter` (Swift), which was not part of the
  active script-driven LLVM executable path.
- Removed the disconnected materialized `ApplicationGraph` projection and graph
  renderer. Validation now stays on the active declaration/source pipeline.
- Removed `Testing/CompilePass/System/RangeSelfPortrait.range`, which read a
  hardcoded `.range/Artifacts/03-graph.txt` artifact.
- Updated `Testing/README.md` to describe the current runnable LLVM example
  surface and manifest gate instead of treating runnable coverage as only a
  future fixture category.
- Added the first self-hosting lane checkpoint:
  `RangeCompiler/Range/Programs/Compiler/Main.range` builds and runs as a
  native `Compiler` binary through `SwiftBootstrap`, then calls its
  Range-authored lexer library for a Range source file and prints a deterministic
  token stream. The lexer is a small direct port of the Swift bootstrap lexer
  path, with a focused test comparing native output against the Swift bootstrap
  lexer stream. The compiler also parses the first tiny AST checkpoint: an
  `@main` block summary plus top-level function declaration summaries with body
  bounds. The parsed `@main` block now lowers to a stage-2 synthetic `main`
  function summary, and direct `return <integer>` in that body emits the first
  Range-authored LLVM text checkpoint.

## Active Validation

The following checks pass after the latest cleanup:

```sh
swift build --package-path RangeCompiler --product range
swift test --package-path RangeCompiler --filter RangeScriptTests
swift test --package-path RangeCompiler --filter SwiftBootstrapTests
scripts/range check-bootstrap-compiler
scripts/range check
```

`scripts/range check` currently runs all 148 examples in
`RangePlayground/Examples/LLVM/run-manifest.tsv` and passes.

The checked examples cover the active executable path across functions, calls,
Void calls, constructs/fields, strings, arrays, enums, control flow, primitives,
file I/O, stdin, command-line arguments, and stdout.

## Important Caveat

Do not use the broad `CompilerFixtureTests` suite as the immediate green gate
for this LLVM-emission cleanup. A combined run of `CompilerFixtureTests` and
`RangeScriptTests` surfaced existing macro/graph fixture failures unrelated to
the artifact deletion, including rewrite-site descriptor and synthesized
extension/conformance expectations.

The active gate for runnable Range programs is the Range script runner (Bash)
plus `SwiftBootstrap`/Range LLVM emitter path validated by `scripts/range check`.
`SwiftBootstrap` now owns the run manifest checks behind that script entrypoint.

## Stage-0 Boundary

`SwiftBootstrap` should be treated as temporary trusted compiler code. Keep code
there when it is required to turn Range source into LLVM, a native executable, or
a directly launched stage-0 process today. The run manifest is part of that
stage-0 boundary because it is the active executable truth; the emit-only corpus
check is also stage-0 validation. Delete old generated-Swift execution, SwiftPM
workspace, and stale artifact plumbing when it is no longer part of that
stage-0 path. As the Range-authored compiler gains coverage, equivalent
`SwiftBootstrap` behavior can become dead code.

## Next Best Targets

1. Continue deleting disconnected Swift-owned compatibility paths that are not
   used by `scripts/range check`.
2. Audit remaining Swift semantic ownership in `RangeCompiler/Sources` and
   separate:
   - required compiler host mechanics
   - Range-authored semantic surfaces
   - stale test-only or artifact-only paths
3. Keep expanding `RangePlayground/Examples/LLVM/run-manifest.tsv` only when a
   new runnable behavior lands. The manifest should remain the executable truth
   for the active path.
4. Avoid reintroducing generated Swift package workspace execution unless it is
   explicitly requested for archaeology.
