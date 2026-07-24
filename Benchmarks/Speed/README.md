# Speed Benchmark

Run:

```sh
npm run speed
```

The task builds and runs equivalent compatible programs in C, C++, Rust, Go,
Swift, Bun, TypeScript 7, and Range. The evaluation matrix currently covers:

- **Loops / While**: sequential integer arithmetic and modulo dependencies.
- **Loops / If**: a repeated one-sided conditional with a 75% taken branch.
- **Loops / If Else**: a repeated balanced two-outcome conditional.
- **Noise / Perlin**: two-dimensional single-cell gradient interpolation.
- **Noise / Voronoi**: nearest-feature squared-distance evaluation.
- **Noise / Value Noise**: smooth bilinear lattice-value interpolation.
- **Strings**: incremental string growth and length tracking.
- **Collections**: array creation, traversal, branching, and reduction.
- **Convolution / 1D Three Tap**: a circular integer stencil over eight samples.
- **Constructs / Raw Struct Race**: a local Range construct whose identity is
  proven unobservable and eliminated against optimized inline C, C++, Rust,
  Go, and Swift values using the same 32-bit integer width as Range `Int`.
- **Constructs / Identity**: eight-level identity chains, shared binding
  mutation, and repeated child replacement.
- **Recursion / Fibonacci**: repeated binary recursion across alternating depths.
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

Construct cases that allocate Range identities also link the identical emitted
LLVM a second time with `RANGE_IDENTITY_USE_MALLOC_BASELINE`. The normal
`Range` row therefore measures the 64 KiB arena, while `Range malloc` measures
the former one-`malloc`-per-identity behavior without changing lowering,
construct layout, or the workload. Both rows report identity allocation count,
requested bytes, aligned bytes used, chunk count, and reserved bytes in the
result artifact. Every Range-capable Constructs leaf declares its expected
identity-allocation count, including zero for the raw struct race, and the run
fails if telemetry disagrees. Telemetry comes from separate validation binaries
compiled with `RANGE_IDENTITY_ENABLE_STATS`; the timed Range binaries contain
no counter or reporting instrumentation.

The raw struct race answers whether graph proof can remove Range's unused
identity and compete with the cheapest inline representations. Its peer
implementations use explicit 32-bit fields, counters, and accumulators so the
hot-loop arithmetic lowering is comparable rather than measuring different
constant-remainder sequences. The identity rows separately compare
reference-shaped storage and mutation. A
Range row remains `notEmitted` when the current compiler cannot lower a
workload; the runner never substitutes a weaker Range program or accepts an
incorrect checksum.

An evaluation can still report `Range skipped` when the current native compiler
cannot lower that language surface. The setup diagnostic is the capability
result; use `VERBOSE=1` to print it.

Correctness for the active LLVM execution path is checked outside the benchmark
with `scripts/range check`, which runs the full LLVM example corpus through
emission, `clang`, process exit, and declared stdout checks.

Use `VERBOSE=1` to show full setup command output on failures.

## Generated results

Every run writes the versioned category → subcategory → leaf tree to:

- `results/latest.json`, the canonical benchmark artifact.
- `Website/public/benchmarks.json`, the website input generated from the same
  run.

Each leaf includes its workload count and unit, correctness status, Range emission status,
fastest-to-slowest language measurements, wall and CPU milliseconds, peak memory, C-relative
ratios, exact output, and the generated C and Range implementations shown by the website. The
artifact also records the compile, execution, validation, and sampling procedure. The contract is
documented by `benchmark-results.schema.json`.

Filtered runs retain the complete catalog and mark leaves outside the filter as `notRun`, so the
website never has to infer missing categories. Set `WRITE_SITE_RESULTS=0` to generate results
without updating the website payload, or set `RESULTS_FILE` and `SITE_RESULTS_FILE` to choose
different destinations.

Use `N` to change the iteration count:

```sh
N=20000000 npm run speed
```

Use `CASES` to run a comma-separated subset by internal name or category:

```sh
CASES=integer_loop,perlin_noise RUNS=20 npm run speed
CASES=Noise npm run speed
CASES=Loops N=20000000 RUNS=20 npm run speed
CASES="If Else" N=20000000 RUNS=20 npm run speed
```
