#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PRODUCT_NAME="CLI"
INSTALL_PREFIX="${RANGE_INSTALL_PREFIX:-${HOME}/.range}"
ACTION="install"

case "$(uname -s)" in
  Darwin) PACKAGE_TEMPLATE="${ROOT_DIR}/Packaging/macOS/Range.lang" ;;
  Linux) PACKAGE_TEMPLATE="${ROOT_DIR}/Packaging/Linux/Range.lang" ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

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
      echo "Flag $1 is no longer used. Range installs under a prefix with current/<version> -> releases/<version>."
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

cd "${ROOT_DIR}/CLI"
swift build -c release --product "${PRODUCT_NAME}"

BINARY="${ROOT_DIR}/CLI/.build/release/${PRODUCT_NAME}"
if [[ ! -x "${BINARY}" ]]; then
  echo "Build succeeded but binary not found at ${BINARY}" >&2
  exit 1
fi

release_version="$(
  sed -nE 's/.*SemanticVersion\(major: ([0-9]+), minor: ([0-9]+), patch: ([0-9]+)\).*/\1.\2.\3/p' \
    "${ROOT_DIR}/CLI/Sources/CLI/RangeVersion.swift" \
    | head -n 1
)"

stage="$(mktemp -d)"
trap 'rm -rf "${stage}"' EXIT
package="${stage}/Range.lang"
cp -R "${PACKAGE_TEMPLATE}" "${package}"
cp "${BINARY}" "${package}/range"
cp -R "${ROOT_DIR}/RangeCore" "${package}/RangeCore"
printf '%s\n' "${release_version}" > "${package}/VERSION"
chmod 755 "${package}/range" "${package}/install.sh" "${package}/uninstall.sh"

RANGE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
RANGE_INSTALL_ASSUME_YES=true \
  "${package}/install.sh"

current_path="${INSTALL_PREFIX}/current/${release_version}"
if [[ ":${PATH}:" != *":${current_path}:"* ]]; then
  echo "Add this to your shell profile:"
  echo "  export PATH=\"${current_path}:\$PATH\""
fi
