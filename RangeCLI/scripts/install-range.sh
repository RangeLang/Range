#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRODUCT_NAME="RangeCLI"
TARGET_NAME="range"

MODE="auto"
ACTION="install"
CUSTOM_INSTALL_DIR=""
FULLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      MODE="local"
      shift
      ;;
    --global)
      MODE="global"
      shift
      ;;
    --uninstall)
      ACTION="uninstall"
      shift
      ;;
    --path)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --path"
        echo "Usage: $0 [--local|--global] [--path <install-dir>] [--fully] [--uninstall]"
        exit 1
      fi
      CUSTOM_INSTALL_DIR="$2"
      shift 2
      ;;
    --fully)
      FULLY=1
      shift
      ;;
    *)
      echo "Unknown flag: $1"
      echo "Usage: $0 [--local|--global] [--path <install-dir>] [--fully] [--uninstall]"
      exit 1
      ;;
  esac
done

LOCAL_BIN="${HOME}/.local/bin"
BREW_BIN="/opt/homebrew/bin"
GLOBAL_BIN="/usr/local/bin"
LOCAL_TARGET="${LOCAL_BIN}/${TARGET_NAME}"
GLOBAL_TARGET="${GLOBAL_BIN}/${TARGET_NAME}"

ensure_local_bin_on_path() {
  if [[ ":${PATH}:" != *":${LOCAL_BIN}:"* ]]; then
    echo "Note: ${LOCAL_BIN} is not on PATH."
    echo "Add this to your shell profile:"
    echo "  export PATH=\"${LOCAL_BIN}:\$PATH\""
  fi
}

choose_install_dir() {
  if [[ -n "${CUSTOM_INSTALL_DIR}" ]]; then
    echo "${CUSTOM_INSTALL_DIR}"
    return
  fi

  case "${MODE}" in
    local)
      echo "${LOCAL_BIN}"
      return
      ;;
    global)
      echo "${GLOBAL_BIN}"
      return
      ;;
    auto)
      if [[ -d "${BREW_BIN}" && -w "${BREW_BIN}" ]]; then
        echo "${BREW_BIN}"
      elif [[ -w "${GLOBAL_BIN}" ]]; then
        echo "${GLOBAL_BIN}"
      else
        echo "${LOCAL_BIN}"
      fi
      return
      ;;
  esac
}

uninstall() {
  local removed=0

  if [[ -e "${GLOBAL_TARGET}" ]]; then
    if [[ -w "${GLOBAL_TARGET}" ]]; then
      rm -f "${GLOBAL_TARGET}"
    else
      sudo rm -f "${GLOBAL_TARGET}"
    fi
    echo "Removed ${GLOBAL_TARGET}"
    removed=1
  fi

  if [[ -e "${LOCAL_TARGET}" ]]; then
    rm -f "${LOCAL_TARGET}"
    echo "Removed ${LOCAL_TARGET}"
    removed=1
  fi

  if [[ "${removed}" -eq 0 ]]; then
    echo "No installed '${TARGET_NAME}' binary found in ${GLOBAL_BIN} or ${LOCAL_BIN}."
  fi
}

if [[ "${ACTION}" == "uninstall" ]]; then
  uninstall
  exit 0
fi

cd "${ROOT_DIR}"
swift package clean
swift build -c release --product "${PRODUCT_NAME}"

BINARY="${ROOT_DIR}/.build/release/${PRODUCT_NAME}"
if [[ ! -x "${BINARY}" ]]; then
  echo "Build succeeded but binary not found at ${BINARY}"
  exit 1
fi

INSTALL_DIR="$(choose_install_dir)"

if [[ -d "${INSTALL_DIR}" ]]; then
  if [[ "${FULLY}" -ne 1 && ( -f "${INSTALL_DIR}/Package.range" || -f "${INSTALL_DIR}/App.range" || -d "${INSTALL_DIR}/.range" ) ]]; then
    echo "Refusing to install '${TARGET_NAME}' into project directory: ${INSTALL_DIR}"
    echo "Choose a bin directory like /opt/homebrew/bin, /usr/local/bin, or ${LOCAL_BIN}."
    echo "Pass --fully to override."
    exit 1
  fi
fi

if [[ "${FULLY}" -ne 1 && -n "${CUSTOM_INSTALL_DIR}" ]]; then
  INSTALL_BASENAME="$(basename "${INSTALL_DIR}")"
  if [[ "${INSTALL_BASENAME}" != "bin" ]]; then
    echo "Refusing to install '${TARGET_NAME}' into non-bin path: ${INSTALL_DIR}"
    echo "Choose a bin directory like /opt/homebrew/bin, /usr/local/bin, or ${LOCAL_BIN}."
    echo "Pass --fully to override."
    exit 1
  fi
fi

mkdir -p "${INSTALL_DIR}"
TARGET_PATH="${INSTALL_DIR}/${TARGET_NAME}"

if [[ -e "${TARGET_PATH}" && ! -w "${TARGET_PATH}" ]]; then
  sudo install -m 755 "${BINARY}" "${TARGET_PATH}"
else
  install -m 755 "${BINARY}" "${TARGET_PATH}"
fi

echo "Installed '${TARGET_NAME}' to ${TARGET_PATH}"
echo "Try it now: ${TARGET_PATH} --help"
"${TARGET_PATH}" --help >/dev/null 2>&1 || true

if [[ "${INSTALL_DIR}" == "${LOCAL_BIN}" ]]; then
  ensure_local_bin_on_path
fi
