#!/usr/bin/env python3
import os
import shutil
import statistics
import subprocess
import tempfile
import textwrap
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
LIMIT = int(os.environ.get("RANGE_BENCH_LIMIT", "1800"))
ITERATIONS_NATIVE = int(os.environ.get("RANGE_BENCH_NATIVE_ITERATIONS", "8"))
ITERATIONS_SCRIPT = int(os.environ.get("RANGE_BENCH_SCRIPT_ITERATIONS", str(ITERATIONS_NATIVE)))
REPEATS = int(os.environ.get("RANGE_BENCH_REPEATS", "5"))
MODULUS = 1_000_000_007


RANGE_LLVM_IR = f"""
; ModuleID = 'RangeScalar'
source_filename = "RangeScalar.ll"

define i64 @RangeLLVM_nestedMix(i64 %limit, i64 %iterations) {{
entry:
  %iter.addr = alloca i64
  store i64 0, ptr %iter.addr
  %sink.addr = alloca i64
  store i64 0, ptr %sink.addr
  br label %iteration.cond

iteration.cond:
  %iter.current = load i64, ptr %iter.addr
  %iter.keepGoing = icmp slt i64 %iter.current, %iterations
  br i1 %iter.keepGoing, label %iteration.body, label %iteration.end

iteration.body:
  %outer.addr = alloca i64
  store i64 0, ptr %outer.addr
  %total.addr = alloca i64
  store i64 0, ptr %total.addr
  br label %outer.cond

outer.cond:
  %outer.current = load i64, ptr %outer.addr
  %outer.keepGoing = icmp slt i64 %outer.current, %limit
  br i1 %outer.keepGoing, label %outer.body, label %outer.end

outer.body:
  %inner.addr = alloca i64
  store i64 0, ptr %inner.addr
  br label %inner.cond

inner.cond:
  %inner.current = load i64, ptr %inner.addr
  %inner.keepGoing = icmp slt i64 %inner.current, %limit
  br i1 %inner.keepGoing, label %inner.body, label %inner.end

inner.body:
  %total.current = load i64, ptr %total.addr
  %outer.value = load i64, ptr %outer.addr
  %outer.term = mul i64 %outer.value, 31
  %inner.value = load i64, ptr %inner.addr
  %inner.term = mul i64 %inner.value, 17
  %with.outer = add i64 %total.current, %outer.term
  %with.inner = add i64 %with.outer, %inner.term
  %with.iter = add i64 %with.inner, %iter.current
  %mixed = srem i64 %with.iter, {MODULUS}
  store i64 %mixed, ptr %total.addr
  %inner.next.base = load i64, ptr %inner.addr
  %inner.next = add i64 %inner.next.base, 1
  store i64 %inner.next, ptr %inner.addr
  br label %inner.cond

inner.end:
  %outer.next.base = load i64, ptr %outer.addr
  %outer.next = add i64 %outer.next.base, 1
  store i64 %outer.next, ptr %outer.addr
  br label %outer.cond

outer.end:
  %sink.current = load i64, ptr %sink.addr
  %total.final = load i64, ptr %total.addr
  %sink.next = xor i64 %sink.current, %total.final
  store i64 %sink.next, ptr %sink.addr
  %iter.next = add i64 %iter.current, 1
  store i64 %iter.next, ptr %iter.addr
  br label %iteration.cond

iteration.end:
  %sink.final = load i64, ptr %sink.addr
  ret i64 %sink.final
}}
""".lstrip()


C_SOURCE = f"""
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

__attribute__((noinline)) int64_t nested_mix(int64_t limit, int64_t iterations) {{
    int64_t sink = 0;
    for (int64_t iter = 0; iter < iterations; iter++) {{
        int64_t total = 0;
        for (int64_t outer = 0; outer < limit; outer++) {{
            for (int64_t inner = 0; inner < limit; inner++) {{
                total = (total + outer * 31 + inner * 17 + iter) % {MODULUS};
            }}
        }}
        sink ^= total;
    }}
    return sink;
}}

int main(int argc, char **argv) {{
    int64_t limit = argc > 1 ? atoll(argv[1]) : {LIMIT};
    int64_t iterations = argc > 2 ? atoll(argv[2]) : {ITERATIONS_NATIVE};
    printf("%lld\\n", (long long)nested_mix(limit, iterations));
    return 0;
}}
""".lstrip()


C_HARNESS_SOURCE = f"""
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

extern int64_t RangeLLVM_nestedMix(int64_t limit, int64_t iterations);

int main(int argc, char **argv) {{
    int64_t limit = argc > 1 ? atoll(argv[1]) : {LIMIT};
    int64_t iterations = argc > 2 ? atoll(argv[2]) : {ITERATIONS_NATIVE};
    printf("%lld\\n", (long long)RangeLLVM_nestedMix(limit, iterations));
    return 0;
}}
""".lstrip()


RUST_SOURCE = f"""
use std::env;

#[inline(never)]
fn nested_mix(limit: i64, iterations: i64) -> i64 {{
    let mut sink = 0_i64;
    let mut iter = 0_i64;
    while iter < iterations {{
        let mut total = 0_i64;
        let mut outer = 0_i64;
        while outer < limit {{
            let mut inner = 0_i64;
            while inner < limit {{
                total = (total + outer * 31 + inner * 17 + iter) % {MODULUS};
                inner += 1;
            }}
            outer += 1;
        }}
        sink ^= total;
        iter += 1;
    }}
    sink
}}

fn main() {{
    let args: Vec<String> = env::args().collect();
    let limit = args.get(1).and_then(|v| v.parse::<i64>().ok()).unwrap_or({LIMIT});
    let iterations = args.get(2).and_then(|v| v.parse::<i64>().ok()).unwrap_or({ITERATIONS_NATIVE});
    println!("{{}}", nested_mix(limit, iterations));
}}
""".lstrip()


PYTHON_SOURCE = f"""
import sys

MODULUS = {MODULUS}


def nested_mix(limit, iterations):
    sink = 0
    for iteration in range(iterations):
        total = 0
        for outer in range(limit):
            for inner in range(limit):
                total = (total + outer * 31 + inner * 17 + iteration) % MODULUS
        sink ^= total
    return sink


limit = int(sys.argv[1]) if len(sys.argv) > 1 else {LIMIT}
iterations = int(sys.argv[2]) if len(sys.argv) > 2 else {ITERATIONS_SCRIPT}
print(nested_mix(limit, iterations))
""".lstrip()


JAVASCRIPT_SOURCE = f"""
const MODULUS = {MODULUS};

function nestedMix(limit, iterations) {{
  let sink = 0;
  for (let iteration = 0; iteration < iterations; iteration++) {{
    let total = 0;
    for (let outer = 0; outer < limit; outer++) {{
      for (let inner = 0; inner < limit; inner++) {{
        total = (total + outer * 31 + inner * 17 + iteration) % MODULUS;
      }}
    }}
    sink = (sink ^ total) | 0;
  }}
  return sink;
}}

const limit = Number(process.argv[2] || {LIMIT});
const iterations = Number(process.argv[3] || {ITERATIONS_SCRIPT});
console.log(nestedMix(limit, iterations));
""".lstrip()


def run(command, cwd=None):
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "command failed:\n"
            + " ".join(command)
            + "\nstdout:\n"
            + result.stdout
            + "\nstderr:\n"
            + result.stderr
        )
    return result


def time_command(command, cwd=None):
    started = time.perf_counter_ns()
    result = run(command, cwd=cwd)
    elapsed = time.perf_counter_ns() - started
    return elapsed / 1_000_000, result.stdout.strip()


def median(values):
    return statistics.median(values)


def main():
    tools = {
        "clang": shutil.which("clang"),
        "rustc": shutil.which("rustc"),
        "python3": shutil.which("python3"),
        "node": shutil.which("node"),
    }

    print(f"limit={LIMIT}")
    print(f"native_iterations={ITERATIONS_NATIVE}")
    print(f"script_iterations={ITERATIONS_SCRIPT}")
    print(f"repeats={REPEATS}")
    print()

    with tempfile.TemporaryDirectory(prefix="range-scalar-bench.") as tmp:
        work = Path(tmp)

        (work / "range.ll").write_text(RANGE_LLVM_IR)
        (work / "range_harness.c").write_text(C_HARNESS_SOURCE)
        (work / "baseline.c").write_text(C_SOURCE)
        (work / "baseline.rs").write_text(RUST_SOURCE)
        (work / "baseline.py").write_text(PYTHON_SOURCE)
        (work / "baseline.js").write_text(JAVASCRIPT_SOURCE)

        benchmarks = []

        if tools["clang"]:
            run([
                tools["clang"],
                "-O3",
                str(work / "range.ll"),
                str(work / "range_harness.c"),
                "-o",
                str(work / "range_llvm"),
            ])
            run([
                tools["clang"],
                "-O3",
                str(work / "baseline.c"),
                "-o",
                str(work / "baseline_c"),
            ])
            benchmarks.append(("Range LLVM", [str(work / "range_llvm"), str(LIMIT), str(ITERATIONS_NATIVE)]))
            benchmarks.append(("C clang", [str(work / "baseline_c"), str(LIMIT), str(ITERATIONS_NATIVE)]))

        if tools["rustc"]:
            run([
                tools["rustc"],
                "-C",
                "opt-level=3",
                str(work / "baseline.rs"),
                "-o",
                str(work / "baseline_rust"),
            ])
            benchmarks.append(("Rust rustc", [str(work / "baseline_rust"), str(LIMIT), str(ITERATIONS_NATIVE)]))

        if tools["python3"]:
            benchmarks.append(("Python", [tools["python3"], str(work / "baseline.py"), str(LIMIT), str(ITERATIONS_SCRIPT)]))

        if tools["node"]:
            benchmarks.append(("JavaScript node", [tools["node"], str(work / "baseline.js"), str(LIMIT), str(ITERATIONS_SCRIPT)]))

        rows = []
        expected = None
        for name, command in benchmarks:
            times = []
            output = None
            for _ in range(REPEATS):
                elapsed_ms, output = time_command(command)
                times.append(elapsed_ms)
            if expected is None:
                expected = output
            status = "ok" if output == expected else f"mismatch expected {expected}"
            rows.append((name, output, min(times), median(times), max(times), status))

        print(f"{'name':<18} {'result':>14} {'min_ms':>12} {'median_ms':>12} {'max_ms':>12} status")
        for name, output, min_ms, median_ms, max_ms, status in rows:
            print(f"{name:<18} {output:>14} {min_ms:12.3f} {median_ms:12.3f} {max_ms:12.3f} {status}")


if __name__ == "__main__":
    main()
