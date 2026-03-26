# Handoff

## Objective
- Continue bootstrapping Neat in Swift while keeping Swift minimal and using `.neat` exploration files as the semantic target model.
- Make the compiler pipeline visible through generated artifacts, especially tokens, AST, and dependency graph output in `NeatPlayground`.

## What Changed
- Added Swift-side parsing for `macro` declarations, `Attached<T>` / `Freestanding<T>` targets, and macro body bindings.
- Added thin macro use-site parsing so attachments like `#autoclosure` are preserved in the bootstrap AST.
- Replaced stringly macro target/type handling with a parsed `TypeReference` AST in key Swift paths.
- Added a structural dependency graph plus exact-name type resolution edges in the Swift bootstrap.
- Added `neat artifacts` and artifact generation for tokens, AST, graph text, and graph HTML.
- Allowed `@main` to coexist with top-level declarations in the same file.
- Extended the parser for typed local declarations, local `derived`, and member-chain assignment targets like `person.age += 1`.
- Removed the old `projection` concept from the Swift bootstrap surface.
- Updated the HTML graph artifact to use a static top-down layout with a scrollable canvas and manual node dragging.
- Added a `thread-handoff` skill at `/Users/george/.codex/skills/thread-handoff/SKILL.md`.

## Key Decisions
- Swift is the minimal bootstrap layer, not the permanent semantic authority.
- `.neat` exploration files remain the target language model, but Swift must ground keywords, parsing, and the early graph.
- Some duplication between Swift bootstrap structs and `.neat` language modeling is acceptable for now.
- Macro semantics should stay mostly in the Neat-side model; Swift should primarily parse and carry structure.
- `@main` mixed with declarations is valid and should parse as a module file with `mainBlock`.
- Expression nodes should also be statements; `ExpressionStatement` was removed from the exploration model.
- The HTML graph should be static, top-down, scrollable, and still draggable by hand.
- Use `NeatPlayground` for validation instead of temp files/folders where possible.

## Current State
- `neat artifacts` writes artifacts to `NeatPlayground/.neat/Artifacts`.
- Current artifact set:
  - `Package/01-tokens.txt`
  - `Package/02-ast.txt`
  - `Playground/01-tokens.txt`
  - `Playground/02-ast.txt`
  - `03-graph.txt`
  - `04-graph.html`
- `Playground.neat` currently includes `@main`, `Person`, and `User`, and parses successfully in the bootstrap parser.
- The graph currently captures declaration/containment/type-reference structure and exact-name type resolution.
- The graph does not yet capture body-level dependencies, mutations, or local derived/state relationships inside bodies.
- The parser now accepts constructs like:
  - `state person: Person = ...`
  - `derived personString: String { ... }`
  - `person.age += 1`
- Runtime/execution semantics still lag behind parsing:
  - member assignment/runtime mutation is not fully implemented
  - body dependency resolution is not implemented
- The generated HTML graph is improved, but it is still a declaration graph, not yet a true dependency-flow view.

## Important Files
- [HANDOFF.md](/Users/george/Documents/Neat/HANDOFF.md)
- [Playground.neat](/Users/george/Documents/Neat/NeatPlayground/Playground.neat)
- [DependencyGraph.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/DependencyGraph.swift)
- [CompilationArtifacts.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/CompilationArtifacts.swift)
- [ArtifactsCommand.swift](/Users/george/Documents/Neat/NeatCLI/Sources/Commands/ArtifactsCommand.swift)
- [Parser.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Shared/Parser.swift)
- [AST+Files.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Files/AST+Files.swift)
- [Parser+Files.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Files/Parser+Files.swift)
- [AST+ControlFlow.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/ControlFlow/AST+ControlFlow.swift)
- [Parser+ControlFlow.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/ControlFlow/Parser+ControlFlow.swift)
- [Parser+Derived.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/Derived/Parser+Derived.swift)
- [MainProgramRunner.swift](/Users/george/Documents/Neat/NeatCLI/Sources/NeatCLI/MainProgramRunner.swift)
- [SwiftBackendEmitter.swift](/Users/george/Documents/Neat/NeatCLI/Sources/NeatCLI/SwiftBackendEmitter.swift)
- [SwiftBackendDriver.swift](/Users/george/Documents/Neat/NeatCLI/Sources/NeatCLI/SwiftBackendDriver.swift)
- [NeatCLI.swift](/Users/george/Documents/Neat/NeatCLI/Sources/NeatCLI/NeatCLI.swift)
- [04-graph.html](/Users/george/Documents/Neat/NeatPlayground/.neat/Artifacts/04-graph.html)
- [03-graph.txt](/Users/george/Documents/Neat/NeatPlayground/.neat/Artifacts/03-graph.txt)

## Open Questions
- Next graph pass: how should body-level dependencies be modeled for:
  - local `state`
  - local `derived`
  - member reads like `person.name`
  - member mutations like `person.age += 1`
- Whether HTML graph labels should visually combine declaration name and referenced type, while keeping the underlying graph unchanged.
- How far Swift should go in representing semantic concepts before the Neat compiler takes over more of the pipeline.

## Next Step
- Add body-level dependency graphing for `@main`, functions, and local `derived` bodies so the graph reflects reads, writes, and mutation flow instead of only declaration structure.

## Verification
- Built successfully:
  - `cd /Users/george/Documents/Neat/NeatCLI && swift build`
  - `cd /Users/george/Documents/Neat/NeatSyntax && swift build`
- Regenerated artifacts with:
  - `cd /Users/george/Documents/Neat/NeatCLI && ./.build/debug/NeatCLI artifacts ../NeatPlayground --output /Users/george/Documents/Neat/NeatPlayground/.neat/Artifacts`
- Current generated HTML graph:
  - [04-graph.html](/Users/george/Documents/Neat/NeatPlayground/.neat/Artifacts/04-graph.html)
- Known stale/generated items in the worktree:
  - `NeatPlayground/.neat/Artifacts/Playground/02-ast-error.txt` is stale from an older parse failure.
  - `tmp-artifacts-check/` exists and can be removed.
  - `zed/neat/grammars/_stale_neat_checkout/` exists and looks stale.
