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

EMSDK_ROOT="${EMSDK_ROOT:-/usr/local/emsdk}"
EMSDK_VERSION="${EMSDK_VERSION:-4.0.14}"
EMSDK_REPOSITORY="${EMSDK_REPOSITORY:-https://github.com/emscripten-core/emsdk.git}"

select_emsdk_python() {
  local candidate
  for candidate in \
    "${EMSDK_PYTHON:-}" \
    /opt/python/cp312-cp312/bin/python3 \
    /usr/local/bin/python3.12 \
    "$(command -v python3.12 2>/dev/null || true)" \
    "$(command -v python3 2>/dev/null || true)"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
      export EMSDK_BOOTSTRAP_PYTHON="$candidate"
      export PATH="$(dirname "$EMSDK_BOOTSTRAP_PYTHON"):$PATH"
      return 0
    fi
  done

  echo "Emscripten requires Python 3.10 or newer. Set EMSDK_PYTHON to a compatible interpreter." >&2
  return 1
}

rust_target_installed() {
  local target="$1"
  ! command -v rustup >/dev/null 2>&1 || rustup target list --installed 2>/dev/null | grep -qx "$target"
}

activate_emsdk() {
  local bootstrap_python="$EMSDK_BOOTSTRAP_PYTHON"

  # emsdk_env.sh sets PATH, EM_CONFIG, EM_CACHE, and EMSDK_NODE together.
  # shellcheck source=/dev/null
  export EMSDK_QUIET=1
  source "${EMSDK_ROOT}/emsdk_env.sh" >/dev/null
  export EMSDK_BOOTSTRAP_PYTHON="$bootstrap_python"
}

write_emscripten_environment() {
  activate_emsdk

  local emcc_dir node_dir binaryen_dir
  emcc_dir="$(dirname "$(command -v emcc)")"
  node_dir="$(dirname "$EMSDK_NODE")"
  binaryen_dir="$(dirname "$(command -v wasm-opt)")"

  cat >/etc/profile.d/emsdk.sh <<EOF
export EMSDK="${EMSDK_ROOT}"
export EMSDK_BOOTSTRAP_PYTHON="${EMSDK_BOOTSTRAP_PYTHON}"
export EMSDK_QUIET=1
export PATH="$(dirname "$EMSDK_BOOTSTRAP_PYTHON"):\$PATH"
source "\$EMSDK/emsdk_env.sh" >/dev/null
export EMCC="\$EMSDK/upstream/emscripten/emcc"
export EMXX="\$EMSDK/upstream/emscripten/em++"
export EMAR="\$EMSDK/upstream/emscripten/emar"
export EMRANLIB="\$EMSDK/upstream/emscripten/emranlib"
export EMNM="\$EMSDK/upstream/emscripten/emnm"
export EMSTRIP="\$EMSDK/upstream/emscripten/emstrip"
EOF
  chmod +x /etc/profile.d/emsdk.sh

  export EMCC="${emcc_dir}/emcc"
  export EMXX="${emcc_dir}/em++"
  export EMAR="${emcc_dir}/emar"
  export EMRANLIB="${emcc_dir}/emranlib"
  export EMNM="${emcc_dir}/emnm"
  export EMSTRIP="${emcc_dir}/emstrip"

  if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
      echo "EMSDK=${EMSDK_ROOT}"
      echo "EMSDK_BOOTSTRAP_PYTHON=${EMSDK_BOOTSTRAP_PYTHON}"
      echo "EM_CONFIG=${EM_CONFIG}"
      echo "EM_CACHE=${EM_CACHE}"
      echo "EMSDK_NODE=${EMSDK_NODE}"
      echo "EMCC=${EMCC}"
      echo "EMXX=${EMXX}"
      echo "EMAR=${EMAR}"
      echo "EMRANLIB=${EMRANLIB}"
      echo "EMNM=${EMNM}"
      echo "EMSTRIP=${EMSTRIP}"
    } >>"$GITHUB_ENV"
  fi
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    for path in "$emcc_dir" "$node_dir" "$binaryen_dir"; do
      grep -qxF "$path" "$GITHUB_PATH" 2>/dev/null || echo "$path" >>"$GITHUB_PATH"
    done
  fi
}

emscripten_toolchain_ready() {
  [[ -x "${EMSDK_ROOT}/emsdk" ]] &&
    [[ -x "${EMSDK_ROOT}/upstream/emscripten/emcc" ]] &&
    [[ -x "${EMSDK_ROOT}/upstream/emscripten/em++" ]] &&
    [[ -x "${EMSDK_ROOT}/upstream/emscripten/emar" ]] &&
    [[ -x "${EMSDK_ROOT}/upstream/emscripten/emranlib" ]] &&
    [[ -x "${EMSDK_ROOT}/upstream/emscripten/emnm" ]] &&
    [[ -x "${EMSDK_ROOT}/upstream/emscripten/emstrip" ]] &&
    rust_target_installed wasm32-unknown-emscripten
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must run as root." >&2
  exit 1
fi

select_emsdk_python

dnf install -y --setopt=install_weak_deps=False git curl xz unzip

if [[ ! -x "${EMSDK_ROOT}/emsdk" ]]; then
  rm -rf "$EMSDK_ROOT"
  git clone --depth 1 "$EMSDK_REPOSITORY" "$EMSDK_ROOT"
  git config --system --add safe.directory "$EMSDK_ROOT"
fi

if ! emscripten_toolchain_ready; then
  (
    cd "$EMSDK_ROOT"
    ./emsdk install "$EMSDK_VERSION"
    ./emsdk activate "$EMSDK_VERSION"
  )
fi

if getent group users >/dev/null 2>&1; then
  chown -R root:users "$EMSDK_ROOT"
else
  chown -R root:root "$EMSDK_ROOT"
fi
chmod -R 775 "$EMSDK_ROOT"

write_emscripten_environment

if command -v rustup >/dev/null 2>&1; then
  rust_target_installed wasm32-unknown-emscripten || rustup target add wasm32-unknown-emscripten
fi

if ! emscripten_toolchain_ready; then
  echo "Emscripten setup completed, but the wasm32-unknown-emscripten toolchain is incomplete." >&2
  exit 1
fi

"$EMCC" --version
