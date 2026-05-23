#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
binary="$package_root/range"
core_sources="$package_root/RangeCore"
default_prefix="$HOME/.range"
prefix="${RANGE_INSTALL_PREFIX:-$default_prefix}"
store_root="${RANGE_STORE_ROOT:-$prefix/releases}"
current_target="$prefix/current"
packages_dir="$prefix/Packages"
projects_dir="$prefix/Projects"
version_file="$package_root/VERSION"
version="unknown"

if [[ -f "$version_file" ]]; then
  version="$(tr -d '\n' < "$version_file")"
fi

current_version_target="$current_target/$version"
payload_dir="$store_root/$version"
payload_binary="$payload_dir/range"
payload_core="$payload_dir/RangeCore"

if [[ ! -x "$binary" ]]; then
  echo "Missing executable: $binary" >&2
  echo "This package should contain range." >&2
  exit 1
fi

echo "Range CLI installer"
echo
echo "Will install Range $version"
echo "stored in:"
echo "  $payload_dir"
echo "active install:"
echo "  $current_version_target"
echo

if [[ "${RANGE_INSTALL_ASSUME_YES:-false}" != "true" ]]; then
  read -r -p "Continue? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
fi

if [[ ! -d "$core_sources" ]]; then
  echo "Missing RangeCore sources: $core_sources" >&2
  exit 1
fi

mkdir -p "$prefix" 2>/dev/null || {
  echo "Cannot create $prefix." >&2
  echo "Choose a writable prefix with RANGE_INSTALL_PREFIX, for example:" >&2
  echo "  RANGE_INSTALL_PREFIX=\"\$HOME/.range\" ./install.sh" >&2
  exit 1
}

if [[ ! -w "$prefix" ]]; then
  echo "Cannot install to $prefix because it is not writable." >&2
  echo "Choose a writable prefix with RANGE_INSTALL_PREFIX, for example:" >&2
  echo "  RANGE_INSTALL_PREFIX=\"\$HOME/.range\" ./install.sh" >&2
  exit 1
fi

if [[ -L "$current_target" || -f "$current_target" ]]; then
  rm -f "$current_target"
fi

mkdir -p "$packages_dir" "$projects_dir" "$store_root" "$payload_dir" "$current_target"
install -m 755 "$binary" "$payload_binary"
rm -rf "$payload_core"
cp -R "$core_sources" "$payload_core"
printf '%s\n' "$version" > "$payload_dir/VERSION"

ln -sfn "../releases/$version" "$current_version_target"

echo
echo "Installed $current_version_target/range"
echo "Run: range version"
