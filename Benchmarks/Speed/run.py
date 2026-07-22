#!/usr/bin/env python3
from __future__ import annotations

import filecmp
import json
import os
import platform
import plistlib
import shutil
import statistics
import subprocess
import sys
import tempfile
import textwrap
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "Benchmarks" / "Speed"
BUILD = BENCH / ".build"
RESULTS = BENCH / "results"
SITE_RESULTS = ROOT / "Website" / "public" / "benchmarks.json"
SEED_MANIFEST = ROOT / "RangeCompiler" / "Bootstrap" / "RangeCompilerSeed.json"
STAGE2_COMPILER = (
    ROOT / "RangeCompiler" / "Range" / "Programs" / "Compiler" / ".range" / "Build" / "stage2" / "RangeCompiler"
)
STAGE3_COMPILER = (
    ROOT / "RangeCompiler" / "Range" / "Programs" / "Compiler" / ".range" / "Build" / "stage3" / "RangeCompiler"
)
ITERATIONS = int(os.environ.get("N", "1000000"))
RUNS = int(os.environ.get("RUNS", "5"))
CASE_FILTER = {
    value.strip().lower()
    for value in os.environ.get("CASES", "").split(",")
    if value.strip()
}
VERBOSE = os.environ.get("VERBOSE") == "1"


@dataclass(frozen=True)
class BenchmarkCase:
    name: str
    category: str
    subcategory: str
    leaf: str
    unit: str
    description: str
    expected_output: str
    expected_exit_code: int
    range_expected_exit_code: int
    n: int
    c: str
    cxx: str
    rust: str
    go: str
    swift: str
    typescript: str
    range_source: str


@dataclass(frozen=True)
class BenchTarget:
    language: str
    command: list[str]
    expected_exit_code: int = 0


@dataclass(frozen=True)
class Measurement:
    wall_seconds: float
    cpu_seconds: float
    peak_rss_kb: int
    output: str


def run_command(
    command: list[str],
    cwd: Path = ROOT,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    process_env = os.environ.copy()
    if env:
        process_env.update(env)
    return subprocess.run(
        command,
        cwd=cwd,
        env=process_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


def measured_command(
    command: list[str],
    cwd: Path = ROOT,
    expected_exit_code: int = 0,
) -> Measurement:
    started = time.perf_counter()

    with tempfile.TemporaryFile(mode="w+t", encoding="utf-8") as stdout_file:
        with tempfile.TemporaryFile(mode="w+t", encoding="utf-8") as stderr_file:
            process = subprocess.Popen(
                command,
                cwd=cwd,
                text=True,
                stdout=stdout_file,
                stderr=stderr_file,
            )
            _, status, usage = os.wait4(process.pid, 0)
            stdout_file.seek(0)
            stderr_file.seek(0)
            stdout = stdout_file.read()
            stderr = stderr_file.read()

    elapsed = time.perf_counter() - started
    cpu_seconds = max(0.0, usage.ru_utime + usage.ru_stime)
    returncode = os.waitstatus_to_exitcode(status)

    if returncode != expected_exit_code:
        raise subprocess.CalledProcessError(
            returncode,
            command,
            output=stdout,
            stderr=stderr,
        )

    return Measurement(
        wall_seconds=elapsed,
        cpu_seconds=cpu_seconds,
        peak_rss_kb=peak_rss_kb(usage.ru_maxrss),
        output=stdout.strip() or f"exit:{returncode}",
    )


def peak_rss_kb(raw_rss: int) -> int:
    if raw_rss <= 0:
        return 0
    if sys.platform == "darwin":
        return raw_rss // 1024
    return raw_rss


def timed_setup(
    label: str,
    command: list[str],
    cwd: Path = ROOT,
    env: dict[str, str] | None = None,
) -> bool:
    started = time.perf_counter()
    try:
        run_command(command, cwd, env)
    except subprocess.CalledProcessError as error:
        print(f"{label}: setup failed", file=sys.stderr)
        if VERBOSE:
            if error.stdout:
                print(error.stdout, file=sys.stderr)
            if error.stderr:
                print(error.stderr, file=sys.stderr)
        else:
            print("Set VERBOSE=1 to show the full setup log.", file=sys.stderr)
        return False
    elapsed = time.perf_counter() - started
    print(f"{label}: setup {elapsed:.2f}s")
    return True


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        raise SystemExit(f"Missing required tool: {name}")


def optional_tool(name: str) -> str | None:
    path = shutil.which(name)
    if path is None:
        print(f"{name}: unavailable; its benchmark rows will be skipped")
    return path


def embedded_swift_env() -> dict[str, str] | None:
    explicit = os.environ.get("RANGE_SWIFT_TOOLCHAINS") or os.environ.get("TOOLCHAINS")
    if explicit:
        return {"TOOLCHAINS": explicit}

    toolchain_roots = [
        Path.home() / "Library" / "Developer" / "Toolchains",
        Path("/Library/Developer/Toolchains"),
    ]
    for root in toolchain_roots:
        if not root.exists():
            continue
        for toolchain in sorted(root.glob("*.xctoolchain")):
            if not (toolchain / "usr" / "lib" / "swift" / "embedded").is_dir():
                continue
            info_path = toolchain / "Info.plist"
            try:
                with info_path.open("rb") as handle:
                    identifier = plistlib.load(handle).get("CFBundleIdentifier")
            except OSError:
                continue
            if isinstance(identifier, str) and identifier:
                return {"TOOLCHAINS": identifier}

    return None


def package_manifest(name: str) -> str:
    return f"""@Project
construct Project {{
    let name: Title("{name}")
    let version: Version(0.1.0)
    let author: "George"
}}
"""


def integer_loop_output(n: int) -> str:
    acc = 1
    for i in range(n):
        acc = (acc + i * 3 + 1) % 1_000_003
    return str(acc)


def if_loop_output(n: int) -> str:
    acc = 1
    for i in range(n):
        if i % 4 != 0:
            acc = (acc + i * 3 + 1) % 1_000_003
    return str(acc)


def if_else_loop_output(n: int) -> str:
    acc = 1
    for i in range(n):
        if i % 2 == 0:
            acc = (acc + i * 3 + 1) % 1_000_003
        else:
            acc = (acc + i * 5 + 2) % 1_000_003
    return str(acc)


def generic_calls_output(n: int) -> str:
    pairs = n // 2
    return str(2 * pairs * pairs + (2 * pairs + 1 if n % 2 else 0))


def collections_output(n: int) -> str:
    values = (0, 1, 2, 3, 4, 5, 6, 7)
    return str(sum(value * 2 for value in (values[index % 8] for index in range(n)) if value % 2 == 0))


def convolution_output(n: int) -> str:
    values = (1, 3, 5, 7, 11, 13, 17, 19)
    acc = 0
    for i in range(n):
        center = i % len(values)
        left = (center - 1) % len(values)
        right = (center + 1) % len(values)
        acc = (acc + values[left] + values[center] * 2 + values[right]) % 1_000_003
    return str(acc)


def constructs_output(n: int) -> str:
    return str((n * n) % 1_000_003)


def fibonacci(value: int) -> int:
    if value < 2:
        return value
    return fibonacci(value - 1) + fibonacci(value - 2)


def recursion_output(repeats: int, depth: int) -> str:
    even_count = (repeats + 1) // 2
    odd_count = repeats // 2
    total = fibonacci(depth) * even_count + fibonacci(depth + 1) * odd_count
    return str(total % 1_000_003)


def selected_cases() -> list[BenchmarkCase]:
    available = cases()
    if not CASE_FILTER:
        return available

    selected = [
        case
        for case in available
        if case.name.lower() in CASE_FILTER
        or case.category.lower() in CASE_FILTER
        or case.subcategory.lower() in CASE_FILTER
    ]
    if selected:
        return selected

    choices = ", ".join(case.name for case in available)
    raise SystemExit(f"CASES did not match any evaluations. Available: {choices}")


def cases() -> list[BenchmarkCase]:
    n = ITERATIONS
    small = max(1, n // 10)
    recursion_repeats = max(1, n // 10_000)
    recursion_depth = 20

    return [
        BenchmarkCase(
            name="integer_loop",
            category="Loops",
            subcategory="While",
            leaf="Sequential modulo",
            unit="iterations",
            description="Sequential integer arithmetic and modulo dependency chain",
            expected_output=integer_loop_output(n),
            expected_exit_code=0,
            range_expected_exit_code=int(integer_loop_output(n)) % 251,
            n=n,
            c=rf"""
                #include <inttypes.h>
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                int main(int argc, char **argv) {{
                    int64_t n = argc > 1 ? atoll(argv[1]) : {n};
                    int64_t i = 0;
                    int64_t acc = 1;
                    while (i < n) {{
                        acc = (acc + i * 3 + 1) % 1000003;
                        i += 1;
                    }}
                    printf("%" PRId64 "\n", acc);
                }}
            """,
            cxx=rf"""
                #include <cstdint>
                #include <cstdlib>
                #include <iostream>
                int main(int argc, char **argv) {{
                    std::int64_t n = argc > 1 ? std::atoll(argv[1]) : {n};
                    std::int64_t i = 0, acc = 1;
                    while (i < n) {{ acc = (acc + i * 3 + 1) % 1000003; ++i; }}
                    std::cout << acc << '\n';
                }}
            """,
            rust=rf"""
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({n});
                    let mut i: i64 = 0;
                    let mut acc: i64 = 1;
                    while i < n {{
                        acc = (acc + i * 3 + 1) % 1_000_003;
                        i += 1;
                    }}
                    println!("{{acc}}");
                }}
            """,
            go=rf"""
                package main
                import ("fmt"; "os"; "strconv")
                func main() {{
                    n := int64({n}); if len(os.Args) > 1 {{ n, _ = strconv.ParseInt(os.Args[1], 10, 64) }}
                    var i int64; acc := int64(1)
                    for i < n {{ acc = (acc + i*3 + 1) % 1000003; i++ }}
                    fmt.Println(acc)
                }}
            """,
            swift=rf"""
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int64.init) ?? {n}
                var i: Int64 = 0
                var acc: Int64 = 1
                while i < n {{
                    acc = (acc + i * 3 + 1) % 1_000_003
                    i += 1
                }}
                print(acc)
            """,
            typescript=rf"""
                const n = Number((globalThis as any).Bun.argv[2] ?? {n});
                let i = 0, acc = 1;
                while (i < n) {{ acc = (acc + i * 3 + 1) % 1000003; i++; }}
                console.log(acc);
            """,
            range_source=rf"""
                @main {{
                    let n: Int({n})
                    state i: Int(0)
                    state acc: Int(1)
                    while i < n {{
                        acc: (acc + i * 3 + 1) % 1000003
                        i: i + 1
                    }}
                    return acc % 251
                }}
            """,
        ),
        BenchmarkCase(
            name="loop_if",
            category="Loops",
            subcategory="If",
            leaf="75% taken",
            unit="iterations",
            description="Repeated one-sided conditional with a 75% taken branch",
            expected_output=if_loop_output(n),
            expected_exit_code=0,
            range_expected_exit_code=int(if_loop_output(n)) % 251,
            n=n,
            c=rf"""
                #include <inttypes.h>
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                int main(int argc, char **argv) {{
                    int64_t n = argc > 1 ? atoll(argv[1]) : {n};
                    int64_t i = 0, acc = 1;
                    while (i < n) {{
                        if (i % 4 != 0) acc = (acc + i * 3 + 1) % 1000003;
                        i += 1;
                    }}
                    printf("%" PRId64 "\n", acc);
                }}
            """,
            cxx=rf"""
                #include <cstdint>
                #include <cstdlib>
                #include <iostream>
                int main(int argc, char **argv) {{
                    std::int64_t n = argc > 1 ? std::atoll(argv[1]) : {n};
                    std::int64_t i = 0, acc = 1;
                    while (i < n) {{
                        if (i % 4 != 0) acc = (acc + i * 3 + 1) % 1000003;
                        ++i;
                    }}
                    std::cout << acc << '\n';
                }}
            """,
            rust=rf"""
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({n});
                    let mut i: i64 = 0;
                    let mut acc: i64 = 1;
                    while i < n {{
                        if i % 4 != 0 {{ acc = (acc + i * 3 + 1) % 1_000_003; }}
                        i += 1;
                    }}
                    println!("{{acc}}");
                }}
            """,
            go=rf"""
                package main
                import ("fmt"; "os"; "strconv")
                func main() {{
                    n := int64({n}); if len(os.Args) > 1 {{ n, _ = strconv.ParseInt(os.Args[1], 10, 64) }}
                    var i int64; acc := int64(1)
                    for i < n {{
                        if i%4 != 0 {{ acc = (acc + i*3 + 1) % 1000003 }}
                        i++
                    }}
                    fmt.Println(acc)
                }}
            """,
            swift=rf"""
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int64.init) ?? {n}
                var i: Int64 = 0
                var acc: Int64 = 1
                while i < n {{
                    if i % 4 != 0 {{
                        acc = (acc + i * 3 + 1) % 1_000_003
                    }}
                    i += 1
                }}
                print(acc)
            """,
            typescript=rf"""
                const n = Number((globalThis as any).Bun.argv[2] ?? {n});
                let i = 0, acc = 1;
                while (i < n) {{
                    if (i % 4 !== 0) acc = (acc + i * 3 + 1) % 1000003;
                    i++;
                }}
                console.log(acc);
            """,
            range_source=rf"""
                @main {{
                    let n: Int({n})
                    state i: Int(0)
                    state acc: Int(1)
                    while i < n {{
                        if i % 4 != 0 {{
                            acc: (acc + i * 3 + 1) % 1000003
                        }}
                        i: i + 1
                    }}
                    return acc % 251
                }}
            """,
        ),
        BenchmarkCase(
            name="loop_if_else",
            category="Loops",
            subcategory="If Else",
            leaf="Balanced alternating",
            unit="iterations",
            description="Repeated balanced two-outcome conditional",
            expected_output=if_else_loop_output(n),
            expected_exit_code=0,
            range_expected_exit_code=int(if_else_loop_output(n)) % 251,
            n=n,
            c=rf"""
                #include <inttypes.h>
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                int main(int argc, char **argv) {{
                    int64_t n = argc > 1 ? atoll(argv[1]) : {n};
                    int64_t i = 0, acc = 1;
                    while (i < n) {{
                        if (i % 2 == 0) acc = (acc + i * 3 + 1) % 1000003;
                        else acc = (acc + i * 5 + 2) % 1000003;
                        i += 1;
                    }}
                    printf("%" PRId64 "\n", acc);
                }}
            """,
            cxx=rf"""
                #include <cstdint>
                #include <cstdlib>
                #include <iostream>
                int main(int argc, char **argv) {{
                    std::int64_t n = argc > 1 ? std::atoll(argv[1]) : {n};
                    std::int64_t i = 0, acc = 1;
                    while (i < n) {{
                        if (i % 2 == 0) acc = (acc + i * 3 + 1) % 1000003;
                        else acc = (acc + i * 5 + 2) % 1000003;
                        ++i;
                    }}
                    std::cout << acc << '\n';
                }}
            """,
            rust=rf"""
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({n});
                    let mut i: i64 = 0;
                    let mut acc: i64 = 1;
                    while i < n {{
                        if i % 2 == 0 {{ acc = (acc + i * 3 + 1) % 1_000_003; }}
                        else {{ acc = (acc + i * 5 + 2) % 1_000_003; }}
                        i += 1;
                    }}
                    println!("{{acc}}");
                }}
            """,
            go=rf"""
                package main
                import ("fmt"; "os"; "strconv")
                func main() {{
                    n := int64({n}); if len(os.Args) > 1 {{ n, _ = strconv.ParseInt(os.Args[1], 10, 64) }}
                    var i int64; acc := int64(1)
                    for i < n {{
                        if i%2 == 0 {{ acc = (acc + i*3 + 1) % 1000003 }} else {{ acc = (acc + i*5 + 2) % 1000003 }}
                        i++
                    }}
                    fmt.Println(acc)
                }}
            """,
            swift=rf"""
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int64.init) ?? {n}
                var i: Int64 = 0
                var acc: Int64 = 1
                while i < n {{
                    if i % 2 == 0 {{
                        acc = (acc + i * 3 + 1) % 1_000_003
                    }} else {{
                        acc = (acc + i * 5 + 2) % 1_000_003
                    }}
                    i += 1
                }}
                print(acc)
            """,
            typescript=rf"""
                const n = Number((globalThis as any).Bun.argv[2] ?? {n});
                let i = 0, acc = 1;
                while (i < n) {{
                    if (i % 2 === 0) acc = (acc + i * 3 + 1) % 1000003;
                    else acc = (acc + i * 5 + 2) % 1000003;
                    i++;
                }}
                console.log(acc);
            """,
            range_source=rf"""
                @main {{
                    let n: Int({n})
                    state i: Int(0)
                    state acc: Int(1)
                    while i < n {{
                        if i % 2 == 0 {{
                            acc: (acc + i * 3 + 1) % 1000003
                        }} else {{
                            acc: (acc + i * 5 + 2) % 1000003
                        }}
                        i: i + 1
                    }}
                    return acc % 251
                }}
            """,
        ),
        BenchmarkCase(
            name="perlin_noise",
            category="Noise",
            subcategory="Perlin",
            leaf="2D single cell",
            unit="samples",
            description="Two-dimensional single-cell Perlin gradient interpolation",
            expected_output="exit:1" if n > 0 else "exit:0",
            expected_exit_code=1 if n > 0 else 0,
            range_expected_exit_code=1 if n > 0 else 0,
            n=n,
            c=rf"""
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                static inline double fade(double value) {{
                    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
                }}
                static inline double noise(double x, double y) {{
                    double u = fade(x), v = fade(y);
                    double n00 = x * 0.8 + y * 0.6;
                    double n10 = (x - 1.0) * -0.6 + y * 0.8;
                    double n01 = x * 0.3 + (y - 1.0) * -0.95;
                    double n11 = (x - 1.0) * -0.8 + (y - 1.0) * -0.6;
                    double lower = n00 * (1.0 - u) + n10 * u;
                    double upper = n01 * (1.0 - u) + n11 * u;
                    return lower * (1.0 - v) + upper * v;
                }}
                int main(int argc, char **argv) {{
                    int64_t n = argc > 1 ? atoll(argv[1]) : {n};
                    double total = 0.0, x = 0.37, y = 0.61;
                    for (int64_t i = 0; i < n; ++i) {{
                        total += noise(x, y);
                        x += 0.000013; if (x > 1.0) x -= 1.0;
                        y += 0.000017; if (y > 1.0) y -= 1.0;
                    }}
                    return total != 0.0 ? 1 : 0;
                }}
            """,
            cxx=rf"""
                #include <cstdint>
                #include <cstdlib>
                #include <iostream>
                static inline double fade(double value) {{
                    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
                }}
                static inline double noise(double x, double y) {{
                    double u = fade(x), v = fade(y);
                    double n00 = x * 0.8 + y * 0.6;
                    double n10 = (x - 1.0) * -0.6 + y * 0.8;
                    double n01 = x * 0.3 + (y - 1.0) * -0.95;
                    double n11 = (x - 1.0) * -0.8 + (y - 1.0) * -0.6;
                    double lower = n00 * (1.0 - u) + n10 * u;
                    double upper = n01 * (1.0 - u) + n11 * u;
                    return lower * (1.0 - v) + upper * v;
                }}
                int main(int argc, char **argv) {{
                    std::int64_t n = argc > 1 ? std::atoll(argv[1]) : {n};
                    double total = 0.0, x = 0.37, y = 0.61;
                    for (std::int64_t i = 0; i < n; ++i) {{
                        total += noise(x, y);
                        x += 0.000013; if (x > 1.0) x -= 1.0;
                        y += 0.000017; if (y > 1.0) y -= 1.0;
                    }}
                    return total != 0.0 ? 1 : 0;
                }}
            """,
            rust=rf"""
                fn fade(value: f64) -> f64 {{
                    value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
                }}
                fn noise(x: f64, y: f64) -> f64 {{
                    let (u, v) = (fade(x), fade(y));
                    let n00 = x * 0.8 + y * 0.6;
                    let n10 = (x - 1.0) * -0.6 + y * 0.8;
                    let n01 = x * 0.3 + (y - 1.0) * -0.95;
                    let n11 = (x - 1.0) * -0.8 + (y - 1.0) * -0.6;
                    let lower = n00 * (1.0 - u) + n10 * u;
                    let upper = n01 * (1.0 - u) + n11 * u;
                    lower * (1.0 - v) + upper * v
                }}
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({n});
                    let mut total = 0.0;
                    let (mut x, mut y) = (0.37, 0.61);
                    for _ in 0..n {{
                        total += noise(x, y);
                        x += 0.000013; if x > 1.0 {{ x -= 1.0; }}
                        y += 0.000017; if y > 1.0 {{ y -= 1.0; }}
                    }}
                    std::process::exit(if total != 0.0 {{ 1 }} else {{ 0 }});
                }}
            """,
            go=rf"""
                package main
                import ("os"; "strconv")
                func fade(value float64) float64 {{
                    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
                }}
                func main() {{
                    n := int64({n}); if len(os.Args) > 1 {{ n, _ = strconv.ParseInt(os.Args[1], 10, 64) }}
                    total, x, y := 0.0, 0.37, 0.61
                    for i := int64(0); i < n; i++ {{
                        u, v := fade(x), fade(y)
                        n00, n10 := x*0.8+y*0.6, (x-1.0)*-0.6+y*0.8
                        n01, n11 := x*0.3+(y-1.0)*-0.95, (x-1.0)*-0.8+(y-1.0)*-0.6
                        lower, upper := n00*(1.0-u)+n10*u, n01*(1.0-u)+n11*u
                        total += lower*(1.0-v)+upper*v
                        x += 0.000013; if x > 1.0 {{ x -= 1.0 }}
                        y += 0.000017; if y > 1.0 {{ y -= 1.0 }}
                    }}
                    if total != 0.0 {{ os.Exit(1) }}
                }}
            """,
            swift=rf"""
                import Darwin
                @inline(__always) func fade(_ value: Double) -> Double {{
                    value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
                }}
                @inline(__always) func noise(_ x: Double, _ y: Double) -> Double {{
                    let (u, v) = (fade(x), fade(y))
                    let n00 = x * 0.8 + y * 0.6
                    let n10 = (x - 1.0) * -0.6 + y * 0.8
                    let n01 = x * 0.3 + (y - 1.0) * -0.95
                    let n11 = (x - 1.0) * -0.8 + (y - 1.0) * -0.6
                    let lower = n00 * (1.0 - u) + n10 * u
                    let upper = n01 * (1.0 - u) + n11 * u
                    return lower * (1.0 - v) + upper * v
                }}
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {n}
                var total = 0.0
                var x = 0.37, y = 0.61
                for _ in 0..<n {{
                    total += noise(x, y)
                    x += 0.000013; if x > 1.0 {{ x -= 1.0 }}
                    y += 0.000017; if y > 1.0 {{ y -= 1.0 }}
                }}
                exit(total != 0.0 ? 1 : 0)
            """,
            typescript=rf"""
                function fade(value: number): number {{
                    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
                }}
                function noise(x: number, y: number): number {{
                    const u = fade(x), v = fade(y);
                    const n00 = x*0.8+y*0.6, n10 = (x-1.0)*-0.6+y*0.8;
                    const n01 = x*0.3+(y-1.0)*-0.95, n11 = (x-1.0)*-0.8+(y-1.0)*-0.6;
                    const lower = n00*(1.0-u)+n10*u, upper = n01*(1.0-u)+n11*u;
                    return lower*(1.0-v)+upper*v;
                }}
                const n = Number((globalThis as any).Bun.argv[2] ?? {n});
                let total = 0.0, x = 0.37, y = 0.61;
                for (let i = 0; i < n; i++) {{
                    total += noise(x, y);
                    x += 0.000013; if (x > 1.0) x -= 1.0;
                    y += 0.000017; if (y > 1.0) y -= 1.0;
                }}
                (globalThis as any).process.exit(total !== 0.0 ? 1 : 0);
            """,
            range_source=rf"""
                function fade(value: Float): Float {{
                    return value * value * value * (value * (value * Float(6.0) - Float(15.0)) + Float(10.0))
                }}

                function perlinNoise(x: Float, y: Float): Float {{
                    let u: Float(fade(value: x))
                    let v: Float(fade(value: y))
                    let n00: Float(x * Float(0.8) + y * Float(0.6))
                    let n10: Float((x - Float(1.0)) * Float(0.0 - 0.6) + y * Float(0.8))
                    let n01: Float(x * Float(0.3) + (y - Float(1.0)) * Float(0.0 - 0.95))
                    let n11: Float((x - Float(1.0)) * Float(0.0 - 0.8) + (y - Float(1.0)) * Float(0.0 - 0.6))
                    let lower: Float(n00 * (Float(1.0) - u) + n10 * u)
                    let upper: Float(n01 * (Float(1.0) - u) + n11 * u)
                    return lower * (Float(1.0) - v) + upper * v
                }}

                @main {{
                    state total: Float(0.0)
                    state index: Int(0)
                    state x: Float(0.37)
                    state y: Float(0.61)
                    while index < {n} {{
                        let sample: Float(perlinNoise(x: x, y: y))
                        total: total + sample
                        index: index + 1
                        x: x + Float(0.000013)
                        if x > Float(1.0) {{ x: x - Float(1.0) }}
                        y: y + Float(0.000017)
                        if y > Float(1.0) {{ y: y - Float(1.0) }}
                    }}
                    if total != Float(0.0) {{
                        return 1
                    }}
                    return 0
                }}
            """,
        ),
        BenchmarkCase(
            name="voronoi_noise",
            category="Noise",
            subcategory="Voronoi",
            leaf="Three feature points",
            unit="samples",
            description="Squared distance to the nearest of three two-dimensional feature points",
            expected_output="exit:1" if n > 0 else "exit:0",
            expected_exit_code=1 if n > 0 else 0,
            range_expected_exit_code=1 if n > 0 else 0,
            n=n,
            c=rf"""
                #include <stdint.h>
                #include <stdlib.h>
                int main(int argc, char **argv) {{
                    int64_t n = argc > 1 ? atoll(argv[1]) : {n};
                    double total = 0.0, x = 0.13, y = 0.27;
                    for (int64_t i = 0; i < n; ++i) {{
                        double ax=x-0.20, ay=y-0.30, bx=x-0.70, by=y-0.80, cx=x-0.40, cy=y-0.65;
                        double best=ax*ax+ay*ay, second=bx*bx+by*by, third=cx*cx+cy*cy;
                        if (second < best) best = second;
                        if (third < best) best = third;
                        total += best;
                        x += 0.000013; if (x > 1.0) x -= 1.0;
                        y += 0.000017; if (y > 1.0) y -= 1.0;
                    }}
                    return total != 0.0 ? 1 : 0;
                }}
            """,
            cxx=rf"""
                #include <cstdint>
                #include <cstdlib>
                int main(int argc, char **argv) {{
                    std::int64_t n = argc > 1 ? std::atoll(argv[1]) : {n};
                    double total = 0.0, x = 0.13, y = 0.27;
                    for (std::int64_t i = 0; i < n; ++i) {{
                        double ax=x-0.20, ay=y-0.30, bx=x-0.70, by=y-0.80, cx=x-0.40, cy=y-0.65;
                        double best=ax*ax+ay*ay, second=bx*bx+by*by, third=cx*cx+cy*cy;
                        if (second < best) best = second;
                        if (third < best) best = third;
                        total += best;
                        x += 0.000013; if (x > 1.0) x -= 1.0;
                        y += 0.000017; if (y > 1.0) y -= 1.0;
                    }}
                    return total != 0.0 ? 1 : 0;
                }}
            """,
            rust=rf"""
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({n});
                    let (mut total, mut x, mut y) = (0.0, 0.13, 0.27);
                    for _ in 0..n {{
                        let (ax, ay, bx, by, cx, cy) = (x-0.20, y-0.30, x-0.70, y-0.80, x-0.40, y-0.65);
                        let (mut best, second, third) = (ax*ax+ay*ay, bx*bx+by*by, cx*cx+cy*cy);
                        if second < best {{ best = second; }}
                        if third < best {{ best = third; }}
                        total += best;
                        x += 0.000013; if x > 1.0 {{ x -= 1.0; }}
                        y += 0.000017; if y > 1.0 {{ y -= 1.0; }}
                    }}
                    std::process::exit(if total != 0.0 {{ 1 }} else {{ 0 }});
                }}
            """,
            go=rf"""
                package main
                import ("os"; "strconv")
                func main() {{
                    n := int64({n}); if len(os.Args) > 1 {{ n, _ = strconv.ParseInt(os.Args[1], 10, 64) }}
                    total, x, y := 0.0, 0.13, 0.27
                    for i := int64(0); i < n; i++ {{
                        ax, ay, bx, by, cx, cy := x-0.20, y-0.30, x-0.70, y-0.80, x-0.40, y-0.65
                        best, second, third := ax*ax+ay*ay, bx*bx+by*by, cx*cx+cy*cy
                        if second < best {{ best = second }}
                        if third < best {{ best = third }}
                        total += best
                        x += 0.000013; if x > 1.0 {{ x -= 1.0 }}
                        y += 0.000017; if y > 1.0 {{ y -= 1.0 }}
                    }}
                    if total != 0.0 {{ os.Exit(1) }}
                }}
            """,
            swift=rf"""
                import Darwin
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {n}
                var total = 0.0, x = 0.13, y = 0.27
                for _ in 0..<n {{
                    let (ax, ay, bx, by, cx, cy) = (x-0.20, y-0.30, x-0.70, y-0.80, x-0.40, y-0.65)
                    var best = ax*ax+ay*ay
                    let second = bx*bx+by*by, third = cx*cx+cy*cy
                    if second < best {{ best = second }}
                    if third < best {{ best = third }}
                    total += best
                    x += 0.000013; if x > 1.0 {{ x -= 1.0 }}
                    y += 0.000017; if y > 1.0 {{ y -= 1.0 }}
                }}
                exit(total != 0.0 ? 1 : 0)
            """,
            typescript=rf"""
                const n = Number((globalThis as any).Bun.argv[2] ?? {n});
                let total = 0.0, x = 0.13, y = 0.27;
                for (let i = 0; i < n; i++) {{
                    const ax=x-0.20, ay=y-0.30, bx=x-0.70, by=y-0.80, cx=x-0.40, cy=y-0.65;
                    let best=ax*ax+ay*ay; const second=bx*bx+by*by, third=cx*cx+cy*cy;
                    if (second < best) best = second;
                    if (third < best) best = third;
                    total += best;
                    x += 0.000013; if (x > 1.0) x -= 1.0;
                    y += 0.000017; if (y > 1.0) y -= 1.0;
                }}
                (globalThis as any).process.exit(total !== 0.0 ? 1 : 0);
            """,
            range_source=rf"""
                @main {{
                    state total: Float(0.0)
                    state index: Int(0)
                    state x: Float(0.13)
                    state y: Float(0.27)
                    while index < {n} {{
                        let ax: Float(x - Float(0.20))
                        let ay: Float(y - Float(0.30))
                        let bx: Float(x - Float(0.70))
                        let by: Float(y - Float(0.80))
                        let cx: Float(x - Float(0.40))
                        let cy: Float(y - Float(0.65))
                        state best: Float(ax * ax + ay * ay)
                        let second: Float(bx * bx + by * by)
                        let third: Float(cx * cx + cy * cy)
                        if second < best {{ best: second }}
                        if third < best {{ best: third }}
                        total: total + best
                        index: index + 1
                        x: x + Float(0.000013)
                        if x > Float(1.0) {{ x: x - Float(1.0) }}
                        y: y + Float(0.000017)
                        if y > Float(1.0) {{ y: y - Float(1.0) }}
                    }}
                    if total != Float(0.0) {{ return 1 }}
                    return 0
                }}
            """,
        ),
        BenchmarkCase(
            name="value_noise",
            category="Noise",
            subcategory="Value Noise",
            leaf="Four lattice values",
            unit="samples",
            description="Two-dimensional smooth bilinear interpolation of four lattice values",
            expected_output="exit:1" if n > 0 else "exit:0",
            expected_exit_code=1 if n > 0 else 0,
            range_expected_exit_code=1 if n > 0 else 0,
            n=n,
            c=rf"""
                #include <stdint.h>
                #include <stdlib.h>
                static inline double fade(double value) {{ return value * value * (3.0 - 2.0 * value); }}
                int main(int argc, char **argv) {{
                    int64_t n = argc > 1 ? atoll(argv[1]) : {n};
                    double total=0.0, x=0.37, y=0.61;
                    for (int64_t i=0; i<n; ++i) {{
                        double u=fade(x), v=fade(y);
                        double lower=0.15*(1.0-u)+0.82*u, upper=0.44*(1.0-u)+0.67*u;
                        total += lower*(1.0-v)+upper*v;
                        x += 0.000013; if (x > 1.0) x -= 1.0;
                        y += 0.000017; if (y > 1.0) y -= 1.0;
                    }}
                    return total != 0.0 ? 1 : 0;
                }}
            """,
            cxx=rf"""
                #include <cstdint>
                #include <cstdlib>
                static inline double fade(double value) {{ return value * value * (3.0 - 2.0 * value); }}
                int main(int argc, char **argv) {{
                    std::int64_t n = argc > 1 ? std::atoll(argv[1]) : {n};
                    double total=0.0, x=0.37, y=0.61;
                    for (std::int64_t i=0; i<n; ++i) {{
                        double u=fade(x), v=fade(y);
                        double lower=0.15*(1.0-u)+0.82*u, upper=0.44*(1.0-u)+0.67*u;
                        total += lower*(1.0-v)+upper*v;
                        x += 0.000013; if (x > 1.0) x -= 1.0;
                        y += 0.000017; if (y > 1.0) y -= 1.0;
                    }}
                    return total != 0.0 ? 1 : 0;
                }}
            """,
            rust=rf"""
                #[inline(always)] fn fade(value: f64) -> f64 {{ value * value * (3.0 - 2.0 * value) }}
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({n});
                    let (mut total, mut x, mut y) = (0.0, 0.37, 0.61);
                    for _ in 0..n {{
                        let (u,v)=(fade(x),fade(y));
                        let lower=0.15*(1.0-u)+0.82*u; let upper=0.44*(1.0-u)+0.67*u;
                        total += lower*(1.0-v)+upper*v;
                        x += 0.000013; if x > 1.0 {{ x -= 1.0; }}
                        y += 0.000017; if y > 1.0 {{ y -= 1.0; }}
                    }}
                    std::process::exit(if total != 0.0 {{1}} else {{0}});
                }}
            """,
            go=rf"""
                package main
                import ("os"; "strconv")
                func fade(value float64) float64 {{ return value*value*(3.0-2.0*value) }}
                func main() {{
                    n := int64({n}); if len(os.Args)>1 {{ n,_=strconv.ParseInt(os.Args[1],10,64) }}
                    total,x,y := 0.0,0.37,0.61
                    for i:=int64(0); i<n; i++ {{
                        u,v:=fade(x),fade(y); lower:=0.15*(1.0-u)+0.82*u; upper:=0.44*(1.0-u)+0.67*u
                        total += lower*(1.0-v)+upper*v
                        x += 0.000013; if x>1.0 {{ x-=1.0 }}
                        y += 0.000017; if y>1.0 {{ y-=1.0 }}
                    }}
                    if total != 0.0 {{ os.Exit(1) }}
                }}
            """,
            swift=rf"""
                import Darwin
                @inline(__always) func fade(_ value: Double) -> Double {{ value*value*(3.0-2.0*value) }}
                let n=CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {n}
                var total=0.0, x=0.37, y=0.61
                for _ in 0..<n {{
                    let u=fade(x), v=fade(y), lower=0.15*(1.0-u)+0.82*u, upper=0.44*(1.0-u)+0.67*u
                    total += lower*(1.0-v)+upper*v
                    x += 0.000013; if x>1.0 {{ x-=1.0 }}
                    y += 0.000017; if y>1.0 {{ y-=1.0 }}
                }}
                exit(total != 0.0 ? 1 : 0)
            """,
            typescript=rf"""
                function fade(value:number):number {{ return value*value*(3.0-2.0*value); }}
                const n=Number((globalThis as any).Bun.argv[2] ?? {n}); let total=0.0,x=0.37,y=0.61;
                for(let i=0;i<n;i++){{
                    const u=fade(x),v=fade(y),lower=0.15*(1.0-u)+0.82*u,upper=0.44*(1.0-u)+0.67*u;
                    total += lower*(1.0-v)+upper*v;
                    x+=0.000013;if(x>1.0)x-=1.0;y+=0.000017;if(y>1.0)y-=1.0;
                }}
                (globalThis as any).process.exit(total!==0.0?1:0);
            """,
            range_source=rf"""
                function valueFade(value: Float): Float {{
                    return value * value * (Float(3.0) - Float(2.0) * value)
                }}
                @main {{
                    state total: Float(0.0)
                    state index: Int(0)
                    state x: Float(0.37)
                    state y: Float(0.61)
                    while index < {n} {{
                        let u: Float(valueFade(value: x))
                        let v: Float(valueFade(value: y))
                        let lower: Float(Float(0.15)*(Float(1.0)-u)+Float(0.82)*u)
                        let upper: Float(Float(0.44)*(Float(1.0)-u)+Float(0.67)*u)
                        total: total + lower*(Float(1.0)-v)+upper*v
                        index: index + 1
                        x: x + Float(0.000013)
                        if x > Float(1.0) {{ x: x - Float(1.0) }}
                        y: y + Float(0.000017)
                        if y > Float(1.0) {{ y: y - Float(1.0) }}
                    }}
                    if total != Float(0.0) {{ return 1 }}
                    return 0
                }}
            """,
        ),
        BenchmarkCase(
            name="strings",
            category="Strings",
            subcategory="Append",
            leaf="Incremental owned growth",
            unit="appends",
            description="Incremental string growth and length tracking",
            expected_output=str(((small * (small + 1) // 2) % 1000003 + small) % 1000003),
            expected_exit_code=0,
            range_expected_exit_code=(((small * (small + 1) // 2) % 1000003 + small) % 1000003) % 251,
            n=small,
            c=rf"""
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                #include <string.h>
                int main(int argc, char **argv) {{
                    int n = argc > 1 ? atoi(argv[1]) : {small};
                    char *s = malloc((size_t)n + 1);
                    int64_t acc = 0;
                    int len = 0;
                    for (int i = 0; i < n; i++) {{
                        s[len++] = (char)('a' + (i % 26));
                        acc = (acc + len) % 1000003;
                    }}
                    s[len] = 0;
                    printf("%lld\n", (long long)((acc + strlen(s)) % 1000003));
                    free(s);
                }}
            """,
            cxx=rf"""
                #include <cstdlib>
                #include <iostream>
                #include <string>
                int main(int argc, char **argv) {{
                    int n = argc > 1 ? std::atoi(argv[1]) : {small};
                    std::string s; s.reserve(n); long long acc = 0;
                    for (int i = 0; i < n; ++i) {{ s.push_back(char('a' + i % 26)); acc = (acc + s.size()) % 1000003; }}
                    std::cout << (acc + s.size()) % 1000003 << '\n';
                }}
            """,
            rust=rf"""
                fn main() {{
                    let n: usize = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({small});
                    let mut s = String::with_capacity(n);
                    let mut acc: i64 = 0;
                    for i in 0..n {{
                        s.push((b'a' + (i % 26) as u8) as char);
                        acc = (acc + s.len() as i64) % 1000003;
                    }}
                    println!("{{}}", (acc + s.len() as i64) % 1000003);
                }}
            """,
            go=rf"""
                package main
                import ("fmt"; "os"; "strconv")
                func main() {{
                    n := {small}; if len(os.Args) > 1 {{ n, _ = strconv.Atoi(os.Args[1]) }}
                    s := make([]byte, 0, n); var acc int64
                    for i := 0; i < n; i++ {{ s = append(s, byte('a'+i%26)); acc = (acc + int64(len(s))) % 1000003 }}
                    fmt.Println((acc + int64(len(s))) % 1000003)
                }}
            """,
            swift=rf"""
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {small}
                var s = ""
                s.reserveCapacity(n)
                var acc = 0
                var i = 0
                while i < n {{
                    s += "a"
                    acc = (acc + i + 1) % 1000003
                    i += 1
                }}
                print((acc + n) % 1000003)
            """,
            typescript=rf"""
                const n = Number((globalThis as any).Bun.argv[2] ?? {small});
                const parts: string[] = []; let acc = 0;
                for (let i = 0; i < n; i++) {{ parts.push(String.fromCharCode(97 + i % 26)); acc = (acc + parts.length) % 1000003; }}
                const s = parts.join(""); console.log((acc + s.length) % 1000003);
            """,
            range_source=rf"""
                @main {{
                    let n: Int({small})
                    state i: Int(0)
                    state text: String("")
                    state acc: Int(0)
                    while i < n {{
                        text: "\(text)a"
                        acc: (acc + i + 1) % 1000003
                        i: i + 1
                    }}
                    return ((acc + stringLength(value: text)) % 1000003) % 251
                }}
            """,
        ),
        BenchmarkCase(
            name="collections",
            category="Collections",
            subcategory="Indexed Read",
            leaf="Eight-value reduction",
            unit="reads",
            description="Repeated indexed array reads, branching, and reduction",
            expected_output=collections_output(small),
            expected_exit_code=0,
            range_expected_exit_code=int(collections_output(small)) % 251,
            n=small,
            c=rf"""
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                int main(int argc, char **argv) {{
                    int n = argc > 1 ? atoi(argv[1]) : {small};
                    int values[8] = {{0, 1, 2, 3, 4, 5, 6, 7}};
                    int64_t acc = 0;
                    for (int i = 0; i < n; i++) {{
                        int value = values[i % 8];
                        if ((value & 1) == 0) acc += value * 2;
                    }}
                    printf("%lld\n", (long long)acc);
                }}
            """,
            cxx=rf"""
                #include <array>
                #include <cstdlib>
                #include <iostream>
                int main(int argc, char **argv) {{
                    int n = argc > 1 ? std::atoi(argv[1]) : {small};
                    std::array<long long, 8> values{{0, 1, 2, 3, 4, 5, 6, 7}};
                    long long acc = 0;
                    for (int i = 0; i < n; ++i) {{ auto value = values[i % 8]; if ((value & 1) == 0) acc += value * 2; }}
                    std::cout << acc << '\n';
                }}
            """,
            rust=rf"""
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({small});
                    let values: [i64; 8] = [0, 1, 2, 3, 4, 5, 6, 7];
                    let mut acc: i64 = 0;
                    for i in 0..n {{ let value = values[(i % 8) as usize]; if value % 2 == 0 {{ acc += value * 2; }} }}
                    println!("{{acc}}");
                }}
            """,
            go=rf"""
                package main
                import ("fmt"; "os"; "strconv")
                func main() {{
                    n := {small}; if len(os.Args) > 1 {{ n, _ = strconv.Atoi(os.Args[1]) }}
                    values := [8]int64{{0, 1, 2, 3, 4, 5, 6, 7}}
                    var acc int64; for i := 0; i < n; i++ {{ value := values[i%8]; if value%2 == 0 {{ acc += value*2 }} }}
                    fmt.Println(acc)
                }}
            """,
            swift=rf"""
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {small}
                let values = [0, 1, 2, 3, 4, 5, 6, 7]
                var i = 0
                var acc = 0
                while i < n {{
                    let value = values[i % 8]
                    if value % 2 == 0 {{
                        acc += value * 2
                    }}
                    i += 1
                }}
                print(acc)
            """,
            typescript=rf"""
                const n = Number((globalThis as any).Bun.argv[2] ?? {small});
                const values = [0, 1, 2, 3, 4, 5, 6, 7]; let acc = 0;
                for (let i = 0; i < n; i++) {{ const value = values[i % 8]; if (value % 2 === 0) acc += value * 2; }}
                console.log(acc);
            """,
            range_source=rf"""
                @main {{
                    let n: Int({small})
                    let values: [0, 1, 2, 3, 4, 5, 6, 7]
                    state index: Int(0)
                    state acc: Int(0)
                    while index < n {{
                        let value: Int(values[index % 8])
                        if value % 2 == 0 {{
                            acc: acc + value * 2
                        }}
                        index: index + 1
                    }}
                    return acc % 251
                }}
            """,
        ),
        BenchmarkCase(
            name="convolution_1d",
            category="Convolution",
            subcategory="1D Three Tap",
            leaf="Circular eight sample",
            unit="windows",
            description="Circular one-dimensional three-tap stencil over eight integer samples",
            expected_output=convolution_output(small),
            expected_exit_code=0,
            range_expected_exit_code=int(convolution_output(small)) % 251,
            n=small,
            c=rf"""
                #include <inttypes.h>
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                int main(int argc, char **argv) {{
                    int64_t n=argc>1?atoll(argv[1]):{small}, values[8]={{1,3,5,7,11,13,17,19}}, acc=0;
                    for(int64_t i=0;i<n;++i){{
                        int64_t center=i%8,left=(center+7)%8,right=(center+1)%8;
                        acc=(acc+values[left]+values[center]*2+values[right])%1000003;
                    }}
                    printf("%" PRId64 "\n",acc);
                }}
            """,
            cxx=rf"""
                #include <array>
                #include <cstdint>
                #include <cstdlib>
                #include <iostream>
                int main(int argc,char**argv){{
                    std::int64_t n=argc>1?std::atoll(argv[1]):{small},acc=0; std::array<std::int64_t,8> values{{1,3,5,7,11,13,17,19}};
                    for(std::int64_t i=0;i<n;++i){{auto center=i%8,left=(center+7)%8,right=(center+1)%8;acc=(acc+values[left]+values[center]*2+values[right])%1000003;}}
                    std::cout<<acc<<'\n';
                }}
            """,
            rust=rf"""
                fn main(){{
                    let n:i64=std::env::args().nth(1).and_then(|v|v.parse().ok()).unwrap_or({small});
                    let values:[i64;8]=[1,3,5,7,11,13,17,19];let mut acc=0i64;
                    for i in 0..n{{let center=(i%8)as usize;let left=(center+7)%8;let right=(center+1)%8;acc=(acc+values[left]+values[center]*2+values[right])%1_000_003;}}
                    println!("{{acc}}");
                }}
            """,
            go=rf"""
                package main
                import("fmt";"os";"strconv")
                func main(){{
                    n:=int64({small});if len(os.Args)>1{{n,_=strconv.ParseInt(os.Args[1],10,64)}}
                    values:=[8]int64{{1,3,5,7,11,13,17,19}};var acc int64
                    for i:=int64(0);i<n;i++{{center:=i%8;left:=(center+7)%8;right:=(center+1)%8;acc=(acc+values[left]+values[center]*2+values[right])%1000003}}
                    fmt.Println(acc)
                }}
            """,
            swift=rf"""
                let n=CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {small}
                let values=[1,3,5,7,11,13,17,19];var acc=0
                for i in 0..<n{{let center=i%8,left=(center+7)%8,right=(center+1)%8;acc=(acc+values[left]+values[center]*2+values[right])%1_000_003}}
                print(acc)
            """,
            typescript=rf"""
                const n=Number((globalThis as any).Bun.argv[2]??{small}),values=[1,3,5,7,11,13,17,19];let acc=0;
                for(let i=0;i<n;i++){{const center=i%8,left=(center+7)%8,right=(center+1)%8;acc=(acc+values[left]+values[center]*2+values[right])%1000003;}}
                console.log(acc);
            """,
            range_source=rf"""
                @main {{
                    let values: [1, 3, 5, 7, 11, 13, 17, 19]
                    state i: Int(0)
                    state acc: Int(0)
                    while i < {small} {{
                        let center: Int(i % 8)
                        let left: Int((center + 7) % 8)
                        let right: Int((center + 1) % 8)
                        acc: (acc + values[left] + values[center] * 2 + values[right]) % 1000003
                        i: i + 1
                    }}
                    return acc % 251
                }}
            """,
        ),
        BenchmarkCase(
            name="constructs",
            category="Constructs",
            subcategory="Value Construction",
            leaf="Pair construction",
            unit="constructions",
            description="Short-lived value construction and member access",
            expected_output=constructs_output(small),
            expected_exit_code=0,
            range_expected_exit_code=int(constructs_output(small)) % 251,
            n=small,
            c=rf"""
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                typedef struct {{ int x; int y; }} Pair;
                int main(int argc, char **argv) {{
                    int n = argc > 1 ? atoi(argv[1]) : {small};
                    int64_t acc = 0;
                    for (int i = 0; i < n; i++) {{
                        Pair pair = (Pair){{i, i + 1}};
                        acc = (acc + pair.x + pair.y) % 1000003;
                    }}
                    printf("%lld\n", (long long)acc);
                }}
            """,
            cxx=rf"""
                #include <cstdlib>
                #include <iostream>
                struct Pair {{ long long x; long long y; }};
                int main(int argc, char **argv) {{
                    int n = argc > 1 ? std::atoi(argv[1]) : {small}; long long acc = 0;
                    for (int i = 0; i < n; ++i) {{ Pair pair{{i, i + 1}}; acc = (acc + pair.x + pair.y) % 1000003; }}
                    std::cout << acc << '\n';
                }}
            """,
            rust=rf"""
                struct Pair {{ x: i64, y: i64 }}
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({small});
                    let mut acc: i64 = 0;
                    for i in 0..n {{
                        let pair = Pair {{ x: i, y: i + 1 }};
                        acc = (acc + pair.x + pair.y) % 1_000_003;
                    }}
                    println!("{{acc}}");
                }}
            """,
            go=rf"""
                package main
                import ("fmt"; "os"; "strconv")
                type Pair struct {{ x, y int64 }}
                func main() {{
                    n := {small}; if len(os.Args) > 1 {{ n, _ = strconv.Atoi(os.Args[1]) }}
                    var acc int64; for i := 0; i < n; i++ {{ pair := Pair{{int64(i), int64(i+1)}}; acc = (acc + pair.x + pair.y) % 1000003 }}
                    fmt.Println(acc)
                }}
            """,
            swift=rf"""
                struct Pair {{ let x: Int; let y: Int }}
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {small}
                var i = 0
                var acc = 0
                while i < n {{
                    let pair = Pair(x: i, y: i + 1)
                    acc = (acc + pair.x + pair.y) % 1_000_003
                    i += 1
                }}
                print(acc)
            """,
            typescript=rf"""
                type Pair = {{ x: number; y: number }};
                const n = Number((globalThis as any).Bun.argv[2] ?? {small}); let acc = 0;
                for (let i = 0; i < n; i++) {{ const pair: Pair = {{ x: i, y: i + 1 }}; acc = (acc + pair.x + pair.y) % 1000003; }}
                console.log(acc);
            """,
            range_source=rf"""
                construct Pair {{
                    let x: Int
                    let y: Int
                }}

                @main {{
                    let n: Int({small})
                    state i: Int(0)
                    state acc: Int(0)
                    while i < n {{
                        let pair: Pair(x: i, y: i + 1)
                        acc: (acc + pair.x + pair.y) % 1000003
                        i: i + 1
                    }}
                    return acc % 251
                }}
            """,
        ),
        BenchmarkCase(
            name="fibonacci_recursion",
            category="Recursion",
            subcategory="Fibonacci",
            leaf="Depth 20 and 21",
            unit="root calls",
            description="Repeated binary recursion alternating depths 20 and 21",
            expected_output=recursion_output(recursion_repeats, recursion_depth),
            expected_exit_code=0,
            range_expected_exit_code=int(recursion_output(recursion_repeats, recursion_depth)) % 251,
            n=recursion_repeats,
            c=rf"""
                #include <inttypes.h>
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                static int64_t fibonacci(int64_t value){{if(value<2)return value;return fibonacci(value-1)+fibonacci(value-2);}}
                int main(int argc,char**argv){{int64_t n=argc>1?atoll(argv[1]):{recursion_repeats},acc=0;for(int64_t i=0;i<n;++i)acc=(acc+fibonacci({recursion_depth}+i%2))%1000003;printf("%" PRId64 "\n",acc);}}
            """,
            cxx=rf"""
                #include <cstdint>
                #include <cstdlib>
                #include <iostream>
                static std::int64_t fibonacci(std::int64_t value){{if(value<2)return value;return fibonacci(value-1)+fibonacci(value-2);}}
                int main(int argc,char**argv){{std::int64_t n=argc>1?std::atoll(argv[1]):{recursion_repeats},acc=0;for(std::int64_t i=0;i<n;++i)acc=(acc+fibonacci({recursion_depth}+i%2))%1000003;std::cout<<acc<<'\n';}}
            """,
            rust=rf"""
                fn fibonacci(value:i64)->i64{{if value<2{{value}}else{{fibonacci(value-1)+fibonacci(value-2)}}}}
                fn main(){{let n:i64=std::env::args().nth(1).and_then(|v|v.parse().ok()).unwrap_or({recursion_repeats});let mut acc=0;for i in 0..n{{acc=(acc+fibonacci({recursion_depth}+i%2))%1_000_003;}}println!("{{acc}}");}}
            """,
            go=rf"""
                package main
                import("fmt";"os";"strconv")
                func fibonacci(value int64)int64{{if value<2{{return value}};return fibonacci(value-1)+fibonacci(value-2)}}
                func main(){{n:=int64({recursion_repeats});if len(os.Args)>1{{n,_=strconv.ParseInt(os.Args[1],10,64)}};var acc int64;for i:=int64(0);i<n;i++{{acc=(acc+fibonacci({recursion_depth}+i%2))%1000003}};fmt.Println(acc)}}
            """,
            swift=rf"""
                @inline(never) func fibonacci(_ value:Int)->Int{{if value<2{{return value}};return fibonacci(value-1)+fibonacci(value-2)}}
                let n=CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {recursion_repeats};var acc=0
                for i in 0..<n{{acc=(acc+fibonacci({recursion_depth}+i%2))%1_000_003}}
                print(acc)
            """,
            typescript=rf"""
                function fibonacci(value:number):number{{if(value<2)return value;return fibonacci(value-1)+fibonacci(value-2);}}
                const n=Number((globalThis as any).Bun.argv[2]??{recursion_repeats});let acc=0;for(let i=0;i<n;i++)acc=(acc+fibonacci({recursion_depth}+i%2))%1000003;console.log(acc);
            """,
            range_source=rf"""
                function fibonacci(value: Int): Int {{
                    if value < 2 {{ return value }}
                    return fibonacci(value: value - 1) + fibonacci(value: value - 2)
                }}
                @main {{
                    state i: Int(0)
                    state acc: Int(0)
                    while i < {recursion_repeats} {{
                        acc: (acc + fibonacci(value: {recursion_depth} + i % 2)) % 1000003
                        i: i + 1
                    }}
                    return acc % 251
                }}
            """,
        ),
        BenchmarkCase(
            name="function_calls",
            category="Function Calls",
            subcategory="Direct Call",
            leaf="Choose",
            unit="calls",
            description="Small reusable function calls and predictable branching",
            expected_output=str(int(generic_calls_output(n)) % 1000003),
            expected_exit_code=0,
            range_expected_exit_code=(int(generic_calls_output(n)) % 1000003) % 251,
            n=n,
            c=rf"""
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                static inline int64_t choose(int64_t lhs, int64_t rhs, int flag) {{ return flag ? lhs : rhs; }}
                int main(int argc, char **argv) {{
                    int64_t n = argc > 1 ? atoll(argv[1]) : {n};
                    int64_t acc = 0;
                    for (int64_t i = 0; i < n; i++) acc = (acc + choose(i, i + 1, (int)(i & 1))) % 1000003;
                    printf("%lld\n", (long long)acc);
                }}
            """,
            cxx=rf"""
                #include <cstdint>
                #include <cstdlib>
                #include <iostream>
                inline long long choose(long long lhs, long long rhs, bool flag) {{ return flag ? lhs : rhs; }}
                int main(int argc, char **argv) {{
                    std::int64_t n = argc > 1 ? std::atoll(argv[1]) : {n}, acc = 0;
                    for (std::int64_t i = 0; i < n; ++i) acc = (acc + choose(i, i + 1, i % 2 == 1)) % 1000003;
                    std::cout << acc << '\n';
                }}
            """,
            rust=rf"""
                #[inline(always)]
                fn choose(lhs: i64, rhs: i64, flag: bool) -> i64 {{ if flag {{ lhs }} else {{ rhs }} }}
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({n});
                    let mut acc = 0i64;
                    for i in 0..n {{
                        acc = (acc + choose(i, i + 1, i % 2 == 1)) % 1000003;
                    }}
                    println!("{{acc}}");
                }}
            """,
            go=rf"""
                package main
                import ("fmt"; "os"; "strconv")
                func choose(lhs, rhs int64, flag bool) int64 {{ if flag {{ return lhs }}; return rhs }}
                func main() {{
                    n := int64({n}); if len(os.Args) > 1 {{ n, _ = strconv.ParseInt(os.Args[1], 10, 64) }}
                    var acc int64; for i := int64(0); i < n; i++ {{ acc = (acc + choose(i, i+1, i%2 == 1)) % 1000003 }}
                    fmt.Println(acc)
                }}
            """,
            swift=rf"""
                @inline(__always) func choose(_ lhs: Int, _ rhs: Int, _ flag: Bool) -> Int {{
                    flag ? lhs : rhs
                }}
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {n}
                var i = 0
                var acc = 0
                while i < n {{
                    acc = (acc + choose(i, i + 1, i % 2 == 1)) % 1000003
                    i += 1
                }}
                print(acc)
            """,
            typescript=rf"""
                function choose(lhs: number, rhs: number, flag: boolean): number {{ return flag ? lhs : rhs; }}
                const n = Number((globalThis as any).Bun.argv[2] ?? {n}); let acc = 0;
                for (let i = 0; i < n; i++) acc = (acc + choose(i, i + 1, i % 2 === 1)) % 1000003;
                console.log(acc);
            """,
            range_source=rf"""
                function choose(lhs: Int, rhs: Int, flag: Bool): Int {{
                    if flag {{
                        return lhs
                    }}
                    return rhs
                }}

                @main {{
                    let n: Int({n})
                    state i: Int(0)
                    state acc: Int(0)
                    while i < n {{
                        acc: (acc + choose(lhs: i, rhs: i + 1, flag: i % 2 == 1)) % 1000003
                        i: i + 1
                    }}
                    return acc % 251
                }}
            """,
        ),
    ]


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(value).strip() + "\n", encoding="utf-8")


def prepare_range_project(case: BenchmarkCase) -> Path:
    project = BUILD / "range-projects" / case.name
    if project.exists():
        shutil.rmtree(project)
    project.mkdir(parents=True, exist_ok=True)
    write_text(project / "Project.range", package_manifest("RangeSpeed" + case.name.title().replace("_", "")))
    write_text(project / "Playground.range", case.range_source)
    return project


def range_runtime_inputs() -> list[str]:
    manifest = json.loads(SEED_MANIFEST.read_text(encoding="utf-8"))
    return [str(ROOT / item["path"]) for item in manifest["runtimeSources"]]


def verified_range_compiler() -> Path | None:
    explicit = os.environ.get("RANGE_BENCH_COMPILER")
    if explicit:
        compiler = Path(explicit).expanduser().resolve()
        if not compiler.is_file():
            raise SystemExit(f"RANGE_BENCH_COMPILER does not exist: {compiler}")
        return compiler

    if (
        STAGE2_COMPILER.is_file()
        and STAGE3_COMPILER.is_file()
        and filecmp.cmp(STAGE2_COMPILER, STAGE3_COMPILER, shallow=False)
    ):
        return STAGE3_COMPILER
    return None


def build_case(
    case: BenchmarkCase,
    range_cli: Path,
    range_env: dict[str, str] | None,
    bun: str | None,
    tsgo: str | None,
) -> list[BenchTarget]:
    case_build = BUILD / "cases" / case.name
    case_build.mkdir(parents=True, exist_ok=True)

    c_source = case_build / "main.c"
    cxx_source = case_build / "main.cpp"
    rust_source = case_build / "main.rs"
    go_source = case_build / "main.go"
    swift_source = case_build / "main.swift"
    typescript_source = case_build / "main.ts"
    c_binary = case_build / "speed-c"
    cxx_binary = case_build / "speed-cxx"
    rust_binary = case_build / "speed-rust"
    go_binary = case_build / "speed-go"
    swift_binary = case_build / "speed-swift"
    tsgo_build = case_build / "tsgo"

    write_text(c_source, case.c)
    write_text(cxx_source, case.cxx)
    write_text(rust_source, case.rust)
    write_text(go_source, case.go)
    write_text(swift_source, case.swift)
    write_text(typescript_source, case.typescript)

    targets: list[BenchTarget] = []

    if timed_setup(
        f"{case.name} C",
        ["cc", "-O3", "-mcpu=native", str(c_source), "-o", str(c_binary)],
    ):
        targets.append(BenchTarget("C", [str(c_binary), str(case.n)], case.expected_exit_code))
    if timed_setup(
        f"{case.name} C++",
        ["c++", "-std=c++20", "-O3", "-mcpu=native", str(cxx_source), "-o", str(cxx_binary)],
    ):
        targets.append(BenchTarget("C++", [str(cxx_binary), str(case.n)], case.expected_exit_code))
    if timed_setup(
        f"{case.name} Rust",
        [
            "rustc",
            "-C",
            "opt-level=3",
            "-C",
            "target-cpu=native",
            str(rust_source),
            "-o",
            str(rust_binary),
        ],
    ):
        targets.append(BenchTarget("Rust", [str(rust_binary), str(case.n)], case.expected_exit_code))
    if timed_setup(f"{case.name} Go", ["go", "build", "-o", str(go_binary), str(go_source)]):
        targets.append(BenchTarget("Go", [str(go_binary), str(case.n)], case.expected_exit_code))
    if timed_setup(
        f"{case.name} Swift",
        ["swiftc", "-Ounchecked", str(swift_source), "-o", str(swift_binary)],
    ):
        targets.append(BenchTarget("Swift", [str(swift_binary), str(case.n)], case.expected_exit_code))

    if bun:
        targets.append(BenchTarget("Bun", [bun, "run", str(typescript_source), str(case.n)], case.expected_exit_code))

    if tsgo:
        if tsgo_build.exists():
            shutil.rmtree(tsgo_build)
        tsgo_build.mkdir(parents=True)
        if timed_setup(
            f"{case.name} TypeScript 7",
            [tsgo, str(typescript_source), "--outDir", str(tsgo_build), "--target", "es2022"],
        ):
            emitted_javascript = tsgo_build / "main.js"
            if bun and emitted_javascript.is_file():
                targets.append(
                    BenchTarget(
                        "TypeScript 7",
                        [bun, "run", str(emitted_javascript), str(case.n)],
                        case.expected_exit_code,
                    )
                )
            elif not bun:
                print(f"{case.name} TypeScript 7 runtime: skipped because Bun is unavailable")
            else:
                print(f"{case.name} TypeScript 7 runtime: skipped because main.js was not emitted")

    range_project = prepare_range_project(case)
    range_binary = range_project / ".range" / "Build" / "llvm" / range_project.name
    range_llvm = range_project / ".range" / "Build" / "llvm" / "Main.ll"
    range_source = range_project / "Playground.range"
    optimized_range_binary = range_binary.with_name(range_binary.name + "-O3")
    range_llvm.parent.mkdir(parents=True, exist_ok=True)
    native_compiler = verified_range_compiler()
    if native_compiler:
        emitted = timed_setup(
            f"{case.name} Range native emit",
            [str(native_compiler), "emit-llvm", str(range_source), str(range_llvm)],
        )
    else:
        print(f"{case.name} Range: no byte-identical Stage 2/3 compiler; using pinned seed")
        emitted = timed_setup(
            f"{case.name} Range emit",
            [str(range_cli), "emit-llvm", str(range_source), str(range_llvm)],
            env=range_env,
        )

    if emitted and range_llvm.is_file():
        if timed_setup(
            f"{case.name} Range optimized link",
            [
                "clang",
                "-O3",
                "-mcpu=native",
                "-Wno-override-module",
                str(range_llvm),
                *range_runtime_inputs(),
                "-o",
                str(optimized_range_binary),
            ],
        ):
            targets.append(
                BenchTarget(
                    "Range",
                    [str(optimized_range_binary)],
                    case.range_expected_exit_code,
                )
            )
    elif emitted:
        print(f"{case.name} Range runtime: skipped because LLVM output was not found")

    return targets


def median_int(values: list[int]) -> int:
    return int(statistics.median(values)) if values else 0


def format_rss(kb: int) -> str:
    if kb <= 0:
        return "n/a"
    return f"{kb / 1024:.1f}MB"


def measure_targets(targets: list[BenchTarget]) -> list[Measurement]:
    wall_samples: list[list[float]] = [[] for _ in targets]
    cpu_samples: list[list[float]] = [[] for _ in targets]
    rss_samples: list[list[int]] = [[] for _ in targets]
    outputs = ["" for _ in targets]

    # Measuring one language's entire sample block before the next made results
    # sensitive to frequency, thermal, and background-load drift. Rotate the
    # starting language every round and reverse each complete rotation so every
    # target is sampled across the run rather than inside one time window.
    target_indices = list(range(len(targets)))
    for run_index in range(RUNS):
        shift = run_index % len(targets)
        order = target_indices[shift:] + target_indices[:shift]
        if (run_index // len(targets)) % 2 == 1:
            order.reverse()

        for target_index in order:
            target = targets[target_index]
            result = measured_command(
                target.command,
                expected_exit_code=target.expected_exit_code,
            )
            wall_samples[target_index].append(result.wall_seconds)
            cpu_samples[target_index].append(result.cpu_seconds)
            rss_samples[target_index].append(result.peak_rss_kb)
            current_output = result.output
            if outputs[target_index] and current_output != outputs[target_index]:
                raise SystemExit(
                    f"{target.language} produced inconsistent output: "
                    f"{current_output} != {outputs[target_index]}"
                )
            outputs[target_index] = current_output

    return [
        Measurement(
            wall_seconds=statistics.median(wall_samples[index]),
            cpu_seconds=statistics.median(cpu_samples[index]),
            peak_rss_kb=median_int(rss_samples[index]),
            output=outputs[index],
        )
        for index in target_indices
    ]


def identifier(value: str) -> str:
    return "-".join(part for part in "".join(character.lower() if character.isalnum() else " " for character in value).split())


def normalized_source(value: str) -> str:
    return textwrap.dedent(value).strip() + "\n"


def benchmark_artifact(
    catalog_cases: list[BenchmarkCase],
    run_results: dict[str, list[tuple[str, Measurement, float, float, float, str]]],
) -> dict[str, object]:
    categories: list[dict[str, object]] = []
    category_index: dict[str, dict[str, object]] = {}
    observed_languages: set[str] = set()
    range_passed = 0
    range_not_emitted = 0

    for case in catalog_cases:
        category_id = identifier(case.category)
        category = category_index.get(category_id)
        if category is None:
            category = {
                "id": category_id,
                "name": case.category,
                "subcategories": [],
            }
            category_index[category_id] = category
            categories.append(category)

        subcategories = category["subcategories"]
        assert isinstance(subcategories, list)
        subcategory_id = identifier(case.subcategory)
        subcategory = next(
            (item for item in subcategories if item["id"] == subcategory_id),
            None,
        )
        if subcategory is None:
            subcategory = {
                "id": subcategory_id,
                "name": case.subcategory,
                "leaves": [],
            }
            subcategories.append(subcategory)

        case_results = run_results.get(case.name, [])
        fastest_wall = min(
            (row[1].wall_seconds for row in case_results),
            default=0.0,
        )
        measurements: list[dict[str, object]] = []
        for language, measurement, wall_relative, cpu_relative, rss_relative, output in sorted(
            case_results,
            key=lambda row: row[1].wall_seconds,
        ):
            observed_languages.add(language)
            measurements.append(
                {
                    "language": language,
                    "status": "passed",
                    "wallMilliseconds": round(measurement.wall_seconds * 1000, 4),
                    "cpuMilliseconds": round(measurement.cpu_seconds * 1000, 4),
                    "peakRssKilobytes": measurement.peak_rss_kb,
                    "relativeToFastest": round(
                        measurement.wall_seconds / fastest_wall if fastest_wall else 1.0,
                        4,
                    ),
                    "relativeToC": round(wall_relative, 4),
                    "cpuRelativeToC": round(cpu_relative, 4),
                    "memoryRelativeToC": round(rss_relative, 4),
                    "output": output,
                }
            )

        range_result = next(
            (measurement for measurement in measurements if measurement["language"] == "Range"),
            None,
        )
        if case_results and range_result is None:
            range_status = "notEmitted"
            range_not_emitted += 1
        elif range_result is not None:
            range_status = "passed"
            range_passed += 1
        else:
            range_status = "notRun"

        leaves = subcategory["leaves"]
        assert isinstance(leaves, list)
        leaves.append(
            {
                "id": case.name,
                "name": case.leaf,
                "description": case.description,
                "workload": {"count": case.n, "unit": case.unit},
                "runStatus": "passed" if case_results else "notRun",
                "rangeStatus": range_status,
                "axisMaxMilliseconds": round(
                    max((measurement["wallMilliseconds"] for measurement in measurements), default=0.0) * 1.08,
                    4,
                ),
                "implementations": [
                    {
                        "language": "C",
                        "syntax": "c",
                        "filename": "main.c",
                        "source": normalized_source(case.c),
                    },
                    {
                        "language": "Range",
                        "syntax": "range",
                        "filename": "Playground.range",
                        "source": normalized_source(case.range_source),
                    },
                ],
                "results": measurements,
            }
        )

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return {
        "schemaVersion": 2,
        "generatedAt": generated_at,
        "configuration": {
            "baseIterations": ITERATIONS,
            "runs": RUNS,
            "caseFilter": sorted(CASE_FILTER),
        },
        "environment": {
            "system": platform.system(),
            "release": platform.release(),
            "architecture": platform.machine(),
            "python": platform.python_version(),
        },
        "procedure": {
            "steps": [
                "Write the generated implementation for each language into an isolated case directory.",
                "Compile every native implementation with its release optimization settings. Compilation time is excluded from the measurement.",
                "Emit Range to LLVM with the verified self-hosted compiler, then link the emitted module and runtime sources with clang -O3 -mcpu=native.",
                "Run every language once per round, rotating the starting language to reduce thermal, frequency, and background-load bias.",
                "Require the expected exit code and identical output on every run, then report median wall time, median CPU time, and median peak RSS.",
            ],
            "commands": {
                "c": [
                    "cc -O3 -mcpu=native main.c -o speed-c",
                    "./speed-c <iterations>",
                ],
                "range": [
                    "RangeCompiler emit-llvm Playground.range Main.ll",
                    "clang -O3 -mcpu=native -Wno-override-module Main.ll <runtime-sources> -o speed-range",
                    "./speed-range",
                ],
                "suite": [
                    "N=<base-iterations> RUNS=<sample-count> npm run benchmarks",
                ],
            },
            "notes": [
                "The workload count is specialized per leaf; some leaves intentionally scale it down to keep total work comparable.",
                "Wall time includes process execution but excludes source generation and compilation.",
                "A result is published only when output remains stable across every measured run.",
                "Bun and TypeScript rows are omitted when their local toolchains are unavailable.",
            ],
        },
        "languages": sorted(observed_languages),
        "summary": {
            "leafCount": len(catalog_cases),
            "runLeafCount": len(run_results),
            "rangePassed": range_passed,
            "rangeNotEmitted": range_not_emitted,
            "rangeFailed": 0,
        },
        "categories": categories,
    }


def write_benchmark_artifact(artifact: dict[str, object]) -> list[Path]:
    output = Path(os.environ.get("RESULTS_FILE", str(RESULTS / "latest.json"))).expanduser()
    destinations = [output]
    if os.environ.get("WRITE_SITE_RESULTS", "1") != "0":
        destinations.append(Path(os.environ.get("SITE_RESULTS_FILE", str(SITE_RESULTS))).expanduser())

    rendered = json.dumps(artifact, indent=2, sort_keys=False) + "\n"
    written: list[Path] = []
    for destination in destinations:
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".tmp")
        temporary.write_text(rendered, encoding="utf-8")
        temporary.replace(destination)
        written.append(destination)
    return written


def main() -> int:
    require_tool("cc")
    require_tool("c++")
    require_tool("rustc")
    require_tool("go")
    require_tool("swiftc")
    bun = optional_tool("bun")
    tsgo = optional_tool("tsgo")

    BUILD.mkdir(parents=True, exist_ok=True)
    range_env = os.environ.copy()
    range_cli = ROOT / "scripts" / "range"

    print(f"base iterations: {ITERATIONS}")
    print(f"runs: {RUNS}")
    print()

    results: dict[str, list[tuple[str, Measurement, float, float, float, str]]] = {}
    benchmark_cases = selected_cases()

    for case in benchmark_cases:
        print()
        print(f"== {case.category} / {case.subcategory}: {case.name} (N={case.n}) ==")
        print(case.description)
        targets = build_case(case, range_cli, range_env, bun, tsgo)
        wall_baselines: dict[str, float] = {}
        cpu_baselines: dict[str, float] = {}
        rss_baselines: dict[str, int] = {}
        case_results: list[tuple[str, Measurement, float, float, float, str]] = []
        measurements = measure_targets(targets)

        for target, measurement in zip(targets, measurements, strict=True):
            expected_output = (
                f"exit:{case.range_expected_exit_code}"
                if target.language == "Range"
                else case.expected_output
            )
            if measurement.output != expected_output:
                raise SystemExit(
                    f"{case.name} {target.language} produced {measurement.output!r}; "
                    f"expected {expected_output!r}"
                )
            if target.language == "C":
                wall_baselines["C"] = measurement.wall_seconds
                cpu_baselines["C"] = measurement.cpu_seconds
                rss_baselines["C"] = measurement.peak_rss_kb

            wall_baseline = wall_baselines.get("C", measurement.wall_seconds)
            cpu_baseline = cpu_baselines.get("C", measurement.cpu_seconds)
            rss_baseline = rss_baselines.get("C", measurement.peak_rss_kb)
            wall_relative = measurement.wall_seconds / wall_baseline if wall_baseline else 1.0
            cpu_relative = measurement.cpu_seconds / cpu_baseline if cpu_baseline else 1.0
            rss_relative = measurement.peak_rss_kb / rss_baseline if rss_baseline else 1.0
            cpu_percent = (
                measurement.cpu_seconds / measurement.wall_seconds * 100
                if measurement.wall_seconds
                else 0
            )

            case_results.append(
                (
                    target.language,
                    measurement,
                    wall_relative,
                    cpu_relative,
                    rss_relative,
                    measurement.output,
                )
            )
            print(
                f"{target.language:>12}: "
                f"wall {measurement.wall_seconds:.4f}s {wall_relative:>6.2f}x  "
                f"cpu {measurement.cpu_seconds:.4f}s {cpu_relative:>6.2f}x "
                f"({cpu_percent:>5.1f}%)  "
                f"mem {format_rss(measurement.peak_rss_kb):>8} {rss_relative:>6.2f}x  "
                f"output={measurement.output}"
            )

        results[case.name] = case_results

    print()
    print("== Range summary ==")
    for case_name, case_results in results.items():
        range_row = next((row for row in case_results if row[0] == "Range"), None)
        rust_row = next((row for row in case_results if row[0] == "Rust"), None)
        if range_row and rust_row:
            range_wall = range_row[1].wall_seconds
            rust_wall = rust_row[1].wall_seconds
            range_cpu = range_row[1].cpu_seconds
            rust_cpu = rust_row[1].cpu_seconds
            range_mem = range_row[1].peak_rss_kb
            rust_mem = rust_row[1].peak_rss_kb
            range_vs_rust = range_wall / rust_wall if rust_wall else 0
            range_cpu_vs_rust = range_cpu / rust_cpu if rust_cpu else 0
            range_mem_vs_rust = range_mem / rust_mem if rust_mem else 0
            print(
                f"{case_name:>14}: "
                f"Range wall {range_wall:.4f}s, Rust wall {rust_wall:.4f}s, "
                f"Range/Rust wall {range_vs_rust:.2f}x, "
                f"cpu {range_cpu_vs_rust:.2f}x, "
                f"mem {range_mem_vs_rust:.2f}x"
            )
        elif range_row:
            print(
                f"{case_name:>14}: "
                f"Range wall {range_row[1].wall_seconds:.4f}s, "
                f"cpu {range_row[1].cpu_seconds:.4f}s, "
                f"mem {format_rss(range_row[1].peak_rss_kb)}"
            )
        else:
            print(f"{case_name:>14}: Range skipped")

    artifact = benchmark_artifact(cases(), results)
    written_artifacts = write_benchmark_artifact(artifact)
    print()
    for artifact_path in written_artifacts:
        print(f"results: {artifact_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
