#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,SC2329

# Create XCFramework bundles for iOS, iOS Simulator, and macOS
# This script mirrors the Android AAR publishing pipeline for Apple platforms

# save start time
START_TIME=$(date +%s)

set -e

# Update sudo timestamp to avoid interruption later
echo "Requesting administrative privileges..."
sudo -v

# State management configuration
export BASEDIR="${BASEDIR:-${PWD}}"
export LOG_FILE="${BASEDIR}/build.log"
STATE_DIR="${STATE_DIR:-${BASEDIR}/.ffmpeg-kit-build-xcframework-state}"
STATE_FILE="${STATE_DIR}/build_xcframework.state"
LOCK_FILE="${STATE_DIR}/build_xcframework.lock"

# Source common functions
source "${BASEDIR}/scripts/function.sh"

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
  echo "Error: Another build process is running (lock file exists: ${LOCK_FILE})"
  echo "If you're sure no other build is running, remove the lock file manually."
  exit 1
fi

# Create lock file
touch "${LOCK_FILE}"

# Keep the timestamp alive in the background for long-running builds
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Parse arguments
VALID_TYPES=("debug" "full" "base" "audio" "video" "video_hw")
VALID_PLATFORMS=("ios" "macos")
VALID_PLATFORM_ARCHS=("ios-aarch64" "iphonesimulator-aarch64" "macos-aarch64" "macos-x86_64")
VALID_LICENSES=("lgpl" "gpl")
VALID_SMALL_FLAGS=("small" "")
REMOTE_RELEASE=true
SMALL_FLAGS=("small" "")
build_type="Release"
reset_state=false
publish_spm=false
publish_cocoapods=false
enable_signing=false
signing_identity=""
team_id=""
apple_id=""
app_specific_password=""
skip_notarization=false
declare -A PLATFORM_ARCHS
create_framework=true
create_bundle=true
create_release=true

# Add a single platform-arch entry to PLATFORMS, skipping duplicates
_add_platform_arch() {
  local key="${1}" value="${2}"
  if [[ -z "${PLATFORM_ARCHS["$key"]}" ]]; then
    PLATFORM_ARCHS["$key"]="${value}"
  elif [[ ",${PLATFORM_ARCHS["$key"]}," != *",${value},"* ]]; then
    PLATFORM_ARCHS["$key"]="${PLATFORM_ARCHS["$key"]},${value}"
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
        # add iphonesimulator if platform is ios — store with 'sim:' prefix to avoid dedup with ios archs
        if [[ "$p" == "ios" ]]; then
          for valid_pa in "${VALID_PLATFORM_ARCHS[@]}"; do
            if [[ "${valid_pa}" == "iphonesimulator-"* ]]; then
              _add_platform_arch "ios" "sim:${valid_pa#*-}"
            fi
          done
        fi
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
    local plat="${p%-*}"
    local arch="${p#*-}"
    # Map iphonesimulator to 'ios' platform key with 'sim:' prefix for combined XCFramework
    if [[ "$plat" == "iphonesimulator" ]]; then
      plat="ios"
      arch="sim:${arch}"
    fi
    _add_platform_arch "${plat}" "${arch}"
  done
}

parse_bundles() {
  bundles="${1}"
  # Ensure bundles is populated if empty
  if [[ -z "${bundles}" ]]; then
    bundles=$(IFS=,; echo "${VALID_TYPES[*]}")
  fi
  
  IFS=',' read -ra BUNDLE_ARRAY <<< "${bundles}"
  for b in "${BUNDLE_ARRAY[@]}"; do
    # Skip empty elements resulting from trailing/double commas
    [[ -z "$b" ]] && continue
    
    # Validate against whitelist
    local valid=false
    for valid_b in "${VALID_TYPES[@]}"; do
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

get_ffmpeg_kit_dir() {
  local platform="$1"
  local arch="$2"
  local bundle="$3"
  local license="$4"
  local small="$5"
  
  local bundle_pfx=""
  local small_pfx=""
  local license_pfx=""
  local debug_pfx=""
  
  if [[ "${bundle}" == "debug" ]]; then
    bundle_pfx="-base"
    debug_pfx="-debug"
  else
    bundle_pfx="-${bundle}"
  fi
  
  if [[ "${small}" == "small" ]]; then
    small_pfx="-small"
  fi
  
  if [[ "${license}" == "gpl" ]]; then
    license_pfx="-gpl"
  fi
  
  echo "${BASEDIR}/prebuilt/${platform}-${arch}/ffmpeg-kit${bundle_pfx}-${platform}-${arch}-shared${debug_pfx}${small_pfx}${license_pfx}"
}

get_output_name() {
  local bundle="$1"
  local license="$2"
  local small="$3"
  local platform="$4"

  local bundle_pfx="${bundle}"
  local small_pfx=""
  local license_pfx=""
  local debug_pfx=""
  local platform_pfx=""

  if [[ "${bundle}" == "debug" ]]; then
    bundle_pfx="base"
    debug_pfx="-debug"
  fi

  if [[ "${small}" == "small" && -z "${debug_pfx}" ]]; then
    small_pfx="-small"
  fi

  if [[ "${license}" == "gpl" ]]; then
    license_pfx="-gpl"
  else
    license_pfx="-lgpl"
  fi

  # Add platform suffix to distinguish per-platform XCFrameworks
  if [[ -n "${platform}" ]]; then
    platform_pfx="-${platform}"
  fi

  echo "bundle-${bundle_pfx}${platform_pfx}-universal${small_pfx}${debug_pfx}${license_pfx}"
}

create_xcframework() {
  local bundle="$1"
  local license="$2"
  local small="$3"  
  local output_name="$4"
  local xcframework_output_dir="$5"
  local target_platform="$6"

  local lib_ext=".dylib"

  # Collect platform-arch combinations for the target platform only
  declare -a framework_inputs=()

  # Special handling for macOS: collect both archs to create universal binary
  declare -A macos_lib_dirs       # lib_dir paths per arch
  local macos_headers_dir=""

  # Only process the target platform
  local archs_for_platform="${PLATFORM_ARCHS[$target_platform]}"
  if [[ -z "$archs_for_platform" ]]; then
    echo "WARNING: No architectures found for platform: ${target_platform}"
    return 0
  fi

  # Helper function: copy all dylibs from lib_dir to dest_dir and fix rpaths
  copy_dylibs_and_fix_rpaths() {
    local src_lib_dir="$1"
    local dest_dir="$2"

    # Copy all dylibs (excluding pkgconfig and other non-dylib files)
    for dylib in "${src_lib_dir}"/*.dylib; do
      [[ -f "$dylib" ]] || continue
      local dylib_name="$(basename "$dylib")"
      cp -f "$dylib" "${dest_dir}/${dylib_name}"

      # Fix the install name to use @rpath
      install_name_tool -id "@rpath/${dylib_name}" "${dest_dir}/${dylib_name}" 2>/dev/null || true
      codesign --sign - --force "${dest_dir}/${dylib_name}" 2>/dev/null || true
    done

    # Pass 2: Fix rpath references in all copied dylibs
    for dylib in "${dest_dir}"/*.dylib; do
      echo "Fixing rpath references in: $(basename "$dylib")"
      [[ -f "$dylib" ]] || continue
      local dylib_name="$(basename "$dylib")"

      local refs
      refs="$(otool -L "$dylib" 2>/dev/null | tail -n +2 | awk '{print $1}')"
      for ref_path in $refs; do
        [[ "$ref_path" != /* && "$ref_path" != @rpath/* ]] && continue
        [[ "$ref_path" == */System/* ]] && continue
        [[ "$ref_path" == */usr/lib/* ]] && continue
        local ref_name
        ref_name="$(basename "$ref_path")"
        local canonical_ref_name=""
        canonical_ref_name="$(canonicalize_bundled_ref_name "${ref_name}" "${dest_dir}" || true)"
        if [[ -n "${canonical_ref_name}" ]]; then
          [[ "$ref_path" == "@rpath/${canonical_ref_name}" ]] && continue
          if [[ "${canonical_ref_name}" != "${ref_name}" ]]; then
            echo "  Fix (alias): ${dylib_name} references ${ref_name} -> ${canonical_ref_name}"
          fi
          install_name_tool -change "$ref_path" "@rpath/${canonical_ref_name}" "$dylib" 2>/dev/null || true
          codesign --sign - --force "$dylib" 2>/dev/null || true
        fi
      done
    done

    # Pass 3: Strip baked-in rpaths, add @loader_path
    for dylib in "${dest_dir}"/*.dylib; do
      [[ -f "$dylib" ]] || continue
      fix_dylib_rpaths "$dylib"
    done
  }

  # Helper function: create universal dylib from two architecture-specific dylibs
  create_universal_dylib() {
    local lib_name="$1"
    local arch1_dir="$2"
    local arch2_dir="$3"
    local output_dir="$4"

    local lib1="${arch1_dir}/${lib_name}"
    local lib2="${arch2_dir}/${lib_name}"

    if [[ -f "$lib1" && -f "$lib2" ]]; then
      lipo -create -output "${output_dir}/${lib_name}" "$lib1" "$lib2"
      install_name_tool -id "@rpath/${lib_name}" "${output_dir}/${lib_name}" 2>/dev/null || true
      codesign --sign - --force "${output_dir}/${lib_name}" 2>/dev/null || true
      # Fix rpath references
      for dylib in "${output_dir}"/*.dylib; do
        [[ -f "$dylib" ]] || continue
        local dylib_name="$(basename "$dylib")"
        [[ "$dylib_name" == "$lib_name" ]] && continue
        if otool -L "${output_dir}/${lib_name}" 2>/dev/null | grep -q "${dylib_name}"; then
          install_name_tool -change "${arch1_dir}/${dylib_name}" "@rpath/${dylib_name}" "${output_dir}/${lib_name}" 2>/dev/null || true
          install_name_tool -change "${arch2_dir}/${dylib_name}" "@rpath/${dylib_name}" "${output_dir}/${lib_name}" 2>/dev/null || true
          codesign --sign - --force "${output_dir}/${lib_name}" 2>/dev/null || true
        fi
      done
    elif [[ -f "$lib1" ]]; then
      cp -f "$lib1" "${output_dir}/${lib_name}"
      install_name_tool -id "@rpath/${lib_name}" "${output_dir}/${lib_name}" 2>/dev/null || true
      codesign --sign - --force "${output_dir}/${lib_name}" 2>/dev/null || true
    elif [[ -f "$lib2" ]]; then
      cp -f "$lib2" "${output_dir}/${lib_name}"
      install_name_tool -id "@rpath/${lib_name}" "${output_dir}/${lib_name}" 2>/dev/null || true
      codesign --sign - --force "${output_dir}/${lib_name}" 2>/dev/null || true
    fi
  }

  # Helper: strip all baked-in rpaths and replace with @loader_path
  fix_dylib_rpaths() {
    local dylib="$1"
    while IFS= read -r rpath; do
      [[ -z "$rpath" ]] && continue
      install_name_tool -delete_rpath "$rpath" "$dylib" 2>/dev/null || true
      codesign --sign - --force "$dylib" 2>/dev/null || true
    done < <(otool -l "$dylib" 2>/dev/null | awk '/cmd LC_RPATH/{found=1} found && /path /{print $2; found=0}')
    install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
    codesign --sign - --force "$dylib" 2>/dev/null || true
  }

  canonicalize_bundled_ref_name() {
    local ref_name="$1"
    local bundle_dir="$2"
    local base_name="${ref_name%.dylib}"

    if [[ "$base_name" =~ ^(.+)\.([0-9]+)$ ]]; then
      local unversioned_name="${BASH_REMATCH[1]}.dylib"
      if [[ -f "${bundle_dir}/${unversioned_name}" ]]; then
        printf '%s\n' "${unversioned_name}"
        return 0
      fi
    fi

    if [[ "$base_name" == "libiomp5" || "$base_name" == "libomp5" || "$base_name" == "libomp" ]]; then
      if [[ -f "${bundle_dir}/libomp.dylib" ]]; then
        printf '%s\n' "libomp.dylib"
        return 0
      fi
    fi

    if [[ -f "${bundle_dir}/${ref_name}" ]]; then
      printf '%s\n' "${ref_name}"
      return 0
    fi

    return 1
  }

  IFS=',' read -ra arch_array <<< "$archs_for_platform"
  for arch in "${arch_array[@]}"; do
    # Strip 'sim:' prefix and determine actual platform
    local is_simulator=false
    local clean_arch="${arch}"
    if [[ "${arch}" == sim:* ]]; then
      is_simulator=true
      clean_arch="${arch#sim:}"
    fi

    local actual_platform="${target_platform}"
    if [[ "${target_platform}" == "ios" && "$is_simulator" == true ]]; then
      actual_platform="iphonesimulator"
    fi

    local ffmpeg_kit_dir="$(get_ffmpeg_kit_dir "${actual_platform}" "${clean_arch}" "${bundle}" "${license}" "${small}")"

    if [[ ! -d "${ffmpeg_kit_dir}" ]]; then
      echo "WARNING: FFmpegKit directory not found: ${ffmpeg_kit_dir}"
      continue
    fi

    local lib_dir="${ffmpeg_kit_dir}/lib"
    local include_dir="${ffmpeg_kit_dir}/include"

    if [[ ! -f "${lib_dir}/libffmpegkit${lib_ext}" ]]; then
      echo "WARNING: libffmpegkit${lib_ext} not found in ${lib_dir}"
      continue
    fi

    # For macOS, collect the directories to create universal binary later
    if [[ "${target_platform}" == "macos" ]]; then
      if [[ "${arch}" == "aarch64" ]]; then
        macos_lib_dirs["aarch64"]="${lib_dir}"
        macos_headers_dir="${include_dir}"
      elif [[ "${arch}" == "x86_64" ]]; then
        macos_lib_dirs["x86_64"]="${lib_dir}"
        macos_headers_dir="${include_dir}"
      fi
      continue
    fi

    # For iOS/iOS Simulator, create individual framework structures
    local temp_framework_dir="${xcframework_output_dir}/.tmp/${actual_platform}-${clean_arch}"
    mkdir -p "${temp_framework_dir}/Headers"

    # Copy all dylibs and fix rpaths
    copy_dylibs_and_fix_rpaths "${lib_dir}" "${temp_framework_dir}"

    # Copy headers
    if [[ -d "${include_dir}" ]]; then
      cp -r "${include_dir}/." "${temp_framework_dir}/Headers/"
    fi

    framework_inputs+=("-library" "${temp_framework_dir}/libffmpegkit${lib_ext}" "-headers" "${temp_framework_dir}/Headers")
  done

  # Handle macOS: create universal binaries if both archs are present
  if [[ "${target_platform}" == "macos" ]]; then
    local macos_aarch64_dir="${macos_lib_dirs[aarch64]:-}"
    local macos_x86_64_dir="${macos_lib_dirs[x86_64]:-}"

    if [[ -n "${macos_aarch64_dir}" || -n "${macos_x86_64_dir}" ]]; then
      local temp_framework_dir="${xcframework_output_dir}/.tmp/macos-universal"
      mkdir -p "${temp_framework_dir}/Headers"

      # Determine which source directory to use for dylib enumeration
      local src_lib_dir=""
      if [[ -n "${macos_aarch64_dir}" ]]; then
        src_lib_dir="${macos_aarch64_dir}"
      else
        src_lib_dir="${macos_x86_64_dir}"
      fi

      # Pass 1: Copy/lipo all dylibs and frameworks
      echo "Bundling dylibs for macOS..."
      for dylib in "${src_lib_dir}"/*.dylib "${src_lib_dir}"/*.framework; do
        [[ -e "$dylib" ]] || continue
        local item_name
        item_name="$(basename "$dylib")"
        local item1="${macos_aarch64_dir}/${item_name}"
        local item2="${macos_x86_64_dir}/${item_name}"

        # Handle frameworks differently - just copy them
        if [[ -d "$dylib" ]]; then
          if [[ -d "$item1" ]]; then
            cp -rf "$item1" "${temp_framework_dir}/${item_name}"
          elif [[ -d "$item2" ]]; then
            cp -rf "$item2" "${temp_framework_dir}/${item_name}"
          fi
          continue
        fi

        if [[ -f "$item1" && -f "$item2" ]]; then
          echo "  Lipo: ${item_name}"
          lipo -create -output "${temp_framework_dir}/${item_name}" "$item1" "$item2"
        elif [[ -f "$item1" ]]; then
          echo "  Copy (arm64 only): ${item_name}"
          cp -f "$item1" "${temp_framework_dir}/${item_name}"
        elif [[ -f "$item2" ]]; then
          echo "  Copy (x86_64 only): ${item_name}"
          cp -f "$item2" "${temp_framework_dir}/${item_name}"
        fi

        # Set install name
        install_name_tool -id "@rpath/${item_name}" "${temp_framework_dir}/${item_name}" 2>/dev/null || true
        codesign --sign - --force "${temp_framework_dir}/${item_name}" 2>/dev/null || true
      done

      # Pass 2: Fix rpath references in all dylibs
      echo "Fixing rpath references..."
      for dylib in "${temp_framework_dir}"/*.dylib; do
        echo "Fixing rpath references in: $(basename "$dylib")"
        [[ -f "$dylib" ]] || continue
        local dylib_name="$(basename "$dylib")"

        # Get all referenced dylibs and fix their paths
        local refs
        refs="$(otool -L "$dylib" 2>/dev/null | tail -n +2 | awk '{print $1}')"
        for ref_path in $refs; do
          [[ "$ref_path" != /* && "$ref_path" != @rpath/* ]] && continue  # Skip non-bundled paths
          [[ "$ref_path" == */System/* ]] && continue  # Skip system frameworks
          [[ "$ref_path" == */usr/lib/* ]] && continue  # Skip system libs
          [[ "$ref_path" == */lib/libSystem* ]] && continue  # Skip libSystem
          local ref_name
          ref_name="$(basename "$ref_path")"
          local canonical_ref_name=""
          canonical_ref_name="$(canonicalize_bundled_ref_name "${ref_name}" "${temp_framework_dir}" || true)"
          if [[ -n "${canonical_ref_name}" ]]; then
            [[ "$ref_path" == "@rpath/${canonical_ref_name}" ]] && continue
            if [[ "${canonical_ref_name}" == "${ref_name}" ]]; then
              echo "  Fix: ${dylib_name} references ${ref_name}"
            else
              echo "  Fix (alias): ${dylib_name} references ${ref_name} -> ${canonical_ref_name}"
            fi
            install_name_tool -change "$ref_path" "@rpath/${canonical_ref_name}" "$dylib" 2>/dev/null || true
            codesign --sign - --force "$dylib" 2>/dev/null || true
          fi
        done
      done

      # Pass 3: Strip baked-in rpaths, add @loader_path
      echo "Fixing rpaths..."
      for dylib in "${temp_framework_dir}"/*.dylib; do
        [[ -f "$dylib" ]] || continue
        fix_dylib_rpaths "$dylib"
      done

      # Copy headers
      if [[ -n "${macos_headers_dir}" && -d "${macos_headers_dir}" ]]; then
        cp -r "${macos_headers_dir}/." "${temp_framework_dir}/Headers/"
      fi

      framework_inputs+=("-library" "${temp_framework_dir}/libffmpegkit${lib_ext}" "-headers" "${temp_framework_dir}/Headers")
    fi
  fi

  if [[ ${#framework_inputs[@]} -eq 0 ]]; then
    echo "ERROR: No valid libraries found to create XCFramework for ${target_platform}"
    return 1
  fi

  # Create XCFramework
  echo "Creating XCFramework: ${xcframework_output_dir}/${output_name}.xcframework"

  # Always remove existing XCFramework to ensure clean build
  if [[ -d "${xcframework_output_dir}/${output_name}.xcframework" ]]; then
    echo "Removing existing XCFramework to ensure clean build: ${output_name}.xcframework"
    rm -rf "${xcframework_output_dir}/${output_name}.xcframework"
    if [[ -d "${xcframework_output_dir}/${output_name}.xcframework" ]]; then
      echo "ERROR: Failed to remove existing XCFramework"
      return 1
    fi
  fi

  xcodebuild -create-xcframework \
    "${framework_inputs[@]}" \
    -output "${xcframework_output_dir}/${output_name}.xcframework"

  if [[ $? -eq 0 ]]; then
    echo "SUCCESS: Created XCFramework: ${output_name}.xcframework"

    # Copy dependency dylibs into the XCFramework slice (xcodebuild only includes the -library dylib)
    if [[ -d "${xcframework_output_dir}/.tmp" ]]; then
      find "${xcframework_output_dir}/.tmp" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r tmp_dir; do
        local slice_name
        slice_name="$(basename "$tmp_dir")"
        # Map tmp directory names to XCFramework slice names
        local xc_slice_name="${slice_name}"
        if [[ "${slice_name}" == "macos-universal" ]]; then
          xc_slice_name="macos-arm64_x86_64"
        elif [[ "${slice_name}" == ios-* ]]; then
          xc_slice_name="${slice_name}"
        fi
        local xc_slice="${xcframework_output_dir}/${output_name}.xcframework/${xc_slice_name}"
        if [[ -d "$xc_slice" ]]; then
          # Pass 1: Copy dylibs
          find "${tmp_dir}" -maxdepth 1 -name "*.dylib" -type f | while IFS= read -r dylib; do
            local dylib_name
            dylib_name="$(basename "$dylib")"
            # Skip the main library (already included by xcodebuild)
            if [[ "$dylib_name" != "libffmpegkit${lib_ext}" ]]; then
              echo "  Bundling dependency: ${dylib_name}"
              cp -f "$dylib" "${xc_slice}/${dylib_name}"
            fi
          done
          # Pass 2: Fix versioned -> unversioned rpath references in the slice
          for slice_dylib in "${xc_slice}"/*.dylib; do
            echo "Fixing rpath references in: $(basename "$slice_dylib")"
            [[ -f "$slice_dylib" ]] || continue
            local sdname
            sdname="$(basename "$slice_dylib")"
            local srefs
            srefs="$(otool -L "$slice_dylib" 2>/dev/null | tail -n +2 | awk '{print $1}')"
            for sref in $srefs; do
              [[ "$sref" == @rpath/* ]] || continue
              local sref_name
              sref_name="$(basename "$sref")"
              local canonical_ref_name=""
              canonical_ref_name="$(canonicalize_bundled_ref_name "${sref_name}" "${xc_slice}" || true)"
              if [[ -n "${canonical_ref_name}" && "${canonical_ref_name}" != "${sref_name}" ]]; then
                echo "  Fix (alias): ${sdname} references ${sref_name} -> ${canonical_ref_name}"
                install_name_tool -change "@rpath/${sref_name}" "@rpath/${canonical_ref_name}" "$slice_dylib" 2>/dev/null || true
                codesign --sign - --force "$slice_dylib" 2>/dev/null || true
              fi
            done
          done
          # Pass 3: Fix rpaths in slice dylibs
          for slice_dylib in "${xc_slice}"/*.dylib; do
            [[ -f "$slice_dylib" ]] || continue
            fix_dylib_rpaths "$slice_dylib"
          done
        fi
      done
      # Clean up temp directories
      rm -rf "${xcframework_output_dir}/.tmp"
    fi

    return 0
  else
    echo "ERROR: Failed to create XCFramework"
    rm -rf "${xcframework_output_dir}/.tmp"
    return 1
  fi
}

create_static_xcframework() {
  local bundle="$1"
  local license="$2"
  local small="$3"
  local output_name="$4"
  local xcframework_output_dir="$5"

  local lib_ext=".a"

  # Collect all platform-arch combinations
  declare -a framework_inputs=()

  # Special handling for macOS: collect both archs to create universal binary
  local macos_arm64_dir=""
  local macos_x86_64_dir=""
  local macos_headers_dir=""

  for platform in "${!PLATFORM_ARCHS[@]}"; do
    IFS=',' read -ra arch_array <<< "${PLATFORM_ARCHS[$platform]}"
    for arch in "${arch_array[@]}"; do
      local ffmpeg_kit_dir="$(get_ffmpeg_kit_dir "${platform}" "${arch}" "${bundle}" "${license}" "${small}")"

      if [[ ! -d "${ffmpeg_kit_dir}" ]]; then
        echo "WARNING: FFmpegKit directory not found: ${ffmpeg_kit_dir}"
        continue
      fi

      local lib_dir="${ffmpeg_kit_dir}/lib"
      local include_dir="${ffmpeg_kit_dir}/include"

      if [[ ! -f "${lib_dir}/libffmpegkit${lib_ext}" ]]; then
        echo "WARNING: libffmpegkit${lib_ext} not found in ${lib_dir}"
        continue
      fi

      # For macOS, collect the directories to create universal binary later
      if [[ "${platform}" == "macos" ]]; then
        if [[ "${arch}" == "aarch64" ]]; then
          macos_arm64_dir="${lib_dir}/libffmpegkit${lib_ext}"
          macos_headers_dir="${include_dir}"
        elif [[ "${arch}" == "x86_64" ]]; then
          macos_x86_64_dir="${lib_dir}/libffmpegkit${lib_ext}"
          macos_headers_dir="${include_dir}"
        fi
        # Skip adding to framework_inputs now, we'll handle macOS separately
        continue
      fi

      # Create a temporary directory for non-macOS platforms
      local temp_dir="${xcframework_output_dir}/.tmp/${platform}-${arch}"
      mkdir -p "${temp_dir}/Headers"

      # Copy library
      cp -f "${lib_dir}/libffmpegkit${lib_ext}" "${temp_dir}/libffmpegkit${lib_ext}"

      # Copy headers
      if [[ -d "${include_dir}" ]]; then
        cp -r "${include_dir}/." "${temp_dir}/Headers/"
      fi

      framework_inputs+=("-library" "${temp_dir}/libffmpegkit${lib_ext}" "-headers" "${temp_dir}/Headers")
    done
  done

  # Handle macOS: create universal binary if both archs are present
  if [[ -n "${macos_arm64_dir}" || -n "${macos_x86_64_dir}" ]]; then
    local temp_dir="${xcframework_output_dir}/.tmp/macos-universal"
    mkdir -p "${temp_dir}/Headers"

    if [[ -n "${macos_arm64_dir}" && -n "${macos_x86_64_dir}" ]]; then
      # Create universal binary with lipo
      echo "Creating universal macOS binary (static)..."
      lipo -create -output "${temp_dir}/libffmpegkit${lib_ext}" \
        "${macos_arm64_dir}" "${macos_x86_64_dir}"
    elif [[ -n "${macos_arm64_dir}" ]]; then
      cp -f "${macos_arm64_dir}" "${temp_dir}/libffmpegkit${lib_ext}"
    else
      cp -f "${macos_x86_64_dir}" "${temp_dir}/libffmpegkit${lib_ext}"
    fi

    # Copy headers
    if [[ -n "${macos_headers_dir}" && -d "${macos_headers_dir}" ]]; then
      cp -r "${macos_headers_dir}/." "${temp_dir}/Headers/"
    fi

    framework_inputs+=("-library" "${temp_dir}/libffmpegkit${lib_ext}" "-headers" "${temp_dir}/Headers")
  fi

  if [[ ${#framework_inputs[@]} -eq 0 ]]; then
    echo "ERROR: No valid libraries found to create static XCFramework for ${target_platform}"
    return 1
  fi

  # Create XCFramework
  echo "Creating static XCFramework: ${xcframework_output_dir}/${output_name}.xcframework"

  # Always remove existing XCFramework to ensure clean build
  if [[ -d "${xcframework_output_dir}/${output_name}.xcframework" ]]; then
    echo "Removing existing XCFramework to ensure clean build: ${output_name}.xcframework"
    rm -rf "${xcframework_output_dir}/${output_name}.xcframework"
    if [[ -d "${xcframework_output_dir}/${output_name}.xcframework" ]]; then
      echo "ERROR: Failed to remove existing XCFramework"
      return 1
    fi
  fi

  xcodebuild -create-xcframework \
    "${framework_inputs[@]}" \
    -output "${xcframework_output_dir}/${output_name}.xcframework"

  if [[ $? -eq 0 ]]; then
    echo "SUCCESS: Created static XCFramework: ${output_name}.xcframework"

    # Clean up temp directories
    rm -rf "${xcframework_output_dir}/.tmp"

    return 0
  else
    echo "ERROR: Failed to create static XCFramework"
    rm -rf "${xcframework_output_dir}/.tmp"
    return 1
  fi
}

# Argument parsing
for arg; do
  case "${arg}" in
    --platform=*)
      parse_platforms "${arg#*=}"
      shift;;
    --bundle=*)
      parse_bundles "${arg#*=}"
      shift;;
    --license=*)
      parse_licenses "${arg#*=}"
      shift;;
    --reset)
      reset_state=true
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
    --create-framework)
      create_bundle=false
      create_release=false
      create_framework=true
      shift;;
    --create-bundle)
      create_release=false
      create_framework=false
      create_bundle=true
      shift;;
    --create-release)
      create_framework=false
      create_bundle=false
      create_release=true
      shift;;
    --help)
      echo "Usage: $0 [--platform=ios-aarch64,iphonesimulator-aarch64,macos-aarch64,macos-x86_64] [--bundle=base,audio,video,video_hw,full,debug] [--license=gpl,lgpl] [--reset] [--help]"
      echo ""
      echo "Options:"
      echo "  --platform=*        Comma separated (without spaces) list of platforms or platform-arch pairs."
      echo "                      A plain platform name expands to all valid archs for that platform."
      echo "                        e.g. --platform=ios              → ios-aarch64,iphonesimulator-aarch64"
      echo "                        e.g. --platform=ios,macos-x86_64 → ios (all archs) + macos-x86_64"
      echo "                      Valid platforms (expands to all archs): ${VALID_PLATFORMS[*]}"
      echo "                      Valid platform-arch combinations:       ${VALID_PLATFORM_ARCHS[*]}"
      echo "                      Note: iphonesimulator is automatically added when ios is specified"
      echo "  --bundle=*          Comma separated (without spaces) list of bundles to build"
      echo "                      Valid bundles: ${VALID_TYPES[*]}"
      echo "  --license=*         Comma separated (without spaces) list of licenses to build"
      echo "                      Valid licenses: ${VALID_LICENSES[*]}"
      echo "  --small             Build with small flags (reduces binary size)."
      echo "  --not-small         Build without small flag."
      echo "  --both              Build both small and full versions (default)"
      echo "  --reset             Reset build state and start from beginning"
      echo "  --remote            Publish release asset to remote repository"
      echo "  --local             Build locally instead of using remote releases"
      echo "                      Note: Not including one of below flags will create all of artifacts: framework, bundle, and release"
      echo "                      Do not specify if you want to create all artifacts."
      echo "  --create-framework  Create framework from built libraries, excludes creating bundle and release"
      echo "  --create-bundle     Create bundle from built libraries, excludes creating framework and release"
      echo "  --create-release    Create release from built libraries, excludes creating bundle and framework"
      echo "  --help              Show this help message"
      echo ""
      echo "State file location: ${STATE_FILE}"
      exit 0;;
    *)
      echo "Invalid argument: ${arg}"
      echo "Use --help for usage information"
      exit 1;;
  esac
done

# Check if the number of elements is 0
if [[ ${#PLATFORM_ARCHS[@]} -eq 0 ]]; then
  parse_platforms ""
fi

if [[ ${#BUNDLE_ARRAY[@]} -eq 0 ]]; then
  parse_bundles ""
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

# Version information
FFMPEG_KIT_VERSION="$(cat "${BASEDIR}/version")"
GITHUB_USERNAME="$(get_github_owner)"
GITHUB_REPO="$(get_github_repo)"

echo "========================================" | tee -a "${LOG_FILE}"
echo "XCFramework Build Pipeline" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"
echo "Version: ${FFMPEG_KIT_VERSION}" | tee -a "${LOG_FILE}"
echo "Bundles: ${bundles}" | tee -a "${LOG_FILE}"
echo "Platforms: ${!PLATFORM_ARCHS[*]}" | tee -a "${LOG_FILE}"
echo "Small flags: ${SMALL_FLAGS[*]}" | tee -a "${LOG_FILE}"
echo "Licenses: ${LICENSE_ARRAY[*]}" | tee -a "${LOG_FILE}"
echo "Output: ${BASEDIR}/prebuilt/apple/xcframeworks/" | tee -a "${LOG_FILE}"
echo "Create framework artifact: ${create_framework}" | tee -a "${LOG_FILE}"
echo "Create bundle artifact: ${create_bundle}" | tee -a "${LOG_FILE}"
echo "Create release artifact: ${create_release}" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

# Create output directory
xcframework_output_dir="${BASEDIR}/prebuilt/apple/xcframeworks"
mkdir -p "${xcframework_output_dir}"

# Define all build steps - create per-platform XCFrameworks
declare -a BUILD_STEPS

create_framework_artifact() {
  platform="$1"
  bundle="$2"
  license="$3"
  small="$4"

  output_name="$(get_output_name "${bundle}" "${license}" "${small}" "${platform}")"
  build_step="create_xcframework '${bundle}' '${license}' '${small}' '${output_name}' '${xcframework_output_dir}' '${platform}'"
  BUILD_STEPS+=("${build_step}")
}

create_bundle_artifact() {
  platform="$1"
  bundle="$2"
  license="$3"
  small="$4"

  output_name="$(get_output_name "${bundle}" "${license}" "${small}" "${platform}")"
  xcframework_path="${xcframework_output_dir}/${output_name}.xcframework"
  # Create a zip archive
  release_asset="${xcframework_output_dir}/${output_name}.xcframework.zip"
  build_step="cd '${xcframework_output_dir}' && zip -r -q '${release_asset}' '${output_name}.xcframework' && chmod 777 '${release_asset}' && cd '${BASEDIR}'"
  BUILD_STEPS+=("${build_step}")
}

create_release_artifact() {
  platform="$1"
  bundle="$2"
  license="$3"
  small="$4"

  output_name="$(get_output_name "${bundle}" "${license}" "${small}" "${platform}")"
  xcframework_path="${xcframework_output_dir}/${output_name}.xcframework"
  release_asset="${xcframework_output_dir}/${output_name}.xcframework.zip"
  if [[ "${REMOTE_RELEASE}" == "true" ]]; then
    build_step="export host_platform='${platform}' && create_github_release '${release_asset}' && rm -rf '${xcframework_path}'"
    BUILD_STEPS+=("${build_step}")
  fi
}

for platform in "${!PLATFORM_ARCHS[@]}"; do
  for bundle in "${BUNDLE_ARRAY[@]}"; do
    for license in "${LICENSE_ARRAY[@]}"; do
      for small in "${SMALL_FLAGS[@]}"; do
        # skip small flag or lgpl flag for 'debug'
        if [[ "${bundle}" == "debug" && ("${small}" == "small") ]]; then
          continue
        fi
        output_name="$(get_output_name "${bundle}" "${license}" "${small}" "${platform}")"
        xcframework_path="${xcframework_output_dir}/${output_name}.xcframework"
        release_asset="${xcframework_output_dir}/${output_name}.xcframework.zip"
        [[ $create_framework == "true" ]] && create_framework_artifact "$platform" "$bundle" "$license" "$small" || true
        [[ $create_bundle == "true" ]] && create_bundle_artifact "$platform" "$bundle" "$license" "$small" || true
        [[ $create_release == "true" ]] && create_release_artifact "$platform" "$bundle" "$license" "$small" || true
      done
    done
  done
done

# Calculate progress
total_steps=${#BUILD_STEPS[@]}
completed_steps=0
for _step in "${BUILD_STEPS[@]}"; do
  is_completed "${_step}" && (( completed_steps++ )) || true
done

echo "Total steps: ${total_steps}" | tee -a "${LOG_FILE}"
echo "Completed steps: ${completed_steps}" | tee -a "${LOG_FILE}"
echo "Remaining steps: $((total_steps - completed_steps))" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

# Execute all build steps
current_step=0
for step in "${BUILD_STEPS[@]}"; do
  current_step=$((current_step + 1))
  echo "========================================" | tee -a "${LOG_FILE}"
  echo "Step ${current_step}/${total_steps}" | tee -a "${LOG_FILE}"
  echo "========================================" | tee -a "${LOG_FILE}"
  
  execute_build "${step}"
  
  echo "" | tee -a "${LOG_FILE}"
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
echo "All XCFramework builds completed successfully!" | tee -a "${LOG_FILE}"
echo "Elapsed time: ${ELAPSED_TIME_HMS}" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"
echo "Output directory: ${xcframework_output_dir}" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"

rm -rf "${STATE_FILE}"
