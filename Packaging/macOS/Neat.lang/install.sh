#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
binary="$package_root/bin/neat"
core_sources="$package_root/share/neat/NeatCore"
skill_sources="$package_root/share/neat/Skills"
default_prefix="$HOME/.neat"
prefix="${NEAT_INSTALL_PREFIX:-$default_prefix}"
store_root="${NEAT_STORE_ROOT:-$HOME/.neat/NeatCLI}"
install_dir="$prefix/bin"
target="$install_dir/neat"
share_dir="$prefix/share/neat"
core_target="$share_dir/NeatCore"
skill_target="$share_dir/Skills"
packages_dir="$HOME/.neat/Packages"
version_file="$package_root/VERSION"
version="unknown"

if [[ -f "$version_file" ]]; then
  version="$(tr -d '\n' < "$version_file")"
fi

payload_dir="$store_root/$version"
payload_bin_dir="$payload_dir/bin"
payload_share_dir="$payload_dir/share/neat"
payload_binary="$payload_bin_dir/neat"
payload_core="$payload_share_dir/NeatCore"
payload_skills="$payload_share_dir/Skills"

if [[ ! -x "$binary" ]]; then
  echo "Missing executable: $binary" >&2
  echo "This package should contain bin/neat." >&2
  exit 1
fi

echo "Neat CLI installer"
echo
echo "Will install Neat $version"
echo "stored in:"
echo "  $payload_dir"
echo "to:"
echo "  $target"
echo "  $core_target"
echo "  $skill_target"
echo "  $packages_dir"
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

if [[ ! -d "$core_sources" ]]; then
  echo "Missing NeatCore sources: $core_sources" >&2
  exit 1
fi

if [[ ! -d "$skill_sources" ]]; then
  echo "Missing Neat skills: $skill_sources" >&2
  exit 1
fi

if [[ ! -d "$share_dir" ]]; then
  mkdir -p "$share_dir" 2>/dev/null || {
    echo "Cannot create $share_dir." >&2
    echo "Choose a writable prefix with NEAT_INSTALL_PREFIX, for example:" >&2
    echo "  NEAT_INSTALL_PREFIX=\"\$HOME/.neat\" ./install.sh" >&2
    exit 1
  }
fi

if [[ ! -d "$install_dir" ]]; then
  mkdir -p "$install_dir" 2>/dev/null || {
    echo "Cannot create $install_dir." >&2
    echo "Choose a writable prefix with NEAT_INSTALL_PREFIX, for example:" >&2
    echo "  NEAT_INSTALL_PREFIX=\"\$HOME/.neat\" ./install.sh" >&2
    exit 1
  }
fi

if [[ ! -w "$install_dir" || ! -w "$share_dir" ]]; then
  echo "Cannot install to $prefix because it is not writable." >&2
  echo "Choose a writable prefix with NEAT_INSTALL_PREFIX, for example:" >&2
  echo "  NEAT_INSTALL_PREFIX=\"\$HOME/.neat\" ./install.sh" >&2
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
echo "Run: neat version"
