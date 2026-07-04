#!/usr/bin/env bash
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
	local file="$WORKFLOW_DIR/build_all_${runner_platform}.yaml"
	local tmp_file
	tmp_file="$(mktemp "${file}.tmp.XXXXXX")"

	cat >"$tmp_file" <<YAML
name: build_all_${runner_platform}

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

permissions:
  contents: write
  packages: read

jobs:
  build:
    name: ${runner_platform} targets
    runs-on: ubuntu-24.04
    env:
      GH_TOKEN: \${{ github.token }}
      WORKFLOW_FORCE_SELF: \${{ inputs.force }}
      WORKFLOW_BUILD_FROM: \${{ inputs.build_from }}
      WORKFLOW_BUILD_ONLY: \${{ inputs.build_only }}
      WORKFLOW_TARGET_PLATFORMS: \${{ inputs.target_platforms }}
      WORKFLOW_TARGET_ARCHS: \${{ inputs.target_archs }}
      RUNNER_WORKFLOW_TARGET_PLATFORMS: "${platform_list}"
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
        run: |
          set -euo pipefail

          source "\${GITHUB_WORKSPACE}/scripts/supported.sh"

          echo "==================================="
          echo "Linux Orchestrator"
          echo "workflow-force-self: \${WORKFLOW_FORCE_SELF}"
          echo "workflow-build-from: \${WORKFLOW_BUILD_FROM}"
          echo "workflow-build-only: \${WORKFLOW_BUILD_ONLY}"
          echo "workflow-target-platforms: \${WORKFLOW_TARGET_PLATFORMS}"
          echo "workflow-target-archs: \${WORKFLOW_TARGET_ARCHS}"
          echo "runner-workflow-target-platforms: \${RUNNER_WORKFLOW_TARGET_PLATFORMS}"
          echo "==================================="

          trim() {
            local value="\$1"
            value="\${value#"\${value%%[![:space:]]*}"}"
            value="\${value%"\${value##*[![:space:]]}"}"
            printf '%s' "\$value"
          }

          contains_csv_value() {
            local csv="\$1"
            local needle="\$2"
            local item
            IFS=',' read -ra items <<< "\$csv"
            for item in "\${items[@]}"; do
              item="\$(trim "\$item")"
              [[ "\$item" == "\$needle" ]] && return 0
            done
            return 1
          }

          is_supported_combo() {
            local combo="\$1"
            local valid
            for valid in "\${VALID_PLATFORM_ARCHS[@]}"; do
              [[ "\$valid" == "\$combo" ]] && return 0
            done
            return 1
          }

          ensure_target_toolchain() {
            local platform="\$1"
            local arch="\$2"
            local key="\$platform"
            [[ "\$platform" == "linux" ]] && key="\${platform}-\${arch}"

            if [[ -n "\${installed_toolchains[\$key]:-}" ]]; then
              return 0
            fi

            case "\$platform" in
              windows)
                sudo -E "\${GITHUB_WORKSPACE}/scripts/toolchain/setup-mingw-w64.sh"
                # shellcheck source=/dev/null
                [[ -f /etc/profile.d/mingw-w64.sh ]] && source /etc/profile.d/mingw-w64.sh
                ;;
              android)
                sudo -E "\${GITHUB_WORKSPACE}/scripts/toolchain/setup-android.sh"
                # shellcheck source=/dev/null
                [[ -f /etc/profile.d/android-sdk.sh ]] && source /etc/profile.d/android-sdk.sh
                # shellcheck source=/dev/null
                [[ -f /etc/profile.d/sdkman.sh ]] && source /etc/profile.d/sdkman.sh
                ;;
              linux)
                if [[ "\$arch" == "aarch64" || "\$arch" == "arm64" || "\$arch" == "arm64-v8a" ]]; then
                  sudo -E "\${GITHUB_WORKSPACE}/scripts/toolchain/setup-linux-arm64.sh"
                  # shellcheck source=/dev/null
                  [[ -f /etc/profile.d/linux-arm64-toolchain.sh ]] && source /etc/profile.d/linux-arm64-toolchain.sh
                fi
                ;;
            esac
            installed_toolchains["\$key"]=1
          }

          if [[ -n "\${WORKFLOW_BUILD_FROM:-}" ]]; then
            if [[ "\$WORKFLOW_BUILD_FROM" != build_* ]]; then
              echo "build_from must be a build_* step, got: \$WORKFLOW_BUILD_FROM" >&2
              exit 1
            fi
          fi

          IFS=',' read -ra selected_platforms <<< "\$WORKFLOW_TARGET_PLATFORMS"
          IFS=',' read -ra selected_archs <<< "\$WORKFLOW_TARGET_ARCHS"
          ran_any=false
          declare -A installed_toolchains=()

          for raw_platform in "\${selected_platforms[@]}"; do
            platform="\$(trim "\$raw_platform")"
            [[ -z "\$platform" ]] && continue

            if ! contains_csv_value "\$RUNNER_WORKFLOW_TARGET_PLATFORMS" "\$platform"; then
              echo "::notice::Skipping platform '\$platform': this ${runner_platform} runner supports only \$RUNNER_WORKFLOW_TARGET_PLATFORMS"
              continue
            fi

            for raw_arch in "\${selected_archs[@]}"; do
              arch="\$(trim "\$raw_arch")"
              [[ -z "\$arch" ]] && continue
              combo="\${platform}-\${arch}"

              if ! is_supported_combo "\$combo"; then
                echo "::notice::Skipping unsupported target \$combo"
                continue
              fi

              ran_any=true
              ensure_target_toolchain "\$platform" "\$arch"
              echo "Preparing build steps for \$combo"
              WORKFLOW_BUILD_STEPS="\$(sudo -E ./runner.sh --host="\$platform" --arch="\$arch" --enable-full --gpl -y --no-bundle --skip --print-all-steps | awk -F= '/^WORKFLOW_BUILD_STEPS=/{print \$2}')"
              echo "WORKFLOW_BUILD_STEPS for \$combo: \$WORKFLOW_BUILD_STEPS"

              start_building=true
              found_build_from=false
              [[ -n "\${WORKFLOW_BUILD_FROM:-}" ]] && start_building=false

              for build in \$WORKFLOW_BUILD_STEPS; do
                if [[ -n "\${WORKFLOW_BUILD_FROM:-}" && "\$build" == "\$WORKFLOW_BUILD_FROM" ]]; then
                  start_building=true
                  found_build_from=true
                fi
                if [[ \${start_building} == "true" ]]; then
                  echo "Running \$build for \$combo"
                  sudo -E ./runner.sh --host="\$platform" --arch="\$arch" --enable-full --gpl -y --no-bundle --skip --workflow --build-only="\$build"
                  sudo rm -rf "\${GITHUB_WORKSPACE}/prebuilt/\${platform}-\${arch}/libraries"
                  sudo rm -rf "\${GITHUB_WORKSPACE}/prebuilt/src"
                  if [[ "\${WORKFLOW_BUILD_ONLY}" == "true" ]]; then
                    start_building=false
                  fi
                fi
              done

              if [[ -n "\${WORKFLOW_BUILD_FROM:-}" && "\$found_build_from" != "true" ]]; then
                echo "build_from step not found in workflow build steps for \$combo: \$WORKFLOW_BUILD_FROM" >&2
                exit 1
              fi
            done
          done

          if [[ "\$ran_any" != "true" ]]; then
            echo "::notice::No supported platform-arch combinations selected for this runner"
          fi

      - name: Upload failure artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failure-artifacts-\${{ github.workflow }}-\${{ github.job }}-\${{ github.run_id }}
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
	local file="$WORKFLOW_DIR/build_all_${runner_platform}.yaml"
	local tmp_file
	tmp_file="$(mktemp "${file}.tmp.XXXXXX")"

	cat >"$tmp_file" <<YAML
name: build_all_${runner_platform}

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

permissions:
  contents: write
  packages: read

jobs:
  build:
    name: ${runner_platform} targets
    runs-on: macos-14
    env:
      GH_TOKEN: \${{ github.token }}
      WORKFLOW_FORCE_SELF: \${{ inputs.force }}
      WORKFLOW_BUILD_FROM: \${{ inputs.build_from }}
      WORKFLOW_BUILD_ONLY: \${{ inputs.build_only }}
      WORKFLOW_TARGET_PLATFORMS: \${{ inputs.target_platforms }}
      WORKFLOW_TARGET_ARCHS: \${{ inputs.target_archs }}
      RUNNER_WORKFLOW_TARGET_PLATFORMS: "${platform_list}"
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Prepare scripts
        shell: bash
        run: chmod +x runner.sh scripts/*.sh scripts/toolchain/*.sh

      - name: Install Bash
        shell: bash
        run: |
          brew install 'bash' 'coreutils' 'ragel' 'curl' 'pkg-config' 'make' 'git' 'svn' 'gcc' 'autoconf' 'automake' 'yasm' 'cvs' 'flex' 'bison' 'ed' 'pax' 'unzip' 'wget' 'xz' 'nasm' 'gperf' 'autogen' 'bzip2' 'python3' 'cython' 'bc' 'texinfo' 'glib' 'llvm' 'lld' 'pipx' 'autoconf-archive' 'bc' 'binutils' 'gpatch' 'libtool' 'gsed' 'trietool'
          echo "HOMEBREW_BASH=\$(brew --prefix)/bin/bash" >> "\$GITHUB_ENV"

      - name: Accept Xcode license
        shell: bash
        run: sudo xcodebuild -license accept

      - name: Build selected dependencies
        shell: bash
        run: |
          set -euo pipefail

          source "\${GITHUB_WORKSPACE}/scripts/supported.sh"

          echo "==================================="
          echo "Linux Orchestrator"
          echo "workflow-force-self: \${WORKFLOW_FORCE_SELF}"
          echo "workflow-build-from: \${WORKFLOW_BUILD_FROM}"
          echo "workflow-build-only: \${WORKFLOW_BUILD_ONLY}"
          echo "workflow-target-platforms: \${WORKFLOW_TARGET_PLATFORMS}"
          echo "workflow-target-archs: \${WORKFLOW_TARGET_ARCHS}"
          echo "runner-workflow-target-platforms: \${RUNNER_WORKFLOW_TARGET_PLATFORMS}"
          echo "==================================="

          trim() {
            local value="\$1"
            value="\${value#"\${value%%[![:space:]]*}"}"
            value="\${value%"\${value##*[![:space:]]}"}"
            printf '%s' "\$value"
          }

          contains_csv_value() {
            local csv="\$1"
            local needle="\$2"
            local item
            IFS=',' read -ra items <<< "\$csv"
            for item in "\${items[@]}"; do
              item="\$(trim "\$item")"
              [[ "\$item" == "\$needle" ]] && return 0
            done
            return 1
          }

          is_supported_combo() {
            local combo="\$1"
            local valid
            for valid in "\${VALID_PLATFORM_ARCHS[@]}"; do
              [[ "\$valid" == "\$combo" ]] && return 0
            done
            return 1
          }

          ensure_target_toolchain() {
            local platform="\$1"
            local arch="\$2"
            local key="\${platform}-\${arch}"

            if [[ -n "\${installed_toolchains[\$key]:-}" ]]; then
              return 0
            fi

            case "\$platform" in
              ios|iphonesimulator|macos)
                "\${GITHUB_WORKSPACE}/scripts/toolchain/setup-apple-rust.sh" "\$platform" "\$arch"
                ;;
            esac

            installed_toolchains["\$key"]=1
          }

          if [[ -n "\${WORKFLOW_BUILD_FROM:-}" ]]; then
            if [[ "\$WORKFLOW_BUILD_FROM" != build_* ]]; then
              echo "build_from must be a build_* step, got: \$WORKFLOW_BUILD_FROM" >&2
              exit 1
            fi
          fi

          IFS=',' read -ra selected_platforms <<< "\$WORKFLOW_TARGET_PLATFORMS"
          IFS=',' read -ra selected_archs <<< "\$WORKFLOW_TARGET_ARCHS"
          ran_any=false
          declare -A installed_toolchains=()

          for raw_platform in "\${selected_platforms[@]}"; do
            platform="\$(trim "\$raw_platform")"
            [[ -z "\$platform" ]] && continue

            if ! contains_csv_value "\$RUNNER_WORKFLOW_TARGET_PLATFORMS" "\$platform"; then
              echo "::notice::Skipping platform '\$platform': this ${runner_platform} runner supports only \$RUNNER_WORKFLOW_TARGET_PLATFORMS"
              continue
            fi

            for raw_arch in "\${selected_archs[@]}"; do
              arch="\$(trim "\$raw_arch")"
              [[ -z "\$arch" ]] && continue
              combo="\${platform}-\${arch}"

              if ! is_supported_combo "\$combo"; then
                echo "::notice::Skipping unsupported target \$combo"
                continue
              fi

              ran_any=true
              ensure_target_toolchain "\$platform" "\$arch"
              echo "Preparing build steps for \$combo"
              WORKFLOW_BUILD_STEPS="\$(sudo -E "\$HOMEBREW_BASH" ./runner.sh --host="\$platform" --arch="\$arch" --enable-full --gpl -y --no-bundle --skip --print-all-steps | awk -F= '/^WORKFLOW_BUILD_STEPS=/{print \$2}')"
              echo "WORKFLOW_BUILD_STEPS for \$combo: \$WORKFLOW_BUILD_STEPS"

              start_building=true
              found_build_from=false
              [[ -n "\${WORKFLOW_BUILD_FROM:-}" ]] && start_building=false

              for build in \$WORKFLOW_BUILD_STEPS; do
                if [[ -n "\${WORKFLOW_BUILD_FROM:-}" && "\$build" == "\$WORKFLOW_BUILD_FROM" ]]; then
                  start_building=true
                  found_build_from=true
                fi
                if [[ \${start_building} == "true" ]]; then
                  echo "Running \$build for \$combo"
                  sudo -E "\$HOMEBREW_BASH" ./runner.sh --host="\$platform" --arch="\$arch" --enable-full --gpl -y --no-bundle --skip --workflow --build-only="\$build"
                  sudo rm -rf "\${GITHUB_WORKSPACE}/prebuilt/\${platform}-\${arch}/libraries"
                  sudo rm -rf "\${GITHUB_WORKSPACE}/prebuilt/src"
                  if [[ "\${WORKFLOW_BUILD_ONLY}" == "true" ]]; then
                    start_building=false
                  fi
                fi
              done

              if [[ -n "\${WORKFLOW_BUILD_FROM:-}" && "\$found_build_from" != "true" ]]; then
                echo "build_from step not found in workflow build steps for \$combo: \$WORKFLOW_BUILD_FROM" >&2
                exit 1
              fi
            done
          done

          if [[ "\$ran_any" != "true" ]]; then
            echo "::notice::No supported platform-arch combinations selected for this runner"
          fi

      - name: Upload failure artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failure-artifacts-\${{ github.workflow }}-\${{ github.job }}-\${{ github.run_id }}
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

rm -f \
	"$WORKFLOW_DIR/build_all_android.yaml" \
	"$WORKFLOW_DIR/build_all_windows.yaml" \
	"$WORKFLOW_DIR/build_all_ios.yaml" \
	"$WORKFLOW_DIR/build_all_iphonesimulator.yaml"

write_linux_orchestrator "linux" "linux,windows,android" "x86_64,aarch64,armv7a"
write_macos_orchestrator "macos" "ios,iphonesimulator,macos" "x86_64,aarch64"
