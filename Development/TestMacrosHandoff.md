# Test Macros Handoff

**Date:** 2026-08-08
**Status:** implementation complete; awaiting clean-tree validation

## Decision in one sentence

Tests are command groups. `@test` is a function marker; `@testGroup` generates a
`Command` enum and `runCommandLine()` — the same shape as `@commandGroup` — so
tests integrate with the existing CLI dispatch without new compiler machinery.

## What we built

### New files

| File | Purpose |
|------|---------|
| `Language/Sources/Core/Macro/Test.range` | `macro test(): Function {}` marker and `macro testGroup(): Construct { ... }` group |
| `Language/Sources/Core/Macro/Main.range` | `macro main(): Void` declaration (skeleton; compiler still hardcodes `@main` entry) |
| `Testing/Test/Pass/Smoke.range` | Pass fixture: two `@test` functions, calls `tests.runCommandLine()` |
| `Testing/Test/Fail/EmptyTestGroup.range` | Rejection fixture: no `@test` functions, expects diagnostic |

### Modified files

| File | Change |
|------|--------|
| `scripts/check-range-value-ownership` | Added `write_test_group_bundle()`, `check_test_group()`, wired call after `check_command_group`; includes `Main.range` + `Test.range` as core sources in the bundle |
| `TODO.md` | Recorded `@test`/`@testGroup` task and follow-up items |
| `Website/Dockerfile` | Added `Main.range` COPY |

### What @testGroup generates

```range
enum Command {
    case invalid
    case smoke
    case alsoSmoke
}

function runCommandLine(): Int {
    return 0
}
```

This is structurally identical to `@commandGroup`'s output (which returns `64`).
The test construct **is** a command group. `range test` or `range <name>`
dispatches to `runCommandLine()` via the existing CLI infrastructure.

## Decisions

### Tests as command groups, not a separate runner

Initial approach generated `enum Test` + `runTests()`. Moved to `enum Command` +
`runCommandLine()` so tests use the same CLI dispatch as everything else. No new
compiler paths needed.

### Main macro declared but not executed

`Core/Macro/Main.range` declares `macro main(): Void` as a skeleton. The actual
`@main` entry is still hardcoded in `CompilerFrontend.range:3475` — the token is
detected, the body is brace-matched, and the entry syntax node is created
manually. The declaration exists so the macro is available in the graph when we
route `@main` through normal macro execution.

The real compiler entry is at `Language/Sources/Compiler/Driver/Main.range`
(CLI arg parsing + dispatch to compile/check/link/build).

### #map limitation in function bodies

The compiler currently supports `#map` for generating enum cases but not for
generating statements inside function bodies. Both `@commandGroup` and
`@testGroup` have stub `runCommandLine()` bodies (`return 64` / `return 0`).
This is tracked in `TODO.md`:

> Support statement arrays produced by `#commands.map` inside generated function
> bodies without aborting native compilation

Once supported, the dispatch body generates automatically from the macro source.

### Bootstrap can't process new macro declarations

The bootstrap compiler has a frozen set of built-in macros. New macro
declarations (like `macro test()`) only compile through the **development
candidate compiler** (built by `check-range-value-ownership` via
`resolve-range-compiler-build`). Direct bootstrap tests with new macro files
fail with `malformedMacroDeclaration`.

## Current state

- All macro sources, fixtures, and check script wiring are in place
- `scripts/range check-value-ownership` validates the full chain
- Tree has uncommitted runtime changes (`Language/Runtime/*.c`) that cause
  hash mismatches in the candidate check
- Need a clean tree (stash or commit runtime changes) to run the full gate

## Next steps

1. Clean tree: stash or commit `Language/Runtime/` changes
2. Run `scripts/range check-value-ownership` to validate `@testGroup` boundary
3. Once `#map` for function body statements is supported: replace `return 0`
   stub with real dispatch (match command name → call test function →
   pass/fail tracking)
4. Consider making `@main` a proper macro (route through normal application
   path, let macros contribute `before`/`after` to the entry)
5. Wire `range test` as a first-class CLI command once command dispatch
   supports real argument routing
