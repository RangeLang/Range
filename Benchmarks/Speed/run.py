#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "Benchmarks" / "Speed"
BUILD = BENCH / ".build"
ITERATIONS = int(os.environ.get("N", "10000000"))
RUNS = int(os.environ.get("RUNS", "5"))
VERBOSE = os.environ.get("VERBOSE") == "1"


@dataclass(frozen=True)
class BenchTarget:
    name: str
    command: list[str]


def run_command(command: list[str], cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


def timed_setup(label: str, command: list[str], cwd: Path = ROOT) -> bool:
    started = time.perf_counter()
    try:
        run_command(command, cwd)
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


def prepare_gradient_project() -> Path:
    project = BUILD / "GradientSpeed"
    project.mkdir(parents=True, exist_ok=True)
    (project / "Package.gradient").write_text(
        """#package
construct Project {
    let name: Title("GradientSpeed")
    let version: Version(0.1.0)
    let author: String("George")
}
""",
        encoding="utf-8",
    )
    (project / "Playground.gradient").write_text(
        f"""#main {{
    let n: Int = {ITERATIONS}

    state i: Int = 0
    state acc: Int = 1
    while i < n {{
        acc = (acc * 1664525 + i) % 2147483647
        i += 1
    }}

    Logger.log("\\(acc)")
}}
""",
        encoding="utf-8",
    )
    return project


def build_targets() -> list[BenchTarget]:
    require_tool("cc")
    require_tool("rustc")
    require_tool("python3")
    require_tool("swift")

    BUILD.mkdir(parents=True, exist_ok=True)

    c_binary = BUILD / "speed-c"
    rust_binary = BUILD / "speed-rust"
    gradient_project = prepare_gradient_project()
    gradient_cli = ROOT / "GradientCLI" / ".build" / "release" / "GradientCLI"
    gradient_binary = gradient_project / ".gradient" / "Build" / "swift" / ".build" / "release" / "GradientGenerated"

    if not timed_setup(
        "C",
        ["cc", "-O3", str(BENCH / "c" / "main.c"), "-o", str(c_binary)],
    ):
        raise SystemExit("C setup failed")
    if not timed_setup(
        "Rust",
        ["rustc", "-C", "opt-level=3", str(BENCH / "rust" / "main.rs"), "-o", str(rust_binary)],
    ):
        raise SystemExit("Rust setup failed")
    if not timed_setup(
        "Gradient CLI",
        ["swift", "build", "-c", "release", "--package-path", "GradientCLI", "--product", "GradientCLI"],
    ):
        raise SystemExit("Gradient CLI setup failed")
    if not timed_setup(
        "Gradient emit",
        [str(gradient_cli), "compile", str(gradient_project)],
    ):
        raise SystemExit("Gradient emit failed")
    gradient_runtime_available = timed_setup(
        "Gradient generated Swift",
        ["swift", "build", "-c", "release"],
        cwd=gradient_project / ".gradient" / "Build" / "swift",
    )

    targets = [
        BenchTarget("C", [str(c_binary), str(ITERATIONS)]),
        BenchTarget("Rust", [str(rust_binary), str(ITERATIONS)]),
        BenchTarget("Python", ["python3", str(BENCH / "python" / "main.py"), str(ITERATIONS)]),
    ]

    if gradient_runtime_available:
        targets.append(BenchTarget("Gradient", [str(gradient_binary)]))
    else:
        print("Gradient runtime: skipped because generated Swift did not build")

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
                f"{target.name} produced inconsistent output: {current_output} != {output}"
            )
        output = current_output

    return statistics.median(samples), output


def main() -> int:
    print(f"iterations: {ITERATIONS}")
    print(f"runs: {RUNS}")
    print()

    targets = build_targets()

    print()
    baseline: float | None = None
    for target in targets:
        median, output = measure(target)
        if baseline is None:
            baseline = median
        relative = median / baseline if baseline else 1.0
        print(f"{target.name:>6}: {median:.4f}s  {relative:>6.2f}x  output={output}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
