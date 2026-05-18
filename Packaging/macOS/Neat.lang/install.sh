#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
binary="$package_root/bin/neat"
prefix="${NEAT_INSTALL_PREFIX:-/usr/local}"
install_dir="$prefix/bin"
target="$install_dir/neat"
version_file="$package_root/VERSION"
version="unknown"

if [[ -f "$version_file" ]]; then
  version="$(tr -d '\n' < "$version_file")"
fi

if [[ ! -x "$binary" ]]; then
  echo "Missing executable: $binary" >&2
  echo "This package should contain bin/neat." >&2
  exit 1
fi

echo "Neat CLI installer"
echo "Version: $version"
echo
echo "Will install:"
echo "  $binary"
echo "to:"
echo "  $target"
echo
echo "Manifest:"
echo "  $package_root/INSTALL_MANIFEST.md"
echo

if [[ ! -d "$install_dir" ]]; then
  mkdir -p "$install_dir" 2>/dev/null || sudo mkdir -p "$install_dir"
fi

if [[ -w "$install_dir" ]]; then
  install -m 755 "$binary" "$target"
else
  sudo install -m 755 "$binary" "$target"
fi

echo
echo "Installed $target"
echo "Run: neat version"
