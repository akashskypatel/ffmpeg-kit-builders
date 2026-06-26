#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")/.github/workflows"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
	echo "Workflow directory not found: $WORKFLOW_DIR" >&2
	exit 1
fi

write_linux_orchestrator() {
	local platform="$1"
	local arch_list="$2"
	local file="$WORKFLOW_DIR/build_all_${platform}.yaml"
	local tmp_file
	tmp_file="$(mktemp "${file}.tmp.XXXXXX")"

	cat >"$tmp_file" <<YAML
name: build_all_${platform}

on:
  workflow_dispatch:

permissions:
  contents: write
  packages: read

jobs:
  build:
    name: ${platform} \${{ matrix.arch }}
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      max-parallel: 1
      matrix:
        arch: [${arch_list}]
    env:
      GH_TOKEN: \${{ github.token }}
    container:
      image: ghcr.io/akashskypatel/ffmpeg-kit-builders-dev:latest
      credentials:
        username: akashskypatel
        password: \${{ secrets.GHCR_PAT || github.token }}
      options: --user root
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Prepare scripts
        shell: bash
        run: chmod +x runner.sh scripts/*.sh

      - name: Build ${platform} dependencies
        shell: bash
        run: |
          set -euo pipefail

          platform="${platform}"
          arch="\${{ matrix.arch }}"
          WORKFLOW_BUILD_STEPS="\$(sudo -E ./runner.sh --host="\$platform" --arch="\$arch" --enable-full --gpl -y --no-bundle --skip --print-all-steps | awk -F= '/^WORKFLOW_BUILD_STEPS=/{print \$2}')"
          echo "WORKFLOW_BUILD_STEPS: \$WORKFLOW_BUILD_STEPS"

          for build in \$WORKFLOW_BUILD_STEPS; do
            echo "Running \$build for \${platform}-\${arch}"
            sudo -E ./runner.sh --host="\$platform" --arch="\$arch" --enable-full --gpl -y --no-bundle --skip --workflow --build-only="\$build"
            sudo rm -rf "\${GITHUB_WORKSPACE}/prebuilt/\${platform}-\${arch}/libraries"
          done

      - name: Upload failure artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failure-artifacts-\${{ github.workflow }}-\${{ github.job }}-\${{ matrix.arch }}
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
	local platform="$1"
	local arch_list="$2"
	local file="$WORKFLOW_DIR/build_all_${platform}.yaml"
	local tmp_file
	tmp_file="$(mktemp "${file}.tmp.XXXXXX")"

	cat >"$tmp_file" <<YAML
name: build_all_${platform}

on:
  workflow_dispatch:

permissions:
  contents: write
  packages: read

jobs:
  build:
    name: ${platform} \${{ matrix.arch }}
    runs-on: macos-14
    strategy:
      fail-fast: false
      max-parallel: 1
      matrix:
        arch: [${arch_list}]
    env:
      GH_TOKEN: \${{ github.token }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Prepare scripts
        shell: bash
        run: chmod +x runner.sh scripts/*.sh

      - name: Install Bash
        shell: bash
        run: |
          brew install 'bash' 'coreutils' 'ragel' 'curl' 'pkg-config' 'make' 'git' 'svn' 'gcc' 'autoconf' 'automake' 'yasm' 'cvs' 'flex' 'bison' 'ed' 'pax' 'unzip' 'wget' 'xz' 'nasm' 'gperf' 'autogen' 'bzip2' 'python3' 'bc' 'texinfo' 'glib' 'llvm' 'lld' 'pipx' 'autoconf-archive' 'bc' 'binutils' 'gpatch' 'libtool' 'gsed'
          echo "HOMEBREW_BASH=\$(brew --prefix)/bin/bash" >> "\$GITHUB_ENV"

      - name: Accept Xcode license
        shell: bash
        run: sudo xcodebuild -license accept

      - name: Build ${platform} dependencies
        shell: bash
        run: |
          set -euo pipefail

          platform="${platform}"
          arch="\${{ matrix.arch }}"
          WORKFLOW_BUILD_STEPS="\$(sudo -E "\$HOMEBREW_BASH" ./runner.sh --host="\$platform" --arch="\$arch" --enable-full --gpl -y --no-bundle --skip --print-all-steps | awk -F= '/^WORKFLOW_BUILD_STEPS=/{print \$2}')"
          echo "WORKFLOW_BUILD_STEPS: \$WORKFLOW_BUILD_STEPS"

          for build in \$WORKFLOW_BUILD_STEPS; do
            echo "Running \$build for \${platform}-\${arch}"
            sudo -E "\$HOMEBREW_BASH" ./runner.sh --host="\$platform" --arch="\$arch" --enable-full --gpl -y --no-bundle --skip --workflow --build-only="\$build"
            sudo rm -rf "\${GITHUB_WORKSPACE}/prebuilt/\${platform}-\${arch}/libraries"
          done

      - name: Upload failure artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failure-artifacts-\${{ github.workflow }}-\${{ github.job }}-\${{ matrix.arch }}
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
for build in "${builds[@]}"; do
	"$SCRIPT_DIR/workflow.sh" "$build"
done

write_linux_orchestrator "linux" "x86_64"
write_linux_orchestrator "windows" "x86_64"
write_linux_orchestrator "android" "x86_64, aarch64, armv7a"
write_macos_orchestrator "ios" "aarch64"
write_macos_orchestrator "iphonesimulator" "aarch64"
write_macos_orchestrator "macos" "x86_64, aarch64"
