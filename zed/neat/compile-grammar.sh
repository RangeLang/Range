#!/usr/bin/env bash
# Compiles the tree-sitter grammar to a Zed-compatible WASM module.
#
# Run this after any change to grammar.js + `npx tree-sitter generate`.
# Then reload extensions in Zed (Cmd+Shift+P → "zed: reload extensions").

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER_C="$SCRIPT_DIR/grammars/tree-sitter-neat/src/parser.c"
OUT="$HOME/Library/Application Support/Zed/extensions/installed/neat/grammars/neat.wasm"

WASI_SDK="$HOME/Library/Application Support/Zed/extensions/build/wasi-sdk"
SYSROOT="$WASI_SDK/share/wasi-sysroot"
CLANG="$WASI_SDK/bin/clang"

echo "Compiling grammar WASM..."
"$CLANG" \
  --sysroot="$SYSROOT" \
  --target=wasm32-wasi \
  -Os \
  -o "$OUT" \
  "$PARSER_C" \
  -fno-exceptions \
  -fvisibility=hidden \
  -Wl,--no-entry \
  -Wl,--export=tree_sitter_neat \
  -Wl,--export-dynamic \
  -nostartfiles

echo "✅ Done: $OUT ($(du -h "$OUT" | cut -f1))"
echo "Now reload the Neat extension in Zed."
