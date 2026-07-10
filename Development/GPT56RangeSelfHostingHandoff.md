# GPT 5.6 Range Self-Hosting Handoff

Repo: `/Users/george/Documents/Range`

Continue the Range self-hosting goal. Stage0 SwiftBootstrap should stay frozen/plumbing. The target path is:

```text
Range source -> Range-authored AST/declaration/type records -> direct LLVM -> linked Stage2 -> Stage2 emits Stage3 -> compare Stage2/Stage3.
```

## Current Blocker

Stage1 builds, but Stage2 native compiler emission has been failing during selected helper rendering/lowering because the generated compiler allocates too many temporary strings.

Evidence:

- Native source-set parse succeeds.
- Reachability succeeds.
- Selected rendering is the bottleneck.
- Bounded selected rendering:
  - 50 funcs passes
  - 100 funcs passes
  - 200 funcs passes
  - 300 funcs aborts with memory failure

## Recent Changes

Added diagnostics:

- `compilerNativeSourceSetParseStats`
- `compilerNativeSourceSetReachableStats`
- `compilerNativeSourceSetSelectedStats`
- `compilerNativeSourceSetSelectedScanStats`
- `compilerNativeSourceSetSelected50Stats`
- `compilerNativeSourceSetSelected100Stats`
- `compilerNativeSourceSetSelected200Stats`
- `compilerNativeSourceSetSelected300Stats`

Refactored selected helper rendering into chunked record processing.

Added chunked native LLVM directives:

- `compilerNativeSourceSetLLVMHeaderText`
- `compilerNativeSourceSetLLVMChunkCount`
- `compilerNativeSourceSetLLVMChunkText<N>`
- `compilerNativeSourceSetLLVMFooterText`

Updated SwiftBootstrap to assemble Stage2/Stage3 LLVM from chunks instead of one monolithic `compilerNativeSourceSetLLVMText` call.

## Validated

- `git diff --check` passes.
- `swift build --package-path RangeCompiler --product range` passes.
- `scripts/range check-stage1-compiler RangeCompiler/Range/Programs/Compiler` passes.
- Direct chunk protocol test works:
  - header works
  - chunk count returns `14`
  - chunk 0 emits about `69KB`
  - footer emits declarations/main

## Interrupted

A full Stage2 gate was started:

```sh
/usr/bin/time -l scripts/range check-stage2-compiler RangeCompiler/Range/Programs/Compiler
```

It was manually interrupted after about `582s`, so there is no final Stage2 pass/fail yet.

## Next Step

Run the full Stage2 gate again:

```sh
/usr/bin/time -l scripts/range check-stage2-compiler RangeCompiler/Range/Programs/Compiler
```

If it fails, inspect whether a specific chunk failed, then test individual chunk directives:

```text
compilerNativeSourceSetLLVMChunkText0
...
compilerNativeSourceSetLLVMChunkText13
```

If chunks still memory-fail, reduce `compilerNativeSourceSetLLVMChunkLength` from `500000`.

## Important

Do not restart the architecture debate. This is not conceptually blocked on lexer/parser. The current issue is finishing stable chunked Stage2 LLVM assembly and then cleaning temporary diagnostics once the gate is green.
