# Scalar Nested Loop Benchmark

Compares one integer-heavy nested loop kernel across:

- Range-emitted LLVM IR compiled with `clang -O3`
- C compiled with `clang -O3`
- Rust compiled with `rustc -C opt-level=3`
- Python
- JavaScript via Node

Run:

```sh
python3 Benchmarks/ScalarNestedLoop/run.py
```

The benchmark is intentionally standalone and directional. It is not part of unit
tests because wall-clock timing is machine/load dependent.
