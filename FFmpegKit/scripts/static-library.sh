#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292

if (( BASH_VERSINFO[0] < 5 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 5+ is required." >&2
    exit 1
fi

set -e
OUTPUT_LIB="$1"
AR_CMD="$2"
RANLIB_CMD="$3"
FFMPEG_BUILD_DIR="$4"
FFMPEG_KIT_LIBRARIES="$5"

verbose=false

truthy() {
    case "$1" in
        true|1|T|t|True|TRUE|y|Y|yes|Yes|YES|on|On|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

echo_log() {
	if truthy "$verbose"; then
		echo "$1"
	fi
}

for arg in "$@"; do
	case "$arg" in
		-v|--verbose|-verbose|--v)
			verbose=true
			set -x
			;;
		-e|--exclude=*)
			# comma separated list of libraries to exclude from bundling
			ex_libs="${arg#*=}"
			IFS=',' read -ra EXCLUDE_LIBS <<< "$ex_libs"
			;;
	esac
done

is_excluded() {
	local lib="$1"
	for excluded_lib in "${EXCLUDE_LIBS[@]}"; do
		if [[ "$lib" == "$excluded_lib" ]]; then
			return 0
		fi
	done
	return 1
}

echo "Generating monolithic static library: $OUTPUT_LIB"
rm -f lib.mri bundle_manifest.txt libs.txt

echo "CREATE $OUTPUT_LIB" >lib.mri
if [ -f "libffmpegkit.a" ]; then
	echo "ADDLIB libffmpegkit.a" >>lib.mri
fi

raw_libs_to_keep=""
if [ -n "$FFMPEG_KIT_LIBRARIES" ]; then
    # Convert semicolon-delimited list to array, handling quoted strings
    echo_log "  [STATIC-LIB] Using BUNDLE_LIBRARIES from CMake: $FFMPEG_KIT_LIBRARIES"
    # Remove surrounding quotes and split by semicolon into array
    clean_libs="${FFMPEG_KIT_LIBRARIES%\"}"
    clean_libs="${clean_libs#\"}"
    IFS=';' read -ra deps <<< "$clean_libs"
else
    # Fallback to original behavior if BUNDLE_LIBRARIES not provided
    echo_log "  [STATIC-LIB] Analyzing dependencies in $FFMPEG_BUILD_DIR..."
    export PKG_CONFIG_PATH="$FFMPEG_BUILD_DIR/lib/pkgconfig"
    deps=$(pkg-config --static --libs libavdevice libavfilter libavformat libavcodec libswresample libswscale libavutil)
		mapfile -t deps <<< "$deps"
fi


is_system_lib() {
	local name="$1"
	if [[ "$name" =~ ^(m|c|pthread|dl|rt|stdc\+\+|gcc|gcc_s|atomic|z|log|android|ole32|shlwapi|gdi32|winmm|kernel32|setupapi|ws2_32|advapi32|user32|shell32|bcrypt|ncrypt|psapi|resolv|selinux|sepol|util|X11|xcb|Xext|Xau|Xdmcp|python)$ ]]; then
		return 0
	fi
	return 1
}

is_system_path() {
	local p="$1"
	# Skip standard Linux system library directories
	if [[ "$p" == "/usr/lib"* ]] ||
		[[ "$p" == "/opt/homebrew/lib"* ]] ||
		[[ "$p" == "/lib"* ]] ||
		[[ "$p" == "/lib64"* ]] ||
		[[ "$p" == "/usr/lib64"* ]] ||
		[[ "$p" == *"/sysroot/usr/lib/"* ]]; then
		return 0
	fi
	return 1
}

process_library_path() {
	local lib_path="$1"
	local name="$2"
	if is_system_path "$lib_path"; then
		echo_log "  [SKIPPING SYSTEM] $lib_path"
		raw_libs_to_keep="$raw_libs_to_keep -l$name"
		return
	fi

	filename=$(basename "$lib_path")
	dirname=$(dirname "$lib_path")
	extension="${filename##*.}"

	case "$extension" in
	a | lib)
		if [ -h "$lib_path" ]; then
			target=$(readlink -f "$lib_path")
			if [[ "$target" == *.so || "$target" == *.dll || "$target" == *.dylib ]]; then
				echo "  [FOUND SHARED VIA SYMLINK] $filename -> $(basename "$target")"
				echo "$target" >> bundle_manifest.txt
				raw_libs_to_keep="$raw_libs_to_keep -l$name"
				return
			fi
		fi
		lib_base="${filename%.*}"
		lib_base="${lib_base%.dll}"
		base_name="${lib_base#lib}"
		bin_dir="$(dirname "$dirname")/bin"
		found_dll=""

		for d in "$bin_dir" "$dirname"; do
			if [ -f "$d/${base_name}.dll" ]; then
				found_dll="$d/${base_name}.dll"
				break
			elif [ -f "$d/lib${base_name}.dll" ]; then
				found_dll="$d/lib${base_name}.dll"
				break
			fi
		done

		if [ -n "$found_dll" ]; then
			if is_excluded "$name"; then
				echo_log "  [EXCLUDED] $filename"
				return
			fi
			echo "  [FOUND SHARED] $(basename "$found_dll")"
			echo "$(readlink -f "$found_dll" 2>/dev/null || echo "$found_dll")" >>bundle_manifest.txt
			raw_libs_to_keep="$raw_libs_to_keep -l$name"
		else
			echo_log "  [MERGING STATIC] $filename"
			echo "ADDLIB $lib_path" >>lib.mri
		fi
		;;
	so | dll | dylib)
		if [ -h "$lib_path" ]; then
			target=$(readlink -f "$lib_path")
			if [[ "$target" == *.a || "$target" == *.lib ]]; then
				echo_log "  [SKIPPING SYMLINK] $filename -> $target (Static target)"
				return
			fi
		fi
		if is_excluded "$name"; then
			echo_log "  [EXCLUDED] $filename"
			return
		fi
		echo "  [FOUND SHARED] $filename"
		echo "$(readlink -f "$lib_path" 2>/dev/null || echo "$lib_path")" >>bundle_manifest.txt
		raw_libs_to_keep="$raw_libs_to_keep -l$name"
		;;
	esac
}

for flag in "${deps[@]}"; do
	echo_log "  [DEBUG] Processing: $flag"
	case "$flag" in
	-l*)
		echo_log "  [DEBUG] $flag is -l flag"
		name=${flag#-l}
		name=${name#:}
		name=${name%.a}

		if is_system_lib "$name"; then
			raw_libs_to_keep="$raw_libs_to_keep -l$name"
			continue
		fi

		lib_path=$(grep -m1 "pkgcfg_lib_FFMPEG_${name}:FILEPATH=" CMakeCache.txt | cut -d'=' -f2 || echo "")

		if [[ -n "$lib_path" && "$lib_path" != *"NOTFOUND" ]]; then
			process_library_path "$lib_path" "$name"
		else
			raw_libs_to_keep="$raw_libs_to_keep -l$name"
		fi
		;;
	-Wl,* | -pthread)
		echo_log "  [DEBUG] $flag is -Wl or -pthread"
		raw_libs_to_keep="$raw_libs_to_keep $flag"
		;;
	*)
		if [[ -f "$flag" ]]; then
			echo_log "  [DEBUG] $flag is file"
			name=$(basename "$flag")
			name=${name%.a}
			name=${name#lib}
			process_library_path "$flag" "$name"
		fi
		;;
	esac
done

echo "SAVE" >>lib.mri
echo "END" >>lib.mri
$AR_CMD -M <lib.mri
$RANLIB_CMD "$OUTPUT_LIB"
rm -f lib.mri

clean_libs=$(echo "$raw_libs_to_keep" | awk '{for (i=1;i<=NF;i++) if (!seen[$i]++) printf("%s%s", $i, OFS)}' | gsed 's/ *$//')
if test -f ffmpegkit.pc; then
  perl -i -pe "s|FFMPEG_KIT_EXT_LIBS|\Q$clean_libs\E|g" ffmpegkit.pc
fi
