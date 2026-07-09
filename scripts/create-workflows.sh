#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")/.github/workflows"

source "$SCRIPT_DIR/function.sh"
source "$SCRIPT_DIR/supported.sh"

OWNER="$(get_github_owner)"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
	echo "Workflow directory not found: $WORKFLOW_DIR" >&2
	exit 1
fi

write_linux_orchestrator() {
	local runner_platform="$1"
	local platform_list="$2"
	local arch_list="$3"
	local file="$WORKFLOW_DIR/build_on_${runner_platform}.yaml"
	local tmp_file
	tmp_file="$(mktemp "${file}.tmp.XXXXXX")"

	cat >"$tmp_file" <<YAML
name: build_on_${runner_platform}

on:
  workflow_dispatch:
    inputs:
      target_platforms:
        description: "Comma-separated target platforms this runner can build"
        required: true
        default: "${platform_list}"
        type: string
      target_archs:
        description: "Comma-separated target architectures to try for each selected platform"
        required: true
        default: "${arch_list}"
        type: string
      force:
        description: "Force rebuild instead of using existing self release artifacts"
        required: false
        default: false
        type: boolean
      build_from:
        description: "Specify step as starting point. Must be build_*"
        required: false
        default: ""
        type: string
      build_only:
        description: "Comma-separated build_* dependency steps to build"
        required: false
        default: ""
        type: string
      bundles:
        description: "Comma-separated target ffmpeg-kit bundles to build"
        required: false
        default: "${bundles}"
        type: string
      build_ffmpeg:
        description: "Build ffmpeg binaries"
        required: false
        default: false
        type: boolean
      build_bundle:
        description: "Build ffmpeg-kit binaries and bundle"
        required: false
        default: false
        type: boolean

env:
  GH_TOKEN: \${{ github.token }}
  WORKFLOW_FORCE_SELF: \${{ inputs.force }}
  WORKFLOW_BUILD_FROM: \${{ inputs.build_from }}
  WORKFLOW_BUILD_ONLY: \${{ inputs.build_only }}
  WORKFLOW_TARGET_PLATFORMS: \${{ inputs.target_platforms }}
  WORKFLOW_TARGET_ARCHS: \${{ inputs.target_archs }}
  WORKFLOW_BUILD_FFMPEG: \${{ inputs.build_ffmpeg }}
  WORKFLOW_BUILD_BUNDLE: \${{ inputs.build_bundle }}
  WORKFLOW_CURRENT_STEP: ""
  WORKFLOW_SEEN_STEPS: ""
  WORKFLOW_BUNDLES: \${{ inputs.bundles }}

permissions:
  contents: write
  packages: read

jobs:
  build_deps:
    name: ${runner_platform} targets
    runs-on: ubuntu-24.04
    container:
      image: ghcr.io/${OWNER}/ffmpeg-kit-builders-dev:latest
      credentials:
        username: ${OWNER}
        password: \${{ secrets.GHCR_PAT || github.token }}
      options: --user root
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Prepare scripts
        shell: bash
        run: chmod +x runner.sh scripts/*.sh scripts/toolchain/*.sh

      - name: Build selected dependencies
        shell: bash
        run: sudo -E "\${GITHUB_WORKSPACE}/scripts/workflow-runner.sh" --runner-platform=linux

      - name: Upload failure artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failure-artifacts-\${{ github.workflow }}-\${{ env.WORKFLOW_CURRENT_STEP }}-\${{ github.job }}-\${{ github.run_id }}
          path: |
            build.log
            prebuilt
          if-no-files-found: ignore
YAML

	chmod 0644 "$tmp_file"
	mv "$tmp_file" "$file"
	echo "Wrote $file"
}

write_macos_orchestrator() {
	local runner_platform="$1"
	local platform_list="$2"
	local arch_list="$3"
	local file="$WORKFLOW_DIR/build_on_${runner_platform}.yaml"
	local tmp_file
	tmp_file="$(mktemp "${file}.tmp.XXXXXX")"

	cat >"$tmp_file" <<YAML
name: build_on_${runner_platform}

on:
  workflow_dispatch:
    inputs:
      target_platforms:
        description: "Comma-separated target platforms this runner can build"
        required: true
        default: "${platform_list}"
        type: string
      target_archs:
        description: "Comma-separated target architectures to try for each selected platform"
        required: true
        default: "${arch_list}"
        type: string
      force:
        description: "Force rebuild instead of using existing self release artifacts"
        required: false
        default: false
        type: boolean
      build_from:
        description: "Specify step as starting point. Must be build_*"
        required: false
        default: ""
        type: string
      build_only:
        description: "Comma-separated build_* dependency steps to build"
        required: false
        default: ""
        type: string
      bundles:
        description: "Comma-separated target ffmpeg-kit bundles to build"
        required: false
        default: "${bundles}"
        type: string
      build_ffmpeg:
        description: "Build ffmpeg binaries"
        required: false
        default: false
        type: boolean
      build_bundle:
        description: "Build ffmpeg-kit binaries and bundle"
        required: false
        default: false
        type: boolean

env:
  GH_TOKEN: \${{ github.token }}
  WORKFLOW_FORCE_SELF: \${{ inputs.force }}
  WORKFLOW_BUILD_FROM: \${{ inputs.build_from }}
  WORKFLOW_BUILD_ONLY: \${{ inputs.build_only }}
  WORKFLOW_TARGET_PLATFORMS: \${{ inputs.target_platforms }}
  WORKFLOW_TARGET_ARCHS: \${{ inputs.target_archs }}
  WORKFLOW_BUILD_FFMPEG: \${{ inputs.build_ffmpeg }}
  WORKFLOW_BUILD_BUNDLE: \${{ inputs.build_bundle }}
  WORKFLOW_CURRENT_STEP: ""
  WORKFLOW_SEEN_STEPS: ""
  WORKFLOW_BUNDLES: \${{ inputs.bundles }}

permissions:
  contents: write
  packages: read

jobs:
  build_deps:
    name: ${runner_platform} targets
    runs-on: macos-14
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Prepare scripts
        shell: bash
        run: chmod +x runner.sh scripts/*.sh scripts/toolchain/*.sh FFmpegKit/scripts/*.sh

      - name: Install Bash
        shell: bash
        run: \${GITHUB_WORKSPACE}/scripts/toolchain/setup-macos-tools.sh

      - name: Normalize cache key inputs
        shell: bash
        run: |
          echo "CACHE_TARGET_PLATFORMS=\$(printf '%s' '\${{ inputs.target_platforms }}' | tr ',' '-')" >> "\$GITHUB_ENV"
          echo "CACHE_TARGET_ARCHS=\$(printf '%s' '\${{ inputs.target_archs }}' | tr ',' '-')" >> "\$GITHUB_ENV"

      - name: Cache Apple Rust toolchains
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/bin
            ~/.cargo/registry
            ~/.cargo/git
            ~/.rustup/toolchains
            ~/.rustup/update-hashes
            ~/.rustup/settings.toml
          key: apple-rust-\${{ runner.os }}-\${{ runner.arch }}-\${{ env.CACHE_TARGET_PLATFORMS }}-\${{ env.CACHE_TARGET_ARCHS }}-\${{ hashFiles('scripts/toolchain/setup-apple-rust.sh') }}
          restore-keys: |
            apple-rust-\${{ runner.os }}-\${{ runner.arch }}-\${{ env.CACHE_TARGET_PLATFORMS }}-
            apple-rust-\${{ runner.os }}-\${{ runner.arch }}-

      - name: Accept Xcode license
        shell: bash
        run: sudo xcodebuild -license accept

      - name: Build selected dependencies
        shell: bash
        run: sudo -E "\$HOMEBREW_BASH" "\${GITHUB_WORKSPACE}/scripts/workflow-runner.sh" --runner-platform=macos

      - name: Upload failure artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failure-artifacts-\${{ github.workflow }}-\${{ env.WORKFLOW_CURRENT_STEP }}-\${{ github.job }}-\${{ github.run_id }}
          path: |
            build.log
            prebuilt
          if-no-files-found: ignore
YAML

	chmod 0644 "$tmp_file"
	mv "$tmp_file" "$file"
	echo "Wrote $file"
}

join_by_comma() {
    local first=1
    local item
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        if (( first )); then
            printf '%s' "$item"
            first=0
        else
            printf ',%s' "$item"
        fi
    done
}

# find all files with pattern deps-*.sh in SCRIPT_DIR
deps_files=("$SCRIPT_DIR"/deps-*.sh)

# loop through each deps_file and extract all occurence of text "build_*" and add it to an array
builds=()
for file in "${deps_files[@]}"; do
	builds+=($(grep -o 'build_[a-zA-Z0-9_]*' "$file"))
done

# remove duplicates
builds=($(printf "%s\n" "${builds[@]}" | sort -u))

# combine VALID_BUNDLES delimited by comma
bundles=$(printf "%s," "${VALID_BUNDLES[@]}")
bundles=${bundles%,}

# combine VALID_LINUX_ARCHS, VALID_WINDOWS_ARCHS, VALID_ANDROID_ARCHS delimited by comma, deduplicated
archs=$(printf '%s\n' "${VALID_LINUX_ARCHS[@]}" "${VALID_WINDOWS_ARCHS[@]}" "${VALID_ANDROID_ARCHS[@]}" | awk '!seen[$0]++' | join_by_comma)

# combine VALID_BUILD_ON_LINUX
build_on_linux=$(printf "%s," "${VALID_BUILD_ON_LINUX[@]}")
build_on_linux=${build_on_linux%,}

write_linux_orchestrator "linux" "$build_on_linux" "$archs"

# combine VALID_IOS_ARCHS, VALID_IPHONESIMULATOR_ARCHS, VALID_MACOS_ARCHS, VALID_APPLETvos_ARCHS, VALID_APPLETVSIMULATOR_ARCHS delimited by comma
macos_archs=$(printf '%s\n' "${VALID_IOS_ARCHS[@]}" "${VALID_IPHONESIMULATOR_ARCHS[@]}" "${VALID_MACOS_ARCHS[@]}" "${VALID_APPLETVOS_ARCHS[@]}" "${VALID_APPLETVSIMULATOR_ARCHS[@]}" | awk '!seen[$0]++' | join_by_comma)

# combine VALID_BUILD_ON_MACOS
build_on_macos=$(printf "%s," "${VALID_BUILD_ON_MACOS[@]}")
build_on_macos=${build_on_macos%,}

write_macos_orchestrator "macos" "$build_on_macos" "$macos_archs"
