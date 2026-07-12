#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

# Code signing and notarization for iOS/macOS XCFramework bundles
# This script signs XCFramework binaries and optionally notarizes them for distribution
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

set -e

# Update sudo timestamp to avoid interruption later
echo "Requesting administrative privileges..."
sudo -v

# State management configuration
export BASEDIR="${BASEDIR:-${PWD}}"
export LOG_FILE="${BASEDIR}/build.log"
STATE_DIR="${STATE_DIR:-${BASEDIR}/.ffmpeg-kit-build-signing-state}"
STATE_FILE="${STATE_DIR}/build_signing.state"
LOCK_FILE="${STATE_DIR}/build_signing.lock"

# Source common functions
source "${BASEDIR}/scripts/function.sh"
source "${BASEDIR}/scripts/supported.sh"

[[ -f "$LOG_FILE" ]] && rm -f "$LOG_FILE"
[[ -f "$LOG_FILE" ]] && chmod -R a+rwx "$LOG_FILE" || true

# Initialize state directory
mkdir -p "${STATE_DIR}"

# Cleanup function for lock file
cleanup() {
  rm -f "${LOCK_FILE}"
}
trap cleanup EXIT

# Check for existing lock
if [[ -f "${LOCK_FILE}" ]]; then
  echo "Error: Another signing process is running (lock file exists: ${LOCK_FILE})"
  echo "If you're sure no other signing is running, remove the lock file manually."
  exit 1
fi

# Create lock file
touch "${LOCK_FILE}"

# Keep the timestamp alive in the background for long-running builds
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Parse arguments
# VALID_BUNDLES=("debug" "full" "base" "audio" "video" "video_hw")
LICENSE_FLAGS=("lgpl" "gpl")
SMALL_FLAGS=("" "small")
reset_state=false
skip_notarization=false
notarize_only=false
signing_identity=""
team_id=""
apple_id=""
app_specific_password=""
owner="$(get_github_owner)"

declare -A PLATFORM_ARCHS

# Check if a build step is already completed
is_completed() {
  grep -qxF "$1" "${STATE_FILE}" 2>/dev/null
}

# Mark a build step as completed
mark_completed() {
  echo "$1" >> "${STATE_FILE}"
}

# Execute a signing step with state tracking
execute_signing() {
  local cmd_string="$1"
  if is_completed "${cmd_string}"; then
    echo "[SKIP] Already completed: ${cmd_string}"
    return 0
  fi

  echo "[SIGNING] Starting: ${cmd_string}"

  if bash -c "${cmd_string}"; then
    mark_completed "${cmd_string}"
    echo "[DONE] Completed: ${cmd_string}"
    return 0
  else
    local exit_code=$?
    echo "[FAIL] Failed: ${cmd_string} (exit code: ${exit_code})"
    echo ""
    echo "Signing failed. You can:"
    echo "  1. Fix the issue and re-run this script to resume from this step"
    echo "  2. Use --reset to start from the beginning"
    exit ${exit_code}
  fi
}

get_output_name() {
  local bundle="$1"
  local license="$2"
  local small="$3"

  local bundle_pfx="${bundle}"
  local small_pfx=""
  local license_pfx=""
  local debug_pfx=""

  if [[ "${bundle}" == "debug" ]]; then
    bundle_pfx="base"
    debug_pfx="-debug"
  fi

  if [[ "${small}" == "small" ]]; then
    small_pfx="-small"
  fi

  if [[ "${license}" == "gpl" ]]; then
    license_pfx="-gpl"
  else
    license_pfx="-lgpl"
  fi

  echo "ffmpegkit-${bundle_pfx}${small_pfx}${debug_pfx}${license_pfx}"
}

validate_signing_environment() {
  echo "Validating signing environment..."

  # Check for signing identity
  if [[ -z "${signing_identity}" ]]; then
    echo "ERROR: No signing identity provided. Use --signing-identity"
    exit 1
  fi

  # Handle ad-hoc signing specially
  if [[ "${signing_identity}" == "-" ]]; then
    echo "⚠ Using ad-hoc signing identity (development only)"
    echo "  Note: Ad-hoc signed binaries cannot be notarized"
    
    # Force skip notarization for ad-hoc signing
    if [[ "${skip_notarization}" == false ]]; then
      echo "  Auto-enabling --skip-notarization for ad-hoc signing"
      skip_notarization=true
    fi
    
    echo "✓ Ad-hoc signing mode enabled"
  else
    # Verify signing identity exists in keychain
    if ! security find-identity -v -p codesigning | grep -q "${signing_identity}"; then
      echo "ERROR: Signing identity '${signing_identity}' not found in keychain"
      echo ""
      echo "Available identities:"
      security find-identity -v -p codesigning
      echo ""
      echo "To import a signing identity:"
      echo "  security import Certificates.p12 -k ~/Library/Keychains/login.keychain-db -P <password>"
      echo ""
      echo "For development/testing, use ad-hoc signing:"
      echo "  --signing-identity=-"
      exit 1
    fi

    echo "✓ Signing identity validated: ${signing_identity}"
  fi

  # Validate notarization credentials if enabled
  if [[ "${skip_notarization}" == false ]]; then
    if [[ -z "${apple_id}" ]]; then
      echo "ERROR: No Apple ID provided. Use --apple-id or --skip-notarization"
      exit 1
    fi

    if [[ -z "${app_specific_password}" ]]; then
      echo "ERROR: No app-specific password provided. Use --app-specific-password"
      echo "Generate one at: https://appleid.apple.com/account/manage"
      exit 1
    fi

    if [[ -z "${team_id}" ]]; then
      echo "ERROR: No team ID provided. Use --team-id"
      exit 1
    fi

    echo "✓ Notarization credentials validated"
  fi

  # Check for required tools
  for tool in codesign xcrun altool; do
    if ! command -v "${tool}" &> /dev/null; then
      echo "ERROR: Required tool '${tool}' not found"
      exit 1
    fi
  done

  echo "✓ All required tools available"
}

sign_xcframework() {
  local xcframework_path="$1"

  echo "Signing XCFramework: ${xcframework_path}"

  if [[ ! -d "${xcframework_path}" ]]; then
    echo "ERROR: XCFramework not found: ${xcframework_path}"
    return 1
  fi

  # Sign all dylibs within the XCFramework
  local signed_count=0
  for platform_dir in "${xcframework_path}"/*; do
    if [[ -d "${platform_dir}" ]]; then
      local lib_file="${platform_dir}/libffmpegkit.dylib"
      if [[ -f "${lib_file}" ]]; then
        echo "  Signing: $(basename "${platform_dir}")/libffmpegkit.dylib"

        codesign \
          --force \
          --sign "${signing_identity}" \
          --timestamp \
          --options runtime \
          --preserve-metadata=entitlements,requirements,flags,runtime \
          "${lib_file}"

        # Verify signature
        if codesign --verify --verbose "${lib_file}"; then
          echo "  ✓ Signed successfully"
          ((signed_count++))
        else
          echo "  ✗ Signature verification failed"
          return 1
        fi
      fi
    fi
  done

  if [[ ${signed_count} -eq 0 ]]; then
    echo "WARNING: No libraries found to sign in XCFramework"
    return 1
  fi

  echo "✓ Signed ${signed_count} libraries in XCFramework"
  return 0
}

verify_signature() {
  local xcframework_path="$1"

  echo "Verifying signatures in: ${xcframework_path}"

  local verified_count=0
  local failed_count=0

  for platform_dir in "${xcframework_path}"/*; do
    if [[ -d "${platform_dir}" ]]; then
      local lib_file="${platform_dir}/libffmpegkit.dylib"
      if [[ -f "${lib_file}" ]]; then
        if codesign --verify --verbose "${lib_file}" 2>/dev/null; then
          echo "  ✓ $(basename "${platform_dir}")/libffmpegkit.dylib"
          ((verified_count++))
        else
          echo "  ✗ $(basename "${platform_dir}")/libffmpegkit.dylib"
          ((failed_count++))
        fi
      fi
    fi
  done

  echo ""
  echo "Verification Summary:"
  echo "  Verified: ${verified_count}"
  echo "  Failed: ${failed_count}"

  if [[ ${failed_count} -gt 0 ]]; then
    return 1
  fi

  return 0
}

create_zip_for_notarization() {
  local xcframework_path="$1"
  local output_dir="$2"

  local xcframework_name="$(basename "${xcframework_path}")"
  local zip_path="${output_dir}/${xcframework_name}.zip"

  echo "Creating ZIP for notarization: ${zip_path}"

  # Create ZIP (required for notarization submission)
  ditto -c -k --sequesterRsrc --keepParent \
    "${xcframework_path}" \
    "${zip_path}"

  if [[ -f "${zip_path}" ]]; then
    echo "✓ Created notarization ZIP: ${zip_path}"
    echo "${zip_path}"
    return 0
  else
    echo "ERROR: Failed to create ZIP"
    return 1
  fi
}

submit_for_notarization() {
  local zip_path="$1"
  local bundle_id="$2"

  echo "Submitting for notarization: $(basename "${zip_path}")"
  echo "Bundle ID: ${bundle_id}"

  # Submit to Apple's notarization service
  local result
  result=$(xcrun altool \
    --notarize-app \
    --file "${zip_path}" \
    --primary-bundle-id "${bundle_id}" \
    --username "${apple_id}" \
    --password "@keychain:AC_PASSWORD" \
    --output-format xml 2>&1) || true

  echo "${result}" >> "${LOG_FILE}"

  # Extract request UUID
  local request_uuid
  request_uuid=$(echo "${result}" | grep -A1 "notarization-upload" | grep "RequestUUID" | gsed 's/.*<string>\(.*\)<\/string>.*/\1/')

  if [[ -z "${request_uuid}" ]]; then
    echo "ERROR: Failed to submit for notarization"
    echo "Result: ${result}"
    return 1
  fi

  echo "✓ Submitted successfully"
  echo "Request UUID: ${request_uuid}"
  echo "${request_uuid}"
  return 0
}

store_app_specific_password() {
  echo "Storing app-specific password in keychain..."

  # Store password in keychain (one-time setup)
  security add-generic-password \
    -a "${apple_id}" \
    -w "${app_specific_password}" \
    -s "AC_PASSWORD" \
    -U

  echo "✓ Password stored in keychain"
}

check_notarization_status() {
  local request_uuid="$1"

  echo "Checking notarization status: ${request_uuid}"

  local status
  status=$(xcrun altool \
    --notarization-info "${request_uuid}" \
    --username "${apple_id}" \
    --password "@keychain:AC_PASSWORD" \
    --output-format xml 2>&1) || true

  echo "${status}" >> "${LOG_FILE}"

  # Extract status
  local notarization_status
  notarization_status=$(echo "${status}" | grep -A1 "Status" | grep "string" | gsed 's/.*<string>\(.*\)<\/string>.*/\1/' | head -1)

  echo "Status: ${notarization_status}"

  case "${notarization_status}" in
    "success")
      echo "✓ Notarization completed successfully"
      return 0
      ;;
    "in progress")
      echo "⏳ Notarization still in progress"
      return 1
      ;;
    "invalid")
      echo "✗ Notarization failed"
      echo ""
      echo "Checking for issues..."
      local issues
      issues=$(echo "${status}" | grep -A20 "Status Code" | grep -A20 "Status Message")
      echo "${issues}"
      return 2
      ;;
    *)
      echo "? Unknown status: ${notarization_status}"
      return 1
      ;;
  esac
}

wait_for_notarization() {
  local request_uuid="$1"
  local max_wait="${2:-1800}"  # Default 30 minutes
  local poll_interval="${3:-30}"  # Default 30 seconds

  echo "Waiting for notarization (max ${max_wait}s, polling every ${poll_interval}s)..."

  local elapsed=0
  while [[ ${elapsed} -lt ${max_wait} ]]; do
    sleep ${poll_interval}
    elapsed=$((elapsed + poll_interval))

    echo "[${elapsed}s] Checking status..."

    if check_notarization_status "${request_uuid}"; then
      return 0
    fi

    local exit_code=$?
    if [[ ${exit_code} -eq 2 ]]; then
      echo "✗ Notarization failed"
      return 1
    fi
  done

  echo "✗ Timeout waiting for notarization"
  return 1
}

staple_notarization_ticket() {
  local xcframework_path="$1"

  echo "Stapling notarization ticket to: ${xcframework_path}"

  # Staple the ticket (only works for macOS, not iOS)
  if xcrun stapler staple "${xcframework_path}"; then
    echo "✓ Stapled notarization ticket"
    return 0
  else
    echo "WARNING: Failed to staple ticket (may not be required for this platform)"
    return 0  # Non-fatal
  fi
}

# Argument parsing
for arg; do
  case "${arg}" in
    --bundles=*)
      bundles="${arg#*=}"
      IFS=',' read -ra BUNDLE_ARRAY <<< "${bundles}"
      shift;;
    --signing-identity=*)
      signing_identity="${arg#*=}"
      shift;;
    --team-id=*)
      team_id="${arg#*=}"
      shift;;
    --apple-id=*)
      apple_id="${arg#*=}"
      shift;;
    --app-specific-password=*)
      app_specific_password="${arg#*=}"
      shift;;
    --skip-notarization)
      skip_notarization=true
      shift;;
    --notarize-only)
      notarize_only=true
      shift;;
    --reset)
      reset_state=true
      shift;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --bundles=*                   Comma separated list of bundles to sign"
      echo "                                Valid bundles: ${VALID_BUNDLES[*]}"
      echo "  --signing-identity=*          Code signing identity (e.g., 'Developer ID Application: Company (TEAMID)')"
      echo "  --team-id=*                   Apple Developer Team ID"
      echo "  --apple-id=*                  Apple ID for notarization"
      echo "  --app-specific-password=*     App-specific password for Apple ID"
      echo "  --skip-notarization           Skip notarization (only sign)"
      echo "  --notarize-only               Only notarize existing signed XCFrameworks"
      echo "  --reset                       Reset signing state"
      echo "  --help                        Show this help message"
      echo ""
      echo "Examples:"
      echo "  # Sign and notarize"
      echo "  $0 --bundles=base,full \\"
      echo "     --signing-identity='Developer ID Application: MyCompany (ABC123)' \\"
      echo "     --team-id=ABC123 \\"
      echo "     --apple-id=developer@example.com \\"
      echo "     --app-specific-password=abcd-efgh-ijkl-mnop"
      echo ""
      echo "  # Sign only (no notarization)"
      echo "  $0 --bundles=base --signing-identity='My Identity' --skip-notarization"
      echo ""
      echo "State file location: ${STATE_FILE}"
      exit 0;;
    *)
      echo "Invalid argument: ${arg}"
      echo "Use --help for usage information"
      exit 1;;
  esac
done

if [[ ${#BUNDLE_ARRAY[@]} -eq 0 ]]; then
  BUNDLE_ARRAY=("${VALID_BUNDLES[@]}")
fi

# Reset state if requested
if [[ "$reset_state" == true ]]; then
  echo "Resetting signing state..."
  rm -f "${STATE_FILE}"
fi

# Initialize state file if it doesn't exist
if [[ ! -f "${STATE_FILE}" ]]; then
  echo "# Signing state file - DO NOT EDIT MANUALLY" > "${STATE_FILE}"
  echo "# Format: <script> <args>" >> "${STATE_FILE}"
fi

# Version information
FFMPEG_KIT_VERSION="$(cat "${BASEDIR}/version")"

echo "========================================"
echo "XCFramework Code Signing Pipeline"
echo "========================================"
echo "Version: ${FFMPEG_KIT_VERSION}"
echo "Bundles: ${bundles}"
echo "Signing Identity: ${signing_identity}"
echo "Notarization: $([[ "${skip_notarization}" == true ]] && echo "Skipped" || echo "Enabled")"
echo "========================================"
echo ""

# Validate environment (skip if notarize-only)
if [[ "${notarize_only}" == false ]]; then
  validate_signing_environment
fi

# Store password if provided
if [[ -n "${apple_id}" && -n "${app_specific_password}" ]]; then
  store_app_specific_password
fi

xcframework_output_dir="${BASEDIR}/prebuilt/apple/xcframeworks"

# Define signing steps
declare -a SIGNING_STEPS

if [[ "${notarize_only}" == false ]]; then
  for bundle in "${BUNDLE_ARRAY[@]}"; do
    for license in "${LICENSE_FLAGS[@]}"; do
      for small in "${SMALL_FLAGS[@]}"; do
        output_name="$(get_output_name "${bundle}" "${license}" "${small}")"
        xcframework_path="${xcframework_output_dir}/${output_name}.xcframework"

        if [[ -d "${xcframework_path}" ]]; then
          SIGNING_STEPS+=("sign_xcframework '${xcframework_path}'")
        else
          echo "WARNING: XCFramework not found: ${xcframework_path}"
        fi
      done
    done
  done
fi

# Execute signing steps
if [[ ${#SIGNING_STEPS[@]} -gt 0 ]]; then
  echo "========================================"
  echo "Signing XCFrameworks"
  echo "========================================"

  for step in "${SIGNING_STEPS[@]}"; do
    execute_signing "${step}"
  done

  echo ""
  echo "========================================"
  echo "Verifying Signatures"
  echo "========================================"

  for bundle in "${BUNDLE_ARRAY[@]}"; do
    for license in "${LICENSE_FLAGS[@]}"; do
      for small in "${SMALL_FLAGS[@]}"; do
        output_name="$(get_output_name "${bundle}" "${license}" "${small}")"
        xcframework_path="${xcframework_output_dir}/${output_name}.xcframework"

        if [[ -d "${xcframework_path}" ]]; then
          verify_signature "${xcframework_path}" || {
            echo "ERROR: Signature verification failed for ${output_name}"
            exit 1
          }
        fi
      done
    done
  done
fi

# Notarization
if [[ "${skip_notarization}" == false && "${notarize_only}" == false ]]; then
  echo ""
  echo "========================================"
  echo "Notarizing XCFrameworks"
  echo "========================================"

  for bundle in "${BUNDLE_ARRAY[@]}"; do
    for license in "${LICENSE_FLAGS[@]}"; do
      for small in "${SMALL_FLAGS[@]}"; do
        output_name="$(get_output_name "${bundle}" "${license}" "${small}")"
        xcframework_path="${xcframework_output_dir}/${output_name}.xcframework"

        if [[ -d "${xcframework_path}" ]]; then
          echo ""
          echo "Processing: ${output_name}"

          # Create ZIP for notarization
          zip_path="$(create_zip_for_notarization "${xcframework_path}" "${xcframework_output_dir}")"

          # Submit for notarization
          bundle_id="com.${owner}.ffmpegkit.${output_name}"
          request_uuid="$(submit_for_notarization "${zip_path}" "${bundle_id}")"

          # Wait for notarization to complete
          if wait_for_notarization "${request_uuid}"; then
            echo "✓ Notarization complete for ${output_name}"

            # Staple ticket (macOS only)
            if [[ "${output_name}" == *"macos"* ]] || [[ -z "${output_name}" ]]; then
              staple_notarization_ticket "${xcframework_path}"
            fi
          else
            echo "✗ Notarization failed or timed out for ${output_name}"
            echo "Check log for details: ${LOG_FILE}"
          fi
        fi
      done
    done
  done
fi

# Notarize-only mode
if [[ "${notarize_only}" == true ]]; then
  echo ""
  echo "========================================"
  echo "Notarizing Existing Signed XCFrameworks"
  echo "========================================"

  for bundle in "${BUNDLE_ARRAY[@]}"; do
    for license in "${LICENSE_FLAGS[@]}"; do
      for small in "${SMALL_FLAGS[@]}"; do
        output_name="$(get_output_name "${bundle}" "${license}" "${small}")"
        xcframework_path="${xcframework_output_dir}/${output_name}.xcframework"

        if [[ -d "${xcframework_path}" ]]; then
          echo ""
          echo "Processing: ${output_name}"

          # Verify signature first
          if verify_signature "${xcframework_path}"; then
            # Create ZIP
            zip_path="$(create_zip_for_notarization "${xcframework_path}" "${xcframework_output_dir}")"

            # Submit
            bundle_id="com.${owner}.ffmpegkit.${output_name}"
            request_uuid="$(submit_for_notarization "${zip_path}" "${bundle_id}")"

            # Wait
            if wait_for_notarization "${request_uuid}"; then
              echo "✓ Notarization complete for ${output_name}"
            else
              echo "✗ Notarization failed for ${output_name}"
            fi
          else
            echo "✗ Signature verification failed for ${output_name}"
          fi
        fi
      done
    done
  done
fi

echo ""
echo "========================================"
echo "Code Signing Complete!"
echo "========================================"
echo "Signed XCFrameworks: ${xcframework_output_dir}/"
echo "========================================"

rm -f "${STATE_FILE}"
