# Speed Benchmark

Run:

```sh
npm run speed
```

The task builds and runs equivalent integer-loop programs in C, Rust, Python,
and Neat. It reports median runtime for the executable/program only; compiler
and setup time are shown separately and are not included in the median.

If the current Neat Swift backend emits a workspace that does not build, the
task still reports Neat CLI build and emit time, then skips the Neat runtime row.
When the backend build is fixed, the same task will automatically include the
Neat executable in the runtime comparison.

Use `VERBOSE=1` to show full setup command output on failures.

Use `N` to change the iteration count:

```sh
N=20000000 npm run speed
```
