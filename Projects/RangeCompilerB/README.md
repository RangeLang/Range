# Compiler B

Compiler B is the new compiler. Build it out in small runnable slices.

- B owns file access, lexing, macros, graph construction, lowering, and emit.
- Host and operating-system boundaries belong behind B-owned `@extern` functions.
- Compiler A only bootstraps B’s LLVM; do not reshape B around A’s tables or body arena.
- Each slice must compile, link, run, and show its result before expanding scope.
- Keep the entrypoint in `Sources/CompilerB/Main.range` until the next boundary is proven.
- The current slice discovers a project’s first `.range` file and prints B-owned lexer tokens.

Run the current slice with:

```sh
scripts/run-compiler-b-bootstrap <route>
```
