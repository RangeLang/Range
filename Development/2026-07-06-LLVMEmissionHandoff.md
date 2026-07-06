# LLVM Emission Handoff - 2026-07-06

## Current Direction

The active execution path is:

```text
Range source
-> Range script runner (Bash)
-> range compiler host (Swift)
-> Range compiler pipeline (Swift)
-> Range LLVM emitter (Swift)
-> LLVM IR
-> clang
-> native executable
```

The goal is still active. Swift remains the current compiler host, but generated
Swift package workspace execution is no longer the desired or active program
execution path.

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
- Removed `Testing/CompilePass/System/RangeSelfPortrait.range`, which read a
  hardcoded `.range/Artifacts/03-graph.txt` artifact.
- Updated `Testing/README.md` to describe the current runnable LLVM example
  surface and manifest gate instead of treating runnable coverage as only a
  future fixture category.

## Active Validation

The following checks pass after the latest cleanup:

```sh
swift build --package-path RangeCompiler --product range
swift test --package-path RangeCompiler --filter RangeScriptTests
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
plus Range LLVM emitter (Swift) path validated by `scripts/range check`.

## Current Dirty Files From This Handoff

- `Development/2026-07-06-LLVMEmissionHandoff.md`
- `Testing/README.md`
- deleted stale artifact snapshot files under `RangePlayground/.range/Artifacts`
- deleted `RangeCompiler/Sources/RangeCompiler/Core/CompilationArtifacts.swift`
- deleted `Testing/CompilePass/System/RangeSelfPortrait.range`

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

