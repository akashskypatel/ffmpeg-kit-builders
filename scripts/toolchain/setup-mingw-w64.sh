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

MINGW_VERSION="${MINGW_VERSION:-15.2.0-2}"
MINGW_ROOT="${MINGW_ROOT:-/usr/local/mingw-w64}"
MINGW_URL="${MINGW_URL:-https://github.com/xpack-dev-tools/mingw-w64-gcc-xpack/releases/download/v${MINGW_VERSION}/xpack-mingw-w64-gcc-${MINGW_VERSION}-linux-x64.tar.gz}"

rust_target_installed() {
  local target="$1"
  ! command -v rustup >/dev/null 2>&1 || rustup target list --installed 2>/dev/null | grep -qx "$target"
}

write_mingw_environment() {
  cat >/etc/profile.d/mingw-w64.sh <<EOF
export PATH="${MINGW_ROOT}/bin:\$PATH"
EOF
  chmod +x /etc/profile.d/mingw-w64.sh

  export PATH="${MINGW_ROOT}/bin:$PATH"

  if [[ -n "${GITHUB_PATH:-}" ]]; then
    grep -qxF "${MINGW_ROOT}/bin" "$GITHUB_PATH" 2>/dev/null || echo "${MINGW_ROOT}/bin" >>"$GITHUB_PATH"
  fi
}

mingw_toolchain_ready() {
  [[ -x "${MINGW_ROOT}/bin/x86_64-w64-mingw32-gcc" ]] &&
    command -v wine >/dev/null 2>&1 &&
    rust_target_installed x86_64-pc-windows-gnu
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must run as root." >&2
  exit 1
fi

if mingw_toolchain_ready; then
  write_mingw_environment
  echo "MinGW-w64 toolchain is already available at ${MINGW_ROOT}; skipping setup."
  "${MINGW_ROOT}/bin/x86_64-w64-mingw32-gcc" --version
  exit 0
fi

dnf install -y --setopt=install_weak_deps=False wget curl xz tar wine

if [[ ! -x "${MINGW_ROOT}/bin/x86_64-w64-mingw32-gcc" ]]; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  curl -L "$MINGW_URL" -o "$tmp_dir/mingw-w64.tar.gz"
  mkdir -p "$tmp_dir/extract"
  tar xf "$tmp_dir/mingw-w64.tar.gz" -C "$tmp_dir/extract"
  rm -rf "$MINGW_ROOT"
  mv "$tmp_dir/extract/xpack-mingw-w64-gcc-${MINGW_VERSION}" "$MINGW_ROOT"
  chown -R root:users "$MINGW_ROOT"
  chmod -R 775 "$MINGW_ROOT"
fi

write_mingw_environment

if command -v rustup >/dev/null 2>&1; then
  rust_target_installed x86_64-pc-windows-gnu || rustup target add x86_64-pc-windows-gnu
fi

"${MINGW_ROOT}/bin/x86_64-w64-mingw32-gcc" --version
