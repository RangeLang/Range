#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${RANGE_REPOSITORY:-georgerange/Range}"
INSTALL_DIR="${RANGE_INSTALL_DIR:-${HOME}/.local/bin}"
VERSION="${1:-latest}"
TARGET_NAME="range"

usage() {
  echo "Usage: $0 [latest|vX.Y.Z]"
  echo "Environment: RANGE_REPOSITORY=owner/repo RANGE_INSTALL_DIR=/path/to/bin"
}

case "${VERSION}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

detect_platform() {
  local os
  local arch

  case "$(uname -s)" in
    Darwin) os="macos" ;;
    Linux) os="linux" ;;
    *)
      echo "Unsupported OS: $(uname -s)" >&2
      exit 1
      ;;
  esac

  case "$(uname -m)" in
    arm64|aarch64) arch="arm64" ;;
    x86_64|amd64) arch="x64" ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  echo "${os}-${arch}"
}

platform="$(detect_platform)"
archive="range-${platform}.tar.gz"

if [[ "${VERSION}" == "latest" ]]; then
  url="https://github.com/${REPOSITORY}/releases/latest/download/${archive}"
else
  url="https://github.com/${REPOSITORY}/releases/download/${VERSION}/${archive}"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

echo "Downloading ${url}"
curl -fsSL "${url}" -o "${tmp_dir}/${archive}"
tar -xzf "${tmp_dir}/${archive}" -C "${tmp_dir}"

mkdir -p "${INSTALL_DIR}"
install -m 755 "${tmp_dir}/range-${platform}/${TARGET_NAME}" "${INSTALL_DIR}/${TARGET_NAME}"

echo "Installed ${TARGET_NAME} to ${INSTALL_DIR}/${TARGET_NAME}"
if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
  echo "Add this to your shell profile:"
  echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
fi
