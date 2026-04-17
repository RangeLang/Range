#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LANG_DIR="${EXT_DIR}/languages/neat"
FRAGMENTS_DIR="${LANG_DIR}/highlights"
OUT_FILE="${LANG_DIR}/highlights.scm"

FRAGMENTS=(
  "comments.scm"
  "keywords.scm"
  "control_flow.scm"
  "attributes.scm"
  "macros.scm"
  "builders.scm"
  "declarations.scm"
  "parameters.scm"
  "calls.scm"
  "assignments.scm"
  "types.scm"
  "literals.scm"
)

{
  echo "; GENERATED FILE. Do not edit directly."
  echo "; Source fragments live under languages/neat/highlights/."
  echo

  for fragment in "${FRAGMENTS[@]}"; do
    fragment_path="${FRAGMENTS_DIR}/${fragment}"
    if [[ ! -f "${fragment_path}" ]]; then
      echo "error: missing highlight fragment ${fragment_path}" >&2
      exit 1
    fi

    cat "${fragment_path}"
    echo
    echo
  done
} > "${OUT_FILE}"

echo "Built ${OUT_FILE}"
