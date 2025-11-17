#!/bin/bash

# shellcheck disable=SC2317
# shellcheck disable=SC1091
# shellcheck disable=SC2120

#echo -e ${SCRIPTDIR}/source.sh
#echo -e "${SCRIPTDIR}/variable.sh"

source "${SCRIPTDIR}/source.sh"

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
		sudo chmod -R 755 "$path"
}

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
			execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
				chown -R "$USER":"$USER" "$path"
			execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "true" \
				sudo chmod -R 755 "$path"
			execute "INFO: removing path: '$path'" "ERROR: unable to remove path '$path'" "true" \
				rm "$options" "$path"
		else
			echo -e "INFO: path ${path} does not exist" 1>>"$LOG_FILE" 2>&1
		fi
	done
}

change_dir() {
	local path="$1"

	if [ -z "$path" ]; then
		error_exit "ERROR: path argument is required"
	fi

	if [[ -e "$path" ]]; then
		execute "INFO: changing to path: '$path'" "ERROR: unable to cd to directory '$path'" "true" \
			cd "$path"
		if [[ ! -r "$path" ]] || [[ ! -w "$path" ]] || [[ ! -x "$path" ]]; then
			execute "INFO: updating path permissions: '$path'" "ERROR: unable to update permissions on '$path'" "false" \
				sudo chmod -R 755 "$path"
		fi
	else
		echo -e "INFO: path ${path} does not exist" 1>>"$LOG_FILE" 2>&1
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
		sudo chmod -R 755 "$destination_path"
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
			((enabled++))
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
			((enabled++))
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
			((enabled++))
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
			((enabled++))
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

		((counter++))
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

		((counter++))
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

		((counter++))
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

		((counter++))
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
	if [ "$(uname)" == "Darwin" ]; then
		echo -e "$(sysctl -n hw.logicalcpu)"
	else
		echo -e "$cpu_count"
	fi
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
	if [ "$(uname)" == "Darwin" ]; then
		export SED_INLINE="sed -i .tmp"
	else
		export SED_INLINE="sed -i"
	fi
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
	if [[ $OSTYPE == darwin* ]]; then
		box_memory_size_bytes=20000000000 # 20G fake it out for now :|
	else
		local ram_kilobytes=$(grep MemTotal /proc/meminfo | awk '{print $2}')
		local swap_kilobytes=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
		box_memory_size_bytes=$((ram_kilobytes * 1024 + swap_kilobytes * 1024))
	fi
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
	if [[ $OSTYPE == darwin* ]]; then
		check_packages+=('glibtoolize') # homebrew special :|
	else
		check_packages+=('libtoolize') # the rest of the world
	fi
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
		if hash "${cmake_binary}" &>/dev/null; then
			cmake_version="$("${cmake_binary}" --version | sed "s#${cmake_binary}##" | head -n 1 | tr -d '[:digit:].')"
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
	local yasm_version="$("${yasm_binary}" --version | sed "s#${yasm_binary}##" | head -n 1 | tr -d '[:digit:].')"
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
		echo -e "svn checking out to $to_dir"
		if [[ -z "$desired_revision" ]]; then
			svn checkout "$repo_url" "$to_dir".tmp --non-interactive --trust-server-cert || exit 1
		else
			svn checkout -r "$desired_revision" "$repo_url" "$to_dir".tmp || exit 1
		fi
		mv "$to_dir".tmp "$to_dir"
	else
		change_dir "$to_dir"
		echo -e "not svn Updating $to_dir since usually svn repo's aren't updated frequently enough..."
		# XXX accomodate for desired revision here if I ever uncomment the next line...
		# svn up
		change_dir ..
	fi
}

# params: git url, to_dir
retry_git_or_die() { # originally from https://stackoverflow.com/a/76012343/32453
	local RETRIES_NO=50
	local RETRY_DELAY=30
	local repo_url=$1
	local to_dir=$2
	local desired_branch=$3
	for i in $(seq 1 $RETRIES_NO); do
		echo -e "Downloading (via git clone) $to_dir from $repo_url"
		remove_path -rf "$to_dir".tmp # just in case it was interrupted previously...not sure if necessary...
		create_dir "$to_dir"
		git ls-remote --exit-code --heads "$repo_url" "$desired_branch" >/dev/null 2>&1
		branch_exists=$?
		if [[ $branch_exists == 0 ]]; then
			git clone --depth 1 -b "$desired_branch" "$repo_url" "$to_dir" --recurse-submodules && break
		else
			echo -e "Failed to get branch $desired_branch for $repo_url. Getting master instead"
			git clone --depth 1 -b "master" "$repo_url" "$to_dir" --recurse-submodules && break
		fi
		# get here -> failure
		[[ $i -eq $RETRIES_NO ]] && echo -e "Failed to execute git cmd $repo_url $to_dir after $RETRIES_NO retries" && exit 1
		echo -e "sleeping before retry git"
		sleep ${RETRY_DELAY}
	done
	# prevent partial checkout confusion by renaming it only after success
	#mv $to_dir.tmp $to_dir
	echo -e "done git cloning branch $desired_branch to $to_dir"
}

do_git_checkout() {
	local repo_url="$1"
	local to_dir="$2"
	if [[ -z $to_dir ]]; then
		to_dir=$(basename "$repo_url" | sed s/\.git/_git/) # http://y/abc.git -> abc_git
	fi
	local desired_branch="$3"
	if [ ! -d "$to_dir" ]; then
		retry_git_or_die "$repo_url" "$to_dir" "$desired_branch"
		change_dir "$to_dir"
	else
		change_dir "$to_dir"
		if [[ $git_get_latest = "y" ]]; then
			git fetch # want this for later...
		else
			echo -e "not doing git get latest pull for latest code $to_dir" # too slow'ish...
		fi
	fi
	change_dir ..
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
	local touch_postfix="_$3"
	if [[ "$configure_name" = "" ]]; then
		configure_name="./configure"
	fi
	local cur_dir2=$(pwd)
	local english_name=$(basename "$cur_dir2")
	local touch_name=$(get_small_touchfile_name "already_configured$touch_postfix" "$configure_options $configure_name")
	if [ ! -f "$touch_name" ]; then
		# make uninstall # does weird things when run under ffmpeg src so disabled for now...

		echo -e "configuring $english_name ($PWD) as $ PKG_CONFIG_PATH=$PKG_CONFIG_PATH PATH=$mingw_bin_path:\$PATH $configure_name $configure_options" # say it now in case bootstrap fails etc.
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
		remove_path -f already_*    # reset
		chmod u+x "$configure_name" # In non-windows environments, with devcontainers, the configuration file doesn't have execution permissions
		# shellcheck disable=SC2086
		nice -n 5 $configure_name $configure_options || {
			echo -e "failed configure $english_name"
			exit 1
		} # less nicey than make (since single thread, and what if you're running another ffmpeg nice build elsewhere?)
		touch -- "$touch_name"
		echo -e "doing preventative make clean"
		nice make clean -j "$(get_cpu_count)" # sometimes useful when files change, etc.
	#else
	#  echo -e "already configured $(basename $cur_dir2)"
	fi
}
# 1. extra_make_options
# 2. touch_postfix
do_make() {
	local extra_make_options="$1"
	local touch_postfix="_$2"
	extra_make_options="$extra_make_options -j $(get_cpu_count)"
	local cur_dir2=$(pwd)
	local touch_name=$(get_small_touchfile_name "already_ran_make$touch_postfix" "$extra_make_options")

	if [ ! -f "$touch_name" ]; then
		echo -e
		echo -e "Making $cur_dir2 as $ PATH=$mingw_bin_path:\$PATH make $extra_make_options"
		echo -e
		if [ ! -f configure ]; then
			nice make clean -j "$(get_cpu_count)" # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
		fi
		# shellcheck disable=SC2086
		nice make $extra_make_options || exit 1
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
	local extra_make_install_options="$1"
	local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
	local touch_postfix="_$3"
	if [[ -z $override_make_install_options ]]; then
		local make_install_options="install $extra_make_install_options"
	else
		local make_install_options="$override_make_install_options $extra_make_install_options"
	fi
	local touch_name=$(get_small_touchfile_name "already_ran_make_install$touch_postfix" "$make_install_options")
	if [ ! -f "$touch_name" ]; then
		echo -e "make installing $(pwd) as $ PATH=$mingw_bin_path:\$PATH make $make_install_options"
		# shellcheck disable=SC2086
		nice make $make_install_options || exit 1
		touch "$touch_name" || exit 1
	fi
}
# 1. extra_args
# 2. source_dir
# 3. touch_postfix
do_cmake() {
	extra_args="$1"
	local build_from_dir="$2"
	local touch_postfix="_$3"
	if [[ -z $build_from_dir ]]; then
		build_from_dir="."
	fi
	local touch_name=$(get_small_touchfile_name "already_ran_cmake$touch_postfix" "$extra_args")

	if [ ! -f "$touch_name" ]; then
		remove_path -f already_* # reset so that make will run again if option just changed
		local cur_dir2=$(pwd)
		local config_options=""
		if [ "$bits_target" = 32 ]; then
			local config_options+="-DCMAKE_SYSTEM_PROCESSOR=x86"
		else
			local config_options+="-DCMAKE_SYSTEM_PROCESSOR=AMD64"
		fi
		echo -e "doing cmake in $cur_dir2 with PATH=$mingw_bin_path:\$PATH with extra_args=$extra_args like this:"
		if [[ $compiler_flavors != "native" ]]; then
			local command="${build_from_dir} -DENABLE_STATIC_RUNTIME=1 -DBUILD_SHARED_LIBS=0 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_FIND_ROOT_PATH=$mingw_w64_x86_64_prefix -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_RANLIB=${cross_prefix}ranlib -DCMAKE_C_COMPILER=${cross_prefix}gcc -DCMAKE_CXX_COMPILER=${cross_prefix}g++ -DCMAKE_RC_COMPILER=${cross_prefix}windres -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $config_options $extra_args"
		else
			local command="${build_from_dir} -DENABLE_STATIC_RUNTIME=1 -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $config_options $extra_args"
		fi
		echo -e "doing ${cmake_command}  -G\"Unix Makefiles\" $command"
		# shellcheck disable=SC2086
		nice -n 5 $cmake_command -G"Unix Makefiles" $command || exit 1
		touch "$touch_name" || exit 1
	fi
}
# 1. extra_args
# 2. source_dir
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
	source_dir="$1"
	extra_args="$2"
	touch_postfix="$3"
	do_cmake "$extra_args" "$source_dir" "$touch_postfix"
	do_make_and_make_install "$extra_args" "" "$touch_postfix"
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
	else
		source tutorial_env/bin/activate
	fi
	change_dir ..
}
# 1. configure_options
# 2. configure_name
# 2. configure_env
# 4. touch_postfix
do_meson() {
	local configure_options="$1 --unity=off"
	local configure_name="$2"
	local configure_env="$3"
	local touch_postfix="_$4"
	local configure_noclean=""
	if [[ "$configure_name" = "" ]]; then
		configure_name="meson"
	fi
	local cur_dir2=$(pwd)
	local english_name=$(basename "$cur_dir2")
	local touch_name=$(get_small_touchfile_name "already_built_meson$touch_postfix" "$configure_options $configure_name $LDFLAGS $CFLAGS")
	if [ ! -f "$touch_name" ]; then
		if [ "$configure_noclean" != "noclean" ]; then
			make clean # just in case
		fi
		remove_path -f already_* # reset
		echo -e "Using meson: $english_name ($PWD) as $ PATH=$PATH ${configure_env} $configure_name $configure_options"
		#env
		"$configure_name" "$configure_options" || exit 1
		touch -- "$touch_name"
		make clean # just in case
	else
		echo -e "Already used meson $(basename "$cur_dir2")"
	fi
}
# 1. extra_args
# 2. touch_postfix
generic_meson() {
	local extra_configure_options="$1"
	local touch_postfix="$2"
	create_dir build
	do_meson "--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib --buildtype=release --default-library=static $extra_configure_options" "$touch_postfix" # --cross-file=${BASEDIR}/meson-cross.mingw.txt
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
	local touch_postfix="_$2"
	do_ninja "$extra_ninja_options" "$touch_postfix"
	local touch_name=$(get_small_touchfile_name "already_ran_make_install$touch_postfix" "$extra_ninja_options")
	if [ ! -f "$touch_name" ]; then
		echo -e "ninja installing $(pwd) as $PATH=$PATH ninja -C build install $extra_make_options"
		ninja -C build install || exit 1
		touch "$touch_name" || exit 1
	fi
}

# 1. touch_postfix
do_ninja() {
	local touch_postfix="_$1"
	local extra_make_options=" -j $(get_cpu_count)"
	local cur_dir2=$(pwd)
	local touch_name=$(get_small_touchfile_name "already_ran_make$touch_postfix" "${extra_make_options}")

	if [ ! -f "$touch_name" ]; then
		echo -e
		echo -e "ninja-ing $cur_dir2 as $ PATH=$PATH ninja -C build $extra_make_options"
		echo -e
		ninja -C build "$extra_make_options" || exit 1
		touch "$touch_name" || exit 1 # only touch if the build was OK
	else
		echo -e "already did ninja $(basename "$cur_dir2")"
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
	if [[ ! -e $patch_done_name ]]; then
		if [[ -f $patch_name ]]; then
			remove_path -rf "$patch_name" || exit 1 # remove old version in case it has been since updated on the server...
		fi
		curl -4 --retry 5 "$url" -O --fail || echo -e_and_exit "unable to download patch file $url"
		echo -e "applying patch $patch_name"
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
		english_name=$(basename "$url" | sed s/\.tar\.*//) # remove .tar.xx, take last part of url
	fi
	local extra_configure_options="$3"
	download_and_unpack_file "$url" "$english_name"
	change_dir "$english_name" || echo -e "unable to cd, may need to specify dir it will unpack to as parameter"
	exit 1
	generic_configure "$extra_configure_options"
	do_make_and_make_install
	change_dir ..
}

generic_configure_make_install() {
	generic_configure # no parameters, force myself to break it up if needed
	do_make_and_make_install
}

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
	# Check if string consists only of digits, optionally with leading + or -
	if [[ "$str" =~ ^[-+]?[0-9]+$ ]]; then
		return 0 # Is integer
	else
		return 1 # Not integer
	fi
}

is_alpha() {
	local str="$1"
	if [[ "$str" =~ ^[a-zA-Z]+$ ]]; then
		return 0
	else
		return 1
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
	echo "-1" # Not found
	return 1
}
