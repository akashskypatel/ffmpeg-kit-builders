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

set -euo pipefail

source "${GITHUB_WORKSPACE}/scripts/supported.sh"

echo "==================================="
echo "Linux Orchestrator"
echo "workflow-force-self: ${WORKFLOW_FORCE_SELF}"
echo "workflow-build-from: ${WORKFLOW_BUILD_FROM}"
echo "workflow-build-only: ${WORKFLOW_BUILD_ONLY}"
echo "workflow-target-platforms: ${WORKFLOW_TARGET_PLATFORMS}"
echo "workflow-target-archs: ${WORKFLOW_TARGET_ARCHS}"
echo "runner-workflow-target-platforms: ${RUNNER_WORKFLOW_TARGET_PLATFORMS}"
echo "workflow-build-ffmpeg: ${WORKFLOW_BUILD_FFMPEG}"
echo "workflow-build-bundle: ${WORKFLOW_BUILD_BUNDLE}"
echo "==================================="

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

contains_csv_value() {
  local csv="$1"
  local needle="$2"
  local item
  IFS=',' read -ra items <<< "$csv"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

ensure_target_toolchain() {
  local platform="$1"
  local arch="$2"
  local key="$platform"
  [[ "$platform" == "linux" ]] && key="${platform}-${arch}"

  if [[ -n "${installed_toolchains[$key]:-}" ]]; then
    return 0
  fi

  case "$platform" in
    windows)
      sudo -E "${GITHUB_WORKSPACE}/scripts/toolchain/setup-mingw-w64.sh"
      # shellcheck source=/dev/null
      [[ -f /etc/profile.d/mingw-w64.sh ]] && source /etc/profile.d/mingw-w64.sh
      ;;
    android)
      sudo -E "${GITHUB_WORKSPACE}/scripts/toolchain/setup-android.sh"
      # shellcheck source=/dev/null
      [[ -f /etc/profile.d/android-sdk.sh ]] && source /etc/profile.d/android-sdk.sh
      # shellcheck source=/dev/null
      [[ -f /etc/profile.d/sdkman.sh ]] && source /etc/profile.d/sdkman.sh
      ;;
    linux)
      if [[ "$arch" == "aarch64" || "$arch" == "arm64" || "$arch" == "arm64-v8a" ]]; then
        sudo -E "${GITHUB_WORKSPACE}/scripts/toolchain/setup-linux-arm64.sh"
        # shellcheck source=/dev/null
        [[ -f /etc/profile.d/linux-arm64-toolchain.sh ]] && source /etc/profile.d/linux-arm64-toolchain.sh
      fi
      ;;
  esac
  installed_toolchains["$key"]=1
}

if [[ -n "${WORKFLOW_BUILD_FROM:-}" ]]; then
  if [[ "$WORKFLOW_BUILD_FROM" != build_* ]]; then
    echo "build_from must be a build_* step, got: $WORKFLOW_BUILD_FROM" >&2
    exit 1
  fi
fi

IFS=',' read -ra selected_platforms <<< "$WORKFLOW_TARGET_PLATFORMS"
IFS=',' read -ra selected_archs <<< "$WORKFLOW_TARGET_ARCHS"
ran_any=false
declare -A installed_toolchains=()

for raw_platform in "${selected_platforms[@]}"; do
  platform="$(trim "$raw_platform")"
  [[ -z "$platform" ]] && continue

  if ! contains_csv_value "$RUNNER_WORKFLOW_TARGET_PLATFORMS" "$platform"; then
    echo "::notice::Skipping platform '$platform': this ${runner_platform} runner supports only $RUNNER_WORKFLOW_TARGET_PLATFORMS"
    continue
  fi

  for raw_arch in "${selected_archs[@]}"; do
    arch="$(trim "$raw_arch")"
    [[ -z "$arch" ]] && continue
    combo="${platform}-${arch}"

    if ! is_supported_combo "$combo"; then
      echo "::notice::Skipping unsupported target $combo"
      continue
    fi

    ran_any=true
    ensure_target_toolchain "$platform" "$arch"
    echo "Preparing build steps for $combo"
    WORKFLOW_BUILD_STEPS="$(sudo -E ./runner.sh --host="$platform" --arch="$arch" --enable-full --gpl -y --no-bundle --skip --print-all-steps | awk -F= '/^WORKFLOW_BUILD_STEPS=/{print $2}')"
    echo "WORKFLOW_BUILD_STEPS for $combo: $WORKFLOW_BUILD_STEPS"

    start_building=true
    found_build_from=false
    [[ -n "${WORKFLOW_BUILD_FROM:-}" ]] && start_building=false

    for build in $WORKFLOW_BUILD_STEPS; do
      WORKFLOW_CURRENT_STEP="$build"
      if [[ -n "${WORKFLOW_BUILD_FROM:-}" && "$build" == "$WORKFLOW_BUILD_FROM" ]]; then
        start_building=true
        found_build_from=true
      fi
      if [[ ${start_building} == "true" ]]; then
        echo "Running $build for $combo"
        sudo -E ./runner.sh --host="$platform" --arch="$arch" --enable-full --gpl -y --no-bundle --skip --workflow --build-only="$build"
        if [[ "${WORKFLOW_BUILD_FFMPEG}" != "true" && "${WORKFLOW_BUILD_BUNDLE}" != "true" ]]; then
          sudo rm -rf "${GITHUB_WORKSPACE}/prebuilt/${platform}-${arch}/libraries"
        fi
        sudo rm -rf "${GITHUB_WORKSPACE}/prebuilt/src"
        if [[ "${WORKFLOW_BUILD_ONLY}" == "true" ]]; then
          start_building=false
        fi
      fi
    done

    if [[ -n "${WORKFLOW_BUILD_FROM:-}" && "$found_build_from" != "true" ]]; then
      echo "build_from step not found in workflow build steps for $combo: $WORKFLOW_BUILD_FROM" >&2
      exit 1
    fi
  done
done

if [[ "$ran_any" != "true" ]]; then
  echo "::notice::No supported platform-arch combinations selected for this runner"
fi