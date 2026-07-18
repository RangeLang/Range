# Speed Benchmark

Run:

```sh
npm run speed
```

The task builds and runs equivalent compatible programs in C, C++, Rust, Go,
Swift, Bun, TypeScript 7, and Range. The evaluation matrix currently covers:

- **Loops**: sequential integer arithmetic and modulo dependencies.
- **Noise**: optimized floating-point arithmetic and a one-million-sample noise loop.
- **Strings**: incremental string growth and length tracking.
- **Collections**: array creation, traversal, branching, and reduction.
- **Constructs**: short-lived value construction and member access.
- **Function Calls**: small reusable calls and predictable branching.

Every measured target must produce its exact expected result. Native Range uses
a bounded process-exit checksum for standalone cases; the other targets emit a
full stdout checksum. A mismatch stops the run instead of publishing incomparable timings. The runner reports median
wall-clock runtime, child CPU time, CPU utilization, and peak resident memory for the
executable/program only; compiler and setup time are shown separately and are not
included in the medians. Runtime, CPU time, and memory are also printed relative
to C per benchmark case.

Runtime samples are collected in a balanced round-robin order rather than one
complete language block at a time. The starting target rotates between rounds
and the direction reverses after a complete rotation, reducing frequency,
thermal, and background-load drift between language rows.

The Bun row executes the TypeScript source directly. The TypeScript 7 row first
compiles that same source with the native `tsgo` compiler, reports compilation as
setup time, and then executes the emitted JavaScript with Bun. This keeps compiler
and runtime cost separate instead of presenting TypeScript 7 as a JavaScript
runtime. If `bun` or `tsgo` is unavailable, the task prints an explicit skip and
continues with the installed toolchains.

JSON encoding and real `@background` concurrency are intentionally not included
yet because those runtime paths are not part of the current LLVM benchmark
surface.

Compiled targets use host-native code generation where their toolchain exposes
it: Clang receives `-mcpu=native`, Rust receives `target-cpu=native`, and Swift
uses `-Ounchecked`. The suite intentionally does not enable fast-math because
reassociation and relaxed floating-point rules would change the Noise workload's
semantics. Go's Noise arithmetic is written directly in the hot loop because Go
does not expose a force-inline attribute and its compiler otherwise leaves the
larger helper as a call while the other optimized artifacts inline it.

The Range setup prefers the repository's Stage 3 native compiler only when its
executable is byte-identical to Stage 2. If that fixed-point pair is unavailable,
the runner falls back to the pinned native seed. Set `RANGE_BENCH_COMPILER` to
test a specific compiler artifact explicitly. The emitted `Main.ll` is relinked
with `clang -O3` and the manifest-pinned Range runtime sources. This keeps
Range's measured native artifact at the same optimization level as the C, C++,
and Rust rows without changing Range's normal command-line defaults.

An evaluation can still report `Range skipped` when the current native compiler
cannot lower that language surface. The setup diagnostic is the capability
result; use `VERBOSE=1` to print it.

Correctness for the active LLVM execution path is checked outside the benchmark
with `scripts/range check`, which runs the full LLVM example corpus through
emission, `clang`, process exit, and declared stdout checks.

Use `VERBOSE=1` to show full setup command output on failures.

Use `N` to change the iteration count:

```sh
N=20000000 npm run speed
```

Use `CASES` to run a comma-separated subset by internal name or category:

```sh
CASES=integer_loop,float_noise RUNS=20 npm run speed
CASES=Noise npm run speed
```
