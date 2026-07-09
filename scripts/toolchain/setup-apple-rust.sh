#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

if (( BASH_VERSINFO[0] < 4 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 4+ is required." >&2
    exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../supported.sh"

APPLE_CARGO_HOME="${CARGO_HOME:-${HOME}/.cargo}"
APPLE_RUSTUP_HOME="${RUSTUP_HOME:-${HOME}/.rustup}"

platform="${1:-${PLATFORM:-}}"
arch="${2:-${ARCH:-}}"

if [[ -z "${platform}" || -z "${arch}" ]]; then
  echo "Usage: $0 <platform> <arch>" >&2
  exit 1
fi

combo="${platform}-${arch}"
is_valid_combo=false
for valid in "${VALID_APPLE[@]}"; do
  if [[ "${valid}" == "${combo}" ]]; then
    is_valid_combo=true
    break
  fi
done

if [[ "${is_valid_combo}" != "true" ]]; then
  echo "Unsupported Apple platform/arch combo: ${combo}" >&2
  exit 1
fi

if ! command -v rustup >/dev/null 2>&1; then
  echo "rustup is required but was not found in PATH." >&2
  exit 1
fi

apply_apple_rust_environment() {
  export CARGO_HOME="${APPLE_CARGO_HOME}"
  export RUSTUP_HOME="${APPLE_RUSTUP_HOME}"

  if [[ -f "${CARGO_HOME}/env" ]]; then
    # shellcheck source=/dev/null
    source "${CARGO_HOME}/env"
  elif [[ ":${PATH}:" != *":${CARGO_HOME}/bin:"* ]]; then
    export PATH="${CARGO_HOME}/bin:${PATH}"
  fi

  if [[ -n "${GITHUB_ENV:-}" ]]; then
    grep -qxF "CARGO_HOME=${CARGO_HOME}" "${GITHUB_ENV}" 2>/dev/null || echo "CARGO_HOME=${CARGO_HOME}" >>"${GITHUB_ENV}"
    grep -qxF "RUSTUP_HOME=${RUSTUP_HOME}" "${GITHUB_ENV}" 2>/dev/null || echo "RUSTUP_HOME=${RUSTUP_HOME}" >>"${GITHUB_ENV}"
  fi
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    grep -qxF "${CARGO_HOME}/bin" "${GITHUB_PATH}" 2>/dev/null || echo "${CARGO_HOME}/bin" >>"${GITHUB_PATH}"
  fi
}

find_homebrew_cargo_cinstall() {
  local brew_prefix="${HOMEBREW_PREFIX:-}"
  local candidate

  if [[ -z "$brew_prefix" ]] && command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
  fi

  for candidate in \
    "${brew_prefix}/bin/cargo-cinstall" \
    /opt/homebrew/bin/cargo-cinstall \
    /usr/local/bin/cargo-cinstall \
    "${brew_prefix}/opt/cargo-c/bin/cargo-cinstall" \
    /opt/homebrew/opt/cargo-c/bin/cargo-cinstall \
    /usr/local/opt/cargo-c/bin/cargo-cinstall; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_cargo_c_path() {
  local cargo_cinstall
  local cargo_c_bin
  if cargo_cinstall="$(find_homebrew_cargo_cinstall)"; then
    cargo_c_bin="$(dirname "$cargo_cinstall")"
    if [[ ":${PATH}:" != *":${cargo_c_bin}:"* ]]; then
      export PATH="${cargo_c_bin}:${PATH}"
    fi
    if [[ -n "${GITHUB_PATH:-}" ]]; then
      grep -qxF "${cargo_c_bin}" "${GITHUB_PATH}" 2>/dev/null || echo "${cargo_c_bin}" >>"${GITHUB_PATH}"
    fi
  fi
}

rust_target_for_combo() {
  local target_combo="$1"
  case "${target_combo}" in
    ios-aarch64)
      echo "aarch64-apple-ios"
      ;;
    iphonesimulator-aarch64)
      echo "aarch64-apple-ios-sim"
      ;;
    appletvos-aarch64)
      echo "aarch64-apple-tvos"
      ;;
    appletvsimulator-aarch64)
      echo "aarch64-apple-tvos-sim"
      ;;
    macos-aarch64)
      echo "aarch64-apple-darwin"
      ;;
    macos-x86_64)
      echo "x86_64-apple-darwin"
      ;;
    *)
      return 1
      ;;
  esac
}

rust_target_installed() {
  local target="$1"
  rustup target list --installed 2>/dev/null | grep -qx "${target}"
}

apply_apple_rust_environment
ensure_cargo_c_path

rust_target="$(rust_target_for_combo "${combo}")"

if [[ "${combo}" == appletvos-* || "${combo}" == appletvsimulator-* ]]; then
  rustup toolchain install nightly
  rustup component add rust-src --toolchain nightly
  if rust_target_installed "${rust_target}"; then
    echo "Rust target ${rust_target} already installed for ${combo}."
    rustup target list --installed | grep -x "${rust_target}"
  else
    rustup target add "${rust_target}" --toolchain nightly || true
  fi
else
  if rust_target_installed "${rust_target}"; then
    echo "Rust target ${rust_target} already installed for ${combo}."
    rustup target list --installed | grep -x "${rust_target}"
  else
    rustup target add "${rust_target}"
    rustup target list --installed | grep -x "${rust_target}"
  fi
fi

if ! cargo cinstall --version >/dev/null 2>&1; then
  cargo install --locked cargo-c
fi
