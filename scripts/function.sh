#!/bin/bash

# shellcheck disable=SC2317
# shellcheck disable=SC1091
# shellcheck disable=SC2120
# shellcheck disable=SC2035
# shellcheck disable=SC2016

#echo -e ${SCRIPTDIR}/source.sh
#echo -e "${SCRIPTDIR}/variable.sh"

source "${SCRIPTDIR}/source.sh"

# 1. error_msg
error_exit() {
	local error_msg="$1"
	shift 1

	if [ "$error_msg" ]; then
		printf "%s\n" "$error_msg" >&2
	else
		printf "an error occured\n" >&2
	fi
	exit 1
}

# 1. info_msg
# 2. error_msg
# 3. no_exit
execute() {
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
		echo -e "${info_msg}" 1>>"$LOG_FILE" 2>&1
		"$@" >>"$LOG_FILE" 2>&1
	fi
}

# 1. path
create_dir() {
	local path="$1"

	echo -e "DEBUG: creating path ${path}" 1>>"$LOG_FILE" 2>&1

	if [ -z "$path" ]; then
		error_exit "ERROR: path argument is required"
	fi

	if [[ ! -e "$path" ]]; then
		execute "INFO: creating path: '$path'" "ERROR: unable to create directory '$path'" "true" \
			sudo mkdir "-pv" "$path"
	else
		echo -e "DEBUG: directory already exists, skipping creation." 1>>"$LOG_FILE" 2>&1
	fi
	execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
		sudo chown -R "$USER":"$USER" "$path"
	execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
		sudo chmod -R 777 "$path"
}

# 1. options
# @. paths
remove_path() {
	local options=$1
	shift 1 # Remove options, leaving only paths

	echo -e "DEBUG: removing paths: $*" 1>>"$LOG_FILE" 2>&1

	if [ $# -eq 0 ]; then
		echo -e "ERROR: at least one path argument is required" 1>>"$LOG_FILE" 2>&1
		return 1
	fi

	for path in "$@"; do
		echo -e "DEBUG: processing path: $path" 1>>"$LOG_FILE" 2>&1

		if [[ -e "$path" ]]; then
			if [ -z "$path" ]; then
				echo -e "ERROR: path argument is required" 1>>"$LOG_FILE" 2>&1
				continue
			fi
			execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
				chown -R "$USER":"$USER" "$path"
			execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
				sudo chmod -R 777 "$path"
			execute "INFO: removing path: '$path'" "ERROR: unable to remove path '$path'" "true" \
				rm "$options" "$path"
		else
			echo -e "INFO: path ${path} does not exist" 1>>"$LOG_FILE" 2>&1
		fi
	done
}

# 1. path
change_dir() {
	local path="$1"
	
	if [ -z "$path" ]; then
		error_exit "ERROR: path argument is required"
	fi

	if [[ -e "$path" ]]; then
		execute "INFO: changing to path: '$(realpath "$path")'" "ERROR: unable to cd to directory '$(realpath "$path")'" "true" \
			cd "$path"
		if [[ ! -r "$path" ]] || [[ ! -w "$path" ]] || [[ ! -x "$path" ]]; then
			execute "INFO: updating path permissions: '$(pwd)'" "ERROR: unable to update permissions on '$(pwd)'" "false" \
				sudo chmod -R 777 "$(pwd)"
		fi
	else
		echo -e "INFO: path '$path' does not exist" 1>>"$LOG_FILE" 2>&1
	fi
}

copy_path() {
	local source_path="$1"
	local destination_path="$2"
	local options="${3:-}"             # Default to empty
	local skip_if_exists="${4:-false}" # Default to false

	echo -e "DEBUG: copying from ${source_path} to ${destination_path}" 1>>"$LOG_FILE" 2>&1

	if [ -z "$source_path" ] || [ -z "$destination_path" ]; then
		error_exit "ERROR: both source and destination path arguments are required"
	fi

	if [ ! -e "$source_path" ]; then
		echo -e "ERROR: source path '$source_path' does not exist"
		return 0
	fi

	# Check if destination already exists
	if [ "$skip_if_exists" = "true" ] && [ -e "$destination_path" ]; then
		echo -e "INFO: destination '$destination_path' already exists, skipping copy" 1>>"$LOG_FILE" 2>&1
		return 0
	fi

	# Create destination directory if it doesn't exist
	local destination_dir
	destination_dir=$(dirname "$destination_path")

	if [ ! -d "$destination_dir" ]; then
		create_dir "$destination_dir"
	fi

	# Perform the copy operation
	if [ -n "$options" ]; then
		execute "INFO: copying path: '$source_path' to '$destination_path' with options '$options'" "ERROR: unable to copy '$source_path' to '$destination_path'" "false" \
			cp "$options" "$source_path" "$destination_path"
	else
		execute "INFO: copying path: '$source_path' to '$destination_path'" "ERROR: unable to copy '$source_path' to '$destination_path'" "false" \
			cp -r "$source_path" "$destination_path"
	fi

	# Update permissions on the copied path
	execute "INFO: updating permissions on copied path: '$destination_path'" "ERROR: unable to update permissions on '$destination_path'" "false" \
		sudo chown -R "$USER":"$USER" "$destination_path"
	execute "INFO: updating path permissions: '$destination_path'" "ERROR: unable to update permissions on '$destination_path'" "false" \
		sudo chmod -R 777 "$destination_path"
}

check_files_exist() {
	local skip_if_missing="${1:-false}"
	shift 1
	local files=("$@")

	echo -e "DEBUG: checking ${#files[@]} files" 1>>"$LOG_FILE" 2>&1

	if [ ${#files[@]} -eq 0 ]; then
		echo -e "ERROR: file list argument is required" 1>>"$LOG_FILE" 2>&1
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
			echo -e "INFO: ${#missing_files[@]} files are missing" 1>>"$LOG_FILE" 2>&1
			return 0
		else
			error_exit "ERROR: ${#missing_files[@]} required files are missing: ${missing_files[*]}"
		fi
	else
		echo -e "INFO: all ${#files[@]} files exist" 1>>"$LOG_FILE" 2>&1
	fi
}

get_arch_name() {
	case $1 in
	0) echo -e "arm-v7a" ;;              # android
	1) echo -e "arm-v7a-neon" ;;         # android
	2) echo -e "armv7" ;;                # ios
	3) echo -e "armv7s" ;;               # ios
	4) echo -e "arm64-v8a" ;;            # android
	5) echo -e "arm64" ;;                # ios, tvos, macos
	6) echo -e "arm64e" ;;               # ios
	7) echo -e "i386" ;;                 # ios
	8) echo -e "x86" ;;                  # android
	9) echo -e "x86-64" ;;               # android, ios, linux, macos, tvos, windows
	10) echo -e "x86-64-mac-catalyst" ;; # ios
	11) echo -e "arm64-mac-catalyst" ;;  # ios
	12) echo -e "arm64-simulator" ;;     # ios, tvos
	esac
}

get_full_arch_name() {
	case $1 in
	8) echo -e "i686" ;;
	9) echo -e "x86_64" ;;
	10) echo -e "x86_64-mac-catalyst" ;;
	*) get_arch_name "$1" ;;
	esac
}

from_arch_name() {
	case $1 in
	arm-v7a) echo -e 0 ;;                 # android
	arm-v7a-neon) echo -e 1 ;;            # android
	armv7) echo -e 2 ;;                   # ios
	armv7s) echo -e 3 ;;                  # ios
	arm64-v8a) echo -e 4 ;;               # android
	arm64) echo -e 5 ;;                   # ios, tvos, macos
	arm64e) echo -e 6 ;;                  # ios
	i386) echo -e 7 ;;                    # ios
	x86 | i686 | win32) echo -e 8 ;;      # android, windows
	x86-64 | x86_64 | win64) echo -e 9 ;; # android, ios, linux, macos, tvos
	x86-64-mac-catalyst) echo -e 10 ;;    # ios
	arm64-mac-catalyst) echo -e 11 ;;     # ios
	arm64-simulator) echo -e 12 ;;        # ios
	esac
}

get_library_name() {
	case $1 in
	0) echo -e "fontconfig" ;;
	1) echo -e "freetype" ;;
	2) echo -e "fribidi" ;;
	3) echo -e "gmp" ;;
	4) echo -e "gnutls" ;;
	5) echo -e "lame" ;;
	6) echo -e "libass" ;;
	7) echo -e "libiconv" ;;
	8) echo -e "libtheora" ;;
	9) echo -e "libvorbis" ;;
	10) echo -e "libvpx" ;;
	11) echo -e "libwebp" ;;
	12) echo -e "libxml2" ;;
	13) echo -e "opencore-amr" ;;
	14) echo -e "shine" ;;
	15) echo -e "speex" ;;
	16) echo -e "dav1d" ;;
	17) echo -e "kvazaar" ;;
	18) echo -e "x264" ;;
	19) echo -e "xvidcore" ;;
	20) echo -e "x265" ;;
	21) echo -e "libvidstab" ;;
	22) echo -e "rubberband" ;;
	23) echo -e "libilbc" ;;
	24) echo -e "opus" ;;
	25) echo -e "snappy" ;;
	26) echo -e "soxr" ;;
	27) echo -e "libaom" ;;
	28) echo -e "chromaprint" ;;
	29) echo -e "twolame" ;;
	30) echo -e "sdl" ;;
	31) echo -e "tesseract" ;;
	32) echo -e "openh264" ;;
	33) echo -e "vo-amrwbenc" ;;
	34) echo -e "zimg" ;;
	35) echo -e "openssl" ;;
	36) echo -e "srt" ;;
	37) echo -e "giflib" ;;
	38) echo -e "jpeg" ;;
	39) echo -e "libogg" ;;
	40) echo -e "libpng" ;;
	41) echo -e "libuuid" ;;
	42) echo -e "nettle" ;;
	43) echo -e "tiff" ;;
	44) echo -e "expat" ;;
	45) echo -e "libsndfile" ;;
	46) echo -e "leptonica" ;;
	47) echo -e "libsamplerate" ;;
	48) echo -e "harfbuzz" ;;
	49) echo -e "cpu-features" ;;
	50)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]]; then
			echo -e "android-zlib"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "ios-zlib"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
			echo -e "linux-zlib"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-zlib"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "tvos-zlib"
		fi
		;;
	51) echo -e "linux-alsa" ;;
	52) echo -e "android-media-codec" ;;
	53)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "ios-audiotoolbox"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-audiotoolbox"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "tvos-audiotoolbox"
		fi
		;;
	54)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "ios-bzip2"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-bzip2"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "tvos-bzip2"
		fi
		;;
	55)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "ios-videotoolbox"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-videotoolbox"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "tvos-videotoolbox"
		fi
		;;
	56)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "ios-avfoundation"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-avfoundation"
		fi
		;;
	57)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "ios-libiconv"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-libiconv"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "tvos-libiconv"
		fi
		;;
	58)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "ios-libuuid"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-libuuid"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "tvos-libuuid"
		fi
		;;
	59)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-coreimage"
		fi
		;;
	60)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-opencl"
		fi
		;;
	61)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "macos-opengl"
		fi
		;;
	62) echo -e "linux-fontconfig" ;;
	63) echo -e "linux-freetype" ;;
	64) echo -e "linux-fribidi" ;;
	65) echo -e "linux-gmp" ;;
	66) echo -e "linux-gnutls" ;;
	67) echo -e "linux-lame" ;;
	68) echo -e "linux-libass" ;;
	69) echo -e "linux-libiconv" ;;
	70) echo -e "linux-libtheora" ;;
	71) echo -e "linux-libvorbis" ;;
	72) echo -e "linux-libvpx" ;;
	73) echo -e "linux-libwebp" ;;
	74) echo -e "linux-libxml2" ;;
	75) echo -e "linux-opencore-amr" ;;
	76) echo -e "linux-shine" ;;
	77) echo -e "linux-speex" ;;
	78) echo -e "linux-opencl" ;;
	79) echo -e "linux-xvidcore" ;;
	80) echo -e "linux-x265" ;;
	81) echo -e "linux-libvidstab" ;;
	82) echo -e "linux-rubberband" ;;
	83) echo -e "linux-v4l2" ;;
	84) echo -e "linux-opus" ;;
	85) echo -e "linux-snappy" ;;
	86) echo -e "linux-soxr" ;;
	87) echo -e "linux-twolame" ;;
	88) echo -e "linux-sdl" ;;
	89) echo -e "linux-tesseract" ;;
	90) echo -e "linux-vaapi" ;;
	91) echo -e "linux-vo-amrwbenc" ;;
	esac
}

from_library_name() {
	case $1 in
	fontconfig) echo -e 0 ;;
	freetype) echo -e 1 ;;
	fribidi) echo -e 2 ;;
	gmp) echo -e 3 ;;
	gnutls) echo -e 4 ;;
	lame) echo -e 5 ;;
	libass) echo -e 6 ;;
	libiconv) echo -e 7 ;;
	libtheora) echo -e 8 ;;
	libvorbis) echo -e 9 ;;
	libvpx) echo -e 10 ;;
	libwebp) echo -e 11 ;;
	libxml2) echo -e 12 ;;
	opencore-amr) echo -e 13 ;;
	shine) echo -e 14 ;;
	speex) echo -e 15 ;;
	dav1d) echo -e 16 ;;
	kvazaar) echo -e 17 ;;
	x264) echo -e 18 ;;
	xvidcore) echo -e 19 ;;
	x265) echo -e 20 ;;
	libvidstab) echo -e 21 ;;
	rubberband) echo -e 22 ;;
	libilbc) echo -e 23 ;;
	opus) echo -e 24 ;;
	snappy) echo -e 25 ;;
	soxr) echo -e 26 ;;
	libaom) echo -e 27 ;;
	chromaprint) echo -e 28 ;;
	twolame) echo -e 29 ;;
	sdl) echo -e 30 ;;
	tesseract) echo -e 31 ;;
	openh264) echo -e 32 ;;
	vo-amrwbenc) echo -e 33 ;;
	zimg) echo -e 34 ;;
	openssl) echo -e 35 ;;
	srt) echo -e 36 ;;
	giflib) echo -e 37 ;;
	jpeg) echo -e 38 ;;
	libogg) echo -e 39 ;;
	libpng) echo -e 40 ;;
	libuuid) echo -e 41 ;;
	nettle) echo -e 42 ;;
	tiff) echo -e 43 ;;
	expat) echo -e 44 ;;
	libsndfile) echo -e 45 ;;
	leptonica) echo -e 46 ;;
	libsamplerate) echo -e 47 ;;
	harfbuzz) echo -e 48 ;;
	cpu-features) echo -e 49 ;;
	android-zlib | ios-zlib | linux-zlib | macos-zlib | tvos-zlib) echo -e 50 ;;
	linux-alsa) echo -e 51 ;;
	android-media-codec) echo -e 52 ;;
	ios-audiotoolbox | macos-audiotoolbox | tvos-audiotoolbox) echo -e 53 ;;
	ios-bzip2 | macos-bzip2 | tvos-bzip2) echo -e 54 ;;
	ios-videotoolbox | macos-videotoolbox | tvos-videotoolbox) echo -e 55 ;;
	ios-avfoundation | macos-avfoundation) echo -e 56 ;;
	ios-libiconv | macos-libiconv | tvos-libiconv) echo -e 57 ;;
	ios-libuuid | macos-libuuid | tvos-libuuid) echo -e 58 ;;
	macos-coreimage) echo -e 59 ;;
	macos-opencl) echo -e 60 ;;
	macos-opengl) echo -e 61 ;;
	linux-fontconfig) echo -e 62 ;;
	linux-freetype) echo -e 63 ;;
	linux-fribidi) echo -e 64 ;;
	linux-gmp) echo -e 65 ;;
	linux-gnutls) echo -e 66 ;;
	linux-lame) echo -e 67 ;;
	linux-libass) echo -e 68 ;;
	linux-libiconv) echo -e 69 ;;
	linux-libtheora) echo -e 70 ;;
	linux-libvorbis) echo -e 71 ;;
	linux-libvpx) echo -e 72 ;;
	linux-libwebp) echo -e 73 ;;
	linux-libxml2) echo -e 74 ;;
	linux-opencore-amr) echo -e 75 ;;
	linux-shine) echo -e 76 ;;
	linux-speex) echo -e 77 ;;
	linux-opencl) echo -e 78 ;;
	linux-xvidcore) echo -e 79 ;;
	linux-x265) echo -e 80 ;;
	linux-libvidstab) echo -e 81 ;;
	linux-rubberband) echo -e 82 ;;
	linux-v4l2) echo -e 83 ;;
	linux-opus) echo -e 84 ;;
	linux-snappy) echo -e 85 ;;
	linux-soxr) echo -e 86 ;;
	linux-twolame) echo -e 87 ;;
	linux-sdl) echo -e 88 ;;
	linux-tesseract) echo -e 89 ;;
	linux-vaapi) echo -e 90 ;;
	linux-vo-amrwbenc) echo -e 91 ;;
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
		echo -e "0"
		;;

	# ALL EXCEPT LINUX
	0 | 1 | 2 | 3 | 4 | 5 | 6 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 19 | 20 | 21 | 22 | 24 | 25 | 26 | 29 | 30 | 31 | 33 | 37 | 38 | 39 | 40 | 42 | 43 | 44 | 45 | 46 | 47 | 48)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
			echo -e "1"
		else
			echo -e "0"
		fi
		;;

	# ONLY LINUX
	51)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
			echo -e "0"
		else
			echo -e "1"
		fi
		;;

	# ONLY LINUX
	62 | 63 | 64 | 65 | 66 | 67 | 68 | 69 | 70 | 71 | 72 | 73 | 74 | 75 | 76 | 77 | 78 | 79 | 80 | 81 | 82 | 83 | 84 | 85 | 86 | 87 | 88 | 89 | 90 | 91 | 92)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
			echo -e "0"
		else
			echo -e "1"
		fi
		;;
	*)
		echo -e "1"
		;;
	esac
}

#
# 1. <arch name>
#
is_arch_supported_on_platform() {
	local arch_index=$(from_arch_name "$1")
	case ${arch_index} in
	"$ARCH_X86_64")
		echo -e 1
		;;
	esac
}

get_package_config_file_name() {
	case $1 in
	1) echo -e "freetype2" ;;
	5) echo -e "libmp3lame" ;;
	8) echo -e "theora" ;;
	9) echo -e "vorbis" ;;
	10) echo -e "vpx" ;;
	12) echo -e "libxml-2.0" ;;
	13) echo -e "opencore-amrnb" ;;
	21) echo -e "vidstab" ;;
	27) echo -e "aom" ;;
	28) echo -e "libchromaprint" ;;
	30) echo -e "sdl2" ;;
	38) echo -e "libjpeg" ;;
	39) echo -e "ogg" ;;
	43) echo -e "libtiff-4" ;;
	45) echo -e "sndfile" ;;
	46) echo -e "lept" ;;
	47) echo -e "samplerate" ;;
	58) echo -e "uuid" ;;
	*) echo -e "$(get_library_name "$1")" ;;
	esac
}

get_meson_target_host_family() {
	case ${FFMPEG_KIT_BUILD_TYPE} in
	android)
		echo -e "android"
		;;
	linux)
		echo -e "linux"
		;;
	*)
		echo -e "darwin"
		;;
	esac
}

get_meson_target_cpu_family() {
	case "$ARCH" in
	arm*)
		echo -e "arm"
		;;
	x86-64*)
		echo -e "x86_64"
		;;
	x86*)
		echo -e "x86"
		;;
	*)
		echo -e "${ARCH}"
		;;
	esac
}

get_target() {
	case ${ARCH} in
	*-mac-catalyst)
		echo -e "$(get_target_cpu)-apple-ios$(get_min_sdk_version)-macabi"
		;;
	armv7 | armv7s | arm64e)
		echo -e "$(get_target_cpu)-apple-ios$(get_min_sdk_version)"
		;;
	i386)
		echo -e "$(get_target_cpu)-apple-ios$(get_min_sdk_version)-simulator"
		;;
	arm64)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "$(get_target_cpu)-apple-ios$(get_min_sdk_version)"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "$(get_target_cpu)-apple-macos$(get_min_sdk_version)"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "$(get_target_cpu)-apple-tvos$(get_min_sdk_version)"
		fi
		;;
	arm64-simulator)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "$(get_target_cpu)-apple-ios$(get_min_sdk_version)-simulator"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "$(get_target_cpu)-apple-tvos$(get_min_sdk_version)-simulator"
		fi
		;;
	x86-64 | x86_64)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]]; then
			echo -e "x86_64-linux-android"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "$(get_target_cpu)-apple-ios$(get_min_sdk_version)-simulator"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]]; then
			echo -e "$(get_target_cpu)-linux-gnu"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "$(get_target_cpu)-apple-darwin$(get_min_sdk_version)"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "$(get_target_cpu)-apple-tvos$(get_min_sdk_version)-simulator"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "windows" ]]; then
			echo -e "x86_64-w64-mingw32"
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
		echo -e "arm-linux-androideabi"
		;;
	armv7 | armv7s | arm64e | i386 | *-mac-catalyst)
		echo -e "$(get_target_cpu)-ios-darwin"
		;;
	arm64-simulator)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "$(get_target_cpu)-ios-darwin"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "$(get_target_cpu)-tvos-darwin"
		fi
		;;
	arm64-v8a)
		echo -e "aarch64-linux-android"
		;;
	arm64)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]]; then
			echo -e "$(get_target_cpu)-ios-darwin"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]]; then
			echo -e "$(get_target_cpu)-apple-darwin"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]]; then
			echo -e "$(get_target_cpu)-tvos-darwin"
		fi
		;;
	x86 | i686 | win32)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "windows" ]]; then
			echo -e "i686-w64-mingw32"
		else
			echo -e "i686-linux-android"
		fi
		;;
	x86-64 | x86_64 | win64)
		if [[ ${FFMPEG_KIT_BUILD_TYPE} == "android" ]] && [[ ${ARCH} != "win64" ]]; then
			echo -e "x86_64-linux-android"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "ios" ]] && [[ ${ARCH} != "win64" ]]; then
			echo -e "$(get_target_cpu)-ios-darwin"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "linux" ]] && [[ ${ARCH} != "win64" ]]; then
			echo -e "$(get_target_cpu)-linux-gnu"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "macos" ]] && [[ ${ARCH} != "win64" ]]; then
			echo -e "$(get_target_cpu)-apple-darwin"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "tvos" ]] && [[ ${ARCH} != "win64" ]]; then
			echo -e "$(get_target_cpu)-tvos-darwin"
		elif [[ ${FFMPEG_KIT_BUILD_TYPE} == "windows" ]] || [[ ${ARCH} == "win64" ]]; then
			echo -e "x86_64-w64-mingw32"
		fi
		;;
	esac
}

#
# 1. key
# 2. value
#
generate_custom_library_environment_variables() {
	CUSTOM_KEY=$(echo -e "CUSTOM_$1" | sed "s/\-/\_/g" | tr '[:lower:]' '[:upper:]')
	CUSTOM_VALUE="$2"

	export "${CUSTOM_KEY}"="${CUSTOM_VALUE}"

	echo -e "INFO: Custom library env variable generated: ${CUSTOM_KEY}=${CUSTOM_VALUE}\n" 1>>"${BASEDIR}"/build.log 2>&1
}

skip_library() {
	SKIP_VARIABLE=$(echo -e "SKIP_$1" | sed "s/\-/\_/g")

	export "${SKIP_VARIABLE}"=1
}

no_output_redirection() {
	export NO_OUTPUT_REDIRECTION=1
}

no_workspace_cleanup_library() {
	NO_WORKSPACE_CLEANUP_VARIABLE=$(echo -e "NO_WORKSPACE_CLEANUP_$1" | sed "s/\-/\_/g")

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
	COMMAND=$(echo -e "$0" | sed -e 's/\.\///g')

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

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavcodec_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVCODEC_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavcodec/version_major.h | sed -e 's|LIBAVCODEC_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libavdevice_version() {
	local MAJOR=$(grep -Eo ' LIBAVDEVICE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version_major.h | sed -e 's|LIBAVDEVICE_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBAVDEVICE_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version.h | sed -e 's|LIBAVDEVICE_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBAVDEVICE_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version.h | sed -e 's|LIBAVDEVICE_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavdevice_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVDEVICE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavdevice/version_major.h | sed -e 's|LIBAVDEVICE_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libavfilter_version() {
	local MAJOR=$(grep -Eo ' LIBAVFILTER_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version_major.h | sed -e 's|LIBAVFILTER_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBAVFILTER_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version.h | sed -e 's|LIBAVFILTER_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBAVFILTER_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version.h | sed -e 's|LIBAVFILTER_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavfilter_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVFILTER_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavfilter/version_major.h | sed -e 's|LIBAVFILTER_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libavformat_version() {
	local MAJOR=$(grep -Eo ' LIBAVFORMAT_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavformat/version_major.h | sed -e 's|LIBAVFORMAT_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBAVFORMAT_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavformat/version.h | sed -e 's|LIBAVFORMAT_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBAVFORMAT_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavformat/version.h | sed -e 's|LIBAVFORMAT_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavformat_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVFORMAT_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavformat/version_major.h | sed -e 's|LIBAVFORMAT_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libavutil_version() {
	local MAJOR=$(grep -Eo ' LIBAVUTIL_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavutil/version.h | sed -e 's|LIBAVUTIL_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBAVUTIL_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libavutil/version.h | sed -e 's|LIBAVUTIL_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBAVUTIL_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libavutil/version.h | sed -e 's|LIBAVUTIL_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libavutil_major_version() {
	local MAJOR=$(grep -Eo ' LIBAVUTIL_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libavutil/version_major.h | sed -e 's|LIBAVUTIL_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libswresample_version() {
	local MAJOR=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswresample/version_major.h | sed -e 's|LIBSWRESAMPLE_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libswresample/version.h | sed -e 's|LIBSWRESAMPLE_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libswresample/version.h | sed -e 's|LIBSWRESAMPLE_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libswresample_major_version() {
	local MAJOR=$(grep -Eo ' LIBSWRESAMPLE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswresample/version_major.h | sed -e 's|LIBSWRESAMPLE_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

get_ffmpeg_libswscale_version() {
	local MAJOR=$(grep -Eo ' LIBSWSCALE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswscale/version_major.h | sed -e 's|LIBSWSCALE_VERSION_MAJOR||g;s| ||g')
	local MINOR=$(grep -Eo ' LIBSWSCALE_VERSION_MINOR .*' "${BASEDIR}"/src/ffmpeg/libswscale/version.h | sed -e 's|LIBSWSCALE_VERSION_MINOR||g;s| ||g')
	local MICRO=$(grep -Eo ' LIBSWSCALE_VERSION_MICRO .*' "${BASEDIR}"/src/ffmpeg/libswscale/version.h | sed -e 's|LIBSWSCALE_VERSION_MICRO||g;s| ||g')

	echo -e "${MAJOR}.${MINOR}.${MICRO}"
}

get_ffmpeg_libswscale_major_version() {
	local MAJOR=$(grep -Eo ' LIBSWSCALE_VERSION_MAJOR .*' "${BASEDIR}"/src/ffmpeg/libswscale/version_major.h | sed -e 's|LIBSWSCALE_VERSION_MAJOR||g;s| ||g')

	echo -e "${MAJOR}"
}

#
# 1. LIBRARY NAME
#
get_ffmpeg_library_version() {
	case $1 in
	libavcodec)
		echo -e "$(get_ffmpeg_libavcodec_version)"
		;;
	libavdevice)
		echo -e "$(get_ffmpeg_libavdevice_version)"
		;;
	libavfilter)
		echo -e "$(get_ffmpeg_libavfilter_version)"
		;;
	libavformat)
		echo -e "$(get_ffmpeg_libavformat_version)"
		;;
	libavutil)
		echo -e "$(get_ffmpeg_libavutil_version)"
		;;
	libswresample)
		echo -e "$(get_ffmpeg_libswresample_version)"
		;;
	libswscale)
		echo -e "$(get_ffmpeg_libswscale_version)"
		;;
	esac
}

#
# 1. LIBRARY NAME
#
get_ffmpeg_library_major_version() {
	case $1 in
	libavcodec)
		echo -e "$(get_ffmpeg_libavcodec_major_version)"
		;;
	libavdevice)
		echo -e "$(get_ffmpeg_libavdevice_major_version)"
		;;
	libavfilter)
		echo -e "$(get_ffmpeg_libavfilter_major_version)"
		;;
	libavformat)
		echo -e "$(get_ffmpeg_libavformat_major_version)"
		;;
	libavutil)
		echo -e "$(get_ffmpeg_libavutil_major_version)"
		;;
	libswresample)
		echo -e "$(get_ffmpeg_libswresample_major_version)"
		;;
	libswscale)
		echo -e "$(get_ffmpeg_libswscale_major_version)"
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
	if [ "$FFMPEG_KIT_BUILD_TYPE" == "android" ]; then
		echo -e "  --enable-custom-library-[n]-uses-cpp\t\t\t\tflag to specify that the library uses libc++ []\n"
	else
		echo -e ""
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
	local RECONF_VARIABLE=$(echo -e "RECONF_$1" | sed "s/\-/\_/g")
	local library_supported=0

	for library in {0..49}; do
		library_name=$(get_library_name "$library")
		local library_supported_on_platform=$(is_library_supported_on_platform "${library_name}")

		if [[ $1 != "ffmpeg" ]] && [[ ${library_name} == "$1" ]] && [[ ${library_supported_on_platform} -eq 0 ]]; then
			export "$RECONF_VARIABLE"=1
			RECONF_LIBRARIES+=("$1")
			library_supported=1
		fi
	done

	if [[ ${library_supported} -ne 1 ]]; then
		export "$RECONF_VARIABLE"=1
		RECONF_LIBRARIES+=("$1")
		echo -e "INFO: --reconf flag detected for custom library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
	else
		echo -e "INFO: --reconf flag detected for library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
	fi
}

#
# 1. <library name>
#
rebuild_library() {
	local REBUILD_VARIABLE=$(echo -e "REBUILD_$1" | sed "s/\-/\_/g")
	local library_supported=0

	for library in {0..49}; do
		library_name=$(get_library_name "$library")
		local library_supported_on_platform=$(is_library_supported_on_platform "${library_name}")

		if [[ $1 != "ffmpeg" ]] && [[ ${library_name} == "$1" ]] && [[ ${library_supported_on_platform} -eq 0 ]]; then
			export "$REBUILD_VARIABLE"=1
			REBUILD_LIBRARIES+=("$1")
			library_supported=1
		fi
	done

	if [[ ${library_supported} -ne 1 ]]; then
		export "$REBUILD_VARIABLE"=1
		REBUILD_LIBRARIES+=("$1")
		echo -e "INFO: --rebuild flag detected for custom library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
	else
		echo -e "INFO: --rebuild flag detected for library $1.\n" 1>>"${BASEDIR}"/build.log 2>&1
	fi
}

#
# 1. <library name>
#
redownload_library() {
	local REDOWNLOAD_VARIABLE=$(echo -e "REDOWNLOAD_$1" | sed "s/\-/\_/g")
	local library_supported=0

	for library in {0..49}; do
		library_name=$(get_library_name "$library")
		local library_supported_on_platform=$(is_library_supported_on_platform "${library_name}")

		if [[ ${library_name} == "$1" ]] && [[ ${library_supported_on_platform} -eq 0 ]]; then
			export "$REDOWNLOAD_VARIABLE"=1
			REDOWNLOAD_LIBRARIES+=("$1")
			library_supported=1
		fi
	done

	if [[ "ffmpeg" == "$1" ]]; then
		export "$REDOWNLOAD_VARIABLE"=1
		REDOWNLOAD_LIBRARIES+=("$1")
		library_supported=1
	fi

	if [[ ${library_supported} -ne 1 ]]; then
		export "$REDOWNLOAD_VARIABLE"=1
		REDOWNLOAD_LIBRARIES+=("$1")
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
		set_virtual_library "libiconv" "$2"
		set_virtual_library "libuuid" "$2"
		set_library "freetype" "$2"
		;;
	freetype)
		ENABLED_LIBRARIES[LIBRARY_FREETYPE]="$2"
		set_virtual_library "zlib" "$2"
		set_library "libpng" "$2"
		;;
	fribidi)
		ENABLED_LIBRARIES[LIBRARY_FRIBIDI]=$2
		;;
	gmp)
		ENABLED_LIBRARIES[LIBRARY_GMP]=$2
		;;
	gnutls)
		ENABLED_LIBRARIES[LIBRARY_GNUTLS]=$2
		set_virtual_library "zlib" "$2"
		set_library "nettle" "$2"
		set_library "gmp" "$2"
		set_virtual_library "libiconv" "$2"
		;;
	harfbuzz)
		ENABLED_LIBRARIES[LIBRARY_HARFBUZZ]=$2
		set_library "freetype" "$2"
		;;
	kvazaar)
		ENABLED_LIBRARIES[LIBRARY_KVAZAAR]=$2
		;;
	lame)
		ENABLED_LIBRARIES[LIBRARY_LAME]=$2
		set_virtual_library "libiconv" "$2"
		;;
	libaom)
		ENABLED_LIBRARIES[LIBRARY_LIBAOM]=$2
		;;
	libass)
		ENABLED_LIBRARIES[LIBRARY_LIBASS]=$2
		ENABLED_LIBRARIES[LIBRARY_EXPAT]=$2
		set_virtual_library "libuuid" "$2"
		set_library "freetype" "$2"
		set_library "fribidi" "$2"
		set_library "fontconfig" "$2"
		set_library "harfbuzz" "$2"
		set_virtual_library "libiconv" "$2"
		;;
	libiconv)
		ENABLED_LIBRARIES[LIBRARY_LIBICONV]=$2
		;;
	libilbc)
		ENABLED_LIBRARIES[LIBRARY_LIBILBC]=$2
		;;
	libpng)
		ENABLED_LIBRARIES[LIBRARY_LIBPNG]=$2
		set_virtual_library "zlib" "$2"
		;;
	libtheora)
		ENABLED_LIBRARIES[LIBRARY_LIBTHEORA]=$2
		ENABLED_LIBRARIES[LIBRARY_LIBOGG]=$2
		set_library "libvorbis" "$2"
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
		set_library "tiff" "$2"
		set_library "libpng" "$2"
		;;
	libxml2)
		ENABLED_LIBRARIES[LIBRARY_LIBXML2]=$2
		set_virtual_library "libiconv" "$2"
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
		set_virtual_library "zlib" "$2"
		;;
	soxr)
		ENABLED_LIBRARIES[LIBRARY_SOXR]=$2
		;;
	speex)
		ENABLED_LIBRARIES[LIBRARY_SPEEX]=$2
		;;
	srt)
		ENABLED_LIBRARIES[LIBRARY_SRT]=$2
		set_library "openssl" "$2"
		;;
	tesseract)
		ENABLED_LIBRARIES[LIBRARY_TESSERACT]=$2
		ENABLED_LIBRARIES[LIBRARY_LEPTONICA]=$2
		ENABLED_LIBRARIES[LIBRARY_LIBWEBP]=$2
		ENABLED_LIBRARIES[LIBRARY_GIFLIB]=$2
		ENABLED_LIBRARIES[LIBRARY_JPEG]=$2
		set_virtual_library "zlib" "$2"
		set_library "tiff" "$2"
		set_library "libpng" "$2"
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
		set_library "gmp" "$2"
		;;
	tiff)
		ENABLED_LIBRARIES[LIBRARY_TIFF]=$2
		ENABLED_LIBRARIES[LIBRARY_JPEG]=$2
		;;
	linux-fontconfig)
		ENABLED_LIBRARIES[LIBRARY_LINUX_FONTCONFIG]=$2
		set_library "linux-libiconv" "$2"
		set_library "linux-freetype" "$2"
		;;
	linux-freetype)
		ENABLED_LIBRARIES[LIBRARY_LINUX_FREETYPE]=$2
		set_virtual_library "zlib" "$2"
		;;
	linux-fribidi)
		ENABLED_LIBRARIES[LIBRARY_LINUX_FRIBIDI]=$2
		;;
	linux-gmp)
		ENABLED_LIBRARIES[LIBRARY_LINUX_GMP]=$2
		;;
	linux-gnutls)
		ENABLED_LIBRARIES[LIBRARY_LINUX_GNUTLS]=$2
		set_virtual_library "zlib" "$2"
		set_library "linux-gmp" "$2"
		set_library "linux-libiconv" "$2"
		;;
	linux-lame)
		ENABLED_LIBRARIES[LIBRARY_LINUX_LAME]=$2
		set_library "linux-libiconv" "$2"
		;;
	linux-libass)
		ENABLED_LIBRARIES[LIBRARY_LINUX_LIBASS]=$2
		set_library "linux-freetype" "$2"
		set_library "linux-fribidi" "$2"
		set_library "linux-fontconfig" "$2"
		set_library "linux-libiconv" "$2"
		;;
	linux-libiconv)
		ENABLED_LIBRARIES[LIBRARY_LINUX_LIBICONV]=$2
		;;
	linux-libtheora)
		ENABLED_LIBRARIES[LIBRARY_LINUX_LIBTHEORA]=$2
		set_library "linux-libvorbis" "$2"
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
		set_virtual_library "zlib" "$2"
		;;
	linux-libxml2)
		ENABLED_LIBRARIES[LIBRARY_LINUX_LIBXML2]=$2
		set_library "linux-libiconv" "$2"
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
		set_virtual_library "zlib" "$2"
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
		set_virtual_library "zlib" "$2"
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
		print_unknown_library "$1"
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
		print_unknown_virtual_library "$1"
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
	DEPENDENCY_REBUILT_VARIABLE=$(echo -e "DEPENDENCY_REBUILT_$1" | sed "s/\-/\_/g")
	export "${DEPENDENCY_REBUILT_VARIABLE}"=1
}

print_enabled_architectures() {
	echo -e -n "Architectures: "

	enabled=0
	for print_arch in {0..12}; do
		if [[ ${ENABLED_ARCHITECTURES[$print_arch]} -eq 1 ]]; then
			if [[ ${enabled} -ge 1 ]]; then
				echo -e -n ", "
			fi
			echo -e -n "$(get_arch_name "${print_arch}")"
			enabled=$(( enabled + 1 ))
		fi
	done

	if [ ${enabled} -gt 0 ]; then
		echo -e ""
	else
		echo -e "none"
	fi
}

print_enabled_architecture_variants() {
	echo -e -n "Architecture variants: "

	enabled=0
	for print_arch_var in {1..8}; do
		if [[ ${ENABLED_ARCHITECTURE_VARIANTS[$print_arch_var]} -eq 1 ]]; then
			if [[ ${enabled} -ge 1 ]]; then
				echo -e -n ", "
			fi
			echo -e -n "$(get_apple_architecture_variant "${print_arch_var}")"
			enabled=$(( enabled + 1 ))
		fi
	done

	if [ ${enabled} -gt 0 ]; then
		echo -e ""
	else
		echo -e "none"
	fi
}

print_enabled_libraries() {
	echo -e -n "Libraries: "

	enabled=0

	# SUPPLEMENTARY LIBRARIES NOT PRINTED
	for library in {50..57} {59..91} {0..36}; do
		if [[ ${ENABLED_LIBRARIES[$library]} -eq 1 ]]; then
			if [[ ${enabled} -ge 1 ]]; then
				echo -e -n ", "
			fi
			echo -e -n "$(get_library_name "${library}")"
			enabled=$(( enabled + 1 ))
		fi
	done

	if [ ${enabled} -gt 0 ]; then
		echo -e ""
	else
		echo -e "none"
	fi
}

print_enabled_xcframeworks() {
	echo -e -n "xcframeworks: "

	enabled=0

	# SUPPLEMENTARY LIBRARIES NOT PRINTED
	for library in {0..49}; do
		if [[ ${ENABLED_LIBRARIES[$library]} -eq 1 ]]; then
			if [[ ${enabled} -ge 1 ]]; then
				echo -e -n ", "
			fi
			echo -e -n "$(get_library_name "${library}")"
			enabled=$(( enabled + 1 ))
		fi
	done

	if [[ ${enabled} -ge 1 ]]; then
		echo -e -n ", "
	fi

	for FFMPEG_LIB in "${FFMPEG_LIBS[@]}"; do
		echo -e -n "${FFMPEG_LIB}, "
	done

	echo -e "ffmpeg-kit"
}

print_reconfigure_requested_libraries() {
	local counter=0

	for RECONF_LIBRARY in "${RECONF_LIBRARIES[@]}"; do
		if [[ ${counter} -eq 0 ]]; then
			echo -e -n "Reconfigure: "
		else
			echo -e -n ", "
		fi

		echo -e -n "${RECONF_LIBRARY}"

		counter=$(( counter + 1 ))
	done

	if [[ ${counter} -gt 0 ]]; then
		echo -e ""
	fi
}

print_rebuild_requested_libraries() {
	local counter=0

	for REBUILD_LIBRARY in "${REBUILD_LIBRARIES[@]}"; do
		if [[ ${counter} -eq 0 ]]; then
			echo -e -n "Rebuild: "
		else
			echo -e -n ", "
		fi

		echo -e -n "${REBUILD_LIBRARY}"

		counter=$(( counter + 1 ))
	done

	if [[ ${counter} -gt 0 ]]; then
		echo -e ""
	fi
}

print_redownload_requested_libraries() {
	local counter=0

	for REDOWNLOAD_LIBRARY in "${REDOWNLOAD_LIBRARIES[@]}"; do
		if [[ ${counter} -eq 0 ]]; then
			echo -e -n "Redownload: "
		else
			echo -e -n ", "
		fi

		echo -e -n "${REDOWNLOAD_LIBRARY}"

		counter=$(( counter + 1 ))
	done

	if [[ ${counter} -gt 0 ]]; then
		echo -e ""
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
			echo -e -n "Custom libraries: "
		else
			echo -e -n ", "
		fi

		echo -e -n "${!LIBRARY_NAME}"

		echo -e "INFO: Custom library options found for ${!LIBRARY_NAME}\n" 1>>"${BASEDIR}"/build.log 2>&1

		counter=$(( counter + 1 ))
	done

	if [[ ${counter} -gt 0 ]]; then
		echo -e "INFO: ${counter} valid custom library definitions found\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e ""
	fi
}

# 1 - library index
get_external_library_license_path() {
	case $1 in
	1) echo -e "${BASEDIR}/src/$(get_library_name "$1")/LICENSE.TXT" ;;
	12) echo -e "${BASEDIR}/src/$(get_library_name "$1")/Copyright" ;;
	35) echo -e "${BASEDIR}/src/$(get_library_name "$1")/LICENSE.txt" ;;
	3 | 42) echo -e "${BASEDIR}/src/$(get_library_name "$1")/COPYING.LESSERv3" ;;
	5 | 44) echo -e "${BASEDIR}/src/$(get_library_name "$1")/$(get_library_name "$1")/COPYING" ;;
	19) echo -e "${BASEDIR}/src/$(get_library_name "$1")/$(get_library_name "$1")/LICENSE" ;;
	26) echo -e "${BASEDIR}/src/$(get_library_name "$1")/COPYING.LGPL" ;;
	28 | 38) echo -e "${BASEDIR}/src/$(get_library_name "$1")/LICENSE.md " ;;
	30) echo -e "${BASEDIR}/src/$(get_library_name "$1")/COPYING.txt" ;;
	43) echo -e "${BASEDIR}/src/$(get_library_name "$1")/COPYRIGHT" ;;
	46) echo -e "${BASEDIR}/src/$(get_library_name "$1")/leptonica-license.txt" ;;
	4 | 10 | 13 | 17 | 21 | 27 | 31 | 32 | 36 | 40 | 49) echo -e "${BASEDIR}/src/$(get_library_name "$1")/LICENSE" ;;
	*) echo -e "${BASEDIR}/src/$(get_library_name "$1")/COPYING" ;;
	esac
}

# 1 - library index
# 2 - license path
copy_external_library_license() {
	license_path_array=("$2")
	for license_path in "${license_path_array[@]}"; do
		RESULT=$(copy_external_library_license_file "$1" "${license_path}")
		if [[ ${RESULT} -ne 0 ]]; then
			echo -e 1
			return
		fi
	done
	echo -e 0
}

# 1 - library index
# 2 - output path
copy_external_library_license_file() {
	if cp "$(get_external_library_license_path "$1")" "$2" 1>>"${BASEDIR}"/build.log 2>&1; then
		echo 0
	else
		echo 1
		return 1
	fi
}

get_cmake_build_directory() {
	echo -e "${FFMPEG_KIT_TMPDIR}/cmake/build/$(get_build_directory)/${LIB_NAME}"
}

get_apple_cmake_system_name() {
	case ${FFMPEG_KIT_BUILD_TYPE} in
	macos)
		echo -e "Darwin"
		;;
	tvos)
		echo -e "tvOS"
		;;
	*)
		case ${ARCH} in
		*-mac-catalyst)
			echo -e "Darwin"
			;;
		*)
			echo -e "iOS"
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
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# FORCE INSTALL
	(autoreconf -fiv)

	local EXTRACT_RC=$?
	if [ ${EXTRACT_RC} -eq 0 ]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
		return
	fi

	echo -e "\nDEBUG: Full autoreconf failed. Running full autoreconf with include for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# FORCE INSTALL WITH m4
	(autoreconf -fiv -I m4)

	EXTRACT_RC=$?
	if [ ${EXTRACT_RC} -eq 0 ]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
		return
	fi

	echo -e "\nDEBUG: Full autoreconf with include failed. Running autoreconf without force for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# INSTALL WITHOUT FORCE
	(autoreconf -iv)

	EXTRACT_RC=$?
	if [ ${EXTRACT_RC} -eq 0 ]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
		return
	fi

	echo -e "\nDEBUG: Autoreconf without force failed. Running autoreconf without force with include for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# INSTALL WITHOUT FORCE WITH m4
	(autoreconf --iv -I m4)

	EXTRACT_RC=$?
	if [ ${EXTRACT_RC} -eq 0 ]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
		return
	fi

	echo -e "\nDEBUG: Autoreconf without force with include failed. Running default autoreconf for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# INSTALL DEFAULT
	(autoreconf)

	EXTRACT_RC=$?
	if [ ${EXTRACT_RC} -eq 0 ]; then
		echo -e "\nDEBUG: autoreconf completed successfully for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
		return
	fi

	echo -e "\nDEBUG: Default autoreconf failed. Running default autoreconf with include for $1\n" 1>>"${BASEDIR}"/build.log 2>&1
	#rm -rf aclocal.m4 autom4te.cache configure Makefile.in src/Makefile.in m4
	# INSTALL DEFAULT WITH m4
	(autoreconf -v -I m4)

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

	if ! mkdir -p "$2" 1>>"${BASEDIR}"/build.log 2>&1; then
		echo -e "\nINFO: Failed to create local directory $2\n" 1>>"${BASEDIR}"/build.log 2>&1
		remove_path -rf "$2" 1>>"${BASEDIR}"/build.log 2>&1
		echo 1
		return 1
	fi

	echo -e "INFO: Cloning commit id $3 from repository $1 into local directory $2\n" 1>>"${BASEDIR}"/build.log 2>&1

	if ! git clone "$1" "$2" --depth 1 1>>"${BASEDIR}"/build.log 2>&1; then
		echo -e "\nINFO: Failed to clone $1\n" 1>>"${BASEDIR}"/build.log 2>&1
		remove_path -rf "$2" 1>>"${BASEDIR}"/build.log 2>&1
		echo 1
		return 1
	fi

	if ! cd "$2" 1>>"${BASEDIR}"/build.log 2>&1; then
		echo -e "\nINFO: Failed to cd into $2\n" 1>>"${BASEDIR}"/build.log 2>&1
		remove_path -rf "$2" 1>>"${BASEDIR}"/build.log 2>&1
		echo 1
		return 1
	fi

	if ! git fetch --depth 1 origin "$3" 1>>"${BASEDIR}"/build.log 2>&1; then
		echo -e "\nINFO: Failed to fetch commit id $3 from $1\n" 1>>"${BASEDIR}"/build.log 2>&1
		remove_path -rf "$2" 1>>"${BASEDIR}"/build.log 2>&1
		echo 1
		return 1
	fi

	if ! git checkout "$3" 1>>"${BASEDIR}"/build.log 2>&1; then
		echo -e "\nINFO: Failed to checkout commit id $3 from $1\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo 1
		return 1
	fi

	echo 0
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
		echo -e ${RC}
		return
	fi

	echo -e "INFO: Cloning tag $2 from repository $1 into local directory $3\n" 1>>"${BASEDIR}"/build.log 2>&1

	(git clone --depth 1 --branch "$2" "$1" "$3" 1>>"${BASEDIR}"/build.log 2>&1)

	RC=$?

	if [ ${RC} -ne 0 ]; then
		echo -e "\nINFO: Failed to clone $1 -> $2\n" 1>>"${BASEDIR}"/build.log 2>&1
		rm -rf "$3" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e ${RC}
		return
	fi

	echo -e ${RC}
}

#
# 1. library index
#
is_gpl_licensed() {
	for gpl_library in {$LIBRARY_X264,$LIBRARY_XVIDCORE,$LIBRARY_X265,$LIBRARY_LIBVIDSTAB,$LIBRARY_RUBBERBAND,$LIBRARY_LINUX_XVIDCORE,$LIBRARY_LINUX_X265,$LIBRARY_LINUX_LIBVIDSTAB,$LIBRARY_LINUX_RUBBERBAND}; do
		if [[ $gpl_library -eq $1 ]]; then
			echo -e 0
			return
		fi
	done

	echo -e 1
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

	echo -e ${RC}
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

	if [ "$LIBRARY_RC" -eq 0 ]; then
		echo -e "INFO: $1 already downloaded. Source folder found at ${LIB_LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 0
		return
	fi

	# Handle different source types
	case "${SOURCE_TYPE}" in
	"TAG" | "BRANCH" | "COMMIT")
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

	if [ "$DOWNLOAD_RC" -ne 0 ]; then
		echo -e "INFO: Downloading library $1 failed. Can not get library from ${SOURCE_REPO_URL}\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e "$DOWNLOAD_RC"
	else
		echo -e "\nINFO: $1 library downloaded" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 0
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
		echo -e ${CURL_RC}
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
	*.tar.gz | *.tgz)
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
		echo -e ${EXTRACT_RC}
		return
	fi

	echo -e "DEBUG: Successfully downloaded and extracted ${LIB_NAME}\n" 1>>"${BASEDIR}"/build.log 2>&1
	echo -e 0
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

	if [ "$LIBRARY_RC" -eq 0 ]; then
		echo -e "INFO: ${LIB_NAME} already downloaded. Source folder found at ${LIB_LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 0
		return
	fi

	if [ "${SOURCE_TYPE}" == "TAG" ]; then
		DOWNLOAD_RC=$(clone_git_repository_with_tag "${SOURCE_REPO_URL}" "${SOURCE_ID}" "${LIB_LOCAL_PATH}")
	else
		DOWNLOAD_RC=$(clone_git_repository_with_commit_id "${SOURCE_REPO_URL}" "${LIB_LOCAL_PATH}" "${SOURCE_ID}")
	fi

	if [ "$DOWNLOAD_RC" -ne 0 ]; then
		echo -e "INFO: Downloading custom library ${LIB_NAME} failed. Can not get library from ${SOURCE_REPO_URL}\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e "$DOWNLOAD_RC"
	else
		echo -e "\nINFO: ${LIB_NAME} custom library downloaded" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 0
	fi
}

download_gnu_config() {
	local SOURCE_REPO_URL=""
	local LIB_NAME="config"
	local LIB_LOCAL_PATH="${FFMPEG_KIT_TMPDIR}/source/${LIB_NAME}"
	local SOURCE_ID=""
	local DOWNLOAD_RC=""
	local SOURCE_TYPE=""
	REDOWNLOAD_VARIABLE=$(echo -e "REDOWNLOAD_$LIB_NAME")

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
	echo -e "$(grep -c aarch64-apple-darwin config.guess 2>>"$BASEDIR"/build.log)"
}

get_cpu_count() {
	echo -e "$cpu_count"
}

#
# 1. <lib name>
#
library_is_downloaded() {
	local LOCAL_PATH
	local LIB_NAME=$1
	local REDOWNLOAD_VARIABLE
	REDOWNLOAD_VARIABLE=$(echo -e "REDOWNLOAD_$1" | sed "s/\-/\_/g")

	LOCAL_PATH=${BASEDIR}/prebuilt/src/${LIB_NAME}

	echo -e "DEBUG: Checking if ${LIB_NAME} is already downloaded at ${LOCAL_PATH}\n" 1>>"${BASEDIR}"/build.log 2>&1

	if [ ! -d "${LOCAL_PATH}" ]; then
		echo -e "INFO: ${LOCAL_PATH} directory not found\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 1
		return
	fi

	files=("${LOCAL_PATH}"/*)

	if [[ ${#files[@]} -eq 1 && ! -e "${files[0]}" ]]; then
		echo -e "INFO: No files found under ${LOCAL_PATH}\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 1
		return
	fi

	if [[ ${REDOWNLOAD_VARIABLE} -eq 1 ]]; then
		echo -e "INFO: ${LIB_NAME} library already downloaded but re-download requested\n" 1>>"${BASEDIR}"/build.log 2>&1
		remove_path -rf "${LOCAL_PATH}" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 1
	else
		echo -e "INFO: ${LIB_NAME} library already downloaded\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 0
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
		echo -e 0
		return
	fi

	if [ ! -d "${INSTALL_PATH}/${LIB_NAME}/lib" ] && [ ! -d "${INSTALL_PATH}/${LIB_NAME}/lib64" ]; then
		echo -e "INFO: ${INSTALL_PATH}/${LIB_NAME}/lib{lib64} directory not found\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 0
		return
	fi

	if [ ! -d "${INSTALL_PATH}"/"${LIB_NAME}"/include ]; then
		echo -e "INFO: ${INSTALL_PATH}/${LIB_NAME}/include directory not found\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 0
		return
	fi

	HEADER_COUNT=("${INSTALL_PATH}"/"${LIB_NAME}"/include/*)
	LIB_COUNT=("${INSTALL_PATH}"/"${LIB_NAME}"/lib/*)

	if [[ ${#HEADER_COUNT[@]} -eq 1 && ! -e "${HEADER_COUNT[0]}" ]]; then
		echo -e "INFO: No headers found under ${INSTALL_PATH}/${LIB_NAME}/include\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 0
		return
	fi
	if [[ ${#LIB_COUNT[@]} -eq 1 && ! -e "${LIB_COUNT[0]}" ]]; then
		echo -e "INFO: No libraries found under ${INSTALL_PATH}/${LIB_NAME}/lib{lib64}\n" 1>>"${BASEDIR}"/build.log 2>&1
		echo -e 0
		return
	fi

	echo -e "INFO: ${LIB_NAME} library is already built and installed\n" 1>>"${BASEDIR}"/build.log 2>&1
	echo -e 1
}

prepare_inline_sed() {
	export SED_INLINE="sed -i"
}

to_capital_case() {
	echo "$(echo "${1:0:1}" | tr '[:lower:]' '[:upper:]')${1:1}"
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
	echo -e "" >"$1" 1>>"${BASEDIR}"/build.log 2>&1
}

compare_versions() {
	VERSION_PARTS_1=("$(echo "$1" | tr "." " ")")
	VERSION_PARTS_2=("$(echo "$2" | tr "." " ")")

	for ((i = 0; (i < ${#VERSION_PARTS_1[@]}) && (i < ${#VERSION_PARTS_2[@]}); i++)); do

		local CURRENT_PART_1=${VERSION_PARTS_1[$i]}
		local CURRENT_PART_2=${VERSION_PARTS_2[$i]}

		if [[ -z ${CURRENT_PART_1} ]]; then
			CURRENT_PART_1=0
		fi

		if [[ -z ${CURRENT_PART_2} ]]; then
			CURRENT_PART_2=0
		fi

		if [[ CURRENT_PART_1 -gt CURRENT_PART_2 ]]; then
			echo -e "1"
			return
		elif [[ CURRENT_PART_1 -lt CURRENT_PART_2 ]]; then
			echo -e "-1"
			return
		fi
	done

	echo -e "0"
	return
}

#
# 1. command
#
command_exists() {
	local COMMAND=$1
	if [[ -n "$(command -v "$COMMAND")" ]]; then
		echo -e 0
	else
		echo -e 1
	fi
}

#
# 1. folder path
#
initialize_folder() {
	if ! remove_path -rf "$1" 1>>"${BASEDIR}"/build.log 2>&1; then
		return 1
	fi

	if ! create_dir "$1" 1>>"${BASEDIR}"/build.log 2>&1; then
		return 1
	fi
}

require_sudo() {
	if [ "$EUID" -ne 0 ]; then
		echo "This script must be run with sudo"
		echo "Usage: sudo $0 [OPTIONS]"
		exit 1
	fi

	if [ -z "$SUDO_USER" ]; then
		echo "Warning: Running as root directly (not via sudo)"
	else
		echo "Running with sudo privileges (user: $SUDO_USER)"
	fi
}

is_integer() {
    local str="$1"
    if [[ "$str" =~ ^[-+]?[0-9]+$ ]]; then
        echo "0" # Is integer
    else
        echo "1" # Not integer
    fi
}

is_alpha() {
	local str="$1"
	if [[ "$str" =~ ^[a-zA-Z]+$ ]]; then
		echo "0" # Is integer
	else
		echo "1" # Not integer
	fi
}

array_index_of() {
	local search_string="$1"
	shift
	local array=("$@")

	for i in "${!array[@]}"; do
		if [[ "${array[i]}" == *"$search_string" ]]; then
			echo "$i" # Return the index
			return 0
		fi
	done
	echo -e "DEBUG: $search_string could not be found in build steps.\n $(print_build_steps)" | tee -a "$LOG_FILE"
	exit 1 # Not found
	return 1
}

#===============================================================================================
#                                           WINDOWS
#===============================================================================================

get_build_type() {
	if [[ ${build_ffmpeg_static,,} =~ ^(y|yes|1|true|on)$ ]]; then
		echo "static"
	else
		echo "shared"
	fi
}

set_box_memory_size_bytes() {
	local ram_kilobytes=$(grep MemTotal /proc/meminfo | awk '{print $2}')
	local swap_kilobytes=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
	box_memory_size_bytes=$((ram_kilobytes * 1024 + swap_kilobytes * 1024))
}

function sortable_version { echo -e "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

at_least_required_version() { # params: required actual
	local sortable_required=$(sortable_version "$1")
	sortable_required=$(echo -e "$sortable_required" | sed 's/^0*//') # remove preceding zeroes, which bash later interprets as octal or screwy
	local sortable_actual=$(sortable_version "$2")
	sortable_actual=$(echo -e "$sortable_actual" | sed 's/^0*//')
	[[ "$sortable_actual" -ge "$sortable_required" ]]
}

apt_not_installed() {
	for x in "$@"; do
		if ! dpkg -l "$x" | grep -q '^.i'; then
			need_install="$need_install $x"
		fi
	done
	echo -e "$need_install"
}

check_missing_packages() {
	# We will need this later if we don't want to just constantly be grepping the /etc/os-release file
	if [ -z "${VENDOR}" ] && grep -E '(centos|rhel)' /etc/os-release &>/dev/null; then
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
	check_packages+=('libtoolize') # the rest of the world
	# Use hash to check if the packages exist or not. Type is a bash builtin which I'm told behaves differently between different versions of bash.
	for package in "${check_packages[@]}"; do
		hash "$package" &>/dev/null || missing_packages=("$package" "${missing_packages[@]}")
	done
	if [ "${VENDOR}" = "redhat" ] || [ "${VENDOR}" = "centos" ]; then
		if [ -n "$(hash cmake 2>&1)" ] && [ -n "$(hash cmake3 2>&1)" ]; then missing_packages=('cmake' "${missing_packages[@]}"); fi
	fi

	if [[ ${#missing_packages[@]} -gt 0 ]]; then
		clear
		echo -e "Could not find the following execs (svn is actually package subversion, makeinfo is actually package texinfo if you're missing them): ${missing_packages[*]}"
		echo -e 'Install the missing packages before running this script.'
		determine_distro

		apt_pkgs='subversion ragel curl texinfo g++ ed bison flex cvs yasm automake libtool autoconf gcc cmake git make pkg-config zlib1g-dev unzip pax nasm gperf autogen bzip2 autoconf-archive p7zip-full clang wget bc tesseract-ocr-eng autopoint python3-full'

		[[ $DISTRO == "debian" ]] && apt_pkgs="$apt_pkgs libtool-bin ed" # extra for debian
		case "$DISTRO" in
		Ubuntu)
			echo -e "for ubuntu:"
			echo -e "$ sudo apt-get update"
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
			echo -e "$ sudo apt-get install $apt_pkgs -y"
			if uname -a | grep -q -- "-microsoft"; then
				echo -e "NB if you use WSL Ubuntu 20.04 you need to do an extra step: https://github.com/rdp/ffmpeg-windows-build-helpers/issues/452"
			fi
			;;
		debian)
			echo -e "for debian:"
			echo -e "$ sudo apt-get update"
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
			echo -e "$ sudo apt-get install $apt_missing -y"
			;;
		*)
			echo -e "for OS X (homebrew): brew install ragel wget cvs yasm autogen automake autoconf cmake libtool xz pkg-config nasm bzip2 autoconf-archive p7zip coreutils llvm" # if edit this edit docker/Dockerfile also :|
			echo -e "   and set llvm to your PATH if on catalina"
			echo -e "for RHEL/CentOS: First ensure you have epel repo available, then run $ sudo yum install ragel subversion texinfo libtool autogen gperf nasm patch unzip pax ed gcc-c++ bison flex yasm automake autoconf gcc zlib-devel cvs bzip2 cmake3 -y"
			echo -e "for fedora: if your distribution comes with a modern version of cmake then use the same as RHEL/CentOS but replace cmake3 with cmake."
			echo -e "for linux native compiler option: same as <your OS> above, also add libva-dev"
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
		if hash $cmake_binary &>/dev/null; then
			cmake_version="$("${cmake_binary}" --version | sed -e "s#${cmake_binary}##g" | head -n 1 | tr -cd '0-9.\n')"
			if at_least_required_version "${REQUIRED_CMAKE_VERSION}" "${cmake_version}"; then
				export cmake_command="${cmake_binary}"
				break
			else
				echo -e "your ${cmake_binary} version is too old ${cmake_version} wanted ${REQUIRED_CMAKE_VERSION}"
			fi
		fi
	done

	# If cmake_command never got assigned then there where no versions found which where sufficient.
	if [ -z "${cmake_command}" ]; then
		echo -e "there where no appropriate versions of cmake found on your machine."
		exit 1
	else
		# If cmake_command is set then either one of the cmake's is adequate.
		if [[ $cmake_command != "cmake" ]]; then # don't echo -e if it's the normal default
			echo -e "cmake binary for this build will be ${cmake_command}"
		fi
	fi

	if [[ ! -f /usr/include/zlib.h ]]; then
		echo -e "warning: you may need to install zlib development headers first if you want to build mp4-box [on ubuntu: $ apt-get install zlib1g-dev] [on redhat/fedora distros: $ yum install zlib-devel]" # XXX do like configure does and attempt to compile and include zlib.h instead?
		sleep 1
	fi

	# TODO nasm version :|

	# doing the cut thing with an assigned variable dies on the version of yasm I have installed (which I'm pretty sure is the RHEL default)
	# because of all the trailing lines of stuff
	export REQUIRED_YASM_VERSION="1.2.0" # export ???
	local yasm_binary=yasm
	local yasm_version="$("${yasm_binary}" --version | sed -e "s#${yasm_binary}##g" | head -n 1 | tr -dc '0-9.\n')"
	if ! at_least_required_version "${REQUIRED_YASM_VERSION}" "${yasm_version}"; then
		echo -e "your yasm version is too old $yasm_version wanted ${REQUIRED_YASM_VERSION}"
		exit 1
	fi
	# local meson_version=`meson --version`
	# if ! at_least_required_version "0.60.0" "${meson_version}"; then
	# echo -e "your meson version is too old $meson_version wanted 0.60.0"
	# exit 1
	# fi
	# also check missing "setup" so it's early LOL

	#check if WSL
	# check WSL for interop setting make sure its disabled
	# check WSL for kernel version look for version 4.19.128 current as of 11/01/2020
	if uname -a | grep -iq -- "-microsoft"; then
		# shellcheck disable=SC2002
		if cat /proc/sys/fs/binfmt_misc/WSLInterop | grep -q enabled; then
			echo -e "windows WSL detected: you must first disable 'binfmt' by running this
      sudo bash -c 'echo -e 0 > /proc/sys/fs/binfmt_misc/WSLInterop'
      then try again"
			#exit 1
		fi
		export MINIMUM_KERNEL_VERSION="4.19.128"
		KERNVER=$(uname -a | awk -F'[ ]' '{ print $3 }' | awk -F- '{ print $1 }')

		function version { # for version comparison @ stackoverflow.com/a/37939589
			echo -e "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
		}

		if [ "$(version "$KERNVER")" -lt "$(version "$MINIMUM_KERNEL_VERSION")" ]; then
			echo -e "Windows Subsystem for Linux (WSL) detected - kernel not at minumum version required: $MINIMUM_KERNEL_VERSION
      Please update via windows update then try again"
			#exit 1
		fi
		echo -e "for WSL ubuntu 20.04 you need to do an extra step https://github.com/rdp/ffmpeg-windows-build-helpers/issues/452"
	fi

}

determine_distro() {

	# Determine OS platform from https://askubuntu.com/a/459425/20972
	UNAME=$(uname | tr "[:upper:]" "[:lower:]")
	# If Linux, try to determine specific distribution
	if [ "$UNAME" == "linux" ]; then
		# If available, use LSB to identify distribution
		if [ -f /etc/lsb-release ] || [ -d /etc/lsb-release.d ]; then
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
	cp "$WINPATCHDIR"/"$zeranoe_script_name" "$WINPATCHDIR"/"$zeranoe_script_name".bak
	cp "$WINPATCHDIR"/"$zeranoe_script_name" "$zeranoe_script_name"
	#rm -f $WINPATCHDIR/$zeranoe_script_name || exit 1
	#curl -4 https://raw.githubusercontent.com/Zeranoe/mingw-w64-build/refs/heads/master/mingw-w64-build -O --fail || exit 1
	chmod u+x "$zeranoe_script_name"
}

# helper methods for downloading and building projects that can take generic input

do_svn_checkout() {
	repo_url="$1"
	to_dir="$2"
	desired_revision="$3"
	if [ ! -d "$to_dir" ]; then
		echo -e "INFO: svn checking out to $to_dir"
		if [[ -z "$desired_revision" ]]; then
			svn checkout "$repo_url" "$to_dir".tmp --non-interactive --trust-server-cert || exit 1
		else
			svn checkout -r "$desired_revision" "$repo_url" "$to_dir".tmp || exit 1
		fi
		mv "$to_dir".tmp "$to_dir"
	else
		change_dir "$to_dir"
		echo -e "INFO: not svn Updating $to_dir since usually svn repo's aren't updated frequently enough..."
		# XXX accomodate for desired revision here if I ever uncomment the next line...
		# svn up
		change_dir ..
	fi
}

get_valid_remote() {
  local repo_url=$1
  local name=$2
  local to_dir=$3

  echo "DEBUG: Starting search for '$name' in $repo_url" >&2
  
  # Get all refs at once
  local all_refs
  if ! all_refs=$(git ls-remote "$repo_url"); then
    echo -e "DEBUG: Cannot access repository: $repo_url" >&2
    return 1
  fi
  echo "DEBUG: Repository is accessible" >&2

  # Check as commit SHA
  echo "DEBUG: Checking if '$name' is a commit SHA..." >&2
  if [[ "$name" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "DEBUG: '$name' matches SHA pattern" >&2
    if echo "$all_refs" | grep -q "^$name"; then
      echo "DEBUG: Found '$name' as a valid commit" >&2
      echo "git clone \"$repo_url\" \"$to_dir\" --recurse-submodules --single-branch && cd \"$to_dir\" && git checkout \"$name\" && cd .."
      return 0
    else
      echo "DEBUG: '$name' matches SHA pattern but not found in remote" >&2
    fi
  fi
  
  # Check as branch
  echo "DEBUG: Checking if '$name' is a branch..." >&2
  if echo "$all_refs" | grep -q "refs/heads/$name"; then
    echo "DEBUG: Found '$name' as a branch" >&2
    echo "git clone --depth 1 --branch \"$name\" \"$repo_url\" \"$to_dir\" --recurse-submodules --single-branch"
    return 0
  fi
  
  # Check as tag
  echo "DEBUG: Checking if '$name' is a tag..." >&2
  if echo "$all_refs" | grep -q "refs/tags/$name"; then
    echo "DEBUG: Found '$name' as a tag" >&2
    echo "git clone --depth 1 --branch \"$name\" \"$repo_url\" \"$to_dir\" --recurse-submodules --single-branch"
    return 0
  fi
  
  # Fallbacks
  echo "DEBUG: Checking fallback branches..." >&2
  for branch in main master; do
    if echo "$all_refs" | grep -q "refs/heads/$branch"; then
      echo "DEBUG: Found fallback branch '$branch'" >&2
      echo "git clone --depth 1 --branch \"$branch\" \"$repo_url\" \"$to_dir\" --recurse-submodules --single-branch"
      return 0
    fi
  done
  
  echo -e "DEBUG: No valid branch/tag/commit found in $repo_url (tried: $name, main, master)" >&2
  return 1
}

# params: git url, to_dir
retry_git_or_die() { # originally from https://stackoverflow.com/a/76012343/32453
	local RETRIES_NO=50
	local RETRY_DELAY=30
	local repo_url=$1
	local to_dir=$2
	local desired_branch="$3"
	for i in $(seq 1 $RETRIES_NO); do
		if ! git_command="$(get_valid_remote "$repo_url" "$desired_branch" "$to_dir.tmp")"; then
			echo -e "DEBUG: Could not find $desired_branch in $repo_url"
		else
			echo -e "INFO: Downloading (via git clone) branch, tag, or commit: $desired_branch to $to_dir from $repo_url"
			remove_path -rf "$to_dir.tmp" # just in case it was interrupted previously...not sure if necessary...
			create_dir "$to_dir.tmp"
			echo -e "DEBUG: Evaluating \"$git_command\""
			eval "$git_command" && break
		fi
		#git clone --depth 1 -b "$desired_branch" "$repo_url" "$to_dir.tmp" --recurse-submodules --single-branch && break
		# get here -> failure
		[[ $i -eq $RETRIES_NO ]] && echo -e "DEBUG: Failed to execute git cmd $repo_url $to_dir after $RETRIES_NO retries" && exit 1
		echo -e "DEBUG: sleeping before retry git"
		sleep ${RETRY_DELAY}
	done
	# prevent partial checkout confusion by renaming it only after success
	#mv $to_dir.tmp $to_dir
	echo -e "done git cloning branch $desired_branch to $to_dir"
}

do_git_checkout() {
	local repo_url="$1"
	local to_dir="$2"
	if [[ -n "$3" ]]; then
		desired_branch="$3"
	else
		desired_branch="master"
	fi
	echo -e "INFO: Starting git checkout $repo_url"
	if [[ -z $to_dir ]]; then
		to_dir=$(basename "$repo_url" | sed s/\.git/_git/) # http://y/abc.git -> abc_git
	fi
	if [ ! -d "$to_dir" ]; then
		echo -e "INFO: Downloading $repo_url $desired_branch into $to_dir"
		retry_git_or_die "$repo_url" "$to_dir" "$desired_branch"
    mv "$to_dir.tmp" "$to_dir"
		change_dir "$to_dir"
	else
		change_dir "$to_dir"
		if [[ $git_get_latest = "y" ]]; then
			git fetch # want this for later...
		else
			echo -e "INFO: not doing git get latest pull for latest code $to_dir" # too slow'ish...
		fi
	fi
}

git_hard_reset() {
	local target_path
	target_path=$(realpath "$1" 2>/dev/null) || return # Handle invalid paths
	if [ -z "$target_path" ]; then
		return
	fi

	local current_path
	current_path=$(pwd)

	if [ "$current_path" = "$target_path" ]; then
		git reset --hard # throw away results of patch files
		git clean -fx    # throw away local changes; 'already_*' and bak-files for instance.
	fi
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
	local beginning="$1"
	local extra_stuff="$2"
	local touch_name="${beginning}_$(echo -e -- "$extra_stuff" "$CFLAGS" "$LDFLAGS" | /usr/bin/env md5sum)" # md5sum to make it smaller, cflags to force rebuild if changes
	touch_name=$(echo -e "$touch_name" | sed "s/ //g")                                                      # md5sum introduces spaces, remove them
	echo -e "$touch_name"                                                                                   # bash cruddy return system LOL
}
# 1. configure_options
# 2. configure_name
# 3. touch_postfix
do_configure() {
	local configure_options="$1"
	local configure_name="$2"
	local touch_postfix=""
	[[ -n $3 ]] && touch_postfix="_$3"
	if [[ "$configure_name" = "" ]]; then
		configure_name="./configure"
	fi
	local cur_dir2=$(pwd)
	local english_name=$(basename "$cur_dir2")
	local touch_name=$(get_small_touchfile_name "already_configured$touch_postfix" "$configure_options $configure_name")
	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -f "$cur_dir2/already_configured$touch_postfix"*
	fi
	if [ ! -f "$touch_name" ]; then
		# make uninstall # does weird things when run under ffmpeg src so disabled for now...
		echo -e "configuring $english_name ($PWD) as $ PKG_CONFIG_PATH=$PKG_CONFIG_PATH PATH=$PATH $configure_name $configure_options" # say it now in case bootstrap fails etc.
		echo -e "all touch files" "already_configured$touch_postfix*" touchname= "$touch_name"
		echo -e "config options $configure_options $configure_name"
		if [ -f bootstrap ]; then
			./bootstrap # some need this to create ./configure :|
		fi
		if [[ ! -f $configure_name && -f bootstrap.sh ]]; then # fftw wants to only run this if no configure :|
			./bootstrap.sh
		fi
		if [[ ! -f $configure_name ]]; then
			echo -e "running autoreconf to generate configure file for us..."
			autoreconf -fiv # a handful of them require this to create ./configure :|
		fi
		remove_path -f "$cur_dir2/already_"*    # reset
		chmod u+x "$configure_name" # In non-windows environments, with devcontainers, the configuration file doesn't have execution permissions
		echo -e "INFO: do_configure() PATH=$PATH\n nice running: \"$configure_name $configure_options\""
		# shellcheck disable=SC2086
		nice -n 5 $configure_name $configure_options || {
			echo -e "failed configure $english_name"
			exit 1
		} # less nicey than make (since single thread, and what if you're running another ffmpeg nice build elsewhere?)
		touch -- "$touch_name"
		echo -e "doing preventative make clean"
		echo -e "INFO: do_configure() nice running: \"make clean -j $(get_cpu_count)\""
		nice make clean -j "$(get_cpu_count)" --silent # sometimes useful when files change, etc.
	#else
	#  echo -e "already configured $(basename $cur_dir2)"
	fi
}
# 1. extra_make_options
# 2. touch_postfix
do_make() {
	local extra_make_options="$1"
	local touch_postfix=""
	[[ -n $2 ]] && touch_postfix="_$2"
	extra_make_options="--silent -j $(get_cpu_count) $extra_make_options"
	local cur_dir2=$(pwd)
	local touch_name=$(get_small_touchfile_name "already_ran_make$touch_postfix" "$extra_make_options")
	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -f "$cur_dir2/already_ran_make$touch_postfix"*
	fi
	if [ ! -f "$touch_name" ]; then
		echo -e
		echo -e "Making $cur_dir2 as $ PATH=$PATH make $extra_make_options"
		echo -e
		if [ ! -f configure ]; then
			echo -e "INFO: do_make() PATH=$PATH\n nice running: \"make clean -j $(get_cpu_count)\""
			nice make clean -j "$(get_cpu_count)" --silent # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
		fi
		echo -e "INFO: do_make() PATH=$PATH\n nice running: \"make $extra_make_options\""
		# shellcheck disable=SC2086
		nice make $extra_make_options --silent || exit 1
		touch "$touch_name" || exit 1 # only touch if the build was OK
	else
		echo -e "Already made $(dirname "$cur_dir2") $(basename "$cur_dir2") ..."
	fi
}
# 1. extra_make_options
# 2. extra_install_options
# 3. touch_postfix
do_make_and_make_install() {
	extra_make_options="$1"
	extra_install_options="$2"
	touch_postfix="$3"
	do_make "$extra_make_options" "$touch_postfix"
	do_make_install "$extra_make_options" "$extra_install_options" "$touch_postfix"
}
# 1. extra_make_options
# 2. extra_install_options
# 3. touch_postfix
do_make_install() {
	local extra_make_install_options="--silent $1"
	local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
	local touch_postfix=""
	[[ -n $3 ]] && touch_postfix="_$3"
	if [[ -z $override_make_install_options ]]; then
		local make_install_options="install $extra_make_install_options"
	else
		local make_install_options="$override_make_install_options $extra_make_install_options"
	fi
	local touch_name=$(get_small_touchfile_name "already_ran_make_install$touch_postfix" "$make_install_options")
	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -f "already_ran_make_install$touch_postfix"*
	fi
	if [ ! -f "$touch_name" ]; then
		echo -e "INFO: do_make_install() PATH=$PATH\n nice running: \"make $make_install_options\""
		# shellcheck disable=SC2086
		nice make $make_install_options --silent || exit 1
		touch "$touch_name" || exit 1
	fi
}

check_cmake_cache() {
    local build_dir="${1:-./build}"
    local expected_source_dir="${2:-$(pwd)}"
    
    if [[ -f "$build_dir/CMakeCache.txt" ]]; then
        echo "INFO: Checking CMake cache in $build_dir"
        
        # Get cached values
        local cache_build_dir=$(grep "^CMAKE_CACHEFILE_DIR:" "$build_dir/CMakeCache.txt" | cut -d'=' -f2- 2>/dev/null | xargs || echo "")
        local cache_source_dir=$(grep "^CMAKE_HOME_DIRECTORY:" "$build_dir/CMakeCache.txt" | cut -d'=' -f2- 2>/dev/null | xargs || echo "")
        
        echo "INFO: Current build dir: $build_dir"
        echo "INFO: Cached build dir: $cache_build_dir"
        echo "INFO: Expected source dir: $expected_source_dir" 
        echo "INFO: Cached source dir: $cache_source_dir"
        
        # Check if build directory matches
        if [[ "$cache_build_dir" != "$build_dir" ]]; then
            echo "WARNING: CMakeCache.txt build directory mismatch"
            echo "  Cache expects: $cache_build_dir"
            echo "  Current build: $build_dir"
            return 1
        fi
        
        # Check if source directory matches (most important check)
        if [[ "$cache_source_dir" != "$expected_source_dir" ]]; then
            echo "WARNING: CMakeCache.txt source directory mismatch"
            echo "  Cache expects: $cache_source_dir"
            echo "  Current source: $expected_source_dir"
            return 1
        fi
        
        echo "INFO: CMake cache is valid"
        return 0
    else
        echo "INFO: No CMakeCache.txt found in $build_dir"
        return 0
    fi
}

# Usage example:
clean_cmake_cache() {
    local build_dir="${1:-./build}"
    local source_dir="${2:-$(pwd)}"
		if ! check_cmake_cache "$source_dir" "$source_dir"; then
        echo "DEBUG: Removing invalid CMake cache..."
        remove_path -f "$source_dir/CMakeCache.txt" 2>/dev/null || true
        remove_path -rf "$source_dir/CMakeFiles" 2>/dev/null || true
        echo "DEBUG: CMake cache cleaned"
				return 0
    fi
    if ! check_cmake_cache "$build_dir" "$source_dir"; then
        echo "DEBUG: Removing invalid CMake cache..."
        remove_path -f "$build_dir/CMakeCache.txt" 2>/dev/null || true
        remove_path -rf "$build_dir/CMakeFiles" 2>/dev/null || true
        echo "DEBUG: CMake cache cleaned"
				return 0
    fi
}

# 1. extra_args
# 2. source_dir
# 3. touch_postfix
do_cmake() {
	extra_args="$1"
	local build_from_dir="$2"
	local touch_postfix=""
	[[ -n $3 ]] && touch_postfix="_$3"
	if [[ -z $build_from_dir ]]; then
		build_from_dir="."
	fi
	local touch_name=$(get_small_touchfile_name "already_ran_cmake$touch_postfix" "$extra_args")
	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -f "already_ran_cmake$touch_postfix"*
	fi
	if [ ! -f "$touch_name" ]; then
		remove_path -f already_* # reset so that make will run again if option just changed
		clean_cmake_cache "$(pwd)/build" "$(pwd)"
		local cur_dir2=$(pwd)
		local config_options=""
		if [ "$bits_target" = 32 ]; then
			local config_options+="-DCMAKE_SYSTEM_PROCESSOR=x86"
		else
			local config_options+="-DCMAKE_SYSTEM_PROCESSOR=AMD64"
		fi
		echo -e "doing cmake in $cur_dir2 with PATH=$PATH with extra_args=$extra_args like this:"
		# TODO: Allow shared library build
		local command="${build_from_dir} -DCMAKE_MESSAGE_LOG_LEVEL=ERROR -DENABLE_STATIC_RUNTIME=1 -DBUILD_SHARED_LIBS=0 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_FIND_ROOT_PATH=$mingw_w64_x86_64_prefix -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_RANLIB=${cross_prefix}ranlib -DCMAKE_C_COMPILER=${cross_prefix}gcc -DCMAKE_CXX_COMPILER=${cross_prefix}g++ -DCMAKE_RC_COMPILER=${cross_prefix}windres -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $config_options $extra_args"
		echo -e "INFO: do_cmake() nice running: \"${cmake_command} -G\"Unix Makefiles\" $command\""
		# shellcheck disable=SC2086
		nice -n 5  ${cmake_command} -G"Unix Makefiles" $command || exit 1
		touch "$touch_name" || exit 1
	fi
}
# 1. source_dir
# 2. extra_args
# 3. touch_postfix
do_cmake_from_build_dir() { # some sources don't allow it, weird XXX combine with the above :)
	source_dir="$1"
	extra_args="$2"
	touch_postfix="$3"
	do_cmake "$extra_args" "$source_dir" "$touch_postfix"
}
# 1. extra_args
# 2. source_dir
# 3. touch_postfix
do_cmake_and_install() {
	extra_args="$1"
	source_dir="$2"
	touch_postfix="$3"
	do_cmake "$extra_args" "$source_dir" "$touch_postfix"
	do_make_and_make_install "" "" "$touch_postfix"
}

activate_meson() {
	echo -e "INFO: Activating meson"
	change_dir "$src_dir" # requires python3-full
	get_meson_cross_file
	if [[ ! -e meson_git ]]; then
		do_git_checkout https://github.com/mesonbuild/meson.git meson_git 1.9.1
	fi
	change_dir "$src_dir/meson_git"
	if [[ ! -e tutorial_env ]]; then
		python3 -m venv tutorial_env
		# shellcheck disable=SC1090
		source "$src_dir/meson_git/tutorial_env/bin/activate"
		python3 -m pip install meson
	else
		source "$src_dir/meson_git/tutorial_env/bin/activate"
	fi
	change_dir "$src_dir"
}
# 1. configure_options
# 2. configure_name
# 2. configure_env
# 4. touch_postfix
do_meson() {
	local configure_options="$1 --unity=off --warnlevel=0"
	local configure_name="$2"
	local configure_env="$3"
	local touch_postfix=""
	[[ -n $4 ]] && touch_postfix="_$4"
	local configure_noclean=""
	local configure_command
	if [[ -e "$src_dir/meson_git/meson.py" ]]; then
    configure_command=(python "$src_dir/meson_git/meson.py")
	else
		configure_command=(meson)
	fi
	if [[ "$configure_name" = "" ]]; then
		configure_name="meson"
	fi
	local cur_dir2=$(pwd)
	local english_name=$(basename "$cur_dir2")
	local touch_name=$(get_small_touchfile_name "already_built_meson$touch_postfix" "$configure_options ${configure_command[*]} $LDFLAGS $CFLAGS")
	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -f "already_built_meson$touch_postfix"*
	fi
	if [ ! -f "$touch_name" ]; then
		if [ "$configure_noclean" != "noclean" ]; then
			make clean --silent # just in case
		fi
		remove_path -f already_* # reset
		# if [[ -n "${configure_command[*]}" && -d "$(pwd)/build" ]]; then
		# 	echo -e "INFO: Using meson: \"${configure_command[*]}\" setup --wipe \"$(pwd)/build\""
		# 	"${configure_command[@]}" setup --wipe "$(pwd)/build"
		# fi
		if [[ -n "${configure_command[*]}" && -d "$(pwd)/build" ]]; then
			echo -e "INFO: Adding --reconfigure to meson config because there is an existing previous build"
			configure_options+=" --reconfigure"
		fi
		echo -e "INFO: Using meson: $english_name ($PWD) as PATH=$PATH ${configure_env} ${configure_command[*]} $configure_options"
		#env
		export MESON_BUILD_ROOT="$(pwd)/build"
		export MESON_SOURCE_ROOT="$(pwd)"
		# shellcheck disable=SC2086
		# shellcheck disable=SC1078
		"${configure_command[@]}" $configure_options || exit 1
		touch -- "$touch_name"
		make clean --silent # just in case
	else
		echo -e "INFO: Already used meson $(basename "$cur_dir2")"
	fi
}
# 1. extra_args
# 2. touch_postfix
generic_meson() {
	local extra_configure_options="$1"
	local touch_postfix="$2"
	create_dir build
	# TODO: Allow shared library build
	do_meson "--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib --buildtype=release --default-library=static $extra_configure_options" "" "$touch_postfix" # --cross-file=$(get_meson_cross_file)
}
# 1. extra_args
# 2. touch_postfix
generic_meson_ninja_install() {
	generic_meson "$1" "$2"
	do_ninja_and_ninja_install "$1" "$2"
}
# 1. extra_args
# 2. touch_postfix
do_ninja_and_ninja_install() {
	local extra_ninja_options="$1"
	local touch_postfix=""
	[[ -n $2 ]] && touch_postfix="_$2"
	do_ninja "$extra_ninja_options" "$touch_postfix"
	local touch_name=$(get_small_touchfile_name "already_ran_make_install$touch_postfix" "$extra_ninja_options")
	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -f "already_ran_make_install$touch_postfix"*
	fi
	if [ ! -f "$touch_name" ]; then
		echo -e "INFO: PATH=$PATH\n do_ninja() in $(pwd) ninja running: \"build $extra_make_options\""
		ninja -C build install --quiet || exit 1
		touch "$touch_name" || exit 1
	fi
}

# 1. touch_postfix
do_ninja() {
	local touch_postfix=""
	[[ -n $1 ]] && touch_postfix="_$1"
	local extra_make_options=" -j $(get_cpu_count)"
	local cur_dir2=$(pwd)
	local touch_name=$(get_small_touchfile_name "already_ran_make$touch_postfix" "${extra_make_options}")
	if [[ $BUILD_FORCE == "1" ]]; then
		remove_path -f "already_ran_make$touch_postfix"*
	fi
	if [ ! -f "$touch_name" ]; then
		echo -e
		echo -e "INFO: ninja-ing $cur_dir2 as PATH=$PATH ninja -C build $extra_make_options"
		echo -e
		echo -e "INFO: do_ninja() ninja running: \"build $extra_make_options\""
		# shellcheck disable=SC2086
		ninja -C build ${extra_make_options} --quiet || exit 1
		touch "$touch_name" || exit 1 # only touch if the build was OK
	else
		echo -e "INFO: already did ninja $(basename "$cur_dir2")"
	fi
}

apply_patch() {
	local url=$1 # if you want it to use a local file instead of a url one [i.e. local file with local modifications] specify it like file://localhost/full/path/to/filename.patch
	local patch_type=$2
	if [[ -z $patch_type ]]; then
		patch_type="-p0" # some are -p1 unfortunately, git's default
	fi
	local patch_name=$(basename "$url")
	local patch_done_name="$patch_name.done"
	local touch_name=
	if [[ ! -e $patch_done_name ]]; then
		if [[ -f $patch_name ]]; then
			remove_path -rf "$patch_name" || exit 1 # remove old version in case it has been since updated on the server...
		fi
		curl -4 --retry 5 "$url" -O --fail || echo_and_exit "unable to download patch file $url"
		echo -e "INFO: applying patch $patch_name"
		patch "$patch_type" <"$patch_name" || exit 1
		touch "$patch_done_name" || exit 1
		# too crazy, you can't do do_configure then apply a patch?
		# rm -f already_ran* # if it's a new patch, reset everything too, in case it's really really really new
	#else
	#  echo -e "patch $patch_name already applied" # too chatty
	fi
}

echo_and_exit() {
	echo -e "failure, exiting: $1"
	exit 1
}

# takes a url, output_dir as params, output_dir optional
download_and_unpack_file() {
	url="$1"
	output_name=$(basename "$url")
	output_dir="$2"
	if [[ -z $output_dir ]]; then
		output_dir=$(basename "$url" | sed s/\.tar\.*//) # remove .tar.xx
	fi
	if [ ! -f "$output_dir/unpacked.successfully" ]; then
		echo -e "downloading $url" # redownload in case failed...
		if [[ -f $output_name ]]; then
			remove_path -rf "$output_name" || exit 1
		fi

		#  From man curl
		#  -4, --ipv4
		#  If curl is capable of resolving an address to multiple IP versions (which it is if it is  IPv6-capable),
		#  this option tells curl to resolve names to IPv4 addresses only.
		#  avoid a "network unreachable" error in certain [broken Ubuntu] configurations a user ran into once
		#  -L means "allow redirection" or some odd :|

		curl -4 "$url" --retry 50 -O -L --fail || echo -e_and_exit "unable to download $url"
		echo -e "unzipping $output_name ..."
		tar -xf "$output_name" || unzip "$output_name" || exit 1
		touch "$output_dir/unpacked.successfully" || exit 1
		remove_path -rf "$output_name" || exit 1
	fi
}
# 1. extra config options
generic_configure() {
	build_triple="${build_triple:-$(gcc -dumpmachine)}"
	local extra_configure_options="$1"
	if [[ -n $build_triple ]]; then extra_configure_options+=" --build=$build_triple"; fi
	# TODO: Allow shared library build
	do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static $extra_configure_options"
}

# params: url, optional "english name it will unpack to"
generic_download_and_make_and_install() {
	local url="$1"
	local english_name="$2"
	if [[ -z $english_name ]]; then
		english_name=$(basename "$url" | sed s/\.tar\.*//) # remove .tar.xx, take last part of url
	fi
	local extra_configure_options="$3"
	download_and_unpack_file "$url" "$english_name"
	change_dir "$english_name"
	generic_configure "$extra_configure_options"
	do_make_and_make_install
	change_dir ..
}

generic_configure_make_install() {
	generic_configure # no parameters, force myself to break it up if needed
	do_make_and_make_install
}
# 1. git url
do_git_checkout_and_make_install() {
	local url=$1
	local git_checkout_name=$(basename "$url" | sed s/\.git/_git/) # http://y/abc.git -> abc_git
	do_git_checkout "$url" "$git_checkout_name"
	change_dir "$git_checkout_name"
	generic_configure_make_install
	change_dir ..
}

gen_ld_script() {
	lib=$mingw_w64_x86_64_prefix/lib/$1
	lib_s="$2"
	if [[ ! -f $mingw_w64_x86_64_prefix/lib/lib$lib_s.a ]]; then
		echo -e "Generating linker script $lib: $2 $3"
		mv -f "$lib" "$mingw_w64_x86_64_prefix"/lib/lib"$lib_s".a
		echo -e "GROUP ( -l$lib_s $3 )" >"$lib"
	fi
}

#===============================================================================================
#                                     WINDOWS BUILD LIBRARIES
#===============================================================================================

build_dlfcn() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/dlfcn-win32/dlfcn-win32.git 1>>"$LOG_FILE" 2>&1
	change_dir "$src_dir/dlfcn-win32_git"
	if [[ ! -f Makefile.bak ]]; then # Change CFLAGS.
		sed -i.bak "s/-O3/-O2/" Makefile
	fi
	do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix" # rejects some normal cross compile options so custom here
	do_make_and_make_install
	gen_ld_script libdl.a dl_s -lpsapi # dlfcn-win32's 'README.md': "If you are linking to the static 'dl.lib' or 'libdl.a', then you would need to explicitly add 'psapi.lib' or '-lpsapi' to your linking command, depending on if MinGW is used."
	change_dir "$src_dir"
}

build_bzip2() {
	change_dir "$src_dir"
	download_and_unpack_file https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
	change_dir "$src_dir/bzip2-1.0.8"
	apply_patch "file://$WINPATCHDIR/bzip2-1.0.8_brokenstuff.diff"
	if [[ ! -f ./libbz2.a ]] || [[ -f $mingw_w64_x86_64_prefix/lib/libbz2.a && ! $(/usr/bin/env md5sum ./libbz2.a) = $(/usr/bin/env md5sum "$mingw_w64_x86_64_prefix"/lib/libbz2.a) ]]; then # Not built or different build installed
		do_make "$compiler_flags libbz2.a"
		install -m644 bzlib.h "$mingw_w64_x86_64_prefix"/include/bzlib.h
		install -m644 libbz2.a "$mingw_w64_x86_64_prefix"/lib/libbz2.a
	else
		echo -e "Already made bzip2-1.0.8"
	fi
	change_dir "$src_dir"
}

build_liblzma() {
	change_dir "$src_dir"
	download_and_unpack_file https://sourceforge.net/projects/lzmautils/files/xz-5.8.1.tar.xz
	change_dir "$src_dir/xz-5.8.1"
	generic_configure "--disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc --disable-nls"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_zlib() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/madler/zlib.git zlib_git
	change_dir "$src_dir/zlib_git"
	local make_options
	export ARFLAGS=rcs # Native can't take ARFLAGS; https://stackoverflow.com/questions/21396988/zlib-build-not-configuring-properly-with-cross-compiler-ignores-ar
	# TODO: Allow shared library build
	do_configure "--prefix=$mingw_w64_x86_64_prefix --static"
	do_make_and_make_install "$compiler_flags ARFLAGS=rcs"
	unset ARFLAGS
	change_dir "$src_dir"
}

build_iconv() {
	change_dir "$src_dir"
	download_and_unpack_file https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz
	change_dir "$src_dir/libiconv-1.18"
	generic_configure "--disable-nls"
	do_make "install-lib" # No need for 'do_make_install', because 'install-lib' already has install-instructions.
	change_dir "$src_dir"
}

build_brotli() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/google/brotli.git brotli_git v1.0.9 # v1.1.0 static headache stay away
	change_dir "$src_dir/brotli_git"
	if [ ! -f "brotli.exe" ]; then
		remove_path -f configure
	fi
	generic_configure
	sed -i.bak -e "s/\(allow_undefined=\)yes/\1no/" libtool
	do_make_and_make_install
  sed -i.bak 's/Libs.*$/Libs: -L${libdir} -lbrotlicommon/' "$PKG_CONFIG_PATH"/libbrotlicommon.pc # remove rpaths not possible in conf
  sed -i.bak 's/Libs.*$/Libs: -L${libdir} -lbrotlidec/' "$PKG_CONFIG_PATH"/libbrotlidec.pc
  sed -i.bak 's/Libs.*$/Libs: -L${libdir} -lbrotlienc/' "$PKG_CONFIG_PATH"/libbrotlienc.pc
	change_dir "$src_dir"
}

build_zstd() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/facebook/zstd.git zstd_git v1.5.7
	change_dir "$src_dir/zstd_git"
	do_cmake "-S build/cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DZSTD_BUILD_SHARED=OFF -DZSTD_USE_STATIC_RUNTIME=ON -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_sdl2() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.libsdl.org/release/SDL2-2.32.10.tar.gz
	change_dir "$src_dir/SDL2-2.32.10"
	apply_patch "file://$WINPATCHDIR/SDL2-2.32.10_lib-only.diff"
	if [[ ! -f configure.bak ]]; then
		sed -i.bak "s/ -mwindows//" configure # Allow ffmpeg to output anything to console.
	fi
	export CFLAGS="$CFLAGS -DDECLSPEC=" # avoid SDL trac tickets 939 and 282 [broken shared builds]
	generic_configure "--bindir=$mingw_bin_path"
	do_make_and_make_install
	if [[ ! -f $mingw_bin_path/$host_target-sdl2-config ]]; then
		mv "$mingw_bin_path/sdl2-config" "$mingw_bin_path/$host_target-sdl2-config" # At the moment FFmpeg's 'configure' doesn't use 'sdl2-config', because it gives priority to 'sdl2.pc', but when it does, it expects 'i686-w64-mingw32-sdl2-config' in 'cross_compilers/mingw-w64-i686/bin'.
	fi
	reset_cflags
	change_dir "$src_dir"
}

build_amd_amf_headers() {
	change_dir "$src_dir"
	# was https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git too big
	# or https://github.com/DeadSix27/AMF smaller
	# but even smaller!
	do_git_checkout https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git amf_headers_git
	change_dir "$src_dir/amf_headers_git"
	if [ ! -f "already_installed" ]; then
		#rm -rf "./Thirdparty" # ?? plus too chatty...
		if [ ! -d "$mingw_w64_x86_64_prefix/include/AMF" ]; then
			create_dir "$mingw_w64_x86_64_prefix/include/AMF"
		fi
		cp -av "amf/public/include/." "$mingw_w64_x86_64_prefix/include/AMF"
		touch "already_installed"
	fi
	change_dir "$src_dir"
}

build_nv_headers() {
	change_dir "$src_dir"
	if [[ $ffmpeg_git_checkout_version == *"n6.0"* ]] || [[ $ffmpeg_git_checkout_version == *"n5"* ]] || [[ $ffmpeg_git_checkout_version == *"n4"* ]] || [[ $ffmpeg_git_checkout_version == *"n3"* ]] || [[ $ffmpeg_git_checkout_version == *"n2"* ]]; then
		# nv_headers for old versions
		do_git_checkout https://github.com/FFmpeg/nv-codec-headers.git nv-codec-headers_git n12.0.16.1
	else
		do_git_checkout https://github.com/FFmpeg/nv-codec-headers.git
	fi
	change_dir "$src_dir/nv-codec-headers_git"
	do_make_install "PREFIX=$mingw_w64_x86_64_prefix" # just copies in headers
	change_dir "$src_dir"
}

build_intel_qsv_mfx() {
	change_dir "$src_dir"                                                                # disableable via command line switch...
	do_git_checkout https://github.com/lu-zero/mfx_dispatch.git mfx_dispatch_git 2cd279f # lu-zero?? oh well seems somewhat supported...
	change_dir "$src_dir/mfx_dispatch_git"
	if [[ ! -f "configure" ]]; then
		autoreconf -fiv || exit 1
		automake --add-missing || exit 1
	fi
	generic_configure_make_install
	change_dir "$src_dir"
}

build_libvpl() {
	change_dir "$src_dir"
	# build_intel_qsv_mfx
	do_git_checkout https://github.com/intel/libvpl.git libvpl_git # f8d9891
	change_dir "$src_dir/libvpl_git"
	if [ "$bits_target" = "32" ]; then
		apply_patch "https://raw.githubusercontent.com/msys2/MINGW-packages/master/mingw-w64-libvpl/0003-cmake-fix-32bit-install.patch" -p1
	fi
	do_cmake "-B build -GNinja -DCMAKE_BUILD_TYPE=Release -DINSTALL_EXAMPLES=OFF -DINSTALL_DEV=ON -DBUILD_EXPERIMENTAL=OFF"
	do_ninja_and_ninja_install
	sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/vpl.pc"
	change_dir "$src_dir"
}

build_giflib() {
	change_dir "$src_dir"
	generic_download_and_make_and_install https://sourceforge.net/projects/giflib/files/giflib-5.1.4.tar.gz
	change_dir "$src_dir"
}

build_libleptonica() {
	build_libjpeg_turbo
	build_giflib
	change_dir "$src_dir"
	do_git_checkout "https://github.com/DanBloomberg/leptonica.git" "leptonica_git"
	change_dir "$src_dir/leptonica_git"
	export CPPFLAGS="-DOPJ_STATIC"
	generic_configure_make_install
	reset_cppflags
	change_dir "$src_dir"
}

build_libtiff() {
	build_libjpeg_turbo # auto uses it?
	change_dir "$src_dir"
	generic_download_and_make_and_install http://download.osgeo.org/libtiff/tiff-4.7.1.tar.gz
	sed -i.bak "s/-ltiff.*$/-ltiff -llzma -ljpeg -lz/" "$PKG_CONFIG_PATH/libtiff-4.pc" # static deps
	change_dir "$src_dir"
}

build_libtensorflow() {
	change_dir "$src_dir"
	if [[ ! -e Tensorflow ]]; then
		create_dir "$src_dir/Tensorflow"
		change_dir "$src_dir/Tensorflow"
		wget "https://storage.googleapis.com/tensorflow/versions/2.18.1/libtensorflow-cpu-windows-x86_64.zip" # tensorflow.dll required by ffmpeg to run
		unzip -o "libtensorflow-cpu-windows-x86_64.zip" -d "$mingw_w64_x86_64_prefix"
		remove_path -f "libtensorflow-cpu-windows-x86_64.zip"
		change_dir ..
	else
		echo -e "Tensorflow already installed"
	fi
	change_dir "$src_dir"
}

build_gettext() {
	change_dir "$src_dir"
	generic_download_and_make_and_install "https://ftp.gnu.org/pub/gnu/gettext/gettext-0.26.tar.gz"
	change_dir "$src_dir"
}

build_libffi() {
	change_dir "$src_dir"
	download_and_unpack_file "https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz" # also dep
	change_dir "$src_dir/libffi-3.5.2"
	apply_patch "file://$WINPATCHDIR/libffi.patch" -p1
	generic_configure_make_install
	change_dir "$src_dir"
}

build_glib() {
	build_gettext
	build_libffi
	change_dir "$src_dir"
	do_git_checkout https://github.com/GNOME/glib.git glib_git
	activate_meson
	change_dir "$src_dir/glib_git"
	local meson_options="setup build --force-fallback-for=libpcre -Dforce_posix_threads=true -Dman-pages=disabled -Dsysprof=disabled -Dglib_debug=disabled -Dtests=false --wrap-mode=default"
	# get_local_meson_cross_with_propeties
	meson_options+=" --cross-file=$(get_meson_cross_file)"
	do_meson "$meson_options"
	do_ninja_and_ninja_install
	sed -i.bak 's/-lglib-2.0.*$/-lglib-2.0 -lintl -lws2_32 -lwinmm -lm -liconv -lole32/' "$PKG_CONFIG_PATH/glib-2.0.pc"
	deactivate
	change_dir "$src_dir"
}

build_lensfun() {
	build_glib
	change_dir "$src_dir"
	do_git_checkout "https://github.com/lensfun/lensfun.git" "lensfun_git"
	change_dir "$src_dir/lensfun_git"
	export CPPFLAGS="$CPPFLAGS-DGLIB_STATIC_COMPILATION"
	export CXXFLAGS="$CFLAGS -DGLIB_STATIC_COMPILATION"
	# TODO: Allow shared library build
	do_cmake "-DBUILD_STATIC=on -DCMAKE_INSTALL_DATAROOTDIR=$mingw_w64_x86_64_prefix -DBUILD_TESTS=off -DBUILD_DOC=off -DINSTALL_HELPER_SCRIPTS=off -DINSTALL_PYTHON_MODULE=OFF"
	do_make_and_make_install
	sed -i.bak 's/-llensfun/-llensfun -lstdc++/' "$PKG_CONFIG_PATH/lensfun.pc"
	reset_cppflags
	unset CXXFLAGS
	change_dir "$src_dir"
}

build_lz4() {
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz
	change_dir "$src_dir/lz4-1.10.0"
	# TODO: Allow shared library build
	do_cmake "-S build/cmake -B build -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_STATIC_LIBS=ON"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libarchive() {
	build_lz4
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/libarchive/libarchive/releases/download/v3.8.1/libarchive-3.8.1.tar.gz
	change_dir "$src_dir/libarchive-3.8.1"
	generic_configure "--with-nettle --bindir=$mingw_w64_x86_64_prefix/bin --without-openssl --without-iconv --disable-posix-regex-lib"
	do_make_install
	change_dir "$src_dir"
}

build_flac() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/flac.git flac_git
	change_dir "$src_dir/flac_git"
	do_cmake "-B build -DCMAKE_BUILD_TYPE=Release -DINSTALL_MANPAGES=OFF -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_openmpt() {
	build_flac
	change_dir "$src_dir"
	do_git_checkout https://github.com/OpenMPT/openmpt.git openmpt_git # OpenMPT-1.30
	change_dir "$src_dir/openmpt_git"
	# TODO: Allow shared library build
	do_make_and_make_install "PREFIX=$mingw_w64_x86_64_prefix CONFIG=mingw64-win64 EXESUFFIX=.exe SOSUFFIX=.dll SOSUFFIXWINDOWS=1 DYNLINK=0 SHARED_LIB=0 STATIC_LIB=1 
      SHARED_SONAME=0 IS_CROSS=1 NO_ZLIB=0 NO_LTDL=0 NO_DL=0 NO_MPG123=0 NO_OGG=0 NO_VORBIS=0 NO_VORBISFILE=0 NO_PORTAUDIO=1 NO_PORTAUDIOCPP=1 NO_PULSEAUDIO=1 NO_SDL=0 
      NO_SDL2=0 NO_SNDFILE=0 NO_FLAC=0 EXAMPLES=0 OPENMPT123=0 TEST=0" # OPENMPT123=1 >>> fail
	sed -i.bak 's/Libs.private.*/& -lrpcrt4/' "$PKG_CONFIG_PATH/libopenmpt.pc"
	change_dir "$src_dir"
}

build_libpsl() {
	change_dir "$src_dir"
	export CFLAGS="-DPSL_STATIC"
	download_and_unpack_file https://github.com/rockdaboot/libpsl/releases/download/0.21.5/libpsl-0.21.5.tar.gz
	change_dir "$src_dir/libpsl-0.21.5"
	generic_configure "--disable-nls --disable-rpath --disable-gtk-doc-html --disable-man --disable-runtime"
	do_make_and_make_install
	sed -i.bak "s/Libs: .*/& -lidn2 -lunistring -lws2_32 -liconv/" "$PKG_CONFIG_PATH/libpsl.pc"
	reset_cflags
	change_dir "$src_dir"
}

build_nghttp2() {
	change_dir "$src_dir"
	export CFLAGS="-DNGHTTP2_STATICLIB"
	download_and_unpack_file https://github.com/nghttp2/nghttp2/releases/download/v1.67.1/nghttp2-1.67.1.tar.gz
	change_dir "$src_dir/nghttp2-1.67.1"
	# TODO: Allow shared library build
	do_cmake "-B build -DENABLE_LIB_ONLY=1 -DBUILD_SHARED_LIBS=0 -DBUILD_STATIC_LIBS=1 -GNinja"
	do_ninja_and_ninja_install
	reset_cflags
	change_dir "$src_dir"
}

build_libssh2() {
	change_dir "$src_dir"
	generic_download_and_make_and_install https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.1/libssh2-1.11.1.tar.gz
	change_dir "$src_dir"
}

build_curl() {
	change_dir "$src_dir"
	build_libssh2
	build_zstd
	build_brotli
	build_libpsl
	build_nghttp2
	local config_options=""
	export CPPFLAGS+="$CPPFLAGS -DNGHTTP2_STATICLIB -DPSL_STATIC $config_options"
	change_dir "$src_dir"
	do_git_checkout https://github.com/curl/curl.git curl_git curl-8_16_0
	change_dir "$src_dir/curl_git"
	generic_configure "--with-libssh2 --with-libpsl --with-libidn2 --disable-debug --enable-hsts --with-brotli --enable-versioned-symbols --enable-sspi --with-schannel"
	do_make_and_make_install
	reset_cppflags
	change_dir "$src_dir"
}

build_libtesseract() {
	build_libtiff
	build_libleptonica
	build_libarchive
	change_dir "$src_dir"
	do_git_checkout https://github.com/tesseract-ocr/tesseract.git tesseract_git
	change_dir "$src_dir/tesseract_git"
	export CPPFLAGS="$CPPFLAGS -DCURL_STATICLIB"
	generic_configure "--disable-openmp --with-archive --disable-graphics --disable-tessdata-prefix --with-curl LIBLEPT_HEADERSDIR=$mingw_w64_x86_64_prefix/include --datadir=$mingw_w64_x86_64_prefix/bin"
	do_make_and_make_install
	sed -i.bak 's/Requires.private.*/& lept libarchive liblzma libtiff-4 libcurl/' "$PKG_CONFIG_PATH/tesseract.pc"
	sed -i 's/-ltesseract.*$/-ltesseract -lstdc++ -lws2_32 -lbz2 -lz -liconv -lpthread  -lgdi32 -lcrypt32/' "$PKG_CONFIG_PATH/tesseract.pc"
	if [[ ! -f $mingw_w64_x86_64_prefix/bin/tessdata/tessdata/eng.traineddata ]]; then
		create_dir "$mingw_w64_x86_64_prefix/bin/tessdata"
		cp -f /usr/share/tesseract-ocr/**/tessdata/eng.traineddata "$mingw_w64_x86_64_prefix/bin/tessdata/"
	fi
	reset_cppflags
	change_dir "$src_dir"
}

build_libzimg() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/sekrit-twc/zimg.git zimg_git
	change_dir "$src_dir"
}

build_libopenjpeg() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/uclouvain/openjpeg.git openjpeg_git
	change_dir "$src_dir/openjpeg_git"
	do_cmake_and_install "-DCMAKE_CROSSCOMPILING=1 -DOPJ_BIG_ENDIAN=0 -DBUILD_CODEC=0"
	change_dir "$src_dir"
}

build_glew() {
	change_dir "$src_dir"
	download_and_unpack_file https://sourceforge.net/projects/glew/files/glew/2.2.0/glew-2.2.0.tgz glew-2.2.0
	change_dir "$src_dir/glew-2.2.0/build"
	local cmake_params=""
	cmake_params+=" -DWIN32=1"
	do_cmake_from_build_dir ./cmake "$cmake_params" # "-DWITH_FFMPEG=0 -DOPENCV_GENERATE_PKGCONFIG=1 -DHAVE_DSHOW=0"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_glfw() {
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/glfw/glfw/releases/download/3.4/glfw-3.4.zip glfw-3.4
	change_dir "$src_dir/glfw-3.4"
	do_cmake_and_install "-DGLFW_BUILD_WAYLAND=OFF -DGLFW_BUILD_X11=OFF -DGLFW_BUILD_WIN32=ON"
	change_dir "$src_dir"
}

build_libpng() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/glennrp/libpng.git
	change_dir "$src_dir"
}

build_libwebp() {
	change_dir "$src_dir"
	do_git_checkout https://chromium.googlesource.com/webm/libwebp.git libwebp_git
	change_dir "$src_dir/libwebp_git"
	# TODO: Allow shared library build
	export LIBPNG_CONFIG="$mingw_w64_x86_64_prefix/bin/libpng-config --static" # LibPNG somehow doesn't get autodetected.
	generic_configure "--disable-wic"
	do_make_and_make_install
	unset LIBPNG_CONFIG
	change_dir "$src_dir"
}

build_harfbuzz() {
	change_dir "$src_dir"
	activate_meson
	build_freetype
	do_git_checkout https://github.com/harfbuzz/harfbuzz.git harfbuzz_git "10.4.0" # 11.0.0 no longer found by ffmpeg via this method, multiple issues, breaks harfbuzz freetype circular depends hack
	change_dir "$src_dir/harfbuzz_git"
	if [[ ! -f DUN ]]; then
		local meson_options="setup build -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled"
		# get_local_meson_cross_with_propeties
		meson_options+=" --cross-file=$(get_meson_cross_file)"
		do_meson "$meson_options"
		do_ninja_and_ninja_install
		touch DUN
	fi
	change_dir "$src_dir"
	build_freetype # with harfbuzz now
	deactivate
	sed -i.bak 's/-lfreetype.*/-lfreetype -lharfbuzz -lpng -lbz2/' "$PKG_CONFIG_PATH/freetype2.pc"
	sed -i.bak 's/-lharfbuzz.*/-lfreetype -lharfbuzz -lpng -lbz2/' "$PKG_CONFIG_PATH/harfbuzz.pc"
}

build_freetype() {
	activate_meson
	change_dir "$src_dir"
	do_git_checkout https://github.com/freetype/freetype.git freetype_git
	change_dir "$src_dir/freetype_git"
	local config_options=""
	if [[ -e $PKG_CONFIG_PATH/harfbuzz.pc ]]; then
		local config_options+=" -Dharfbuzz=enabled"
	fi
	local meson_options="setup build $config_options"
	# get_local_meson_cross_with_propeties
	meson_options+=" --cross-file=$(get_meson_cross_file)"
	do_meson "$meson_options"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libxml2() {
	change_dir "$src_dir"
	do_git_checkout https://gitlab.gnome.org/GNOME/libxml2.git libxml2_git
	change_dir "$src_dir/libxml2_git"
	generic_configure "--with-ftp=no --with-http=no --with-python=no"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libvmaf() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/Netflix/vmaf.git vmaf_git
	activate_meson
	change_dir "$src_dir/vmaf_git/libvmaf"
	local meson_options="setup build -Denable_float=true -Dbuilt_in_models=true -Denable_tests=false -Denable_docs=false"
	# get_local_meson_cross_with_propeties
	meson_options+=" --cross-file=$(get_meson_cross_file)"
	do_meson "$meson_options"
	do_ninja_and_ninja_install
	sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/libvmaf.pc"
	deactivate
	change_dir "$src_dir"
}

build_fontconfig() {
	activate_meson
	change_dir "$src_dir"
	do_git_checkout https://gitlab.freedesktop.org/fontconfig/fontconfig.git fontconfig_git # meson build for fontconfig no good
	change_dir "$src_dir/fontconfig_git"
	local meson_options="setup build -Ddoc=disabled -Diconv=enabled -Dxml-backend=libxml2 -Dtests=disabled"
	# get_local_meson_cross_with_propeties
	meson_options+=" --cross-file=$(get_meson_cross_file)"
	do_meson "$meson_options"
	do_ninja_and_ninja_install
	#generic_configure "--enable-iconv --enable-libxml2 --disable-docs --with-libiconv --disable-testing" # Use Libxml2 instead of Expat; will find libintl from gettext on 2nd pass build and ffmpeg rejects it
	#do_make_and_make_install
	change_dir "$src_dir"
}

build_gmp() {
	change_dir "$src_dir"
	download_and_unpack_file https://ftp.gnu.org/pub/gnu/gmp/gmp-6.3.0.tar.xz
	change_dir "$src_dir/gmp-6.3.0"
	export CC_FOR_BUILD=/usr/bin/gcc # WSL seems to need this..
	export CPP_FOR_BUILD=usr/bin/cpp
	generic_configure "ABI=$bits_target"
	unset CC_FOR_BUILD
	unset CPP_FOR_BUILD
	do_make_and_make_install
	change_dir "$src_dir"
}

build_librtmfp() {
	# needs some version of openssl...
	# build_openssl_1_0_2 # fails OS X
	build_openssl_1_1_1 # fails WSL
	change_dir "$src_dir"
	do_git_checkout https://github.com/MonaSolutions/librtmfp.git
	change_dir "$src_dir/librtmfp_git/include/Base"
	do_git_checkout https://github.com/meganz/mingw-std-threads.git mingw-std-threads # our g++ apparently doesn't have std::mutex baked in...weird...this replaces it...
	change_dir "$src_dir"
	change_dir "$src_dir/librtmfp_git"
	apply_patch "file://$WINPATCHDIR/rtmfp.static.cross.patch" -p1  # works e48efb4f
	apply_patch "file://$WINPATCHDIR/rtmfp_capitalization.diff" -p1 # cross for windows needs it if on linux...
	apply_patch "file://$WINPATCHDIR/librtmfp_xp.diff.diff" -p1     # cross for windows needs it if on linux...
	do_make "$compiler_flags GPP=${cross_prefix}g++"
	do_make_install "prefix=$mingw_w64_x86_64_prefix PKGCONFIGPATH=$PKG_CONFIG_PATH"
	sed -i.bak 's/-lrtmfp.*/-lrtmfp -lstdc++ -lws2_32 -liphlpapi/' "$PKG_CONFIG_PATH/librtmfp.pc"
	change_dir "$src_dir"
}

build_libnettle() {
	change_dir "$src_dir"
	download_and_unpack_file https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz
	change_dir "$src_dir/nettle-3.10.2"
	local config_options="--disable-openssl --disable-documentation" # in case we have both gnutls and openssl, just use gnutls [except that gnutls uses this so...huh?
	generic_configure "$config_options" # in case we have both gnutls and openssl, just use gnutls [except that gnutls uses this so...huh? https://github.com/rdp/ffmpeg-windows-build-helpers/issues/25#issuecomment-28158515
	do_make_and_make_install            # What's up with "Configured with: ... --with-gmp=/cygdrive/d/ffmpeg-windows-build-helpers-master/native_build/windows/ffmpeg_local_builds/prebuilt/cross_compilers/pkgs/gmp/gmp-6.1.2-i686" in 'config.log'? Isn't the 'gmp-6.1.2' above being used?
	change_dir "$src_dir"
}

build_unistring() {
	change_dir "$src_dir"
	generic_download_and_make_and_install https://ftp.gnu.org/gnu/libunistring/libunistring-1.4.1.tar.gz
	change_dir "$src_dir"
}

build_libidn2() {
	change_dir "$src_dir"
	download_and_unpack_file https://ftp.gnu.org/gnu/libidn/libidn2-2.3.8.tar.gz
	change_dir "$src_dir/libidn2-2.3.8"
	generic_configure "--disable-doc --disable-rpath --disable-nls --disable-gtk-doc-html --disable-fast-install"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_gnutls() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.9.tar.xz # v3.8.10 not found by ffmpeg with identical .pc?
	change_dir "$src_dir/gnutls-3.8.9"
	export CFLAGS="-Wno-int-conversion"
	local config_options=""
	local config_options+=" --disable-non-suiteb-curves"
	generic_configure "--disable-cxx --disable-doc --disable-tools --disable-tests --disable-nls --disable-rpath --disable-libdane --disable-gcc-warnings --disable-code-coverage
      --without-p11-kit --with-idn --without-tpm --with-included-unistring --with-included-libtasn1 -disable-gtk-doc-html --with-brotli $config_options"
	do_make_and_make_install
	reset_cflags
	sed -i.bak 's/-lgnutls.*/-lgnutls -lcrypt32 -lnettle -lhogweed -lgmp -liconv -lunistring/' "$PKG_CONFIG_PATH/gnutls.pc"
	change_dir "$src_dir"
}

build_openssl_1_0_2() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.openssl.org/source/openssl-1.0.2p.tar.gz
	change_dir "$src_dir/openssl-1.0.2p"
	apply_patch "file://$WINPATCHDIR/openssl-1.0.2l_lib-only.diff"
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

		create_dir "$src_dir/redist" # Strip and pack shared libraries.
		archive="$src_dir/redist/openssl-${arch}-v1.0.2l.7z"
		if [[ ! -f $archive ]]; then
			for sharedlib in *.dll; do
				# shellcheck disable=SC2086
				"${cross_prefix}strip" $sharedlib
			done
			sed "s/$/\r/" LICENSE >LICENSE.txt
			7z a -mx=9 "$archive" *.dll LICENSE.txt && remove_path -f LICENSE.txt
		fi
	else
		do_make_and_make_install
	fi
	unset CC
	unset AR
	unset RANLIB
	change_dir "$src_dir"
}

build_openssl_1_1_1() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.openssl.org/source/openssl-1.1.1.tar.gz
	change_dir "$src_dir/openssl-1.1.1"
	export CC="${cross_prefix}gcc"
	export AR="${cross_prefix}ar"
	export RANLIB="${cross_prefix}ranlib"
	local config_options="--prefix=$mingw_w64_x86_64_prefix zlib "
	if [ "$1" = "dllonly" ]; then
		config_options+="shared no-engine "
	else
		config_options+="no-shared no-dso no-engine "
	fi
	if [[ $(uname) =~ 5.1 ]] || [[ $(uname) =~ 6.0 ]]; then
		config_options+="no-async " # "Note: on older OSes, like CentOS 5, BSD 5, and Windows XP or Vista, you will need to configure with no-async when building OpenSSL 1.1.0 and above. The configuration system does not detect lack of the Posix feature on the platforms." (https://wiki.openssl.org/index.php/Compilation_and_Installation)
	fi
	if [ "$bits_target" = "32" ]; then
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
		create_dir "$src_dir/redist" # Strip and pack shared libraries.
		archive="$src_dir/redist/openssl-${arch}-v1.1.0f.7z"
		if [[ ! -f $archive ]]; then
			for sharedlib in *.dll; do
				# shellcheck disable=SC2086
				"${cross_prefix}strip" $sharedlib
			done
			sed "s/$/\r/" LICENSE >LICENSE.txt
			7z a -mx=9 "$archive" *.dll LICENSE.txt && remove_path -f LICENSE.txt
		fi
	else
		do_make_install "" "install_dev"
	fi
	unset CC
	unset AR
	unset RANLIB
	change_dir "$src_dir"
}

build_libogg() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/xiph/ogg.git
	change_dir "$src_dir"
}

build_libvorbis() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/vorbis.git
	change_dir "$src_dir/vorbis_git"
	generic_configure "--disable-docs --disable-examples --disable-oggtest"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libopus() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/opus.git opus_git origin/main
	change_dir "$src_dir/opus_git"
	generic_configure "--disable-doc --disable-extra-programs --disable-stack-protector"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libspeexdsp() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/speexdsp.git
	change_dir "$src_dir/speexdsp_git"
	generic_configure "--disable-examples"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libspeex() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/speex.git
	change_dir "$src_dir/speex_git"
	export SPEEXDSP_CFLAGS="-I$mingw_w64_x86_64_prefix/include"
	export SPEEXDSP_LIBS="-L$mingw_w64_x86_64_prefix/lib -lspeexdsp" # 'configure' somehow can't find SpeexDSP with 'pkg-config'.
	generic_configure "--disable-binaries"                           # If you do want the libraries, then 'speexdec.exe' needs 'LDFLAGS=-lwinmm'.
	do_make_and_make_install
	unset SPEEXDSP_CFLAGS
	unset SPEEXDSP_LIBS
	change_dir "$src_dir"
}

build_libtheora() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/xiph/theora.git
	change_dir "$src_dir/theora_git"
	generic_configure "--disable-doc --disable-spec --disable-oggtest --disable-vorbistest --disable-examples --disable-asm" # disable asm: avoid [theora @ 0x1043144a0]error in unpack_block_qpis in 64 bit... [OK OS X 64 bit tho...]
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libsndfile() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/libsndfile/libsndfile.git
	change_dir "$src_dir/libsndfile_git"
	generic_configure "--disable-sqlite --disable-external-libs --disable-full-suite"
	do_make_and_make_install
	if [[ ! -f $mingw_w64_x86_64_prefix/lib/libgsm.a ]]; then
		install -m644 src/GSM610/gsm.h "$mingw_w64_x86_64_prefix/include/gsm.h" || exit 1
		install -m644 src/GSM610/.libs/libgsm.a "$mingw_w64_x86_64_prefix/lib/libgsm.a" || exit 1
	else
		echo -e "already installed GSM 6.10 ..."
	fi
	change_dir "$src_dir"
}

build_mpg123() {
	change_dir "$src_dir"
	do_svn_checkout svn://scm.orgis.org/mpg123/trunk mpg123_svn r5008 # avoid Think again failure
	change_dir "$src_dir/mpg123_svn"
	generic_configure_make_install
	change_dir "$src_dir"
}

build_lame() {
	change_dir "$src_dir"
	do_svn_checkout https://svn.code.sf.net/p/lame/svn/trunk/lame lame_svn r6525 # anything other than r6525 fails
	change_dir "$src_dir/lame_svn"
	# sed -i.bak '1s/^\xEF\xBB\xBF//' libmp3lame/i386/nasm.h # Remove a UTF-8 BOM that breaks nasm if it's still there; should be fixed in trunk eventually https://sourceforge.net/p/lame/patches/81/
	generic_configure "--enable-nasm --enable-libmpg123"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_twolame() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/njh/twolame.git twolame_git "origin/main"
	change_dir "$src_dir/twolame_git"
	if [[ ! -f Makefile.am.bak ]]; then # Library only, front end refuses to build for some reason with git master
		sed -i.bak "/^SUBDIRS/s/ frontend.*//" Makefile.am || exit 1
	fi
	cpu_count=1 # maybe can't handle it http://betterlogic.com/roger/2017/07/mp3lame-woe/ comments
	generic_configure_make_install
	cpu_count=$original_cpu_count
	change_dir "$src_dir"
}

# build_fdk-aac() {
# local checkout_dir=fdk-aac_git
#     if [[ -n $fdk_aac_git_checkout_version ]]; then
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
	change_dir "$src_dir"
	generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-0.1.6.tar.gz
	change_dir "$src_dir"
	generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz
	change_dir "$src_dir"
}

build_libilbc() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/TimothyGu/libilbc.git libilbc_git
	change_dir "$src_dir/libilbc_git"
	do_cmake "-B build -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libmodplug() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/Konstanty/libmodplug.git
	change_dir "libmodplug_git"
	sed -i.bak 's/__declspec(dllexport)//' "$mingw_w64_x86_64_prefix/include/libmodplug/modplug.h" #strip DLL import/export directives
	sed -i.bak 's/__declspec(dllimport)//' "$mingw_w64_x86_64_prefix/include/libmodplug/modplug.h"
	if [[ ! -f "configure" ]]; then
		autoreconf -fiv || exit 1
		automake --add-missing || exit 1
	fi
	generic_configure_make_install # or could use cmake I guess
	change_dir "$src_dir"
}

build_libgme() {
	# do_git_checkout https://bitbucket.org/mpyne/game-music-emu.git
	change_dir "$src_dir"
	download_and_unpack_file https://bitbucket.org/mpyne/game-music-emu/downloads/game-music-emu-0.6.3.tar.xz
	change_dir "$src_dir/game-music-emu-0.6.3"
	do_cmake_and_install "-DENABLE_UBSAN=0"
	change_dir "$src_dir"
}

build_mingw_std_threads() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/meganz/mingw-std-threads.git # it needs std::mutex too :|
	change_dir "$src_dir/mingw-std-threads_git"
	cp *.h "$mingw_w64_x86_64_prefix/include"
	change_dir "$src_dir"
}

build_opencv() {
	build_mingw_std_threads
	#do_git_checkout https://github.com/opencv/opencv.git # too big :|
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/opencv/opencv/archive/3.4.5.zip opencv-3.4.5
	create_dir "$src_dir/opencv-3.4.5/build"
	#change_dir "$src_dir/opencv-3.4.5"
	apply_patch "file://$WINPATCHDIR/opencv.detection_based.patch"
	change_dir "$src_dir"
	change_dir "$src_dir/opencv-3.4.5/build"
	# could do more here, it seems to think it needs its own internal libwebp etc...
	cpu_count=1
	do_cmake_from_build_dir "$src_dir/opencv-3.4.5" "-DWITH_FFMPEG=0 -DOPENCV_GENERATE_PKGCONFIG=1 -DHAVE_DSHOW=0" # https://stackoverflow.com/q/40262928/32453, no pkg config by default on "windows", who cares ffmpeg
	do_make_and_make_install
	cp unix-install/opencv.pc "$PKG_CONFIG_PATH"
	cpu_count=$original_cpu_count
	change_dir "$src_dir"
}

build_facebooktransform360() {
	build_opencv
	change_dir "$src_dir"
	do_git_checkout https://github.com/facebook/transform360.git
	change_dir "$src_dir/transform360_git"
	apply_patch "file://$WINPATCHDIR/transform360.pi.diff" -p1
	#change_dir "$src_dir"
	change_dir "$src_dir/transform360_git/Transform360"
	do_cmake ""
	sed -i.bak "s/isystem/I/g" CMakeFiles/Transform360.dir/includes_CXX.rsp # weird stdlib.h error
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libbluray() {
	change_dir "$src_dir"
	do_git_checkout https://code.videolan.org/videolan/libbluray.git
	activate_meson
	change_dir "$src_dir/libbluray_git"
	apply_patch "https://raw.githubusercontent.com/m-ab-s/mabs-patches/master/libbluray/0001-dec-prefix-with-libbluray-for-now.patch" -p1
	local meson_options="setup build -Denable_examples=false -Dbdj_jar=disabled --wrap-mode=default"
	# get_local_meson_cross_with_propeties
	meson_options+=" --cross-file=$(get_meson_cross_file)"
	do_meson "$meson_options"
	do_ninja_and_ninja_install # "CPPFLAGS=\"-Ddec_init=libbr_dec_init\""
	sed -i.bak 's/-lbluray.*/-lbluray -lstdc++ -lssp -lgdi32/' "$PKG_CONFIG_PATH/libbluray.pc"
	deactivate
	change_dir "$src_dir"
}

build_libbs2b() {
	change_dir "$src_dir"
	download_and_unpack_file https://downloads.sourceforge.net/project/bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.gz
	change_dir "$src_dir/libbs2b-3.1.0"
	apply_patch "file://$WINPATCHDIR/libbs2b.patch"
	sed -i.bak "s/AC_FUNC_MALLOC//" configure.ac # #270
	export LIBS=-lm                              # avoid pow failure linux native
	generic_configure_make_install
	unset LIBS
	change_dir "$src_dir"
}

build_libsoxr() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/chirlu/soxr.git soxr_git
	change_dir "$src_dir/soxr_git"
	do_cmake_and_install "-DWITH_OPENMP=0 -DBUILD_TESTS=0 -DBUILD_EXAMPLES=0"
	change_dir "$src_dir"
}

build_libflite() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/festvox/flite.git flite_git
	change_dir "$src_dir/flite_git"
	apply_patch "file://$WINPATCHDIR/flite-2.1.0_mingw-w64-fixes.patch"
	if [[ ! -f main/Makefile.bak ]]; then
		sed -i.bak "s/cp -pd/cp -p/" main/Makefile # friendlier cp for OS X
	fi
	generic_configure "--bindir=$mingw_w64_x86_64_prefix/bin --with-audio=none"
	do_make
	if [[ ! -f $mingw_w64_x86_64_prefix/lib/libflite.a ]]; then
		cp -rf ./build/x86_64-mingw32/lib/libflite* "$mingw_w64_x86_64_prefix/lib/"
		cp -rf include "$mingw_w64_x86_64_prefix/include/flite"
		# cp -rf ./bin/*.exe $mingw_w64_x86_64_prefix/bin # if want .exe's uncomment
	fi
	change_dir "$src_dir"
}

build_libsnappy() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/google/snappy.git snappy_git # got weird failure once 1.1.8
	change_dir "$src_dir/snappy_git"
	do_cmake_and_install "-DBUILD_BINARY=OFF -DCMAKE_BUILD_TYPE=Release -DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF" # extra params from deadsix27 and from new cMakeLists.txt content
	remove_path -f "$mingw_w64_x86_64_prefix/lib/libsnappy.dll.a"                                                               # unintall shared :|
	change_dir "$src_dir"
}

build_vamp_plugin() {
	#download_and_unpack_file https://code.soundsoftware.ac.uk/attachments/download/2691/vamp-plugin-sdk-2.10.0.tar.gz
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/vamp-plugins/vamp-plugin-sdk/archive/refs/tags/vamp-plugin-sdk-v2.10.zip vamp-plugin-sdk-vamp-plugin-sdk-v2.10
	#cd vamp-plugin-sdk-2.10.0
	change_dir "$src_dir/vamp-plugin-sdk-vamp-plugin-sdk-v2.10"
	apply_patch "file://$WINPATCHDIR/vamp-plugin-sdk-2.10_static-lib.diff"
	if [[ ! -f src/vamp-sdk/PluginAdapter.cpp.bak ]]; then
		sed -i.bak "s/#include <mutex>/#include <mingw.mutex.h>/" src/vamp-sdk/PluginAdapter.cpp
	fi
	if [[ ! -f configure.bak ]]; then # Fix for "'M_PI' was not declared in this scope" (see https://stackoverflow.com/a/29264536).
		sed -i.bak "s/c++11/gnu++11/" configure
		sed -i.bak "s/c++11/gnu++11/" Makefile.in
	fi
	do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-programs"
	# TODO: Allow shared library build
	do_make "install-static" # No need for 'do_make_install', because 'install-static' already has install-instructions.
	change_dir "$src_dir"
}

build_fftw() {
	change_dir "$src_dir"
	download_and_unpack_file http://fftw.org/fftw-3.3.10.tar.gz
	change_dir "$src_dir/fftw-3.3.10"
	# TODO: Allow shared library build
	generic_configure "--disable-doc --prefix=$mingw_w64_x86_64_prefix --host=$host_target --enable-static --disable-shared"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libsamplerate() {
	# I think this didn't work with ubuntu 14.04 [too old automake or some odd] :|
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/erikd/libsamplerate.git
	# but OS X can't use 0.1.9 :|
	# rubberband can use this, but uses speex bundled by default [any difference? who knows!]
	change_dir "$src_dir"
}

build_librubberband() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/breakfastquay/rubberband.git rubberband_git 18c06ab8c431854056407c467f4755f761e36a8e
	change_dir "$src_dir/rubberband_git"
	apply_patch "file://$WINPATCHDIR/rubberband_git_static-lib.diff" # create install-static target
	do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-ladspa"
	# TODO: Allow shared library build
	do_make "install-static AR=${cross_prefix}ar" # No need for 'do_make_install', because 'install-static' already has install-instructions.
	sed -i.bak 's/-lrubberband.*$/-lrubberband -lfftw3 -lsamplerate -lstdc++/' "$PKG_CONFIG_PATH/rubberband.pc"
	change_dir "$src_dir"
}

build_frei0r() {
	#do_git_checkout https://github.com/dyne/frei0r.git
	#cd frei0r_git
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/dyne/frei0r/archive/refs/tags/v2.3.3.tar.gz frei0r-2.3.3
	change_dir "$src_dir/frei0r-2.3.3"
	sed -i.bak 's/-arch i386//' CMakeLists.txt # OS X https://github.com/dyne/frei0r/issues/64
	do_cmake_and_install "-DWITHOUT_OPENCV=1"  # XXX could look at this more...

	create_dir "$src_dir/redist" # Strip and pack shared libraries.
	if [ "$bits_target" = 32 ]; then
		local arch=x86
	else
		local arch=x86_64
	fi
	archive="$src_dir/redist/frei0r-plugins-${arch}-$(git describe --tags).7z"
	if [[ ! -f "$archive.done" ]]; then
		for sharedlib in "$mingw_w64_x86_64_prefix"/lib/frei0r-1/*.dll; do
			# shellcheck disable=SC2086
			"${cross_prefix}strip" $sharedlib
		done
		for doc in AUTHORS ChangeLog COPYING README.md; do
			sed "s/$/\r/" $doc >"$mingw_w64_x86_64_prefix/lib/frei0r-1/$doc.txt"
		done
		7z a -mx=9 "$archive $mingw_w64_x86_64_prefix/lib/frei0r-1" && remove_path -f "$mingw_w64_x86_64_prefix/lib/frei0r-1/*.txt"
		touch "$archive.done" # for those with no 7z so it won't restrip every time
	fi
	change_dir "$src_dir"
}

build_svt_hevc() {
	if [[ "$bits_target" != "32" ]] && [[ $build_svt_hevc = y ]]; then
		change_dir "$src_dir"
		do_git_checkout https://github.com/OpenVisualCloud/SVT-HEVC.git
		create_dir "$src_dir/SVT-HEVC_git/release"
		do_cmake_from_build_dir "$src_dir/SVT-HEVC_git" "-DCMAKE_BUILD_TYPE=Release"
		do_make_and_make_install
		change_dir "$src_dir"
	fi
}

build_svt_vp9() {
	if [[ "$bits_target" != "32" ]] && [[ $build_svt_vp9 = y ]]; then
		change_dir "$src_dir"
		do_git_checkout https://github.com/OpenVisualCloud/SVT-VP9.git
		change_dir "$src_dir/SVT-VP9_git/Build"
		do_cmake_from_build_dir "$src_dir/SVT-VP9_git" "-DCMAKE_BUILD_TYPE=Release"
		do_make_and_make_install
		change_dir "$src_dir"
	fi
}

build_cpuinfo() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/pytorch/cpuinfo.git
	change_dir "$src_dir/cpuinfo_git"
	do_cmake_and_install # builds included cpuinfo bugged
	change_dir "$src_dir"
}

build_svt_av1() {
	if [[ "$bits_target" != "32" ]]; then
		build_cpuinfo
		change_dir "$src_dir"
		do_git_checkout https://gitlab.com/AOMediaCodec/SVT-AV1.git SVT-AV1_git
		change_dir "$src_dir/SVT-AV1_git"
		do_cmake "-B build -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DUSE_CPUINFO=SYSTEM" # -DSVT_AV1_LTO=OFF if fails try adding this
		do_ninja_and_ninja_install
		change_dir "$src_dir"
	fi
}

build_vidstab() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/georgmartius/vid.stab.git vid.stab_git
	change_dir "$src_dir/vid.stab_git"
	do_cmake_and_install "-DUSE_OMP=0" # '-DUSE_OMP' is on by default, but somehow libgomp ('cygwin_local_install/lib/gcc/i686-pc-cygwin/5.4.0/include/omp.h') can't be found, so '-DUSE_OMP=0' to prevent a compilation error.
	change_dir "$src_dir"
}

build_libmysofa() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/hoene/libmysofa.git libmysofa_git "origin/main"
	change_dir "$src_dir/libmysofa_git"
	local cmake_params="-DBUILD_TESTS=0"
	do_cmake "$cmake_params"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libcaca() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/cacalabs/libcaca.git libcaca_git 813baea7a7bc28986e474541dd1080898fac14d7
	change_dir "$src_dir/libcaca_git"
	apply_patch "file://$WINPATCHDIR/libcaca_git_stdio-cruft.diff" -p1 # Fix WinXP incompatibility.
	change_dir "$src_dir/libcaca_git/caca"
	sed -i.bak "s/__declspec(dllexport)//g" *.h # get rid of the declspec lines otherwise the build will fail for undefined symbols
	sed -i.bak "s/__declspec(dllimport)//g" *.h
	change_dir "$src_dir/libcaca_git"
	generic_configure "--libdir=$mingw_w64_x86_64_prefix/lib --disable-csharp --disable-java --disable-cxx --disable-python --disable-ruby --disable-doc --disable-cocoa --disable-ncurses"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libdecklink() {
	change_dir "$src_dir"
	do_git_checkout https://gitlab.com/m-ab-s/decklink-headers.git decklink-headers_git 47d84f8d272ca6872b5440eae57609e36014f3b6
	change_dir "$src_dir/decklink-headers_git"
	do_make_install "PREFIX=$mingw_w64_x86_64_prefix"
	change_dir "$src_dir"
}

build_zvbi() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/zapping-vbi/zvbi.git zvbi_git
	change_dir "$src_dir/zvbi_git"
	generic_configure "--disable-dvb --disable-bktr --disable-proxy --disable-nls --without-doxygen --disable-examples --disable-tests --without-libiconv-prefix"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_fribidi() {
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz # Get c2man errors building from repo
	change_dir "$src_dir/fribidi-1.0.16"
	generic_configure "--disable-debug --disable-deprecated --disable-docs"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libsrt() {
	# do_git_checkout https://github.com/Haivision/srt.git # might be able to use these days...?
	change_dir "$src_dir"
	download_and_unpack_file https://github.com/Haivision/srt/archive/v1.5.4.tar.gz srt-1.5.4
	change_dir "$src_dir/srt-1.5.4"
	apply_patch "file://$WINPATCHDIR/srt.app.patch" -p1
	# CMake Warning at CMakeLists.txt:893 (message):
	#   On MinGW, some C++11 apps are blocked due to lacking proper C++11 headers
	#   for <thread>.  FIX IF POSSIBLE.
	do_cmake "-DUSE_ENCLIB=gnutls -DENABLE_SHARED=OFF -DENABLE_CXX11=OFF"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libass() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/libass/libass.git
	change_dir "$src_dir"
}

build_vulkan() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/KhronosGroup/Vulkan-Headers.git Vulkan-Headers_git v1.4.326
	change_dir "$src_dir/Vulkan-Headers_git"
	do_cmake_and_install "-DCMAKE_BUILD_TYPE=Release -DVULKAN_HEADERS_ENABLE_MODULE=NO -DVULKAN_HEADERS_ENABLE_TESTS=NO -DVULKAN_HEADERS_ENABLE_INSTALL=YES"
	change_dir "$src_dir"
}

build_vulkan_loader() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/BtbN/Vulkan-Shim-Loader.git Vulkan-Shim-Loader.git 9657ca8e395ef16c79b57c8bd3f4c1aebb319137
	change_dir "$src_dir/Vulkan-Shim-Loader.git"
	do_git_checkout https://github.com/KhronosGroup/Vulkan-Headers.git Vulkan-Headers v1.4.326
	do_cmake_and_install "-DCMAKE_BUILD_TYPE=Release -DVULKAN_SHIM_IMPERSONATE=ON"
	change_dir "$src_dir"
}

build_libunwind() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/libunwind/libunwind.git libunwind_git
	change_dir "$src_dir/libunwind_git"
	autoreconf -i
	# TODO: Allow shared library build
	do_configure "--host=x86_64-linux-gnu --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libxxhash() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/Cyan4973/xxHash.git xxHash_git dev
	change_dir "$src_dir/xxHash_git"
	do_cmake "-S build/cmake -B build -DCMAKE_BUILD_TYPE=release -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_spirv-cross() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/KhronosGroup/SPIRV-Cross.git SPIRV-Cross_git b26ac3fa8bcfe76c361b56e3284b5276b23453ce
	change_dir "$src_dir/SPIRV-Cross_git"
	# TODO: Allow shared library build
	do_cmake "-B build -GNinja -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_SHARED=OFF -DCMAKE_BUILD_TYPE=Release -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_FORCE_PIC=ON -DSPIRV_CROSS_ENABLE_CPP=OFF"
	do_ninja_and_ninja_install
	mv "$PKG_CONFIG_PATH/spirv-cross-c.pc" "$PKG_CONFIG_PATH/spirv-cross-c-shared.pc"
	change_dir "$src_dir"
}

build_libdovi() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/quietvoid/dovi_tool.git dovi_tool_git
	change_dir "$src_dir/dovi_tool_git"
	if [[ ! -e $mingw_w64_x86_64_prefix/lib/libdovi.a ]]; then
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . "$HOME/.cargo/env" && rustup update && rustup target add x86_64-pc-windows-gnu # rustup self uninstall
		wget https://github.com/quietvoid/dovi_tool/releases/download/2.3.1/dovi_tool-2.3.1-x86_64-pc-windows-msvc.zip
		unzip -o dovi_tool-2.3.1-x86_64-pc-windows-msvc.zip -d "$mingw_w64_x86_64_prefix/bin"
		remove_path -f dovi_tool-2.3.1-x86_64-pc-windows-msvc.zip
		unset PKG_CONFIG_PATH
		change_dir "$src_dir/dovi_tool_git/dolby_vision"
		cargo install cargo-c --features=vendored-openssl
		export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
		# TODO: Allow shared library build
		cargo cinstall --release --prefix="$mingw_w64_x86_64_prefix" --libdir="$mingw_w64_x86_64_prefix/lib" --library-type=staticlib --target x86_64-pc-windows-gnu
		change_dir "$src_dir"
	else
		echo -e "libdovi already installed"
	fi
	change_dir "$src_dir"
}

build_shaderc() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/google/shaderc.git shaderc_git 3a44d5d7850da3601aa43d523a3d228f045fb43d
	change_dir "$src_dir/shaderc_git"
	./utils/git-sync-deps
	# TODO: Allow shared library build
	do_cmake "-B build -DCMAKE_BUILD_TYPE=release -GNinja -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_TESTS=ON -DSPIRV_SKIP_TESTS=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DENABLE_EXCEPTIONS=ON -DENABLE_GLSLANG_BINARIES=OFF -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_TOOLS_BUILD_STATIC=ON -DBUILD_SHARED_LIBS=OFF"
	do_ninja_and_ninja_install
	cp build/libshaderc_util/libshaderc_util.a "$mingw_w64_x86_64_prefix/lib"
	sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/shaderc_combined.pc"
	sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/shaderc_static.pc"
	change_dir "$src_dir"
}

build_lcms() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/ImageMagick/lcms.git
	change_dir "$src_dir"
}

build_libplacebo() {
	#build_vulkan_loader
	#build_lcms
	#build_libunwind
	#build_libxxhash
	#build_spirv-cross
	#build_libdovi
	#build_shaderc
	change_dir "$src_dir"
	do_git_checkout https://code.videolan.org/videolan/libplacebo.git libplacebo_git #515da9548ad734d923c7d0988398053f87b454d5
	activate_meson
	change_dir "$src_dir/libplacebo_git"
	apply_patch "file://$WINPATCHDIR/fix_libplacebo_absolute_path.patch" -p1 # latest meson version wont work without patch
	git submodule update --init --recursive --depth=1 --filter=blob:none
	local config_options=""
	local config_options+=" -Dvulkan-registry=$mingw_w64_x86_64_prefix/share/vulkan/registry/vk.xml"
	# TODO: Allow shared library build
	local meson_options="setup build -Ddemos=false -Dbench=false -Dfuzz=false -Dvulkan=enabled -Dvk-proc-addr=disabled -Dshaderc=enabled -Dglslang=disabled -Dc_link_args=-static -Dcpp_link_args=-static $config_options" # https://mesonbuild.com/Dependencies.html#shaderc trigger use of shaderc_combined
	# get_local_meson_cross_with_propeties
	meson_options+=" --cross-file=$(get_meson_cross_file)"
	do_meson "$meson_options"
	do_ninja_and_ninja_install
	sed -i.bak 's/-lplacebo.*$/-lplacebo -lm -lshlwapi -lunwind -lxxhash -lversion -lstdc++/' "$PKG_CONFIG_PATH/libplacebo.pc"
	deactivate
	change_dir "$src_dir"
}

build_libaribb24() {
	change_dir "$src_dir"
	do_git_checkout_and_make_install https://github.com/nkoriyama/aribb24
	change_dir "$src_dir"
}

build_libaribcaption() {
	if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then
		change_dir "$src_dir"
		do_git_checkout https://github.com/xqq/libaribcaption
		mkdir libaribcaption/build
		change_dir "$src_dir/libaribcaption/build"
		do_cmake_from_build_dir "$src_dir/libaribcaption" "-DCMAKE_BUILD_TYPE=Release"
		do_make_and_make_install
		change_dir "$src_dir"
	fi
}

build_libxavs() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/Distrotech/xavs.git xavs_git
	change_dir "$src_dir/xavs_git"
	if [[ ! -f Makefile.bak ]]; then
		sed -i.bak "s/O4/O2/" configure # Change CFLAGS.
	fi
	apply_patch "https://patch-diff.githubusercontent.com/raw/Distrotech/xavs/pull/1.patch" -p1
	do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix" # see https://github.com/rdp/ffmpeg-windows-build-helpers/issues/3
	do_make_and_make_install "$compiler_flags"
	if [[ -d NUL ]]; then
		remove_path -f NUL # cygwin causes windows explorer to not be able to delete this folder if it has this oddly named file in it...
	fi
	change_dir "$src_dir"
}

build_libxavs2() {
	if [[ $host_target != 'i686-w64-mingw32' ]]; then
		change_dir "$src_dir"
		do_git_checkout https://github.com/pkuvcl/xavs2.git xavs2_git
		change_dir "$src_dir/xavs2_git"
		for file in "${PWD}/build/linux/already_configured"*; do
			if [[ -e "$file" ]]; then
				curl "https://github.com/pkuvcl/xavs2/compare/master...1480c1:xavs2:gcc14/pointerconversion.patch" | git apply -v
			fi
		done
		change_dir "$src_dir/xavs2_git/build/linux"
		do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$mingw_w64_x86_64_prefix --enable-strip" # --enable-pic
		do_make_and_make_install
		change_dir "$src_dir"
	fi
}

build_libdavs2() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/pkuvcl/davs2.git
	change_dir "$src_dir/davs2_git/build/linux"
	if [[ $host_target == "i686-w64-mingw32" ]]; then
		do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$mingw_w64_x86_64_prefix --enable-pic --disable-asm"
	else
		do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$mingw_w64_x86_64_prefix --enable-pic"
	fi
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libxvid() {
	change_dir "$src_dir"
	download_and_unpack_file https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz xvidcore
	change_dir "$src_dir/xvidcore/build/generic"
	apply_patch "file://$WINPATCHDIR/xvidcore-1.3.7_static-lib.patch"
	do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix" # no static option...
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libvpx() {
	change_dir "$src_dir"
	do_git_checkout https://chromium.googlesource.com/webm/libvpx.git libvpx_git "origin/main"
	change_dir "$src_dir/libvpx_git"
	# apply_patch file://$WINPATCHDIR/vpx_160_semaphore.patch -p1 # perhaps someday can remove this after 1.6.0 or mingw fixes it LOL
	if [[ "$bits_target" = "32" ]]; then
		local config_options="--target=x86-win32-gcc"
	else
		local config_options="--target=x86_64-win64-gcc"
	fi
	export CROSS="$cross_prefix"
	# VP8 encoder *requires* sse3 support
	# TODO: Allow shared library build
	do_configure "$config_options --prefix=$mingw_w64_x86_64_prefix --enable-ssse3 --enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth --extra-cflags=-fno-asynchronous-unwind-tables --extra-cflags=-mstackrealign" # fno for Error: invalid register for .seh_savexmm
	do_make_and_make_install
	unset CROSS
	change_dir "$src_dir"
}

build_libaom() {
	change_dir "$src_dir"
	do_git_checkout https://aomedia.googlesource.com/aom aom_git
	if [ "$bits_target" = "32" ]; then
		local config_options="-DCMAKE_TOOLCHAIN_FILE=../build/cmake/toolchains/x86-mingw-gcc.cmake -DAOM_TARGET_CPU=x86"
	else
		local config_options="-DCMAKE_TOOLCHAIN_FILE=../build/cmake/toolchains/x86_64-mingw-gcc.cmake -DAOM_TARGET_CPU=x86_64"
	fi
	create_dir "$src_dir/aom_git/aom_build"
	change_dir "$src_dir/aom_git/aom_build"
	do_cmake_from_build_dir "$src_dir/aom_git" "$config_options"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_dav1d() {
	change_dir "$src_dir"
	do_git_checkout https://code.videolan.org/videolan/dav1d.git libdav1d
	activate_meson
	change_dir "$src_dir/libdav1d"
	if [[ $bits_target == 32 || $bits_target == 64 ]]; then   # XXX why 64???
		apply_patch "file://$WINPATCHDIR/david_no_asm.patch" -p1 # XXX report
	fi
	cpu_count=1 # XXX report :|
	local meson_options="setup build -Denable_tests=false -Denable_examples=false"
	# get_local_meson_cross_with_propeties
	meson_options+=" --cross-file=$(get_meson_cross_file)"
	do_meson "$meson_options"
	do_ninja_and_ninja_install
	copy_path "$src_dir/build/src/libdav1d.a" "$mingw_w64_x86_64_prefix/lib" || exit 1 # avoid 'run ranlib' weird failure, possibly older meson's https://github.com/mesonbuild/meson/issues/4138 :|
	cpu_count=$original_cpu_count
	deactivate
	change_dir "$src_dir"
}

build_avisynth() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/AviSynth/AviSynthPlus.git avisynth_git
	create_dir "$src_dir/avisynth_git/avisynth-build"
	change_dir "$src_dir/avisynth_git/avisynth-build"
	do_cmake_from_build_dir "$src_dir/avisynth_git" -DHEADERS_ONLY:bool=on
	do_make "$compiler_flags VersionGen install"
	change_dir "$src_dir"
}

build_libvvenc() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/fraunhoferhhi/vvenc.git libvvenc_git
	change_dir "$src_dir/libvvenc_git"
	do_cmake "-B build -DCMAKE_BUILD_TYPE=Release -DVVENC_ENABLE_LINK_TIME_OPT=OFF -DVVENC_INSTALL_FULLFEATURE_APP=ON -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libvvdec() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/fraunhoferhhi/vvdec.git libvvdec_git
	change_dir "$src_dir/libvvdec_git"
	do_cmake "-B build -DCMAKE_BUILD_TYPE=Release -DVVDEC_ENABLE_LINK_TIME_OPT=OFF -DVVDEC_INSTALL_VVDECAPP=ON -GNinja"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_libx265() {
	change_dir "$src_dir"
	local checkout_dir=x265
	local remote="https://bitbucket.org/multicoreware/x265_git"
	if [[ -n $x265_git_checkout_version ]]; then
		checkout_dir+="_$x265_git_checkout_version"
		do_git_checkout "$remote" "$checkout_dir" "$x265_git_checkout_version"
	else
		if [[ $prefer_stable = "n" ]]; then
			checkout_dir+="_unstable"
			do_git_checkout "$remote" "$checkout_dir" "origin/master"
		fi
		if [[ $prefer_stable = "y" ]]; then
			do_git_checkout "$remote" "$checkout_dir" "origin/stable"
		fi
	fi
	change_dir "$checkout_dir"

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
	cmake_params+=" -DEXTRA_LIB='$(pwd)/libx265_main10.a;$(pwd)/libx265_main12.a'"
	do_cmake_from_build_dir ../source "$cmake_params"
	do_make
	mv libx265.a libx265_main.a
		"${cross_prefix}ar" -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
	make install # force reinstall in case you just switched from stable to not :|
	change_dir "$src_dir"
}

build_libopenh264() {
	change_dir "$src_dir"
	do_git_checkout "https://github.com/cisco/openh264.git" openh264_git v2.6.0 #75b9fcd2669c75a99791 # wels/codec_api.h weirdness
	change_dir "$src_dir/openh264_git"
	sed -i.bak "s/_M_X64/_M_DISABLED_X64/" codec/encoder/core/inc/param_svc.h # for 64 bit, avoid missing _set_FMA3_enable, it needed to link against msvcrt120 to get this or something weird?
	if [[ $bits_target == 32 ]]; then
		local arch=i686 # or x86?
	else
		local arch=x86_64
	fi
	# TODO: Allow shared library build
	do_make "$compiler_flags OS=mingw_nt ARCH=$arch ASM=yasm install-static"
	change_dir "$src_dir"
}

build_libx264() {
	change_dir "$src_dir"
	local checkout_dir="x264"
	if [[ $build_x264_with_libav == "y" ]]; then
		# TODO: Allow shared library build
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
		do_git_checkout "https://code.videolan.org/videolan/x264.git" $checkout_dir "origin/stable"
	fi
	change_dir $checkout_dir
	if [[ ! -f configure.bak ]]; then # Change CFLAGS.
		sed -i.bak "s/O3 -/O2 -/" configure
	fi
	# TODO: Allow shared library build
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
		sed -i.bak "s_\\, ./x264_, wine ./x264_" Makefile     # in case they have wine auto-run disabled http://askubuntu.com/questions/344088/how-to-ensure-wine-does-not-auto-run-exe-files
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
	change_dir "$src_dir"
}

build_lsmash() { # an MP4 library
	change_dir "$src_dir"
	do_git_checkout https://github.com/l-smash/l-smash.git l-smash
	change_dir l-smash
	do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix"
	do_make_and_make_install
	change_dir "$src_dir"
}

build_libdvdread() {
	build_libdvdcss
	change_dir "$src_dir"
	download_and_unpack_file http://dvdnav.mplayerhq.hu/releases/libdvdread-4.9.9.tar.xz # last revision before 5.X series so still works with MPlayer
	change_dir "$src_dir/libdvdread-4.9.9"
	# XXXX better CFLAGS here...
	generic_configure "CFLAGS=-DHAVE_DVDCSS_DVDCSS_H LDFLAGS=-ldvdcss --enable-dlfcn" # vlc patch: "--enable-libdvdcss" # XXX ask how I'm *supposed* to do this to the dvdread peeps [svn?]
	do_make_and_make_install
	sed -i.bak 's/-ldvdread.*/-ldvdread -ldvdcss/' "$PKG_CONFIG_PATH/dvdread.pc"
	change_dir "$src_dir"
}

build_libdvdnav() {
	change_dir "$src_dir"
	download_and_unpack_file http://dvdnav.mplayerhq.hu/releases/libdvdnav-4.2.1.tar.xz # 4.2.1. latest revision before 5.x series [?]
	change_dir "$src_dir/libdvdnav-4.2.1"
	if [[ ! -f ./configure ]]; then
		./autogen.sh
	fi
	generic_configure_make_install
	sed -i.bak 's/-ldvdnav.*/-ldvdnav -ldvdread -ldvdcss -lpsapi/' "$PKG_CONFIG_PATH/dvdnav.pc" # psapi for dlfcn ... [hrm?]
	change_dir "$src_dir"
}

build_libdvdcss() {
	change_dir "$src_dir"
	generic_download_and_make_and_install https://download.videolan.org/pub/videolan/libdvdcss/1.2.13/libdvdcss-1.2.13.tar.bz2
}

build_libjpeg_turbo() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/libjpeg-turbo/libjpeg-turbo libjpeg-turbo_git "origin/main"
	change_dir "$src_dir/libjpeg-turbo_git"
	local cmake_params="-DENABLE_SHARED=0 -DCMAKE_ASM_NASM_COMPILER=yasm"
		cmake_params+=" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake"
		local target_proc=AMD64
		if [ "$bits_target" = "32" ]; then
			target_proc=X86
		fi
		cat >toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ${target_proc})
set(CMAKE_C_COMPILER ${cross_prefix}gcc)
set(CMAKE_RC_COMPILER ${cross_prefix}windres)
EOF
	do_cmake_and_install "$cmake_params"
	change_dir "$src_dir"
}

build_libproxy() {
	# NB this lacks a .pc file still
	change_dir "$src_dir"
	download_and_unpack_file https://libproxy.googlecode.com/files/libproxy-0.4.11.tar.gz
	change_dir "$src_dir/libproxy-0.4.11"
	sed -i.bak "s/= recv/= (void *) recv/" libmodman/test/main.cpp # some compile failure
	do_cmake_and_install
	change_dir "$src_dir"
}

build_lua() {
	change_dir "$src_dir"
	download_and_unpack_file https://www.lua.org/ftp/lua-5.3.3.tar.gz
	change_dir "$src_dir/lua-5.3.3"
	export AR="${cross_prefix}ar rcu"                                    # needs rcu parameter so have to call it out different :|
	# TODO: Allow shared library build
	do_make "CC=${cross_prefix}gcc RANLIB=${cross_prefix}ranlib generic" # generic == "generic target" and seems to result in a static build, no .exe's blah blah the mingw option doesn't even build liblua.a
	unset AR
	do_make_install "INSTALL_TOP=$mingw_w64_x86_64_prefix" "generic install"
	cp etc/lua.pc "$PKG_CONFIG_PATH"
	change_dir "$src_dir"
}

build_libhdhomerun() {
	exit 1 # still broken unfortunately, for cross compile :|
	change_dir "$src_dir"
	download_and_unpack_file https://download.silicondust.com/hdhomerun/libhdhomerun_20150826.tgz libhdhomerun
	change_dir "$src_dir/libhdhomerun"
	do_make "CROSS_COMPILE=$cross_prefix OS=Windows_NT"
	change_dir "$src_dir"
}

build_meson_cross_jsoncpp() {
	local cpu_family="x86_64"
	if [ "$bits_target" = 32 ]; then
		cpu_family="x86"
	fi
	remove_path -fv "${src_dir}/jsoncpp/meson-cross-jsoncpp.mingw.txt"
	cat >>"${src_dir}/jsoncpp/meson-cross-jsoncpp.mingw.txt" <<EOF
[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'  
default_library = 'both'
backend = 'ninja'
prefix = '$mingw_w64_x86_64_prefix'
libdir = 'lib'
includedir = 'include'

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
pkg_config_libdir = '$mingw_w64_x86_64_prefix/lib/pkgconfig'
EOF
}

build_libjsoncpp() {
	change_dir "$src_dir"
	do_git_checkout https://github.com/open-source-parsers/jsoncpp jsoncpp
	change_dir "$src_dir/jsoncpp"
	if [[ "$BUILD_FORCE" -eq 1 ]]; then
		remove_path -rf already_*
	fi
	local config_options=""
	local meson_options="setup build $config_options"
	build_meson_cross_jsoncpp
	meson_options+=" --cross-file=${src_dir}/jsoncpp/meson-cross-jsoncpp.mingw.txt"
	do_meson "$meson_options"
	do_ninja_and_ninja_install
	change_dir "$src_dir"
}

build_dvbtee_app() {
	build_iconv # said it needed it
	build_curl  # it "can use this" so why not
	#  build_libhdhomerun # broken but possible dependency apparently :|
	change_dir "$src_dir"
	do_git_checkout https://github.com/mkrufky/libdvbtee.git libdvbtee_git
	change_dir "$src_dir/libdvbtee_git"
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
	change_dir "$src_dir"
}

build_qt() {
	build_libjpeg_turbo # libjpeg a dependency [?]
	unset CFLAGS        # it makes something of its own first, which runs locally, so can't use a foreign arch, or maybe it can, but not important enough: http://stackoverflow.com/a/18775859/32453 XXXX could look at this
	#download_and_unpack_file http://pkgs.fedoraproject.org/repo/pkgs/qt/qt-everywhere-opensource-src-4.8.7.tar.gz/d990ee66bf7ab0c785589776f35ba6ad/qt-everywhere-opensource-src-4.8.7.tar.gz # untested
	#cd qt-everywhere-opensource-src-4.8.7
	# download_and_unpack_file http://download.qt-project.org/official_releases/qt/5.1/5.1.1/submodules/qtbase-opensource-src-5.1.1.tar.xz qtbase-opensource-src-5.1.1 # not officially supported seems...so didn't try it
	change_dir "$src_dir"
	download_and_unpack_file http://pkgs.fedoraproject.org/repo/pkgs/qt/qt-everywhere-opensource-src-4.8.5.tar.gz/1864987bdbb2f58f8ae8b350dfdbe133/qt-everywhere-opensource-src-4.8.5.tar.gz
	change_dir qt-everywhere-opensource-src-4.8.5
	apply_patch "file://$WINPATCHDIR/imageformats.patch"
	apply_patch "file://$WINPATCHDIR/qt-win64.patch"
	# vlc's configure options...mostly
	# TODO: Allow shared library build
	do_configure "-static -release -fast -no-exceptions -no-stl -no-sql-sqlite -no-qt3support -no-gif -no-libmng -qt-libjpeg -no-libtiff -no-qdbus -no-openssl -no-webkit -sse -no-script -no-multimedia -no-phonon -opensource -no-scripttools -no-opengl -no-script -no-scripttools -no-declarative -no-declarative-debug -opensource -no-s60 -host-little-endian -confirm-license -xplatform win32-g++ -device-option CROSS_COMPILE=$cross_prefix -prefix $mingw_w64_x86_64_prefix -prefix-install -nomake examples"
	if [ ! -f 'already_qt_maked_k' ]; then
		make sub-src -j "$(get_cpu_count)"
		make install sub-src                                                                      # let it fail, baby, it still installs a lot of good stuff before dying on mng...? huh wuh?
		cp ./plugins/imageformats/libqjpeg.a "$mingw_w64_x86_64_prefix/lib" || exit 1             # I think vlc's install is just broken to need this [?]
		cp ./plugins/accessible/libqtaccessiblewidgets.a "$mingw_w64_x86_64_prefix/lib" || exit 1 # this feels wrong...
		# do_make_and_make_install "sub-src" # sub-src might make the build faster? # complains on mng? huh?
		touch 'already_qt_maked_k'
	fi
	# vlc needs an adjust .pc file? huh wuh?
	sed -i.bak 's/Libs: -L${libdir} -lQtGui/Libs: -L${libdir} -lcomctl32 -lqjpeg -lqtaccessiblewidgets -lQtGui/' "$PKG_CONFIG_PATH/QtGui.pc" # sniff
	change_dir "$src_dir"
	reset_cflags
}

build_vlc() {
	# currently broken, since it got too old for libavcodec and I didn't want to build its own custom one yet to match, and now it's broken with gcc 5.2.0 seemingly
	# call out dependencies here since it's a lot, plus hierarchical FTW!
	# should be ffmpeg 1.1.1 or some odd?
	echo -e "not building vlc, broken dependencies or something weird"
	return
	# vlc's own dependencies:
	build_lua
	build_libdvdread
	build_libdvdnav
	build_libx265
	build_libjpeg_turbo
	build_ffmpeg
	build_qt
	change_dir "$src_dir"
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
	remove_path -f "$(find . -name "*.exe")"                                                                                                 # try to force a rebuild...though there are tons of .a files we aren't rebuilding as well FWIW...:|
	remove_path -f already_ran_make*                                                                                                         # try to force re-link just in case...
	do_make
	# do some gymnastics to avoid building the mozilla plugin for now [couldn't quite get it to work]
	#sed -i.bak 's_git://git.videolan.org/npapi-vlc.git_https://github.com/rdp/npapi-vlc.git_' Makefile # this wasn't enough...following lines instead...
	sed -i.bak "s/package-win-common: package-win-install build-npapi/package-win-common: package-win-install/" Makefile
	sed -i.bak "s/.*cp .*builddir.*npapi-vlc.*//g" Makefile
	make package-win-common # not do_make, fails still at end, plus this way we get new vlc.exe's
	echo -e "


     vlc success, created a file like ${PWD}/vlc-xxx-git/vlc.exe



"
	change_dir "$src_dir"
	unset DVDREAD_LIBS
}

reset_cflags() {
	export CFLAGS=$original_cflags
}

reset_cppflags() {
	export CPPFLAGS=$original_cppflags
}

reset_ldflags() {
	export LDFLAGS=$original_ldflags
}

get_meson_cross_file() {
	if [[ ! -e "$src_dir/$target_name-meson-cross.mingw.txt" ]]; then
		local cpu_family="x86_64"
		if [ "$bits_target" = 32 ]; then
			cpu_family="x86"
		fi
		# TODO: Allow shared library build
	cat >>"$src_dir/$target_name-meson-cross.mingw.txt" <<EOF
[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'  
default_library = 'static'  
prefer_static = 'true'
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
	fi
	echo "$src_dir/$target_name-meson-cross.mingw.txt"
}

get_local_meson_cross_with_propeties() {
	local local_dir="$1"
	if [[ -z $local_dir ]]; then
		local_dir="."
	fi
	copy_path "$src_dir/$target_name-meson-cross.mingw.txt" "$local_dir"
	cat >>meson-cross.mingw.txt <<EOF
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
	export LDFLAGS='-lpthread -ldvdnav -ldvdread -ldvdcss'                 # not compat with newer dvdread possibly? huh wuh?
	export CFLAGS=-DHAVE_DVDCSS_DVDCSS_H
	do_configure "--enable-cross-compile --host-cc=cc --cc=${cross_prefix}gcc --windres=${cross_prefix}windres --ranlib=${cross_prefix}ranlib --ar=${cross_prefix}ar --as=${cross_prefix}as --nm=${cross_prefix}nm --enable-runtime-cpudetection --extra-cflags=$CFLAGS --with-dvdnav-config=$mingw_w64_x86_64_prefix/bin/dvdnav-config --disable-dvdread-internal --disable-libdvdcss-internal --disable-w32threads --enable-pthreads --extra-libs=-lpthread --enable-debug --enable-ass-internal --enable-dvdread --enable-dvdnav --disable-libvpx-lavc" # haven't reported the ldvdcss thing, think it's to do with possibly it not using dvdread.pc [?] XXX check with trunk
	# disable libvpx didn't work with its v1.5.0 some reason :|
	unset LDFLAGS
	reset_cflags
	sed -i.bak "s/HAVE_PTHREAD_CANCEL 0/HAVE_PTHREAD_CANCEL 1/g" config.h # mplayer doesn't set this up right?
	touch -t 201203101513 config.h                                        # the above line change the modify time for config.h--forcing a full rebuild *every time* yikes!
	# try to force re-link just in case...
	remove_path -f *.exe
	remove_path -f already_ran_make* # try to force re-link just in case...
	do_make
	cp mplayer.exe mplayer_debug.exe
	"${cross_prefix}strip" mplayer.exe
	echo -e "built ${PWD}/{mplayer,mencoder,mplayer_debug}.exe"
	change_dir "$src_dir"
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
	# TODO: Allow shared library build
	generic_configure "  --cross-prefix=${cross_prefix} --target-os=MINGW32 --extra-cflags=-Wno-format --static-build --static-bin --disable-oss-audio --extra-ldflags=-municode --disable-x11 --sdl-cfg=${cross_prefix}sdl-config"
	./check_revision.sh
	# I seem unable to pass 3 libs into the same config line so do it with sed...
	sed -i.bak "s/EXTRALIBS=.*/EXTRALIBS=-lws2_32 -lwinmm -lz/g" config.mak
	change_dir src
	do_make "$compiler_flags"
	change_dir ..
	remove_path -f ./bin/gcc/MP4Box* # try and force a relink/rebuild of the .exe
	change_dir applications/mp4box
	remove_path -f already_ran_make* # ??
	do_make "$compiler_flags"
	change_dir ../..
	# copy it every time just in case it was rebuilt...
	cp ./bin/gcc/MP4Box ./bin/gcc/MP4Box.exe # it doesn't name it .exe? That feels broken somehow...
	echo -e "built $(readlink -f ./bin/gcc/MP4Box.exe)"
	change_dir "$src_dir"
}

build_libMXF() {
	download_and_unpack_file https://sourceforge.net/projects/ingex/files/1.0.0/libMXF/libMXF-src-1.0.0.tgz "libMXF-src-1.0.0"
	change_dir libMXF-src-1.0.0
	apply_patch "file://$WINPATCHDIR/libMXF.diff"
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
	change_dir "$src_dir"
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
	change_dir "$src_dir"
}

build_chromaprint() {
	echo -e "$mingw_w64_x86_64_prefix"
	build_fftw
	do_git_checkout https://github.com/acoustid/chromaprint.git chromaprint
	change_dir chromaprint
	# TODO: Allow shared library build
	cat >toolchain.cmake <<EOF
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