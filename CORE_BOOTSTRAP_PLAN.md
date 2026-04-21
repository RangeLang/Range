# Core Bootstrap Plan

## Objective

Align the Swift-hosted compiler with Neat's `@core` model without blocking progress on bootstrapping.

The compiler should recognize literals and `@core` declarations, while `NeatCore` remains the language-visible source of truth for foundational types and protocols.

## Phase 1: Name The Boundary Correctly

- Treat remaining Swift-side type knowledge as bootstrap machinery, not as true builtins.
- Keep narrow compiler concepts named as bootstrap machinery rather than as true builtins.
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

## Current Status

This plan is still directionally correct, but one important rename step is already done:

- the compiler now uses `BootstrapLiteralType`, not `BuiltinType`

That means the remaining work is no longer naming cleanup. It is semantic cleanup.

## Immediate Next Step

Keep shrinking the places where `BootstrapLiteralType` directly carries language meaning.

The next useful slice is:

- push more literal compatibility and destination choice through declaration-graph
  facts and `@core` literal bridge protocols
- keep Swift-side bootstrap logic only where parsing, lowering, or runtime hooks
  still truly require it
