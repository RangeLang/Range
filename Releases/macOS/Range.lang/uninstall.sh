#!/usr/bin/env bash
set -euo pipefail

default_prefix="$HOME/.range"
prefix="${RANGE_INSTALL_PREFIX:-$default_prefix}"
current_target="$prefix/current"
version="${RANGE_UNINSTALL_VERSION:-}"
current_is_legacy_symlink=false

if [[ -L "$current_target" ]]; then
  current_is_legacy_symlink=true
fi

if [[ "$current_is_legacy_symlink" == "false" && -z "$version" && -f "$current_target/VERSION" ]]; then
  version="$(tr -d '\n' < "$current_target/VERSION")"
fi

if [[ "$current_is_legacy_symlink" == "false" && -z "$version" && -d "$current_target" ]]; then
  version="$(
    find "$current_target" -mindepth 1 -maxdepth 1 -type l -exec basename {} \; | sort -Vr | head -n 1
  )"
fi

if [[ "$current_is_legacy_symlink" == "true" ]]; then
  remove_target="$current_target"
elif [[ -n "$version" ]]; then
  remove_target="$current_target/$version"
else
  remove_target="$current_target"
fi

echo "CLI uninstaller"
echo
echo "Will remove:"
echo "  $remove_target"
echo

if [[ ! -e "$remove_target" && ! -L "$remove_target" ]]; then
  echo "Nothing to remove."
  exit 0
fi

if [[ -L "$remove_target" && -w "$(dirname "$remove_target")" ]]; then
  rm -f "$remove_target"
elif [[ -e "$remove_target" && -w "$(dirname "$remove_target")" ]]; then
  rm -rf "$remove_target"
elif [[ -e "$remove_target" ]]; then
  sudo rm -rf "$remove_target"
fi

if [[ -d "$current_target" ]] && ! find "$current_target" -mindepth 1 -maxdepth 1 | read -r _; then
  rmdir "$current_target" 2>/dev/null || true
fi

echo "Removed CLI."
