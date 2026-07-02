# Semantic Ownership Audit

Current as of the script-driven LLVM path.

## Active Path

```text
scripts/range
-> range compiler host (Swift)
-> Range compiler pipeline (Swift)
-> Range Foundation macros (Range)
-> macro-produced LLVM module text
-> clang
-> executable
```

## Swift-Owned Host Plumbing

- File discovery and source loading in `RangeCompiler/Sources/range/main.swift`.
- Minimal parsing and macro expansion plumbing in `RangeCompiler/Sources/RangeCompiler`.
- The bootstrap `@macro` seed declaration, injected by the parser so hosted
  macro declarations can be parsed before macro self-hosting exists.
- Compile-time value execution needed to run Range-authored macro bodies.
- Current context boxes for declarations, applications, and graph views.
- Artifact file writing in `RangeCompiler/Sources/RangeEmission/MacroLLVMArtifactEmitter.swift`.

## Range-Owned Semantics

- `@main` executable meaning in `RangeCompiler/Range/Foundation/Macros/Main.range`.
- Normal macro declarations authored with `@macro(name: ...)` after the Swift-hosted seed exists.
- Primitive marker surfaces such as `@int`, `@bool`, `@string`, and `@void`.
- Core syntax and library declarations under `RangeCompiler/Range/Core`.

## Removed Swift Semantic Paths

- Swift workspace emission.
- Generated `RangeGenerated` package emission.
- Swift backend source rendering.
- Scalar LLVM lowerability and statement lowering as an active backend.
- `llvmMain(body:)` Swift-side main rendering.

## Remaining Swift Semantic Risk

- The parser still has declaration and expression models beyond a pure macro tree.
- `DeclarationGraph` still materializes Range declarations into Swift structs.

## Compile-Time Evaluator Audit

`CompileTimeValueEvaluator` is the largest remaining semantic pocket in Swift.
It is still required today because Swift executes Range-authored macro bodies,
but its responsibilities should keep moving toward host services and away from
Range language meaning.

### Host Services

- String and array operations needed to run macro bodies.
- File and project source discovery helpers for bootstrap compiler macros.
- Graph/context lookup over the current Swift-hosted declaration graph.
- User macro function execution for Range-authored macro declarations.
- Diagnostics transport for macro validation output.

### Removed

- `llvmMain(body:)` and `LLVM.main(...)` special calls.
- Swift-side construction of an LLVM `main` from statement/value objects.

### Semantic Risks

- Built-in knowledge of concrete object names such as `RangeProject`,
  `ProgramSourceFile`, and graph-related records.
- String/array operations are currently host intrinsics rather than
  Range-authored library behavior.
- User-function execution still depends on Swift expression and statement
  models.
- Graph lookup currently projects Swift declaration structs into macro values.

The next reduction target is to make those remaining Swift models serve generic
macro execution only, with Range-authored macros deciding which records or
artifacts exist.
