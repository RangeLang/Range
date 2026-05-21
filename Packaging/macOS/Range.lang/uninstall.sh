#!/usr/bin/env bash
set -euo pipefail

default_prefix="$HOME/.range"
prefix="${RANGE_INSTALL_PREFIX:-$default_prefix}"
current_target="$prefix/current"

echo "Range CLI uninstaller"
echo
echo "Will remove:"
echo "  $current_target"
echo

if [[ ! -e "$current_target" ]]; then
  echo "Nothing to remove."
  exit 0
fi

if [[ -L "$current_target" && -w "$(dirname "$current_target")" ]]; then
  rm -f "$current_target"
elif [[ -e "$current_target" && -w "$(dirname "$current_target")" ]]; then
  rm -rf "$current_target"
elif [[ -e "$current_target" ]]; then
  sudo rm -rf "$current_target"
fi

echo "Removed Range CLI."
