# Range

Range currently runs `.range` projects through the `SwiftBootstrap` compiler
host, which emits LLVM IR, links it with `clang`, and launches the native
executable.

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

`scripts/range check` delegates the run manifest to `SwiftBootstrap`, which
validates manifest coverage, emits LLVM, links with `clang`, launches each
executable, and checks exit/stdout expectations. The emit-only example corpus
check also runs through `SwiftBootstrap`. `scripts/range run` delegates to
`range run`, which writes `.range/Build/llvm/Main.ll` through `SwiftBootstrap`,
links it, and launches the executable.
Swift remains the current compiler host; generated Swift package workspaces are
no longer the active backend path.

`SwiftBootstrap` is the stage-0 compiler target: it exists to compile Range
source through the current Swift-hosted pipeline until the Range-authored
compiler can compile itself.

The first self-hosting lane lives at `RangeCompiler/Range/Programs/Compiler`.
It is intentionally tiny right now: `scripts/range check-bootstrap-compiler`
compiles that Range-authored compiler program through `SwiftBootstrap`, links it
with `clang`, and runs the native `Compiler` binary against a Range source file
so the binary calls its Range-authored scanner library and prints a deterministic
token stream.
