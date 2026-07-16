# Range

Range's normal `compile`, source `check`, `run`, `emit-llvm`, and
`compile-executable` commands now use
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

Compile a Range file to LLVM on standard output, or type-check it without
emitting output:

```sh
scripts/range compile path/to/Main.range
scripts/range check path/to/Main.range
```

Projects can own a command line by declaring a `commandLine` source in their
`Project.range`. The Compiler project exposes its Range-authored CLI under its
project namespace:

```sh
scripts/range compiler compile path/to/Main.range
scripts/range compiler check path/to/Main.range
scripts/range compiler emit-llvm path/to/Main.range Main.ll
```

The command-line target is ordinary Range code, so another project can define
its own argument vocabulary and run it as `scripts/range ProjectName ...`.

Build one content-addressed compiler candidate from the accepted previous seed:

```sh
scripts/range compiler next
```

`next` validates and links the candidate under `.range/Compiler/Next`, reports
whether its LLVM already matches the accepted fixed point, and never promotes
the checked-in seed.

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

`SwiftBootstrap` remains only for the legacy example corpus; it is no longer a
build stage for the Range-authored compiler. Native compiler regressions link
the checked-in seed directly, so new compiler syntax and runtime ABI work does
not need a duplicate Swift implementation.

The self-hosting compiler lives at `RangeCompiler/Range/Programs/Compiler`.
Run `scripts/range check-compiler-candidate` for the full Stage 2/3 fixed-point
gate, or `scripts/range check-stage2-compiler` to verify the checked-in seed and
its frozen source/runtime manifest. The compiler now uses the core-declared
`RawBuffer` storage ABI for both integer tables and text assembly; the former
`IntBuffer` and `TextBuffer` compiler/runtime models have been removed.
