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
        description: "Only build the specified step and exit"
        required: false
        default: false
        type: boolean
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
  RUNNER_WORKFLOW_TARGET_PLATFORMS: "${platform_list}"
  WORKFLOW_BUILD_FFMPEG: \${{ inputs.build_ffmpeg }}
  WORKFLOW_BUILD_BUNDLE: \${{ inputs.build_bundle }}

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
        run: sudo -E "\${GITHUB_WORKSPACE}/scripts/workflow-linux.sh"

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
        description: "Only build the specified step and exit"
        required: false
        default: false
        type: boolean
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
  RUNNER_WORKFLOW_TARGET_PLATFORMS: "${platform_list}"
  WORKFLOW_BUILD_FFMPEG: \${{ inputs.build_ffmpeg }}
  WORKFLOW_BUILD_BUNDLE: \${{ inputs.build_bundle }}

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

      - name: Accept Xcode license
        shell: bash
        run: sudo xcodebuild -license accept

      - name: Build selected dependencies
        shell: bash
        run: sudo -E "\$HOMEBREW_BASH" "\${GITHUB_WORKSPACE}/scripts/workflow-macos.sh"

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

# find all files with pattern deps-*.sh in SCRIPT_DIR
deps_files=("$SCRIPT_DIR"/deps-*.sh)

# loop through each deps_file and extract all occurence of text "build_*" and add it to an array
builds=()
for file in "${deps_files[@]}"; do
	builds+=($(grep -o 'build_[a-zA-Z0-9_]*' "$file"))
done

# remove duplicates
builds=($(printf "%s\n" "${builds[@]}" | sort -u))

# for each build step in builds, create a workflow by running workflow.sh with the build step as argument
# for build in "${builds[@]}"; do
# 	"$SCRIPT_DIR/workflow.sh" "$build"
# done

# rm -f \
# 	"$WORKFLOW_DIR/build_on_android.yaml" \
# 	"$WORKFLOW_DIR/build_on_windows.yaml" \
# 	"$WORKFLOW_DIR/build_on_ios.yaml" \
# 	"$WORKFLOW_DIR/build_on_iphonesimulator.yaml"

rm -f "$WORKFLOW_DIR/build_all_macos.yaml" \
	"$WORKFLOW_DIR/build_all_linux.yaml"

write_linux_orchestrator "linux" "linux,windows,android" "x86_64,aarch64,armv7a"
write_macos_orchestrator "macos" "ios,iphonesimulator,macos,appletvos,appletvsimulator" "x86_64,aarch64"
