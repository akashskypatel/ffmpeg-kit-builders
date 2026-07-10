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

echo -e "INFO: Build options: ${RUN_ARGS[*]}\n" 1>>"$LOG_FILE" 2>&1
[[ -f "$LOG_FILE" ]] && chmod -R a+rwx "$LOG_FILE" || true;

ff_flags_raw=()    # Original arguments: --ff-something
ff_flags_values=() # Extracted values: something

display_help() {
	echo -e "available option=value - [default_value] or (optional):
General Options:
	-h, --help                                                    display this help and exit
	-v, --version                                                 display version and exit
	-d, --debug                                                   build with debug information
	-f, --force                                                   force build
  -y                                                            accept all defaults and disables interactive prompts

Licensing options:
	--enable-gpl|--gpl                                            allow building GPL libraries, created libs will be 
	                                                              licensed under the GPLv3.0 [no]
	--enable-nonfree|--nonfree                                    build binaries will be non-redistributable

Feature Presets:
  --enable-base                                                 enable only base built-in ffmpeg libraries
                                                                cannot be combined with other presets
  --enable-full                                                 enable all available external libraries 
                                                                (based on gpl/non-gpl selection)
  --enable-small                                                exclude certain extra libraries from presets 
                                                                to reduce size (see --list-excluded)
  --enable-https                                                enable https libraries
  --enable-audio                                                enable all audio processing libraries
  --enable-audio-ai                                             enable all audio processing ai libraries
  --enable-video                                                enable all video processing libraries
  --enable-streaming                                            enable all streaming libraries
  --enable-video-ai-cpu                                         enable all video ai cpu based libraries
  --enable-video-ai-gpu[-cuda|-rocm]                            enable all video ai gpu:- interactive, 
                                                                cuda or rocm based libraries
  --enable-hardware                                             enable all hardware accel libraries
  --enable-ssh                                                  enable SSH/SFTP support
  --enable-smb                                                  enable SMB (SAMBA) file sharing protocol support
  --enable-mq                                                   enable distributed systems support

Bundle Presets (pre-defined collections of libraries to include in ffmpeg-kit bundle):
  --audio-bundle                                                contains https + audio only libraries in the final bundle
  --audio-ai-bundle                                             contains https + audio + audio only ai libraries 
                                                                in the final bundle
  --video-bundle                                                contains https + audio + video libraries 
                                                                in the final bundle
  --video-ai-cpu-bundle                                         contains https + audio + video + ai (cpu) 
                                                                libraries in the final bundle
  --video-ai-gpu[-cuda|-rocm]-bundle                            contains https + audio + video + ai (gpu [cuda|rocm]) 
                                                                libraries in the final bundle
  --video-hw-bundle                                             contains https + audio + video + hardware 
                                                                libraries in the final bundle
  --video-hw-ai-cpu-bundle                                      contains https + audio + video + hardware 
                                                                + ai (cpu) libraries in the final bundle
  --video-hw-ai-gpu[-cuda|-rocm]-bundle                         contains https + audio + video + hardware 
                                                                + ai (gpu [cuda|rocm]) libraries in the final bundle
                                                                libraries in the final bundle
  --full-bundle                                                 contains https + audio + video + hardware + ai + streaming 
                                                                + ssh + smb + mq libraries in the final bundle

Build Options:
	--host-platform=|--host=(linux|windows)                       where the compiled program will run
	--host-arch=|--arch=(i686|x86_64|arm64|armv7a|armv8a)          host cpu architecture (32-bit or 64-bit)
	--ffmpeg-git-checkout-version=[release/8.0]                   if you want to build a particular version of FFmpeg, 
	                                                              ex: n3.1.1 or a specific git hash
                                                                WARNING: This will most likely break ffmpeg-kit libraries
                                                                if the fftools version it too old.
	--ffmpeg-git-checkout=[https://github.com/FFmpeg/FFmpeg.git]  if you want to clone FFmpeg from other repositories
	--ffmpeg-source-dir=[default empty]                           specify the directory of ffmpeg source code. When 
	                                                              specified, git will not be used.
	--cflags=$original_cflags                                     override default CFLAGS
  --cxxflags=$original_cxxflags                                 override default CXXFLAGS
  --cppflags=$original_cppflags                                 override default CPPFLAGS
  --ldflags=$original_ldflags                                   override default LDFLAGS
	--git-get-latest=[n]                                          [do a git pull for latest code from repositories like 
	                                                              FFmpeg--can force a rebuild if changes are detected]
	--prefer-stable=[y]                                           build a few libraries from releases instead of git master
  --release=[local]|remote                                      create release zip of ffmpeg-kit bundled binaries to be distributed
                                                                local: create release zip locally
                                                                remote: publish release zip to GitHub releases
  --release-and-clean                                           create release zip of ffmpeg-kit bundled binaries to be distributed 
                                                                and clean ffmpeg and ffmpeg-kit build artifacts (dependencies are not deleted)
	--clean-builds=[shared]|static                                clean ffmpeg and ffmpeg-kit builds of type [shared] or static and exit
  --clean=[all]|ffmpeg|kit|bundle                               clean build artifacts of specified components. Pass as Comma-separated list
                                                                to specify multiple components. Blank value cleans all components.
  --resume                                                      resume previously inturrupted run (based on ~run.state file)

Advanced Dependency Control:
	--print-total-steps|--print-all-steps                         print dependency steps and list all step names by index
	--build-only={0..} OR [library_name]                          build only specific dependency (e.g. --build-only=libx264)
	--build-from={0..} OR [library_name]                          start building dependencies from given step
	--build-deps=[y]                                              builds the ffmpeg dependencies. Disable when dependencies
	                                                              are already built to reduce time.
	--build-deps-only                                             Only build dependency binaries. Will not build ffmpeg or 
                                                                ffmpeg-kit binaries. (static or shared build only affects 
                                                                ffmpeg and ffmpeg-kit. Dependencies are always built statically.)
	--build-ffmpeg-only=[shared]|static                           build ffmpeg binaries only of type [shared] or static. 
                                                                Does not (re)build ext-library dependencies.
                                                                By default ffmpeg-kit always needs a static build of ffmpeg 
                                                                to be present already. Missing dependencies will cause a failure
	--build-ffmpeg-kit-only=[shared]|static                       build ffmpeg-kit library and bundle only of type [shared] or static.
                                                                By default ffmpeg-kit always needs a static build of ffmpeg 
                                                                to be present already. Does not (re)build ext-library dependencies. 
                                                                Missing dependencies will cause a failure.
  --build-tests|--build-test|--test|--tests                     Build tests. By default tests are not built. 
  --debug-build|--build-debug                                   Build debug version of ffmpeg and ffmpeg-kit.
	--list-libraries                                              lists available ext-libraries that can be included

Dynamic Library Control:
	--enable-[library name]                                       enable specific library (e.g. --enable-libx264)
	--disable-[library name]                                      disable specific library (e.g. --disable-libxcb)
                                                                NOTE: disables will override enables if they conflict
	--ff-*                                                        pass additional ffmpeg parameters directly to configure.
	                                                              Example: --ff-disable-network passed as --disable-network
"
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
  -y)
    export accept_defaults=y
    echo "Skipping interactive. Accepting defult selections."
    shift
    ;;
  --debug-build|--build-debug)
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
        echo "Invalid release type: ${1#*=}. Defaulting to local."
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
  --host-platform=*|--host=*)
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
		echo -e "setting CFLAGS as $original_cflags"
		shift
		;;
  --cxxflags=*)
		append_cxxflags "${1#*=}"
		echo -e "setting CXXFLAGS as $original_cxxflags"
		shift
		;;
  --cppflags=*)
		append_cppflags "${1#*=}"
		echo -e "setting CPPFLAGS as $original_cppflags"
		shift
		;;
  --ldflags=*)
		append_ldflags "${1#*=}"
		echo -e "setting LDFLAGS as $original_ldflags"
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
	--build-deps=*)
		export build_dependencies="${1#*=}"
		shift
		;;
	--build-only=*)
		export build_only="${1#*=}"
		shift
		;;
	--build-from=*)
		export build_from="${1#*=}"
		shift
		;;
	--build-deps-only|--build-deps)
		export build_dependencies=y
		shift
		;;
  --build-ffmpeg-only|--build-ffmpeg|--ffmpeg)
    export build_ffmpeg_type=static
    export build_ffmpeg=y
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
    export build_ffmpeg=y
		shift
		;;
  --build-ffmpeg-kit-only|--build-ffmpeg-kit|--ffmpeg-kit|--kit)
    export build_ffmpeg_kit_type=shared
    export build_ffmpeg_kit=y
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
    export build_ffmpeg_kit=y
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
      export test_type=undefined
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
    shift
    ;;
  --enable-video)
    export enable_video=y
    shift
    ;;
  --enable-streaming)
    export enable_streaming=y
    shift
    ;;
  --enable-audio-ai)
    export enable_audio_ai=y
    shift
    ;;
  --enable-video-ai-cpu)
    export enable_video_ai=y
    export enable_audio_ai=y
    export gpu_support=n
    shift
    ;;
  # interactive
  --enable-video-ai-gpu)
    export enable_video_ai=y
    export enable_audio_ai=y
    export gpu_support=n
    shift
    ;;
  # cuda
  --enable-video-ai-gpu-cuda)
    export enable_video_ai=y
    export enable_audio_ai=y
    export gpu_support=y
    pick_gpu_type "cuda"
    shift
    ;;
  # rocm
  --enable-video-ai-gpu-rocm)
    export enable_video_ai=y
    export enable_audio_ai=y
    export gpu_support=y
    pick_gpu_type "rocm"
    shift
    ;;
  --enable-hardware|--enable-hw)
    export enable_hardware=y
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
  --video-hw-bundle)
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
		echo -e "Error, unknown option: '$1'."
		exit 1
		;;
	*)
    echo "Unknown argument: $1"
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
    echo "Error: could not find previous run.state file."
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
      apply_preset "$CONFIG_TVOS_UNSUPPORTED"
    fi
    ;;
    rpi)
    apply_preset "$CONFIG_RPI"
    ;;
    oh|openharmony|open-harmony|open_harmony|harmony)
    apply_preset "$CONFIG_OH"
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

  if truthy "$build_nonfree"; then
    echo "WARNING: Non-free licensing selected. Ffmpeg and ffmpeg-kit 
    Binaries will be non-redistributable without proper licensing. You 
    are responsible for making sure you have the appropriate licensing 
    to distribute the binaries!" | tee -a "$LOG_FILE"

    truthy "$enable_audio" || truthy "$enable_full" && apply_preset "$CONFIG_AUDIO_NON_FREE"
    truthy "$enable_video" || truthy "$enable_full" && apply_preset "$CONFIG_VIDEO_NON_FREE"
    truthy "$enable_streaming" || truthy "$enable_full" && apply_preset "$CONFIG_STREAMING_NON_FREE"
    truthy "$enable_hardware" || truthy "$enable_full" && apply_preset "$CONFIG_HARDWARE_NON_FREE"
    truthy "$enable_audio_ai" || truthy "$enable_full" && apply_preset "$CONFIG_AUDIO_AI_NON_FREE"
    truthy "$enable_video_ai" || truthy "$enable_full" && apply_preset "$CONFIG_VIDEO_AI_NON_FREE"
    truthy "$enable_ssh" || truthy "$enable_full" && apply_preset "$CONFIG_SSH_NON_FREE"

    if ! iswindows; then
      truthy "$enable_smb" || truthy "$enable_full" && apply_preset "$CONFIG_SMB_NON_FREE"
    fi
  fi

  truthy "$enable_audio" || truthy "$enable_full" && apply_preset "$CONFIG_AUDIO"
  truthy "$enable_video" || truthy "$enable_full" && apply_preset "$CONFIG_VIDEO"
  truthy "$enable_streaming" || truthy "$enable_full" && apply_preset "$CONFIG_STREAMING"
  truthy "$enable_hardware" || truthy "$enable_full" && apply_preset "$CONFIG_HARDWARE"
  truthy "$enable_audio_ai" || truthy "$enable_full" && apply_preset "$CONFIG_AUDIO_AI"
  truthy "$enable_video_ai" || truthy "$enable_full" && apply_preset "$CONFIG_VIDEO_AI"
  truthy "$enable_ssh" || truthy "$enable_full" && apply_preset "$CONFIG_SSH"

  if ! iswindows; then
    truthy "$enable_smb" || truthy "$enable_full" && apply_preset "$CONFIG_SMB"
  fi

  if ! truthy "$build_small"; then
    truthy "$enable_audio" || truthy "$enable_full" && apply_preset "$CONFIG_AUDIO_EXTRA"
    truthy "$enable_video" || truthy "$enable_full" && apply_preset "$CONFIG_VIDEO_EXTRA"
  fi

  truthy "$enable_ssh" || truthy "$enable_full" && apply_preset "$CONFIG_SSH"
  truthy "$enable_smb" || truthy "$enable_full" && apply_preset "$CONFIG_SMB"

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

  # disable deprecated libraries
  echo -e "\n  [CONFIG] Disabling deprecated libraries..." >>"$LOG_FILE"
  disable_library "libnpp"
  if ! truthy "$disable_libcelt" && truthy "$enable_libcelt"; then
  enable_library "libopus"
  disable_library "libcelt"
  fi

  resolve_collisions

  # strict gpl libraries
  check_gpl_libraries
fi

echo -e "\n  [CONFIG] Enabling explicit libraries..." >>"$LOG_FILE"
for lib in "${explicit_enabled[@]}"; do
  enable_library "$lib"
done

echo -e "\n  [CONFIG] Disabling explicit libraries:" >>"$LOG_FILE"
for lib in "${explicit_disabled[@]}"; do
  disable_library "$lib"
done

check_missing_packages

main() {
  # single step with no dependency built mode
  if [[ -n $run_only ]]; then
    echo -e "INFO: --- Executing single function: $run_only ---" | tee -a "$LOG_FILE"
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
    if [[ "$build_only" == build_* ]]; then
      if ! declare -F "$build_only" >/dev/null; then
        exit_message 1 "DEBUG: Invalid function: $build_only (not defined on $host_platform)"
      fi
      declare -A BUILD_STEPS
      add_step "$build_only"
      optimize_dependencies
    else
      exit_message 1 "Invalid build function $build_only"
    fi
    echo -e "INFO: --- Executing single build step: $build_only ---" | tee -a "$LOG_FILE"
    echo -e "WARNING: This may fail if previous dependencies havent been built yet." | tee -a "$LOG_FILE"
    run_valid_build_functions
    echo | tee -a "$LOG_FILE"
    echo -e "INFO: --- Done building single build step: $step_name ---" | tee -a "$LOG_FILE"
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
    truthy "$build_ffmpeg" && { 
      download_ffmpeg
      configure_ffmpeg
      install_ffmpeg
    }
    # build ffmpeg-kit mode
    truthy "$build_ffmpeg_kit" && {
     configure_ffmpeg_kit
     install_ffmpeg_kit
     }
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
