# Agent Notes

## Component Language Labels

When discussing Range components, always include the implementation language in
parentheses the first time the component is mentioned in a response or section.

Examples:

- Range compiler pipeline (Swift)
- Range parser/type checker/macro expander (Swift)
- Range lexer declarations (Range)
- Range Swift-hosted emission pipeline (Swift)
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
  Sources/RangeEmission/  Swift-hosted emission and LLVM lowering
  Range/Core/             Range-authored core declarations
  Range/Foundation/       Range-authored bundled macros/features
  Range/Lexer/            Range-authored lexer declarations

CLI/
  Sources/                command-line shell
```

Normal Range program execution currently uses the Range Swift-hosted emission
pipeline (Swift):

```text
Range source
-> Range compiler pipeline (Swift)
-> generated Swift workspace
-> optional LLVM IR/object for supported scalar functions
-> Swift compiler
-> executable
```

Range LLVM emitter (Swift) is an internal lowering path of the Swift-hosted
emission pipeline, not a separate peer backend. It currently emits LLVM IR and a
linked object file for lowerable scalar `Int` functions. It supports simple
integer arithmetic, local `state`, `while` loops, and nested `while` loops.

Range LLVM emitter (Swift) is verified by tests that compile emitted LLVM IR with
Apple `clang` and run a small C harness. It is also wired into normal `range run`
workspace emission for lowerable scalar functions.

When explaining hybrid execution, say explicitly that Swift remains the current
program driver and LLVM is the native lowering path for supported scalar compute
inside that generated Swift workspace. Do not describe C, Rust, or other
imaginary backends as active targets.
