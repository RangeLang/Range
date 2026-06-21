#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ZED_EXTENSION_DIR="${RANGE_ZED_EXTENSION_DIR:-${REPO_ROOT}/../RangeZed}"
GRAMMAR_DIR="${ZED_EXTENSION_DIR}/grammars/tree-sitter-range"
LANGUAGE_CONFIG="${ZED_EXTENSION_DIR}/languages/range/config.toml"
HIGHLIGHTS_QUERY="${ZED_EXTENSION_DIR}/languages/range/highlights.scm"
EXTENSION_MANIFEST="${ZED_EXTENSION_DIR}/extension.toml"
FIXTURE="${REPO_ROOT}/Development/Benchmarks/Speed/RangeSpeed/Playground.range"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "error: missing ${path}" >&2
    exit 1
  fi
}

require_file "${EXTENSION_MANIFEST}"
require_file "${LANGUAGE_CONFIG}"
require_file "${HIGHLIGHTS_QUERY}"
require_file "${GRAMMAR_DIR}/src/parser.c"
require_file "${FIXTURE}"

if ! grep -F 'languages = ["languages/range"]' "${EXTENSION_MANIFEST}" >/dev/null; then
  echo "error: Zed extension manifest does not register languages/range" >&2
  exit 1
fi

if ! grep -F 'path_suffixes = ["range"]' "${LANGUAGE_CONFIG}" >/dev/null; then
  echo "error: Zed language config does not associate .range files" >&2
  exit 1
fi

parse_output="$(
  cd "${GRAMMAR_DIR}"
  npx --yes tree-sitter-cli parse "${FIXTURE}" 2>&1
)"

if grep -E '\((ERROR|MISSING)' <<< "${parse_output}" >/dev/null; then
  echo "error: Tree-sitter grammar did not cleanly parse ${FIXTURE}" >&2
  echo "${parse_output}" >&2
  exit 1
fi

query_output="$(
  cd "${GRAMMAR_DIR}"
  npx --yes tree-sitter-cli query "${HIGHLIGHTS_QUERY}" "${FIXTURE}" 2>&1
)"

assert_capture() {
  local text="$1"
  local capture="$2"
  if ! grep -F "capture:" <<< "${query_output}" | grep -F -- "- ${capture}," | grep -F "text: \`${text}\`" >/dev/null; then
    echo "error: expected highlight capture ${text} as @${capture}" >&2
    echo "${query_output}" >&2
    exit 1
  fi
}

assert_capture "main" "keyword"
assert_capture "let" "keyword"
assert_capture "n" "declaration"
assert_capture "Int" "type"
assert_capture "10000000" "number"
assert_capture "log" "function.method"
assert_capture "\"" "string"

echo "Range Zed syntax highlighting check passed."
echo "Extension: ${ZED_EXTENSION_DIR}"
echo "Fixture:   ${FIXTURE}"
