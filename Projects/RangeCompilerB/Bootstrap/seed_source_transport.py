#!/usr/bin/env python3
"""Compiler A-only transport for canonical Compiler B cardinality syntax."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def transport_first_index(source: str) -> str:
    marker = ".firstIndex("
    cursor = 0
    output: list[str] = []
    while True:
        marker_index = source.find(marker, cursor)
        if marker_index < 0:
            output.append(source[cursor:])
            return "".join(output)

        receiver_start = marker_index
        while receiver_start > cursor and (
            source[receiver_start - 1].isalnum()
            or source[receiver_start - 1] in "_."
        ):
            receiver_start -= 1
        receiver = source[receiver_start:marker_index]
        if not receiver:
            raise ValueError("firstIndex receiver is not a canonical identity path")

        opening = marker_index + len(marker) - 1
        depth = 0
        closing = opening
        while closing < len(source):
            character = source[closing]
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    break
            closing += 1
        if depth != 0:
            raise ValueError("firstIndex application is not balanced")

        argument = source[opening + 1 : closing].strip()
        if not argument.startswith("value:"):
            raise ValueError("firstIndex application is missing its value label")
        value = argument[len("value:") :].strip()
        output.append(source[cursor:receiver_start])
        output.append(
            "compilerBFacetRowForSyntaxID("
            f"syntaxIDs: {receiver}, syntaxID: {value})"
        )
        cursor = closing + 1


def transport(source: str, strip_entry: bool, seed_string_storage: bool) -> str:
    if seed_string_storage:
        source = re.sub(
            r"(?m)^construct String \{\n\s*@many\n\s*state bytes: Byte\n",
            "@builtin(.storage)\nconstruct String {\n"
            "    state bytes: CompilerBSeedByteManyTransport\n",
            source,
            count=1,
        )
    source = re.sub(
        r"(?m)^(\s*)@many\s*\n\1state (\w+): Int\s*$",
        r"\1let \2: CompilerBSeedIntManyTransport",
        source,
    )
    source = re.sub(
        r"(?m)^(\s*)@many\s*\n\1state (\w+): Byte\s*$",
        r"\1state \2: CompilerBSeedByteManyTransport",
        source,
    )
    source = re.sub(
        r"\b(let|state) (\w+): @many\(capacity: ([^()\n]+)\)",
        r"\1 \2: CompilerBSeedIntManyTransport(bufferCreateInt(capacity: \3))",
        source,
    )
    source = source.replace("@many(capacity:", "bufferCreateInt(capacity:")
    source = transport_first_index(source)
    if strip_entry:
        source = re.sub(r"(?ms)^macro compilerEntry\(\).*\Z", "", source)
    return source


def main() -> int:
    if len(sys.argv) not in (2, 3) or (
        len(sys.argv) == 3 and sys.argv[2] != "--strip-entry"
    ):
        print("usage: seed_source_transport.py <source> [--strip-entry]", file=sys.stderr)
        return 64
    source_path = Path(sys.argv[1])
    source = source_path.read_text()
    path = source_path.as_posix()
    if path.endswith("/Core/Macros/Print.range"):
        source = """macro print(message: String): Void {
    stringPrint(value: message)
}

macro print(nodes: @many): Void {
    nodes.each { node in
        stringPrint(value: node)
    }
}
"""
    elif path.endswith("/Core/Macros/Diagnostic.range"):
        source = """macro diagnostic(message: String): Void {
    stringDiagnostic(value: message)
}
"""
    elif path.endswith("/Core/Process.range"):
        source = """@extern
@builtin
function stringPrint(value: String): Int

@extern
@builtin
function stringDiagnostic(value: String): Int

""" + source
    elif path.endswith("/Core/Execution.range"):
        source = source.replace(
            "    binding effect: @syntax?",
            "    binding effect: Write?",
        )
        source = re.sub(
            r"(?m)^\s*@many\s*\n\s*state next: Execution\s*$",
            "    let next: CompilerBSeedIntManyTransport",
            source,
            count=1,
        )
    elif path.endswith("/Core/System/Output.range"):
        source = re.sub(
            r"(?m)^\s*@many\s*\n\s*binding bytes: Byte\s*$",
            "    binding bytes: String",
            source,
            count=1,
        )
        source = source.replace(
            "macro write(bytes: @many, destination: Output): Void",
            "macro write(bytes: String, destination: Output): Void",
        )
    sys.stdout.write(
        transport(
            source,
            len(sys.argv) == 3,
            path.endswith("/Core/String.range"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
