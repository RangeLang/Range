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
yet because those generated paths are not Embedded Swift-compatible today.

If the current Range script runner cannot emit a native binary for a benchmark
case, the task reports that setup failure and skips the Range runtime row. On
macOS, the script looks for an installed Swift toolchain with
`usr/lib/swift/embedded` for historical Swift comparison targets.
Set `RANGE_SWIFT_TOOLCHAINS` to override the detected toolchain identifier.

Use `VERBOSE=1` to show full setup command output on failures.

Use `N` to change the iteration count:

```sh
N=20000000 npm run speed
```
