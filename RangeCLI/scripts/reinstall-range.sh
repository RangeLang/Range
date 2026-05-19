#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install-gradient.sh"
TARGET_INPUT="${1:-}"
EXTRA_FLAG="${2:-}"
AUTO_YES=0

if [[ -n "${EXTRA_FLAG}" && "${EXTRA_FLAG}" != "--yes" ]]; then
  echo "Unknown flag: ${EXTRA_FLAG}"
  echo "Usage: $0 [path] [--yes]"
  exit 1
fi

if [[ "${EXTRA_FLAG}" == "--yes" ]]; then
  AUTO_YES=1
fi

confirm_wipe() {
  local label="$1"
  if [[ "${AUTO_YES}" -eq 1 ]]; then
    echo "Auto-confirmed wipe for ${label}."
    return 0
  fi
  echo "This will wipe existing content for ${label}."
  read -r -p "Continue? [y/N] " response
  case "${response}" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      echo "Aborted."
      return 1
      ;;
  esac
}

if [[ -z "${TARGET_INPUT}" ]]; then
  confirm_wipe "installed gradient binaries" || exit 1
  "${INSTALL_SCRIPT}" --uninstall
  "${INSTALL_SCRIPT}"
  exit 0
fi

PROJECT_DIR="${TARGET_INPUT}"
if [[ "${PROJECT_DIR}" == */gradient ]]; then
  PROJECT_DIR="${PROJECT_DIR%/gradient}"
fi

PROJECT_DIR="$(cd "$(dirname "${PROJECT_DIR}")" && pwd)/$(basename "${PROJECT_DIR}")"
BASENAME="$(basename "${PROJECT_DIR}")"

if [[ "${PROJECT_DIR}" == "/" || "${PROJECT_DIR}" == "${HOME}" || -z "${PROJECT_DIR}" || "${BASENAME}" == "bin" ]]; then
  echo "Refusing to wipe unsafe target path: ${PROJECT_DIR}"
  echo "Use a specific project directory path."
  exit 1
fi

confirm_wipe "${PROJECT_DIR}" || exit 1

if [[ -d "${PROJECT_DIR}" ]]; then
  find "${PROJECT_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
else
  mkdir -p "${PROJECT_DIR}"
fi

"${INSTALL_SCRIPT}"
"${SCRIPT_DIR}/../.build/release/GradientCLI" create "${PROJECT_DIR}"
