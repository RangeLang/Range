#!/usr/bin/env bash
set -euo pipefail

default_prefix="$HOME/.gradient"
prefix="${GRADIENT_INSTALL_PREFIX:-$default_prefix}"
target="$prefix/bin/gradient"
core_target="$prefix/share/gradient/GradientCore"
skill_target="$prefix/share/gradient/Skills"

echo "Gradient CLI uninstaller"
echo
echo "Will remove:"
echo "  $target"
echo "  $core_target"
echo "  $skill_target"
echo

if [[ ! -e "$target" && ! -e "$core_target" && ! -e "$skill_target" ]]; then
  echo "Nothing to remove."
  exit 0
fi

if [[ -L "$target" && -w "$(dirname "$target")" ]]; then
  rm -f "$target"
elif [[ -e "$target" && -w "$(dirname "$target")" ]]; then
  rm -f "$target"
elif [[ -e "$target" ]]; then
  sudo rm -f "$target"
fi

if [[ -L "$core_target" && -w "$(dirname "$core_target")" ]]; then
  rm -f "$core_target"
elif [[ -e "$core_target" && -w "$(dirname "$core_target")" ]]; then
  rm -rf "$core_target"
elif [[ -e "$core_target" ]]; then
  sudo rm -rf "$core_target"
fi

if [[ -L "$skill_target" && -w "$(dirname "$skill_target")" ]]; then
  rm -f "$skill_target"
elif [[ -e "$skill_target" && -w "$(dirname "$skill_target")" ]]; then
  rm -rf "$skill_target"
elif [[ -e "$skill_target" ]]; then
  sudo rm -rf "$skill_target"
fi

echo "Removed Gradient CLI."
