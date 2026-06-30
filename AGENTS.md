# Agent Notes

## Component Language Labels

When discussing Range components, always include the implementation language in
parentheses the first time the component is mentioned in a response or section.

Examples:

- Range compiler pipeline (Swift)
- Range parser/type checker/macro expander (Swift)
- Range lexer declarations (Range)
- Range macro-produced LLVM emission pipeline (Swift)
- Range LLVM emitter (Swift)
- Range runtime support (Swift)
- RangeCore syntax declarations (Range)
- Range benchmark harness (Python)

If a component has multiple layers, name both layers explicitly instead of using
ambiguous shorthand.

Examples:

- Range function parser (Swift) lowers source written in Range syntax.
- Range lexer declarations (Range) are compiled through generated Swift runtime
  support.
- Range LLVM IR artifact is emitted by Range LLVM emitter (Swift).

Avoid saying only "the compiler", "the lexer", "the backend", or "the runtime"
when multiple implementation languages are involved.

## Current Backend Reality

The active package layout is:

```text
RangeCompiler/
  Sources/RangeCompiler/  Swift compiler pipeline
  Sources/RangeEmission/  Macro-produced LLVM artifact collection
  Sources/range/          Tiny Swift compiler host for script-driven LLVM emission
  Range/Core/             Range-authored core declarations
  Range/Foundation/       Range-authored bundled macros/features
  Range/Lexer/            Range-authored lexer declarations
scripts/range             Shell command surface for emit/link/run
```

Normal Range program execution currently uses the Range script runner (Bash)
with the `range` compiler host (Swift):

```text
Range source
-> Range compiler pipeline (Swift)
-> Range-authored macro expansion to LLVM module text
-> clang
-> executable
```

Range LLVM emitter (Swift) is currently a macro-produced module text collector
used by `range` for Range-authored `@main` LLVM output. The active script path
writes LLVM IR and links it with Apple `clang`.

Range LLVM emitter (Swift) is verified by tests that assert macro-produced LLVM
module text is collected and written. The script runner is verified by running
`scripts/range run` against `@main {}`.

When explaining execution, say explicitly that Swift remains the current compiler
host, but the command driver is `scripts/range` and the produced executable is
linked from LLVM IR with `clang`. Do not describe C, Rust, or other imaginary
backends as active targets.
