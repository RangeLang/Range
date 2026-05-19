#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
binary="$package_root/bin/range"
core_sources="$package_root/share/range/RangeCore"
skill_sources="$package_root/share/range/Skills"
default_prefix="$HOME/.range"
prefix="${RANGE_INSTALL_PREFIX:-$default_prefix}"
store_root="${RANGE_STORE_ROOT:-$HOME/.range/RangeCLI}"
install_dir="$prefix/bin"
target="$install_dir/range"
share_dir="$prefix/share/range"
core_target="$share_dir/RangeCore"
skill_target="$share_dir/Skills"
packages_dir="$HOME/.range/Packages"
version_file="$package_root/VERSION"
version="unknown"

if [[ -f "$version_file" ]]; then
  version="$(tr -d '\n' < "$version_file")"
fi

payload_dir="$store_root/$version"
payload_bin_dir="$payload_dir/bin"
payload_share_dir="$payload_dir/share/range"
payload_binary="$payload_bin_dir/range"
payload_core="$payload_share_dir/RangeCore"
payload_skills="$payload_share_dir/Skills"

if [[ ! -x "$binary" ]]; then
  echo "Missing executable: $binary" >&2
  echo "This package should contain bin/range." >&2
  exit 1
fi

echo "Range CLI installer"
echo
echo "Will install Range $version"
echo "stored in:"
echo "  $payload_dir"
echo "to:"
echo "  $target"
echo "  $core_target"
echo "  $skill_target"
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

if [[ ! -d "$skill_sources" ]]; then
  echo "Missing Range skills: $skill_sources" >&2
  exit 1
fi

if [[ ! -d "$share_dir" ]]; then
  mkdir -p "$share_dir" 2>/dev/null || {
    echo "Cannot create $share_dir." >&2
    echo "Choose a writable prefix with RANGE_INSTALL_PREFIX, for example:" >&2
    echo "  RANGE_INSTALL_PREFIX=\"\$HOME/.range\" ./install.sh" >&2
    exit 1
  }
fi

if [[ ! -d "$install_dir" ]]; then
  mkdir -p "$install_dir" 2>/dev/null || {
    echo "Cannot create $install_dir." >&2
    echo "Choose a writable prefix with RANGE_INSTALL_PREFIX, for example:" >&2
    echo "  RANGE_INSTALL_PREFIX=\"\$HOME/.range\" ./install.sh" >&2
    exit 1
  }
fi

if [[ ! -w "$install_dir" || ! -w "$share_dir" ]]; then
  echo "Cannot install to $prefix because it is not writable." >&2
  echo "Choose a writable prefix with RANGE_INSTALL_PREFIX, for example:" >&2
  echo "  RANGE_INSTALL_PREFIX=\"\$HOME/.range\" ./install.sh" >&2
  exit 1
fi

mkdir -p "$packages_dir"
mkdir -p "$payload_bin_dir" "$payload_share_dir"
install -m 755 "$binary" "$payload_binary"
rm -rf "$payload_core" "$payload_skills"
cp -R "$core_sources" "$payload_core"
cp -R "$skill_sources" "$payload_skills"

ln -sfn "$payload_binary" "$target"
ln -sfn "$payload_core" "$core_target"
ln -sfn "$payload_skills" "$skill_target"

echo
echo "Installed $target"
echo "Run: range version"
