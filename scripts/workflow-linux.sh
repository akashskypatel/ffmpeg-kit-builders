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

runner_platform="linux"
RUNNER_WORKFLOW_TARGET_PLATFORMS=$(printf "%s," "${VALID_BUILD_ON_LINUX[@]}")
RUNNER_WORKFLOW_TARGET_PLATFORMS=${RUNNER_WORKFLOW_TARGET_PLATFORMS%,}

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

set_workflow_current_step() {
  local step="$1"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "WORKFLOW_CURRENT_STEP=$step" >> "$GITHUB_ENV"
  fi
  export WORKFLOW_CURRENT_STEP="$step"
}

read_workflow_bundles() {
  local bundle_csv="${WORKFLOW_BUNDLES:-}"
  if [[ -z "$bundle_csv" ]]; then
    printf '%s\n' "full" "video_hw" "video" "audio" "base" "debug"
    return 0
  fi

  local bundle
  IFS=',' read -ra bundles <<< "$bundle_csv"
  for bundle in "${bundles[@]}"; do
    bundle="$(trim "$bundle")"
    [[ -n "$bundle" ]] && printf '%s\n' "$bundle"
  done
}

ffmpeg_pattern_for_bundle() {
  local platform="$1"
  local arch="$2"
  local bundle="$3"

  if [[ "$bundle" == "debug" ]]; then
    printf 'ffmpeg-base-%s-%s-static-debug*' "$platform" "$arch"
  else
    printf 'ffmpeg-%s-%s-%s-static*' "$bundle" "$platform" "$arch"
  fi
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

workflow_build_ffmpeg() {
  local platform="$1"
  local arch="$2"
  local combo="${platform}-${arch}"

  if [[ -z "$platform" || -z "$arch" ]]; then
    echo "build_ffmpeg: platform and arch must be provided" >&2
    return 1
  fi

  if [[ -n "${WORKFLOW_BUNDLES:-}" ]]; then
    sudo -E ./scripts/build_all.sh --platform="${combo}" --build=ffmpeg --bundle="${WORKFLOW_BUNDLES}"
  else
    sudo -E ./scripts/build_all.sh --platform="${combo}" --build=ffmpeg
  fi

  local build_dir="${GITHUB_WORKSPACE}/prebuilt/${platform}-${arch}"
  while IFS= read -r dir; do
    echo "Found ffmpeg directory: $dir"
    sudo -E ./scripts/upload-deps-release.sh "$platform" "$arch" "$(basename "$dir")" --artifact-dir "$dir"
  done < <(find "$build_dir" -type d -name "ffmpeg-*-${platform}-${arch}-*" ! -name "ffmpeg-kit-*")
}

ensure_ffmpeg_artifacts() {
  local platform="$1"
  local arch="$2"
  local bundle pattern

  if [[ "${WORKFLOW_FORCE_SELF}" == "true" ]]; then
    workflow_build_ffmpeg "$platform" "$arch"
    return
  fi

  while IFS= read -r bundle; do
    [[ -z "$bundle" ]] && continue
    pattern="$(ffmpeg_pattern_for_bundle "$platform" "$arch" "$bundle")"
    if ! sudo -E ./scripts/workflow-get-deps.sh "$platform" "$arch" "$pattern" --artifact-pattern; then
      echo "::notice::Failed to get ffmpeg artifacts matching '$pattern' for ${platform}-${arch}; building locally"
      workflow_build_ffmpeg "$platform" "$arch"
      return
    fi
  done < <(read_workflow_bundles)
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
      set_workflow_current_step "$build"
      if [[ -n "${WORKFLOW_BUILD_FROM:-}" && "$build" == "$WORKFLOW_BUILD_FROM" ]]; then
        start_building=true
        found_build_from=true
      fi
      if [[ ${start_building} == "true" ]]; then
        echo "Running $build for $combo"
        runner_args=(--host="$platform" --arch="$arch" --enable-full --gpl -y --no-bundle --skip --build-only="$build")
        [[ "${WORKFLOW_BUILD_FFMPEG}" != "true" && "${WORKFLOW_BUILD_BUNDLE}" != "true" ]] && runner_args+=(--workflow)
        sudo -E ./runner.sh "${runner_args[@]}"
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

if [[ "${WORKFLOW_BUILD_FFMPEG}" == "true" ]]; then
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

      set_workflow_current_step "build_ffmpeg"
      if ! ensure_ffmpeg_artifacts "$platform" "$arch"; then
        echo "::error::Failed to prepare ffmpeg artifacts for ${platform}-${arch}"
        exit 1
      fi
    done
  done
fi

if [[ "${WORKFLOW_BUILD_BUNDLE}" == "true" ]]; then
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

      set_workflow_current_step "build_bundle"

      if [[ "${WORKFLOW_BUILD_FFMPEG}" != "true" ]]; then
        ensure_ffmpeg_artifacts "$platform" "$arch"
      fi

      if [[ -n "${WORKFLOW_BUNDLES:-}" ]]; then
        sudo -E ./scripts/build_all.sh --platform="${combo}" --build=kit,bundle --remote --bundle="${WORKFLOW_BUNDLES}"
      else
        sudo -E ./scripts/build_all.sh --platform="${combo}" --build=kit,bundle --remote
      fi

    done
  done
fi

if [[ "$ran_any" != "true" ]]; then
  echo "::notice::No supported platform-arch combinations selected for this runner"
fi
