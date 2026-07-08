#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292

if (( BASH_VERSINFO[0] < 5 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 5+ is required." >&2
    exit 1
fi

export VALID_TYPES=("full" "video_hw" "video" "audio" "base" "debug")
export VALID_PLATFORMS=("linux" "windows" "android" "ios" "iphonesimulator" "macos")
export VALID_PLATFORM_ARCHS=("linux-x86_64" "windows-x86_64" "android-aarch64" "android-armv7a" "android-x86_64" "ios-aarch64" "iphonesimulator-aarch64" "macos-aarch64" "macos-x86_64" "appletvos-aarch64" "appletvsimulator-aarch64")
export VALID_ARCHS=("x86_64" "aarch64" "armv7a")
export VALID_LINUX=("linux-x86_64")
export VALID_WINDOWS=("windows-x86_64")
export VALID_ANDROID=("android-aarch64" "android-armv7a" "android-x86_64")
export VALID_IOS=("ios-aarch64")
export VALID_IPHONESIMULATOR=("iphonesimulator-aarch64")
export VALID_APPLETVOS=("appletvos-aarch64")
export VALID_APPLETVSIMULATOR=("appletvsimulator-aarch64")
export VALID_MACOS=("macos-aarch64" "macos-x86_64")
export VALID_APPLE=("ios-aarch64" "iphonesimulator-aarch64" "macos-aarch64" "macos-x86_64" "appletvos-aarch64" "appletvsimulator-aarch64")
export VALID_BUILDS=("ffmpeg" "kit" "bundle")
export VALID_LICENSES=("lgpl" "gpl")
export VALID_SMALL_FLAGS=("small" "")

is_supported_combo() {
  local combo="$1"
  local valid
  for valid in "${VALID_PLATFORM_ARCHS[@]}"; do
    [[ "$valid" == "$combo" ]] && return 0
  done
  return 1
}