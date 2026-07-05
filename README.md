# Range

Range currently runs `.range` projects through the Range script runner, which
asks the Swift-hosted compiler to emit LLVM IR and then links that IR with
`clang`.

## Download

The active development command surface is the repository script:

```sh
scripts/range run path/to/Main.range
```

## Start

Emit LLVM IR directly:

```sh
scripts/range emit-llvm path/to/Main.range .range/Build/llvm/Main.ll
```

`scripts/range run` writes `.range/Build/llvm/Main.ll`, links it with `clang`,
and launches the executable. Swift remains the current compiler host; generated
Swift package workspaces are no longer the active backend path.
