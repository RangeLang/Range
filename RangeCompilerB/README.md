# Range Compiler B

`RangeCompilerB` is the only actively evolving compiler source tree. It is a
complete fork of the current Range-authored compiler, including its Core,
Foundation, compiler phases, driver, LLVM emission, and native runtime.

`RangeCompiler/Bootstrap/` remains the sole accepted Compiler A authority. A
builds B once; the resulting B executable builds the same B source revision to
prove self-hosting and deterministic reproduction:

```text
accepted A + B source -> B candidate
B candidate + B source -> B reproduction
```

Candidate and reproduction LLVM and executables must compare byte for byte.
RangeView is the first independent product after this self-compilation proof;
it is not part of Compiler B and is not required to configure B.

The B proof uses the candidate harness's runtime-roll mode because B owns a
copied, evolving runtime that may intentionally differ from A's accepted
manifest. This does not promote B or relax candidate/reproduction equality; A's
committed LLVM, executable, and manifest remain verified before producing B.

Compiler B intentionally begins as a complete duplicate. Compiler A is frozen,
and compiler changes belong only here. Existing tables and arenas are inherited
implementation details, not architectural commitments; B can replace them with
typed graph values one vertical phase at a time while retaining a runnable
self-hosting baseline.

Run the fixed-point proof from the repository root:

```sh
scripts/range check-compiler-b
```

The initial fork checkpoint builds candidate B and passes its source, Core,
ownership, macro, body-replay, and native smoke audits. It currently stops
before reproduction at the inherited direct-`@many` unresolved-macro boundary;
the proof must remain reported as incomplete until that language capability is
restored in B and the byte comparisons run.

The earlier single-file lexical/source-graph experiment remains available only
as a focused component proof:

```sh
scripts/range check-compiler-b-source-graph
```
