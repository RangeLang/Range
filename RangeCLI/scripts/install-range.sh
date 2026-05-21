#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PACKAGE_TEMPLATE="${ROOT_DIR}/Packaging/macOS/Range.lang"
PRODUCT_NAME="RangeCLI"
INSTALL_PREFIX="${RANGE_INSTALL_PREFIX:-${HOME}/.range}"
ACTION="install"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall)
      ACTION="uninstall"
      shift
      ;;
    --path)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --path"
        echo "Usage: $0 [--path <install-prefix>] [--uninstall]"
        exit 1
      fi
      INSTALL_PREFIX="$2"
      shift 2
      ;;
    --local|--global|--fully)
      echo "Flag $1 is no longer used. Range installs under a prefix with current -> versions/<version>."
      echo "Use --path <install-prefix> or RANGE_INSTALL_PREFIX instead."
      exit 1
      ;;
    *)
      echo "Unknown flag: $1"
      echo "Usage: $0 [--path <install-prefix>] [--uninstall]"
      exit 1
      ;;
  esac
done

if [[ "${ACTION}" == "uninstall" ]]; then
  RANGE_INSTALL_PREFIX="${INSTALL_PREFIX}" "${PACKAGE_TEMPLATE}/uninstall.sh"
  exit 0
fi

cd "${ROOT_DIR}/RangeCLI"
swift build -c release --product "${PRODUCT_NAME}"

BINARY="${ROOT_DIR}/RangeCLI/.build/release/${PRODUCT_NAME}"
if [[ ! -x "${BINARY}" ]]; then
  echo "Build succeeded but binary not found at ${BINARY}" >&2
  exit 1
fi

release_version="$(
  sed -nE 's/.*SemanticVersion\(major: ([0-9]+), minor: ([0-9]+), patch: ([0-9]+)\).*/\1.\2.\3/p' \
    "${ROOT_DIR}/RangeCLI/Sources/RangeCLI/RangeVersion.swift" \
    | head -n 1
)"

stage="$(mktemp -d)"
trap 'rm -rf "${stage}"' EXIT
package="${stage}/Range.lang"
cp -R "${PACKAGE_TEMPLATE}" "${package}"
cp "${BINARY}" "${package}/range"
cp -R "${ROOT_DIR}/RangeCore" "${package}/RangeCore"
mkdir -p "${package}/Skills"
cp -R "${ROOT_DIR}/.codex/skills/range-onboarding" "${package}/Skills/range-onboarding"
printf '%s\n' "${release_version}" > "${package}/VERSION"
chmod 755 "${package}/range" "${package}/install.sh" "${package}/uninstall.sh"

RANGE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
RANGE_INSTALL_ASSUME_YES=true \
  "${package}/install.sh"

if [[ ":${PATH}:" != *":${INSTALL_PREFIX}/current:"* ]]; then
  echo "Add this to your shell profile:"
  echo "  export PATH=\"${INSTALL_PREFIX}/current:\$PATH\""
fi
