#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292

if (( BASH_VERSINFO[0] < 4 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 4+ is required." >&2
    exit 1
fi

: "${LOG_FILE:=/dev/null}"

export VALID_BUNDLES=("full" "video_hw" "video" "audio" "base" "debug")
export VALID_BUILD_ON_LINUX=("linux" "windows" "android" "wasm")
export VALID_BUILD_ON_MACOS=("ios" "iphonesimulator" "appletvos" "appletvsimulator" "macos")
export VALID_ARCHS=("x86_64" "aarch64" "armv7a" "wasm32")
export VALID_LINUX_ARCHS=("x86_64") # "aarch64" not functional yet
export VALID_WASM_ARCHS=("wasm32")
export VALID_WINDOWS_ARCHS=("x86_64")
export VALID_ANDROID_ARCHS=("aarch64" "armv7a" "x86_64")
export VALID_IOS_ARCHS=("aarch64")
export VALID_IPHONESIMULATOR_ARCHS=("aarch64")
export VALID_APPLETVOS_ARCHS=("aarch64")
export VALID_APPLETVSIMULATOR_ARCHS=("aarch64")
export VALID_MACOS_ARCHS=("aarch64" "x86_64")
export VALID_BUILDS=("ffmpeg" "kit" "bundle")
export VALID_LICENSES=("lgpl" "gpl")
export VALID_SMALL_FLAGS=("small" "")

# combine platform and arch into single array
mapfile -t VALID_LINUX < <(for arch in "${VALID_LINUX_ARCHS[@]}"; do echo "linux-${arch}"; done)
mapfile -t VALID_WINDOWS < <(for arch in "${VALID_WINDOWS_ARCHS[@]}"; do echo "windows-${arch}"; done)
mapfile -t VALID_ANDROID < <(for arch in "${VALID_ANDROID_ARCHS[@]}"; do echo "android-${arch}"; done)
mapfile -t VALID_IOS < <(for arch in "${VALID_IOS_ARCHS[@]}"; do echo "ios-${arch}"; done)
mapfile -t VALID_IPHONESIMULATOR < <(for arch in "${VALID_IPHONESIMULATOR_ARCHS[@]}"; do echo "iphonesimulator-${arch}"; done)
mapfile -t VALID_APPLETVOS < <(for arch in "${VALID_APPLETVOS_ARCHS[@]}"; do echo "appletvos-${arch}"; done)
mapfile -t VALID_APPLETVSIMULATOR < <(for arch in "${VALID_APPLETVSIMULATOR_ARCHS[@]}"; do echo "appletvsimulator-${arch}"; done)
mapfile -t VALID_MACOS < <(for arch in "${VALID_MACOS_ARCHS[@]}"; do echo "macos-${arch}"; done)
mapfile -t VALID_WASM < <(for arch in "${VALID_WASM_ARCHS[@]}"; do echo "wasm-${arch}"; done)

VALID_PLATFORMS=(
  "${VALID_BUILD_ON_LINUX[@]}"
  "${VALID_BUILD_ON_MACOS[@]}"
)

# combine VALID_IOS, VALID_IPHONESIMULATOR, VALID_APPLETVOS, VALID_APPLETVSIMULATOR, VALID_MACOS into VALID_APPLE
VALID_APPLE=(
  "${VALID_IOS[@]}"
  "${VALID_IPHONESIMULATOR[@]}"
  "${VALID_APPLETVOS[@]}"
  "${VALID_APPLETVSIMULATOR[@]}"
  "${VALID_MACOS[@]}"
)

# combine all platform/arch combinations
VALID_PLATFORM_ARCHS=(
  "${VALID_LINUX[@]}"
  "${VALID_WINDOWS[@]}"
  "${VALID_ANDROID[@]}"
  "${VALID_APPLE[@]}"
  "${VALID_WASM[@]}"
)

is_supported_combo() {
  local combo="$1"
  local valid
  for valid in "${VALID_PLATFORM_ARCHS[@]}"; do
    [[ "$valid" == "$combo" ]] && return 0
  done
  return 1
}
