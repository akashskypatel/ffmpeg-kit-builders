#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,SC2086

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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

runner_platform=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runner-platform=*)
      runner_platform="${1#*=}"
      shift
      ;;
    --runner-platform)
      runner_platform="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$runner_platform" != "linux" && "$runner_platform" != "macos" ]]; then
  echo "runner_platform must be one of: linux, macos" >&2
  exit 1
fi

case "$runner_platform" in
  linux)
    RUNNER_WORKFLOW_TARGET_PLATFORMS=$(printf "%s," "${VALID_BUILD_ON_LINUX[@]}")
    runner_arch="x86_64"
    ;;
  macos)
    RUNNER_WORKFLOW_TARGET_PLATFORMS=$(printf "%s," "${VALID_BUILD_ON_MACOS[@]}")
    runner_arch="aarch64"
    ;;
esac
RUNNER_WORKFLOW_TARGET_PLATFORMS=${RUNNER_WORKFLOW_TARGET_PLATFORMS%,}
export GITHUB_REPO="${GITHUB_REPOSITORY#*/}"
export GITHUB_USERNAME="${GITHUB_REPOSITORY%%/*}"

echo "==================================="
echo "${runner_platform} Orchestrator"
echo "workflow-force-self: ${WORKFLOW_FORCE_SELF}"
echo "workflow-build-from: ${WORKFLOW_BUILD_FROM}"
echo "workflow-build-only: ${WORKFLOW_BUILD_ONLY}"
echo "workflow-target-platforms: ${WORKFLOW_TARGET_PLATFORMS}"
echo "workflow-target-archs: ${WORKFLOW_TARGET_ARCHS}"
echo "runner-workflow-target-platforms: ${RUNNER_WORKFLOW_TARGET_PLATFORMS}"
echo "workflow-bundles: ${WORKFLOW_BUNDLES}"
echo "workflow-build-ffmpeg: ${WORKFLOW_BUILD_FFMPEG}"
echo "workflow-build-bundle: ${WORKFLOW_BUILD_BUNDLE}"
echo "==================================="

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

print_workflow_progress() {
  local current_step="$1"
  local steps="$2"
  local combo="$3"
  local step_name="$4"
  local percent=$((current_step * 100 / steps))
  local bars=$((percent * 100 / 100))
  
  local bar_str=""
  for ((j = 0; j < bars; j++)); do bar_str="${bar_str}█"; done
  for ((j = bars; j < 100; j++)); do bar_str="${bar_str}░"; done

  echo "Workflow progress: ${combo}" | tee -a "$LOG_FILE"
  printf "\r\033[K\033[1;31m[%s]\033[0m %3d%% (%2d/%2d) | \033[1;36m%s\033[0m" "$bar_str" "$percent" "$current_step" "$steps" "$step_name" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
}

count_workflow_steps_to_run() {
  local start_building=true
  local count=0
  local step

  [[ -n "${WORKFLOW_BUILD_FROM:-}" ]] && start_building=false

  for step in "$@"; do
    if [[ -n "${WORKFLOW_BUILD_FROM:-}" && "$step" == "$WORKFLOW_BUILD_FROM" ]]; then
      start_building=true
    fi
    if [[ "$start_building" == "true" ]]; then
      ((++count))
    fi
  done

  printf '%s\n' "$count"
}

contains_csv_value() {
  local csv="$1"
  local needle="$2"
  local item
  local -a items=()
  IFS=',' read -ra items <<< "$csv"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

parse_build_only_steps() {
  local build_only_csv="${WORKFLOW_BUILD_ONLY:-}"
  local raw_step step
  local -a raw_build_only_steps=()

  build_only_enabled=false
  build_only_steps=()
  build_only_seen_steps=()

  if [[ -z "$build_only_csv" || "$build_only_csv" == "false" ]]; then
    return 0
  fi

  if [[ "$build_only_csv" == "true" ]]; then
    echo "::error::build_only must be a comma-separated list of build_* steps, not a boolean"
    exit 1
  fi

  IFS=',' read -ra raw_build_only_steps <<< "$build_only_csv"
  for raw_step in "${raw_build_only_steps[@]}"; do
    step="$(trim "$raw_step")"
    [[ -z "$step" ]] && continue
    if [[ "$step" != build_* ]]; then
      echo "::error::build_only entries must be build_* steps, got: $step" >&2
      exit 1
    fi
    if [[ -z "${build_only_seen_steps[$step]:-}" ]]; then
      build_only_steps+=("$step")
      build_only_seen_steps["$step"]=0
    fi
  done

  if [[ ${#build_only_steps[@]} -gt 0 ]]; then
    build_only_enabled=true
  fi
}

run_with_runner_shell() {
  if [[ "$runner_platform" == "macos" ]]; then
    sudo -E "$HOMEBREW_BASH" "$@"
  else
    sudo -E "$@"
  fi
}

set_workflow_current_step() {
  local step="$1"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "WORKFLOW_CURRENT_STEP=$step" >> "$GITHUB_ENV"
  fi
  export WORKFLOW_CURRENT_STEP="$step"
}

reset_workflow_seen_steps() {
  local seen_steps_file="${WORKFLOW_SEEN_STEPS_FILE:-${GITHUB_WORKSPACE:-${repo_root}}/workflow-seen-steps.log}"
  export WORKFLOW_SEEN_STEPS=""
  rm -f "$seen_steps_file"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "WORKFLOW_SEEN_STEPS=" >> "$GITHUB_ENV"
  fi
}

read_workflow_bundles() {
  local bundle_csv="${WORKFLOW_BUNDLES:-}"
  local bundle
  local -a bundles=()

  if [[ -z "$bundle_csv" ]]; then
    printf '%s\n' "full"
    return 0
  fi

  IFS=',' read -ra bundles <<< "$bundle_csv"
  for bundle in "${bundles[@]}"; do
    bundle="$(trim "$bundle")"
    [[ -n "$bundle" ]] && printf '%s\n' "$bundle"
  done
}

get_simulator_companion_platform() {
  local platform="$1"
  case "$platform" in
    ios) printf '%s\n' "iphonesimulator" ;;
    appletvos) printf '%s\n' "appletvsimulator" ;;
    *) return 1 ;;
  esac
}

is_simulator_platform() {
  local platform="$1"
  [[ "$platform" == "iphonesimulator" || "$platform" == "appletvsimulator" ]]
}

is_android_platform() {
  local platform="$1"
  [[ "$platform" == "android" ]]
}

cleanup_platform_batch_prebuilt_dirs() {
  local platform="$1"
  local combo arch
  local combo_csv="${bundle_platform_combo_csv[$platform]:-}"
  local -a platform_batch_combos=()

  [[ -z "$combo_csv" ]] && return 0

  IFS=',' read -ra platform_batch_combos <<< "$combo_csv"
  for combo in "${platform_batch_combos[@]}"; do
    [[ -z "$combo" ]] && continue
    arch="${combo#*-}"
    if is_android_platform "$platform"; then
      echo "::notice::Cleaning up Android prebuilt directory for $combo"
      sudo rm -rf "${GITHUB_WORKSPACE}/prebuilt/${combo}"
    else
      cleanup_combo_prebuilt_dirs "$platform" "$arch"
    fi
  done
}

cleanup_combo_libraries() {
  local platform="$1"
  local arch="$2"

  sudo rm -rf "${GITHUB_WORKSPACE}/prebuilt/${platform}-${arch}/libraries"
}

cleanup_combo_prebuilt_dirs() {
  local platform="$1"
  local arch="$2"
  local combo="${platform}-${arch}"
  local simulator_platform

  if is_simulator_platform "$platform"; then
    echo "::notice::Skipping prebuilt cleanup for simulator combo $combo until its physical device companion completes"
    return 0
  fi

  echo "::notice::Cleaning up prebuilt directory for $combo"
  sudo rm -rf "${GITHUB_WORKSPACE}/prebuilt/${combo}"

  if simulator_platform="$(get_simulator_companion_platform "$platform" 2>/dev/null)" && is_supported_combo "${simulator_platform}-${arch}"; then
    echo "::notice::Cleaning up paired simulator prebuilt directory for ${simulator_platform}-${arch}"
    sudo rm -rf "${GITHUB_WORKSPACE}/prebuilt/${simulator_platform}-${arch}"
  fi
}

validate_workflow_target_combo() {
  local platform="$1"
  local arch="$2"
  local combo="${platform}-${arch}"

  if [[ -z "$platform" || -z "$arch" ]]; then
    echo "::notice::Skipping target with missing platform or arch: platform='$platform' arch='$arch'"
    return 1
  fi

  if ! contains_csv_value "$RUNNER_WORKFLOW_TARGET_PLATFORMS" "$platform"; then
    echo "::notice::Skipping platform '$platform': this ${runner_platform} runner supports only $RUNNER_WORKFLOW_TARGET_PLATFORMS"
    return 1
  fi

  if ! is_supported_combo "$combo"; then
    echo "::notice::Skipping unsupported target $combo"
    return 1
  fi
}

build_runner_args() {
  local platform="$1"
  local arch="$2"
  local bundle
  local -a selected_bundles=()
  local omit_base=false

  runner_args=(--host="$platform" --arch="$arch" --gpl -y --no-bundle --skip --hide-banner)

  if [[ -n "${WORKFLOW_BUNDLES:-}" ]]; then
    while IFS= read -r bundle; do
      [[ -z "$bundle" ]] && continue
      selected_bundles+=("$bundle")
      case "$bundle" in
        full|video_hw|video|audio)
          omit_base=true
          ;;
      esac
    done < <(read_workflow_bundles)

    for bundle in "${selected_bundles[@]}"; do
      [[ -z "$bundle" ]] && continue
      if [[ "$omit_base" == true && ( "$bundle" == "base" || "$bundle" == "debug" ) ]]; then
        continue
      fi
      if [[ "$bundle" == "debug" ]]; then
        runner_args+=(--enable-base --enable-debug)
      else
        runner_args+=("--enable-$bundle")
      fi
    done
  else
    runner_args+=(--enable-full)
  fi
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

upload_ffmpeg_bundle_artifacts() {
  local platform="$1"
  local arch="$2"
  local bundle="$3"
  local combo="${platform}-${arch}"
  local build_dir="${GITHUB_WORKSPACE}/prebuilt/${combo}"
  local pattern
  local found_artifact=false

  pattern="$(ffmpeg_pattern_for_bundle "$platform" "$arch" "$bundle")"
  while IFS= read -r dir; do
    found_artifact=true
    echo "Found ffmpeg directory for bundle '$bundle': $dir"
    if ! run_with_runner_shell ./scripts/upload-deps-release.sh "$platform" "$arch" "$(basename "$dir")" --artifact-dir "$dir"; then
      echo "::error::Failed to upload ffmpeg artifacts for $combo bundle $bundle"
      exit 1
    fi
  done < <(find "$build_dir" -type d -name "$pattern" ! -name "ffmpeg-kit-*")

  if [[ "$found_artifact" != "true" ]]; then
    echo "::error::No ffmpeg artifacts found for $combo bundle $bundle using pattern '$pattern'"
    exit 1
  fi
}

ensure_target_toolchain() {
  local platform="$1"
  local arch="$2"
  local key="$platform"
  [[ "$runner_platform" == "macos" || "$platform" == "linux" ]] && key="${platform}-${arch}"

  if [[ -n "${installed_toolchains[$key]:-}" ]]; then
    return 0
  fi

  if [[ "$runner_platform" == "macos" ]]; then
    case "$platform" in
      ios|iphonesimulator|macos|appletvos|appletvsimulator)
        "${GITHUB_WORKSPACE}/scripts/toolchain/setup-apple-rust.sh" "$platform" "$arch"
        ;;
    esac
  else
    case "$platform" in
      windows)
        sudo -E "${GITHUB_WORKSPACE}/scripts/toolchain/setup-mingw-w64.sh"
        [[ -f /etc/profile.d/mingw-w64.sh ]] && source /etc/profile.d/mingw-w64.sh
        ;;
      android)
        sudo -E "${GITHUB_WORKSPACE}/scripts/toolchain/setup-android.sh"
        [[ -f /etc/profile.d/android-sdk.sh ]] && source /etc/profile.d/android-sdk.sh
        [[ -f /etc/profile.d/sdkman.sh ]] && source /etc/profile.d/sdkman.sh
        ;;
      linux)
        if [[ "$arch" == "aarch64" || "$arch" == "arm64" || "$arch" == "arm64-v8a" ]]; then
          sudo -E "${GITHUB_WORKSPACE}/scripts/toolchain/setup-linux-arm64.sh"
          [[ -f /etc/profile.d/linux-arm64-toolchain.sh ]] && source /etc/profile.d/linux-arm64-toolchain.sh
        fi
        ;;
    esac
  fi

  installed_toolchains["$key"]=1
}

workflow_build_ffmpeg() {
  local platform="$1"
  local arch="$2"
  local combo="${platform}-${arch}"
  local bundle

  if [[ -z "$platform" || -z "$arch" ]]; then
    echo "build_ffmpeg: platform and arch must be provided" >&2
    return 1
  fi

  while IFS= read -r bundle; do
    [[ -z "$bundle" ]] && continue
    echo "::notice::Building ffmpeg for $combo bundle $bundle"
    if ! run_with_runner_shell ./scripts/build_all.sh --platform="${combo}" --build=ffmpeg --bundle="$bundle"; then
      echo "::error::Failed to build ffmpeg for $combo bundle $bundle"
      exit 1
    fi
    upload_ffmpeg_bundle_artifacts "$platform" "$arch" "$bundle"
  done < <(read_workflow_bundles)
}

ensure_ffmpeg_artifacts() {
  local platform="$1"
  local arch="$2"
  local bundle pattern

  if [[ "${WORKFLOW_BUILD_FFMPEG}" == "true" ]]; then
    workflow_build_ffmpeg "$platform" "$arch"
    return
  fi

  while IFS= read -r bundle; do
    [[ -z "$bundle" ]] && continue
    pattern="$(ffmpeg_pattern_for_bundle "$platform" "$arch" "$bundle")"
    if ! run_with_runner_shell ./scripts/workflow-get-deps.sh "$platform" "$arch" "$pattern" --artifact-pattern; then
      echo "::notice::Failed to get ffmpeg artifacts matching '$pattern' for ${platform}-${arch}; building locally"
      workflow_build_ffmpeg "$platform" "$arch"
    fi
  done < <(read_workflow_bundles)
}

append_bundle_target_combo() {
  local platform="$1"
  local arch="$2"
  local combo="${platform}-${arch}"

  if [[ -z "${bundle_platform_seen[$platform]:-}" ]]; then
    bundle_platform_seen["$platform"]=1
    bundle_platforms+=("$platform")
  fi

  if [[ -z "${bundle_combo_seen[$combo]:-}" ]]; then
    bundle_combo_seen["$combo"]=1
    if [[ -n "${bundle_platform_combo_csv[$platform]:-}" ]]; then
      bundle_platform_combo_csv["$platform"]+=",${combo}"
    else
      bundle_platform_combo_csv["$platform"]="$combo"
    fi
  fi
}

workflow_step_build_ffmpeg() {
  local platform="$1"
  local arch="$2"
  if [[ "${WORKFLOW_BUILD_FFMPEG}" == "true" ]]; then
    echo "::notice::Building ffmpeg for selected platforms and architectures"
    validate_workflow_target_combo "$platform" "$arch" || return 1

    set_workflow_current_step "build_ffmpeg"
    if ! ensure_ffmpeg_artifacts "$platform" "$arch"; then
      echo "::error::Failed to prepare ffmpeg artifacts for ${platform}-${arch}"
      return 1
    fi
  fi
}

workflow_step_build_bundle() {
  local platform="$1"
  local arch="$2"
  local combo="${platform}-${arch}"
  if [[ "${WORKFLOW_BUILD_BUNDLE}" == "true" ]]; then
    echo "::notice::Preparing bundle build for $combo"
    validate_workflow_target_combo "$platform" "$arch" || return 1

    set_workflow_current_step "build_bundle"

    if [[ "${WORKFLOW_BUILD_FFMPEG}" != "true" ]]; then
      if ! ensure_ffmpeg_artifacts "$platform" "$arch"; then
        echo "::error::Failed to prepare ffmpeg artifacts for ${platform}-${arch}"
        return 1
      fi
    fi

    append_bundle_target_combo "$platform" "$arch"
  fi
}

workflow_step_build_bundle_batches() {
  local platform combo_csv
  local -a build_all_args

  [[ "${WORKFLOW_BUILD_BUNDLE}" == "true" ]] || return 0

  for platform in "${bundle_platforms[@]}"; do
    combo_csv="${bundle_platform_combo_csv[$platform]:-}"
    [[ -z "$combo_csv" ]] && continue

    set_workflow_current_step "build_bundle"
    if [[ "${WORKFLOW_IS_CI}" == "true" ]]; then
      build_all_args=(./scripts/build_all.sh --platform="${combo_csv}" --bundle="debug" --build="kit" --license="lgpl" --small --local)
    else
      build_all_args=(./scripts/build_all.sh --platform="${combo_csv}" --build="kit,bundle" --remote)
      if [[ -n "${WORKFLOW_BUNDLES:-}" ]]; then
        build_all_args+=(--bundle="${WORKFLOW_BUNDLES}")
      fi
    fi

    echo "::notice::Building bundle batch for $platform platforms: $combo_csv"
    if ! run_with_runner_shell "${build_all_args[@]}"; then
      echo "::error::Failed to build bundle batch for $platform platforms: $combo_csv"
      return 1
    fi

    echo "::notice::Bundle batch built successfully for $platform platforms: $combo_csv"
    cleanup_platform_batch_prebuilt_dirs "$platform"
  done
}

workflow_step_test() {
  local build_args
  build_args=(./runner.sh --host="$runner_platform" --arch="$runner_arch" --enable-base --gpl --kit --build-deps --no-bundle --test="${TEST_TYPE:-undefined}" --build-debug --skip -y)
  
  echo "::notice::Building tests"
  if ! run_with_runner_shell "${build_args[@]}"; then
    echo "::error::Failed to build tests"
    return 1
  fi

  echo "::notice::Running tests"
  local test_args
  test_args=("./FFmpegKit/build/tests/ffmpegkit_tests")
  if [[ -n "${TEST_FILTER:-}" ]]; then
    test_args+=("--gtest_filter=${TEST_FILTER}")
  fi
  if ! run_with_runner_shell "${test_args[@]}"; then
    echo "::error::Failed to run tests"
    return 1
  fi
  
  echo "::notice::Tests passed successfully"
}

declare -a build_only_steps=()
declare -A build_only_seen_steps=()
build_only_enabled=false
parse_build_only_steps

if [[ -n "${WORKFLOW_BUILD_FROM:-}" && "$build_only_enabled" == "true" ]]; then
  echo "::error::WORKFLOW_BUILD_ONLY and WORKFLOW_BUILD_FROM cannot both be defined" >&2
  exit 1
fi

if [[ -n "${WORKFLOW_BUILD_FROM:-}" ]]; then
  if [[ "$WORKFLOW_BUILD_FROM" != build_* ]]; then
    echo "::notice::build_from must be a build_* step, got: $WORKFLOW_BUILD_FROM" >&2
    exit 1
  fi
fi

if [[ ( "${WORKFLOW_BUILD_FFMPEG}" == "true" || "${WORKFLOW_BUILD_BUNDLE}" == "true" ) && ( -n "${WORKFLOW_BUILD_FROM:-}" || "$build_only_enabled" == "true" ) ]]; then
  echo "::error::WORKFLOW_BUILD_FFMPEG/WORKFLOW_BUILD_BUNDLE cannot be combined with WORKFLOW_BUILD_FROM or WORKFLOW_BUILD_ONLY" >&2
  exit 1
fi

workflow_mode="default"
if [[ "$build_only_enabled" == "true" ]]; then
  workflow_mode="build_only"
elif [[ -n "${WORKFLOW_BUILD_FROM:-}" ]]; then
  workflow_mode="build_from"
elif [[ "${WORKFLOW_BUILD_FFMPEG}" == "true" || "${WORKFLOW_BUILD_BUNDLE}" == "true" ]]; then
  workflow_mode="ffmpeg_bundle"
fi

IFS=',' read -ra selected_platforms <<< "$WORKFLOW_TARGET_PLATFORMS"
IFS=',' read -ra selected_archs <<< "$WORKFLOW_TARGET_ARCHS"
ran_any=false
declare -A installed_toolchains=()
declare -A workflow_target_combo_seen=()
declare -a workflow_target_combos=()
declare -A bundle_platform_seen=()
declare -A bundle_combo_seen=()
declare -A bundle_platform_combo_csv=()
declare -a bundle_platforms=()

append_workflow_target_combo() {
  local platform="$1"
  local arch="$2"
  local combo="${platform}-${arch}"

  if ! validate_workflow_target_combo "$platform" "$arch"; then
    return 0
  fi

  if [[ -z "${workflow_target_combo_seen[$combo]:-}" ]]; then
    workflow_target_combo_seen["$combo"]=1
    workflow_target_combos+=("$combo")
  fi
}

echo "::notice::Workflow mode: $workflow_mode"
echo "::notice::Starting workflow for platforms: $WORKFLOW_TARGET_PLATFORMS and architectures: $WORKFLOW_TARGET_ARCHS"
for raw_platform in "${selected_platforms[@]}"; do
  platform="$(trim "$raw_platform")"
  [[ -z "$platform" ]] && continue

  for raw_arch in "${selected_archs[@]}"; do
    arch="$(trim "$raw_arch")"
    [[ -z "$arch" ]] && continue
    if companion_platform="$(get_simulator_companion_platform "$platform" 2>/dev/null)"; then
      append_workflow_target_combo "$companion_platform" "$arch"
    fi
    append_workflow_target_combo "$platform" "$arch"
  done
done

for combo in "${workflow_target_combos[@]}"; do
    platform="${combo%-*}"
    arch="${combo#*-}"
    workflow_step_number=0
    workflow_step_total=0
    ran_any=true
    ensure_target_toolchain "$platform" "$arch"
    echo "Preparing build steps for $combo"
    runner_args=()
    build_runner_args "$platform" "$arch"

    if [[ "$workflow_mode" == "build_only" ]]; then
      WORKFLOW_BUILD_STEPS="${build_only_steps[*]}"
    else
      steps_cmd="./runner.sh ${runner_args[*]} --hide-banner --print-all-steps"
      echo "Running: $steps_cmd"
      WORKFLOW_BUILD_STEPS="$(run_with_runner_shell $steps_cmd | awk -F= '/^WORKFLOW_BUILD_STEPS=/{print $2}')"
    fi
    echo "WORKFLOW_BUILD_STEPS for $combo: $WORKFLOW_BUILD_STEPS"
    read -ra workflow_build_steps <<< "$WORKFLOW_BUILD_STEPS"
    workflow_step_total="$(count_workflow_steps_to_run "${workflow_build_steps[@]}")"
    echo "::notice::High-level build plan for $combo: $workflow_step_total step(s) to run from WORKFLOW_BUILD_STEPS"

    start_building=true
    found_build_from=false
    [[ -n "${WORKFLOW_BUILD_FROM:-}" ]] && start_building=false

    for build in "${workflow_build_steps[@]}"; do
      set_workflow_current_step "$build"
      if [[ -n "${WORKFLOW_BUILD_FROM:-}" && "$build" == "$WORKFLOW_BUILD_FROM" ]]; then
        start_building=true
        found_build_from=true
      fi
      if [[ ${start_building} == "true" ]]; then
        ((++workflow_step_number))
        print_workflow_progress "$workflow_step_number" "$workflow_step_total" "$combo" "$build"
        echo "Running $build for $combo"
        step_runner_args=("${runner_args[@]}" --build-only="$build")
        [[ "$workflow_mode" != "ffmpeg_bundle" ]] && step_runner_args+=(--upload-deps)
        if ! run_with_runner_shell ./runner.sh "${step_runner_args[@]}"; then
          echo "::error::Failed to run $build for $combo"
          exit 1
        fi
        if [[ "$workflow_mode" != "ffmpeg_bundle" ]]; then
          cleanup_combo_libraries "$platform" "$arch"
          reset_workflow_seen_steps
        fi
        sudo rm -rf "${GITHUB_WORKSPACE}/prebuilt/src"
      fi
    done

    if [[ -n "${WORKFLOW_BUILD_FROM:-}" && "$found_build_from" != "true" ]]; then
      echo "::notice::build_from step not found in workflow build steps for $combo: $WORKFLOW_BUILD_FROM" >&2
      exit 1
    fi

    if ! workflow_step_build_ffmpeg "$platform" "$arch"; then
      echo "::error::Failed to build ffmpeg for $combo"
      exit 1
    fi

    if [[ "${WORKFLOW_BUILD_FFMPEG}" == "true" && "${WORKFLOW_BUILD_BUNDLE}" != "true" ]]; then
      echo "::notice::ffmpeg built successfully for $combo and no bundle build was requested"
      cleanup_combo_prebuilt_dirs "$platform" "$arch"
      continue
    fi

    if [[ "${WORKFLOW_BUILD_BUNDLE}" == "true" ]]; then
      if ! workflow_step_build_bundle "$platform" "$arch"; then
        echo "::error::Failed to prepare bundle build for $combo"
        exit 1
      fi
    fi
done

if ! workflow_step_build_bundle_batches; then
  exit 1
fi

if [[ "${RUN_TESTS}" == "true" ]]; then
  rm -f "workflow-seen-steps.log"
  if ! workflow_step_test; then
    echo "::error::Failed to run tests"
    exit 1
  fi
fi

if [[ "$ran_any" != "true" ]]; then
  echo "::notice::No supported platform-arch combinations selected for this runner"
fi
