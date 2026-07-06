# Range

Range currently runs `.range` projects through the Range script runner, which
asks the `SwiftBootstrap` compiler host to emit LLVM IR, link it with `clang`,
and return a native executable.

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

`scripts/range check` runs the full LLVM example corpus through `SwiftBootstrap`,
emitted LLVM, `clang`, and the linked executable. `scripts/range run` writes
`.range/Build/llvm/Main.ll` through `SwiftBootstrap`, then launches the
executable.
Swift remains the current compiler host; generated Swift package workspaces are
no longer the active backend path.

`SwiftBootstrap` is the stage-0 compiler target: it exists to compile Range
source through the current Swift-hosted pipeline until the Range-authored
compiler can compile itself.
