#!/usr/bin/env bash
# Compiles the Neat tree-sitter grammar to a Zed-compatible dylink WASM.
#
# This uses the EXACT same clang flags as Zed's internal extension builder
# (see zed/crates/extension/src/extension_builder.rs :: compile_grammar).
#
# Zed skips recompiling if neat.wasm is newer than parser.c + scanner.c.
# This script forces a fresh compile so changes always take effect.
#
# Workflow:
#   1. Edit grammar.js
#   2. Run: npx tree-sitter generate   (updates src/parser.c)
#   3. Run: ./compile-grammar.sh
#   4. Reload extensions in Zed: Cmd+Shift+P → "zed: reload extensions"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/grammars/tree-sitter-neat/src"
OUT="$HOME/Library/Application Support/Zed/extensions/installed/neat/grammars/neat.wasm"
WASI_SDK="$HOME/Library/Application Support/Zed/extensions/build/wasi-sdk"
CLANG="$WASI_SDK/bin/clang"

# Optionally regenerate parser first
if [ "${1:-}" = "--generate" ]; then
  echo "→ Regenerating parser from grammar.js..."
  (cd "$SCRIPT_DIR/grammars/tree-sitter-neat" && npx tree-sitter-cli generate)
fi

echo "→ Compiling grammar WASM (dylink format)..."
"$CLANG" \
  -fPIC -shared -Os \
  "-Wl,--export=tree_sitter_neat" \
  -o "$OUT" \
  -I "$SRC" \
  "$SRC/parser.c"

echo "✅ $(du -h "$OUT" | cut -f1) written to Zed grammars"
echo "   Reload extensions: Cmd+Shift+P → 'zed: reload extensions'"
