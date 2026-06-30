#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

PATH="$HOME/.swiftly/bin:$PATH" "$ROOT_DIR/scripts/range" run "$SCRIPT_DIR" -- "$@"
