# Handoff

## Objective
- Keep pushing the `NeatCLI` vs `NeatSyntax` split toward the intended architecture:
  - `NeatSyntax` owns compiler pipeline and semantic validation
  - `NeatCLI` owns file discovery, commands, backend selection, reporting
- Keep Swift as a backend adapter, not the source of Neat semantics.

## What Changed
- Added a real semantic pipeline artifact in `NeatSyntax`:
  - `NeatSyntax/Sources/NeatSyntax/Core/SemanticProgram.swift`
  - `SourceInput`
  - `SourceInputRole`
  - `SemanticProgram`
  - `CompilerPipeline`
- Added semantic validation in `NeatSyntax`:
  - `NeatSyntax/Sources/NeatSyntax/Core/SemanticProgramValidator.swift`
  - `NeatSyntax/Sources/NeatSyntax/Core/SemanticValidationError.swift`
- Added validated compile entry points in `CompilerPipeline`:
  - `buildValidated(inputs:)`
  - `validatePrimaryDeclarations(inputs:)`
- Reduced `NeatCLI` semantic assembly:
  - `NeatCLI/Sources/NeatCLI/ProjectSourceValidator.swift` is now a thin wrapper over `NeatSyntax`
  - `NeatCLI/Sources/NeatCLI/NeatCoreLoader.swift` now builds `SourceInput` and consumes `SemanticProgram`
  - `NeatCLI/Sources/Commands/GraphCommand.swift` now uses `SemanticProgram`
  - `NeatCLI/Sources/Commands/ArtifactsCommand.swift` now uses `SemanticProgram`
  - `NeatCLI/Sources/Terminal/ErrorPresenter.swift` now handles `SemanticValidationError`
- Fixed Swift backend construct emission:
  - `NeatCLI/Sources/NeatCLI/SwiftBackendDriver.swift`
  - `NeatCLI/Sources/NeatCLI/SwiftBackendLowerer.swift`
  - `NeatCLI/Sources/NeatCLI/SwiftBackendEmitter.swift`
- The backend now emits basic Swift `struct` declarations for user constructs such as `Person` and `User`.

## Key Decisions
- Compiler pipeline is documented as:
  1. `Lexer`
  2. `Parser`
  3. `AST`
  4. `DeclarationGraph`
  5. `SemanticProgram`
  6. `MemoryGraph`
  7. `ReactivityGraph`
  8. `BackendLowering`
  9. `Emission`
- `DeclarationGraph` is in front of backend lowering.
- `SemanticProgram` is the first semantic artifact boundary, not a replacement for `DeclarationGraph`.
- Swift backend is target adaptation only.
- Literal semantics are declaration-graph driven; backend scalar collapse is Swift-only adaptation.
- Current long-term goal is backend swappability: Swift now, C/C++ or native later, without disturbing front-end compiler flow.

## Current State
- `NeatSyntax` now owns:
  - parsing inputs into a semantic artifact
  - declaration graph construction
  - semantic validation
- `NeatCLI` now more cleanly owns:
  - file discovery
  - `NeatCore` loading
  - commands and reporting
  - backend invocation
- `graph`, `artifacts`, and `compile` all go through the `NeatSyntax` semantic pipeline.
- Generated Swift for `NeatPlayground` now includes:
  - `struct Person`
  - `struct User`
  - `mutating func incrementAge()`
- Still incomplete:
  - Swift backend is still in `NeatCLI`
  - `MainProgramRunner` is still CLI-side interpreter logic over semantic/expanded program state
  - project/package/file discovery is still duplicated across commands
  - `MemoryGraph` and `ReactivityGraph` are still documented architecture, not implemented pipeline stages

## Important Files
- `HANDOFF.md`
- `NeatSyntax/Sources/NeatSyntax/Core/SemanticProgram.swift`
- `NeatSyntax/Sources/NeatSyntax/Core/SemanticProgramValidator.swift`
- `NeatSyntax/Sources/NeatSyntax/Core/SemanticValidationError.swift`
- `NeatSyntax/Sources/NeatSyntax/Core/CompilerPipeline.md`
- `NeatSyntax/Sources/NeatSyntax/GraphBindings/MemoryGraph/DeclarationGraph.md`
- `NeatSyntax/Sources/NeatSyntax/GraphBindings/MemoryGraph/MemoryGraph.md`
- `NeatCLI/Sources/NeatCLI/ProjectSourceValidator.swift`
- `NeatCLI/Sources/NeatCLI/NeatCoreLoader.swift`
- `NeatCLI/Sources/NeatCLI/SwiftBackendDriver.swift`
- `NeatCLI/Sources/NeatCLI/SwiftBackendLowerer.swift`
- `NeatCLI/Sources/NeatCLI/SwiftBackendEmitter.swift`
- `NeatCLI/Sources/Commands/GraphCommand.swift`
- `NeatCLI/Sources/Commands/ArtifactsCommand.swift`
- `NeatPlayground/Playground.neat`
- `NeatPlayground/.neat/Build/swift/Sources/Playground.swift`

## Open Questions
- Should `MainProgramRunner` remain CLI/runtime-specific, or should it consume a more formal `NeatSyntax` semantic interface?
- Should the Swift backend stay in `NeatCLI`, or eventually move behind a backend package/module boundary?
- What is the next clean boundary after `SemanticProgram`:
  - shared project loader/discovery service
  - backend interface
  - interpreter boundary

## Next Step
- Continue the split by centralizing project/package/file loading on the CLI side and reducing duplicate file enumeration across commands, while keeping all semantic compilation behind `NeatSyntax`.

## Verification
- `swift build` in `NeatSyntax` passed
- `swift build` in `NeatCLI` passed
- `./.build/debug/NeatCLI graph /Users/george/Documents/Neat/NeatPlayground` passed
- `./.build/debug/NeatCLI artifacts /Users/george/Documents/Neat/NeatPlayground` passed
- `./.build/debug/NeatCLI compile /Users/george/Documents/Neat/NeatPlayground` passed
- Generated Swift file confirmed at:
  - `NeatPlayground/.neat/Build/swift/Sources/Playground.swift`
- Note:
  - local `swift build` of the generated workspace still hits a host toolchain issue:
    - `unknown argument: '-isysroot'`
  - that is separate from the Neat-side pipeline/split work.
