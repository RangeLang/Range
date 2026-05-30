#!/usr/bin/env python3
from __future__ import annotations

import os
import plistlib
import shutil
import statistics
import subprocess
import sys
import textwrap
import time
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "Benchmarks" / "Speed"
BUILD = BENCH / ".build"
ITERATIONS = int(os.environ.get("N", "1000000"))
RUNS = int(os.environ.get("RUNS", "5"))
VERBOSE = os.environ.get("VERBOSE") == "1"


@dataclass(frozen=True)
class BenchmarkCase:
    name: str
    n: int
    c: str
    rust: str
    swift: str
    python: str
    range_source: str


@dataclass(frozen=True)
class BenchTarget:
    language: str
    command: list[str]


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
    return f"""#package
construct Project {{
    let name: Title("{name}")
    let version: Version(0.1.0)
    let author: "George"
}}
"""


def cases() -> list[BenchmarkCase]:
    n = ITERATIONS
    small = max(1, n // 10)

    return [
        BenchmarkCase(
            name="integer_loop",
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
                        acc = (acc * 1664525 + i) % 2147483647;
                        i += 1;
                    }}
                    printf("%" PRId64 "\n", acc);
                }}
            """,
            rust=rf"""
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({n});
                    let mut i: i64 = 0;
                    let mut acc: i64 = 1;
                    while i < n {{
                        acc = (acc * 1_664_525 + i) % 2_147_483_647;
                        i += 1;
                    }}
                    println!("{{acc}}");
                }}
            """,
            swift=rf"""
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int64.init) ?? {n}
                var i: Int64 = 0
                var acc: Int64 = 1
                while i < n {{
                    acc = (acc * 1_664_525 + i) % 2_147_483_647
                    i += 1
                }}
                print(acc)
            """,
            python=rf"""
                import sys
                n = int(sys.argv[1]) if len(sys.argv) > 1 else {n}
                i = 0
                acc = 1
                while i < n:
                    acc = (acc * 1_664_525 + i) % 2_147_483_647
                    i += 1
                print(acc)
            """,
            range_source=rf"""
                @main {{
                    let n: Int({n})
                    state i: Int(0)
                    state acc: Int(1)
                    while i < n {{
                        acc += (((acc * 1664525) + i) % 2147483647) - acc
                        i += 1
                    }}
                    Logger.log("\(acc)")
                }}
            """,
        ),
        BenchmarkCase(
            name="strings",
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
                        acc += len;
                    }}
                    s[len] = 0;
                    printf("%lld\n", (long long)(acc + strlen(s)));
                    free(s);
                }}
            """,
            rust=rf"""
                fn main() {{
                    let n: usize = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({small});
                    let mut s = String::with_capacity(n);
                    let mut acc: i64 = 0;
                    for i in 0..n {{
                        s.push((b'a' + (i % 26) as u8) as char);
                        acc += s.len() as i64;
                    }}
                    println!("{{}}", acc + s.len() as i64);
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
                    acc += i + 1
                    i += 1
                }}
                print(acc + n)
            """,
            python=rf"""
                import sys
                n = int(sys.argv[1]) if len(sys.argv) > 1 else {small}
                parts = []
                acc = 0
                for _ in range(n):
                    parts.append("a")
                    acc += len(parts)
                s = "".join(parts)
                print(acc + len(s))
            """,
            range_source=rf"""
                @main {{
                    let n: Int({small})
                    state i: Int(0)
                    state text: String("")
                    state acc: Int(0)
                    while i < n {{
                        text += "a"
                        acc += i + 1
                        i += 1
                    }}
                    Logger.log("\(acc + n)")
                }}
            """,
        ),
        BenchmarkCase(
            name="collections",
            n=small,
            c=rf"""
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                int main(int argc, char **argv) {{
                    int n = argc > 1 ? atoi(argv[1]) : {small};
                    int *values = malloc(sizeof(int) * (size_t)n);
                    int64_t acc = 0;
                    for (int i = 0; i < n; i++) values[i] = i;
                    for (int i = 0; i < n; i++) if ((values[i] & 1) == 0) acc += values[i] * 2;
                    printf("%lld\n", (long long)acc);
                    free(values);
                }}
            """,
            rust=rf"""
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({small});
                    let values: Vec<i64> = (0..n).collect();
                    let acc: i64 = values.iter().filter(|v| **v % 2 == 0).map(|v| *v * 2).sum();
                    println!("{{acc}}");
                }}
            """,
            swift=rf"""
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {small}
                var values: [Int] = []
                values.reserveCapacity(n)
                var i = 0
                while i < n {{
                    values.append(i)
                    i += 1
                }}
                var acc = 0
                for value in values {{
                    if value % 2 == 0 {{
                        acc += value * 2
                    }}
                }}
                print(acc)
            """,
            python=rf"""
                import sys
                n = int(sys.argv[1]) if len(sys.argv) > 1 else {small}
                values = list(range(n))
                print(sum(value * 2 for value in values if value % 2 == 0))
            """,
            range_source=rf"""
                @main {{
                    let n: Int({small})
                    state i: Int(0)
                    state values: [Int]
                    while i < n {{
                        values.append(element: i)
                        i += 1
                    }}

                    state index: Int(0)
                    state acc: Int(0)
                    while index < values.count {{
                        if values.element(index: index) % 2 == 0 {{
                            acc += values.element(index: index) * 2
                        }}
                        index += 1
                    }}
                    Logger.log("\(acc)")
                }}
            """,
        ),
        BenchmarkCase(
            name="constructs",
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
                        acc += pair.x + pair.y;
                    }}
                    printf("%lld\n", (long long)acc);
                }}
            """,
            rust=rf"""
                struct Pair {{ x: i64, y: i64 }}
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({small});
                    let mut acc: i64 = 0;
                    for i in 0..n {{
                        let pair = Pair {{ x: i, y: i + 1 }};
                        acc += pair.x + pair.y;
                    }}
                    println!("{{acc}}");
                }}
            """,
            swift=rf"""
                struct Pair {{ let x: Int; let y: Int }}
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {small}
                var i = 0
                var acc = 0
                while i < n {{
                    let pair = Pair(x: i, y: i + 1)
                    acc += pair.x + pair.y
                    i += 1
                }}
                print(acc)
            """,
            python=rf"""
                import sys
                n = int(sys.argv[1]) if len(sys.argv) > 1 else {small}
                acc = 0
                for i in range(n):
                    pair = (i, i + 1)
                    acc += pair[0] + pair[1]
                print(acc)
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
                        acc += pair.x + pair.y
                        i += 1
                    }}
                    Logger.log("\(acc)")
                }}
            """,
        ),
        BenchmarkCase(
            name="generics",
            n=n,
            c=rf"""
                #include <stdint.h>
                #include <stdio.h>
                #include <stdlib.h>
                static inline int64_t choose(int64_t lhs, int64_t rhs, int flag) {{ return flag ? lhs : rhs; }}
                int main(int argc, char **argv) {{
                    int64_t n = argc > 1 ? atoll(argv[1]) : {n};
                    int64_t acc = 0;
                    for (int64_t i = 0; i < n; i++) acc += choose(i, i + 1, (int)(i & 1));
                    printf("%lld\n", (long long)acc);
                }}
            """,
            rust=rf"""
                #[inline(always)]
                fn choose<T: Copy>(lhs: T, rhs: T, flag: bool) -> T {{ if flag {{ lhs }} else {{ rhs }} }}
                fn main() {{
                    let n: i64 = std::env::args().nth(1).and_then(|v| v.parse().ok()).unwrap_or({n});
                    let mut acc = 0i64;
                    for i in 0..n {{
                        acc += choose(i, i + 1, i % 2 == 1);
                    }}
                    println!("{{acc}}");
                }}
            """,
            swift=rf"""
                @inline(__always) func choose<T>(_ lhs: T, _ rhs: T, _ flag: Bool) -> T {{
                    flag ? lhs : rhs
                }}
                let n = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? {n}
                var i = 0
                var acc = 0
                while i < n {{
                    acc += choose(i, i + 1, i % 2 == 1)
                    i += 1
                }}
                print(acc)
            """,
            python=rf"""
                import sys
                def choose(lhs, rhs, flag):
                    return lhs if flag else rhs
                n = int(sys.argv[1]) if len(sys.argv) > 1 else {n}
                acc = 0
                for i in range(n):
                    acc += choose(i, i + 1, i % 2 == 1)
                print(acc)
            """,
            range_source=rf"""
                function choose<T>(lhs lhs: T, rhs rhs: T, flag flag: Bool) -> T {{
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
                        acc += choose(lhs: i, rhs: i + 1, flag: i % 2 == 1)
                        i += 1
                    }}
                    Logger.log("\(acc)")
                }}
            """,
        ),
    ]


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(value).strip() + "\n", encoding="utf-8")


def prepare_range_project(case: BenchmarkCase) -> Path:
    project = BUILD / "range-projects" / case.name
    project.mkdir(parents=True, exist_ok=True)
    write_text(project / "Project.range", package_manifest("RangeSpeed" + case.name.title().replace("_", "")))
    write_text(project / "Playground.range", case.range_source)
    return project


def build_case(
    case: BenchmarkCase,
    range_cli: Path,
    range_env: dict[str, str] | None,
) -> list[BenchTarget]:
    case_build = BUILD / "cases" / case.name
    case_build.mkdir(parents=True, exist_ok=True)

    c_source = case_build / "main.c"
    rust_source = case_build / "main.rs"
    swift_source = case_build / "main.swift"
    python_source = case_build / "main.py"
    c_binary = case_build / "speed-c"
    rust_binary = case_build / "speed-rust"
    swift_binary = case_build / "speed-swift"

    write_text(c_source, case.c)
    write_text(rust_source, case.rust)
    write_text(swift_source, case.swift)
    write_text(python_source, case.python)

    targets: list[BenchTarget] = []

    if timed_setup(f"{case.name} C", ["cc", "-O3", str(c_source), "-o", str(c_binary)]):
        targets.append(BenchTarget("C", [str(c_binary), str(case.n)]))
    if timed_setup(
        f"{case.name} Rust",
        ["rustc", "-C", "opt-level=3", str(rust_source), "-o", str(rust_binary)],
    ):
        targets.append(BenchTarget("Rust", [str(rust_binary), str(case.n)]))
    if timed_setup(f"{case.name} Swift", ["swiftc", "-O", str(swift_source), "-o", str(swift_binary)]):
        targets.append(BenchTarget("Swift", [str(swift_binary), str(case.n)]))

    targets.append(BenchTarget("Python", ["python3", str(python_source), str(case.n)]))

    range_project = prepare_range_project(case)
    range_binary = range_project / ".range" / "Build" / "swift" / ".build" / "release" / "RangeGenerated"
    if timed_setup(f"{case.name} Range emit", [str(range_cli), "compile", str(range_project)]):
        if timed_setup(
            f"{case.name} Range generated Swift",
            ["swift", "build", "-c", "release"],
            cwd=range_project / ".range" / "Build" / "swift",
            env=range_env,
        ):
            targets.append(BenchTarget("Range", [str(range_binary)]))
        else:
            print(f"{case.name} Range runtime: skipped because generated Swift did not build")

    return targets


def measure(target: BenchTarget) -> tuple[float, str]:
    samples: list[float] = []
    output = ""

    for _ in range(RUNS):
        started = time.perf_counter()
        result = run_command(target.command)
        samples.append(time.perf_counter() - started)
        current_output = result.stdout.strip()
        if output and current_output != output:
            raise SystemExit(
                f"{target.language} produced inconsistent output: {current_output} != {output}"
            )
        output = current_output

    return statistics.median(samples), output


def main() -> int:
    require_tool("cc")
    require_tool("rustc")
    require_tool("python3")
    require_tool("swift")

    BUILD.mkdir(parents=True, exist_ok=True)
    range_env = embedded_swift_env()
    range_cli = ROOT / "RangeCLI" / ".build" / "release" / "RangeCLI"

    print(f"base iterations: {ITERATIONS}")
    print(f"runs: {RUNS}")
    print()

    if not timed_setup(
        "Range CLI",
        ["swift", "build", "-c", "release", "--package-path", "RangeCLI", "--product", "RangeCLI"],
        env=range_env,
    ):
        raise SystemExit("Range CLI setup failed")

    results: dict[str, list[tuple[str, float, float, str]]] = {}

    for case in cases():
        print()
        print(f"== {case.name} (N={case.n}) ==")
        targets = build_case(case, range_cli, range_env)
        baselines: dict[str, float] = {}
        case_results: list[tuple[str, float, float, str]] = []

        for target in targets:
            median, output = measure(target)
            if "C" not in baselines and target.language == "C":
                baselines["C"] = median
            baseline = baselines.get("C", median)
            relative = median / baseline if baseline else 1.0
            case_results.append((target.language, median, relative, output))
            print(f"{target.language:>6}: {median:.4f}s  {relative:>6.2f}x  output={output}")

        results[case.name] = case_results

    print()
    print("== Range summary ==")
    for case_name, case_results in results.items():
        range_row = next((row for row in case_results if row[0] == "Range"), None)
        rust_row = next((row for row in case_results if row[0] == "Rust"), None)
        if range_row and rust_row:
            range_vs_rust = range_row[1] / rust_row[1] if rust_row[1] else 0
            print(
                f"{case_name:>14}: Range {range_row[1]:.4f}s, "
                f"Rust {rust_row[1]:.4f}s, Range/Rust {range_vs_rust:.2f}x"
            )
        elif range_row:
            print(f"{case_name:>14}: Range {range_row[1]:.4f}s")
        else:
            print(f"{case_name:>14}: Range skipped")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
