#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${RANGE_REPOSITORY:-georgetchelidze/Range}"
INSTALL_PREFIX="${RANGE_INSTALL_PREFIX:-${HOME}/.range}"
VERSION="${1:-latest}"

usage() {
  echo "Usage: $0 [latest|vX.Y.Z]"
  echo "Environment: RANGE_REPOSITORY=owner/repo RANGE_INSTALL_PREFIX=\$HOME/.range"
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
archive="range-${platform}.lang.tar.gz"

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

RANGE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
RANGE_INSTALL_ASSUME_YES=true \
  "${tmp_dir}/range-${platform}.lang/install.sh"

installed_version="$VERSION"
if [[ -f "${tmp_dir}/range-${platform}.lang/VERSION" ]]; then
  installed_version="$(tr -d '\n' < "${tmp_dir}/range-${platform}.lang/VERSION")"
fi

current_path="${INSTALL_PREFIX}/current/${installed_version}"
echo "Installed range to ${current_path}/range"
if [[ ":${PATH}:" != *":${current_path}:"* ]]; then
  echo "Add this to your shell profile:"
  echo "  export PATH=\"${current_path}:\$PATH\""
fi
