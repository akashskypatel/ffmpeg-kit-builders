#!/usr/bin/env bash
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-/usr/local/android-sdk}"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-29.0.14206865}"
ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION}}"
ANDROID_CMDLINE_TOOLS_URL="${ANDROID_CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip}"
SDKMAN_DIR="${SDKMAN_DIR:-/usr/local/sdkman}"

android_toolchain_bin() {
  printf '%s/toolchains/llvm/prebuilt/linux-x86_64/bin' "$ANDROID_NDK_ROOT"
}

rust_target_installed() {
  local target="$1"
  ! command -v rustup >/dev/null 2>&1 || rustup target list --installed 2>/dev/null | grep -qx "$target"
}

android_rust_targets_installed() {
  rust_target_installed x86_64-linux-android &&
    rust_target_installed i686-linux-android &&
    rust_target_installed aarch64-linux-android &&
    rust_target_installed armv7-linux-androideabi
}

write_android_environment() {
  local toolchain_bin
  toolchain_bin="$(android_toolchain_bin)"

  export ANDROID_HOME
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export ANDROID_NDK_VERSION
  export ANDROID_NDK_ROOT
  export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"
  export NDK_HOME="$ANDROID_NDK_ROOT"
  export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${toolchain_bin}:${PATH}"

  if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
      echo "ANDROID_HOME=${ANDROID_HOME}"
      echo "ANDROID_SDK_ROOT=${ANDROID_HOME}"
      echo "ANDROID_NDK_VERSION=${ANDROID_NDK_VERSION}"
      echo "ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT}"
      echo "ANDROID_NDK_HOME=${ANDROID_NDK_ROOT}"
      echo "NDK_HOME=${ANDROID_NDK_ROOT}"
    } >>"$GITHUB_ENV"
  fi
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    grep -qxF "${ANDROID_HOME}/cmdline-tools/latest/bin" "$GITHUB_PATH" 2>/dev/null || echo "${ANDROID_HOME}/cmdline-tools/latest/bin" >>"$GITHUB_PATH"
    grep -qxF "${ANDROID_HOME}/platform-tools" "$GITHUB_PATH" 2>/dev/null || echo "${ANDROID_HOME}/platform-tools" >>"$GITHUB_PATH"
    grep -qxF "$toolchain_bin" "$GITHUB_PATH" 2>/dev/null || echo "$toolchain_bin" >>"$GITHUB_PATH"
  fi

  cat >/etc/profile.d/android-sdk.sh <<EOF
export ANDROID_HOME="${ANDROID_HOME}"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
export ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT}"
export ANDROID_NDK_HOME="${ANDROID_NDK_ROOT}"
export NDK_HOME="${ANDROID_NDK_ROOT}"
export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${toolchain_bin}:\$PATH"
EOF
  chmod +x /etc/profile.d/android-sdk.sh
}

write_sdkman_environment() {
  cat >/etc/profile.d/sdkman.sh <<EOF
export SDKMAN_DIR="${SDKMAN_DIR}"
source "\${SDKMAN_DIR}/bin/sdkman-init.sh"
export PATH="\${SDKMAN_DIR}/candidates/gradle/current/bin:\$PATH"
EOF
  chmod +x /etc/profile.d/sdkman.sh
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    grep -qxF "SDKMAN_DIR=${SDKMAN_DIR}" "$GITHUB_ENV" 2>/dev/null || echo "SDKMAN_DIR=${SDKMAN_DIR}" >>"$GITHUB_ENV"
  fi
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    grep -qxF "${SDKMAN_DIR}/candidates/gradle/current/bin" "$GITHUB_PATH" 2>/dev/null || echo "${SDKMAN_DIR}/candidates/gradle/current/bin" >>"$GITHUB_PATH"
  fi
}

android_toolchain_ready() {
  local toolchain_bin
  toolchain_bin="$(android_toolchain_bin)"

  [[ -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]] &&
    [[ -x "${ANDROID_HOME}/platform-tools/adb" ]] &&
    [[ -d "${ANDROID_HOME}/platforms/android-34" ]] &&
    [[ -x "${ANDROID_HOME}/build-tools/34.0.0/aapt" ]] &&
    [[ -x "${toolchain_bin}/x86_64-linux-android26-clang" ]] &&
    [[ -x "${toolchain_bin}/aarch64-linux-android26-clang" ]] &&
    [[ -x "${toolchain_bin}/armv7a-linux-androideabi26-clang" ]] &&
    [[ -x "${toolchain_bin}/x86_64-linux-android-gcc" ]] &&
    [[ -x "${toolchain_bin}/aarch64-linux-android-gcc" ]] &&
    [[ -x "${toolchain_bin}/armv7a-linux-androideabi-gcc" ]] &&
    [[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]] &&
    [[ -x "${SDKMAN_DIR}/candidates/gradle/current/bin/gradle" ]] &&
    android_rust_targets_installed
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must run as root." >&2
  exit 1
fi

if android_toolchain_ready; then
  write_android_environment
  write_sdkman_environment
  echo "Android SDK/NDK toolchain is already available at ${ANDROID_HOME}; skipping setup."
  "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --version
  exit 0
fi

dnf install -y --setopt=install_weak_deps=False curl unzip zip java-17-openjdk-devel

mkdir -p "${ANDROID_HOME}/cmdline-tools"
if [[ ! -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]]; then
  tmp_zip="$(mktemp)"
  curl -L "$ANDROID_CMDLINE_TOOLS_URL" -o "$tmp_zip"
  unzip -q "$tmp_zip" -d "${ANDROID_HOME}/cmdline-tools"
  rm -f "$tmp_zip"
  rm -rf "${ANDROID_HOME}/cmdline-tools/latest"
  mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
fi

write_android_environment

yes | sdkmanager --licenses >/dev/null || true
sdkmanager \
  "platform-tools" \
  "platforms;android-34" \
  "build-tools;34.0.0" \
  "ndk;${ANDROID_NDK_VERSION}"

ln -sfn "$ANDROID_NDK_ROOT" "${ANDROID_HOME}/ndk-bundle"
toolchain_bin="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin"
ln -sf "${toolchain_bin}/x86_64-linux-android26-clang" "${toolchain_bin}/x86_64-linux-android-gcc"
ln -sf "${toolchain_bin}/x86_64-linux-android26-clang++" "${toolchain_bin}/x86_64-linux-android-g++"
ln -sf "${toolchain_bin}/aarch64-linux-android26-clang" "${toolchain_bin}/aarch64-linux-android-gcc"
ln -sf "${toolchain_bin}/aarch64-linux-android26-clang++" "${toolchain_bin}/aarch64-linux-android-g++"
ln -sf "${toolchain_bin}/armv7a-linux-androideabi26-clang" "${toolchain_bin}/armv7a-linux-androideabi-gcc"
ln -sf "${toolchain_bin}/armv7a-linux-androideabi26-clang++" "${toolchain_bin}/armv7a-linux-androideabi-g++"

write_android_environment

if [[ ! -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]]; then
  export SDKMAN_DIR
  curl -s "https://get.sdkman.io" | bash
fi

# shellcheck source=/dev/null
source "${SDKMAN_DIR}/bin/sdkman-init.sh"
sdk install gradle || true
sdk flush archives || true
sdk flush temp || true
write_sdkman_environment

if command -v rustup >/dev/null 2>&1; then
  android_rust_targets_installed || rustup target add x86_64-linux-android i686-linux-android aarch64-linux-android armv7-linux-androideabi
fi

chown -R vscode:vscode "$ANDROID_HOME" 2>/dev/null || true
sdkmanager --version
