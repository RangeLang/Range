#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import statistics
import subprocess
import textwrap
import time
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / "Development" / "Benchmarks" / "Speed" / ".build" / "nested-billion"
OUTER = int(os.environ.get("OUTER", "1000"))
INNER = int(os.environ.get("INNER", "1000000"))
RUNS = int(os.environ.get("RUNS", "1"))


@dataclass(frozen=True)
class Measurement:
    wall_seconds: float
    output: str


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(value).strip() + "\n", encoding="utf-8")


def run(command: list[str], cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


def try_run(command: list[str], cwd: Path = ROOT) -> subprocess.CompletedProcess[str] | None:
    try:
        return run(command, cwd)
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout.strip())
        if error.stderr:
            print(error.stderr.strip())
        return None


def measure(command: list[str]) -> Measurement:
    samples: list[float] = []
    output = ""
    for _ in range(RUNS):
        started = time.perf_counter()
        completed = run(command)
        elapsed = time.perf_counter() - started
        current_output = completed.stdout.strip()
        if output and current_output != output:
            raise SystemExit(f"inconsistent output: {current_output} != {output}")
        output = current_output
        samples.append(elapsed)
    return Measurement(statistics.median(samples), output)


def main() -> int:
    if shutil.which("cc") is None:
        raise SystemExit("missing cc")

    range_cli = ROOT / "scripts" / "range"

    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir(parents=True)

    c_source = BUILD / "main.c"
    c_binary = BUILD / "nested-c"
    range_project = BUILD / "RangeNested"
    range_binary = range_project / ".range" / "Build" / "llvm" / "Playground"

    write_text(
        c_source,
        """
        #include <inttypes.h>
        #include <stdint.h>
        #include <stdio.h>
        #include <stdlib.h>

        int main(int argc, char **argv) {
            int64_t outer = argc > 1 ? atoll(argv[1]) : 1000;
            int64_t inner = argc > 2 ? atoll(argv[2]) : 1000000;
            int64_t acc = 1;

            for (int64_t i = 0; i < outer; i++) {
                for (int64_t j = 0; j < inner; j++) {
                    acc = (acc * 1664525 + i + j) % 2147483647;
                }
            }

            printf("%" PRId64 "\\n", acc);
            return 0;
        }
        """,
    )
    run(["cc", "-O3", str(c_source), "-o", str(c_binary)])

    write_text(
        range_project / "Playground.range",
        f"""
        @main {{
            let outer: Int({OUTER})
            let inner: Int({INNER})
            state i: Int(0)
            state acc: Int(1)

            while i < outer {{
                state j: Int(0)
                while j < inner {{
                    acc: ((acc * 1664525) + i + j) % 2147483647
                    j: j + 1
                }}
                i: i + 1
            }}

            print(value: acc)
        }}
        """,
    )

    range_build = try_run([str(range_cli), "run", str(range_project / "Playground.range")])
    range_label = "Range LLVM"
    if range_build is None:
        raise SystemExit("Range LLVM build failed")

    if not range_binary.is_file():
        raise SystemExit(f"Range binary not found: {range_binary}")

    iterations = OUTER * INNER
    print(f"nested loop iterations: {OUTER} x {INNER} = {iterations}")
    print(f"runs: {RUNS}")
    print()

    c = measure([str(c_binary), str(OUTER), str(INNER)])
    print(f"C:     {c.wall_seconds:.3f}s output={c.output}")

    range_measurement = measure([str(range_binary)])
    relative = range_measurement.wall_seconds / c.wall_seconds if c.wall_seconds else 0
    print(f"{range_label}: {range_measurement.wall_seconds:.3f}s output={range_measurement.output}")
    print(f"Range/C wall time: {relative:.2f}x")

    if c.output != range_measurement.output:
        print("warning: outputs differ; Range Int currently lowers to i32 while C uses int64_t here")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
