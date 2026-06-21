#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.range/Build/llvm"
IR_FILE="$BUILD_DIR/RangeScalar.ll"
EXECUTABLE="$SCRIPT_DIR/.range/Build/llvm/Compiler"

if [[ ! -f "$IR_FILE" ]]; then
    echo "Missing LLVM IR file: $IR_FILE" >&2
    exit 1
fi

clang "$IR_FILE" -o "$EXECUTABLE"
"$EXECUTABLE" "$@"
