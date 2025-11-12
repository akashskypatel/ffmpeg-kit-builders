#!/bin/bash

#echo ${SCRIPTDIR}/source.sh
#echo "${SCRIPTDIR}/variable.sh"

source ${SCRIPTDIR}/source.sh
source "${SCRIPTDIR}/variable.sh"

error_exit()
{
    local error_msg="$1"
    shift 1

    if [ "$error_msg" ]; then
        printf "%s\n" "$error_msg" >&2
    else
        printf "an error occured\n" >&2
    fi
    exit 1
}

execute()
{
    local info_msg="$1"
    local error_msg="$2"
    local no_exit="$3"
    shift 3

    if [ ! "$error_msg" ]; then
        error_msg="error"
    fi
    if [[ $no_exit != "true" ]]; then
      "$@" >>"$LOG_FILE" 2>&1 || error_exit "$error_msg, check $LOG_FILE for details"
    else
      "$@" >>"$LOG_FILE" 2>&1
    fi
}

create_dir()
{
    local path="$1"

    echo "DEBUG: creating path ${path}" 1>> $LOG_FILE 2>&1

    if [ -z "$path" ]; then
        error_exit "ERROR: path argument is required"
    fi

    if [[ ! -e "$path" ]]; then
      execute "INFO: creating path: '$path'" "ERROR: unable to create directory '$path'" "false" \
          mkdir "-pv" "$path"
    else
      echo "DEBUG: directory already exists, skipping creation." 1>> $LOG_FILE 2>&1
    fi
    execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "false" \
          sudo chown -R "$USER":"$USER" "$path"
}

remove_path()
{
    local options=$1
    shift 1  # Remove options, leaving only paths
    
    echo "DEBUG: removing paths: $@" 1>> "$LOG_FILE" 2>&1

    if [ $# -eq 0 ]; then
        echo "ERROR: at least one path argument is required" 1>> "$LOG_FILE" 2>&1
        return 1
    fi

    for path in "$@"; do
        echo "DEBUG: processing path: $path" 1>> "$LOG_FILE" 2>&1
        
        if [[ -e "$path" ]]; then
            execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
                sudo chown -R "$USER":"$USER" "$path"

            execute "INFO: removing path: '$path'" "ERROR: unable to remove path '$path'" "true" \
                rm $options "$path"
        else
            echo "INFO: path ${path} does not exist" 1>> "$LOG_FILE" 2>&1
        fi
    done
}

change_dir()
{
    local path="$1"
    
    if [ -z "$path" ]; then
        error_exit "ERROR: path argument is required"
    fi

    if [[ -e "$path" ]]; then
      execute "INFO: changing to path: '$path'" "ERROR: unable to cd to directory '$path'" "false" \
          cd "$path"
    else
      echo "INFO: path ${path} does not exist" 1>> $LOG_FILE 2>&1
    fi
}

copy_path()
{
    local source_path="$1"
    local destination_path="$2"
    local options="${3:-}"  # Default to empty
    local skip_if_exists="${4:-false}"  # Default to false

    echo "DEBUG: copying from ${source_path} to ${destination_path}" 1>> "$LOG_FILE" 2>&1

    if [ -z "$source_path" ] || [ -z "$destination_path" ]; then
        error_exit "ERROR: both source and destination path arguments are required"
    fi

    if [ ! -e "$source_path" ]; then
        echo "ERROR: source path '$source_path' does not exist"
        return 0
    fi

    # Check if destination already exists
    if [ "$skip_if_exists" = "true" ] && [ -e "$destination_path" ]; then
        echo "INFO: destination '$destination_path' already exists, skipping copy" 1>> "$LOG_FILE" 2>&1
        return 0
    fi

    # Create destination directory if it doesn't exist
    local destination_dir
    destination_dir=$(dirname "$destination_path")
    
    if [ ! -d "$destination_dir" ]; then
        execute "INFO: creating destination directory: '$destination_dir'" "ERROR: unable to create destination directory '$destination_dir'" "false" \
            mkdir -pv "$destination_dir"
    fi

    # Perform the copy operation
    if [ -n "$options" ]; then
        execute "INFO: copying path: '$source_path' to '$destination_path' with options '$options'" "ERROR: unable to copy '$source_path' to '$destination_path'" "true" \
            cp $options "$source_path" "$destination_path"
    else
        execute "INFO: copying path: '$source_path' to '$destination_path'" "ERROR: unable to copy '$source_path' to '$destination_path'" "true" \
            cp -r "$source_path" "$destination_path"
    fi

    # Update permissions on the copied path
    execute "INFO: updating permissions on copied path: '$destination_path'" "ERROR: unable to update permissions on '$destination_path'" "true" \
        sudo chown -R "$USER":"$USER" "$destination_path"
}

check_files_exist()
{
    local skip_if_missing="${1:-false}"
    shift 1
    local files=("$@")

    echo "DEBUG: checking ${#files[@]} files" 1>> "$LOG_FILE" 2>&1

    if [ ${#files[@]} -eq 0 ]; then
        echo "ERROR: file list argument is required" 1>> "$LOG_FILE" 2>&1
        return 1
    fi

    local missing_files=()
    
    for file in "${files[@]}"; do
        if [ ! -e "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        if [ "$skip_if_missing" = "true" ]; then
            echo "INFO: ${#missing_files[@]} files are missing" 1>> "$LOG_FILE" 2>&1
            return 0
        else
            error_exit "ERROR: ${#missing_files[@]} required files are missing: ${missing_files[*]}"
        fi
    else
        echo "INFO: all ${#files[@]} files exist" 1>> "$LOG_FILE" 2>&1
    fi
}

get_arch_name() {
  case $1 in
  0) echo "arm-v7a" ;; # android
  1) echo "arm-v7a-neon" ;; # android
  2) echo "armv7" ;; # ios
  3) echo "armv7s" ;; # ios
  4) echo "arm64-v8a" ;; # android
  5) echo "arm64" ;; # ios, tvos, macos
  6) echo "arm64e" ;; # ios
  7) echo "i386" ;; # ios
  8) echo "x86" ;; # android
  9) echo "x86-64" ;; # android, ios, linux, macos, tvos, windows
  10) echo "x86-64-mac-catalyst" ;; # ios
  11) echo "arm64-mac-catalyst" ;; # ios
  12) echo "arm64-simulator" ;; # ios, tvos
  esac
}

get_full_arch_name() {
  case $1 in
  8) echo "i686" ;;
  9) echo "x86_64" ;;
  10) echo "x86_64-mac-catalyst" ;;
  *) get_arch_name "$1" ;;
  esac
}

from_arch_name() {
  case $1 in
  arm-v7a) echo 0 ;; # android
  arm-v7a-neon) echo 1 ;; # android
  armv7) echo 2 ;; # ios
  armv7s) echo 3 ;; # ios
  arm64-v8a) echo 4 ;; # android
  arm64) echo 5 ;; # ios, tvos, macos
  arm64e) echo 6 ;; # ios
  i386) echo 7 ;; # ios
  x86 | i686 | win32) echo 8 ;; # android, windows
  x86-64 | x86_64 | win64) echo 9 ;; # android, ios, linux, macos, tvos
  x86-64-mac-catalyst) echo 10 ;; # ios
  arm64-mac-catalyst) echo 11 ;; # ios
  arm64-simulator) echo 12 ;; # ios
  esac
}

get_library_name() {
  case $1 in
  0) echo "fontconfig" ;;
  1) echo "freetype" ;;
  2) echo "fribidi" ;;
  3) echo "gmp" ;;
  4) echo "gnutls" ;;
  5) echo "lame" ;;
  6) echo "libass" ;;
  7) echo "libiconv" ;;
  8) echo "libtheora" ;;
  9) echo "libvorbis" ;;
  10) echo "libvpx" ;;
  11) echo "libwebp" ;;
  12) echo "libxml2" ;;
  13) echo "opencore-amr" ;;
  14) echo "shine" ;;
  15) echo "speex" ;;
  16) echo "dav1d" ;;
  17) echo "kvazaar" ;;
  18) echo "x264" ;;
  19) echo "xvidcore" ;;
  20) echo "x265" ;;
  21) echo "libvidstab" ;;
  22) echo "rubberband" ;;
  23) echo "libilbc" ;;
  24) echo "opus" ;;
  25) echo "snappy" ;;
  26) echo "soxr" ;;
  27) echo "libaom" ;;
  28) echo "chromaprint" ;;
  29) echo "twolame" ;;
  30) echo "sdl" ;;
  31) echo "tesseract" ;;
  32) echo "openh264" ;;
  33) echo "vo-amrwbenc" ;;
  34) echo "zimg" ;;
  35) echo "openssl" ;;
  36) echo "srt" ;;
  37) echo "giflib" ;;
  38) echo "jpeg" ;;
  39) echo "libogg" ;;
  40) echo "libpng" ;;
  41) echo "libuuid" ;;
  42) echo "nettle" ;;
  43) echo "tiff" ;;
  44) echo "expat" ;;
  45) echo "libsndfile" ;;
  46) echo "leptonica" ;;
  47) echo "libsamplerate" ;;
  48) echo "harfbuzz" ;;
  49) echo "cpu-features" ;;
  50)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]]; then
      echo "android-zlib"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "ios-zlib"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
      echo "linux-zlib"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-zlib"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "tvos-zlib"
    fi
    ;;
  51) echo "linux-alsa" ;;
  52) echo "android-media-codec" ;;
  53)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "ios-audiotoolbox"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-audiotoolbox"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "tvos-audiotoolbox"
    fi
    ;;
  54)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "ios-bzip2"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-bzip2"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "tvos-bzip2"
    fi
    ;;
  55)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "ios-videotoolbox"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-videotoolbox"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "tvos-videotoolbox"
    fi
    ;;
  56)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "ios-avfoundation"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-avfoundation"
    fi
    ;;
  57)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "ios-libiconv"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-libiconv"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "tvos-libiconv"
    fi
    ;;
  58)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "ios-libuuid"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-libuuid"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "tvos-libuuid"
    fi
    ;;
  59)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-coreimage"
    fi
    ;;
  60)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-opencl"
    fi
    ;;
  61)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "macos-opengl"
    fi
    ;;
  62) echo "linux-fontconfig" ;;
  63) echo "linux-freetype" ;;
  64) echo "linux-fribidi" ;;
  65) echo "linux-gmp" ;;
  66) echo "linux-gnutls" ;;
  67) echo "linux-lame" ;;
  68) echo "linux-libass" ;;
  69) echo "linux-libiconv" ;;
  70) echo "linux-libtheora" ;;
  71) echo "linux-libvorbis" ;;
  72) echo "linux-libvpx" ;;
  73) echo "linux-libwebp" ;;
  74) echo "linux-libxml2" ;;
  75) echo "linux-opencore-amr" ;;
  76) echo "linux-shine" ;;
  77) echo "linux-speex" ;;
  78) echo "linux-opencl" ;;
  79) echo "linux-xvidcore" ;;
  80) echo "linux-x265" ;;
  81) echo "linux-libvidstab" ;;
  82) echo "linux-rubberband" ;;
  83) echo "linux-v4l2" ;;
  84) echo "linux-opus" ;;
  85) echo "linux-snappy" ;;
  86) echo "linux-soxr" ;;
  87) echo "linux-twolame" ;;
  88) echo "linux-sdl" ;;
  89) echo "linux-tesseract" ;;
  90) echo "linux-vaapi" ;;
  91) echo "linux-vo-amrwbenc" ;;
  esac
}

from_library_name() {
  case $1 in
  fontconfig) echo 0 ;;
  freetype) echo 1 ;;
  fribidi) echo 2 ;;
  gmp) echo 3 ;;
  gnutls) echo 4 ;;
  lame) echo 5 ;;
  libass) echo 6 ;;
  libiconv) echo 7 ;;
  libtheora) echo 8 ;;
  libvorbis) echo 9 ;;
  libvpx) echo 10 ;;
  libwebp) echo 11 ;;
  libxml2) echo 12 ;;
  opencore-amr) echo 13 ;;
  shine) echo 14 ;;
  speex) echo 15 ;;
  dav1d) echo 16 ;;
  kvazaar) echo 17 ;;
  x264) echo 18 ;;
  xvidcore) echo 19 ;;
  x265) echo 20 ;;
  libvidstab) echo 21 ;;
  rubberband) echo 22 ;;
  libilbc) echo 23 ;;
  opus) echo 24 ;;
  snappy) echo 25 ;;
  soxr) echo 26 ;;
  libaom) echo 27 ;;
  chromaprint) echo 28 ;;
  twolame) echo 29 ;;
  sdl) echo 30 ;;
  tesseract) echo 31 ;;
  openh264) echo 32 ;;
  vo-amrwbenc) echo 33 ;;
  zimg) echo 34 ;;
  openssl) echo 35 ;;
  srt) echo 36 ;;
  giflib) echo 37 ;;
  jpeg) echo 38 ;;
  libogg) echo 39 ;;
  libpng) echo 40 ;;
  libuuid) echo 41 ;;
  nettle) echo 42 ;;
  tiff) echo 43 ;;
  expat) echo 44 ;;
  libsndfile) echo 45 ;;
  leptonica) echo 46 ;;
  libsamplerate) echo 47 ;;
  harfbuzz) echo 48 ;;
  cpu-features) echo 49 ;;
  android-zlib | ios-zlib | linux-zlib | macos-zlib | tvos-zlib) echo 50 ;;
  linux-alsa) echo 51 ;;
  android-media-codec) echo 52 ;;
  ios-audiotoolbox | macos-audiotoolbox | tvos-audiotoolbox) echo 53 ;;
  ios-bzip2 | macos-bzip2 | tvos-bzip2) echo 54 ;;
  ios-videotoolbox | macos-videotoolbox | tvos-videotoolbox) echo 55 ;;
  ios-avfoundation | macos-avfoundation) echo 56 ;;
  ios-libiconv | macos-libiconv | tvos-libiconv) echo 57 ;;
  ios-libuuid | macos-libuuid | tvos-libuuid) echo 58 ;;
  macos-coreimage) echo 59 ;;
  macos-opencl) echo 60 ;;
  macos-opengl) echo 61 ;;
  linux-fontconfig) echo 62 ;;
  linux-freetype) echo 63 ;;
  linux-fribidi) echo 64 ;;
  linux-gmp) echo 65 ;;
  linux-gnutls) echo 66 ;;
  linux-lame) echo 67 ;;
  linux-libass) echo 68 ;;
  linux-libiconv) echo 69 ;;
  linux-libtheora) echo 70 ;;
  linux-libvorbis) echo 71 ;;
  linux-libvpx) echo 72 ;;
  linux-libwebp) echo 73 ;;
  linux-libxml2) echo 74 ;;
  linux-opencore-amr) echo 75 ;;
  linux-shine) echo 76 ;;
  linux-speex) echo 77 ;;
  linux-opencl) echo 78 ;;
  linux-xvidcore) echo 79 ;;
  linux-x265) echo 80 ;;
  linux-libvidstab) echo 81 ;;
  linux-rubberband) echo 82 ;;
  linux-v4l2) echo 83 ;;
  linux-opus) echo 84 ;;
  linux-snappy) echo 85 ;;
  linux-soxr) echo 86 ;;
  linux-twolame) echo 87 ;;
  linux-sdl) echo 88 ;;
  linux-tesseract) echo 89 ;;
  linux-vaapi) echo 90 ;;
  linux-vo-amrwbenc) echo 91 ;;
  esac
}

#
# 1. <library name>
#
is_library_supported_on_platform() {
  local library_index=$(from_library_name "$1")
  case ${library_index} in
  # ALL
  16 | 17 | 18 | 23 | 27 | 28 | 32 | 34 | 35 | 36 | 50)
    echo "0"
    ;;

  # ALL EXCEPT LINUX
  0 | 1 | 2 | 3 | 4 | 5 | 6 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 19 | 20 | 21 | 22 | 24 | 25 | 26 | 29 | 30 | 31 | 33 | 37 | 38 | 39 | 40 | 42 | 43 | 44 | 45 | 46 | 47 | 48)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
      echo "1"
    else
      echo "0"
    fi
    ;;

  # ANDROID
  7 | 41 | 49 | 52)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]]; then
      echo "0"
    else
      echo "1"
    fi
    ;;

  # ONLY LINUX
  51)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
      echo "0"
    else
      echo "1"
    fi
    ;;

  # ONLY IOS AND MACOS
  56)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]] && [[ $1 == "ios-avfoundation" ]]; then
      echo "0"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]] && [[ $1 == "macos-avfoundation" ]]; then
      echo "0"
    else
      echo "1"
    fi
    ;;

  # IOS, MACOS AND TVOS
  53 | 54 | 55 | 57 | 58)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "0"
    else
      echo "1"
    fi
    ;;

  # ONLY MACOS
  59 | 60 | 61)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "0"
    else
      echo "1"
    fi
    ;;

  # ONLY LINUX
  62 | 63 | 64 | 65 | 66 | 67 | 68 | 69 | 70 | 71 | 72 | 73 | 74 | 75 | 76 | 77 | 78 | 79 | 80 | 81 | 82 | 83 | 84 | 85 | 86 | 87 | 88 | 89 | 90 | 91 | 92)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
      echo "0"
    else
      echo "1"
    fi
    ;;
  *)
    echo "1"
    ;;
  esac
}

#
# 1. <arch name>
#
is_arch_supported_on_platform() {
  local arch_index=$(from_arch_name "$1")
  case ${arch_index} in
  $ARCH_X86_64)
    echo 1
    ;;

    # ANDROID
  $ARCH_ARM_V7A | $ARCH_ARM_V7A_NEON | $ARCH_ARM64_V8A | $ARCH_X86)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]]; then
      echo 1
    else
      echo 0
    fi
    ;;

    # IOS
  $ARCH_ARMV7 | $ARCH_ARMV7S | $ARCH_ARM64E | $ARCH_I386 | $ARCH_X86_64_MAC_CATALYST | $ARCH_ARM64_MAC_CATALYST)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo 1
    else
      echo 0
    fi
    ;;

    # IOS OR TVOS
  $ARCH_ARM64_SIMULATOR)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo 1
    else
      echo 0
    fi
    ;;

    # IOS, MACOS OR TVOS
  $ARCH_ARM64)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo 1
    else
      echo 0
    fi
    ;;
  *)
    echo 0
    ;;
  esac
}

get_package_config_file_name() {
  case $1 in
  1) echo "freetype2" ;;
  5) echo "libmp3lame" ;;
  8) echo "theora" ;;
  9) echo "vorbis" ;;
  10) echo "vpx" ;;
  12) echo "libxml-2.0" ;;
  13) echo "opencore-amrnb" ;;
  21) echo "vidstab" ;;
  27) echo "aom" ;;
  28) echo "libchromaprint" ;;
  30) echo "sdl2" ;;
  38) echo "libjpeg" ;;
  39) echo "ogg" ;;
  43) echo "libtiff-4" ;;
  45) echo "sndfile" ;;
  46) echo "lept" ;;
  47) echo "samplerate" ;;
  58) echo "uuid" ;;
  *) echo "$(get_library_name "$1")" ;;
  esac
}

get_meson_target_host_family() {
  case ${FFMPEG_KIT_BUILD_TYPE} in
  android)
    echo "android"
    ;;
  linux)
    echo "linux"
    ;;
  *)
    echo "darwin"
    ;;
  esac
}

get_meson_target_cpu_family() {
  case ${ARCH} in
  arm*)
    echo "arm"
    ;;
  x86-64*)
    echo "x86_64"
    ;;
  x86*)
    echo "x86"
    ;;
  *)
    echo "${ARCH}"
    ;;
  esac
}

get_target() {
  case ${ARCH} in
  *-mac-catalyst)
    echo "$(get_target_cpu)-apple-ios$(get_min_sdk_version)-macabi"
    ;;
  armv7 | armv7s | arm64e)
    echo "$(get_target_cpu)-apple-ios$(get_min_sdk_version)"
    ;;
  i386)
    echo "$(get_target_cpu)-apple-ios$(get_min_sdk_version)-simulator"
    ;;
  arm64)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "$(get_target_cpu)-apple-ios$(get_min_sdk_version)"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "$(get_target_cpu)-apple-macos$(get_min_sdk_version)"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "$(get_target_cpu)-apple-tvos$(get_min_sdk_version)"
    fi
    ;;
  arm64-simulator)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "$(get_target_cpu)-apple-ios$(get_min_sdk_version)-simulator"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "$(get_target_cpu)-apple-tvos$(get_min_sdk_version)-simulator"
    fi
    ;;
  x86-64 | x86_64)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]]; then
      echo "x86_64-linux-android"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "$(get_target_cpu)-apple-ios$(get_min_sdk_version)-simulator"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
      echo "$(get_target_cpu)-linux-gnu"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "$(get_target_cpu)-apple-darwin$(get_min_sdk_version)"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "$(get_target_cpu)-apple-tvos$(get_min_sdk_version)-simulator"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "windows" ]]; then
      echo "x86_64-w64-mingw32"
    fi
    ;;
  *)
    get_host
    ;;
  esac
}

get_host() {
  case ${ARCH} in
  arm-v7a | arm-v7a-neon)
    echo "arm-linux-androideabi"
    ;;
  armv7 | armv7s | arm64e | i386 | *-mac-catalyst)
    echo "$(get_target_cpu)-ios-darwin"
    ;;
  arm64-simulator)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "$(get_target_cpu)-ios-darwin"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "$(get_target_cpu)-tvos-darwin"
    fi
    ;;
  arm64-v8a)
    echo "aarch64-linux-android"
    ;;
  arm64)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
      echo "$(get_target_cpu)-ios-darwin"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
      echo "$(get_target_cpu)-apple-darwin"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
      echo "$(get_target_cpu)-tvos-darwin"
    fi
    ;;
  x86 | i686 | win32)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "windows" ]]; then
      echo "i686-w64-mingw32"
    else
      echo "i686-linux-android"
    fi
    ;;
  x86-64 | x86_64 | win64)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]] && [[ ${ARCH} != "win64" ]]; then
      echo "x86_64-linux-android"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]] && [[ ${ARCH} != "win64" ]]; then
      echo "$(get_target_cpu)-ios-darwin"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]] && [[ ${ARCH} != "win64" ]]; then
      echo "$(get_target_cpu)-linux-gnu"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]] && [[ ${ARCH} != "win64" ]]; then
      echo "$(get_target_cpu)-apple-darwin"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]] && [ [${ARCH} != "win64" ]]; then
      echo "$(get_target_cpu)-tvos-darwin"
    elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "windows" ]] || [[ ${ARCH} == "win64" ]]; then
      echo "x86_64-w64-mingw32"
    fi
    ;;
  esac
}

#
# 1. key
# 2. value
#
generate_custom_library_environment_variables() {
  CUSTOM_KEY=$(echo "CUSTOM_$1" | sed "s/\-/\_/g" | tr '[a-z]' '[A-Z]')
  CUSTOM_VALUE="$2"

  export "${CUSTOM_KEY}"="${CUSTOM_VALUE}"

  echo -e "INFO: Custom library env variable generated: ${CUSTOM_KEY}=${CUSTOM_VALUE}\n" 1>>"${BASEDIR}"/build.log 2>&1
}

skip_library() {
  SKIP_VARIABLE=$(echo "SKIP_$1" | sed "s/\-/\_/g")

  export "${SKIP_VARIABLE}"=1
}

no_output_redirection() {
  export NO_OUTPUT_REDIRECTION=1
}

no_workspace_cleanup_library() {
  NO_WORKSPACE_CLEANUP_VARIABLE=$(echo "NO_WORKSPACE_CLEANUP_$1" | sed "s/\-/\_/g")

  export "${NO_WORKSPACE_CLEANUP_VARIABLE}"=1
}

no_link_time_optimization() {
  export NO_LINK_TIME_OPTIMIZATION=1
}

enable_debug() {
  export FFMPEG_KIT_DEBUG="-g"

  BUILD_TYPE_ID+="debug "
}

optimize_for_speed() {
  export FFMPEG_KIT_OPTIMIZED_FOR_SPEED="1"
}

print_unknown_option() {
  echo -e "\n(*) Unknown option \"$1\".\n\nSee $0 --help for available options.\n"
  exit 1
}

print_unknown_library() {
  echo -e "\n(*) Unknown library \"$1\".\n\nSee $0 --help for available libraries.\n"
  exit 1
}

print_unknown_virtual_library() {
  echo -e "\n(*) Unknown virtual library \"$1\".\n\nThis is a bug and must be reported to project developers.\n"
  exit 1
}

print_unknown_arch() {
  echo -e "\n(*) Unknown architecture \"$1\".\n\nSee $0 --help for available architectures.\n"
  exit 1
}

print_unknown_arch_variant() {
  echo -e "\n(*) Unknown architecture variant \"$1\".\n\nSee $0 --help for available architecture variants.\n"
  exit 1
}

display_version() {
  COMMAND=$(echo "$0" | sed -e 's/\.\///g')

  echo -e "\
$COMMAND v$(get_ffmpeg_kit_version)
Copyright (c) 2018-2022 Taner Sener\n\
License LGPLv3.0: GNU LGPL version 3 or later\n\
<https://www.gnu.org/licenses/lgpl-3.0.en.html>\n\
This is free software: you can redistribute it and/or modify it under the terms of the \
GNU Lesser General Public License as published by the Free Software Foundation, \
either version 3 of the License, or (at your option) any later version."
}

get_ffmpeg_libavcodec_version() {
  local MAJOR=$(grep -Eo ' LIBAVCODEC_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavcodec/version_major.h | sed -e 's|LIBAVCODEC_VERSION_MAJOR||g;s| ||g')
  local MINOR=$(grep -Eo ' LIBAVCODEC_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavcodec/version.h | sed -e 's|LIBAVCODEC_VERSION_MINOR||g;s| ||g')
  local MICRO=$(grep -Eo ' LIBAVCODEC_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavcodec/version.h | sed -e 's|LIBAVCODEC_VERSION_MICRO||g;s| ||g')

  echo "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavcodec_major_version() {
  local MAJOR=$(grep -Eo ' LIBAVCODEC_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavcodec/version_major.h | sed -e 's|LIBAVCODEC_VERSION_MAJOR||g;s| ||g')

  echo "${MAJOR}"
}

get_ffmpeg_libavdevice_version() {
  local MAJOR=$(grep -Eo ' LIBAVDEVICE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version_major.h | sed -e 's|LIBAVDEVICE_VERSION_MAJOR||g;s| ||g')
  local MINOR=$(grep -Eo ' LIBAVDEVICE_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version.h | sed -e 's|LIBAVDEVICE_VERSION_MINOR||g;s| ||g')
  local MICRO=$(grep -Eo ' LIBAVDEVICE_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version.h | sed -e 's|LIBAVDEVICE_VERSION_MICRO||g;s| ||g')

  echo "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavdevice_major_version() {
  local MAJOR=$(grep -Eo ' LIBAVDEVICE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version_major.h | sed -e 's|LIBAVDEVICE_VERSION_MAJOR||g;s| ||g')

  echo "${MAJOR}"
}

get_ffmpeg_libavfilter_version() {
  local MAJOR=$(grep -Eo ' LIBAVFILTER_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version_major.h | sed -e 's|LIBAVFILTER_VERSION_MAJOR||g;s| ||g')
  local MINOR=$(grep -Eo ' LIBAVFILTER_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version.h | sed -e 's|LIBAVFILTER_VERSION_MINOR||g;s| ||g')
  local MICRO=$(grep -Eo ' LIBAVFILTER_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version.h | sed -e 's|LIBAVFILTER_VERSION_MICRO||g;s| ||g')

  echo "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavfilter_major_version() {
  local MAJOR=$(grep -Eo ' LIBAVFILTER_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version_major.h | sed -e 's|LIBAVFILTER_VERSION_MAJOR||g;s| ||g')

  echo "${MAJOR}"
}

get_ffmpeg_libavformat_version() {
  local MAJOR=$(grep -Eo ' LIBAVFORMAT_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavformat/version_major.h | sed -e 's|LIBAVFORMAT_VERSION_MAJOR||g;s| ||g')
  local MINOR=$(grep -Eo ' LIBAVFORMAT_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavformat/version.h | sed -e 's|LIBAVFORMAT_VERSION_MINOR||g;s| ||g')
  local MICRO=$(grep -Eo ' LIBAVFORMAT_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavformat/version.h | sed -e 's|LIBAVFORMAT_VERSION_MICRO||g;s| ||g')

  echo "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavformat_major_version() {
  local MAJOR=$(grep -Eo ' LIBAVFORMAT_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavformat/version_major.h | sed -e 's|LIBAVFORMAT_VERSION_MAJOR||g;s| ||g')

  echo "${MAJOR}"
}

get_ffmpeg_libavutil_version() {
  local MAJOR=$(grep -Eo ' LIBAVUTIL_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavutil/version.h | sed -e 's|LIBAVUTIL_VERSION_MAJOR||g;s| ||g')
  local MINOR=$(grep -Eo ' LIBAVUTIL_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavutil/version.h | sed -e 's|LIBAVUTIL_VERSION_MINOR||g;s| ||g')
  local MICRO=$(grep -Eo ' LIBAVUTIL_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavutil/version.h | sed -e 's|LIBAVUTIL_VERSION_MICRO||g;s| ||g')

  echo "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavutil_major_version() {
  local MAJOR=$(grep -Eo ' LIBAVUTIL_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavutil/version_major.h | sed -e 's|LIBAVUTIL_VERSION_MAJOR||g;s| ||g')

  echo "${MAJOR}"
}

get_ffmpeg_libswresample_version() {
  local MAJOR=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswresample/version_major.h | sed -e 's|LIBSWRESAMPLE_VERSION_MAJOR||g;s| ||g')
  local MINOR=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libswresample/version.h | sed -e 's|LIBSWRESAMPLE_VERSION_MINOR||g;s| ||g')
  local MICRO=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libswresample/version.h | sed -e 's|LIBSWRESAMPLE_VERSION_MICRO||g;s| ||g')

  echo "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libswresample_major_version() {
  local MAJOR=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswresample/version_major.h | sed -e 's|LIBSWRESAMPLE_VERSION_MAJOR||g;s| ||g')

  echo "${MAJOR}"
}

get_ffmpeg_libswscale_version() {
  local MAJOR=$(grep -Eo ' LIBSWSCALE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswscale/version_major.h | sed -e 's|LIBSWSCALE_VERSION_MAJOR||g;s| ||g')
  local MINOR=$(grep -Eo ' LIBSWSCALE_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libswscale/version.h | sed -e 's|LIBSWSCALE_VERSION_MINOR||g;s| ||g')
  local MICRO=$(grep -Eo ' LIBSWSCALE_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libswscale/version.h | sed -e 's|LIBSWSCALE_VERSION_MICRO||g;s| ||g')

  echo "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libswscale_major_version() {
  local MAJOR=$(grep -Eo ' LIBSWSCALE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswscale/version_major.h | sed -e 's|LIBSWSCALE_VERSION_MAJOR||g;s| ||g')

  echo "${MAJOR}"
}

#
# 1. LIBRARY NAME
#
get_ffmpeg_library_version() {
  case $1 in
    libavcodec)
      echo "$(get_ffmpeg_libavcodec_version)"
    ;;
    libavdevice)
      echo "$(get_ffmpeg_libavdevice_version)"
    ;;
    libavfilter)
      echo "$(get_ffmpeg_libavfilter_version)"
    ;;
    libavformat)
      echo "$(get_ffmpeg_libavformat_version)"
    ;;
    libavutil)
      echo "$(get_ffmpeg_libavutil_version)"
    ;;
    libswresample)
      echo "$(get_ffmpeg_libswresample_version)"
    ;;
    libswscale)
      echo "$(get_ffmpeg_libswscale_version)"
    ;;
  esac
}

#
# 1. LIBRARY NAME
#
get_ffmpeg_library_major_version() {
  case $1 in
    libavcodec)
      echo "$(get_ffmpeg_libavcodec_major_version)"
    ;;
    libavdevice)
      echo "$(get_ffmpeg_libavdevice_major_version)"
    ;;
    libavfilter)
      echo "$(get_ffmpeg_libavfilter_major_version)"
    ;;
    libavformat)
      echo "$(get_ffmpeg_libavformat_major_version)"
    ;;
    libavutil)
      echo "$(get_ffmpeg_libavutil_major_version)"
    ;;
    libswresample)
      echo "$(get_ffmpeg_libswresample_major_version)"
    ;;
    libswscale)
      echo "$(get_ffmpeg_libswscale_major_version)"
    ;;
  esac
}

display_help_options() {
  echo -e "Options:"
  echo -e "  -h, --help\t\t\tdisplay this help and exit"
  echo -e "  -v, --version\t\t\tdisplay version information and exit"
  echo -e "  -d, --debug\t\t\tbuild with debug information"
  echo -e "  -s, --speed\t\t\toptimize for speed instead of size"
  echo -e "  -f, --force\t\t\tignore warnings"
  if [ -n "$1" ]; then
    echo -e "$1"
  fi
  if [ -n "$2" ]; then
    echo -e "$2"
  fi
  if [ -n "$3" ]; then
    echo -e "$3"
  fi
  if [ -n "$4" ]; then
    echo -e "$4"
  fi
  echo -e ""
}

display_help_licensing() {
  echo -e "Licensing options:"
  echo -e "  --enable-gpl\t\t\tallow building GPL libraries, created libs will be licensed under the GPLv3.0 [no]\n"
}

display_help_common_libraries() {
  echo -e "  --enable-chromaprint\t\tbuild with chromaprint [no]"
  echo -e "  --enable-dav1d\t\tbuild with dav1d [no]"
  echo -e "  --enable-fontconfig\t\tbuild with fontconfig [no]"
  echo -e "  --enable-freetype\t\tbuild with freetype [no]"
  echo -e "  --enable-fribidi\t\tbuild with fribidi [no]"
  echo -e "  --enable-gmp\t\t\tbuild with gmp [no]"
  echo -e "  --enable-gnutls\t\tbuild with gnutls [no]"
  echo -e "  --enable-kvazaar\t\tbuild with kvazaar [no]"
  echo -e "  --enable-lame\t\t\tbuild with lame [no]"
  echo -e "  --enable-libaom\t\tbuild with libaom [no]"
  echo -e "  --enable-libass\t\tbuild with libass [no]"

  case ${FFMPEG_KIT_BUILD_TYPE} in
  android)
    echo -e "  --enable-libiconv\t\tbuild with libiconv [no]"
    ;;
  esac

  echo -e "  --enable-libilbc\t\tbuild with libilbc [no]"
  echo -e "  --enable-libtheora\t\tbuild with libtheora [no]"
  echo -e "  --enable-libvorbis\t\tbuild with libvorbis [no]"
  echo -e "  --enable-libvpx\t\tbuild with libvpx [no]"
  echo -e "  --enable-libwebp\t\tbuild with libwebp [no]"
  echo -e "  --enable-libxml2\t\tbuild with libxml2 [no]"
  echo -e "  --enable-opencore-amr\t\tbuild with opencore-amr [no]"
  echo -e "  --enable-openh264\t\tbuild with openh264 [no]"
  echo -e "  --enable-openssl\t\tbuild with openssl [no]"
  echo -e "  --enable-opus\t\t\tbuild with opus [no]"
  echo -e "  --enable-sdl\t\t\tbuild with sdl [no]"
  echo -e "  --enable-shine\t\tbuild with shine [no]"
  echo -e "  --enable-snappy\t\tbuild with snappy [no]"
  echo -e "  --enable-soxr\t\t\tbuild with soxr [no]"
  echo -e "  --enable-speex\t\tbuild with speex [no]"
  echo -e "  --enable-srt\t\t\tbuild with srt [no]"
  echo -e "  --enable-tesseract\t\tbuild with tesseract [no]"
  echo -e "  --enable-twolame\t\tbuild with twolame [no]"
  echo -e "  --enable-vo-amrwbenc\t\tbuild with vo-amrwbenc [no]"
  echo -e "  --enable-zimg\t\t\tbuild with zimg [no]\n"
}

display_help_gpl_libraries() {
  echo -e "GPL libraries:"
  echo -e "  --enable-libvidstab\t\tbuild with libvidstab [no]"
  echo -e "  --enable-rubberband\t\tbuild with rubber band [no]"
  echo -e "  --enable-x264\t\t\tbuild with x264 [no]"
  echo -e "  --enable-x265\t\t\tbuild with x265 [no]"
  echo -e "  --enable-xvidcore\t\tbuild with xvidcore [no]\n"
}

display_help_custom_libraries() {
  echo -e "Custom libraries:"
  echo -e "  --enable-custom-library-[n]-name=value\t\t\tname of the custom library []"
  echo -e "  --enable-custom-library-[n]-repo=value\t\t\tgit repository of the source code []"
  echo -e "  --enable-custom-library-[n]-repo-commit=value\t\t\tgit commit to download the source code from []"
  echo -e "  --enable-custom-library-[n]-repo-tag=value\t\t\tgit tag to download the source code from []"
  echo -e "  --enable-custom-library-[n]-package-config-file-name=value\tpackage config file installed by the build script []"
  echo -e "  --enable-custom-library-[n]-ffmpeg-enable-flag=value\tlibrary name used in ffmpeg configure script to enable the library []"
  echo -e "  --enable-custom-library-[n]-license-file=value\t\tlicence file path relative to the library source folder []"
  if [ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]; then
    echo -e "  --enable-custom-library-[n]-uses-cpp\t\t\t\tflag to specify that the library uses libc++ []\n"
  else
    echo ""
  fi
}

display_help_advanced_options() {
  echo -e "Advanced options:"
  echo -e "  --reconf-LIBRARY\t\trun autoreconf before building LIBRARY [no]"
  echo -e "  --redownload-LIBRARY\t\tdownload LIBRARY even if it is detected as already downloaded [no]"
  echo -e "  --rebuild-LIBRARY\t\tbuild LIBRARY even if it is detected as already built [no]"
  if [ -n "$1" ]; then
    echo -e "$1"
  fi
  if [ -n "$2" ]; then
    echo -e "$2"
  fi
  echo -e ""
}

#
# 1. <library name>
#
reconf_library() {
  local RECONF_VARIABLE=$(echo "RECONF_$1" | sed "s/\-/\_/g")
  local library_supported=0

  for library in {0..49}; do
    library_name=$(get_library_name ${library})
    local library_supported_on_platform=$(is_library_supported_on_platform "${library_name}")

    if [[ $1 != "ffmpeg" ]] && [[ ${library_name} == "$1" ]] && [[ ${library_supported_on_platform} -eq 0 ]]; then
      export ${RECONF_VARIABLE}=1
      RECONF_LIBRARIES+=($1)
      library_supported=1
    fi
  done

  if [[ ${library_supported} -ne 1 ]]; then
    export ${RECONF_VARIABLE}=1
    RECONF_LIBRARIES+=($1)
    echo -e "INFO: --reconf flag detected for custom library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
  else
    echo -e "INFO: --reconf flag detected for library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
  fi
}

#
# 1. <library name>
#
rebuild_library() {
  local REBUILD_VARIABLE=$(echo "REBUILD_$1" | sed "s/\-/\_/g")
  local library_supported=0

  for library in {0..49}; do
    library_name=$(get_library_name ${library})
    local library_supported_on_platform=$(is_library_supported_on_platform "${library_name}")

    if [[ $1 != "ffmpeg" ]] && [[ ${library_name} == "$1" ]] && [[ ${library_supported_on_platform} -eq 0 ]]; then
      export ${REBUILD_VARIABLE}=1
      REBUILD_LIBRARIES+=($1)
      library_supported=1
    fi
  done

  if [[ ${library_supported} -ne 1 ]]; then
    export ${REBUILD_VARIABLE}=1
    REBUILD_LIBRARIES+=($1)
    echo -e "INFO: --rebuild flag detected for custom library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
  else
    echo -e "INFO: --rebuild flag detected for library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
  fi
}

#
# 1. <library name>
#
redownload_library() {
  local REDOWNLOAD_VARIABLE=$(echo "REDOWNLOAD_$1" | sed "s/\-/\_/g")
  local library_supported=0

  for library in {0..49}; do
    library_name=$(get_library_name ${library})
    local library_supported_on_platform=$(is_library_supported_on_platform "${library_name}")

    if [[ ${library_name} == "$1" ]] && [[ ${library_supported_on_platform} -eq 0 ]]; then
      export ${REDOWNLOAD_VARIABLE}=1
      REDOWNLOAD_LIBRARIES+=($1)
      library_supported=1
    fi
  done

  if [[ "ffmpeg" == $1 ]]; then
    export ${REDOWNLOAD_VARIABLE}=1
    REDOWNLOAD_LIBRARIES+=($1)
    library_supported=1
  fi

  if [[ ${library_supported} -ne 1 ]]; then
    export ${REDOWNLOAD_VARIABLE}=1
    REDOWNLOAD_LIBRARIES+=($1)
    echo -e "INFO: --redownload flag detected for custom library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
  else
    echo -e "INFO: --redownload flag detected for library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
  fi
}

#
# 1. library name
# 2. ignore unknown libraries
#
enable_library() {
  if [ -n "$1" ]; then
    local library_supported_on_platform=$(is_library_supported_on_platform "$1")
    if [[ $library_supported_on_platform == 0 ]]; then
      set_library "$1" 1
    elif [[ $2 -ne 1 ]]; then
      print_unknown_library "$1"
    fi
  fi
}

#
# 1. library name
# 2. enable/disable
#
set_library() {
  local library_supported_on_platform=$(is_library_supported_on_platform "$1")
  if [[ $library_supported_on_platform -ne 0 ]]; then
    return
  fi

  case $1 in
  android-zlib | ios-zlib | linux-zlib | macos-zlib | tvos-zlib)
    ENABLED_LIBRARIES[LIBRARY_SYSTEM_ZLIB]=$2
    ;;
  linux-alsa)
    ENABLED_LIBRARIES[LIBRARY_LINUX_ALSA]=$2
    ;;
  android-media-codec)
    ENABLED_LIBRARIES[LIBRARY_ANDROID_MEDIA_CODEC]=$2
    ;;
  ios-audiotoolbox | macos-audiotoolbox | tvos-audiotoolbox)
    ENABLED_LIBRARIES[LIBRARY_APPLE_AUDIOTOOLBOX]=$2
    ;;
  ios-bzip2 | macos-bzip2 | tvos-bzip2)
    ENABLED_LIBRARIES[LIBRARY_APPLE_BZIP2]=$2
    ;;
  ios-videotoolbox | macos-videotoolbox | tvos-videotoolbox)
    ENABLED_LIBRARIES[LIBRARY_APPLE_VIDEOTOOLBOX]=$2
    ;;
  ios-avfoundation | macos-avfoundation)
    ENABLED_LIBRARIES[LIBRARY_APPLE_AVFOUNDATION]=$2
    ;;
  ios-libiconv | macos-libiconv | tvos-libiconv)
    ENABLED_LIBRARIES[LIBRARY_APPLE_LIBICONV]=$2
    ;;
  ios-libuuid | macos-libuuid | tvos-libuuid)
    ENABLED_LIBRARIES[LIBRARY_APPLE_LIBUUID]=$2
    ;;
  macos-coreimage)
    ENABLED_LIBRARIES[LIBRARY_APPLE_COREIMAGE]=$2
    ;;
  macos-opencl)
    ENABLED_LIBRARIES[LIBRARY_APPLE_OPENCL]=$2
    ;;
  macos-opengl)
    ENABLED_LIBRARIES[LIBRARY_APPLE_OPENGL]=$2
    ;;
  chromaprint)
    ENABLED_LIBRARIES[LIBRARY_CHROMAPRINT]=$2
    ;;
  cpu-features)
    # CPU-FEATURES IS ALWAYS ENABLED
    ENABLED_LIBRARIES[LIBRARY_CPU_FEATURES]=1
    ;;
  dav1d)
    ENABLED_LIBRARIES[LIBRARY_DAV1D]=$2
    ;;
  fontconfig)
    ENABLED_LIBRARIES[LIBRARY_FONTCONFIG]=$2
    ENABLED_LIBRARIES[LIBRARY_EXPAT]=$2
    set_virtual_library "libiconv" $2
    set_virtual_library "libuuid" $2
    set_library "freetype" $2
    ;;
  freetype)
    ENABLED_LIBRARIES[LIBRARY_FREETYPE]=$2
    set_virtual_library "zlib" $2
    set_library "libpng" $2
    ;;
  fribidi)
    ENABLED_LIBRARIES[LIBRARY_FRIBIDI]=$2
    ;;
  gmp)
    ENABLED_LIBRARIES[LIBRARY_GMP]=$2
    ;;
  gnutls)
    ENABLED_LIBRARIES[LIBRARY_GNUTLS]=$2
    set_virtual_library "zlib" $2
    set_library "nettle" $2
    set_library "gmp" $2
    set_virtual_library "libiconv" $2
    ;;
  harfbuzz)
    ENABLED_LIBRARIES[LIBRARY_HARFBUZZ]=$2
    set_library "freetype" $2
    ;;
  kvazaar)
    ENABLED_LIBRARIES[LIBRARY_KVAZAAR]=$2
    ;;
  lame)
    ENABLED_LIBRARIES[LIBRARY_LAME]=$2
    set_virtual_library "libiconv" $2
    ;;
  libaom)
    ENABLED_LIBRARIES[LIBRARY_LIBAOM]=$2
    ;;
  libass)
    ENABLED_LIBRARIES[LIBRARY_LIBASS]=$2
    ENABLED_LIBRARIES[LIBRARY_EXPAT]=$2
    set_virtual_library "libuuid" $2
    set_library "freetype" $2
    set_library "fribidi" $2
    set_library "fontconfig" $2
    set_library "harfbuzz" $2
    set_virtual_library "libiconv" $2
    ;;
  libiconv)
    ENABLED_LIBRARIES[LIBRARY_LIBICONV]=$2
    ;;
  libilbc)
    ENABLED_LIBRARIES[LIBRARY_LIBILBC]=$2
    ;;
  libpng)
    ENABLED_LIBRARIES[LIBRARY_LIBPNG]=$2
    set_virtual_library "zlib" $2
    ;;
  libtheora)
    ENABLED_LIBRARIES[LIBRARY_LIBTHEORA]=$2
    ENABLED_LIBRARIES[LIBRARY_LIBOGG]=$2
    set_library "libvorbis" $2
    ;;
  libuuid)
    ENABLED_LIBRARIES[LIBRARY_LIBUUID]=$2
    ;;
  libvidstab)
    ENABLED_LIBRARIES[LIBRARY_LIBVIDSTAB]=$2
    ;;
  libvorbis)
    ENABLED_LIBRARIES[LIBRARY_LIBVORBIS]=$2
    ENABLED_LIBRARIES[LIBRARY_LIBOGG]=$2
    ;;
  libvpx)
    ENABLED_LIBRARIES[LIBRARY_LIBVPX]=$2
    ;;
  libwebp)
    ENABLED_LIBRARIES[LIBRARY_LIBWEBP]=$2
    ENABLED_LIBRARIES[LIBRARY_GIFLIB]=$2
    ENABLED_LIBRARIES[LIBRARY_JPEG]=$2
    set_library "tiff" $2
    set_library "libpng" $2
    ;;
  libxml2)
    ENABLED_LIBRARIES[LIBRARY_LIBXML2]=$2
    set_virtual_library "libiconv" $2
    ;;
  opencore-amr)
    ENABLED_LIBRARIES[LIBRARY_OPENCOREAMR]=$2
    ;;
  openh264)
    ENABLED_LIBRARIES[LIBRARY_OPENH264]=$2
    ;;
  openssl)
    ENABLED_LIBRARIES[LIBRARY_OPENSSL]=$2
    ;;
  opus)
    ENABLED_LIBRARIES[LIBRARY_OPUS]=$2
    ;;
  rubberband)
    ENABLED_LIBRARIES[LIBRARY_RUBBERBAND]=$2
    ENABLED_LIBRARIES[LIBRARY_SNDFILE]=$2
    ENABLED_LIBRARIES[LIBRARY_LIBSAMPLERATE]=$2
    ;;
  sdl)
    ENABLED_LIBRARIES[LIBRARY_SDL]=$2
    ;;
  shine)
    ENABLED_LIBRARIES[LIBRARY_SHINE]=$2
    ;;
  snappy)
    ENABLED_LIBRARIES[LIBRARY_SNAPPY]=$2
    set_virtual_library "zlib" $2
    ;;
  soxr)
    ENABLED_LIBRARIES[LIBRARY_SOXR]=$2
    ;;
  speex)
    ENABLED_LIBRARIES[LIBRARY_SPEEX]=$2
    ;;
  srt)
    ENABLED_LIBRARIES[LIBRARY_SRT]=$2
    set_library "openssl" $2
    ;;
  tesseract)
    ENABLED_LIBRARIES[LIBRARY_TESSERACT]=$2
    ENABLED_LIBRARIES[LIBRARY_LEPTONICA]=$2
    ENABLED_LIBRARIES[LIBRARY_LIBWEBP]=$2
    ENABLED_LIBRARIES[LIBRARY_GIFLIB]=$2
    ENABLED_LIBRARIES[LIBRARY_JPEG]=$2
    set_virtual_library "zlib" $2
    set_library "tiff" $2
    set_library "libpng" $2
    ;;
  twolame)
    ENABLED_LIBRARIES[LIBRARY_TWOLAME]=$2
    ENABLED_LIBRARIES[LIBRARY_SNDFILE]=$2
    ;;
  vo-amrwbenc)
    ENABLED_LIBRARIES[LIBRARY_VO_AMRWBENC]=$2
    ;;
  x264)
    ENABLED_LIBRARIES[LIBRARY_X264]=$2
    ;;
  x265)
    ENABLED_LIBRARIES[LIBRARY_X265]=$2
    ;;
  xvidcore)
    ENABLED_LIBRARIES[LIBRARY_XVIDCORE]=$2
    ;;
  zimg)
    ENABLED_LIBRARIES[LIBRARY_ZIMG]=$2
    ;;
  expat | giflib | jpeg | leptonica | libogg | libsamplerate | libsndfile)
    # THESE LIBRARIES ARE NOT ENABLED DIRECTLY
    ;;
  nettle)
    ENABLED_LIBRARIES[LIBRARY_NETTLE]=$2
    set_library "gmp" $2
    ;;
  tiff)
    ENABLED_LIBRARIES[LIBRARY_TIFF]=$2
    ENABLED_LIBRARIES[LIBRARY_JPEG]=$2
    ;;
  linux-fontconfig)
    ENABLED_LIBRARIES[LIBRARY_LINUX_FONTCONFIG]=$2
    set_library "linux-libiconv" $2
    set_library "linux-freetype" $2
    ;;
  linux-freetype)
    ENABLED_LIBRARIES[LIBRARY_LINUX_FREETYPE]=$2
    set_virtual_library "zlib" $2
    ;;
  linux-fribidi)
    ENABLED_LIBRARIES[LIBRARY_LINUX_FRIBIDI]=$2
    ;;
  linux-gmp)
    ENABLED_LIBRARIES[LIBRARY_LINUX_GMP]=$2
    ;;
  linux-gnutls)
    ENABLED_LIBRARIES[LIBRARY_LINUX_GNUTLS]=$2
    set_virtual_library "zlib" $2
    set_library "linux-gmp" $2
    set_library "linux-libiconv" $2
    ;;
  linux-lame)
    ENABLED_LIBRARIES[LIBRARY_LINUX_LAME]=$2
    set_library "linux-libiconv" $2
    ;;
  linux-libass)
    ENABLED_LIBRARIES[LIBRARY_LINUX_LIBASS]=$2
    set_library "linux-freetype" $2
    set_library "linux-fribidi" $2
    set_library "linux-fontconfig" $2
    set_library "linux-libiconv" $2
    ;;
  linux-libiconv)
    ENABLED_LIBRARIES[LIBRARY_LINUX_LIBICONV]=$2
    ;;
  linux-libtheora)
    ENABLED_LIBRARIES[LIBRARY_LINUX_LIBTHEORA]=$2
    set_library "linux-libvorbis" $2
    ;;
  linux-libvidstab)
    ENABLED_LIBRARIES[LIBRARY_LINUX_LIBVIDSTAB]=$2
    ;;
  linux-libvorbis)
    ENABLED_LIBRARIES[LIBRARY_LINUX_LIBVORBIS]=$2
    ;;
  linux-libvpx)
    ENABLED_LIBRARIES[LIBRARY_LINUX_LIBVPX]=$2
    ;;
  linux-libwebp)
    ENABLED_LIBRARIES[LIBRARY_LINUX_LIBWEBP]=$2
    set_virtual_library "zlib" $2
    ;;
  linux-libxml2)
    ENABLED_LIBRARIES[LIBRARY_LINUX_LIBXML2]=$2
    set_library "linux-libiconv" $2
    ;;
  linux-vaapi)
    ENABLED_LIBRARIES[LIBRARY_LINUX_VAAPI]=$2
    ;;
  linux-opencl)
    ENABLED_LIBRARIES[LIBRARY_LINUX_OPENCL]=$2
    ;;
  linux-opencore-amr)
    ENABLED_LIBRARIES[LIBRARY_LINUX_OPENCOREAMR]=$2
    ;;
  linux-opus)
    ENABLED_LIBRARIES[LIBRARY_LINUX_OPUS]=$2
    ;;
  linux-rubberband)
    ENABLED_LIBRARIES[LIBRARY_LINUX_RUBBERBAND]=$2
    ;;
  linux-sdl)
    ENABLED_LIBRARIES[LIBRARY_LINUX_SDL]=$2
    ;;
  linux-shine)
    ENABLED_LIBRARIES[LIBRARY_LINUX_SHINE]=$2
    ;;
  linux-snappy)
    ENABLED_LIBRARIES[LIBRARY_LINUX_SNAPPY]=$2
    set_virtual_library "zlib" $2
    ;;
  linux-soxr)
    ENABLED_LIBRARIES[LIBRARY_LINUX_SOXR]=$2
    ;;
  linux-speex)
    ENABLED_LIBRARIES[LIBRARY_LINUX_SPEEX]=$2
    ;;
  linux-tesseract)
    ENABLED_LIBRARIES[LIBRARY_LINUX_TESSERACT]=$2
    ENABLED_LIBRARIES[LIBRARY_LINUX_LIBWEBP]=$2
    set_virtual_library "zlib" $2
    ;;
  linux-twolame)
    ENABLED_LIBRARIES[LIBRARY_LINUX_TWOLAME]=$2
    ;;
  linux-v4l2)
    ENABLED_LIBRARIES[LIBRARY_LINUX_V4L2]=$2
    ;;
  linux-vo-amrwbenc)
    ENABLED_LIBRARIES[LIBRARY_LINUX_VO_AMRWBENC]=$2
    ;;
  linux-x265)
    ENABLED_LIBRARIES[LIBRARY_LINUX_X265]=$2
    ;;
  linux-xvidcore)
    ENABLED_LIBRARIES[LIBRARY_LINUX_XVIDCORE]=$2
    ;;
  *)
    print_unknown_library $1
    ;;
  esac
}

#
# 1. library name
# 2. enable/disable
#
# These libraries are supported by all platforms.
#
set_virtual_library() {
  case $1 in
  libiconv)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "apple" ]]; then
      ENABLED_LIBRARIES[LIBRARY_APPLE_LIBICONV]=$2
    else
      ENABLED_LIBRARIES[LIBRARY_LIBICONV]=$2
    fi
    ;;
  libuuid)
    if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]] || [[ ${FFMPEG_KIT_BUILD_TYPE} == "apple" ]]; then
      ENABLED_LIBRARIES[LIBRARY_APPLE_LIBUUID]=$2
    else
      ENABLED_LIBRARIES[LIBRARY_LIBUUID]=$2
    fi
    ;;
  zlib)
    ENABLED_LIBRARIES[LIBRARY_SYSTEM_ZLIB]=$2
    ;;
  *)
    print_unknown_virtual_library $1
    ;;
  esac
}

disable_arch() {
  local arch_supported_on_platform=$(is_arch_supported_on_platform "$1")
  if [[ $arch_supported_on_platform == 1 ]]; then
    set_arch "$1" 0
  else
    print_unknown_arch "$1"
  fi
}

set_arch() {
  case $1 in
  arm-v7a)
    ENABLED_ARCHITECTURES[ARCH_ARM_V7A]=$2
    ;;
  arm-v7a-neon)
    ENABLED_ARCHITECTURES[ARCH_ARM_V7A_NEON]=$2
    ;;
  armv7)
    ENABLED_ARCHITECTURES[ARCH_ARMV7]=$2
    ;;
  armv7s)
    ENABLED_ARCHITECTURES[ARCH_ARMV7S]=$2
    ;;
  arm64-v8a)
    ENABLED_ARCHITECTURES[ARCH_ARM64_V8A]=$2
    ;;
  arm64)
    ENABLED_ARCHITECTURES[ARCH_ARM64]=$2
    ;;
  arm64-mac-catalyst)
    ENABLED_ARCHITECTURES[ARCH_ARM64_MAC_CATALYST]=$2
    ;;
  arm64-simulator)
    ENABLED_ARCHITECTURES[ARCH_ARM64_SIMULATOR]=$2
    ;;
  arm64e)
    ENABLED_ARCHITECTURES[ARCH_ARM64E]=$2
    ;;
  i386)
    ENABLED_ARCHITECTURES[ARCH_I386]=$2
    ;;
  x86)
    ENABLED_ARCHITECTURES[ARCH_X86]=$2
    ;;
  x86-64)
    ENABLED_ARCHITECTURES[ARCH_X86_64]=$2
    ;;
  x86-64-mac-catalyst)
    ENABLED_ARCHITECTURES[ARCH_X86_64_MAC_CATALYST]=$2
    ;;
  *)
    print_unknown_arch "$1"
    ;;
  esac
}

check_if_dependency_rebuilt() {
  case $1 in
  cpu-features)
    set_dependency_rebuilt_flag "libvpx"
    set_dependency_rebuilt_flag "openh264"
    ;;
  expat)
    set_dependency_rebuilt_flag "fontconfig"
    set_dependency_rebuilt_flag "libass"
    ;;
  fontconfig)
    set_dependency_rebuilt_flag "libass"
    ;;
  freetype)
    set_dependency_rebuilt_flag "fontconfig"
    set_dependency_rebuilt_flag "libass"
    set_dependency_rebuilt_flag "harfbuzz"
    ;;
  fribidi)
    set_dependency_rebuilt_flag "libass"
    ;;
  giflib)
    set_dependency_rebuilt_flag "libwebp"
    set_dependency_rebuilt_flag "leptonica"
    set_dependency_rebuilt_flag "tesseract"
    ;;
  gmp)
    set_dependency_rebuilt_flag "gnutls"
    set_dependency_rebuilt_flag "nettle"
    ;;
  harfbuzz)
    set_dependency_rebuilt_flag "libass"
    ;;
  jpeg)
    set_dependency_rebuilt_flag "tiff"
    set_dependency_rebuilt_flag "libwebp"
    set_dependency_rebuilt_flag "leptonica"
    set_dependency_rebuilt_flag "tesseract"
    ;;
  leptonica)
    set_dependency_rebuilt_flag "tesseract"
    ;;
  libiconv)
    set_dependency_rebuilt_flag "fontconfig"
    set_dependency_rebuilt_flag "gnutls"
    set_dependency_rebuilt_flag "lame"
    set_dependency_rebuilt_flag "libass"
    set_dependency_rebuilt_flag "libxml2"
    ;;
  libogg)
    set_dependency_rebuilt_flag "libvorbis"
    set_dependency_rebuilt_flag "libtheora"
    ;;
  libpng)
    set_dependency_rebuilt_flag "freetype"
    set_dependency_rebuilt_flag "libwebp"
    set_dependency_rebuilt_flag "libass"
    set_dependency_rebuilt_flag "leptonica"
    set_dependency_rebuilt_flag "tesseract"
    ;;
  libsamplerate)
    set_dependency_rebuilt_flag "rubberband"
    ;;
  libsndfile)
    set_dependency_rebuilt_flag "twolame"
    set_dependency_rebuilt_flag "rubberband"
    ;;
  libuuid)
    set_dependency_rebuilt_flag "fontconfig"
    set_dependency_rebuilt_flag "libass"
    ;;
  libvorbis)
    set_dependency_rebuilt_flag "libtheora"
    ;;
  libwebp)
    set_dependency_rebuilt_flag "leptonica"
    set_dependency_rebuilt_flag "tesseract"
    ;;
  nettle)
    set_dependency_rebuilt_flag "gnutls"
    ;;
  openssl)
    set_dependency_rebuilt_flag "srt"
    ;;
  tiff)
    set_dependency_rebuilt_flag "libwebp"
    set_dependency_rebuilt_flag "leptonica"
    set_dependency_rebuilt_flag "tesseract"
    ;;
  esac
}

set_dependency_rebuilt_flag() {
  DEPENDENCY_REBUILT_VARIABLE=$(echo "DEPENDENCY_REBUILT_$1" | sed "s/\-/\_/g")
  export "${DEPENDENCY_REBUILT_VARIABLE}"=1
}

print_enabled_architectures() {
  echo -n "Architectures: "

  let enabled=0
  for print_arch in {0..12}; do
    if [[ ${ENABLED_ARCHITECTURES[$print_arch]} -eq 1 ]]; then
      if [[ ${enabled} -ge 1 ]]; then
        echo -n ", "
      fi
      echo -n "$(get_arch_name "${print_arch}")"
      enabled=$((${enabled} + 1))
    fi
  done

  if [ ${enabled} -gt 0 ]; then
    echo ""
  else
    echo "none"
  fi
}

print_enabled_architecture_variants() {
  echo -n "Architecture variants: "

  let enabled=0
  for print_arch_var in {1..8}; do
    if [[ ${ENABLED_ARCHITECTURE_VARIANTS[$print_arch_var]} -eq 1 ]]; then
      if [[ ${enabled} -ge 1 ]]; then
        echo -n ", "
      fi
      echo -n "$(get_apple_architecture_variant "${print_arch_var}")"
      enabled=$((${enabled} + 1))
    fi
  done

  if [ ${enabled} -gt 0 ]; then
    echo ""
  else
    echo "none"
  fi
}

print_enabled_libraries() {
  echo -n "Libraries: "

  let enabled=0

  # SUPPLEMENTARY LIBRARIES NOT PRINTED
  for library in {50..57} {59..91} {0..36}; do
    if [[ ${ENABLED_LIBRARIES[$library]} -eq 1 ]]; then
      if [[ ${enabled} -ge 1 ]]; then
        echo -n ", "
      fi
      echo -n "$(get_library_name "${library}")"
      enabled=$((${enabled} + 1))
    fi
  done

  if [ ${enabled} -gt 0 ]; then
    echo ""
  else
    echo "none"
  fi
}

print_enabled_xcframeworks() {
  echo -n "xcframeworks: "

  let enabled=0

  # SUPPLEMENTARY LIBRARIES NOT PRINTED
  for library in {0..49}; do
    if [[ ${ENABLED_LIBRARIES[$library]} -eq 1 ]]; then
      if [[ ${enabled} -ge 1 ]]; then
        echo -n ", "
      fi
      echo -n "$(get_library_name "${library}")"
      enabled=$((${enabled} + 1))
    fi
  done

  if [[ ${enabled} -ge 1 ]]; then
    echo -n ", "
  fi

  for FFMPEG_LIB in "${FFMPEG_LIBS[@]}"; do
    echo -n "${FFMPEG_LIB}, "
  done

  echo "ffmpeg-kit"
}

print_reconfigure_requested_libraries() {
  local counter=0

  for RECONF_LIBRARY in "${RECONF_LIBRARIES[@]}"; do
    if [[ ${counter} -eq 0 ]]; then
      echo -n "Reconfigure: "
    else
      echo -n ", "
    fi

    echo -n "${RECONF_LIBRARY}"

    counter=$((${counter} + 1))
  done

  if [[ ${counter} -gt 0 ]]; then
    echo ""
  fi
}

print_rebuild_requested_libraries() {
  local counter=0

  for REBUILD_LIBRARY in "${REBUILD_LIBRARIES[@]}"; do
    if [[ ${counter} -eq 0 ]]; then
      echo -n "Rebuild: "
    else
      echo -n ", "
    fi

    echo -n "${REBUILD_LIBRARY}"

    counter=$((${counter} + 1))
  done

  if [[ ${counter} -gt 0 ]]; then
    echo ""
  fi
}

print_redownload_requested_libraries() {
  local counter=0

  for REDOWNLOAD_LIBRARY in "${REDOWNLOAD_LIBRARIES[@]}"; do
    if [[ ${counter} -eq 0 ]]; then
      echo -n "Redownload: "
    else
      echo -n ", "
    fi

    echo -n "${REDOWNLOAD_LIBRARY}"

    counter=$((${counter} + 1))
  done

  if [[ ${counter} -gt 0 ]]; then
    echo ""
  fi
}

print_custom_libraries() {
  local counter=0

  for index in {1..20}; do
    LIBRARY_NAME="CUSTOM_LIBRARY_${index}_NAME"
    LIBRARY_REPO="CUSTOM_LIBRARY_${index}_REPO"
    LIBRARY_REPO_COMMIT="CUSTOM_LIBRARY_${index}_REPO_COMMIT"
    LIBRARY_REPO_TAG="CUSTOM_LIBRARY_${index}_REPO_TAG"
    LIBRARY_PACKAGE_CONFIG_FILE_NAME="CUSTOM_LIBRARY_${index}_PACKAGE_CONFIG_FILE_NAME"
    LIBRARY_FFMPEG_ENABLE_FLAG="CUSTOM_LIBRARY_${index}_FFMPEG_ENABLE_FLAG"
    LIBRARY_LICENSE_FILE="CUSTOM_LIBRARY_${index}_LICENSE_FILE"
    LIBRARY_USES_CPP="CUSTOM_LIBRARY_${index}_USES_CPP"

    if [[ -z "${!LIBRARY_NAME}" ]]; then
      echo -e "INFO: Custom library ${index} not detected\n" 1>>"${BASEDIR}"/build.log 2>&1
      break
    fi

    if [[ -z "${!LIBRARY_REPO}" ]]; then
      echo -e "INFO: Custom library ${index} repo not set\n" 1>>"${BASEDIR}"/build.log 2>&1
      continue
    fi

    if [[ -z "${!LIBRARY_REPO_COMMIT}" ]] && [[ -z "${!LIBRARY_REPO_TAG}" ]]; then
      echo -e "INFO: Custom library ${index} repo source not set. Both commit id and tag are empty\n" 1>>"${BASEDIR}"/build.log 2>&1
      continue
    fi

    if [[ -z "${!LIBRARY_PACKAGE_CONFIG_FILE_NAME}" ]]; then
      echo -e "INFO: Custom library ${index} package config file not set\n" 1>>"${BASEDIR}"/build.log 2>&1
      continue
    fi

    if [[ -z "${!LIBRARY_FFMPEG_ENABLE_FLAG}" ]]; then
      echo -e "INFO: Custom library ${index} ffmpeg enable flag not set\n" 1>>"${BASEDIR}"/build.log 2>&1
      continue
    fi

    if [[ -z "${!LIBRARY_LICENSE_FILE}" ]]; then
      echo -e "INFO: Custom library ${index} license file not set\n" 1>>"${BASEDIR}"/build.log 2>&1
      continue
    fi

    if [[ -n "${!LIBRARY_USES_CPP}" ]] && [[ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]]; then
      echo -e "INFO: Custom library ${index} is marked as uses libc++ \n" 1>>"${BASEDIR}"/build.log 2>&1
      export CUSTOM_LIBRARY_USES_CPP=1
    fi

    CUSTOM_LIBRARIES+=("${index}")

    if [[ ${counter} -eq 0 ]]; then
      echo -n "Custom libraries: "
    else
      echo -n ", "
    fi

    echo -n "${!LIBRARY_NAME}"

    echo -e "INFO: Custom library options found for ${!LIBRARY_NAME}\n" 1>>"${BASEDIR}"/build.log 2>&1

    counter=$((${counter} + 1))
  done

  if [[ ${counter} -gt 0 ]]; then
    echo -e "INFO: ${counter} valid custom library definitions found\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo ""
  fi
}

# 1 - library index
get_external_library_license_path() {
  case $1 in
  1) echo "${BASEDIR}/src/$(get_library_name "$1")/LICENSE.TXT" ;;
  12) echo "${BASEDIR}/src/$(get_library_name "$1")/Copyright" ;;
  35) echo "${BASEDIR}/src/$(get_library_name "$1")/LICENSE.txt" ;;
  3 | 42) echo "${BASEDIR}/src/$(get_library_name "$1")/COPYING.LESSERv3" ;;
  5 | 44) echo "${BASEDIR}/src/$(get_library_name "$1")/$(get_library_name "$1")/COPYING" ;;
  19) echo "${BASEDIR}/src/$(get_library_name "$1")/$(get_library_name "$1")/LICENSE" ;;
  26) echo "${BASEDIR}/src/$(get_library_name "$1")/COPYING.LGPL" ;;
  28 | 38) echo "${BASEDIR}/src/$(get_library_name "$1")/LICENSE.md " ;;
  30) echo "${BASEDIR}/src/$(get_library_name "$1")/COPYING.txt" ;;
  43) echo "${BASEDIR}/src/$(get_library_name "$1")/COPYRIGHT" ;;
  46) echo "${BASEDIR}/src/$(get_library_name "$1")/leptonica-license.txt" ;;
  4 | 10 | 13 | 17 | 21 | 27 | 31 | 32 | 36 | 40 | 49) echo "${BASEDIR}/src/$(get_library_name "$1")/LICENSE" ;;
  *) echo "${BASEDIR}/src/$(get_library_name "$1")/COPYING" ;;
  esac
}

# 1 - library index
# 2 - license path
copy_external_library_license() {
  license_path_array=("$2")
  for license_path in "${license_path_array[@]}"; do
    RESULT=$(copy_external_library_license_file "$1" "${license_path}")
    if [[ ${RESULT} -ne 0 ]]; then
      echo 1
      return
    fi
  done
  echo 0
}

# 1 - library index
# 2 - output path
copy_external_library_license_file() {
  cp $(get_external_library_license_path "$1") "$2" 1>>"${BASEDIR}"/build.log 2>&1
  if [[ $? -ne 0 ]]; then
    echo 1
    return
  fi
  echo 0
}

get_cmake_build_directory() {
  echo "${FFMPEG_KIT_TMPDIR}/cmake/build/$(get_build_directory)/${LIB_NAME}"
}

get_apple_cmake_system_name() {
  case ${FFMPEG_KIT_BUILD_TYPE} in
  macos)
    echo "Darwin"
    ;;
  tvos)
    echo "tvOS"
    ;;
  *)
    case ${ARCH} in
    *-mac-catalyst)
      echo "Darwin"
      ;;
    *)
      echo "iOS"
      ;;
    esac
    ;;
  esac
}

#
# 1. <library name>
#
autoreconf_library() {
  echo -e "\nINFO: Running full autoreconf for $1\n" 1>>"${BASEDIR}"/build.log 2>&1

  # FORCE INSTALL
  (autoreconf --force --install)

  local EXTRACT_RC=$?
  if [ ${EXTRACT_RC} -eq 0 ]; then
    echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
    return
  fi

  echo -e "\nDEBUG: Full autoreconf failed. Running full autoreconf with include for $1\n" 1>>"${BASEDIR}"/build.log 2>&1

  # FORCE INSTALL WITH m4
  (autoreconf --force --install -I m4)

  EXTRACT_RC=$?
  if [ ${EXTRACT_RC} -eq 0 ]; then
    echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
    return
  fi

  echo -e "\nDEBUG: Full autoreconf with include failed. Running autoreconf without force for $1\n" 1>>"${BASEDIR}"/build.log 2>&1

  # INSTALL WITHOUT FORCE
  (autoreconf --install)

  EXTRACT_RC=$?
  if [ ${EXTRACT_RC} -eq 0 ]; then
    echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
    return
  fi

  echo -e "\nDEBUG: Autoreconf without force failed. Running autoreconf without force with include for $1\n" 1>>"${BASEDIR}"/build.log 2>&1

  # INSTALL WITHOUT FORCE WITH m4
  (autoreconf --install -I m4)

  EXTRACT_RC=$?
  if [ ${EXTRACT_RC} -eq 0 ]; then
    echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
    return
  fi

  echo -e "\nDEBUG: Autoreconf without force with include failed. Running default autoreconf for $1\n" 1>>"${BASEDIR}"/build.log 2>&1

  # INSTALL DEFAULT
  (autoreconf)

  EXTRACT_RC=$?
  if [ ${EXTRACT_RC} -eq 0 ]; then
    echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
    return
  fi

  echo -e "\nDEBUG: Default autoreconf failed. Running default autoreconf with include for $1\n" 1>>"${BASEDIR}"/build.log 2>&1

  # INSTALL DEFAULT WITH m4
  (autoreconf -I m4)

  EXTRACT_RC=$?
  if [ ${EXTRACT_RC} -eq 0 ]; then
    echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
  else
    echo -e "\nDEBUG: Default autoreconf with include for $1 failed\n" 1>>"${BASEDIR}"/build.log 2>&1
  fi
}

#
# 1. <repo url>
# 2. <local folder path>
# 3. <commit id>
#
clone_git_repository_with_commit_id() {
  local RC

  (mkdir -p "$2" 1>>"${BASEDIR}"/build.log 2>&1)

  RC=$?

  if [ ${RC} -ne 0 ]; then
    echo -e "\nINFO: Failed to create local directory $2\n" 1>>"${BASEDIR}"/build.log 2>&1
    rm -rf "$2" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${RC}
    return
  fi

  echo -e "INFO: Cloning commit id $3 from repository $1 into local directory $2\n" 1>>"${BASEDIR}"/build.log 2>&1

  (git clone "$1" "$2" --depth 1 1>>"${BASEDIR}"/build.log 2>&1)

  RC=$?

  if [ ${RC} -ne 0 ]; then
    echo -e "\nINFO: Failed to clone $1\n" 1>>"${BASEDIR}"/build.log 2>&1
    rm -rf "$2" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${RC}
    return
  fi

  cd "$2" 1>>"${BASEDIR}"/build.log 2>&1

  RC=$?

  if [ ${RC} -ne 0 ]; then
    echo -e "\nINFO: Failed to cd into $2\n" 1>>"${BASEDIR}"/build.log 2>&1
    rm -rf "$2" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${RC}
    return
  fi

  (git fetch --depth 1 origin "$3" 1>>"${BASEDIR}"/build.log 2>&1)

  RC=$?

  if [ ${RC} -ne 0 ]; then
    echo -e "\nINFO: Failed to fetch commit id $3 from $1\n" 1>>"${BASEDIR}"/build.log 2>&1
    rm -rf "$2" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${RC}
    return
  fi

  (git checkout "$3" 1>>"${BASEDIR}"/build.log 2>&1)

  RC=$?

  if [ ${RC} -ne 0 ]; then
    echo -e "\nINFO: Failed to checkout commit id $3 from $1\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${RC}
    return
  fi

  echo ${RC}
}

#
# 1. <repo url>
# 2. <tag name>
# 3. <local folder path>
#
clone_git_repository_with_tag() {
  local RC

  (mkdir -p "$3" 1>>"${BASEDIR}"/build.log 2>&1)

  RC=$?

  if [ ${RC} -ne 0 ]; then
    echo -e "\nINFO: Failed to create local directory $3\n" 1>>"${BASEDIR}"/build.log 2>&1
    rm -rf "$3" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${RC}
    return
  fi

  echo -e "INFO: Cloning tag $2 from repository $1 into local directory $3\n" 1>>"${BASEDIR}"/build.log 2>&1

  (git clone --depth 1 --branch "$2" "$1" "$3" 1>>"${BASEDIR}"/build.log 2>&1)

  RC=$?

  if [ ${RC} -ne 0 ]; then
    echo -e "\nINFO: Failed to clone $1 -> $2\n" 1>>"${BASEDIR}"/build.log 2>&1
    rm -rf "$3" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${RC}
    return
  fi

  echo ${RC}
}

#
# 1. library index
#
is_gpl_licensed() {
  for gpl_library in {$LIBRARY_X264,$LIBRARY_XVIDCORE,$LIBRARY_X265,$LIBRARY_LIBVIDSTAB,$LIBRARY_RUBBERBAND,$LIBRARY_LINUX_XVIDCORE,$LIBRARY_LINUX_X265,$LIBRARY_LINUX_LIBVIDSTAB,$LIBRARY_LINUX_RUBBERBAND}; do
    if [[ $gpl_library -eq $1 ]]; then
      echo 0
      return
    fi
  done

  echo 1
}

downloaded_library_sources() {

  # DOWNLOAD FFMPEG SOURCE CODE FIRST
  DOWNLOAD_RESULT=$(download_library_source "ffmpeg")
  if [[ ${DOWNLOAD_RESULT} -ne 0 ]]; then
    echo -e "failed\n"
    exit 1
  fi

  for library in {1..50}; do
    if [[ ${!library} -eq 1 ]]; then
      library_name=$(get_library_name $((library - 1)))

      echo -e "\nDEBUG: Downloading library ${library_name}\n" 1>>"${BASEDIR}"/build.log 2>&1

      DOWNLOAD_RESULT=$(download_library_source "${library_name}")
      if [[ ${DOWNLOAD_RESULT} -ne 0 ]]; then
        echo -e "failed\n"
        exit 1
      fi
    fi
  done

  for custom_library_index in "${CUSTOM_LIBRARIES[@]}"; do
    library_name="CUSTOM_LIBRARY_${custom_library_index}_NAME"

    echo -e "\nDEBUG: Downloading custom library ${!library_name}\n" 1>>"${BASEDIR}"/build.log 2>&1

    DOWNLOAD_RESULT=$(download_custom_library_source "${custom_library_index}")
    if [[ ${DOWNLOAD_RESULT} -ne 0 ]]; then
      echo -e "failed\n"
      exit 1
    fi
  done

  echo -e "ok"
}

#
# 1. <url>
# 2. <local file name>
# 3. <on error action>
#
download() {
  if [ ! -d "${FFMPEG_KIT_TMPDIR}" ]; then
    create_dir "${FFMPEG_KIT_TMPDIR}"
  fi

  (curl --fail --location "$1" -o "${FFMPEG_KIT_TMPDIR}"/"$2" 1>>"${BASEDIR}"/build.log 2>&1)

  local RC=$?

  if [ ${RC} -eq 0 ]; then
    echo -e "\nDEBUG: Downloaded $1 to ${FFMPEG_KIT_TMPDIR}/$2\n" 1>>"${BASEDIR}"/build.log 2>&1
  else
    remove_path -f "${FFMPEG_KIT_TMPDIR}"/"$2" 1>>"${BASEDIR}"/build.log 2>&1

    echo -e -n "\nINFO: Failed to download $1 to ${FFMPEG_KIT_TMPDIR}/$2, rc=${RC}. " 1>>"${BASEDIR}"/build.log 2>&1

    if [ "$3" == "exit" ]; then
      echo -e "DEBUG: Build will now exit.\n" 1>>"${BASEDIR}"/build.log 2>&1
      exit 1
    else
      echo -e "DEBUG: Build will continue.\n" 1>>"${BASEDIR}"/build.log 2>&1
    fi
  fi

  echo ${RC}
}

#
# 1. library name
#
download_library_source() {
  local SOURCE_REPO_URL=""
  local LIB_NAME="$1"
  local LIB_LOCAL_PATH=${BASEDIR}/prebuilt/src/${LIB_NAME}
  local SOURCE_ID=""
  local LIBRARY_RC=""
  local DOWNLOAD_RC=""
  local SOURCE_TYPE=""

  echo -e "DEBUG: Downloading library source: $1\n" 1>>"${BASEDIR}"/build.log 2>&1

  SOURCE_REPO_URL=$(get_library_source "${LIB_NAME}" 1)
  SOURCE_ID=$(get_library_source "${LIB_NAME}" 2)
  SOURCE_TYPE=$(get_library_source "${LIB_NAME}" 3)

  LIBRARY_RC=$(library_is_downloaded "${LIB_NAME}")

  if [ ${LIBRARY_RC} -eq 0 ]; then
    echo -e "INFO: $1 already downloaded. Source folder found at ${LIB_LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
    return
  fi

  # Handle different source types
  case "${SOURCE_TYPE}" in
    "TAG"|"BRANCH"|"COMMIT")
      if [ "${SOURCE_TYPE}" == "TAG" ]; then
        DOWNLOAD_RC=$(clone_git_repository_with_tag "${SOURCE_REPO_URL}" "${SOURCE_ID}" "${LIB_LOCAL_PATH}")
      else
        DOWNLOAD_RC=$(clone_git_repository_with_commit_id "${SOURCE_REPO_URL}" "${LIB_LOCAL_PATH}" "${SOURCE_ID}")
      fi
      ;;
    "DOWNLOAD")
      # For DOWNLOAD type, SOURCE_REPO_URL is the direct download URL
      # and SOURCE_ID is the version identifier
      DOWNLOAD_RC=$(download_file "${SOURCE_REPO_URL}" "${LIB_NAME}" "${SOURCE_ID}")
      ;;
    *)
      echo -e "INFO: Unknown source type '${SOURCE_TYPE}' for library $1\n" 1>>"${BASEDIR}"/build.log 2>&1
      DOWNLOAD_RC=1
      ;;
  esac

  if [ ${DOWNLOAD_RC} -ne 0 ]; then
    echo -e "INFO: Downloading library $1 failed. Can not get library from ${SOURCE_REPO_URL}\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${DOWNLOAD_RC}
  else
    echo -e "\nINFO: $1 library downloaded" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
  fi
}

#
# 1. download url
# 2. library name
# 3. source id (version)
#
download_file() {
  local DOWNLOAD_URL="$1"
  local LIB_NAME="$2"
  local SOURCE_ID="$3"
  local LIB_LOCAL_PATH=${BASEDIR}/prebuilt/src/${LIB_NAME}
  local FILE_NAME=$(basename "${DOWNLOAD_URL}")
  local FILE_PATH="${FFMPEG_KIT_TMPDIR}/${FILE_NAME}"

  echo -e "DEBUG: Downloading file from ${DOWNLOAD_URL} to ${FILE_PATH}\n" 1>>"${BASEDIR}"/build.log 2>&1

  # Create temporary directory
  create_dir "${FFMPEG_KIT_TMPDIR}" 1>>"${BASEDIR}"/build.log 2>&1

  # Download the file
  (curl --fail --location "${DOWNLOAD_URL}" -o "${FILE_PATH}" 1>>"${BASEDIR}"/build.log 2>&1)

  local CURL_RC=$?

  if [ ${CURL_RC} -ne 0 ]; then
    echo -e "INFO: Failed to download ${DOWNLOAD_URL}\n" 1>>"${BASEDIR}"/build.log 2>&1
    remove_path -f "${FILE_PATH}" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${CURL_RC}
    return
  fi

  # Create library directory
  create_dir "${LIB_LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1

  local EXTRACT_RC=0

  # Extract based on file extension
  case "${FILE_NAME}" in
    *.zip)
      (unzip -q "${FILE_PATH}" -d "${LIB_LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1)
      EXTRACT_RC=$?
      ;;
    *.tar.gz|*.tgz)
      (tar -xzf "${FILE_PATH}" -C "${LIB_LOCAL_PATH}" --strip-components=1 1>>"${BASEDIR}"/build.log 2>&1)
      EXTRACT_RC=$?
      ;;
    *.tar.bz2)
      (tar -xjf "${FILE_PATH}" -C "${LIB_LOCAL_PATH}" --strip-components=1 1>>"${BASEDIR}"/build.log 2>&1)
      EXTRACT_RC=$?
      ;;
    *.tar.xz)
      (tar -xJf "${FILE_PATH}" -C "${LIB_LOCAL_PATH}" --strip-components=1 1>>"${BASEDIR}"/build.log 2>&1)
      EXTRACT_RC=$?
      ;;
    *)
      echo -e "INFO: Unknown archive format for ${FILE_NAME}\n" 1>>"${BASEDIR}"/build.log 2>&1
      EXTRACT_RC=1
      ;;
  esac

  # Clean up downloaded file
  remove_path -f "${FILE_PATH}" 1>>"${BASEDIR}"/build.log 2>&1

  if [ ${EXTRACT_RC} -ne 0 ]; then
    echo -e "INFO: Failed to extract ${FILE_NAME}\n" 1>>"${BASEDIR}"/build.log 2>&1
    remove_path -rf "${LIB_LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${EXTRACT_RC}
    return
  fi

  echo -e "DEBUG: Successfully downloaded and extracted ${LIB_NAME}\n" 1>>"${BASEDIR}"/build.log 2>&1
  echo 0
}

#
# 1. custom library index
#
download_custom_library_source() {
  local LIBRARY_NAME="CUSTOM_LIBRARY_$1_NAME"
  local LIBRARY_REPO="CUSTOM_LIBRARY_$1_REPO"
  local LIBRARY_REPO_COMMIT="CUSTOM_LIBRARY_$1_REPO_COMMIT"
  local LIBRARY_REPO_TAG="CUSTOM_LIBRARY_$1_REPO_TAG"

  local SOURCE_REPO_URL=""
  local LIB_NAME="${!LIBRARY_NAME}"
  local LIB_LOCAL_PATH=${BASEDIR}/prebuilt/src/${LIB_NAME}
  local SOURCE_ID=""
  local LIBRARY_RC=""
  local DOWNLOAD_RC=""
  local SOURCE_TYPE=""

  echo -e "DEBUG: Downloading custom library source: ${LIB_NAME}\n" 1>>"${BASEDIR}"/build.log 2>&1

  SOURCE_REPO_URL=${!LIBRARY_REPO}
  if [ -n "${!LIBRARY_REPO_TAG}" ]; then
    SOURCE_ID=${!LIBRARY_REPO_TAG}
    SOURCE_TYPE="TAG"
  else
    SOURCE_ID=${!LIBRARY_REPO_COMMIT}
    SOURCE_TYPE="COMMIT"
  fi

  LIBRARY_RC=$(library_is_downloaded "${LIB_NAME}")

  if [ ${LIBRARY_RC} -eq 0 ]; then
    echo -e "INFO: ${LIB_NAME} already downloaded. Source folder found at ${LIB_LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
    return
  fi

  if [ "${SOURCE_TYPE}" == "TAG" ]; then
    DOWNLOAD_RC=$(clone_git_repository_with_tag "${SOURCE_REPO_URL}" "${SOURCE_ID}" "${LIB_LOCAL_PATH}")
  else
    DOWNLOAD_RC=$(clone_git_repository_with_commit_id "${SOURCE_REPO_URL}" "${LIB_LOCAL_PATH}" "${SOURCE_ID}")
  fi

  if [ ${DOWNLOAD_RC} -ne 0 ]; then
    echo -e "INFO: Downloading custom library ${LIB_NAME} failed. Can not get library from ${SOURCE_REPO_URL}\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo ${DOWNLOAD_RC}
  else
    echo -e "\nINFO: ${LIB_NAME} custom library downloaded" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
  fi
}

download_gnu_config() {
  local SOURCE_REPO_URL=""
  local LIB_NAME="config"
  local LIB_LOCAL_PATH="${FFMPEG_KIT_TMPDIR}/source/${LIB_NAME}"
  local SOURCE_ID=""
  local DOWNLOAD_RC=""
  local SOURCE_TYPE=""
  REDOWNLOAD_VARIABLE=$(echo "REDOWNLOAD_$LIB_NAME")

  echo -e "DEBUG: Downloading gnu config source.\n" 1>>"${BASEDIR}"/build.log 2>&1

  SOURCE_REPO_URL=$(get_library_source "${LIB_NAME}" 1)
  SOURCE_ID=$(get_library_source "${LIB_NAME}" 2)
  SOURCE_TYPE=$(get_library_source "${LIB_NAME}" 3)

  if [[ -d "${LIB_LOCAL_PATH}" ]]; then
    if [[ ${REDOWNLOAD_VARIABLE} -eq 1 ]]; then
      echo -e "INFO: gnu config already downloaded but re-download requested\n" 1>>"${BASEDIR}"/build.log 2>&1
      remove_path -rf "${LIB_LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1
    else
      echo -e "INFO: gnu config already downloaded. Source folder found at ${LIB_LOCAL_PATH}\n" 1>>"${BASEDIR}"/build.log 2>&1
      return
    fi
  fi

  DOWNLOAD_RC=$(clone_git_repository_with_tag "${SOURCE_REPO_URL}" "${SOURCE_ID}" "${LIB_LOCAL_PATH}")

  if [[ ${DOWNLOAD_RC} -ne 0 ]]; then
    echo -e "INFO: Downloading gnu config failed. Can not get source from ${SOURCE_REPO_URL}\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo -e "failed\n"
    exit 1
  else
    echo -e "\nINFO: gnu config downloaded successfully\n" 1>>"${BASEDIR}"/build.log 2>&1
  fi
}

is_gnu_config_files_up_to_date() {
  echo $(grep aarch64-apple-darwin config.guess | wc -l 2>>"${BASEDIR}"/build.log)
}

get_cpu_count() {
  if [ "$(uname)" == "Darwin" ]; then
    echo $(sysctl -n hw.logicalcpu)
  else
    echo $cpu_count
  fi
}

#
# 1. <lib name>
#
library_is_downloaded() {
  local LOCAL_PATH
  local LIB_NAME=$1
  local FILE_COUNT
  local REDOWNLOAD_VARIABLE
  REDOWNLOAD_VARIABLE=$(echo "REDOWNLOAD_$1" | sed "s/\-/\_/g")

  LOCAL_PATH=${BASEDIR}/prebuilt/src/${LIB_NAME}

  echo -e "DEBUG: Checking if ${LIB_NAME} is already downloaded at ${LOCAL_PATH}\n" 1>>"${BASEDIR}"/build.log 2>&1

  if [ ! -d "${LOCAL_PATH}" ]; then
    echo -e "INFO: ${LOCAL_PATH} directory not found\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo 1
    return
  fi

  FILE_COUNT=$(ls -l "${LOCAL_PATH}" | wc -l)

  if [[ ${FILE_COUNT} -eq 0 ]]; then
    echo -e "INFO: No files found under ${LOCAL_PATH}\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo 1
    return
  fi

  if [[ ${REDOWNLOAD_VARIABLE} -eq 1 ]]; then
    echo -e "INFO: ${LIB_NAME} library already downloaded but re-download requested\n" 1>>"${BASEDIR}"/build.log 2>&1
    remove_path -rf "${LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1
    echo 1
  else
    echo -e "INFO: ${LIB_NAME} library already downloaded\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
  fi
}

library_is_installed() {
  local INSTALL_PATH=$1
  local LIB_NAME=$2
  local HEADER_COUNT
  local LIB_COUNT

  echo -e "DEBUG: Checking if ${LIB_NAME} is already built and installed at ${INSTALL_PATH}/${LIB_NAME}\n" 1>>"${BASEDIR}"/build.log 2>&1

  if [ ! -d "${INSTALL_PATH}"/"${LIB_NAME}" ]; then
    echo -e "INFO: ${INSTALL_PATH}/${LIB_NAME} directory not found\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
    return
  fi

  if [ ! -d "${INSTALL_PATH}/${LIB_NAME}/lib" ] && [ ! -d "${INSTALL_PATH}/${LIB_NAME}/lib64" ]; then
    echo -e "INFO: ${INSTALL_PATH}/${LIB_NAME}/lib{lib64} directory not found\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
    return
  fi

  if [ ! -d "${INSTALL_PATH}"/"${LIB_NAME}"/include ]; then
    echo -e "INFO: ${INSTALL_PATH}/${LIB_NAME}/include directory not found\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
    return
  fi

  HEADER_COUNT=$(ls -l "${INSTALL_PATH}"/"${LIB_NAME}"/include | wc -l)
  LIB_COUNT=$(ls -l ${INSTALL_PATH}/${LIB_NAME}/lib* | wc -l)

  if [[ ${HEADER_COUNT} -eq 0 ]]; then
    echo -e "INFO: No headers found under ${INSTALL_PATH}/${LIB_NAME}/include\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
    return
  fi

  if [[ ${LIB_COUNT} -eq 0 ]]; then
    echo -e "INFO: No libraries found under ${INSTALL_PATH}/${LIB_NAME}/lib{lib64}\n" 1>>"${BASEDIR}"/build.log 2>&1
    echo 0
    return
  fi

  echo -e "INFO: ${LIB_NAME} library is already built and installed\n" 1>>"${BASEDIR}"/build.log 2>&1
  echo 1
}

prepare_inline_sed() {
  if [ "$(uname)" == "Darwin" ]; then
    export SED_INLINE="sed -i .tmp"
  else
    export SED_INLINE="sed -i"
  fi
}

to_capital_case() {
  echo "$(echo ${1:0:1} | tr '[a-z]' '[A-Z]')${1:1}"
}

#
# 1. source file
# 2. destination file
#
overwrite_file() {
  copy_path "$2" "$2.bak" # backup
  remove_path -f "$2" 2>>"${BASEDIR}"/build.log
  copy_path "$1" "$2" 2>>"${BASEDIR}"/build.log
}

#
# 1. destination file
#
create_file() {
  remove_path -f "$1"
  echo "" > "$1" 1>>"${BASEDIR}"/build.log 2>&1
}

compare_versions() {
  VERSION_PARTS_1=($(echo $1 | tr "." " "))
  VERSION_PARTS_2=($(echo $2 | tr "." " "))

  for((i=0;(i<${#VERSION_PARTS_1[@]})&&(i<${#VERSION_PARTS_2[@]});i++))
  do

    local CURRENT_PART_1=${VERSION_PARTS_1[$i]}
    local CURRENT_PART_2=${VERSION_PARTS_2[$i]}

    if [[ -z ${CURRENT_PART_1} ]]; then
      CURRENT_PART_1=0
    fi

    if [[ -z ${CURRENT_PART_2} ]]; then
      CURRENT_PART_2=0
    fi

    if [[ CURRENT_PART_1 -gt CURRENT_PART_2 ]]; then
      echo "1"
      return;
    elif [[ CURRENT_PART_1 -lt CURRENT_PART_2 ]]; then
      echo "-1"
      return;
    fi
  done

  echo "0"
  return;
}

#
# 1. command
#
command_exists() {
  local COMMAND=$1
  if [[ -n "$(command -v $COMMAND)" ]]; then
    echo 0
  else
    echo 1
  fi
}

#
# 1. folder path
#
initialize_folder() {
  remove_path -rf "$1" 1>>"${BASEDIR}"/build.log 2>&1
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  create_dir "$1" 1>>"${BASEDIR}"/build.log 2>&1
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  return 0
}

#===============================================================================================
#                                           WINDOWS
#===============================================================================================

set_box_memory_size_bytes() {
  if [[ $OSTYPE == darwin* ]]; then
    box_memory_size_bytes=20000000000 # 20G fake it out for now :|
  else
    local ram_kilobytes=`grep MemTotal /proc/meminfo | awk '{print $2}'`
    local swap_kilobytes=`grep SwapTotal /proc/meminfo | awk '{print $2}'`
    box_memory_size_bytes=$[ram_kilobytes * 1024 + swap_kilobytes * 1024]
  fi
}

function sortable_version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

at_least_required_version() { # params: required actual
  local sortable_required=$(sortable_version $1)
  sortable_required=$(echo $sortable_required | sed 's/^0*//') # remove preceding zeroes, which bash later interprets as octal or screwy
  local sortable_actual=$(sortable_version $2)
  sortable_actual=$(echo $sortable_actual | sed 's/^0*//')
  [[ "$sortable_actual" -ge "$sortable_required" ]]
}

apt_not_installed() {
  for x in "$@"; do
    if ! dpkg -l "$x" | grep -q '^.i'; then
      need_install="$need_install $x"
    fi
  done
  echo "$need_install"
}

check_missing_packages () {
  # We will need this later if we don't want to just constantly be grepping the /etc/os-release file
  if [ -z "${VENDOR}" ] && grep -E '(centos|rhel)' /etc/os-release &> /dev/null; then
    # In RHEL this should always be set anyway. But not so sure about CentOS
    VENDOR="redhat"
  fi
  # zeranoe's build scripts use wget, though we don't here...
  local check_packages=('ragel' 'curl' 'pkg-config' 'make' 'git' 'svn' 'gcc' 'autoconf' 'automake' 'yasm' 'cvs' 'flex' 'bison' 'makeinfo' 'g++' 'ed' 'pax' 'unzip' 'patch' 'wget' 'xz' 'nasm' 'gperf' 'autogen' 'bzip2' 'realpath' 'clang' 'python' 'bc' 'autopoint')
  # autoconf-archive is just for leptonica FWIW
  # I'm not actually sure if VENDOR being set to centos is a thing or not. On all the centos boxes I can test on it's not been set at all.
  # that being said, if it where set I would imagine it would be set to centos... And this contition will satisfy the "Is not initially set"
  # case because the above code will assign "redhat" all the time.
  if [ -z "${VENDOR}" ] || [ "${VENDOR}" != "redhat" ] && [ "${VENDOR}" != "centos" ]; then
    check_packages+=('cmake')
  fi
  # libtool check is wonky...
  if [[ $OSTYPE == darwin* ]]; then
    check_packages+=('glibtoolize') # homebrew special :|
  else
    check_packages+=('libtoolize') # the rest of the world
  fi
  # Use hash to check if the packages exist or not. Type is a bash builtin which I'm told behaves differently between different versions of bash.
  for package in "${check_packages[@]}"; do
    hash "$package" &> /dev/null || missing_packages=("$package" "${missing_packages[@]}")
  done
  if [ "${VENDOR}" = "redhat" ] || [ "${VENDOR}" = "centos" ]; then
    if [ -n "$(hash cmake 2>&1)" ] && [ -n "$(hash cmake3 2>&1)" ]; then missing_packages=('cmake' "${missing_packages[@]}"); fi
  fi
  if [[ -n "${missing_packages[@]}" ]]; then
    clear
    echo "Could not find the following execs (svn is actually package subversion, makeinfo is actually package texinfo if you're missing them): ${missing_packages[*]}"
    echo 'Install the missing packages before running this script.'
    determine_distro

    apt_pkgs='subversion ragel curl texinfo g++ ed bison flex cvs yasm automake libtool autoconf gcc cmake git make pkg-config zlib1g-dev unzip pax nasm gperf autogen bzip2 autoconf-archive p7zip-full clang wget bc tesseract-ocr-eng autopoint python3-full'

    [[ $DISTRO == "debian" ]] && apt_pkgs="$apt_pkgs libtool-bin ed" # extra for debian
    case "$DISTRO" in
      Ubuntu)
        echo "for ubuntu:"
        echo "$ sudo apt-get update"
        ubuntu_ver="$(lsb_release -rs)"
        if at_least_required_version "18.04" "$ubuntu_ver"; then
          apt_pkgs="$apt_pkgs python3-distutils" # guess it's no longer built-in, lensfun requires it...
        fi
        if at_least_required_version "20.04" "$ubuntu_ver"; then
          apt_pkgs="$apt_pkgs python-is-python3" # needed
        fi
		if at_least_required_version "22.04" "$ubuntu_ver"; then
          apt_pkgs="$apt_pkgs ninja-build" # needed
        fi
        echo "$ sudo apt-get install $apt_pkgs -y"
        if uname -a | grep  -q -- "-microsoft" ; then
         echo NB if you use WSL Ubuntu 20.04 you need to do an extra step: https://github.com/rdp/ffmpeg-windows-build-helpers/issues/452
	fi
        ;;
      debian)
        echo "for debian:"
        echo "$ sudo apt-get update"
        # Debian version is always encoded in the /etc/debian_version
        # This file is deployed via the base-files package which is the essential one - deployed in all installations.
        # See their content for individual debian releases - https://sources.debian.org/src/base-files/
        # Stable releases contain a version number.
        # Testing/Unstable releases contain a textual codename description (e.g. bullseye/sid)
        #
        deb_ver="$(cat /etc/debian_version)"
        # Upcoming codenames taken from https://en.wikipedia.org/wiki/Debian_version_history
        #
        if [[ $deb_ver =~ bullseye ]]; then
            deb_ver="11"
        elif [[ $deb_ver =~ bookworm ]]; then
            deb_ver="12"
        elif [[ $deb_ver =~ trixie ]]; then
            deb_ver="13"
        fi
        if at_least_required_version "10" "$deb_ver"; then
          apt_pkgs="$apt_pkgs python3-distutils" # guess it's no longer built-in, lensfun requires it...
        fi
        if at_least_required_version "11" "$deb_ver"; then
          apt_pkgs="$apt_pkgs python-is-python3" # needed
        fi
        apt_missing="$(apt_not_installed "$apt_pkgs")"
        echo "$ sudo apt-get install $apt_missing -y"
        ;;
      *)
        echo "for OS X (homebrew): brew install ragel wget cvs yasm autogen automake autoconf cmake libtool xz pkg-config nasm bzip2 autoconf-archive p7zip coreutils llvm" # if edit this edit docker/Dockerfile also :|
        echo "   and set llvm to your PATH if on catalina"
        echo "for RHEL/CentOS: First ensure you have epel repo available, then run $ sudo yum install ragel subversion texinfo libtool autogen gperf nasm patch unzip pax ed gcc-c++ bison flex yasm automake autoconf gcc zlib-devel cvs bzip2 cmake3 -y"
        echo "for fedora: if your distribution comes with a modern version of cmake then use the same as RHEL/CentOS but replace cmake3 with cmake."
        echo "for linux native compiler option: same as <your OS> above, also add libva-dev"
        ;;
    esac
    exit 1
  fi

  export REQUIRED_CMAKE_VERSION="3.0.0"
  for cmake_binary in 'cmake' 'cmake3'; do
    # We need to check both binaries the same way because the check for installed packages will work if *only* cmake3 is installed or
    # if *only* cmake is installed.
    # On top of that we ideally would handle the case where someone may have patched their version of cmake themselves, locally, but if
    # the version of cmake required move up to, say, 3.1.0 and the cmake3 package still only pulls in 3.0.0 flat, then the user having manually
    # installed cmake at a higher version wouldn't be detected.
    if hash "${cmake_binary}"  &> /dev/null; then
      cmake_version="$( "${cmake_binary}" --version | sed -e "s#${cmake_binary}##g" | head -n 1 | tr -cd '[0-9.\n]' )"
      if at_least_required_version "${REQUIRED_CMAKE_VERSION}" "${cmake_version}"; then
        export cmake_command="${cmake_binary}"
        break
      else
        echo "your ${cmake_binary} version is too old ${cmake_version} wanted ${REQUIRED_CMAKE_VERSION}"
      fi
    fi
  done

  # If cmake_command never got assigned then there where no versions found which where sufficient.
  if [ -z "${cmake_command}" ]; then
    echo "there where no appropriate versions of cmake found on your machine."
    exit 1
  else
    # If cmake_command is set then either one of the cmake's is adequate.
    if [[ $cmake_command != "cmake" ]]; then # don't echo if it's the normal default
      echo "cmake binary for this build will be ${cmake_command}"
    fi
  fi

  if [[ ! -f /usr/include/zlib.h ]]; then
    echo "warning: you may need to install zlib development headers first if you want to build mp4-box [on ubuntu: $ apt-get install zlib1g-dev] [on redhat/fedora distros: $ yum install zlib-devel]" # XXX do like configure does and attempt to compile and include zlib.h instead?
    sleep 1
  fi

  # TODO nasm version :|

  # doing the cut thing with an assigned variable dies on the version of yasm I have installed (which I'm pretty sure is the RHEL default)
  # because of all the trailing lines of stuff
  export REQUIRED_YASM_VERSION="1.2.0" # export ???
  local yasm_binary=yasm
  local yasm_version="$( "${yasm_binary}" --version |sed -e "s#${yasm_binary}##g" | head -n 1 | tr -dc '[0-9.\n]' )"
  if ! at_least_required_version "${REQUIRED_YASM_VERSION}" "${yasm_version}"; then
    echo "your yasm version is too old $yasm_version wanted ${REQUIRED_YASM_VERSION}"
    exit 1
  fi
  # local meson_version=`meson --version`
  # if ! at_least_required_version "0.60.0" "${meson_version}"; then
    # echo "your meson version is too old $meson_version wanted 0.60.0"
    # exit 1
  # fi
  # also check missing "setup" so it's early LOL

  #check if WSL
  # check WSL for interop setting make sure its disabled
  # check WSL for kernel version look for version 4.19.128 current as of 11/01/2020
  if uname -a | grep  -iq -- "-microsoft" ; then
    if cat /proc/sys/fs/binfmt_misc/WSLInterop | grep -q enabled ; then
      echo "windows WSL detected: you must first disable 'binfmt' by running this
      sudo bash -c 'echo 0 > /proc/sys/fs/binfmt_misc/WSLInterop'
      then try again"
      #exit 1
    fi
    export MINIMUM_KERNEL_VERSION="4.19.128"
    KERNVER=$(uname -a | awk -F'[ ]' '{ print $3 }' | awk -F- '{ print $1 }')

    function version { # for version comparison @ stackoverflow.com/a/37939589
      echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
    }

    if [ $(version $KERNVER) -lt $(version $MINIMUM_KERNEL_VERSION) ]; then
      echo "Windows Subsystem for Linux (WSL) detected - kernel not at minumum version required: $MINIMUM_KERNEL_VERSION
      Please update via windows update then try again"
      #exit 1
    fi
    echo "for WSL ubuntu 20.04 you need to do an extra step https://github.com/rdp/ffmpeg-windows-build-helpers/issues/452"
  fi

}

determine_distro() {

# Determine OS platform from https://askubuntu.com/a/459425/20972
UNAME=$(uname | tr "[:upper:]" "[:lower:]")
# If Linux, try to determine specific distribution
if [ "$UNAME" == "linux" ]; then
    # If available, use LSB to identify distribution
    if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
        export DISTRO=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'//)
    # Otherwise, use release info file
    else
        export DISTRO=$(grep '^ID' /etc/os-release | sed 's#.*=\(\)#\1#')
    fi
fi
# For everything else (or if above failed), just use generic identifier
[ "$DISTRO" == "" ] && export DISTRO=$UNAME
unset UNAME
}

# made into a method so I don't/don't have to download this script every time if only doing just 32 or just6 64 bit builds...
download_gcc_build_script() {
    local zeranoe_script_name=$1
    cp $WINPATCHDIR/$zeranoe_script_name $WINPATCHDIR/$zeranoe_script_name.bak
    cp $WINPATCHDIR/$zeranoe_script_name $zeranoe_script_name
    #rm -f $WINPATCHDIR/$zeranoe_script_name || exit 1
    #curl -4 https://raw.githubusercontent.com/Zeranoe/mingw-w64-build/refs/heads/master/mingw-w64-build -O --fail || exit 1
    chmod u+x $zeranoe_script_name
}

# helper methods for downloading and building projects that can take generic input

do_svn_checkout() {
  repo_url="$1"
  to_dir="$2"
  desired_revision="$3"
  if [ ! -d $to_dir ]; then
    echo "svn checking out to $to_dir"
    if [[ -z "$desired_revision" ]]; then
      svn checkout $repo_url $to_dir.tmp  --non-interactive --trust-server-cert || exit 1
    else
      svn checkout -r $desired_revision $repo_url $to_dir.tmp || exit 1
    fi
    mv $to_dir.tmp $to_dir
  else
    change_dir $to_dir
    echo "not svn Updating $to_dir since usually svn repo's aren't updated frequently enough..."
    # XXX accomodate for desired revision here if I ever uncomment the next line...
    # svn up
    change_dir ..
  fi
}

# params: git url, to_dir
retry_git_or_die() {  # originally from https://stackoverflow.com/a/76012343/32453
  local RETRIES_NO=50
  local RETRY_DELAY=30
  local repo_url=$1
  local to_dir=$2
  local desired_branch=$3
  for i in $(seq 1 $RETRIES_NO); do
    echo "Downloading (via git clone) $to_dir from $repo_url"
    remove_path -rf $to_dir.tmp # just in case it was interrupted previously...not sure if necessary...
    create_dir $to_dir
    git ls-remote --exit-code --heads "$repo_url" "$desired_branch" >/dev/null 2>&1 
    branch_exists=$?
    if [[ $branch_exists == 0 ]]; then
      git clone --depth 1 -b "$desired_branch" "$repo_url" "$to_dir" --recurse-submodules && break
    else
      echo "Failed to get branch $desired_branch for $repo_url. Getting master instead"
      git clone --depth 1 -b "master" $repo_url $to_dir --recurse-submodules && break
    fi
    # get here -> failure
    [[ $i -eq $RETRIES_NO ]] && echo "Failed to execute git cmd $repo_url $to_dir after $RETRIES_NO retries" && exit 1
    echo "sleeping before retry git"
    sleep ${RETRY_DELAY}
  done
  # prevent partial checkout confusion by renaming it only after success
  #mv $to_dir.tmp $to_dir
  echo "done git cloning branch $desired_branch to $to_dir"
}

do_git_checkout() {
  local repo_url="$1"
  local to_dir="$2"
  if [[ -z $to_dir ]]; then
    to_dir=$(basename $repo_url | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  fi
  local desired_branch="$3"
  if [ ! -d $to_dir ]; then
    retry_git_or_die $repo_url $to_dir $desired_branch
    change_dir $to_dir
  else
    change_dir $to_dir
    if [[ $git_get_latest = "y" ]]; then
      git fetch # want this for later...
    else
      echo "not doing git get latest pull for latest code $to_dir" # too slow'ish...
    fi
  fi
  change_dir ..
}

git_hard_reset() {
  local target_path
  target_path=$(realpath "$1" 2>/dev/null) || return  # Handle invalid paths
  if [ -z "$target_path" ]; then
      return
  fi
  
  local current_path
  current_path=$(pwd)
  
  if [ "$current_path" = "$target_path" ]; then
    git reset --hard  # throw away results of patch files
    git clean -fx     # throw away local changes; 'already_*' and bak-files for instance.
  fi
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
  local beginning="$1"
  local extra_stuff="$2"
  local touch_name="${beginning}_$(echo -- $extra_stuff $CFLAGS $LDFLAGS | /usr/bin/env md5sum)" # md5sum to make it smaller, cflags to force rebuild if changes
  touch_name=$(echo "$touch_name" | sed "s/ //g") # md5sum introduces spaces, remove them
  echo "$touch_name" # bash cruddy return system LOL
}

do_configure() {
  local configure_options="$1"
  local configure_name="$2"
  if [[ "$configure_name" = "" ]]; then
    configure_name="./configure"
  fi
  local cur_dir2=$(pwd)
  local english_name=$(basename $cur_dir2)
  local touch_name=$(get_small_touchfile_name already_configured "$configure_options $configure_name")
  if [ ! -f "$touch_name" ]; then
    # make uninstall # does weird things when run under ffmpeg src so disabled for now...

    echo "configuring $english_name ($PWD) as $ PKG_CONFIG_PATH=$PKG_CONFIG_PATH PATH=$mingw_bin_path:\$PATH $configure_name $configure_options" # say it now in case bootstrap fails etc.
    echo "all touch files" already_configured* touchname= "$touch_name"
    echo "config options "$configure_options $configure_name""
    if [ -f bootstrap ]; then
      ./bootstrap # some need this to create ./configure :|
    fi
    if [[ ! -f $configure_name && -f bootstrap.sh ]]; then # fftw wants to only run this if no configure :|
      ./bootstrap.sh
    fi
    if [[ ! -f $configure_name ]]; then
      echo "running autoreconf to generate configure file for us..."
      autoreconf -fiv # a handful of them require this to create ./configure :|
    fi
    remove_path -f already_* # reset
    chmod u+x "$configure_name" # In non-windows environments, with devcontainers, the configuration file doesn't have execution permissions
    nice -n 5 "$configure_name" $configure_options || { echo "failed configure $english_name"; exit 1;} # less nicey than make (since single thread, and what if you're running another ffmpeg nice build elsewhere?)
    touch -- "$touch_name"
    echo "doing preventative make clean"
    nice make clean -j $(get_cpu_count) # sometimes useful when files change, etc.
  #else
  #  echo "already configured $(basename $cur_dir2)"
  fi
}

do_make() {
  local extra_make_options="$1"
  extra_make_options="$extra_make_options -j $(get_cpu_count)"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_make "$extra_make_options" )

  if [ ! -f $touch_name ]; then
    echo
    echo "Making $cur_dir2 as $ PATH=$mingw_bin_path:\$PATH make $extra_make_options"
    echo
    if [ ! -f configure ]; then
      nice make clean -j $(get_cpu_count) # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
    fi
    nice make $extra_make_options || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "Already made $(dirname "$cur_dir2") $(basename "$cur_dir2") ..."
  fi
}

do_make_and_make_install() {
  local extra_make_options="$1"
  do_make "$extra_make_options"
  do_make_install "$extra_make_options"
}

do_make_install() {
  local extra_make_install_options="$1"
  local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
  if [[ -z $override_make_install_options ]]; then
    local make_install_options="install $extra_make_install_options"
  else
    local make_install_options="$override_make_install_options $extra_make_install_options"
  fi
  local touch_name=$(get_small_touchfile_name already_ran_make_install "$make_install_options")
  if [ ! -f $touch_name ]; then
    echo "make installing $(pwd) as $ PATH=$mingw_bin_path:\$PATH make $make_install_options"
    nice make $make_install_options || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake() {
  extra_args="$1"
  local build_from_dir="$2"
  if [[ -z $build_from_dir ]]; then
    build_from_dir="."
  fi
  local touch_name=$(get_small_touchfile_name already_ran_cmake "$extra_args")

  if [ ! -f $touch_name ]; then
    remove_path -f already_* # reset so that make will run again if option just changed
    local cur_dir2=$(pwd)
    local config_options=""
    if [ $bits_target = 32 ]; then
	  local config_options+="-DCMAKE_SYSTEM_PROCESSOR=x86" 
	else
      local config_options+="-DCMAKE_SYSTEM_PROCESSOR=AMD64" 
    fi	
    echo doing cmake in $cur_dir2 with PATH=$mingw_bin_path:\$PATH with extra_args=$extra_args like this:
    if [[ $compiler_flavors != "native" ]]; then
      local command="${build_from_dir} -DENABLE_STATIC_RUNTIME=1 -DBUILD_SHARED_LIBS=0 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_FIND_ROOT_PATH=$mingw_w64_x86_64_prefix -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_RANLIB=${cross_prefix}ranlib -DCMAKE_C_COMPILER=${cross_prefix}gcc -DCMAKE_CXX_COMPILER=${cross_prefix}g++ -DCMAKE_RC_COMPILER=${cross_prefix}windres -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $config_options $extra_args"
	else
      local command="${build_from_dir} -DENABLE_STATIC_RUNTIME=1 -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $config_options $extra_args"
    fi
    echo "doing ${cmake_command}  -G\"Unix Makefiles\" $command"
    nice -n 5  ${cmake_command} -G"Unix Makefiles" $command || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake_from_build_dir() { # some sources don't allow it, weird XXX combine with the above :)
  source_dir="$1"
  extra_args="$2"
  do_cmake "$extra_args" "$source_dir"
}

do_cmake_and_install() {
  do_cmake "$1"
  do_make_and_make_install
}

activate_meson() {
  if [[ ! -e meson_git ]]; then 
    do_git_checkout https://github.com/mesonbuild/meson.git meson_git 1.9.1
  fi
  change_dir meson_git # requires python3-full   
    if [[ ! -e tutorial_env ]]; then 
      python3 -m venv tutorial_env 
      source tutorial_env/bin/activate
      python3 -m pip install meson
    else source tutorial_env/bin/activate
    fi
  change_dir ..
}

do_meson() {
    local configure_options="$1 --unity=off"
    local configure_name="$2"
    local configure_env="$3"
    local configure_noclean=""
    if [[ "$configure_name" = "" ]]; then
        configure_name="meson"
    fi
    local cur_dir2=$(pwd)
    local english_name=$(basename $cur_dir2)
    local touch_name=$(get_small_touchfile_name already_built_meson "$configure_options $configure_name $LDFLAGS $CFLAGS")
    if [ ! -f "$touch_name" ]; then
        if [ "$configure_noclean" != "noclean" ]; then
            make clean # just in case
        fi
        remove_path -f already_* # reset
        echo "Using meson: $english_name ($PWD) as $ PATH=$PATH ${configure_env} $configure_name $configure_options"
        #env
        "$configure_name" $configure_options || exit 1
        touch -- "$touch_name"
        make clean # just in case
    else
        echo "Already used meson $(basename $cur_dir2)"
    fi
}

generic_meson() {
    local extra_configure_options="$1"
    create_dir build
    do_meson "--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib --buildtype=release --default-library=static $extra_configure_options" # --cross-file=${BASEDIR}/meson-cross.mingw.txt
}

generic_meson_ninja_install() {
    generic_meson "$1"
    do_ninja_and_ninja_install
}

do_ninja_and_ninja_install() {
    local extra_ninja_options="$1"
    do_ninja "$extra_ninja_options"
    local touch_name=$(get_small_touchfile_name already_ran_make_install "$extra_ninja_options")
    if [ ! -f $touch_name ]; then
        echo "ninja installing $(pwd) as $PATH=$PATH ninja -C build install $extra_make_options"
        ninja -C build install || exit 1
        touch $touch_name || exit 1
    fi
}

do_ninja() {
  local extra_make_options=" -j $(get_cpu_count)"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_make "${extra_make_options}")

  if [ ! -f $touch_name ]; then
    echo
    echo "ninja-ing $cur_dir2 as $ PATH=$PATH ninja -C build "${extra_make_options}"
    echo
    ninja -C build "${extra_make_options} || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "already did ninja $(basename "$cur_dir2")"
  fi
}

apply_patch() {
  local url=$1 # if you want it to use a local file instead of a url one [i.e. local file with local modifications] specify it like file://localhost/full/path/to/filename.patch
  local patch_type=$2
  if [[ -z $patch_type ]]; then
    patch_type="-p0" # some are -p1 unfortunately, git's default
  fi
  local patch_name=$(basename $url)
  local patch_done_name="$patch_name.done"
  if [[ ! -e $patch_done_name ]]; then
    if [[ -f $patch_name ]]; then
      remove_path -rf $patch_name || exit 1 # remove old version in case it has been since updated on the server...
    fi
    curl -4 --retry 5 $url -O --fail || echo_and_exit "unable to download patch file $url"
    echo "applying patch $patch_name"
    patch $patch_type < "$patch_name" || exit 1
    touch $patch_done_name || exit 1
    # too crazy, you can't do do_configure then apply a patch?
    # rm -f already_ran* # if it's a new patch, reset everything too, in case it's really really really new
  #else
  #  echo "patch $patch_name already applied" # too chatty
  fi
}

echo_and_exit() {
  echo "failure, exiting: $1"
  exit 1
}

# takes a url, output_dir as params, output_dir optional
download_and_unpack_file() {
  url="$1"
  output_name=$(basename $url)
  output_dir="$2"
  if [[ -z $output_dir ]]; then
    output_dir=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx
  fi
  if [ ! -f "$output_dir/unpacked.successfully" ]; then
    echo "downloading $url" # redownload in case failed...
    if [[ -f $output_name ]]; then
      remove_path -rf $output_name || exit 1
    fi

    #  From man curl
    #  -4, --ipv4
    #  If curl is capable of resolving an address to multiple IP versions (which it is if it is  IPv6-capable),
    #  this option tells curl to resolve names to IPv4 addresses only.
    #  avoid a "network unreachable" error in certain [broken Ubuntu] configurations a user ran into once
    #  -L means "allow redirection" or some odd :|

    curl -4 "$url" --retry 50 -O -L --fail || echo_and_exit "unable to download $url"
    echo "unzipping $output_name ..."
    tar -xf "$output_name" || unzip "$output_name" || exit 1
    touch "$output_dir/unpacked.successfully" || exit 1
    remove_path -rf "$output_name" || exit 1
  fi
}

generic_configure() {
  build_triple="${build_triple:-$(gcc -dumpmachine)}"
  local extra_configure_options="$1"
  if [[ -n $build_triple ]]; then extra_configure_options+=" --build=$build_triple"; fi
  do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static $extra_configure_options"
}

# params: url, optional "english name it will unpack to"
generic_download_and_make_and_install() {
  local url="$1"
  local english_name="$2"
  if [[ -z $english_name ]]; then
    english_name=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx, take last part of url
  fi
  local extra_configure_options="$3"
  download_and_unpack_file $url $english_name
  change_dir $english_name || exit "unable to cd, may need to specify dir it will unpack to as parameter"
  generic_configure "$extra_configure_options"
  do_make_and_make_install
  change_dir ..
}

do_git_checkout_and_make_install() {
  local url=$1
  local git_checkout_name=$(basename $url | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  do_git_checkout $url $git_checkout_name
  change_dir $git_checkout_name
    generic_configure_make_install
  change_dir ..
}

generic_configure_make_install() {
  if [ $# -gt 0 ]; then
    echo "cant pass parameters to this method today, they'd be a bit ambiguous"
    echo "The following arguments where passed: ${@}"
    exit 1
  fi
  generic_configure # no parameters, force myself to break it up if needed
  do_make_and_make_install
}

gen_ld_script() {
  lib=$mingw_w64_x86_64_prefix/lib/$1
  lib_s="$2"
  if [[ ! -f $mingw_w64_x86_64_prefix/lib/lib$lib_s.a ]]; then
    echo "Generating linker script $lib: $2 $3"
    mv -f $lib $mingw_w64_x86_64_prefix/lib/lib$lib_s.a
    echo "GROUP ( -l$lib_s $3 )" > $lib
  fi
}

#===============================================================================================
#                                     WINDOWS BUILD LIBRARIES
#===============================================================================================

build_dlfcn() {
  do_git_checkout https://github.com/dlfcn-win32/dlfcn-win32.git
  change_dir dlfcn-win32_git
    if [[ ! -f Makefile.bak ]]; then # Change CFLAGS.
      sed -i.bak "s/-O3/-O2/" Makefile
    fi
    do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix" # rejects some normal cross compile options so custom here
    do_make_and_make_install
    gen_ld_script libdl.a dl_s -lpsapi # dlfcn-win32's 'README.md': "If you are linking to the static 'dl.lib' or 'libdl.a', then you would need to explicitly add 'psapi.lib' or '-lpsapi' to your linking command, depending on if MinGW is used."
  change_dir ..
}

build_bzip2() {
  download_and_unpack_file https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
  change_dir bzip2-1.0.8
    apply_patch file://$WINPATCHDIR/bzip2-1.0.8_brokenstuff.diff
    if [[ ! -f ./libbz2.a ]] || [[ -f $mingw_w64_x86_64_prefix/lib/libbz2.a && ! $(/usr/bin/env md5sum ./libbz2.a) = $(/usr/bin/env md5sum $mingw_w64_x86_64_prefix/lib/libbz2.a) ]]; then # Not built or different build installed
      do_make "$make_prefix_options libbz2.a"
      install -m644 bzlib.h $mingw_w64_x86_64_prefix/include/bzlib.h
      install -m644 libbz2.a $mingw_w64_x86_64_prefix/lib/libbz2.a
    else
      echo "Already made bzip2-1.0.8"
    fi
  change_dir ..
}

build_liblzma() {
  download_and_unpack_file https://sourceforge.net/projects/lzmautils/files/xz-5.8.1.tar.xz
  change_dir xz-5.8.1
    generic_configure "--disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc --disable-nls"
    do_make_and_make_install
  change_dir ..
}

build_zlib() {
  do_git_checkout https://github.com/madler/zlib.git zlib_git
  change_dir zlib_git
    local make_options
    if [[ $compiler_flavors == "native" ]]; then
      export CFLAGS="$CFLAGS -fPIC" # For some reason glib needs this even though we build a static library
    else
      export ARFLAGS=rcs # Native can't take ARFLAGS; https://stackoverflow.com/questions/21396988/zlib-build-not-configuring-properly-with-cross-compiler-ignores-ar
    fi
    do_configure "--prefix=$mingw_w64_x86_64_prefix --static"
    do_make_and_make_install "$make_prefix_options ARFLAGS=rcs"
    if [[ $compiler_flavors == "native" ]]; then
      reset_cflags
    else
      unset ARFLAGS
    fi
  change_dir ..
}

build_iconv() {
  download_and_unpack_file https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz
  change_dir libiconv-1.18
    generic_configure "--disable-nls"
    do_make "install-lib" # No need for 'do_make_install', because 'install-lib' already has install-instructions.
  change_dir ..
}

build_brotli() {
  do_git_checkout https://github.com/google/brotli.git brotli_git v1.0.9 # v1.1.0 static headache stay away
  change_dir brotli_git
    if [ ! -f "brotli.exe" ]; then
      remove_path -f configure
    fi
    generic_configure
    sed -i.bak -e "s/\(allow_undefined=\)yes/\1no/" libtool
    do_make_and_make_install
    sed -i.bak 's/Libs.*$/Libs: -L${libdir} -lbrotlicommon/' $PKG_CONFIG_PATH/libbrotlicommon.pc # remove rpaths not possible in conf
    sed -i.bak 's/Libs.*$/Libs: -L${libdir} -lbrotlidec/' $PKG_CONFIG_PATH/libbrotlidec.pc
    sed -i.bak 's/Libs.*$/Libs: -L${libdir} -lbrotlienc/' $PKG_CONFIG_PATH/libbrotlienc.pc
  change_dir ..
}  
  
build_zstd() {  
  do_git_checkout https://github.com/facebook/zstd.git zstd_git v1.5.7
  change_dir zstd_git
    do_cmake "-S build/cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DZSTD_BUILD_SHARED=OFF -DZSTD_USE_STATIC_RUNTIME=ON -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF"
    do_ninja_and_ninja_install
  change_dir ..
 } 
  
build_sdl2() {
  download_and_unpack_file https://www.libsdl.org/release/SDL2-2.32.10.tar.gz
  change_dir SDL2-2.32.10
    apply_patch file://$WINPATCHDIR/SDL2-2.32.10_lib-only.diff
    if [[ ! -f configure.bak ]]; then
      sed -i.bak "s/ -mwindows//" configure # Allow ffmpeg to output anything to console.
    fi
    export CFLAGS="$CFLAGS -DDECLSPEC="  # avoid SDL trac tickets 939 and 282 [broken shared builds]
    if [[ $compiler_flavors == "native" ]]; then
      unset PKG_CONFIG_LIBDIR # Allow locally installed things for native builds; libpulse-dev is an important one otherwise no audio for most Linux
    fi
    generic_configure "--bindir=$mingw_bin_path"
    do_make_and_make_install
    if [[ $compiler_flavors == "native" ]]; then
      export PKG_CONFIG_LIBDIR=
    fi
    if [[ ! -f $mingw_bin_path/$host_target-sdl2-config ]]; then
      mv "$mingw_bin_path/sdl2-config" "$mingw_bin_path/$host_target-sdl2-config" # At the moment FFmpeg's 'configure' doesn't use 'sdl2-config', because it gives priority to 'sdl2.pc', but when it does, it expects 'i686-w64-mingw32-sdl2-config' in 'cross_compilers/mingw-w64-i686/bin'.
    fi
    reset_cflags
  change_dir ..
}

build_amd_amf_headers() {
  # was https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git too big
  # or https://github.com/DeadSix27/AMF smaller
  # but even smaller!
  do_git_checkout https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git amf_headers_git
  change_dir amf_headers_git
    if [ ! -f "already_installed" ]; then
      #rm -rf "./Thirdparty" # ?? plus too chatty...
      if [ ! -d "$mingw_w64_x86_64_prefix/include/AMF" ]; then
        create_dir "$mingw_w64_x86_64_prefix/include/AMF"
      fi
      cp -av "amf/public/include/." "$mingw_w64_x86_64_prefix/include/AMF"
      touch "already_installed"
    fi
  change_dir ..
}

build_nv_headers() {
  if [[ $ffmpeg_git_checkout_version == *"n6.0"* ]] || [[ $ffmpeg_git_checkout_version == *"n5"* ]] || [[ $ffmpeg_git_checkout_version == *"n4"* ]] || [[ $ffmpeg_git_checkout_version == *"n3"* ]] || [[ $ffmpeg_git_checkout_version == *"n2"* ]]; then
    # nv_headers for old versions
    do_git_checkout https://github.com/FFmpeg/nv-codec-headers.git nv-codec-headers_git n12.0.16.1
  else
    do_git_checkout https://github.com/FFmpeg/nv-codec-headers.git
  fi
  change_dir nv-codec-headers_git
    do_make_install "PREFIX=$mingw_w64_x86_64_prefix" # just copies in headers
  change_dir ..
}

build_intel_qsv_mfx() { # disableable via command line switch...
  do_git_checkout https://github.com/lu-zero/mfx_dispatch.git mfx_dispatch_git 2cd279f # lu-zero?? oh well seems somewhat supported...
  change_dir mfx_dispatch_git
    if [[ ! -f "configure" ]]; then
      autoreconf -fiv || exit 1
      automake --add-missing || exit 1
    fi
    if [[ $compiler_flavors == "native" && $OSTYPE != darwin* ]]; then
      unset PKG_CONFIG_LIBDIR # allow mfx_dispatch to use libva-dev or some odd on linux...not sure for OS X so just disable it :)
      generic_configure_make_install
      export PKG_CONFIG_LIBDIR=
    else
      generic_configure_make_install
    fi
  change_dir ..
}

build_libvpl () {
  # build_intel_qsv_mfx
  do_git_checkout https://github.com/intel/libvpl.git libvpl_git # f8d9891 
  change_dir libvpl_git
    if [ "$bits_target" = "32" ]; then
      apply_patch "https://raw.githubusercontent.com/msys2/MINGW-packages/master/mingw-w64-libvpl/0003-cmake-fix-32bit-install.patch" -p1
    fi
    do_cmake "-B build -GNinja -DCMAKE_BUILD_TYPE=Release -DINSTALL_EXAMPLES=OFF -DINSTALL_DEV=ON -DBUILD_EXPERIMENTAL=OFF" 
    do_ninja_and_ninja_install
    sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/vpl.pc"
  change_dir ..
}

build_libleptonica() {
  build_libjpeg_turbo
  generic_download_and_make_and_install https://sourceforge.net/projects/giflib/files/giflib-5.1.4.tar.gz
  do_git_checkout https://github.com/DanBloomberg/leptonica.git leptonica_git
  change_dir leptonica_git
    export CPPFLAGS="-DOPJ_STATIC"
    generic_configure_make_install
    reset_cppflags
  change_dir ..
}

build_libtiff() {
  build_libjpeg_turbo # auto uses it?
  generic_download_and_make_and_install http://download.osgeo.org/libtiff/tiff-4.7.1.tar.gz
  sed -i.bak 's/-ltiff.*$/-ltiff -llzma -ljpeg -lz/' $PKG_CONFIG_PATH/libtiff-4.pc # static deps
}

build_libtensorflow() { 
  if [[ ! -e Tensorflow ]]; then
    mkdir Tensorflow
    change_dir Tensorflow
      wget https://storage.googleapis.com/tensorflow/versions/2.18.1/libtensorflow-cpu-windows-x86_64.zip # tensorflow.dll required by ffmpeg to run
      unzip -o libtensorflow-cpu-windows-x86_64.zip -d $mingw_w64_x86_64_prefix
      remove_path -f libtensorflow-cpu-windows-x86_64.zip
    change_dir ..
  else echo "Tensorflow already installed"
  fi
}

build_glib() {
  generic_download_and_make_and_install  https://ftp.gnu.org/pub/gnu/gettext/gettext-0.26.tar.gz
  download_and_unpack_file  https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz # also dep
  change_dir libffi-3.5.2
    apply_patch file://$WINPATCHDIR/libffi.patch -p1 
    generic_configure_make_install
  change_dir ..
  
  do_git_checkout https://github.com/GNOME/glib.git glib_git 
  activate_meson
  change_dir glib_git
    local meson_options="setup --force-fallback-for=libpcre -Dforce_posix_threads=true -Dman-pages=disabled -Dsysprof=disabled -Dglib_debug=disabled -Dtests=false --wrap-mode=default . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    if [[ $compiler_flavors == "native" ]]; then
      sed -i.bak 's/-lglib-2.0.*$/-lglib-2.0 -lm -liconv/' $PKG_CONFIG_PATH/glib-2.0.pc
    else
      sed -i.bak 's/-lglib-2.0.*$/-lglib-2.0 -lintl -lws2_32 -lwinmm -lm -liconv -lole32/' $PKG_CONFIG_PATH/glib-2.0.pc
    fi
  deactivate
  change_dir ..
}

build_lensfun() {
  build_glib
  do_git_checkout https://github.com/lensfun/lensfun.git lensfun_git
  change_dir lensfun_git
    export CPPFLAGS="$CPPFLAGS-DGLIB_STATIC_COMPILATION"
    export CXXFLAGS="$CFLAGS -DGLIB_STATIC_COMPILATION"
    do_cmake "-DBUILD_STATIC=on -DCMAKE_INSTALL_DATAROOTDIR=$mingw_w64_x86_64_prefix -DBUILD_TESTS=off -DBUILD_DOC=off -DINSTALL_HELPER_SCRIPTS=off -DINSTALL_PYTHON_MODULE=OFF"
    do_make_and_make_install
    sed -i.bak 's/-llensfun/-llensfun -lstdc++/' "$PKG_CONFIG_PATH/lensfun.pc"
    reset_cppflags
    unset CXXFLAGS
  change_dir ..
}

build_lz4 () {
  download_and_unpack_file https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz
  change_dir lz4-1.10.0
    do_cmake "-S build/cmake -B build -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_STATIC_LIBS=ON"
    do_ninja_and_ninja_install
  change_dir .. 
}

 build_libarchive () {
  build_lz4
  download_and_unpack_file https://github.com/libarchive/libarchive/releases/download/v3.8.1/libarchive-3.8.1.tar.gz
  change_dir libarchive-3.8.1
    generic_configure "--with-nettle --bindir=$mingw_w64_x86_64_prefix/bin --without-openssl --without-iconv --disable-posix-regex-lib"
    do_make_install
  change_dir ..
}

build_flac () {
  do_git_checkout https://github.com/xiph/flac.git flac_git 
  change_dir flac_git
    do_cmake "-B build -DCMAKE_BUILD_TYPE=Release -DINSTALL_MANPAGES=OFF -GNinja"
    do_ninja_and_ninja_install
  change_dir ..
}

build_openmpt () {
  build_flac
  do_git_checkout https://github.com/OpenMPT/openmpt.git openmpt_git # OpenMPT-1.30
  change_dir openmpt_git
    do_make_and_make_install "PREFIX=$mingw_w64_x86_64_prefix CONFIG=mingw64-win64 EXESUFFIX=.exe SOSUFFIX=.dll SOSUFFIXWINDOWS=1 DYNLINK=0 SHARED_LIB=0 STATIC_LIB=1 
      SHARED_SONAME=0 IS_CROSS=1 NO_ZLIB=0 NO_LTDL=0 NO_DL=0 NO_MPG123=0 NO_OGG=0 NO_VORBIS=0 NO_VORBISFILE=0 NO_PORTAUDIO=1 NO_PORTAUDIOCPP=1 NO_PULSEAUDIO=1 NO_SDL=0 
      NO_SDL2=0 NO_SNDFILE=0 NO_FLAC=0 EXAMPLES=0 OPENMPT123=0 TEST=0" # OPENMPT123=1 >>> fail
    sed -i.bak 's/Libs.private.*/& -lrpcrt4/' $PKG_CONFIG_PATH/libopenmpt.pc
  change_dir ..
}

build_libpsl () {
  export CFLAGS="-DPSL_STATIC"
  download_and_unpack_file https://github.com/rockdaboot/libpsl/releases/download/0.21.5/libpsl-0.21.5.tar.gz  
  change_dir libpsl-0.21.5
    generic_configure "--disable-nls --disable-rpath --disable-gtk-doc-html --disable-man --disable-runtime"
    do_make_and_make_install
    sed -i.bak "s/Libs: .*/& -lidn2 -lunistring -lws2_32 -liconv/" $PKG_CONFIG_PATH/libpsl.pc
  reset_cflags
  change_dir ..
}
 
build_nghttp2 () { 
  export CFLAGS="-DNGHTTP2_STATICLIB"
  download_and_unpack_file https://github.com/nghttp2/nghttp2/releases/download/v1.67.1/nghttp2-1.67.1.tar.gz
  change_dir nghttp2-1.67.1
    do_cmake "-B build -DENABLE_LIB_ONLY=1 -DBUILD_SHARED_LIBS=0 -DBUILD_STATIC_LIBS=1 -GNinja"
    do_ninja_and_ninja_install
  reset_cflags
  change_dir ..
}
 
build_curl () { 
  generic_download_and_make_and_install https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.1/libssh2-1.11.1.tar.gz
  build_zstd
  build_brotli
  build_libpsl
  build_nghttp2
  local config_options=""
  if [[ $compiler_flavors == "native" ]]; then
    local config_options+="-DGNUTLS_INTERNAL_BUILD" 
  fi  
  export CPPFLAGS+="$CPPFLAGS -DNGHTTP2_STATICLIB -DPSL_STATIC $config_options"
  do_git_checkout https://github.com/curl/curl.git curl_git curl-8_16_0
  change_dir curl_git 
    if [[ $compiler_flavors != "native" ]]; then
      generic_configure "--with-libssh2 --with-libpsl --with-libidn2 --disable-debug --enable-hsts --with-brotli --enable-versioned-symbols --enable-sspi --with-schannel"
    else
      generic_configure "--with-gnutls --with-libssh2 --with-libpsl --with-libidn2 --disable-debug --enable-hsts --with-brotli --enable-versioned-symbols" # untested on native
    fi
    do_make_and_make_install
  reset_cppflags
  change_dir ..
}
  
build_libtesseract() {
  build_libtiff
  build_libleptonica   
  build_libarchive
  do_git_checkout https://github.com/tesseract-ocr/tesseract.git tesseract_git 
  change_dir tesseract_git
    export CPPFLAGS="$CPPFLAGS -DCURL_STATICLIB"
    generic_configure "--disable-openmp --with-archive --disable-graphics --disable-tessdata-prefix --with-curl LIBLEPT_HEADERSDIR=$mingw_w64_x86_64_prefix/include --datadir=$mingw_w64_x86_64_prefix/bin"
    do_make_and_make_install
    sed -i.bak 's/Requires.private.*/& lept libarchive liblzma libtiff-4 libcurl/' $PKG_CONFIG_PATH/tesseract.pc
    sed -i 's/-ltesseract.*$/-ltesseract -lstdc++ -lws2_32 -lbz2 -lz -liconv -lpthread  -lgdi32 -lcrypt32/' $PKG_CONFIG_PATH/tesseract.pc
    if [[ ! -f $mingw_w64_x86_64_prefix/bin/tessdata/tessdata/eng.traineddata ]]; then
      create_dir $mingw_w64_x86_64_prefix/bin/tessdata
      cp -f /usr/share/tesseract-ocr/**/tessdata/eng.traineddata $mingw_w64_x86_64_prefix/bin/tessdata/ 
    fi
  reset_cppflags
  change_dir ..
}

build_libzimg() {
  do_git_checkout_and_make_install https://github.com/sekrit-twc/zimg.git zimg_git
}

build_libopenjpeg() {
  do_git_checkout https://github.com/uclouvain/openjpeg.git openjpeg_git
  change_dir openjpeg_git
    do_cmake_and_install "-DBUILD_CODEC=0"
  change_dir ..
}

build_glew() {
  download_and_unpack_file https://sourceforge.net/projects/glew/files/glew/2.2.0/glew-2.2.0.tgz glew-2.2.0
  change_dir glew-2.2.0/build
    local cmake_params=""
    if [[ $compiler_flavors != "native" ]]; then
      cmake_params+=" -DWIN32=1"
    fi
    do_cmake_from_build_dir ./cmake "$cmake_params" # "-DWITH_FFMPEG=0 -DOPENCV_GENERATE_PKGCONFIG=1 -DHAVE_DSHOW=0"
    do_make_and_make_install
  change_dir ../..
}

build_glfw() {
  download_and_unpack_file https://github.com/glfw/glfw/releases/download/3.4/glfw-3.4.zip glfw-3.4
  change_dir glfw-3.4
    do_cmake_and_install
  change_dir ..
}

build_libpng() {
  do_git_checkout_and_make_install https://github.com/glennrp/libpng.git
}

build_libwebp() {
  do_git_checkout https://chromium.googlesource.com/webm/libwebp.git libwebp_git
  change_dir libwebp_git
    export LIBPNG_CONFIG="$mingw_w64_x86_64_prefix/bin/libpng-config --static" # LibPNG somehow doesn't get autodetected.
    generic_configure "--disable-wic"
    do_make_and_make_install
    unset LIBPNG_CONFIG
  change_dir ..
}

build_harfbuzz() {
  do_git_checkout https://github.com/harfbuzz/harfbuzz.git harfbuzz_git 10.4.0 # 11.0.0 no longer found by ffmpeg via this method, multiple issues, breaks harfbuzz freetype circular depends hack
  activate_meson
  build_freetype
  change_dir harfbuzz_git
    if [[ ! -f DUN ]]; then
      local meson_options="setup -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled . build"
      if [[ $compiler_flavors != "native" ]]; then
        # get_local_meson_cross_with_propeties 
        meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
        do_meson "$meson_options"      
      else
        generic_meson "$meson_options"
      fi
      do_ninja_and_ninja_install	   
      touch DUN
    fi
  change_dir ..
  build_freetype # with harfbuzz now
  deactivate
  sed -i.bak 's/-lfreetype.*/-lfreetype -lharfbuzz -lpng -lbz2/' "$PKG_CONFIG_PATH/freetype2.pc"
  sed -i.bak 's/-lharfbuzz.*/-lfreetype -lharfbuzz -lpng -lbz2/' "$PKG_CONFIG_PATH/harfbuzz.pc"
}

build_freetype() {
  do_git_checkout https://github.com/freetype/freetype.git freetype_git
  change_dir freetype_git
    local config_options=""
    if [[ -e $PKG_CONFIG_PATH/harfbuzz.pc ]]; then
      local config_options+=" -Dharfbuzz=enabled" 
    fi	
    local meson_options="setup $config_options . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
  change_dir ..
}

build_libxml2() {
  do_git_checkout https://gitlab.gnome.org/GNOME/libxml2.git libxml2_git
  change_dir libxml2_git
    generic_configure "--with-ftp=no --with-http=no --with-python=no"
    do_make_and_make_install
  change_dir ..
}

build_libvmaf() {
  do_git_checkout https://github.com/Netflix/vmaf.git vmaf_git
  activate_meson
  change_dir vmaf_git/libvmaf
    local meson_options="setup -Denable_float=true -Dbuilt_in_models=true -Denable_tests=false -Denable_docs=false . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/libvmaf.pc"
  deactivate
  change_dir ../..
}

build_fontconfig() {
  do_git_checkout https://gitlab.freedesktop.org/fontconfig/fontconfig.git fontconfig_git # meson build for fontconfig no good
  change_dir fontconfig_git
    generic_configure "--enable-iconv --enable-libxml2 --disable-docs --with-libiconv" # Use Libxml2 instead of Expat; will find libintl from gettext on 2nd pass build and ffmpeg rejects it
    do_make_and_make_install
  change_dir ..
}

build_gmp() {
  download_and_unpack_file https://ftp.gnu.org/pub/gnu/gmp/gmp-6.3.0.tar.xz
  change_dir gmp-6.3.0
    export CC_FOR_BUILD=/usr/bin/gcc # WSL seems to need this..
    export CPP_FOR_BUILD=usr/bin/cpp
    generic_configure "ABI=$bits_target"
    unset CC_FOR_BUILD
    unset CPP_FOR_BUILD
    do_make_and_make_install
  change_dir ..
}

build_librtmfp() {
  # needs some version of openssl...
  # build_openssl-1.0.2 # fails OS X
  build_openssl-1.1.1 # fails WSL
  do_git_checkout https://github.com/MonaSolutions/librtmfp.git
  change_dir librtmfp_git/include/Base
    do_git_checkout https://github.com/meganz/mingw-std-threads.git mingw-std-threads # our g++ apparently doesn't have std::mutex baked in...weird...this replaces it...
  change_dir ../../..
  change_dir librtmfp_git
    if [[ $compiler_flavors != "native" ]]; then
      apply_patch file://$WINPATCHDIR/rtmfp.static.cross.patch -p1 # works e48efb4f
      apply_patch file://$WINPATCHDIR/rtmfp_capitalization.diff -p1 # cross for windows needs it if on linux...
      apply_patch file://$WINPATCHDIR/librtmfp_xp.diff.diff -p1 # cross for windows needs it if on linux...
    else
      apply_patch file://$WINPATCHDIR/rtfmp.static.make.patch -p1
    fi
    do_make "$make_prefix_options GPP=${cross_prefix}g++"
    do_make_install "prefix=$mingw_w64_x86_64_prefix PKGCONFIGPATH=$PKG_CONFIG_PATH"
    if [[ $compiler_flavors == "native" ]]; then
      sed -i.bak 's/-lrtmfp.*/-lrtmfp -lstdc++/' "$PKG_CONFIG_PATH/librtmfp.pc"
    else
      sed -i.bak 's/-lrtmfp.*/-lrtmfp -lstdc++ -lws2_32 -liphlpapi/' "$PKG_CONFIG_PATH/librtmfp.pc"
    fi
  change_dir ..
}

build_libnettle() {
  download_and_unpack_file https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz
  change_dir nettle-3.10.2
    local config_options="--disable-openssl --disable-documentation" # in case we have both gnutls and openssl, just use gnutls [except that gnutls uses this so...huh?
    if [[ $compiler_flavors == "native" ]]; then
      config_options+=" --libdir=${mingw_w64_x86_64_prefix}/lib" # Otherwise native builds install to /lib32 or /lib64 which gnutls doesn't find
    fi
    generic_configure "$config_options" # in case we have both gnutls and openssl, just use gnutls [except that gnutls uses this so...huh? https://github.com/rdp/ffmpeg-windows-build-helpers/issues/25#issuecomment-28158515
    do_make_and_make_install # What's up with "Configured with: ... --with-gmp=/cygdrive/d/ffmpeg-windows-build-helpers-master/native_build/windows/ffmpeg_local_builds/prebuilt/cross_compilers/pkgs/gmp/gmp-6.1.2-i686" in 'config.log'? Isn't the 'gmp-6.1.2' above being used?
  change_dir ..
}

build_unistring() {
  generic_download_and_make_and_install https://ftp.gnu.org/gnu/libunistring/libunistring-1.4.1.tar.gz
}

build_libidn2() {
  download_and_unpack_file https://ftp.gnu.org/gnu/libidn/libidn2-2.3.8.tar.gz
  change_dir libidn2-2.3.8
    generic_configure "--disable-doc --disable-rpath --disable-nls --disable-gtk-doc-html --disable-fast-install"
    do_make_and_make_install 
  change_dir ..
}

build_gnutls() {
  download_and_unpack_file https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.9.tar.xz # v3.8.10 not found by ffmpeg with identical .pc?
  change_dir gnutls-3.8.9
    export CFLAGS="-Wno-int-conversion"
    local config_options=""
    if [[ $compiler_flavors != "native" ]]; then
      local config_options+=" --disable-non-suiteb-curves" 
    fi	
    generic_configure "--disable-cxx --disable-doc --disable-tools --disable-tests --disable-nls --disable-rpath --disable-libdane --disable-gcc-warnings --disable-code-coverage
      --without-p11-kit --with-idn --without-tpm --with-included-unistring --with-included-libtasn1 -disable-gtk-doc-html --with-brotli $config_options"
    do_make_and_make_install
    reset_cflags
    if [[ $compiler_flavors != "native"  ]]; then
      sed -i.bak 's/-lgnutls.*/-lgnutls -lcrypt32 -lnettle -lhogweed -lgmp -liconv -lunistring/' "$PKG_CONFIG_PATH/gnutls.pc"
      if [[ $OSTYPE == darwin* ]]; then
        sed -i.bak 's/-lgnutls.*/-lgnutls -framework Security -framework Foundation/' "$PKG_CONFIG_PATH/gnutls.pc"
      fi
    fi
  change_dir ..
}

build_openssl-1.0.2() {
  download_and_unpack_file https://www.openssl.org/source/openssl-1.0.2p.tar.gz
  change_dir openssl-1.0.2p
    apply_patch file://$WINPATCHDIR/openssl-1.0.2l_lib-only.diff
    export CC="${cross_prefix}gcc"
    export AR="${cross_prefix}ar"
    export RANLIB="${cross_prefix}ranlib"
    local config_options="--prefix=$mingw_w64_x86_64_prefix zlib "
    if [ "$1" = "dllonly" ]; then
      config_options+="shared "
    else
      config_options+="no-shared no-dso "
    fi
    if [ "$bits_target" = "32" ]; then
      config_options+="mingw" # Build shared libraries ('libeay32.dll' and 'ssleay32.dll') if "dllonly" is specified.
      local arch=x86
    else
      config_options+="mingw64" # Build shared libraries ('libeay64.dll' and 'ssleay64.dll') if "dllonly" is specified.
      local arch=x86_64
    fi
    do_configure "$config_options" ./Configure
    if [[ ! -f Makefile_1 ]]; then
      sed -i_1 "s/-O3/-O2/" Makefile # Change CFLAGS (OpenSSL's 'Configure' already creates a 'Makefile.bak').
    fi
    if [ "$1" = "dllonly" ]; then
      do_make "build_libs"

      create_dir $WORKDIR/redist # Strip and pack shared libraries.
      archive="$WORKDIR/redist/openssl-${arch}-v1.0.2l.7z"
      if [[ ! -f $archive ]]; then
        for sharedlib in *.dll; do
          ${cross_prefix}strip $sharedlib
        done
        sed "s/$/\r/" LICENSE > LICENSE.txt
        7z a -mx=9 $archive *.dll LICENSE.txt && remove_path -f LICENSE.txt
      fi
    else
      do_make_and_make_install
    fi
    unset CC
    unset AR
    unset RANLIB
  change_dir ..
}

build_openssl-1.1.1() {
  download_and_unpack_file https://www.openssl.org/source/openssl-1.1.1.tar.gz
  change_dir openssl-1.1.1
    export CC="${cross_prefix}gcc"
    export AR="${cross_prefix}ar"
    export RANLIB="${cross_prefix}ranlib"
    local config_options="--prefix=$mingw_w64_x86_64_prefix zlib "
    if [ "$1" = "dllonly" ]; then
      config_options+="shared no-engine "
    else
      config_options+="no-shared no-dso no-engine "
    fi
    if [[ `uname` =~ "5.1" ]] || [[ `uname` =~ "6.0" ]]; then
      config_options+="no-async " # "Note: on older OSes, like CentOS 5, BSD 5, and Windows XP or Vista, you will need to configure with no-async when building OpenSSL 1.1.0 and above. The configuration system does not detect lack of the Posix feature on the platforms." (https://wiki.openssl.org/index.php/Compilation_and_Installation)
    fi
    if [[ $compiler_flavors == "native" ]]; then
      if [[ $OSTYPE == darwin* ]]; then
        config_options+="darwin64-x86_64-cc "
      else
        config_options+="linux-generic64 "
      fi
      local arch=native
    elif [ "$bits_target" = "32" ]; then
      config_options+="mingw" # Build shared libraries ('libcrypto-1_1.dll' and 'libssl-1_1.dll') if "dllonly" is specified.
      local arch=x86
    else
      config_options+="mingw64" # Build shared libraries ('libcrypto-1_1-x64.dll' and 'libssl-1_1-x64.dll') if "dllonly" is specified.
      local arch=x86_64
    fi
    do_configure "$config_options" ./Configure
    if [[ ! -f Makefile.bak ]]; then # Change CFLAGS.
      sed -i.bak "s/-O3/-O2/" Makefile
    fi
    do_make "build_libs"
    if [ "$1" = "dllonly" ]; then
      create_dir $WORKDIR/redist # Strip and pack shared libraries.
      archive="$WORKDIR/redist/openssl-${arch}-v1.1.0f.7z"
      if [[ ! -f $archive ]]; then
        for sharedlib in *.dll; do
          ${cross_prefix}strip $sharedlib
        done
        sed "s/$/\r/" LICENSE > LICENSE.txt
        7z a -mx=9 $archive *.dll LICENSE.txt && remove_path -f LICENSE.txt
      fi
    else
      do_make_install "" "install_dev"
    fi
    unset CC
    unset AR
    unset RANLIB
  change_dir ..
}

build_libogg() {
  do_git_checkout_and_make_install https://github.com/xiph/ogg.git
}

build_libvorbis() {
  do_git_checkout https://github.com/xiph/vorbis.git
  change_dir vorbis_git
    generic_configure "--disable-docs --disable-examples --disable-oggtest"
    do_make_and_make_install
  change_dir ..
}

build_libopus() {
  do_git_checkout https://github.com/xiph/opus.git opus_git origin/main
  change_dir opus_git
    generic_configure "--disable-doc --disable-extra-programs --disable-stack-protector"
    do_make_and_make_install
  change_dir ..
}

build_libspeexdsp() {
  do_git_checkout https://github.com/xiph/speexdsp.git
  change_dir speexdsp_git
    generic_configure "--disable-examples"
    do_make_and_make_install
  change_dir ..
}

build_libspeex() {
  do_git_checkout https://github.com/xiph/speex.git
  change_dir speex_git
    export SPEEXDSP_CFLAGS="-I$mingw_w64_x86_64_prefix/include"
    export SPEEXDSP_LIBS="-L$mingw_w64_x86_64_prefix/lib -lspeexdsp" # 'configure' somehow can't find SpeexDSP with 'pkg-config'.
    generic_configure "--disable-binaries" # If you do want the libraries, then 'speexdec.exe' needs 'LDFLAGS=-lwinmm'.
    do_make_and_make_install
    unset SPEEXDSP_CFLAGS
    unset SPEEXDSP_LIBS
  change_dir ..
}

build_libtheora() {
  do_git_checkout https://github.com/xiph/theora.git
  change_dir theora_git
    generic_configure "--disable-doc --disable-spec --disable-oggtest --disable-vorbistest --disable-examples --disable-asm" # disable asm: avoid [theora @ 0x1043144a0]error in unpack_block_qpis in 64 bit... [OK OS X 64 bit tho...]
    do_make_and_make_install
  change_dir ..
}

build_libsndfile() {
  do_git_checkout https://github.com/libsndfile/libsndfile.git
  change_dir libsndfile_git
    generic_configure "--disable-sqlite --disable-external-libs --disable-full-suite"
    do_make_and_make_install
    if [ "$1" = "install-libgsm" ]; then
      if [[ ! -f $mingw_w64_x86_64_prefix/lib/libgsm.a ]]; then
        install -m644 src/GSM610/gsm.h $mingw_w64_x86_64_prefix/include/gsm.h || exit 1
        install -m644 src/GSM610/.libs/libgsm.a $mingw_w64_x86_64_prefix/lib/libgsm.a || exit 1
      else
        echo "already installed GSM 6.10 ..."
      fi
    fi
  change_dir ..
}

build_mpg123() {
  do_svn_checkout svn://scm.orgis.org/mpg123/trunk mpg123_svn r5008 # avoid Think again failure
  change_dir mpg123_svn
    generic_configure_make_install
  change_dir ..
}

build_lame() {
  do_svn_checkout https://svn.code.sf.net/p/lame/svn/trunk/lame lame_svn r6525 # anything other than r6525 fails
  change_dir lame_svn
  # sed -i.bak '1s/^\xEF\xBB\xBF//' libmp3lame/i386/nasm.h # Remove a UTF-8 BOM that breaks nasm if it's still there; should be fixed in trunk eventually https://sourceforge.net/p/lame/patches/81/
    generic_configure "--enable-nasm --enable-libmpg123"
    do_make_and_make_install
  change_dir ..
}

build_twolame() {
  do_git_checkout https://github.com/njh/twolame.git twolame_git "origin/main"
  change_dir twolame_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only, front end refuses to build for some reason with git master
      sed -i.bak "/^SUBDIRS/s/ frontend.*//" Makefile.am || exit 1
    fi
    cpu_count=1 # maybe can't handle it http://betterlogic.com/roger/2017/07/mp3lame-woe/ comments
    generic_configure_make_install
    cpu_count=$original_cpu_count
  change_dir ..
}

# build_fdk-aac() {
# local checkout_dir=fdk-aac_git
#     if [[ ! -z $fdk_aac_git_checkout_version ]]; then
#       checkout_dir+="_$fdk_aac_git_checkout_version"
#       do_git_checkout "https://github.com/mstorsjo/fdk-aac.git" $checkout_dir "refs/tags/$fdk_aac_git_checkout_version"
#     else
#       do_git_checkout "https://github.com/mstorsjo/fdk-aac.git" $checkout_dir
#     fi
#   change_dir $checkout_dir
#     if [[ ! -f "configure" ]]; then
#       autoreconf -fiv || exit 1
#     fi
#     generic_configure_make_install
#   change_dir ..
# }

# build_AudioToolboxWrapper() {
#   do_git_checkout https://github.com/cynagenautes/AudioToolboxWrapper.git AudioToolboxWrapper_git
#   change_dir AudioToolboxWrapper_git
#     do_cmake "-B build -GNinja"
#     do_ninja_and_ninja_install
#     # This wrapper library enables FFmpeg to use AudioToolbox codecs on Windows, with DLLs shipped with iTunes.
#     # i.e. You need to install iTunes, or be able to LoadLibrary("CoreAudioToolbox.dll"), for this to work.
#     # test ffmpeg build can use it [ffmpeg -f lavfi -i sine=1000 -c aac_at -f mp4 -y NUL]
#   change_dir ..
# }

build_libopencore() {
  generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-0.1.6.tar.gz
  generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz
}

build_libilbc() {
  do_git_checkout https://github.com/TimothyGu/libilbc.git libilbc_git
  change_dir libilbc_git
    do_cmake "-B build -GNinja"
    do_ninja_and_ninja_install
  change_dir ..
}

build_libmodplug() {
  do_git_checkout https://github.com/Konstanty/libmodplug.git
  change_dir libmodplug_git
    sed -i.bak 's/__declspec(dllexport)//' "$mingw_w64_x86_64_prefix/include/libmodplug/modplug.h" #strip DLL import/export directives
    sed -i.bak 's/__declspec(dllimport)//' "$mingw_w64_x86_64_prefix/include/libmodplug/modplug.h"
    if [[ ! -f "configure" ]]; then
      autoreconf -fiv || exit 1
      automake --add-missing || exit 1
    fi
    generic_configure_make_install # or could use cmake I guess
  change_dir ..
}

build_libgme() {
  # do_git_checkout https://bitbucket.org/mpyne/game-music-emu.git
  download_and_unpack_file https://bitbucket.org/mpyne/game-music-emu/downloads/game-music-emu-0.6.3.tar.xz
  change_dir game-music-emu-0.6.3
    do_cmake_and_install "-DENABLE_UBSAN=0"
  change_dir ..
}

build_mingw_std_threads() {
  do_git_checkout https://github.com/meganz/mingw-std-threads.git # it needs std::mutex too :|
  change_dir mingw-std-threads_git
    cp *.h "$mingw_w64_x86_64_prefix/include"
  change_dir ..
}

build_opencv() {
  build_mingw_std_threads
  #do_git_checkout https://github.com/opencv/opencv.git # too big :|
  download_and_unpack_file https://github.com/opencv/opencv/archive/3.4.5.zip opencv-3.4.5
  create_dir opencv-3.4.5/build
  change_dir opencv-3.4.5
     apply_patch file://$WINPATCHDIR/opencv.detection_based.patch
  change_dir ..
  change_dir opencv-3.4.5/build
    # could do more here, it seems to think it needs its own internal libwebp etc...
    cpu_count=1
    do_cmake_from_build_dir .. "-DWITH_FFMPEG=0 -DOPENCV_GENERATE_PKGCONFIG=1 -DHAVE_DSHOW=0" # https://stackoverflow.com/q/40262928/32453, no pkg config by default on "windows", who cares ffmpeg
    do_make_and_make_install
    cp unix-install/opencv.pc $PKG_CONFIG_PATH
    cpu_count=$original_cpu_count
  change_dir ../..
}

build_facebooktransform360() {
  build_opencv
  do_git_checkout https://github.com/facebook/transform360.git
  change_dir transform360_git
    apply_patch file://$WINPATCHDIR/transform360.pi.diff -p1
  change_dir ..
  change_dir transform360_git/Transform360
    do_cmake ""
    sed -i.bak "s/isystem/I/g" CMakeFiles/Transform360.dir/includes_CXX.rsp # weird stdlib.h error
    do_make_and_make_install
  change_dir ../..
}

build_libbluray() {
  do_git_checkout https://code.videolan.org/videolan/libbluray.git
  activate_meson
  change_dir libbluray_git
    apply_patch "https://raw.githubusercontent.com/m-ab-s/mabs-patches/master/libbluray/0001-dec-prefix-with-libbluray-for-now.patch" -p1
    local meson_options="setup -Denable_examples=false -Dbdj_jar=disabled --wrap-mode=default . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install # "CPPFLAGS=\"-Ddec_init=libbr_dec_init\""
      sed -i.bak 's/-lbluray.*/-lbluray -lstdc++ -lssp -lgdi32/' "$PKG_CONFIG_PATH/libbluray.pc"
  deactivate
  change_dir ..
}

build_libbs2b() {
  download_and_unpack_file https://downloads.sourceforge.net/project/bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.gz
  change_dir libbs2b-3.1.0
    apply_patch file://$WINPATCHDIR/libbs2b.patch
    sed -i.bak "s/AC_FUNC_MALLOC//" configure.ac # #270
    export LIBS=-lm # avoid pow failure linux native
    generic_configure_make_install
    unset LIBS
  change_dir ..
}

build_libsoxr() {
  do_git_checkout https://github.com/chirlu/soxr.git soxr_git
  change_dir soxr_git
    do_cmake_and_install "-DWITH_OPENMP=0 -DBUILD_TESTS=0 -DBUILD_EXAMPLES=0"
  change_dir ..
}

build_libflite() {
  do_git_checkout https://github.com/festvox/flite.git flite_git
  change_dir flite_git
    apply_patch file://$WINPATCHDIR/flite-2.1.0_mingw-w64-fixes.patch
    if [[ ! -f main/Makefile.bak ]]; then									
    sed -i.bak "s/cp -pd/cp -p/" main/Makefile # friendlier cp for OS X
    fi
    generic_configure "--bindir=$mingw_w64_x86_64_prefix/bin --with-audio=none" 
    do_make
    if [[ ! -f $mingw_w64_x86_64_prefix/lib/libflite.a ]]; then
      cp -rf ./build/x86_64-mingw32/lib/libflite* $mingw_w64_x86_64_prefix/lib/ 
      cp -rf include $mingw_w64_x86_64_prefix/include/flite 
      # cp -rf ./bin/*.exe $mingw_w64_x86_64_prefix/bin # if want .exe's uncomment
    fi
  change_dir ..
}

build_libsnappy() {
  do_git_checkout https://github.com/google/snappy.git snappy_git # got weird failure once 1.1.8
  change_dir snappy_git
    do_cmake_and_install "-DBUILD_BINARY=OFF -DCMAKE_BUILD_TYPE=Release -DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF" # extra params from deadsix27 and from new cMakeLists.txt content
    remove_path -f $mingw_w64_x86_64_prefix/lib/libsnappy.dll.a # unintall shared :|
  change_dir ..
}

build_vamp_plugin() {
  #download_and_unpack_file https://code.soundsoftware.ac.uk/attachments/download/2691/vamp-plugin-sdk-2.10.0.tar.gz
  download_and_unpack_file https://github.com/vamp-plugins/vamp-plugin-sdk/archive/refs/tags/vamp-plugin-sdk-v2.10.zip vamp-plugin-sdk-vamp-plugin-sdk-v2.10
  #cd vamp-plugin-sdk-2.10.0
  change_dir vamp-plugin-sdk-vamp-plugin-sdk-v2.10
    apply_patch file://$WINPATCHDIR/vamp-plugin-sdk-2.10_static-lib.diff
    if [[ $compiler_flavors != "native" && ! -f src/vamp-sdk/PluginAdapter.cpp.bak ]]; then
      sed -i.bak "s/#include <mutex>/#include <mingw.mutex.h>/" src/vamp-sdk/PluginAdapter.cpp
    fi
    if [[ ! -f configure.bak ]]; then # Fix for "'M_PI' was not declared in this scope" (see https://stackoverflow.com/a/29264536).
      sed -i.bak "s/c++11/gnu++11/" configure
      sed -i.bak "s/c++11/gnu++11/" Makefile.in
    fi
    do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-programs"
    do_make "install-static" # No need for 'do_make_install', because 'install-static' already has install-instructions.
  change_dir ..
}

build_fftw() {
  download_and_unpack_file http://fftw.org/fftw-3.3.10.tar.gz
  change_dir fftw-3.3.10
    generic_configure "--disable-doc --prefix=$mingw_w64_x86_64_prefix --host=$host_target --enable-static --disable-shared"
    do_make_and_make_install
  change_dir ..
}

build_libsamplerate() {
  # I think this didn't work with ubuntu 14.04 [too old automake or some odd] :|
  do_git_checkout_and_make_install https://github.com/erikd/libsamplerate.git
  # but OS X can't use 0.1.9 :|
  # rubberband can use this, but uses speex bundled by default [any difference? who knows!]
}

build_librubberband() {
  do_git_checkout https://github.com/breakfastquay/rubberband.git rubberband_git 18c06ab8c431854056407c467f4755f761e36a8e
  change_dir rubberband_git
    apply_patch file://$WINPATCHDIR/rubberband_git_static-lib.diff # create install-static target
    do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-ladspa"
    do_make "install-static AR=${cross_prefix}ar" # No need for 'do_make_install', because 'install-static' already has install-instructions.
    sed -i.bak 's/-lrubberband.*$/-lrubberband -lfftw3 -lsamplerate -lstdc++/' $PKG_CONFIG_PATH/rubberband.pc
  change_dir ..
}

build_frei0r() {
  #do_git_checkout https://github.com/dyne/frei0r.git
  #cd frei0r_git
  download_and_unpack_file https://github.com/dyne/frei0r/archive/refs/tags/v2.3.3.tar.gz frei0r-2.3.3
  change_dir frei0r-2.3.3
    sed -i.bak 's/-arch i386//' CMakeLists.txt # OS X https://github.com/dyne/frei0r/issues/64
    do_cmake_and_install "-DWITHOUT_OPENCV=1" # XXX could look at this more...

    create_dir $WORKDIR/redist # Strip and pack shared libraries.
    if [ $bits_target = 32 ]; then
      local arch=x86
    else
      local arch=x86_64
    fi
    archive="$WORKDIR/redist/frei0r-plugins-${arch}-$(git describe --tags).7z"
    if [[ ! -f "$archive.done" ]]; then
      for sharedlib in $mingw_w64_x86_64_prefix/lib/frei0r-1/*.dll; do
        ${cross_prefix}strip $sharedlib
      done
      for doc in AUTHORS ChangeLog COPYING README.md; do
        sed "s/$/\r/" $doc > $mingw_w64_x86_64_prefix/lib/frei0r-1/$doc.txt
      done
      7z a -mx=9 $archive $mingw_w64_x86_64_prefix/lib/frei0r-1 && remove_path -f $mingw_w64_x86_64_prefix/lib/frei0r-1/*.txt
      touch "$archive.done" # for those with no 7z so it won't restrip every time
    fi
  change_dir ..
}

build_svt-hevc() {
  do_git_checkout https://github.com/OpenVisualCloud/SVT-HEVC.git
  create_dir SVT-HEVC_git/release
  change_dir SVT-HEVC_git/release
    do_cmake_from_build_dir .. "-DCMAKE_BUILD_TYPE=Release"
    do_make_and_make_install
  change_dir ../..
}

build_svt-vp9() {
  do_git_checkout https://github.com/OpenVisualCloud/SVT-VP9.git
  change_dir SVT-VP9_git/Build
    do_cmake_from_build_dir .. "-DCMAKE_BUILD_TYPE=Release"
    do_make_and_make_install
  change_dir ../..
}

build_svt-av1() {
  do_git_checkout https://github.com/pytorch/cpuinfo.git
  change_dir cpuinfo_git
    do_cmake_and_install # builds included cpuinfo bugged
  change_dir ..
  do_git_checkout https://gitlab.com/AOMediaCodec/SVT-AV1.git SVT-AV1_git 
  change_dir SVT-AV1_git
    do_cmake "-B build -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DUSE_CPUINFO=SYSTEM" # -DSVT_AV1_LTO=OFF if fails try adding this
    do_ninja_and_ninja_install
 change_dir ..
}

build_vidstab() {
  do_git_checkout https://github.com/georgmartius/vid.stab.git vid.stab_git
  change_dir vid.stab_git
    do_cmake_and_install "-DUSE_OMP=0" # '-DUSE_OMP' is on by default, but somehow libgomp ('cygwin_local_install/lib/gcc/i686-pc-cygwin/5.4.0/include/omp.h') can't be found, so '-DUSE_OMP=0' to prevent a compilation error.
  change_dir ..
}

build_libmysofa() {
  do_git_checkout https://github.com/hoene/libmysofa.git libmysofa_git "origin/main"
  change_dir libmysofa_git
    local cmake_params="-DBUILD_TESTS=0"
    if [[ $compiler_flavors == "native" ]]; then
      cmake_params+=" -DCODE_COVERAGE=0"
    fi
    do_cmake "$cmake_params"
    do_make_and_make_install
  change_dir ..
}

build_libcaca() {
  do_git_checkout https://github.com/cacalabs/libcaca.git libcaca_git 813baea7a7bc28986e474541dd1080898fac14d7
  change_dir libcaca_git
    apply_patch file://$WINPATCHDIR/libcaca_git_stdio-cruft.diff -p1 # Fix WinXP incompatibility.
    change_dir caca
      sed -i.bak "s/__declspec(dllexport)//g" *.h # get rid of the declspec lines otherwise the build will fail for undefined symbols
      sed -i.bak "s/__declspec(dllimport)//g" *.h
    change_dir ..
    generic_configure "--libdir=$mingw_w64_x86_64_prefix/lib --disable-csharp --disable-java --disable-cxx --disable-python --disable-ruby --disable-doc --disable-cocoa --disable-ncurses"
    do_make_and_make_install
    if [[ $compiler_flavors == "native" ]]; then
      sed -i.bak "s/-lcaca.*/-lcaca -lX11/" $PKG_CONFIG_PATH/caca.pc
    fi
  change_dir ..
}

build_libdecklink() {
  do_git_checkout https://gitlab.com/m-ab-s/decklink-headers.git decklink-headers_git 47d84f8d272ca6872b5440eae57609e36014f3b6
  change_dir decklink-headers_git
    do_make_install PREFIX=$mingw_w64_x86_64_prefix
  change_dir ..
}

build_zvbi() {
  do_git_checkout https://github.com/zapping-vbi/zvbi.git zvbi_git
  change_dir zvbi_git
    generic_configure "--disable-dvb --disable-bktr --disable-proxy --disable-nls --without-doxygen --disable-examples --disable-tests --without-libiconv-prefix"							
    do_make_and_make_install
  change_dir ..
}

build_fribidi() {
  download_and_unpack_file https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz # Get c2man errors building from repo
  change_dir fribidi-1.0.16
    generic_configure "--disable-debug --disable-deprecated --disable-docs"
    do_make_and_make_install
  change_dir ..
}

build_libsrt() {
  # do_git_checkout https://github.com/Haivision/srt.git # might be able to use these days...?
  download_and_unpack_file https://github.com/Haivision/srt/archive/v1.5.4.tar.gz srt-1.5.4
  change_dir srt-1.5.4
    if [[ $compiler_flavors != "native" ]]; then
      apply_patch file://$WINPATCHDIR/srt.app.patch -p1
    fi
    # CMake Warning at CMakeLists.txt:893 (message):
    #   On MinGW, some C++11 apps are blocked due to lacking proper C++11 headers
    #   for <thread>.  FIX IF POSSIBLE.
    do_cmake "-DUSE_ENCLIB=gnutls -DENABLE_SHARED=OFF -DENABLE_CXX11=OFF"
    do_make_and_make_install
  change_dir ..
}

build_libass() {
  do_git_checkout_and_make_install https://github.com/libass/libass.git
}

build_vulkan() {
  do_git_checkout https://github.com/KhronosGroup/Vulkan-Headers.git Vulkan-Headers_git v1.4.326
  change_dir Vulkan-Headers_git
    do_cmake_and_install "-DCMAKE_BUILD_TYPE=Release -DVULKAN_HEADERS_ENABLE_MODULE=NO -DVULKAN_HEADERS_ENABLE_TESTS=NO -DVULKAN_HEADERS_ENABLE_INSTALL=YES"
  change_dir ..
}

build_vulkan_loader() {
  do_git_checkout https://github.com/BtbN/Vulkan-Shim-Loader.git Vulkan-Shim-Loader.git  9657ca8e395ef16c79b57c8bd3f4c1aebb319137
  change_dir Vulkan-Shim-Loader.git 
    do_git_checkout https://github.com/KhronosGroup/Vulkan-Headers.git Vulkan-Headers v1.4.326
    do_cmake_and_install "-DCMAKE_BUILD_TYPE=Release -DVULKAN_SHIM_IMPERSONATE=ON"
  change_dir ..
}

build_libunwind() {
 do_git_checkout https://github.com/libunwind/libunwind.git libunwind_git
 change_dir libunwind_git
   autoreconf -i
   do_configure "--host=x86_64-linux-gnu --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static"
   do_make_and_make_install
 change_dir ..
}

build_libxxhash() {
  do_git_checkout https://github.com/Cyan4973/xxHash.git xxHash_git dev
  change_dir xxHash_git
    do_cmake "-S build/cmake -B build -DCMAKE_BUILD_TYPE=release -GNinja"
    do_ninja_and_ninja_install
  change_dir ..
}

build_spirv-cross() {
  do_git_checkout https://github.com/KhronosGroup/SPIRV-Cross.git SPIRV-Cross_git  b26ac3fa8bcfe76c361b56e3284b5276b23453ce
  change_dir SPIRV-Cross_git
    do_cmake "-B build -GNinja -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_SHARED=OFF -DCMAKE_BUILD_TYPE=Release -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_FORCE_PIC=ON -DSPIRV_CROSS_ENABLE_CPP=OFF"
    do_ninja_and_ninja_install
    mv $PKG_CONFIG_PATH/spirv-cross-c.pc $PKG_CONFIG_PATH/spirv-cross-c-shared.pc 
  change_dir ..
}

build_libdovi() {
  do_git_checkout https://github.com/quietvoid/dovi_tool.git dovi_tool_git
  change_dir dovi_tool_git
    if [[ ! -e $mingw_w64_x86_64_prefix/lib/libdovi.a ]]; then        
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . "$HOME/.cargo/env" && rustup update && rustup target add x86_64-pc-windows-gnu # rustup self uninstall
      if [[ $compiler_flavors != "native" ]]; then
        wget https://github.com/quietvoid/dovi_tool/releases/download/2.3.1/dovi_tool-2.3.1-x86_64-pc-windows-msvc.zip
	unzip -o dovi_tool-2.3.1-x86_64-pc-windows-msvc.zip -d $mingw_w64_x86_64_prefix/bin
	remove_path -f dovi_tool-2.3.1-x86_64-pc-windows-msvc.zip
      fi

      unset PKG_CONFIG_PATH	  
      if [[ $compiler_flavors == "native" ]]; then	
        cargo build --release --no-default-features --features internal-font && cp /target/release//dovi_tool $mingw_w64_x86_64_prefix/bin
      fi
      change_dir dolby_vision
        cargo install cargo-c --features=vendored-openssl
	if [[ $compiler_flavors == "native" ]]; then
	  cargo cinstall --release --prefix=$mingw_w64_x86_64_prefix --libdir=$mingw_w64_x86_64_prefix/lib --library-type=staticlib
	fi		
		
      export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
	if [[ $compiler_flavors != "native" ]]; then
	  cargo cinstall --release --prefix=$mingw_w64_x86_64_prefix --libdir=$mingw_w64_x86_64_prefix/lib --library-type=staticlib --target x86_64-pc-windows-gnu
        fi		  
      change_dir ..
      else echo "libdovi already installed"
    fi
  change_dir ..
}

build_shaderc() {
  do_git_checkout https://github.com/google/shaderc.git shaderc_git 3a44d5d7850da3601aa43d523a3d228f045fb43d
  change_dir shaderc_git
    ./utils/git-sync-deps  	
     do_cmake "-B build -DCMAKE_BUILD_TYPE=release -GNinja -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_TESTS=ON -DSPIRV_SKIP_TESTS=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DENABLE_EXCEPTIONS=ON -DENABLE_GLSLANG_BINARIES=OFF -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_TOOLS_BUILD_STATIC=ON -DBUILD_SHARED_LIBS=OFF"
	do_ninja_and_ninja_install
     cp build/libshaderc_util/libshaderc_util.a $mingw_w64_x86_64_prefix/lib
      sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/shaderc_combined.pc"
      sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/shaderc_static.pc"
  change_dir ..
}

build_libplacebo() { 
  build_vulkan_loader
  do_git_checkout_and_make_install https://github.com/ImageMagick/lcms.git 
  build_libunwind  
  build_libxxhash 
  build_spirv-cross
  build_libdovi
  build_shaderc
  do_git_checkout https://code.videolan.org/videolan/libplacebo.git libplacebo_git 515da9548ad734d923c7d0988398053f87b454d5
  activate_meson
  change_dir libplacebo_git
    git submodule update --init --recursive --depth=1 --filter=blob:none
    local config_options=""
    if [[ $OSTYPE != darwin* ]]; then
      local config_options+=" -Dvulkan-registry=$mingw_w64_x86_64_prefix/share/vulkan/registry/vk.xml" 
    fi		
    local meson_options="setup -Ddemos=false -Dbench=false -Dfuzz=false -Dvulkan=enabled -Dvk-proc-addr=disabled -Dshaderc=enabled -Dglslang=disabled -Dc_link_args=-static -Dcpp_link_args=-static $config_options . build" # https://mesonbuild.com/Dependencies.html#shaderc trigger use of shaderc_combined 
   if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    sed -i.bak 's/-lplacebo.*$/-lplacebo -lm -lshlwapi -lunwind -lxxhash -lversion -lstdc++/' "$PKG_CONFIG_PATH/libplacebo.pc"
  deactivate
  change_dir ..
}

build_libaribb24() {
  do_git_checkout_and_make_install https://github.com/nkoriyama/aribb24
}

build_libaribcaption() {
  do_git_checkout https://github.com/xqq/libaribcaption
  mkdir libaribcaption/build
  change_dir libaribcaption/build
    do_cmake_from_build_dir .. "-DCMAKE_BUILD_TYPE=Release"
    do_make_and_make_install
  change_dir ../..
}

build_libxavs() {
  do_git_checkout https://github.com/Distrotech/xavs.git xavs_git
  change_dir xavs_git
    if [[ ! -f Makefile.bak ]]; then
      sed -i.bak "s/O4/O2/" configure # Change CFLAGS.
    fi
    apply_patch "https://patch-diff.githubusercontent.com/raw/Distrotech/xavs/pull/1.patch" -p1
    do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix" # see https://github.com/rdp/ffmpeg-windows-build-helpers/issues/3
    do_make_and_make_install "$make_prefix_options"
    remove_path -f NUL # cygwin causes windows explorer to not be able to delete this folder if it has this oddly named file in it...
  change_dir ..
}

build_libxavs2() {
  do_git_checkout https://github.com/pkuvcl/xavs2.git xavs2_git
  change_dir xavs2_git
  if [ ! -e $PWD/build/linux/already_configured* ]; then
    curl "https://github.com/pkuvcl/xavs2/compare/master...1480c1:xavs2:gcc14/pointerconversion.patch" | git apply -v
  fi
  change_dir build/linux 
    do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$mingw_w64_x86_64_prefix --enable-strip" # --enable-pic
    do_make_and_make_install 
  change_dir ../../..
}

build_libdavs2() {
  do_git_checkout https://github.com/pkuvcl/davs2.git
  change_dir davs2_git/build/linux
    if [[ $host_target == 'i686-w64-mingw32' ]]; then
      do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$mingw_w64_x86_64_prefix --enable-pic --disable-asm"
    else
      do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$mingw_w64_x86_64_prefix --enable-pic"
    fi
    do_make_and_make_install
  change_dir ../../..
}

build_libxvid() {
  download_and_unpack_file https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz xvidcore
  change_dir xvidcore/build/generic
    apply_patch file://$WINPATCHDIR/xvidcore-1.3.7_static-lib.patch
    do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix" # no static option...
    do_make_and_make_install
  change_dir ../../..
}

build_libvpx() {
  do_git_checkout https://chromium.googlesource.com/webm/libvpx.git libvpx_git "origin/main"
  change_dir libvpx_git
    # apply_patch file://$WINPATCHDIR/vpx_160_semaphore.patch -p1 # perhaps someday can remove this after 1.6.0 or mingw fixes it LOL
    if [[ $compiler_flavors == "native" ]]; then
      local config_options=""
    elif [[ "$bits_target" = "32" ]]; then
      local config_options="--target=x86-win32-gcc"
    else
      local config_options="--target=x86_64-win64-gcc"
    fi
    export CROSS="$cross_prefix"  
    # VP8 encoder *requires* sse3 support
    do_configure "$config_options --prefix=$mingw_w64_x86_64_prefix --enable-ssse3 --enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth --extra-cflags=-fno-asynchronous-unwind-tables --extra-cflags=-mstackrealign" # fno for Error: invalid register for .seh_savexmm
    do_make_and_make_install
    unset CROSS
  change_dir ..
}

build_libaom() {
  do_git_checkout https://aomedia.googlesource.com/aom aom_git
  if [[ $compiler_flavors == "native" ]]; then
    local config_options=""
  elif [ "$bits_target" = "32" ]; then
    local config_options="-DCMAKE_TOOLCHAIN_FILE=../build/cmake/toolchains/x86-mingw-gcc.cmake -DAOM_TARGET_CPU=x86"
  else
    local config_options="-DCMAKE_TOOLCHAIN_FILE=../build/cmake/toolchains/x86_64-mingw-gcc.cmake -DAOM_TARGET_CPU=x86_64"
  fi
  create_dir aom_git/aom_build
  change_dir aom_git/aom_build
    do_cmake_from_build_dir .. $config_options
    do_make_and_make_install
  change_dir ../..
}

build_dav1d() {
  do_git_checkout https://code.videolan.org/videolan/dav1d.git libdav1d
  activate_meson
  change_dir libdav1d
    if [[ $bits_target == 32 || $bits_target == 64 ]]; then # XXX why 64???
      apply_patch file://$WINPATCHDIR/david_no_asm.patch -p1 # XXX report
    fi
    cpu_count=1 # XXX report :|
    local meson_options="setup -Denable_tests=false -Denable_examples=false . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${BASEDIR}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    cp build/src/libdav1d.a $mingw_w64_x86_64_prefix/lib || exit 1 # avoid 'run ranlib' weird failure, possibly older meson's https://github.com/mesonbuild/meson/issues/4138 :|
    cpu_count=$original_cpu_count
  deactivate
  change_dir ..
}

build_avisynth() {
  do_git_checkout https://github.com/AviSynth/AviSynthPlus.git avisynth_git
  create_dir avisynth_git/avisynth-build
  change_dir avisynth_git/avisynth-build
    do_cmake_from_build_dir .. -DHEADERS_ONLY:bool=on
    do_make "$make_prefix_options VersionGen install"
  change_dir ../..
}

build_libvvenc() {
  do_git_checkout https://github.com/fraunhoferhhi/vvenc.git libvvenc_git   
  change_dir libvvenc_git 
    do_cmake "-B build -DCMAKE_BUILD_TYPE=Release -DVVENC_ENABLE_LINK_TIME_OPT=OFF -DVVENC_INSTALL_FULLFEATURE_APP=ON -GNinja"
    do_ninja_and_ninja_install
  change_dir ..
}

build_libvvdec() {
  do_git_checkout https://github.com/fraunhoferhhi/vvdec.git libvvdec_git  
  change_dir libvvdec_git  
    do_cmake "-B build -DCMAKE_BUILD_TYPE=Release -DVVDEC_ENABLE_LINK_TIME_OPT=OFF -DVVDEC_INSTALL_VVDECAPP=ON -GNinja"
    do_ninja_and_ninja_install
  change_dir ..
}

build_libx265() {
  local checkout_dir=x265
  local remote="https://bitbucket.org/multicoreware/x265_git"
  if [[ ! -z $x265_git_checkout_version ]]; then
    checkout_dir+="_$x265_git_checkout_version"
    do_git_checkout "$remote" $checkout_dir "$x265_git_checkout_version"
  else
    if [[ $prefer_stable = "n" ]]; then
      checkout_dir+="_unstable"
      do_git_checkout "$remote" $checkout_dir "origin/master"
    fi
    if [[ $prefer_stable = "y" ]]; then
      do_git_checkout "$remote" $checkout_dir "origin/stable"
    fi
  fi
  change_dir $checkout_dir

  local cmake_params="-DENABLE_SHARED=0" # build x265.exe

  # Apply x86 noasm detection fix on newer versions
  if [[ $x265_git_checkout_version != *"3.5"* ]] && [[ $x265_git_checkout_version != *"3.4"* ]] && [[ $x265_git_checkout_version != *"3.3"* ]] && [[ $x265_git_checkout_version != *"3.2"* ]] && [[ $x265_git_checkout_version != *"3.1"* ]]; then
    git apply "$WINPATCHDIR/x265_x86_noasm_fix.patch"
  fi

  if [ "$bits_target" = "32" ]; then
    cmake_params+=" -DWINXP_SUPPORT=1" # enable windows xp/vista compatibility in x86 build, since it still can I think...
  fi
  create_dir 8bit 10bit 12bit

  # Build 12bit (main12)
  change_dir 12bit
  local cmake_12bit_params="$cmake_params -DENABLE_CLI=0 -DHIGH_BIT_DEPTH=1 -DMAIN12=1 -DEXPORT_C_API=0"
  if [ "$bits_target" = "32" ]; then
    cmake_12bit_params="$cmake_12bit_params -DENABLE_ASSEMBLY=OFF" # apparently required or build fails
  fi
  do_cmake_from_build_dir ../source "$cmake_12bit_params"
  do_make
  cp libx265.a ../8bit/libx265_main12.a

  # Build 10bit (main10)
  change_dir ../10bit
  local cmake_10bit_params="$cmake_params -DENABLE_CLI=0 -DHIGH_BIT_DEPTH=1 -DENABLE_HDR10_PLUS=1 -DEXPORT_C_API=0"
  if [ "$bits_target" = "32" ]; then
    cmake_10bit_params="$cmake_10bit_params -DENABLE_ASSEMBLY=OFF" # apparently required or build fails
  fi
  do_cmake_from_build_dir ../source "$cmake_10bit_params"
  do_make
  cp libx265.a ../8bit/libx265_main10.a

  # Build 8 bit (main) with linked 10 and 12 bit then install
  change_dir ../8bit
  cmake_params="$cmake_params -DENABLE_CLI=1 -DEXTRA_LINK_FLAGS=-L. -DLINKED_10BIT=1 -DLINKED_12BIT=1"
  if [[ $compiler_flavors == "native" && $OSTYPE != darwin* ]]; then
    cmake_params+=" -DENABLE_SHARED=0 -DEXTRA_LIB='$(pwd)/libx265_main10.a;$(pwd)/libx265_main12.a;-ldl'" # Native multi-lib CLI builds are slightly broken right now; other option is to -DENABLE_CLI=0, but this seems to work (https://bitbucket.org/multicoreware/x265/issues/520)
  else
    cmake_params+=" -DEXTRA_LIB='$(pwd)/libx265_main10.a;$(pwd)/libx265_main12.a'"
  fi
  do_cmake_from_build_dir ../source "$cmake_params"
  do_make
  mv libx265.a libx265_main.a
  if [[ $compiler_flavors == "native" && $OSTYPE == darwin* ]]; then
    libtool -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a 2>/dev/null
  else
    ${cross_prefix}ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
  fi
  make install # force reinstall in case you just switched from stable to not :|
  change_dir ../..
}

build_libopenh264() {
  do_git_checkout "https://github.com/cisco/openh264.git" openh264_git v2.6.0 #75b9fcd2669c75a99791 # wels/codec_api.h weirdness
  change_dir openh264_git
    sed -i.bak "s/_M_X64/_M_DISABLED_X64/" codec/encoder/core/inc/param_svc.h # for 64 bit, avoid missing _set_FMA3_enable, it needed to link against msvcrt120 to get this or something weird?
    if [[ $bits_target == 32 ]]; then
      local arch=i686 # or x86?
    else
      local arch=x86_64
    fi
    if [[ $compiler_flavors == "native" ]]; then
      # No need for 'do_make_install', because 'install-static' already has install-instructions. we want install static so no shared built...
      do_make "$make_prefix_options ASM=yasm install-static"
    else
      do_make "$make_prefix_options OS=mingw_nt ARCH=$arch ASM=yasm install-static"
    fi
  change_dir ..
}

build_libx264() {
  local checkout_dir="x264"
  if [[ $build_x264_with_libav == "y" ]]; then
    build_ffmpeg static --disable-libx264 ffmpeg_git_pre_x264 # installs libav locally so we can use it within x264.exe FWIW...
    checkout_dir="${checkout_dir}_with_libav"
    # they don't know how to use a normal pkg-config when cross compiling, so specify some manually: (see their mailing list for a request...)
    export LAVF_LIBS="$LAVF_LIBS $(pkg-config --libs libavformat libavcodec libavutil libswscale)"
    export LAVF_CFLAGS="$LAVF_CFLAGS $(pkg-config --cflags libavformat libavcodec libavutil libswscale)"
    export SWSCALE_LIBS="$SWSCALE_LIBS $(pkg-config --libs libswscale)"
  fi

  local x264_profile_guided=n # or y -- haven't gotten this proven yet...TODO

  if [[ $prefer_stable = "n" ]]; then
    checkout_dir="${checkout_dir}_unstable"
    do_git_checkout "https://code.videolan.org/videolan/x264.git" $checkout_dir "origin/master" 
  else
    do_git_checkout "https://code.videolan.org/videolan/x264.git" $checkout_dir  "origin/stable" 
  fi
  change_dir $checkout_dir
    if [[ ! -f configure.bak ]]; then # Change CFLAGS.
      sed -i.bak "s/O3 -/O2 -/" configure
    fi

    local configure_flags="--host=$host_target --enable-static --cross-prefix=$cross_prefix --prefix=$mingw_w64_x86_64_prefix --enable-strip" # --enable-win32thread --enable-debug is another useful option here?
    if [[ $build_x264_with_libav == "n" ]]; then
      configure_flags+=" --disable-lavf" # lavf stands for libavformat, there is no --enable-lavf option, either auto or disable...
    fi
    configure_flags+=" --bit-depth=all"
    for i in $CFLAGS; do
      configure_flags+=" --extra-cflags=$i" # needs it this way seemingly :|
    done

    if [[ $x264_profile_guided = y ]]; then
      # I wasn't able to figure out how/if this gave any speedup...
      # TODO more march=native here?
      # TODO profile guided here option, with wine?
      do_configure "$configure_flags"
      curl -4 http://samples.mplayerhq.hu/yuv4mpeg2/example.y4m.bz2 -O --fail || exit 1
      remove_path -f example.y4m # in case it exists already...
      bunzip2 example.y4m.bz2 || exit 1
      # XXX does this kill git updates? maybe a more general fix, since vid.stab does also?
      sed -i.bak "s_\\, ./x264_, wine ./x264_" Makefile # in case they have wine auto-run disabled http://askubuntu.com/questions/344088/how-to-ensure-wine-does-not-auto-run-exe-files
      do_make_and_make_install "fprofiled VIDS=example.y4m" # guess it has its own make fprofiled, so we don't need to manually add -fprofile-generate here...
    else
      # normal path non profile guided
      do_configure "$configure_flags"
      do_make
      make install # force reinstall in case changed stable -> unstable
    fi

    unset LAVF_LIBS
    unset LAVF_CFLAGS
    unset SWSCALE_LIBS
  change_dir ..
}

build_lsmash() { # an MP4 library
  do_git_checkout https://github.com/l-smash/l-smash.git l-smash
  change_dir l-smash
    do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix"
    do_make_and_make_install
  change_dir ..
}

build_libdvdread() {
  build_libdvdcss
  download_and_unpack_file http://dvdnav.mplayerhq.hu/releases/libdvdread-4.9.9.tar.xz # last revision before 5.X series so still works with MPlayer
  change_dir libdvdread-4.9.9
    # XXXX better CFLAGS here...
    generic_configure "CFLAGS=-DHAVE_DVDCSS_DVDCSS_H LDFLAGS=-ldvdcss --enable-dlfcn" # vlc patch: "--enable-libdvdcss" # XXX ask how I'm *supposed* to do this to the dvdread peeps [svn?]
    do_make_and_make_install
    sed -i.bak 's/-ldvdread.*/-ldvdread -ldvdcss/' "$PKG_CONFIG_PATH/dvdread.pc"
  change_dir ..
}

build_libdvdnav() {
  download_and_unpack_file http://dvdnav.mplayerhq.hu/releases/libdvdnav-4.2.1.tar.xz # 4.2.1. latest revision before 5.x series [?]
  change_dir libdvdnav-4.2.1
    if [[ ! -f ./configure ]]; then
      ./autogen.sh
    fi
    generic_configure_make_install
    sed -i.bak 's/-ldvdnav.*/-ldvdnav -ldvdread -ldvdcss -lpsapi/' "$PKG_CONFIG_PATH/dvdnav.pc" # psapi for dlfcn ... [hrm?]
  change_dir ..
}

build_libdvdcss() {
  generic_download_and_make_and_install https://download.videolan.org/pub/videolan/libdvdcss/1.2.13/libdvdcss-1.2.13.tar.bz2
}

build_libjpeg_turbo() {
  do_git_checkout https://github.com/libjpeg-turbo/libjpeg-turbo libjpeg-turbo_git "origin/main"
  change_dir libjpeg-turbo_git
    local cmake_params="-DENABLE_SHARED=0 -DCMAKE_ASM_NASM_COMPILER=yasm"
    if [[ $compiler_flavors != "native" ]]; then
      cmake_params+=" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake"
      local target_proc=AMD64
      if [ "$bits_target" = "32" ]; then
        target_proc=X86
      fi
      cat > toolchain.cmake << EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ${target_proc})
set(CMAKE_C_COMPILER ${cross_prefix}gcc)
set(CMAKE_RC_COMPILER ${cross_prefix}windres)
EOF
    fi
    do_cmake_and_install "$cmake_params"
  change_dir ..
}

build_libproxy() {
  # NB this lacks a .pc file still
  download_and_unpack_file https://libproxy.googlecode.com/files/libproxy-0.4.11.tar.gz
  change_dir libproxy-0.4.11
    sed -i.bak "s/= recv/= (void *) recv/" libmodman/test/main.cpp # some compile failure
    do_cmake_and_install
  change_dir ..
}

build_lua() {
  download_and_unpack_file https://www.lua.org/ftp/lua-5.3.3.tar.gz
  change_dir lua-5.3.3
    export AR="${cross_prefix}ar rcu" # needs rcu parameter so have to call it out different :|
    do_make "CC=${cross_prefix}gcc RANLIB=${cross_prefix}ranlib generic" # generic == "generic target" and seems to result in a static build, no .exe's blah blah the mingw option doesn't even build liblua.a
    unset AR
    do_make_install "INSTALL_TOP=$mingw_w64_x86_64_prefix" "generic install"
    cp etc/lua.pc $PKG_CONFIG_PATH
  change_dir ..
}

build_libhdhomerun() {
  exit 1 # still broken unfortunately, for cross compile :|
  download_and_unpack_file https://download.silicondust.com/hdhomerun/libhdhomerun_20150826.tgz libhdhomerun
  change_dir libhdhomerun
    do_make CROSS_COMPILE=$cross_prefix  OS=Windows_NT
  change_dir ..
}

build_dvbtee_app() {
  build_iconv # said it needed it
  build_curl # it "can use this" so why not
  #  build_libhdhomerun # broken but possible dependency apparently :|
  do_git_checkout https://github.com/mkrufky/libdvbtee.git libdvbtee_git
  change_dir libdvbtee_git
    # checkout its submodule, apparently required
    if [ ! -e libdvbpsi/bootstrap ]; then
      remove_path -rf libdvbpsi # remove placeholder
      do_git_checkout https://github.com/mkrufky/libdvbpsi.git
      change_dir libdvbpsi_git
        generic_configure_make_install # library dependency submodule... TODO don't install it, just leave it local :)
      change_dir ..
    fi
    generic_configure
    do_make # not install since don't have a dependency on the library
  change_dir ..
}

build_qt() {
  build_libjpeg_turbo # libjpeg a dependency [?]
  unset CFLAGS # it makes something of its own first, which runs locally, so can't use a foreign arch, or maybe it can, but not important enough: http://stackoverflow.com/a/18775859/32453 XXXX could look at this
  #download_and_unpack_file http://pkgs.fedoraproject.org/repo/pkgs/qt/qt-everywhere-opensource-src-4.8.7.tar.gz/d990ee66bf7ab0c785589776f35ba6ad/qt-everywhere-opensource-src-4.8.7.tar.gz # untested
  #cd qt-everywhere-opensource-src-4.8.7
  # download_and_unpack_file http://download.qt-project.org/official_releases/qt/5.1/5.1.1/submodules/qtbase-opensource-src-5.1.1.tar.xz qtbase-opensource-src-5.1.1 # not officially supported seems...so didn't try it
  download_and_unpack_file http://pkgs.fedoraproject.org/repo/pkgs/qt/qt-everywhere-opensource-src-4.8.5.tar.gz/1864987bdbb2f58f8ae8b350dfdbe133/qt-everywhere-opensource-src-4.8.5.tar.gz
  change_dir qt-everywhere-opensource-src-4.8.5
    apply_patch file://$WINPATCHDIR/imageformats.patch
    apply_patch file://$WINPATCHDIR/qt-win64.patch
    # vlc's configure options...mostly
    do_configure "-static -release -fast -no-exceptions -no-stl -no-sql-sqlite -no-qt3support -no-gif -no-libmng -qt-libjpeg -no-libtiff -no-qdbus -no-openssl -no-webkit -sse -no-script -no-multimedia -no-phonon -opensource -no-scripttools -no-opengl -no-script -no-scripttools -no-declarative -no-declarative-debug -opensource -no-s60 -host-little-endian -confirm-license -xplatform win32-g++ -device-option CROSS_COMPILE=$cross_prefix -prefix $mingw_w64_x86_64_prefix -prefix-install -nomake examples"
    if [ ! -f 'already_qt_maked_k' ]; then
      make sub-src -j $(get_cpu_count)
      make install sub-src # let it fail, baby, it still installs a lot of good stuff before dying on mng...? huh wuh?
      cp ./plugins/imageformats/libqjpeg.a $mingw_w64_x86_64_prefix/lib || exit 1 # I think vlc's install is just broken to need this [?]
      cp ./plugins/accessible/libqtaccessiblewidgets.a  $mingw_w64_x86_64_prefix/lib || exit 1 # this feels wrong...
      # do_make_and_make_install "sub-src" # sub-src might make the build faster? # complains on mng? huh?
      touch 'already_qt_maked_k'
    fi
    # vlc needs an adjust .pc file? huh wuh?
    sed -i.bak 's/Libs: -L${libdir} -lQtGui/Libs: -L${libdir} -lcomctl32 -lqjpeg -lqtaccessiblewidgets -lQtGui/' "$PKG_CONFIG_PATH/QtGui.pc" # sniff
  change_dir ..
  reset_cflags
}

build_vlc() {
  # currently broken, since it got too old for libavcodec and I didn't want to build its own custom one yet to match, and now it's broken with gcc 5.2.0 seemingly
  # call out dependencies here since it's a lot, plus hierarchical FTW!
  # should be ffmpeg 1.1.1 or some odd?
  echo "not building vlc, broken dependencies or something weird"
  return
  # vlc's own dependencies:
  build_lua
  build_libdvdread
  build_libdvdnav
  build_libx265
  build_libjpeg_turbo
  build_ffmpeg
  build_qt

  # currently vlc itself currently broken :|
  do_git_checkout https://github.com/videolan/vlc.git
  change_dir vlc_git
  #apply_patch file://$WINPATCHDIR/vlc_localtime_s.patch # git revision needs it...
  # outdated and patch doesn't apply cleanly anymore apparently...
  #if [[ "$non_free" = "y" ]]; then
  #  apply_patch https://raw.githubusercontent.com/gcsx/ffmpeg-windows-build-helpers/patch-5/patches/priorize_avcodec.patch
  #fi
  if [[ ! -f "configure" ]]; then
    ./bootstrap
  fi
  export DVDREAD_LIBS='-ldvdread -ldvdcss -lpsapi'
  do_configure "--disable-libgcrypt --disable-a52 --host=$host_target --disable-lua --disable-mad --enable-qt --disable-sdl --disable-mod" # don't have lua mingw yet, etc. [vlc has --disable-sdl [?]] x265 disabled until we care enough... Looks like the bluray problem was related to the BLURAY_LIBS definition. [not sure what's wrong with libmod]
  remove_path -f `find . -name *.exe` # try to force a rebuild...though there are tons of .a files we aren't rebuilding as well FWIW...:|
  remove_path -f already_ran_make* # try to force re-link just in case...
  do_make
  # do some gymnastics to avoid building the mozilla plugin for now [couldn't quite get it to work]
  #sed -i.bak 's_git://git.videolan.org/npapi-vlc.git_https://github.com/rdp/npapi-vlc.git_' Makefile # this wasn't enough...following lines instead...
  sed -i.bak "s/package-win-common: package-win-install build-npapi/package-win-common: package-win-install/" Makefile
  sed -i.bak "s/.*cp .*builddir.*npapi-vlc.*//g" Makefile
  make package-win-common # not do_make, fails still at end, plus this way we get new vlc.exe's
  echo "


     vlc success, created a file like ${PWD}/vlc-xxx-git/vlc.exe



"
  change_dir ..
  unset DVDREAD_LIBS
}

reset_cflags() {
  export CFLAGS=$original_cflags
}

reset_cppflags() {
  export CPPFLAGS=$original_cppflags
}

build_meson_cross() {
  local cpu_family="x86_64"
  if [ $bits_target = 32 ]; then
    cpu_family="x86"
  fi
  remove_path -fv meson-cross.mingw.txt
  cat >> meson-cross.mingw.txt << EOF
[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'  
default_library = 'static'  
prefer_static = 'true'
default_both_libraries = 'static'
backend = 'ninja'
prefix = '$mingw_w64_x86_64_prefix'
libdir = '$mingw_w64_x86_64_prefix/lib'
 
[binaries]
c = '${cross_prefix}gcc'
cpp = '${cross_prefix}g++'
ld = '${cross_prefix}ld'
ar = '${cross_prefix}ar'
strip = '${cross_prefix}strip'
nm = '${cross_prefix}nm'
windres = '${cross_prefix}windres'
dlltool = '${cross_prefix}dlltool'
pkg-config = 'pkg-config'
nasm = 'nasm'
cmake = 'cmake'

[host_machine]
system = 'windows'
cpu_family = '$cpu_family'
cpu = '$cpu_family'
endian = 'little'

[properties]
pkg_config_sysroot_dir = '$mingw_w64_x86_64_prefix'
pkg_config_libdir = '$pkg_config_sysroot_dir/lib/pkgconfig'
EOF
  mv -v meson-cross.mingw.txt ../..
}

get_local_meson_cross_with_propeties() {
  local local_dir="$1"
  if [[ -z $local_dir ]]; then
    local_dir="."
  fi
  cp ${BASEDIR}/meson-cross.mingw.txt "$local_dir"
  cat >> meson-cross.mingw.txt << EOF
EOF
}

build_mplayer() {
  # pre requisites
  build_libjpeg_turbo
  build_libdvdread
  build_libdvdnav

  download_and_unpack_file https://sourceforge.net/projects/mplayer-edl/files/mplayer-export-snapshot.2014-05-19.tar.bz2 mplayer-export-2014-05-19
  change_dir mplayer-export-2014-05-19
    do_git_checkout https://github.com/FFmpeg/FFmpeg ffmpeg d43c303038e9bd # known compatible commit
    export LDFLAGS='-lpthread -ldvdnav -ldvdread -ldvdcss' # not compat with newer dvdread possibly? huh wuh?
    export CFLAGS=-DHAVE_DVDCSS_DVDCSS_H
    do_configure "--enable-cross-compile --host-cc=cc --cc=${cross_prefix}gcc --windres=${cross_prefix}windres --ranlib=${cross_prefix}ranlib --ar=${cross_prefix}ar --as=${cross_prefix}as --nm=${cross_prefix}nm --enable-runtime-cpudetection --extra-cflags=$CFLAGS --with-dvdnav-config=$mingw_w64_x86_64_prefix/bin/dvdnav-config --disable-dvdread-internal --disable-libdvdcss-internal --disable-w32threads --enable-pthreads --extra-libs=-lpthread --enable-debug --enable-ass-internal --enable-dvdread --enable-dvdnav --disable-libvpx-lavc" # haven't reported the ldvdcss thing, think it's to do with possibly it not using dvdread.pc [?] XXX check with trunk
    # disable libvpx didn't work with its v1.5.0 some reason :|
    unset LDFLAGS
    reset_cflags
    sed -i.bak "s/HAVE_PTHREAD_CANCEL 0/HAVE_PTHREAD_CANCEL 1/g" config.h # mplayer doesn't set this up right?
    touch -t 201203101513 config.h # the above line change the modify time for config.h--forcing a full rebuild *every time* yikes!
    # try to force re-link just in case...
    remove_path -f *.exe
    remove_path -f already_ran_make* # try to force re-link just in case...
    do_make
    cp mplayer.exe mplayer_debug.exe
    ${cross_prefix}strip mplayer.exe
    echo "built ${PWD}/{mplayer,mencoder,mplayer_debug}.exe"
  change_dir ..
}

build_mp4box() { # like build_gpac
  # This script only builds the gpac_static lib plus MP4Box. Other tools inside
  # specify revision until this works: https://sourceforge.net/p/gpac/discussion/287546/thread/72cf332a/
  do_git_checkout https://github.com/gpac/gpac.git mp4box_gpac_git
  change_dir mp4box_gpac_git
    # are these tweaks needed? If so then complain to the mp4box people about it?
    sed -i.bak "s/has_dvb4linux=\"yes\"/has_dvb4linux=\"no\"/g" configure
    # XXX do I want to disable more things here?
    # ./prebuilt/cross_compilers/mingw-w64-i686/bin/i686-w64-mingw32-sdl-config
    generic_configure "  --cross-prefix=${cross_prefix} --target-os=MINGW32 --extra-cflags=-Wno-format --static-build --static-bin --disable-oss-audio --extra-ldflags=-municode --disable-x11 --sdl-cfg=${cross_prefix}sdl-config"
    ./check_revision.sh
    # I seem unable to pass 3 libs into the same config line so do it with sed...
    sed -i.bak "s/EXTRALIBS=.*/EXTRALIBS=-lws2_32 -lwinmm -lz/g" config.mak
    change_dir src
      do_make "$make_prefix_options"
    change_dir ..
    remove_path -f ./bin/gcc/MP4Box* # try and force a relink/rebuild of the .exe
    change_dir applications/mp4box
      remove_path -f already_ran_make* # ??
      do_make "$make_prefix_options"
    change_dir ../..
    # copy it every time just in case it was rebuilt...
    cp ./bin/gcc/MP4Box ./bin/gcc/MP4Box.exe # it doesn't name it .exe? That feels broken somehow...
    echo "built $(readlink -f ./bin/gcc/MP4Box.exe)"
  change_dir ..
}

build_libMXF() {
  download_and_unpack_file https://sourceforge.net/projects/ingex/files/1.0.0/libMXF/libMXF-src-1.0.0.tgz "libMXF-src-1.0.0"
  change_dir libMXF-src-1.0.0
    apply_patch file://$WINPATCHDIR/libMXF.diff
    do_make "MINGW_CC_PREFIX=$cross_prefix"
    #
    # Manual equivalent of make install. Enable it if desired. We shouldn't need it in theory since we never use libMXF.a file and can just hand pluck out the *.exe files already...
    #
    #cp libMXF/lib/libMXF.a $mingw_w64_x86_64_prefix/lib/libMXF.a
    #cp libMXF++/libMXF++/libMXF++.a $mingw_w64_x86_64_prefix/lib/libMXF++.a
    #mv libMXF/examples/writeaviddv50/writeaviddv50 libMXF/examples/writeaviddv50/writeaviddv50.exe
    #mv libMXF/examples/writeavidmxf/writeavidmxf libMXF/examples/writeavidmxf/writeavidmxf.exe
    #cp libMXF/examples/writeaviddv50/writeaviddv50.exe $mingw_w64_x86_64_prefix/bin/writeaviddv50.exe
    #cp libMXF/examples/writeavidmxf/writeavidmxf.exe $mingw_w64_x86_64_prefix/bin/writeavidmxf.exe
  change_dir ..
}

build_lsw() {
   # Build L-Smash-Works, which are AviSynth plugins based on lsmash/ffmpeg
   #build_ffmpeg static # dependency, assume already built since it builds before this does...
   build_lsmash # dependency
   do_git_checkout https://github.com/VFR-maniac/L-SMASH-Works.git lsw
   change_dir lsw/VapourSynth
     do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix --target-os=mingw"
     do_make_and_make_install
     # AviUtl is 32bit-only
     if [ "$bits_target" = "32" ]; then
       change_dir ../AviUtl
       do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix"
       do_make
     fi
   change_dir ../..
}

build_chromaprint() {
  echo $mingw_w64_x86_64_prefix
  build_fftw
  do_git_checkout https://github.com/acoustid/chromaprint.git chromaprint
  change_dir chromaprint
    cat > toolchain.cmake << EOF  
set(CMAKE_SYSTEM_NAME Windows)  
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc)  
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)  
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)  
set(CMAKE_FIND_ROOT_PATH $mingw_w64_x86_64_prefix)  
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)  
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)  
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)  
set(CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES "")  
set(CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES "")
set(CMAKE_C_FLAGS "-static -static-libgcc -static-libstdc++")  
set(CMAKE_CXX_FLAGS "-static -static-libgcc -static-libstdc++")
EOF
    do_cmake_and_install "-DCMAKE_BUILD_TYPE=Release -DBUILD_TOOLS=OFF -DBUILD_TESTS=OFF -DFFT_LIB=fftw3 -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake"
  change_dir ..
}

