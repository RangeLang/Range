# Range

Range's normal `run`, `emit-llvm`, and `compile-executable` commands now use
the checked-in native seed compiler to emit LLVM IR, link it with `clang`, and
launch the native executable. The native self-hosting compiler and macro
candidate/seed gates are green, including the actual Foundation `Registrable`
macro. The complete LLVM example/run manifest still uses the retained
SwiftBootstrap path: the native seed's current bounded language slice does not
yet cover the manifest's print/Text, arrays, enums/switch, generics, optionals,
and file-I/O programs. Swift compiler/package/test deletion is therefore
blocked until that parity is implemented.

## Download

The active development command surface is the repository script:

```sh
scripts/range run path/to/Main.range
```

## Start

Run the active LLVM executable gate:

```sh
scripts/range check
```

Emit LLVM IR directly:

```sh
scripts/range emit-llvm path/to/Main.range .range/Build/llvm/Main.ll
```

Check that the LLVM example corpus still emits module text:

```sh
scripts/range check-llvm-examples
```

Check representative examples by linking and running the emitted LLVM:

```sh
scripts/range check-llvm-runs
```

`scripts/range check` still delegates the run manifest to `SwiftBootstrap`,
which validates manifest coverage, emits LLVM, links with `clang`, launches
each executable, and checks exit/stdout expectations. The emit-only example
corpus check also remains on that retained path. `scripts/range run` is native
by default and writes `.range/Build/llvm/Main.ll` through the checked-in seed.

`SwiftBootstrap` remains only as the retained compatibility/checking host while
the Range-authored compiler grows beyond its current bounded native slice.

The first self-hosting lane lives at `RangeCompiler/Range/Programs/Compiler`.
It is intentionally tiny right now: `scripts/range check-bootstrap-compiler`
compiles that Range-authored compiler program through `SwiftBootstrap`, links it
with `clang`, and runs the native `Compiler` binary against a Range source file
so the binary calls its Range-authored lexer library and prints a deterministic
token stream. The lexer is a small direct port of the Swift bootstrap lexer path.
The test suite compares the native lexer stream against the Swift bootstrap
lexer for the compiler entrypoint. The binary also parses the first tiny AST
checkpoints: an `@main` block summary and top-level function declaration
summaries with body bounds. The `@main` block also lowers to a compiler `main`
function summary, and a direct `return <integer>` in that body emits the first
Range-authored LLVM text checkpoint.
