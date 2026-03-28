# Handoff

## Objective
- Continue turning Neat macros into real language-owned behavior, with the current focus on attached `Init` macros and `#literal<T>`.
- Keep the architecture graph-driven: protocol init requirements carry macros onto conforming initializers, and invocation/literal lowering should consume that carried result.

## What Changed
- Preserved generic arguments on macro applications.
  - `#literal<IntLiteral>` is no longer reduced to just `#literal`.
- Added construct collection to the macro expander, with carried protocol init macros already merged onto concrete construct initializers before later expansion.
- Added the first executable literal-lowering bootstrap path:
  - raw literal expressions now lower through carried `#literal<...>` init macros into construct init calls
  - first verified case: integer literal -> `Int(literal: 5)` internally, emitted as `Int(5)` for Swift.
- Patched Swift emission so native Swift bridge types (`Int`, `Float`, `Double`, `String`, `Bool`) drop the Neat `literal:` label when emitting call arguments.
- Simplified `NeatCore/Macros/Implementations/Literal.neat` into a parseable sketch again.

## Key Decisions
- `@core` applies to constructs, not protocols.
- Macro closure bindings stay at `target, diagnostics` only.
- Attached parameter macros attach as `Attached<Parameter>`, but their execution-time `target` is contextual.
- `CallContext` is the parameter-level invocation view:
  - `parameter`
  - `arguments`
- `InitCall` is the initializer-level invocation view:
  - `init`
  - `calls: [CallContext]`
- `InitCall` is rewritable; `Argument` remains rewritable for parameter-local transforms.
- `FunctionType` was introduced to separate closure type syntax from closure expression syntax.
- Literal handling direction:
  - compiler knows literal syntax forms
  - protocol/init-carried macros determine literal carrier behavior
  - current implementation is still bootstrap-specialized, not a full attached-init macro interpreter
- Core literal init surfaces were aligned to labeled form only:
  - `init(literal: IntLiteral)` etc.
  - no compatibility hack for `_`

## Current State
- Real macro surface exists under `NeatCore/Macros`.
- Attached parameter macros work in bootstrap form:
  - `#autoclosure`
  - `#variadic`
- Protocol init requirements now preserve initializers with macros, and carried init macros are merged onto matching concrete initializers.
- `#literal<T>` is now preserved and used during bootstrap literal lowering.
- First real literal bootstrap path works:
  - raw `5` lowers via carried `#literal<IntLiteral>` on `Int.init(literal: IntLiteral)`
  - generated Swift for the smoke case is `var count = Int(5)`

- What is still intentionally incomplete:
  - no general `Attached<Init>` interpreter yet
  - `Literal.neat` body is not executed as source of truth
  - current literal lowering is still specialized in `MacroExpander.swift`
  - protocol carriage is implemented separately from general attached-init execution
  - no general support yet for `target.calls[...]`, `target.rewrite(...)`, `target.expression(...)`, or `T.self` as an interpreted attached-init body API

## Important Files
- `/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/MacroExpander.swift`
- `/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/AST+Macro.swift`
- `/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/Parser+MacroUseSite.swift`
- `/Users/george/Documents/Neat/NeatCLI/Sources/NeatCLI/SwiftBackendEmitter.swift`
- `/Users/george/Documents/Neat/NeatCore/Macros/Implementations/Literal.neat`
- `/Users/george/Documents/Neat/NeatCore/Macros/Declarations/Init.neat`
- `/Users/george/Documents/Neat/NeatCore/Macros/Declarations/InitCall.neat`
- `/Users/george/Documents/Neat/NeatCore/Macros/Declarations/CallContext.neat`
- `/Users/george/Documents/Neat/NeatCore/DataSystem/Int/Int.neat`
- `/Users/george/Documents/Neat/NeatCore/DataSystem/Int/ExpressableByIntLiteral.neat`
- `/Users/george/Documents/Neat/NeatCore/DataSystem/Optional/ExpressableByNilLiteral.neat`
- `/Users/george/Documents/Neat/.codex-tmp/LiteralSmoke.neat`
- `/Users/george/Documents/Neat/.codex-tmp/LiteralSmoke.swift`

## Open Questions
- Should the next step be:
  - a real attached-init interpreter for the current `literal` body shape, or
  - a more explicit literal-lowering phase that still remains graph-driven but is not body-interpreted?
- How far should the Swift-native bridge emission go beyond `Int`, `Float`, `Double`, `String`, `Bool`?
  - array/dictionary/set/nil literal bridging is not solved in Swift emission yet.
- Whether to expose more of attached-init execution directly as `InitContext` operations before generalizing to other attached init macros.

## Next Step
- Replace the current literal-specialized bootstrap helper in `MacroExpander.swift` with the first real `Attached<Init>` executor for the existing `Literal.neat` body shape.

## Verification
- `swift build` in `/Users/george/Documents/Neat/NeatSyntax`
- `swift build` in `/Users/george/Documents/Neat/NeatCLI`
- `./.build/debug/NeatCLI artifacts /Users/george/Documents/Neat/.codex-tmp/LiteralSmoke.neat`
- `./.build/debug/NeatCLI compile /Users/george/Documents/Neat/.codex-tmp/LiteralSmoke.neat /Users/george/Documents/Neat/.codex-tmp/LiteralSmoke.swift`
- `./.build/debug/NeatCLI run /Users/george/Documents/Neat/.codex-tmp/LiteralSmoke.neat`

- Smoke result:
  - generated Swift contains `var count = Int(5)`
  - end-to-end `run` succeeds

- Limits of verification:
  - artifact AST output is still pre-expansion
  - the current literal path is verified through generated Swift and run behavior, not through a general attached-init macro interpreter

- Current visible git status during handoff creation:
  - `?? zed/neat/grammars/_stale_neat_checkout/`
