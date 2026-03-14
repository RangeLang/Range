#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${EXT_DIR}/../.." && pwd)"
EXT_TOML="${EXT_DIR}/extension.toml"
INSTALL_DIR="${HOME}/Library/Application Support/Zed/extensions/installed/neat"

if [[ ! -f "${EXT_TOML}" ]]; then
  echo "error: extension.toml not found at ${EXT_TOML}" >&2
  exit 1
fi

CURRENT_VERSION="$(
  perl -ne 'print "$1.$2.$3\n" if /^version = "([0-9]+)\.([0-9]+)\.([0-9]+)"/' "${EXT_TOML}" | head -n1
)"

if [[ -z "${CURRENT_VERSION}" ]]; then
  echo "error: could not read version from ${EXT_TOML}" >&2
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT_VERSION}"
NEXT_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
HEAD_REV="$(git -C "${REPO_ROOT}" rev-parse HEAD)"

DIRTY_ZED_FILES="$(git -C "${REPO_ROOT}" status --porcelain zed/neat)"

perl -0pi -e 's/version = "\Q'"${CURRENT_VERSION}"'\E"/version = "'"${NEXT_VERSION}"'"/' "${EXT_TOML}"

if [[ -z "${DIRTY_ZED_FILES}" ]]; then
  perl -0pi -e 's/rev = "[0-9a-f]{40}"/rev = "'"${HEAD_REV}"'"/' "${EXT_TOML}"
  echo "Updated extension version to ${NEXT_VERSION} and rev to ${HEAD_REV}"
else
  echo "Updated extension version to ${NEXT_VERSION}"
  echo "warning: zed/neat has uncommitted changes, so rev was left unchanged" >&2
fi

(cd "${EXT_DIR}" && cargo build)
(cd "${EXT_DIR}" && ./compile-grammar.sh)

mkdir -p "${INSTALL_DIR}"
rsync -a --delete \
  --exclude target \
  --exclude node_modules \
  --exclude build \
  --exclude .build \
  --exclude '.git' \
  --exclude 'grammars/neat' \
  --exclude 'grammars/_*' \
  "${EXT_DIR}/" "${INSTALL_DIR}/"

echo
echo "Synced Zed extension cache:"
echo "  version: ${NEXT_VERSION}"
if [[ -z "${DIRTY_ZED_FILES}" ]]; then
  echo "  rev:     ${HEAD_REV}"
else
  echo "  rev:     unchanged (dirty zed/neat worktree)"
fi
echo
echo "Next step: zed: reload extensions"
