# Agent Notes

## Component Language Labels

When discussing Range components, always include the implementation language in
parentheses the first time the component is mentioned in a response or section.

Examples:

- Range compiler pipeline (Swift)
- Range parser/type checker/macro expander (Swift)
- Range lexer declarations (Range)
- Range backend Swift (Swift)
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

Normal Range program execution currently uses Range backend Swift (Swift):

```text
Range source
-> Range compiler pipeline (Swift)
-> generated Swift workspace
-> Swift compiler
-> executable
```

Range LLVM emitter (Swift) is experimental and currently emits LLVM IR artifacts
for lowerable scalar `Int` functions. It supports simple integer arithmetic,
local `state`, `while` loops, and nested `while` loops.

Range LLVM emitter (Swift) is verified by tests that compile emitted LLVM IR with
Apple `clang` and run a small C harness. It is not yet wired into normal
`range run` execution.

When explaining hybrid execution, say explicitly that Swift remains the current
program driver and LLVM is currently a side path for scalar compute artifacts.
