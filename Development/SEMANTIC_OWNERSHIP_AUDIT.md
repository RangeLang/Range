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
- Compile-time value execution needed to run Range-authored macro bodies.
- Current context boxes for declarations, applications, and graph views.
- Artifact file writing in `RangeCompiler/Sources/RangeEmission/CapabilityLLVMEmitter.swift`.

## Range-Owned Semantics

- `@main` executable meaning in `RangeCompiler/Range/Foundation/Macros/Main.range`.
- Macro declaration surface in `RangeCompiler/Range/Foundation/Macros/Macro.range`.
- Primitive marker surfaces such as `@integer`, `@bool`, `@string`, and `@void`.
- Core syntax and library declarations under `RangeCompiler/Range/Core`.

## Removed Swift Semantic Paths

- Swift workspace emission.
- Generated `RangeGenerated` package emission.
- Swift backend source rendering.
- Scalar LLVM lowerability and statement lowering as an active backend.
- `llvmMain(body:)` Swift-side main rendering.

## Remaining Swift Semantic Risk

- The parser still has declaration and expression models beyond a pure macro tree.
- The compile-time evaluator still knows concrete operations such as strings,
  arrays, graph lookup, filesystem/project helpers, and user-function calls.
- `DeclarationGraph` still materializes Range declarations into Swift structs.

The next reduction target is to make those remaining Swift models serve generic
macro execution only, with Range-authored macros deciding which records or
artifacts exist.
