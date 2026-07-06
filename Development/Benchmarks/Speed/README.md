# Speed Benchmark

Run:

```sh
npm run speed
```

The task builds and runs equivalent compatible programs in C, Rust, Swift,
Python, and Range. It currently covers integer loops, strings, collections,
construct initialization, and generic calls. It reports median wall-clock
runtime, child CPU time, CPU utilization, and peak resident memory for the
executable/program only; compiler and setup time are shown separately and are not
included in the medians. Runtime, CPU time, and memory are also printed relative
to C per benchmark case.

JSON encoding and real `@background` concurrency are intentionally not included
yet because those runtime paths are not part of the current LLVM benchmark
surface.

The Range row uses `scripts/range run`, which asks the range compiler host
(Swift) to emit LLVM IR, links it with `clang`, and then benchmarks the linked
executable. If the Range LLVM build does not produce an executable, the task
reports the setup output and skips the Range runtime row.

Correctness for the active LLVM execution path is checked outside the benchmark
with `scripts/range check`, which runs the full LLVM example corpus through
emission, `clang`, process exit, and declared stdout checks.

Use `VERBOSE=1` to show full setup command output on failures.

Use `N` to change the iteration count:

```sh
N=20000000 npm run speed
```
