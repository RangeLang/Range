<div align="center">

<a href="https://rangelang.org">
  <img src="Website/public/og-homepage.png" alt="Range — a love letter to electrons, logic and abstraction" width="100%">
</a>

### An applied programming language

[Website](https://rangelang.org) · [Intro to Range](https://rangelang.org/posts/intro-to-range) · [Benchmarks](https://rangelang.org/benchmarks)

</div>

Range describes a program as a typed graph. Identity and value are its smallest
unit of meaning; binding intents describe access; constructs, enums, and
functions compose the graph. Macros receive program structure and return a
transformed execution graph.

The supported implementation is the Range-authored self-hosted compiler. It
emits native LLVM and must reproduce byte-identical LLVM and linked compiler
executables before a compiler change is accepted.

Compiler checkpoints use one rolling authority. The accepted compiler builds
a candidate from the current source, then that candidate rebuilds the same
source once. Byte-identical candidate and reproduction LLVM/executables permit
the candidate to replace the accepted compiler; no third build or active
archive of older compilers is required. Promotion is a deliberate maintainer
checkpoint, not a step after every source edit.

## Performance

Native LLVM · `-O3` · July 2026

![Range String performance improved from 491.2 ms and 5.3 GB to 4.1 ms and 1.9 MB](Benchmarks/Speed/range-strings-improvement.svg)

Range's owned String storage now carries its length, capacity, and data forward, allowing uniquely owned strings to grow in the same allocation.

| 100k appends | Before | After | Improvement |
|---|---:|---:|---:|
| Median wall time | 491.2 ms | **4.1 ms** | **~120× faster** |
| Peak memory | 5.3 GB | **1.9 MB** | **~2,800× less** |

## Native comparison

All results below are ordered fastest to slowest. Range is highlighted in bold.

| Strings · 100k appends | Median wall time |
|---|---:|
| C | 3.9 ms |
| C++ | 3.9 ms |
| **Range** | **4.1 ms** |
| Rust | 4.2 ms |
| Go | 4.8 ms |
| Swift | 5.6 ms |

Range peak memory: **1.9 MB**.

<details>
<summary><strong>Initial benchmark</strong> · July 18, 2026</summary>

### Loops · 20m iterations

| Language | Median wall time |
|---|---:|
| C++ | 61.3 ms |
| C | 61.4 ms |
| Rust | 61.9 ms |
| Swift | 62.5 ms |
| **Range** | **66.3 ms** |
| Go | 79.6 ms |

### Noise · 50m samples

| Language | Median wall time |
|---|---:|
| C | 70.5 ms |
| C++ | 70.9 ms |
| Go | 78.9 ms |
| **Range** | **82.4 ms** |
| Rust | 82.9 ms |
| Swift | 82.9 ms |

### Function calls · 20m iterations

| Language | Median wall time |
|---|---:|
| Go | 64.2 ms |
| C++ | 67.4 ms |
| C | 67.5 ms |
| Rust | 67.9 ms |
| Swift | 68.5 ms |
| **Range** | **72.3 ms** |

### Strings before lowering · 100k appends

| Language | Median wall time |
|---|---:|
| C++ | 3.6 ms |
| Rust | 3.6 ms |
| Go | 4.3 ms |
| C | 4.4 ms |
| Swift | 4.8 ms |
| **Range** | **491.2 ms** |

Range peak memory: **5.3 GB** · peers: **1.8–4.2 MB**.

</details>

<details>
<summary><strong>String scaling</strong> · 30 runs at each size</summary>

| 100k appends | 1m appends | 5m appends | 10m appends |
|---|---|---|---|
| C · 4.2 ms | C++ · 8.2 ms | C · 20.0 ms | C · 36.1 ms |
| C++ · 4.3 ms | C · 8.7 ms | C++ · 20.2 ms | Rust · 36.2 ms |
| **Range · 4.3 ms** | Rust · 8.9 ms | Rust · 20.3 ms | C++ · 36.3 ms |
| Rust · 4.4 ms | Go · 9.5 ms | Go · 21.3 ms | Go · 37.0 ms |
| Go · 5.3 ms | **Range · 10.1 ms** | **Range · 27.2 ms** | **Range · 50.1 ms** |
| Swift · 6.2 ms | Swift · 20.7 ms | Swift · 62.1 ms | Swift · 118.4 ms |

</details>

## Compiler status

**4 of 6 tests emitted and passed.**

| Result | Tests |
|---|---|
| Passed | Loops, Noise, Function Calls, Strings |
| Did not emit | Collections · resolution stage 2 |
| Did not emit | Constructs · constructor-argument parse reachability |
| Emitted but failed | None |

## Use Range

```sh
scripts/range compile Testing/Basics/Pass/ReturnInteger.range
range run GPUCanvas
scripts/range check-compiler-candidate
scripts/range check-compiler
```

The ordinary file/directory wrapper bundles canonical Core sources through the
accepted compiler; `range run` additionally links the manifest-declared runtime
inputs and executes `@main`. See the
[speed benchmark](Benchmarks/Speed/README.md) for performance comparisons.
The two compiler checks above are maintainer proofs: the first validates the
candidate/reproduction fixed point, and the second verifies the currently
accepted bootstrap.

## License

Copyright 2026 Giorgi Tchelidze.

Range is licensed under the [Apache License, Version 2.0](LICENSE).

## Trademarks

The Range name and logo are trademarks of Giorgi Tchelidze. The Apache License
does not grant permission to use these marks except as required for reasonable
and customary use in describing the origin of the software.
