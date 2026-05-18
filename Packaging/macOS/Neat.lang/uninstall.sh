#!/usr/bin/env bash
set -euo pipefail

prefix="${NEAT_INSTALL_PREFIX:-/usr/local}"
target="$prefix/bin/neat"

echo "Neat CLI uninstaller"
echo
echo "Will remove:"
echo "  $target"
echo

if [[ ! -e "$target" ]]; then
  echo "Nothing to remove."
  exit 0
fi

if [[ -w "$(dirname "$target")" ]]; then
  rm -f "$target"
else
  sudo rm -f "$target"
fi

echo "Removed $target"
