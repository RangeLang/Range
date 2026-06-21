#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.range/Build/llvm"
VALIDATION_SCRIPT="$BUILD_DIR/validate.sh"
CLI_BIN="$ROOT_DIR/CLI/.build/debug/CLI"

mkdir -p "$BUILD_DIR"

PATH="$HOME/.swiftly/bin:$PATH" swift build --package-path "$ROOT_DIR/CLI" >/dev/null

"$CLI_BIN" build "$SCRIPT_DIR"
"$CLI_BIN" compile "$SCRIPT_DIR" "$VALIDATION_SCRIPT"
"$VALIDATION_SCRIPT" "$@"
