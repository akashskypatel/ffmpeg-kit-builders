#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,1090

if (( BASH_VERSINFO[0] < 4 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 4+ is required." >&2
    exit 1
fi

export BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPTDIR="${BASEDIR}/scripts"
export LOG_FILE="${BASEDIR}/build.log"
export sandbox="prebuilt"
export WORKDIR="$BASEDIR/$sandbox"
export src_dir="${WORKDIR}/src"
export RUN_ARGS=("${@}")

source "${SCRIPTDIR}/variable.sh"
source "${SCRIPTDIR}/function.sh"

require_sudo

[[ -f "$LOG_FILE" ]] && rm -f "$LOG_FILE"
touch "$LOG_FILE"
echo -e "INFO: Build options: ${RUN_ARGS[*]}\n" | tee -a "$LOG_FILE"
[[ -f "$LOG_FILE" ]] && chmod -R a+rwx "$LOG_FILE" || true;

ff_flags_raw=()    # Original arguments: --ff-something
ff_flags_values=() # Extracted values: something

display_help() {
  cat <<'EOF'
Usage: sudo ./runner.sh [OPTIONS]

General:
  -h, --help                         Show this help and exit
  -v, --version                      Show the builder version and exit
  -d, --debug                        Trace shell commands
  -y                                 Accept defaults and disable prompts
  --hide-banner                      Hide the startup banner
  -f, --force                        Force dependency rebuilds
  -fs, --force-self                  Skip artifact reuse for the requested dependency step
  -ff, --force-ffmpeg                Force an FFmpeg rebuild
  -fk, --force-kit                   Force an FFmpegKit rebuild
  --skip                             Skip package checks and build validation
  --skip-pkg-check, --skip-pkg       Skip package checks
  --skip-validation, --skip-val      Skip build validation
  --resume                           Resume the last interrupted run
  --debug-build, --build-debug, --enable-debug
                                     Build FFmpeg and FFmpegKit with debug settings

Target:
  --host-platform=PLATFORM, --host=PLATFORM, --platform=PLATFORM
                                     linux, windows, macos, ios, iphonesimulator,
                                     appletvos, appletvsimulator, android, or wasm
  --host-arch=ARCH, --arch=ARCH      x86_64, i686, aarch64, armv7a, or wasm32

Licensing:
  --enable-gpl, --gpl                Enable GPL libraries
  --enable-gpl-all, --gpl-all        Enable all available GPL libraries
  --enable-nonfree, --nonfree        Enable nonfree, non-redistributable libraries

Feature presets:
  --enable-base, --base              Enable base FFmpeg libraries
  --enable-full, --full              Enable all external libraries allowed by licensing
  --enable-small, --small            Exclude selected libraries to reduce build size
  --enable-https                     Enable HTTPS libraries
  --enable-audio                     Enable audio libraries
  --enable-audio-ai                  Enable audio AI libraries
  --enable-video                     Enable video libraries
  --enable-streaming                 Enable streaming libraries
  --enable-video-ai-cpu              Enable CPU video AI libraries
  --enable-video-ai-gpu              Enable GPU video AI with interactive GPU selection
  --enable-video-ai-gpu-cuda         Enable GPU video AI with CUDA
  --enable-video-ai-gpu-rocm         Enable GPU video AI with ROCm
  --enable-hardware, --enable-hw     Enable hardware acceleration libraries
  --enable-ssh                       Enable SSH/SFTP support
  --enable-smb                       Enable SMB support
  --enable-mq                        Enable message queue support

Bundle presets:
  --base-bundle                      Base libraries
  --audio-bundle                     HTTPS and audio libraries
  --audio-ai-bundle                  HTTPS, audio, and audio AI libraries
  --video-bundle                     HTTPS, audio, and video libraries
  --video-ai-cpu-bundle              Video bundle with CPU AI libraries
  --video-ai-gpu[-cuda|-rocm]-bundle Video bundle with GPU AI libraries
  --video-hw-bundle                  Video bundle with hardware libraries
  --video-hw-ai-cpu-bundle           Hardware video bundle with CPU AI libraries
  --video-hw-ai-gpu[-cuda|-rocm]-bundle
                                     Hardware video bundle with GPU AI libraries
  --full-bundle                      All supported feature groups
  --no-bundle                        Do not create an FFmpegKit bundle

Build selection:
  --build-deps-only, --build-deps, --deps
                                     Enable dependency builds (add --no-bundle to skip bundling)
  --build-only=STEP[,STEP...], --only=STEP[,STEP...]
                                     Build named build_* steps and their prerequisites
  --build-dependents, --build-depts, --depts
                                     Include direct and transitive dependents of --build-only steps
  --build-from=STEP, --from=STEP     Build dependency steps starting at a named build_* step
  --run-only=FUNCTION                Run one named build function or helper
  --dry-run                          Exit before executing build steps
  --print-all-steps, --print-total-steps
                                     Print the planned build steps and/or their count; build continues
  --build-ffmpeg-only[=TYPE], --build-ffmpeg[=TYPE], --ffmpeg[=TYPE]
                                     Build FFmpeg only (TYPE: static or shared; default: static)
  --build-ffmpeg-kit-only[=TYPE], --build-ffmpeg-kit[=TYPE], --ffmpeg-kit[=TYPE], --kit[=TYPE]
                                     Build FFmpegKit (FFmpeg is built if needed; TYPE: shared or static, default: shared)
  --build-tests[=TYPE], --build-test[=TYPE], --test[=TYPE], --tests[=TYPE]
                                     Build tests; TYPE may be tsan, asan, or ubsan

FFmpeg configuration:
  --ffmpeg-git-checkout-version=REF  FFmpeg ref to build (default: release/9.0)
  --ffmpeg-git-checkout=URL          FFmpeg repository URL
  --ffmpeg-source-dir=PATH           Use an existing FFmpeg source tree
  --cflags=FLAGS                     Set C compiler flags
  --cxxflags=FLAGS                   Set C++ compiler flags
  --cppflags=FLAGS                   Set preprocessor flags
  --ldflags=FLAGS                    Set linker flags
  --git-get-latest=y|n               Pull latest Git revisions (default: n)
  --prefer-stable=y|n                Prefer release sources where supported (default: y)
  --enable-LIBRARY                   Enable a specific library, e.g. --enable-libx264
  --disable-LIBRARY                  Disable a specific library; disable wins on conflict
  --ff-OPTION                        Pass --OPTION through to FFmpeg configure
  --list-libraries                   Show FFmpeg configure options and exit

Release and cleanup:
  --release[=local|remote]           Create a release archive (default: local)
  --clean[=COMPONENTS]               With --release, clean outputs after archiving;
                                     COMPONENTS: all, ffmpeg, kit, bundle (comma-separated)
  --clean-builds=static|shared       Clean FFmpeg/FFmpegKit builds of that type and exit
  --reset-and-clean[=SOURCE_DIR]      Reset source build state; optionally limit to a source dir
  --upload-deps                      Upload dependency artifacts where supported
EOF
}

append_cflags() {
  export original_cflags+=" $1"
}

append_ldflags() {
  export original_ldflags+=" $1"
}

append_cppflags() {
  export original_cppflags+=" $1"
}

append_cxxflags() {
  export original_cxxflags+=" $1"
}

explicit_enabled=()
explicit_disabled=()

parse_arguments() {
# parse command line parameters, if any
while [ $# -gt 0 ]; do
	case $1 in
	-h | --help)
		display_help
		shift
    exit 0
		;;
	-v | --version) 
    display_version
    shift
    exit 0
    ;;
	-d | --debug)
		set -x
		shift
		;;
	-f | --force)
    export build_force=y
    shift
		;;
  -fs | --force-self)
    export force_self=y
    shift
		;;
  -ff | --force-ffmpeg)
    export force_ffmpeg=y
    shift
		;;
  -fk | --force-kit)
    export force_kit=y
    shift
		;;
  -y)
    export accept_defaults=y
    echo "INFO: Skipping interactive. Accepting defult selections." | tee -a "$LOG_FILE"
    shift
    ;;
  --hide-banner)
    export hide_banner=y
    shift
    ;;
  --debug-build|--build-debug|--enable-debug)
    export do_debug_build=y
    shift
    ;;
  --resume)
    shift
    ;;
  --skip)
    export skip_validation=y
    export skip_package_check=y
    shift
    ;;
  --skip-pkg-check|--skip-pkg)
    export skip_package_check=y
    shift
    ;;
  --skip-validation|--skip-val)
    export skip_validation=y
    shift
    ;;
  --release=*)
    case "${1#*=}" in
      local)
        export create_release=local
        ;;
      remote)
        export create_release=remote
        ;;
      *)
        echo "Invalid release type: ${1#*=}. Defaulting to local." | tee -a "$LOG_FILE"
        export create_release=local
        ;;
    esac
    shift
    ;;
  --release)
    export create_release=local
    shift
    ;;
  --clean=*)
    export create_release_clean_type="${1#*=}"
    shift
    ;;
  --clean)
    export create_release_clean=y
    export create_release_clean_type="all"
    shift
    ;;
  --host-platform=*|--host=*|--platform=*)
    export host_platform="${1#*=}"
    shift
    ;;
  --host-arch=*|--arch=*)
    export host_arch="${1#*=}"
    shift
    ;;
	--ffmpeg-git-checkout-version=*)
		export ffmpeg_git_checkout_version="${1#*=}"
		shift
		;;
	--ffmpeg-git-checkout=*)
		export ffmpeg_git_checkout="${1#*=}"
		shift
		;;
	--ffmpeg-source-dir=*)
		export ffmpeg_source_dir="${1#*=}"
		shift
		;;
	--cflags=*)
		append_cflags "${1#*=}"
		echo -e "setting CFLAGS as $original_cflags" | tee -a "$LOG_FILE"
		shift
		;;
  --cxxflags=*)
		append_cxxflags "${1#*=}"
		echo -e "setting CXXFLAGS as $original_cxxflags" | tee -a "$LOG_FILE"
		shift
		;;
  --cppflags=*)
		append_cppflags "${1#*=}"
		echo -e "setting CPPFLAGS as $original_cppflags" | tee -a "$LOG_FILE"
		shift
		;;
  --ldflags=*)
		append_ldflags "${1#*=}"
		echo -e "setting LDFLAGS as $original_ldflags" | tee -a "$LOG_FILE"
		shift
		;;
	--git-get-latest=*)
		export git_get_latest="${1#*=}"
		shift
		;;
	--prefer-stable=*)
		export prefer_stable="${1#*=}"
		shift
		;;
	--enable-gpl | --gpl)
		export build_gpl=y
		shift
		;;
  --enable-gpl-all | --gpl-all)
    export build_all_gpl=y
    shift
    ;;
  --enable-nonfree | --nonfree)
		export build_nonfree=y
		shift
		;;
  --build-dependents|--build-depts|--depts)
    export build_dependents=y
    shift
    ;;
	--build-only=*|--only=*)
		export build_only="${1#*=}"
		shift
		;;
	--build-from=*|--from=*)
		export build_from="${1#*=}"
		shift
		;;
	--build-deps-only|--build-deps|--deps)
		export build_dependencies=y
		shift
		;;
  --build-ffmpeg-only|--build-ffmpeg|--ffmpeg)
    export build_ffmpeg_type=static
    export do_build_ffmpeg=y
    shift
    ;;
	--build-ffmpeg-only=*|--build-ffmpeg=*|--ffmpeg=*)
    build_type="${1#*=}"
    case "$build_type" in
      shared)
      export build_ffmpeg_type=shared
      ;;
      static)
      export build_ffmpeg_type=static
      ;;
      *)
      export build_ffmpeg_type=shared
      ;;
    esac
    export do_build_ffmpeg=y
		shift
		;;
  --build-ffmpeg-kit-only|--build-ffmpeg-kit|--ffmpeg-kit|--kit)
    export build_ffmpeg_kit_type=shared
    export do_build_ffmpeg_kit=y
    shift
    ;;
	--build-ffmpeg-kit-only=*|--build-ffmpeg-kit=*|--ffmpeg-kit=*|--kit=*)
    build_type="${1#*=}"
    case "$build_type" in
      shared)
      export build_ffmpeg_kit_type=shared
      ;;
      static)
      export build_ffmpeg_kit_type=static
      ;;
      *)
      export build_ffmpeg_kit_type=shared
      ;;
    esac
    export do_build_ffmpeg_kit=y
		shift
		;;
  --build-tests|--build-test|--test|--tests)
    export build_tests=y
    source "${SCRIPTDIR}/extract-fate.sh"
		shift
		;;
  --build-tests=*|--build-test=*|--test=*|--tests=*)
    export test_type="${1#*=}"
    export build_tests=y
    case "$test_type" in
      tsan|thread|t)
      export test_type=tsan
      ;;
      asan|address|a)
      export test_type=asan
      ;;
      undefined|ubsan|u)
      export test_type=undefined
      ;;
      *)
      export test_type=none
      ;;
    esac
		shift
		;;
	--print-total-steps | --print-all-steps | --reset-and-clean=* | --reset-and-clean) shift ;; # Handled below, just consume and ignore here
	--clean-builds=*)
    build_type="${1#*=}"
    case "$build_type" in
      shared)
      export build_ffmpeg_type=shared
      export build_ffmpeg_kit_type=shared
      ;;
      static)
      export build_ffmpeg_type=static
      export build_ffmpeg_kit_type=static
      ;;
      *)
      export build_ffmpeg_type=shared
      export build_ffmpeg_kit_type=shared
      ;;
    esac
		export enable_clean_builds=y
    shift
		;;
  --list-libraries)
    list_libraries
    shift
    ;;
  --run-only=*)
    export run_only="${1#*=}"
    shift
    ;;
  --enable-base|--base)
    export enable_base=y
    shift
    ;;
	--enable-full|--full)
    export enable_full=y
    shift
    ;;
  --enable-small|--small)
    export build_small=y
    shift
    ;;
  --enable-https)
    export enable_https=y
    shift
    ;;
  --enable-audio)
    export enable_audio=y
    export audio_bundle=y
    shift
    ;;
  --enable-video)
    export enable_video=y
    export video_bundle=y
    shift
    ;;
  --enable-streaming)
    export enable_streaming=y
    shift
    ;;
  --enable-audio-ai)
    export enable_audio_ai=y
    export enable_audio=y
    export audio_bundle=y
    shift
    ;;
  --enable-video-ai-cpu)
    export enable_video_ai=y
    export enable_audio_ai=y
    export enable_video=y
    export enable_audio=y
    export video_bundle=y
    export audio_bundle=y
    export gpu_support=n
    shift
    ;;
  # interactive
  --enable-video-ai-gpu)
    export enable_video_ai=y
    export enable_audio_ai=y
    export enable_video=y
    export enable_audio=y
    export video_bundle=y
    export audio_bundle=y
    export gpu_support=n
    shift
    ;;
  # cuda
  --enable-video-ai-gpu-cuda)
    export enable_video_ai=y
    export enable_audio_ai=y
    export enable_video=y
    export enable_audio=y
    export video_bundle=y
    export audio_bundle=y
    export gpu_support=y
    pick_gpu_type "cuda"
    shift
    ;;
  # rocm
  --enable-video-ai-gpu-rocm)
    export enable_video_ai=y
    export enable_audio_ai=y
    export enable_video=y
    export enable_audio=y
    export video_bundle=y
    export audio_bundle=y
    export gpu_support=y
    pick_gpu_type "rocm"
    shift
    ;;
  --enable-hardware|--enable-hw)
    export enable_hardware=y
    export enable_video=y
    export video_bundle=y
    export enable_audio=y
    export audio_bundle=y
    shift
    ;;
  --enable-ssh)
    export enable_ssh=y
    shift
    ;;
  --enable-smb)
    export enable_smb=y
    shift
    ;;
  --enable-mq)
    export enable_mq=y
    shift
    ;;
  --base-bundle)
    export enable_base=y
    shift
    ;;
  --audio-bundle)
    export audio_bundle=y
    shift
    ;;
  --video-bundle)
    export video_bundle=y
    shift
    ;;
  --audio-ai-bundle)
    export audio_ai_bundle=y
    shift
    ;;
  --full-bundle)
    export enable_full=y
    shift
    ;;
  --video-ai-cpu-bundle)
    export video_ai_bundle=y
    export enable_audio_ai=y
    export gpu_support=n
    shift
    ;;
  # interactive
  --video-ai-gpu-bundle)
    export video_ai_bundle=y
    export enable_audio_ai=y
    export gpu_support=y
    shift
    ;;
  # cuda
  --video-ai-gpu-cuda-bundle)
    export video_ai_bundle=y
    export enable_audio_ai=y
    export gpu_support=y
    pick_gpu_type "cuda"
    shift
    ;;
  # rocm
  --video-ai-gpu-rocm-bundle)
    export video_ai_bundle=y
    export enable_audio_ai=y
    export gpu_support=y
    pick_gpu_type "rocm"
    shift
    ;;
  --video-hw-bundle|--enable-video_hw)
    export video_hw_bundle=y
    shift
    ;;
  --video-hw-ai-cpu-bundle)
    export video_ai_hw_bundle=y
    export gpu_support=n
    shift
    ;;
  # interactive
  --video-hw-ai-gpu-bundle)
    export video_ai_hw_bundle=y
    export gpu_support=y
    shift
    ;;
  # cuda
  --video-hw-ai-gpu-cuda-bundle)
    export video_ai_hw_bundle=y
    export gpu_support=y
    pick_gpu_type "cuda"
    shift
    ;;
  # rocm
  --video-hw-ai-gpu-rocm-bundle)
    export video_ai_hw_bundle=y
    export gpu_support=y
    pick_gpu_type "rocm"
    shift
    ;;
  --no-bundle)
    export create_bundle=n
    shift
    ;;
  --upload-deps)
    export upload_deps=y
    shift
    ;;
  --dry-run)
    export dry_run=y
    shift
    ;;
	--enable-*)
    lib_name="${1#--enable-}"
    explicit_enabled+=( "$lib_name" )
    shift
    ;;
  --disable-*)
    lib_name="${1#--disable-}"
    explicit_disabled+=( "$lib_name" )
    shift
    ;;
  --ff-*)
    # Store original
    ff_flags_raw+=("$1")
    # Store extracted value
    VALUE="${1#--ff-}"
    ff_flags_values+=("--$VALUE")
    shift
    ;;
	--)
		shift
		;;
	-*)
		echo -e "Error, unknown option: '$1'." | tee -a "$LOG_FILE"
		exit 1
		;;
	*)
    echo "Unknown argument: $1" | tee -a "$LOG_FILE"
    shift 
    ;;
	esac
done
}

export RUN_STATE_FILE="$BASEDIR/~run.state"
export BUILT_STATE_FILE="$BASEDIR/~built.state"

if [[ "$*" == *"--resume"* ]]; then
  if [[ -f "$BUILT_STATE_FILE" ]]; then
      while IFS= read -r line; do
          INSTALLED_LIBS["$line"]="1"
      done < "$BUILT_STATE_FILE"
  fi
  if [[ -f "$RUN_STATE_FILE" ]]; then
    LINE=$(head -n 1 "$RUN_STATE_FILE")
    STEP=$(gsed -i -n '2{p;q;}' "$RUN_STATE_FILE")
    read -r -a args <<< "$LINE"
    idx_run=-1
    idx_build_only=-1
    idx_build_from=-1
    for i in "${!args[@]}"; do
      case "${args[i]}" in
        --run-only=*)   idx_run=$i ;;
        --build-only=*) idx_build_only=$i ;;
        --build-from=*) idx_build_from=$i ;;
      esac
    done
    # shellcheck disable=2004
    if [[ $idx_run -ge 0 ]]; then
       args[$idx_run]="--run-only=$STEP"
    elif [[ $idx_build_only -ge 0 ]]; then
       args[$idx_build_only]="--build-only=$STEP"
    elif [[ $idx_build_from -ge 0 ]]; then
       args[$idx_build_from]="--build-from=$STEP"
    else
       args+=("--build-from=$STEP")
    fi
    RUN_ARGS=("${args[@]}")
    echo "INFO: Resuming previous run with: ${RUN_ARGS[*]}" | tee -a "$LOG_FILE"
    parse_arguments "${RUN_ARGS[@]}"
  else
    echo "Error: could not find previous run.state file." | tee -a "$LOG_FILE"
    exit 1
  fi
else
  [[ -f "$BUILT_STATE_FILE" ]] && remove_path -f "$BUILT_STATE_FILE"
  parse_arguments "$@"
fi

if ! truthy "$accept_defaults"; then
  pick_host_platform "$host_platform"
  pick_host_arch "$host_arch"
else
  pick_host_platform "${host_platform:-linux}"
  pick_host_arch "${host_arch:-x86_64}"
fi

truthy "$enable_clean_builds" && { clean_ffmpeg_builds; exit 0; }

if ! truthy "$build_dependencies"; then
truthy "$build_gpl" && truthy "$build_nonfree" && echo -e "ERROR: --enable-gpl is not compatible with --enable-nonfree. Remove one and run again" | tee -a "$LOG_FILE"
fi

intro                  # remember to always run the intro, since it adjust pwd

set_box_memory_size_bytes
if [[ $box_memory_size_bytes -lt 600000000 ]]; then
	echo -e "your box only has $box_memory_size_bytes, 512MB (only) 
  boxes crash when building cross compiler gcc, please add some swap" | tee -a "$LOG_FILE" # 1G worked OK however...
	exit 1
fi

if [[ $box_memory_size_bytes -gt 2000000000 ]]; then
	gcc_cpu_count=$(get_cpu_count) # they can handle it seemingly...
else
	echo -e "low RAM detected so using only one cpu for gcc compilation" | tee -a "$LOG_FILE"
	gcc_cpu_count=y # compatible low RAM...
fi

if [[ $host_platform == "iphonesimulator" ]]; then
	source_platform="ios"
elif [[ $host_platform == "appletvsimulator" ]]; then
  source_platform="appletvos"
else
	source_platform="$host_platform"
fi

source "${SCRIPTDIR}/function-$source_platform.sh"
source "${SCRIPTDIR}/run-$source_platform.sh"
source "${SCRIPTDIR}/deps-$source_platform.sh"

# Setup config variables

# disable libraries autodetected by default to prevent inadvertent bundling
disable_autodetected

apply_preset "$CONFIG_BASE"

if truthy "$build_nonfree"; then
  echo "INFO: Building with non-free ${host_platform,,} libraries" | tee -a "$LOG_FILE"
  case "${host_platform,,}" in
    linux)
    apply_preset "$CONFIG_LINUX_NON_FREE"
    ;;
    windows)
    apply_preset "$CONFIG_WINDOWS_NON_FREE"
    ;;
    android)
    apply_preset "$CONFIG_ANDROID_NON_FREE"
    ;;
    ios|macos|iphonesimulator)
    apply_preset "$CONFIG_APPLE_NON_FREE"
    ;;
    rpi)
    apply_preset "$CONFIG_RPI_NON_FREE"
    ;;
    oh|openharmony|open-harmony|open_harmony|harmony)
    apply_preset "$CONFIG_OH_NON_FREE"
    ;;
    wasm|wasm32)
    apply_preset "$CONFIG_WASM_NON_FREE"
    ;;
    *)
    ;;
  esac
else
  echo "INFO: Building with free ${host_platform,,} libraries" | tee -a "$LOG_FILE"
  case "${host_platform,,}" in
    linux)
    apply_preset "$CONFIG_LINUX"
    ;;
    windows)
    apply_preset "$CONFIG_WINDOWS"
    ;;
    android)
    apply_preset "$CONFIG_ANDROID"
    ;;
    ios|macos|iphonesimulator|appletvos|appletvsimulator)
    apply_preset "$CONFIG_APPLE"
    if [[ "$host_platform" == "macos" ]]; then
      apply_preset "$CONFIG_MACOS"
    elif [[ "$host_platform" == "ios" ]]; then
      apply_preset "$CONFIG_IOS"
    fi
    if [[ "$host_platform" == "appletvos" || "$host_platform" == "appletvsimulator" ]]; then
      apply_preset "$CONFIG_TVOS"
    fi
    ;;
    rpi)
    apply_preset "$CONFIG_RPI"
    ;;
    oh|openharmony|open-harmony|open_harmony|harmony)
    apply_preset "$CONFIG_OH"
    ;;
    wasm|wasm32)
    apply_preset "$CONFIG_WASM"
    ;;
    *)
    ;;
  esac
fi

if ! truthy "$enable_base"; then
  echo -e "\n  [CONFIG] Enabling selected libraries..." >>"$LOG_FILE"
  apply_preset "$CONFIG_GENERAL"

  if truthy "$audio_bundle" || truthy "$enable_full"; then
    enable_audio=y
    enable_https=y
    enable_streaming=y
  fi
  if truthy "$audio_ai_bundle" || truthy "$enable_full"; then
    enable_audio=y
    enable_audio_ai=y
    enable_https=y
    enable_streaming=y
  fi
  if truthy "$video_bundle" || truthy "$enable_full"; then
    enable_audio=y
    enable_video=y
    enable_https=y
    enable_streaming=y
  fi
  if truthy "$video_ai_bundle" || truthy "$enable_full"; then
    enable_audio=y
    enable_video=y
    enable_video_ai=y
    enable_https=y
    enable_streaming=y
  fi
  if truthy "$video_hw_bundle" || truthy "$enable_full"; then
    enable_audio=y
    enable_video=y
    enable_hardware=y
    enable_https=y
    enable_streaming=y
  fi
  if truthy "$video_ai_hw_bundle" || truthy "$enable_full"; then
    enable_audio=y
    enable_video=y
    enable_audio_ai=y
    enable_video_ai=y
    enable_hardware=y
    enable_https=y
    enable_streaming=y
  fi

  if truthy "$enable_mq" || truthy "$enable_full"; then
    pick_mq_lib
  fi

  if truthy "$gpu_support" && [[ -z "$gpu_type" ]]; then
    pick_gpu_type
  fi

  if truthy "$enable_https"; then
    echo -e "\n  [CONFIG] Checking https libraries..." >>"$LOG_FILE"
    if truthy "$accept_defaults"; then
      pick_ssl_type "openssl"
    elif [[ -z "$ssl_type" ]]; then
      pick_ssl_type
      case "${ssl_type,,}" in
        openssl)
          disable_library "gnutls"
          disable_library "mbedtls"
          disable_library "libtls"
          ;;
        gnutls)
          disable_library "mbedtls"
          disable_library "libtls"
          disable_library "openssl"
          ;;
        mbedtls)
          disable_library "gnutls"
          disable_library "libtls"
          disable_library "openssl"
          ;;
        libtls)
          disable_library "gnutls"
          disable_library "mbedtls"
          disable_library "openssl"
          ;;
      esac
    fi
  fi

  if truthy "$enable_streaming"; then
    if ! truthy "$enable_openssl" && truthy "$disable_openssl" && ! truthy "$enable_librtmp" && truthy "$disable_librtmp"; then
      if [[ -z "$crypto_type" ]]; then
        pick_cryto_lib
      fi
    fi
  fi
else
  echo -e "\n  [CONFIG] No bundles selected. No external libraries enabled except platform built-in libraries." >>"$LOG_FILE"
fi

if truthy "$build_nonfree"; then
  echo "WARNING: Non-free licensing selected. Ffmpeg and ffmpeg-kit 
  Binaries will be non-redistributable without proper licensing. You 
  are responsible for making sure you have the appropriate licensing 
  to distribute the binaries!" | tee -a "$LOG_FILE"

  if truthy "$enable_audio" || truthy "$enable_full"; then apply_preset "$CONFIG_AUDIO_NON_FREE"; fi
  if truthy "$enable_video" || truthy "$enable_full"; then apply_preset "$CONFIG_VIDEO_NON_FREE"; fi
  if truthy "$enable_streaming" || truthy "$enable_full"; then apply_preset "$CONFIG_STREAMING_NON_FREE"; fi
  if truthy "$enable_hardware" || truthy "$enable_full"; then apply_preset "$CONFIG_HARDWARE_NON_FREE"; fi
  if truthy "$enable_audio_ai" || truthy "$enable_full"; then apply_preset "$CONFIG_AUDIO_AI_NON_FREE"; fi
  if truthy "$enable_video_ai" || truthy "$enable_full"; then apply_preset "$CONFIG_VIDEO_AI_NON_FREE"; fi
  if truthy "$enable_ssh" || truthy "$enable_full"; then apply_preset "$CONFIG_SSH_NON_FREE"; fi

  if ! iswindows; then
    if truthy "$enable_smb" || truthy "$enable_full"; then apply_preset "$CONFIG_SMB_NON_FREE"; fi
  fi
fi

if truthy "$enable_audio" || truthy "$enable_full"; then apply_preset "$CONFIG_AUDIO"; fi
if truthy "$enable_video" || truthy "$enable_full"; then apply_preset "$CONFIG_VIDEO"; fi
if truthy "$enable_streaming" || truthy "$enable_full"; then apply_preset "$CONFIG_STREAMING"; fi
if truthy "$enable_hardware" || truthy "$enable_full"; then apply_preset "$CONFIG_HARDWARE"; fi
if truthy "$enable_audio_ai" || truthy "$enable_full"; then apply_preset "$CONFIG_AUDIO_AI"; fi
if truthy "$enable_video_ai" || truthy "$enable_full"; then apply_preset "$CONFIG_VIDEO_AI"; fi
if truthy "$enable_ssh" || truthy "$enable_full"; then apply_preset "$CONFIG_SSH"; fi

if ! iswindows; then
  if truthy "$enable_smb" || truthy "$enable_full"; then apply_preset "$CONFIG_SMB"; fi
fi

if ! truthy "$build_small"; then
  if truthy "$enable_audio" || truthy "$enable_full"; then apply_preset "$CONFIG_AUDIO_EXTRA"; fi
  if truthy "$enable_video" || truthy "$enable_full"; then apply_preset "$CONFIG_VIDEO_EXTRA"; fi
fi

if truthy "$enable_ssh" || truthy "$enable_full"; then apply_preset "$CONFIG_SSH"; fi
if truthy "$enable_smb" || truthy "$enable_full"; then apply_preset "$CONFIG_SMB"; fi

resolve_collisions

# strict gpl libraries
check_gpl_libraries

# disable unsupported by platform
disable_unsupported

echo -e "\n  [CONFIG] Enabling explicit libraries..." >>"$LOG_FILE"
for lib in "${explicit_enabled[@]}"; do
  enable_library "$lib"
done

echo -e "\n  [CONFIG] Disabling explicit libraries:" >>"$LOG_FILE"
for lib in "${explicit_disabled[@]}"; do
  disable_library "$lib"
done

check_missing_packages

get_platform_deps_file() {
  local platform="$1"
  case "$platform" in
    android) echo "$SCRIPTDIR/deps-android.sh" ;;
    ios|iphonesimulator) echo "$SCRIPTDIR/deps-ios.sh" ;;
    appletvos|appletvsimulator) echo "$SCRIPTDIR/deps-appletvos.sh" ;;
    macos) echo "$SCRIPTDIR/deps-macos.sh" ;;
    linux) echo "$SCRIPTDIR/deps-linux.sh" ;;
    windows) echo "$SCRIPTDIR/deps-windows.sh" ;;
    wasm) echo "$SCRIPTDIR/deps-wasm.sh" ;;
    *) echo "Unknown platform: $platform" >&2; return 1 ;;
  esac
}

main() {
  # single step with no dependency built mode
  if truthy "$dry_run"; then
    echo -e "INFO: --- Dry run mode enabled ---" | tee -a "$LOG_FILE"
    optimize_dependencies
    return 0
  fi
  if [[ -n $run_only ]]; then
    echo -e "INFO: --- Executing single function: $run_only ---" | tee -a "$LOG_FILE"
    echo -e "WARNING: This may fail if previous dependencies havent been built yet." | tee -a "$LOG_FILE"
    if [[ "$run_only" == build_* ]]; then
      if ! declare -F "$run_only" >/dev/null; then
        exit_message 1 "DEBUG: Invalid function: $run_only (not defined on $host_platform)"
      fi
      run_valid_function "$run_only"
    else
      eval "$run_only" || exit_message 1 "unable to run $run_only"
    fi
    echo | tee -a "$LOG_FILE"
    echo -e "INFO: --- Done executing single function: $run_only ---" | tee -a "$LOG_FILE"
  # multi-step with requested build_only step and its dependencies
  elif [[ -n "$build_only" ]]; then
    IFS=',' read -ra build_only_steps <<< "$build_only"
    declare -A BUILD_STEPS
    for step in "${build_only_steps[@]}"; do
      if [[ "$step" == build_* ]]; then
        if ! declare -F "$step" >/dev/null; then
          exit_message 1 "DEBUG: Invalid function: $step (not defined on $host_platform)"
        fi
        add_step "$step"
        if truthy "$build_dependents"; then
          deps_file="$(get_platform_deps_file "$host_platform")"
          printf -v deps_command '%q ' "$SCRIPTDIR/transitive-deps.sh" "$deps_file" "$step"
          dependents="$("$SCRIPTDIR/transitive-deps.sh" "$deps_file" "$step")"
          IFS=',' read -ra dependents_array <<< "$dependents"
          for dependent in "${dependents_array[@]}"; do
            add_step "$dependent"
          done
        fi
      else
        exit_message 1 "Invalid build function $step"
      fi
    done
    optimize_dependencies
    echo -e "INFO: --- Executing requested build step(s): $build_only ---" | tee -a "$LOG_FILE"
    run_valid_build_functions
    echo | tee -a "$LOG_FILE"
    echo -e "INFO: --- Done building requested build step(s): $build_only ---" | tee -a "$LOG_FILE"
  # multi-step build all starting from build_from
  elif [[ -n "$build_from" ]]; then
    if ! declare -F "$build_from" >/dev/null; then
      exit_message 1 "DEBUG: Invalid function: $build_from (not defined on $host_platform)"
    fi
    optimize_dependencies
    if step_name=$(find_build_step "$build_from"); then
      echo -e "INFO: --- Building dependencies from step: $step_name ---" | tee -a "$LOG_FILE"
      echo -e "WARNING: This may fail if previous dependencies havent been built yet." | tee -a "$LOG_FILE"
      run_valid_build_functions "$step_name"
      echo | tee -a "$LOG_FILE"
      echo -e "INFO: --- Done building dependencies from step: $step_name ---" | tee -a "$LOG_FILE"
    else
      exit_message 1 "Invalid step $build_from"
    fi
  # default mode
  else
    change_dir "$work_dir" || exit_message 1 "unable to change directory to $work_dir"
    optimize_dependencies
    # builds all dependencies
    truthy "$build_dependencies" && run_valid_build_functions
    # build ffmpeg mode
    truthy "$do_build_ffmpeg" && build_ffmpeg
    # build ffmpeg-kit mode
    truthy "$do_build_ffmpeg_kit" && build_ffmpeg_kit
     # build ffmpeg-kit bundle mode
    truthy "$create_bundle" && create_ffmpeg_kit_bundle
  fi
}

for arg; do
  case "$arg" in
    --reset-and-clean=*)
      path="${arg#*=}"
      [[ -n $path ]] && reset_and_clean "$(validate_path "prebuilt/src/$path")"
      [[ -z $path ]] && exit_message 1 "Valid folder not provided."
      echo "INFO: Attempting to clean prebuilt/src/$path..." | tee -a "$LOG_FILE"
      exit 0
      ;;
    --reset-and-clean)
      reset_and_clean
      exit 0
      ;;
  esac
done

main

[[ -f "$BUILT_STATE_FILE" ]] && rm -f "$BUILT_STATE_FILE"

echo -e "Ffmpeg-kit-builders finished successfully: $(ts)" | tee -a "$LOG_FILE"
exit 0
