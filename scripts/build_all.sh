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

# save start time
START_TIME=$(date +%s)

set -e

# Update sudo timestamp to avoid interruption later
echo "Requesting administrative privileges..."
sudo -v

export BASEDIR="${BASEDIR:-${PWD}}"
export LOG_FILE="${BASEDIR}/build.log"

# State management configuration
WORK_DIR="${WORK_DIR:-${PWD}}"
STATE_DIR="${STATE_DIR:-${WORK_DIR}/.ffmpeg-kit-build-state}"
STATE_FILE="${STATE_DIR}/build_all.state"
LOCK_FILE="${STATE_DIR}/build_all.lock"

source "${BASEDIR}/scripts/function.sh"
source "${BASEDIR}/scripts/supported.sh"

[[ -f "$LOG_FILE" ]] && rm -f "$LOG_FILE"
[[ -f "$LOG_FILE" ]] && chmod -R a+rwx "$LOG_FILE" || true;

# Initialize state directory
mkdir -p "${STATE_DIR}"

# Cleanup function for lock file
cleanup() {
  rm -f "${LOCK_FILE}"
}
trap cleanup EXIT

# Check for existing lock
if [[ -f "${LOCK_FILE}" ]]; then
  echo "Error: Another build process is running (lock file exists: ${LOCK_FILE})"
  echo "If you're sure no other build is running, remove the lock file manually."
  exit 1
fi

# Create lock file
touch "${LOCK_FILE}"

# Keep the timestamp alive in the background for long-running builds
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Parse arguments
p_args=""
deps=""
bundles=""
reset_state=false
# VALID_BUNDLES=("full" "video_hw" "video" "audio" "base" "debug")
# VALID_PLATFORMS=("linux" "windows" "android" "ios" "iphonesimulator" "macos")
# VALID_PLATFORM_ARCHS=("linux-x86_64" "windows-x86_64" "android-aarch64" "android-armv7a" "android-x86_64" "ios-aarch64" "iphonesimulator-aarch64" "macos-aarch64" "macos-x86_64")
# VALID_BUILDS=("ffmpeg" "kit" "bundle")
# VALID_LICENSES=("lgpl" "gpl")
# VALID_SMALL_FLAGS=("small" "")
SMALL_FLAGS=("small" "")
ANDROID_PLATFORM_ARCHS=()
APPLE_PLATFORM_ARCHS=()
BUILD_ARRAY=()
build_aars=false
declare -A PLATFORMS
build_ffmpeg=false
build_kit=false
build_bundle=false
no_clean=true
REMOTE_RELEASE=false
build_commands=""

# Check if value is truthy
# Returns 0 (success) for truthy values, 1 (failure) for falsey values
truthy() {
  local value="$1"
  case "${value,,}" in
    true|1|T|t|True|TRUE|y|Y|yes|Yes|YES|on|On|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# Check if value is falsey  
# Returns 0 (success) for falsey values, 1 (failure) for truthy values
falsey() {
  local value="$1"
  case "${value,,}" in
    false|0|F|f|False|FALSE|n|N|no|No|NO|off|Off|OFF) return 0 ;;
    *) return 1 ;;
  esac
}

# Add a single platform-arch entry to PLATFORMS, skipping duplicates
_add_platform_arch() {
  local key="${1}" value="${2}"
  if [[ -z "${PLATFORMS["$key"]}" ]]; then
    PLATFORMS["$key"]="${value}"
  elif [[ ",${PLATFORMS["$key"]}," != *",${value},"* ]]; then
    PLATFORMS["$key"]="${PLATFORMS["$key"]},${value}"
  fi
}

parse_platforms() {
  p_args="${1}"
  # Ensure p_args is populated if empty
  if [[ -z "${p_args}" ]]; then
    p_args=$(IFS=,; echo "${VALID_PLATFORM_ARCHS[*]}")
  fi
  IFS=',' read -ra P_ARRAY <<< "$p_args"
  for p in "${P_ARRAY[@]}"; do
    # Skip empty elements resulting from trailing/double commas
    [[ -z "$p" ]] && continue

    # Check if it's a plain platform name — expand to all valid archs for that platform
    local is_platform=false
    for valid_plat in "${VALID_PLATFORMS[@]}"; do
      if [[ "$p" == "$valid_plat" ]]; then
        is_platform=true
        for valid_pa in "${VALID_PLATFORM_ARCHS[@]}"; do
          if [[ "${valid_pa}" == "${p}-"* ]]; then
            _add_platform_arch "${valid_pa%-*}" "${valid_pa#*-}"
          fi
        done
        break
      fi
    done
    [[ "$is_platform" == true ]] && continue

    # Validate as a platform-arch combination
    local valid=false
    for valid_p in "${VALID_PLATFORM_ARCHS[@]}"; do
      [[ "$p" == "$valid_p" ]] && valid=true && break
    done
    if [[ "$valid" == false ]]; then
      echo "Error: Invalid platform or platform-arch: ${p}"
      echo "Use --help for usage information"
      exit 1
    fi
    _add_platform_arch "${p%-*}" "${p#*-}"
  done
}

parse_bundles() {
  local b_arr="${1}"
  # Ensure bundles is populated if empty
  if [[ -z "${b_arr}" ]]; then
    b_arr=$(IFS=,; echo "${VALID_BUNDLES[*]}")
  fi
  # Use IFS local to the read command
  bundles="$b_arr"
  IFS=',' read -ra BUNDLE_ARRAY <<< "${b_arr}"
  for b in "${BUNDLE_ARRAY[@]}"; do
    # Skip empty elements resulting from trailing/double commas
    [[ -z "$b" ]] && continue
    # Validate against whitelist
    local valid=false
    for valid_b in "${VALID_BUNDLES[@]}"; do
      [[ "$b" == "$valid_b" ]] && valid=true && break
    done
    if [[ "$valid" == false ]]; then
      echo "Error: Invalid bundle type: ${b}"
      echo "Use --help for usage information"
      exit 1
    fi
  done
}

parse_licenses() {
  licenses="${1}"
  # Ensure licenses is populated if empty
  if [[ -z "${licenses}" ]]; then
    licenses=$(IFS=,; echo "${VALID_LICENSES[*]}")
  fi
  
  IFS=',' read -ra LICENSE_ARRAY <<< "${licenses}"
  for l in "${LICENSE_ARRAY[@]}"; do
    # Skip empty elements resulting from trailing/double commas
    [[ -z "$l" ]] && continue
    
    # Validate against whitelist
    local valid=false
    for valid_l in "${VALID_LICENSES[@]}"; do
      [[ "$l" == "$valid_l" ]] && valid=true && break
    done
    if [[ "$valid" == false ]]; then
      echo "Error: Invalid license: ${l}"
      echo "Use --help for usage information"
      exit 1
    fi
  done
}

parse_builds() {
  local b_arr="${1}"
  # Ensure builds is populated if empty
  if [[ -z "${b_arr}" ]]; then
    b_arr=$(IFS=,; echo "${VALID_BUILDS[*]}")
  fi
  # Use IFS local to the read command
  builds="$b_arr"
  IFS=',' read -ra BUILD_ARRAY <<< "${b_arr}"
  for b in "${BUILD_ARRAY[@]}"; do
    # Skip empty elements resulting from trailing/double commas
    [[ -z "$b" ]] && continue
    # Validate against whitelist
    local valid=false
    for valid_b in "${VALID_BUILDS[@]}"; do
      if [[ "$b" == "$valid_b" ]]; then
        valid=true
        if [[ "$b" == "ffmpeg" ]]; then
            build_ffmpeg=true
            build_commands+=" --ffmpeg"
        elif [[ "$b" == "kit" ]]; then
            build_kit=true
            build_commands+=" --kit"
        elif [[ "$b" == "bundle" ]]; then
            build_bundle=true
        fi
        break
      fi
    done
    if [[ "$valid" == false ]]; then
      echo "Error: Invalid build type: ${b}"
      echo "Use --help for usage information"
      exit 1
    fi
  done
}

for arg; do
  case "${arg}" in
    --platform=*)
     # input format: platform-arch ex: linux-x86_64 or android-aarch64. Comma separated (without spaces) list of platforms.
     # output format: platform ex: linux or android
     p_args="${arg#*=}"
     parse_platforms "${p_args}"
     shift;;
    --license=*)
      parse_licenses "${arg#*=}"
      shift;;
    --deps)
      deps="--deps"
      shift;;
    --reset)
      reset_state=true
      shift;;
    --help)
      echo "Usage: $0 [--platform=<platform>|<platform-arch>,...] [--deps] [--reset] [--bundles=*] [--help]"
      echo ""
      echo "Options:"
      echo "  --platform=*  Comma separated (without spaces) list of platforms or platform-arch pairs."
      echo "                A plain platform name expands to all valid archs for that platform."
      echo "                  e.g. --platform=android              → android-aarch64,android-armv7a,android-x86_64"
      echo "                  e.g. --platform=android,linux-x86_64 → android (all archs) + linux-x86_64"
      echo "                Valid platforms (expands to all archs): ${VALID_PLATFORMS[*]}"
      echo "                Valid platform-arch combinations:       ${VALID_PLATFORM_ARCHS[*]}"
      echo "  --deps        Build dependencies first"
      echo "  --reset       Reset build state and start from beginning"
      echo "  --bundle=*    Comma separated (without spaces) list of bundles to build (e.g. --bundle=debug,full,base,audio,video,video_hw)"
      echo "                Valid bundles: ${VALID_BUNDLES[*]}"
      echo "  --build=*     Comma separated (without spaces) list of builds to build (e.g. --build=ffmpeg,kit,bundle)"
      echo "                Valid builds: ${VALID_BUILDS[*]}"
      echo "  --clean=*     Comma separated (without spaces) list of components to clean (e.g. --clean=ffmpeg,kit,bundle)"
      echo "                Valid components: all OR ${VALID_BUILDS[*]}"
      echo "  --license=*   Comma separated (without spaces) list of licenses to build"
      echo "                Valid licenses: ${VALID_LICENSES[*]}"
      echo "  --remote      Publish release asset to remote repository"
      echo "  --local       Build locally instead of using remote releases"
      echo "  --small       Build with small flags (reduces binary size)."
      echo "  --not-small   Build without small flag."
      echo "  --both        Build both small and full versions (default)"
      echo "  --snapshot    Create snapshot version (Android only)."
      echo "  --help        Show this help message"
      echo ""
      echo "State file location: ${STATE_FILE}"
      exit 0;;
    --bundle=*)
      #comma separated list of bundles to build
      parse_bundles "${arg#*=}"
      shift;;
    --build=*)
      #comma separated list of builds to build
      parse_builds "${arg#*=}"
      shift;;
    --clean=*)
      #comma separated list of components to clean
      clean_type="${arg#*=}"
      no_clean=false
      shift;;
    --small)
      SMALL_FLAGS=("small")
      shift;;
    --not-small)
      SMALL_FLAGS=("")
      shift;;
    --both)
      SMALL_FLAGS=("small" "")
      shift;;
    --remote)
      REMOTE_RELEASE=true
      shift;;
    --local)
      REMOTE_RELEASE=false
      shift;;
    --snapshot)
      SNAPSHOT=" --snapshot"
      shift;;
    *)  
      echo "Invalid argument: ${arg}"
      echo "Use --help for usage information"
      shift;;
  esac
done

# Check if the number of elements is 0
if [[ ${#PLATFORMS[@]} -eq 0 ]]; then
  parse_platforms ""
fi

if [[ ${#BUNDLE_ARRAY[@]} -eq 0 ]]; then
  parse_bundles ""
fi

if [[ ${#BUILD_ARRAY[@]} -eq 0 ]]; then
  parse_builds ""
fi

if [[ ${#LICENSE_ARRAY[@]} -eq 0 ]]; then
  parse_licenses ""
fi

# Reset state if requested
if [[ "$reset_state" == true ]]; then
  echo "Resetting build state..."
  rm -f "${STATE_FILE}"
fi

# Initialize state file if it doesn't exist
if [[ ! -f "${STATE_FILE}" ]]; then
  echo "# Build state file - DO NOT EDIT MANUALLY" > "${STATE_FILE}"
  echo "# Format: <script> <args>" >> "${STATE_FILE}"
fi

# Check if a build step is already completed
is_completed() {
  grep -qxF "$1" "${STATE_FILE}" 2>/dev/null
}

# Mark a build step as completed
mark_completed() {
  echo "$1" >> "${STATE_FILE}"
}

# Execute a build step with state tracking
execute_build() {
  local cmd_string="$1"
  local step_label="${2:-}"
  if is_completed "${cmd_string}"; then
    echo "[SKIP] Already completed: ${cmd_string}" | tee -a "${LOG_FILE}"
    return 0
  fi

  echo "[BUILD] Starting: ${cmd_string}" | tee -a "${LOG_FILE}"

  if sudo -E bash -c "${cmd_string}"; then
    mark_completed "${cmd_string}"
    echo "[DONE] Completed: ${cmd_string}" | tee -a "${LOG_FILE}"
    return 0
  else
    local exit_code=$?
    echo "[FAIL] Step ${step_label} failed: ${cmd_string} (exit code: ${exit_code})" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Build failed. You can:" | tee -a "${LOG_FILE}"
    echo "  1. Fix the issue and re-run this script to resume from this step" | tee -a "${LOG_FILE}"
    echo "  2. Use --reset to start from the beginning" | tee -a "${LOG_FILE}"
    exit ${exit_code}
  fi
}

# Define all build steps
declare -a BUILD_STEPS

for platform in "${!PLATFORMS[@]}"; do
  # comma separated list of architectures
  IFS=',' read -ra arch_array <<< "${PLATFORMS[$platform]}"
  for arch in "${arch_array[@]}"; do
    if [[ "${platform}" == "android" ]]; then
      ANDROID_PLATFORM_ARCHS+=("android-${arch}")
    fi
    for bundle in "${BUNDLE_ARRAY[@]}"; do
      for license in "${LICENSE_ARRAY[@]}"; do
        for small in "${SMALL_FLAGS[@]}"; do
          commands="$build_commands"
          if [[ $small == "small" ]]; then
            commands+=" --small"
          fi
          if [[ $license == "gpl" ]]; then
            commands+=" --gpl"
          fi
          if truthy "${no_clean}"; then
            clean=""
          else
            clean="--clean=${clean_type}"
          fi
          remote=""
          no_bundle=""
          if [[ "${platform}" == "android" || "${platform}" == "ios" || "${platform}" == "macos" || "${platform}" == "iphonesimulator" ]]; then
            build_aars=true
            remote="--release=local"
            clean=""
            no_bundle="--no-bundle"
          else
            if [[ "${REMOTE_RELEASE}" == true ]]; then
              remote="--release=remote"
            else
              remote="--release=local"
            fi
          fi
          if falsey "${build_bundle}"; then
            no_bundle="--no-bundle"
          fi
          if [[ "${bundle}" == "debug" ]]; then
            BUILD_STEPS+=("./runner.sh --host=${platform} --arch=${arch} -y ${deps} --base-bundle --build-debug $commands $no_bundle $clean $remote --skip -f --ff-disable-programs")
          else
            BUILD_STEPS+=("./runner.sh --host=${platform} --arch=${arch} -y ${deps} --${bundle//_/-}-bundle $commands $no_bundle $clean $remote --skip -f --ff-disable-programs")
          fi
        done
      done
    done
  done
done

# Calculate progress — count only steps in the current BUILD_STEPS list
# that are already recorded in the state file (accurate for resumed runs)
total_steps=${#BUILD_STEPS[@]}
completed_steps=0
for _step in "${BUILD_STEPS[@]}"; do
  is_completed "${_step}" && (( completed_steps++ )) || true
done

echo "========================================" | tee -a "${LOG_FILE}"
echo "FFmpeg Kit Build All - State Management" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"
echo "Platform: ${p_args}" | tee -a "${LOG_FILE}"
echo "Bundles: ${bundles}" | tee -a "${LOG_FILE}"
echo "Builds: ${builds}" | tee -a "${LOG_FILE}"
echo "Dependencies: ${deps:-no}" | tee -a "${LOG_FILE}"
echo "Total steps: ${total_steps}" | tee -a "${LOG_FILE}"
echo "Completed steps: ${completed_steps}" | tee -a "${LOG_FILE}"
echo "Remaining steps: $((total_steps - completed_steps))" | tee -a "${LOG_FILE}"
echo "State file: ${STATE_FILE}" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

# Execute all build steps
current_step=0
for step in "${BUILD_STEPS[@]}"; do
  current_step=$((current_step + 1))
  echo "" | tee -a "${LOG_FILE}"
  echo "========================================" | tee -a "${LOG_FILE}"
  echo "Step ${current_step}/${total_steps}" | tee -a "${LOG_FILE}"
  echo "========================================" | tee -a "${LOG_FILE}"
  [[ -z "${step}" ]] && continue
  echo "Executing ${step}" | tee -a "${LOG_FILE}"
  execute_build "${step}" "${current_step}/${total_steps}"
done

# save end time
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
# elapsed time in h:m:s
ELAPSED_H=$((ELAPSED_TIME / 3600))
ELAPSED_M=$(((ELAPSED_TIME % 3600) / 60))
ELAPSED_S=$((ELAPSED_TIME % 60))
ELAPSED_TIME_HMS="${ELAPSED_H}h:${ELAPSED_M}m:${ELAPSED_S}s"

echo "" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"
echo "All builds completed successfully!" | tee -a "${LOG_FILE}"
echo "Elapsed time: ${ELAPSED_TIME_HMS}" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"

rm -rf "${STATE_DIR}"

# Build XCFrameworks for Apple platforms
declare -a android_platforms
android_platforms=()
android_platforms_str=""
for platform in "${!PLATFORMS[@]}"; do
  case "${platform}" in
    "android")
      android_platforms+=("${platform}")
      ;;
    *)
      ;;
  esac
done

if [[ ${#android_platforms[@]} -gt 0 ]]; then
  android_platforms_str=$(IFS=,; echo "${android_platforms[*]}")
fi

if [[ ${#android_platforms[@]} -gt 0 ]] && truthy "$build_bundle"; then
  echo "Building AARs..." | tee -a "${LOG_FILE}"
  if [[ "${REMOTE_RELEASE}" == true ]]; then
    remote="--remote"
  else
    remote="--local"
  fi
  repo_path="${GITHUB_REPOSITORY:-"$(get_github_owner)/$(get_github_repo)"}"
  owner="${repo_path%%/*}"
  export GITHUB_USERNAME="$owner" && \
  export GITHUB_REPO="${repo_path#*/}" && \
  export GITHUB_PASSWORD="${GH_TOKEN:-${GITHUB_TOKEN:-$(get_github_token)}}" && \
  export GITHUB_PASSWORD_CLASSIC="${GH_TOKEN:-${GITHUB_TOKEN:-$(get_github_token_classic)}}" && \
  export OSSRH_BASE64="${OSSRH_BASE64:-$(get_maven_base64)}" && \
  export OSSRH_USERNAME="${OSSRH_USERNAME:-$(get_maven_username)}" && \
  export OSSRH_PASSWORD="${OSSRH_PASSWORD:-$(get_maven_password)}" && \
  sudo -E bash -c "${WORK_DIR}/scripts/android/build_aar.sh --bundle=${bundles} --reset ${remote} ${SNAPSHOT}"
fi

# Build XCFrameworks for Apple platforms
declare -a apple_platforms
apple_platforms=()
apple_platforms_str=""
for platform in "${!PLATFORMS[@]}"; do
  case "${platform}" in
    "ios"|"macos")
      apple_platforms+=("${platform}")
      ;;
    *)
      ;;
  esac
done

if [[ ${#apple_platforms[@]} -gt 0 ]]; then
  apple_platforms_str=$(IFS=,; echo "${apple_platforms[*]}")
fi

if [[ -n "${apple_platforms_str}" ]] && truthy "$build_bundle"; then
  echo "========================================" | tee -a "${LOG_FILE}"
  echo "Building XCFrameworks for Apple platforms" | tee -a "${LOG_FILE}"
  echo "========================================" | tee -a "${LOG_FILE}"
  echo "Platforms: ${apple_platforms_str}" | tee -a "${LOG_FILE}"
  echo "Bundles: ${bundles}" | tee -a "${LOG_FILE}"
  echo "========================================" | tee -a "${LOG_FILE}"
  if [[ "${REMOTE_RELEASE}" == true ]]; then
    remote="--remote"
  else
    remote="--local"
  fi
  sudo -E bash -c "${WORK_DIR}/scripts/apple/build_xcframework.sh --platform=${apple_platforms_str} --bundle=${bundles} --reset ${remote}"
fi
