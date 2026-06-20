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


def remove_embedded_swift_setting(package_swift: Path) -> None:
    source = package_swift.read_text(encoding="utf-8")
    source = source.replace(".macOS(.v14)", ".macOS(.v26)")
    source = source.replace(
        """,
            swiftSettings: [
                .enableExperimentalFeature("Embedded")
            ]""",
        "",
    )
    package_swift.write_text(source, encoding="utf-8")


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

    local_range_cli = ROOT / "CLI" / ".build" / "release" / "CLI"
    installed_range_cli = shutil.which("range")
    range_cli = local_range_cli if local_range_cli.is_file() else None
    if range_cli is None and installed_range_cli:
        range_cli = Path(installed_range_cli)
    if range_cli is None:
        run(["swift", "build", "-c", "release", "--package-path", "CLI", "--product", "CLI"])
        range_cli = local_range_cli

    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir(parents=True)

    c_source = BUILD / "main.c"
    c_binary = BUILD / "nested-c"
    range_project = BUILD / "RangeNested"
    generated_swift_package = range_project / ".range" / "Build" / "swift"
    embedded_range_binary = generated_swift_package / ".build" / "debug" / "RangeGenerated"
    nonembedded_range_binary = generated_swift_package / ".build" / "release" / "RangeGenerated"

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

    project_manifest = """
        @project
        construct Project {
            let name: Title("RangeNestedBillion")
            let version: Version(0.1.0)
            let author: "George"
        }
        """
    package_manifest = """
        @package
        construct RangeNestedBillion {
            let name: Title("RangeNestedBillion")
            let version: Version(0.1.0)
            let author: "George"
        }
        """
    write_text(range_project / "Project.range", project_manifest)
    write_text(range_project / "Package.range", package_manifest)
    write_text(
        range_project / "Playground.range",
        f"""
        @main {{
            let outer: Int   {OUTER}
            let inner: Int   {INNER}
            state i: Int   0
            state acc: Int   1

            while i < outer {{
                state j: Int   0
                while j < inner {{
                    set acc   ((acc * 1664525) + i + j) % 2147483647
                    j += 1
                }}
                i += 1
            }}

            Logger.log("\\(acc)")
        }}
        """,
    )

    range_build = try_run([str(range_cli), "run", str(range_project / "Playground.range")])
    if range_build is None and range_cli == local_range_cli and installed_range_cli:
        range_cli = Path(installed_range_cli)
        range_build = try_run([str(range_cli), "run", str(range_project / "Playground.range")])

    range_binary = embedded_range_binary
    range_label = "Range"
    if range_build is None or not embedded_range_binary.is_file():
        package_swift = generated_swift_package / "Package.swift"
        if not package_swift.is_file():
            raise SystemExit("Range build failed before generating Swift")
        remove_embedded_swift_setting(package_swift)
        run(["swift", "build", "-c", "release", "--package-path", str(generated_swift_package)])
        range_binary = nonembedded_range_binary
        range_label = "Range-generated Swift (non-Embedded fallback)"

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
        print("warning: outputs differ; Range Int overflow semantics differ from C uint64 wraparound here")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
