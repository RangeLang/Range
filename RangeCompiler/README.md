# Range Compiler

`RangeCompiler` is the repository's only compiler implementation.

The checked-in bootstrap at `Bootstrap/range` is a hash-pinned macOS arm64
seed. It reads the canonical source manifest, emits deterministic Apple arm64
assembly, and depends dynamically only on libSystem. It is replaced only after
a candidate compiler reproduces byte-identical assembly, object code,
executable bytes, and focused fixture output.

The compiler pipeline is:

```text
Range graph
  -> semantic execution graph
  -> Apple arm64 instruction graph
  -> textual assembly
  -> clang assembly and linking
```

Clang is a target tool only. Range semantics and instruction selection remain
Range-authored. The C host and RawBuffer runtime are temporary until dynamic
graph-native many storage, file/process effects, and cleanup are native.

## Commands

```sh
scripts/range compiler --emit-assembly <project>
scripts/range run <project> [-- args...]
scripts/range check-compiler
scripts/range check-compiler-self-host --audit-only
scripts/range check-compiler-self-host --expect-boundary
```

The current self-host boundary is the continuation after the compiler entry's
first compound conditional. Removing the former compiler does not itself prove
self-hosting.
