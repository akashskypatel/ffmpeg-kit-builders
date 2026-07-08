#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

if (( BASH_VERSINFO[0] < 5 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 5+ is required." >&2
    exit 1
fi
set -euo pipefail

FLUTTER_ROOT="${FLUTTER_ROOT:-/usr/local/flutter}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"

write_flutter_environment() {
  cat >/etc/profile.d/flutter.sh <<EOF
export PATH="${FLUTTER_ROOT}/bin:\$PATH"
EOF
  chmod +x /etc/profile.d/flutter.sh

  export PATH="${FLUTTER_ROOT}/bin:$PATH"

  if [[ -n "${GITHUB_PATH:-}" ]]; then
    grep -qxF "${FLUTTER_ROOT}/bin" "$GITHUB_PATH" 2>/dev/null || echo "${FLUTTER_ROOT}/bin" >>"$GITHUB_PATH"
  fi
}

flutter_toolchain_ready() {
  [[ -x "${FLUTTER_ROOT}/bin/flutter" ]] &&
    [[ -x "${FLUTTER_ROOT}/bin/dart" ]] &&
    [[ -f "${FLUTTER_ROOT}/bin/cache/flutter_tools.snapshot" ]]
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must run as root." >&2
  exit 1
fi

if flutter_toolchain_ready; then
  write_flutter_environment
  echo "Flutter toolchain is already available at ${FLUTTER_ROOT}; skipping setup."
  "$FLUTTER_ROOT/bin/flutter" --version
  exit 0
fi

dnf install -y --setopt=install_weak_deps=False git curl xz unzip

if [[ ! -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
  rm -rf "$FLUTTER_ROOT"
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_CHANNEL" "$FLUTTER_ROOT"
  git config --system --add safe.directory "$FLUTTER_ROOT"
fi

chown -R vscode:vscode "$FLUTTER_ROOT" 2>/dev/null || true
write_flutter_environment

if id vscode >/dev/null 2>&1; then
  sudo -E -u vscode "$FLUTTER_ROOT/bin/flutter" config --no-analytics
  sudo -E -u vscode "$FLUTTER_ROOT/bin/flutter" precache
else
  "$FLUTTER_ROOT/bin/flutter" config --no-analytics
  "$FLUTTER_ROOT/bin/flutter" precache
fi

"$FLUTTER_ROOT/bin/flutter" --version
