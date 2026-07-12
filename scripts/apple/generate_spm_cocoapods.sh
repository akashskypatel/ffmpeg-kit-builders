#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

# Generate Swift Package Manager and CocoaPods publishing files
# This script creates the final Package.swift and FFmpegKit.podspec from templates
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

export BASEDIR="${BASEDIR:-${PWD}}"
export LOG_FILE="${BASEDIR}/build.log"

# Source common functions
source "${BASEDIR}/scripts/function.sh"
source "${BASEDIR}/scripts/supported.sh"

# Parse arguments
# VALID_BUNDLES=("debug" "full" "base" "audio" "video" "video_hw")
LICENSE_FLAGS=("lgpl" "gpl")
SMALL_FLAGS=("" "small")
reset_state=false

for arg; do
  case "${arg}" in
    --bundles=*)
      bundles="${arg#*=}"
      IFS=',' read -ra BUNDLE_ARRAY <<< "${bundles}"
      shift;;
    --help)
      echo "Usage: $0 [--bundles=base,audio,video,video_hw,full,debug] [--help]"
      echo ""
      echo "Options:"
      echo "  --bundles=*   Comma separated (without spaces) list of bundles"
      echo "                Valid bundles: ${VALID_BUNDLES[*]}"
      echo "  --help        Show this help message"
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

# Version information
FFMPEG_KIT_VERSION="$(cat "${BASEDIR}/version")"
GITHUB_USERNAME="$(get_github_owner)"
GITHUB_REPO="$(get_github_repo)"

echo "========================================"
echo "Generating SPM and CocoaPods Files"
echo "========================================"
echo "Version: ${FFMPEG_KIT_VERSION}"
echo "========================================"
echo ""

# Generate Swift Package Manager Package.swift
echo "Generating Package.swift..."

package_swift_template="$(cat "${BASEDIR}/tools/apple/Package.swift.template")"

# Replace version placeholder
package_swift="${package_swift_template//VERSION/${FFMPEG_KIT_VERSION}}"

# Generate checksums for each XCFramework
xcframework_output_dir="${BASEDIR}/prebuilt/apple/xcframeworks"

for bundle in "${BUNDLE_ARRAY[@]}"; do
  for license in "${LICENSE_FLAGS[@]}"; do
    for small in "${SMALL_FLAGS[@]}"; do
      # Determine output name
      bundle_pfx="${bundle}"
      small_pfx=""
      license_pfx=""
      debug_pfx=""
      
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
      
      output_name="ffmpegkit-${bundle_pfx}${small_pfx}${debug_pfx}${license_pfx}"
      xcframework_zip="${xcframework_output_dir}/${output_name}.xcframework.zip"
      
      if [[ -f "${xcframework_zip}" ]]; then
        # Calculate SHA256 checksum
        checksum="$(shasum -a 256 "${xcframework_zip}" | awk '{print $1}')"
        
        # Replace checksum placeholder
        checksum_var="CHECKSUM_$(echo "${output_name}" | tr '[:lower:]-' '[:upper:]_' | tr -d '.')"
        package_swift="${package_swift//CHECKSUM_${checksum_var#CHECKSUM_}/${checksum}}"
        
        echo "  ${output_name}: ${checksum}"
      else
        echo "WARNING: XCFramework zip not found: ${xcframework_zip}"
      fi
    done
  done
done

# Write Package.swift
echo "${package_swift}" > "${BASEDIR}/Package.swift"
echo "Generated: Package.swift"

# Generate CocoaPods FFmpegKit.podspec
echo ""
echo "Generating FFmpegKit.podspec..."

podspec_template="$(cat "${BASEDIR}/tools/apple/FFmpegKit.podspec.template")"

# Replace version placeholder
podspec="${podspec_template//VERSION/${FFMPEG_KIT_VERSION}}"

# Write FFmpegKit.podspec
echo "${podspec}" > "${BASEDIR}/FFmpegKit.podspec"
echo "Generated: FFmpegKit.podspec"

echo ""
echo "========================================"
echo "SPM and CocoaPods files generated!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Review Package.swift and FFmpegKit.podspec"
echo "2. Test locally: cd <test-project> && pod install"
echo "3. Publish to CocoaPods: pod trunk push FFmpegKit.podspec --allow-warnings"
echo "4. Tag release: git tag v${FFMPEG_KIT_VERSION} && git push origin v${FFMPEG_KIT_VERSION}"
echo "========================================"
