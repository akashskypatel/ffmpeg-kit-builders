#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

# Build AARs for Android
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

# Update sudo timestamp to avoid interruption later
echo "Requesting administrative privileges..."
sudo -v

# State management configuration
export BASEDIR="${BASEDIR:-${PWD}}"
export LOG_FILE="${BASEDIR}/build.log"
export host_platform="android"
STATE_DIR="${STATE_DIR:-${BASEDIR}/.ffmpeg-kit-build-aar-state}"
STATE_FILE="${STATE_DIR}/build_aar.state"
LOCK_FILE="${STATE_DIR}/build_aar.lock"

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
while true; do sudo -n v; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Parse arguments
p=""
p_args=""
deps=""
reset_state=false
# VALID_BUNDLES=("debug" "full" "base" "audio" "video" "video_hw")
# VALID_ARCHS=("x86_64" "aarch64" "armv7a")
# VALID_ANDROID=("android-aarch64" "android-armv7a" "android-x86_64")
LICENSE_ARRAY=(" " "gpl")
SMALL_FLAGS=(" " "small")
VALID_LICENSES=("lgpl" "gpl")
VALID_SMALL_FLAGS=("small" "")
declare -A PLATFORMS
local_build=false
# Define all build steps
declare -a BUILD_STEPS
create_aar=true
create_release=true

parse_arch() {
    case "$1" in
        "x86_64")
            echo "x86_64"
            ;;
        "aarch64"|"arm64"|"arm64-v8a")
            echo "arm64-v8a"
            ;;
        "armv7a"|"arm"|"armeabi-v7a")
            echo "armeabi-v7a"
            ;;
        *)
            echo "parse_arch: Unsupported host arch '$1' for Android"
            exit 1
            ;;
    esac
}

parse_platforms() {
  p_args="${1}"
  # Ensure p_args is populated if empty
  if [[ -z "${p_args}" ]]; then
    p_args=$(IFS=,; echo "${VALID_ANDROID[*]}")
  fi
  echo "DEBUG: p_args: ${p_args}"
  # Use IFS local to the read command
  IFS=',' read -ra P_ARRAY <<< "$p_args"
  for p in "${P_ARRAY[@]}"; do
    # Skip empty elements resulting from trailing/double commas
    [[ -z "$p" ]] && continue
    # Validate against whitelist
    local valid=false
    for valid_p in "${VALID_ANDROID[@]}"; do
      [[ "$p" == "$valid_p" ]] && valid=true && break
    done
    if [[ "$valid" == false ]]; then
      echo "Error: Invalid platform and arch: ${p}"
      echo "Use --help for usage information"
      exit 1
    fi
    local key="${p%-*}"
    local value="${p#*-}"
    # Always quote the key within the brackets
    if [[ -z "${PLATFORMS["$key"]}" ]]; then
      PLATFORMS["$key"]="${value}"
    else
      PLATFORMS["$key"]="${PLATFORMS["$key"]},${value}"
    fi
  done
}

parse_bundles() {
  bundles="${1}"
  # Ensure bundles is populated if empty
  if [[ -z "${bundles}" ]]; then
    bundles=$(IFS=,; echo "${VALID_BUNDLES[*]}")
  fi
  echo "DEBUG: bundles: ${bundles}"
  # Use IFS local to the read command
  IFS=',' read -ra BUNDLE_ARRAY <<< "${bundles}"
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
  if is_completed "${cmd_string}"; then
    echo "[SKIP] Already completed: ${cmd_string}" | tee -a "${LOG_FILE}"
    return 0
  fi
  
  echo "[BUILD] Starting: ${cmd_string}" | tee -a "${LOG_FILE}"
  
  if eval "${cmd_string}" > >(redirect_output) 2>&1; then
    mark_completed "${cmd_string}"
    echo "[DONE] Completed: ${cmd_string}" | tee -a "${LOG_FILE}"
    return 0
  else
    local exit_code=$?
    echo "[FAIL] Failed: ${cmd_string} (exit code: ${exit_code})" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Build failed. You can:" | tee -a "${LOG_FILE}"
    echo "  1. Fix the issue and re-run this script to resume from this step" | tee -a "${LOG_FILE}"
    echo "  2. Use --reset to start from the beginning" | tee -a "${LOG_FILE}"
    exit ${exit_code}
  fi
}

create_jni_libs_dir() {
  local bundle_pfx=""
  local small_pfx=""
  local license_pfx=""
  local is_debug_pfx=""
  for arg in "$@"; do
    case "$arg" in
      -b=*)
        local bundle="${arg#*=}"
        local bundle_pfx="-${bundle}"
        ;;
      -s=*)
        local small="${arg#*=}"
        if [[ "${small}" == "small" ]]; then
            small_pfx="-small"
        fi
        ;;
      -l=*)
        local license="${arg#*=}"
        if [[ "${license}" == "gpl" ]]; then
            license_pfx="-gpl"
        fi
        ;;
      *)
        echo "create_jni_libs_dir: Unsupported arg '$arg'"
        exit 1
        ;;
    esac
  done
  if [[ "${bundle}" == "debug" ]]; then
    bundle_pfx="-base"
    is_debug_pfx="-debug"
  fi
  local jni_libs_dir="${BASEDIR}/prebuilt/android/jniLibs${bundle_pfx}${small_pfx}${is_debug_pfx}${license_pfx}/jniLibs"
  mkdir -p "${jni_libs_dir}"/{include,lib/pkgconfig,arm64-v8a,armeabi-v7a,x86,x86_64}
  chmod -R a+rwx "${jni_libs_dir}"
  echo "${jni_libs_dir}"
}

get_ffmpeg_kit_dir() {
  local arch_pfx=""
  local bundle_pfx=""
  local small_pfx=""
  local license_pfx=""
  local is_debug_pfx=""
  for arg in "$@"; do
    case "$arg" in
      -a=*)
        local arch="${arg#*=}"
        local arch_pfx="-${arch}"
        ;;
      -b=*)
        local bundle="${arg#*=}"
        local bundle_pfx="-${bundle}"
        ;;
      -s=*)
        local small="${arg#*=}"
        if [[ "${small}" == "small" ]]; then
            small_pfx="-small"
        fi
        ;;
      -l=*)
        local license="${arg#*=}"
        if [[ "${license}" == "gpl" ]]; then
            license_pfx="-gpl"
        fi
        ;;
      *)
        echo "get_ffmpeg_kit_dir: Unsupported arg '$arg'"
        exit 1
        ;;
    esac
  done
  if [[ "${bundle}" == "debug" ]]; then
    bundle_pfx="-base"
    is_debug_pfx="-debug"
  fi
    # ffmpeg-kit-base-android-x86_64-shared-debug-gpl or ffmpeg-kit-video_hw-android-x86_64-shared-small-gpl
    echo "${BASEDIR}/prebuilt/android-${arch}/ffmpeg-kit${bundle_pfx}-android${arch_pfx}-shared${small_pfx}${is_debug_pfx}${license_pfx}"
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
    --reset)
      reset_state=true
      shift;;
    --local)
      local_build=true
      shift;;
    --remote)
      local_build=false
      shift;;
    --create-aar)
      create_aar=true
      create_release=false
      shift;;
    --create-release)
      create_release=true
      create_aar=false
      shift;;
    --help)
      echo "Usage: $0 [--platform=linux-x86_64|windows-x86_64|android-aarch64|android-armv7a|android-x86_64] [--reset] [--bundles=*) ] [--help]"
      echo ""
      echo "Options:"
      echo "  --platform=*      Comma separated (without spaces) list of platforms and architectures (e.g. --platform=linux-x86_64,windows-x86_64,android-aarch64,android-armv7a,android-x86_64)"
      echo "                    Valid platforms: ${VALID_PLATFORMS[*]}"
      echo "                    Valid architectures: ${VALID_ARCHS[*]}"
      echo "                    Valid platform and arch combinations: ${VALID_ANDROID[*]}"
      echo "  --reset           Reset build state and start from beginning"
      echo "  --bundle=*        Comma separated (without spaces) list of bundles to build (e.g. --bundle=debug,full,base,audio,video,video_hw)"
      echo "                    Valid bundles: ${VALID_BUNDLES[*]}"
      echo "                    Note: Not including one of below flags will create all of artifacts: AAR, and release"
      echo "                    Do not specify if you want to create all artifacts."
      echo "  --license=*       Comma separated (without spaces) list of licenses to build"
      echo "                    Valid licenses: ${VALID_LICENSES[*]}"
      echo "  --create-aar      Create AAR file. Will not create release."
      echo "  --create-release  Create release. Will not create AAR. Requires aar release asset to be present."
      echo "  --small           Build with small flags (reduces binary size)."
      echo "  --not-small       Build without small flag."
      echo "  --both            Build both small and full versions (default)"
      echo "  --local           Create local release."
      echo "  --remote          Publish release to remote repository."
      echo "  --snapshot        Create snapshot version."
      echo "  --help            Show this help message"
      echo ""
      echo "State file location: ${STATE_FILE}"
      exit 0;;
    --bundle=*) 
      #comma separated list of bundles to build
      parse_bundles "${arg#*=}"
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
    --snapshot)
      SNAPSHOT=true
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

ANDROID_HOME="/usr/local/android-sdk"
latest_ndk=$(ls -v "$ANDROID_HOME/ndk" 2>/dev/null | tail -n 1)
ANDROID_API_LEVEL="26"
repo_path="${GITHUB_REPOSITORY:-"$(get_github_owner)/$(get_github_repo)"}"
repo_name="${repo_path##*/}"
owner="${repo_path%%/*}"
GITHUB_USERNAME="${GITHUB_USERNAME:-${owner:-$(get_github_owner)}}"
GITHUB_REPO="${GITHUB_REPO:-${repo_name:-$(get_github_repo)}}"
GITHUB_PASSWORD="${GH_TOKEN:-${GITHUB_TOKEN:-$(get_github_token)}}"
GITHUB_PASSWORD_CLASSIC="${GH_TOKEN:-${GITHUB_TOKEN:-$(get_github_token_classic)}}"
OSSRH_USERNAME="${OSSRH_USERNAME:-$(get_maven_username)}"
OSSRH_PASSWORD="${OSSRH_PASSWORD:-$(get_maven_password)}"
GRADLE_COMMAND="publishToMavenCentral"
GRADLE_SIGN_PUBLICATIONS="true"
SIGNING_HOME="${GITHUB_WORKSPACE:-$(get_userhome)}"
SIGNING_HOME="${SIGNING_HOME:-$HOME}"
GRADLE_SIGNING_HOME="${SIGNING_HOME}/.gradle"
SDKMAN_DIR="${SDKMAN_DIR:-/usr/local/sdkman}"

if [[ -z "$SIGNING_HOME" || ! -d "$SIGNING_HOME" ]]; then
  exit_message 1 "Unable to determine user home"
fi

if [[ ! -f "${GRADLE_SIGNING_HOME}/gradle.properties" || ! -f "${SIGNING_HOME}/.gnupg/secring.gpg" ]] || [[ "$local_build" == "true" || "$SNAPSHOT" == "true" ]]; then
  echo "Maven signing not configured, using local build" | tee -a "${LOG_FILE}"
  GRADLE_COMMAND="publishToMavenLocal"
  GRADLE_SIGN_PUBLICATIONS="false"
fi

# FFMPEG_KIT_VERSION: from version file
if [[ "$SNAPSHOT" == true ]]; then
  FFMPEG_KIT_VERSION="$(cat "${BASEDIR}/version")-SNAPSHOT"
else
  FFMPEG_KIT_VERSION="$(cat "${BASEDIR}/version")"
fi

cd "${BASEDIR}" || { exit_message 1 "Failed to change directory to ${BASEDIR}"; }
echo "sdk.dir=$ANDROID_HOME" > local.properties

# Define all build steps
declare -a BUILD_STEPS

if ! command -v gradle >/dev/null 2>&1; then
  if [[ -f /etc/profile.d/sdkman.sh ]]; then
    # shellcheck source=/dev/null
    source /etc/profile.d/sdkman.sh
  fi
  if [[ -x "${SDKMAN_DIR}/candidates/gradle/current/bin/gradle" ]]; then
    export PATH="${SDKMAN_DIR}/candidates/gradle/current/bin:${PATH}"
  fi
fi

if [[ ! -f "${BASEDIR}/gradlew" ]]; then
  if ! command -v gradle >/dev/null 2>&1; then
    exit_message 1 "Gradle is not available on PATH. Ensure scripts/toolchain/setup-android.sh completed successfully."
  fi
  echo "RUNNING: gradle wrapper --distribution-type all" | tee -a "${LOG_FILE}"
  gradle wrapper --distribution-type all || { exit_message 1 "Failed to create Gradle wrapper"; }
fi
chmod +x "${BASEDIR}/gradlew"
OWNER="${GITHUB_USERNAME:-$(get_github_owner)}"
create_aar_artifact() {
  FFMPEG_KIT_JNI_LIBS_DIR="$1"
  FFMPEG_KIT_OUTPUT_NAME="$2"
  FFMPEG_KIT_NAMESPACE="io.github.${OWNER}.ffmpegkit"
  ANDROID_NDK="${latest_ndk}"
  FFMPEG_KIT_VERSION_CODE="$(date +%Y%m%d)"
  build_step="./gradlew :tools:android:${GRADLE_COMMAND} \
  --no-daemon --info --warning-mode all --gradle-user-home ~/.gradle \
  -PFFMPEG_KIT_NAMESPACE=\"${FFMPEG_KIT_NAMESPACE}\" \
  -PANDROID_NDK=\"${ANDROID_NDK}\" \
  -PANDROID_API_LEVEL=\"${ANDROID_API_LEVEL}\" \
  -PFFMPEG_KIT_VERSION_CODE=\"${FFMPEG_KIT_VERSION_CODE}\" \
  -PFFMPEG_KIT_VERSION=\"${FFMPEG_KIT_VERSION}\" \
  -PFFMPEG_KIT_JNI_LIBS_DIR=\"${FFMPEG_KIT_JNI_LIBS_DIR}\" \
  -PFFMPEG_KIT_OUTPUT_NAME=\"${FFMPEG_KIT_OUTPUT_NAME}\" \
  -PFFMPEG_KIT_SIGN_PUBLICATIONS=\"${GRADLE_SIGN_PUBLICATIONS}\" \
  -PmavenCentralUsername=\"${OSSRH_USERNAME}\" \
  -PmavenCentralPassword=\"${OSSRH_PASSWORD}\""
  if [[ "$local_build" == "true" ]]; then
    BUILD_STEPS+=("$build_step")
  elif check_maven_package_status "${FFMPEG_KIT_OUTPUT_NAME}" "$FFMPEG_KIT_VERSION" > >(redirect_output) 2>&1; then
    echo "Package ${FFMPEG_KIT_OUTPUT_NAME} version ${FFMPEG_KIT_VERSION} already exists in Maven Central, skipping build" | tee -a "${LOG_FILE}"
  else
    BUILD_STEPS+=("$build_step")
  fi
}

create_release_artifact() {
  release_asset="$1"
  build_step="export host_platform=${host_platform:-android} && create_github_release \"${release_asset}\""
  BUILD_STEPS+=("$build_step")
}

for key in "${!PLATFORMS[@]}"; do
  platform=${key}
  # comma separated list of architectures
  IFS=',' read -ra arch_array <<< "${PLATFORMS[$key]}"
  for bundle in "${BUNDLE_ARRAY[@]}"; do
      for license in "${LICENSE_ARRAY[@]}"; do
          for small in "${SMALL_FLAGS[@]}"; do
              jni_libs_dir="$(create_jni_libs_dir -b="${bundle}" -l="${license}" -s="${small}")"
              license_flag=""
              if [[ "${license}" == "gpl" ]]; then
                  license_flag="--gpl"
              fi
              small_flag=""
              if [[ "${small}" == "small" ]]; then
                  small_flag="--small"
              fi
              for arch in "${arch_array[@]}"; do
                if [[ "${create_aar}" == "true" ]]; then
                  # execute_build "${step}"
                  ffmpeg_kit_dir="$(get_ffmpeg_kit_dir -b="${bundle}" -l="${license}" -s="${small}" -a="${arch}")"
                  ffmpeg_kit_include_dir="${ffmpeg_kit_dir}/include"
                  abi_arch="$(parse_arch "${arch}")"
                  # copy to jniLibs
                  if [[ -d "${ffmpeg_kit_include_dir}" ]]; then
                    echo "Copying include directory to jniLibs" > >(redirect_output)
                    build_step="cp -r \"${ffmpeg_kit_include_dir}\" \"${jni_libs_dir}\""
                    BUILD_STEPS+=("$build_step")
                  fi
                  if [[ -d "${ffmpeg_kit_dir}/lib" ]]; then
                    echo "Copying lib directory to jniLibs" > >(redirect_output)
                    build_step="find \"${ffmpeg_kit_dir}/lib\" \( -name \"*.so*\" -o -name \"*.a*\" \) -exec cp -fv {} \"${jni_libs_dir}/${abi_arch}\" \;"
                    BUILD_STEPS+=("$build_step")
                  fi
                  if [[ -d "${ffmpeg_kit_dir}/lib/pkgconfig" ]]; then
                    echo "Copying pkgconfig directory to jniLibs" > >(redirect_output)
                    build_step="cp -r \"${ffmpeg_kit_dir}/lib/pkgconfig\" \"${jni_libs_dir}/lib\""
                    BUILD_STEPS+=("$build_step")
                  fi
                  build_step="chmod -R a+rwx \"${jni_libs_dir}\""
                  BUILD_STEPS+=("$build_step")
                fi
              done
              FFMPEG_KIT_JNI_LIBS_DIR=$(realpath "${jni_libs_dir}")
              if [[ ! -d "${FFMPEG_KIT_JNI_LIBS_DIR}" ]]; then
                echo "DEBUG: Failed to resolve jniLibs directory" | tee -a "${LOG_FILE}"
                continue
              fi
              small_pfx=""
              if [[ "${small}" == "small" ]]; then
                  small_pfx="-small"
              fi
              license_pfx=""
              if [[ "${license}" == "gpl" ]]; then
                  license_pfx="-gpl"
              else
                  license_pfx="-lgpl"
              fi
              assemble_type="Release"
              bundle_pfx="$bundle"
              debug_pfx=""
              if [[ "${bundle}" == "debug" ]]; then
                  bundle_pfx="base"
                  debug_pfx="-debug"
              fi
              FFMPEG_KIT_OUTPUT_NAME="bundle-${bundle_pfx}-shared${debug_pfx}${small_pfx}${license_pfx}"
              package_name="${FFMPEG_KIT_NAMESPACE}.${FFMPEG_KIT_OUTPUT_NAME}"
              echo "jniLibs dir: ${FFMPEG_KIT_JNI_LIBS_DIR}" > >(redirect_output)
              if find "${FFMPEG_KIT_JNI_LIBS_DIR}" -type f \( -name "*.so" -o -name "*.a" \) | read -r; then
                [[ "${create_aar}" == "true" ]] && { create_aar_artifact "${FFMPEG_KIT_JNI_LIBS_DIR}" "${FFMPEG_KIT_OUTPUT_NAME}" || exit_message 1 "Failed to create AAR artifact"; }
                if [[ "${create_release}" == "true" ]]; then
                  release_asset="${BASEDIR}/tools/android/build/outputs/aar/${FFMPEG_KIT_OUTPUT_NAME}-${assemble_type,,}.aar"
                  if [[ ! -f "$release_asset" ]]; then
                    exit_message 1 "Release asset not found: $release_asset"
                  fi
                fi
                [[ "${create_release}" == "true" && "$local_build" != "true" ]] && { create_release_artifact "${release_asset}" || exit_message 1 "Failed to create release artifact"; }
              fi
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
echo "FFmpeg Kit AAR Build - State Management" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"
echo "Platform: ${PLATFORMS[*]}" | tee -a "${LOG_FILE}"
echo "Bundles: ${BUNDLE_ARRAY[*]}" | tee -a "${LOG_FILE}"
echo "Licenses: ${LICENSE_ARRAY[*]}" | tee -a "${LOG_FILE}"
echo "Small: ${SMALL_FLAGS[*]}" | tee -a "${LOG_FILE}"
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
