# Core Bootstrap Plan

## Objective

Align the Swift-hosted compiler with Neat's `@core` model without blocking progress on bootstrapping.

The compiler should recognize literals and `@core` declarations, while `NeatCore` remains the language-visible source of truth for foundational types and protocols.

## Phase 1: Name The Boundary Correctly

- Treat remaining Swift-side type knowledge as bootstrap machinery, not as true builtins.
- Rename narrow compiler concepts away from `BuiltinType` terminology.
- Keep the bootstrap set intentionally small and explicit.

## Phase 2: Move From Scalar Types To Literal Categories

- Stop using Swift-side scalar type names as the primary bootstrap semantic model.
- Model compiler-recognized literals as literal categories such as int, float, string, bool, and nil.
- Keep `Void` and optional/nil compatibility as explicit bootstrap bridges where needed.

## Phase 3: Resolve Against `@core`

- Make type checking resolve literal and return compatibility against `@core` declarations and literal bridge protocols in `NeatCore`.
- Treat `@core` as the semantic marker for compiler-recognized structural constructs.
- Reduce ad hoc scalar-name checks in parser validation.

## Phase 4: Shrink Compiler Special Cases

- Keep only parsing, lowering, runtime, and sugar hooks in Swift.
- Move more language meaning into Neat declarations and protocols.
- Remove bootstrap mirrors when source-driven semantic resolution can replace them.

## Immediate Next Step

Rename the remaining narrow Swift-side bootstrap type model away from `BuiltinType` so the code reflects its real role.
