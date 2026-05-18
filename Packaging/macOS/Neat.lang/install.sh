#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
binary="$package_root/bin/neat"
core_sources="$package_root/share/neat/NeatCore"
prefix="${NEAT_INSTALL_PREFIX:-/usr/local}"
install_dir="$prefix/bin"
target="$install_dir/neat"
share_dir="$prefix/share/neat"
core_target="$share_dir/NeatCore"
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
echo
echo "Will install Neat $version"
echo "to:"
echo "  $target"
echo "  $core_target"
echo

if [[ "${NEAT_INSTALL_ASSUME_YES:-false}" != "true" ]]; then
  read -r -p "Continue? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
fi

if [[ ! -d "$install_dir" ]]; then
  mkdir -p "$install_dir" 2>/dev/null || sudo mkdir -p "$install_dir"
fi

if [[ -w "$install_dir" ]]; then
  install -m 755 "$binary" "$target"
else
  sudo install -m 755 "$binary" "$target"
fi

if [[ ! -d "$core_sources" ]]; then
  echo "Missing NeatCore sources: $core_sources" >&2
  exit 1
fi

if [[ ! -d "$share_dir" ]]; then
  mkdir -p "$share_dir" 2>/dev/null || sudo mkdir -p "$share_dir"
fi

if [[ -w "$share_dir" ]]; then
  rm -rf "$core_target"
  cp -R "$core_sources" "$core_target"
else
  sudo rm -rf "$core_target"
  sudo cp -R "$core_sources" "$core_target"
fi

echo
echo "Installed $target"
echo "Run: neat version"
