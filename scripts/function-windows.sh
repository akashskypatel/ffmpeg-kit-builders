#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292

if (( BASH_VERSINFO[0] < 4 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 4+ is required." >&2
    exit 1
fi

: "${LOG_FILE:=/dev/null}"

find_all_build_exes() {
	local found=""
	# NB that we're currently in the prebuilt dir...
	for file in $(find . -name ffmpeg.exe) $(find . -name ffmpeg_g.exe) $(find . -name ffplay.exe) $(find . -name ffmpeg) $(find . -name ffplay) $(find . -name ffprobe) $(find . -name MP4Box.exe) $(find . -name mplayer.exe) $(find . -name mencoder.exe) $(find . -name avconv.exe) $(find . -name avprobe.exe) $(find . -name x264.exe) $(find . -name writeavidmxf.exe) $(find . -name writeaviddv50.exe) $(find . -name rtmpdump.exe) $(find . -name x265.exe) $(find . -name ismindex.exe) $(find . -name dvbtee.exe) $(find . -name boxdumper.exe) $(find . -name muxer.exe) $(find . -name remuxer.exe) $(find . -name timelineeditor.exe) $(find . -name lwcolor.auc) $(find . -name lwdumper.auf) $(find . -name lwinput.aui) $(find . -name lwmuxer.auf) $(find . -name vslsmashsource.dll); do
		found="$found $(readlink -f "$file")"
	done

	# bash recursive glob fails here again?
	for file in $(find . -name vlc.exe | grep -- -); do
		found="$found $(readlink -f "$file")"
	done
	echo -e "$found" # pseudo return value...
}

set_toolchain_paths() {
	export PATH="${PATH}:${toolchain_bin_path}:${dependency_install_prefix}/bin"
	export CC="${cross_prefix}gcc"
	export AR="$(realpath "${cross_prefix}ar")"
	export AS="$(realpath "${cross_prefix}as")"
	export NM="$(realpath "${cross_prefix}nm")"
	export RANLIB="$(realpath "${cross_prefix}ranlib")"
	export LD="$(realpath "${cross_prefix}ld")"
	export STRIP="$(realpath "${cross_prefix}strip")"
	export CXX="$(realpath "${cross_prefix}g++")"
}

check_cross_compiler_bin() {
	local gcc_bin="$toolchain_bin_path/$host_target-gcc"
	if [[ -f $gcc_bin ]]; then
		echo -e "INFO: MinGW compiler already installed for $host_name, not re-installing..." | tee -a "$LOG_FILE"
		return 0 # early exit they've selected at least some kind by this point...
	fi
	return 1
}

check_cross_compiler() {
	if [[ $(check_cross_compiler_bin) != 0 ]]; then
		install_cross_compiler
	fi
}

install_cross_compiler() {
	echo -e "INFO: Building (or already built) MinGW-w64 cross-compiler(s)..." | tee -a "$LOG_FILE"
	create_dir "$work_dir"/cross_compilers
	change_dir "$work_dir"/cross_compilers

	unset CFLAGS # don't want these "windows target" settings used the compiler itself since it creates executables to run on the local box (we have a parameter allowing them to set them for the script "all builds" basically)
	# pthreads version to avoid having to use cvs for it
	echo -e "Starting to download and build cross compile version of gcc [requires working internet access] with thread count $gcc_cpu_count..." >>"$LOG_FILE"
	echo -e "" >>"$LOG_FILE"

	# --disable-shared allows c++ to be distributed at all...which seemed necessary for some random dependency which happens to use/require c++...
	local zeranoe_script_name=mingw-w64-build
	local zeranoe_script_options="--gcc-branch=releases/gcc-14 --mingw-w64-branch=master --binutils-branch=binutils-2_44-branch" # --cached-sources"
	if iswindows && [[ ! -f ../$win32_gcc ]]; then
		echo -e "Building win32 cross compiler..." >>"$LOG_FILE"
		download_gcc_build_script "$zeranoe_script_name"
		if [[ "$(uname)" =~ (5.1) ]]; then # Avoid using secure API functions for compatibility with msvcrt.dll on Windows XP.
			gsed -i "s/ --enable-secure-api//" "$zeranoe_script_name"
		fi
		# shellcheck disable=SC2086
		CFLAGS='-O2 -pipe' CXXFLAGS='-O2 -pipe' nice ./"$zeranoe_script_name" "$zeranoe_script_options" i686 || exit_message 1 "cannot set up i686 cross compiler script" # i686 option needs work to implement
		if [[ ! -f ../$win32_gcc ]]; then
			exit_message 1 "failure building 32 bit gcc? Recommend nuke prebuilt (rm -rf prebuilt) and start over..."
		fi
		if [[ ! -f ../cross_compilers/mingw-w64-i686/i686-w64-mingw32/lib/libmingwex.a ]]; then
			exit_message 1 "failure building mingwex? 32 bit"
		fi
		if [[ $host_arch == "x86_64" && ! -f ../$win64_gcc ]]; then
			echo -e "Building win64 x86_64 cross compiler..." >>"$LOG_FILE"
			download_gcc_build_script "$zeranoe_script_name"
			# shellcheck disable=SC2086
			CFLAGS='-O3 -pipe' CXXFLAGS='-O3 -pipe' nice ./"$zeranoe_script_name" "$zeranoe_script_options" x86_64 || exit_message 1 "could not update cross compiler script for x86_64"
			if [[ ! -f ../$win64_gcc ]]; then
				exit_message 1 "failure building 64 bit gcc? Recommend nuke prebuilt (rm -rf prebuilt) and start over..."
			fi
			if [[ ! -f ../cross_compilers/mingw-w64-x86_64/x86_64-w64-mingw32/lib/libmingwex.a ]]; then
				exit_message 1 "failure building mingwex? 64 bit"
			fi
		fi
		change_dir "$work_dir/cross_compilers/src"
	fi
	# rm -f build.log # leave resultant build log...sometimes useful...
	reset_cflags
	change_dir ..
	echo -e "INFO: Done building (or already built) MinGW-w64 cross-compiler(s) successfully..." | tee -a "$LOG_FILE"
}

configure_ffmpeg_kit() {
	echo -e "INFO: Configuring ffmpeg kit" | tee -a "$LOG_FILE"
	local type_postfix="$build_ffmpeg_kit_type"
	
	iswindows && fix_pkgconfig_flags

	if truthy "$build_force"; then
		remove_path -rf "$ffmpeg_kit_src_dir"/already_configured_*
		remove_path -rf "$ffmpeg_kit_install"
		remove_path -rf "$ffmpeg_kit_src_dir"/build
	fi

	create_dir "$ffmpeg_kit_install"

	export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${ffmpeg_install_prefix}/lib/pkgconfig"
	set_toolchain_paths

	reset_allflags
	local local_cflags="${CFLAGS} -static -static-libgcc -static-libstdc++ -I${ffmpeg_install_prefix}/include -L${ffmpeg_install_prefix}/lib -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"
	local local_cxxfalgs="${CXXFLAGS} -static -static-libgcc -static-libstdc++ -I${ffmpeg_install_prefix}/include -L${ffmpeg_install_prefix}/lib -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"
	
	change_dir "${ffmpeg_kit_src_dir}"
	make distclean > >(redirect_output) 2>&1

	export CFLAGS="${local_cflags}"
	export CXXFLAGS="${local_cxxfalgs}"
	export LDFLAGS="${LDFLAGS//-static /} -static-libgcc -static-libstdc++ -Wl,-Bstatic"

	local cmake_params="-DCMAKE_SYSTEM_NAME=Windows \
-DCMAKE_C_COMPILER=$CC \
-DCMAKE_CXX_COMPILER=$CXX \
-DFFMPEG_SRC_DIR=\"$ffmpeg_source_dir\" \
-DFFMPEG_BUILD_DIR=\"$ffmpeg_install_prefix\" \
-DDEPENDENCY_BUILD_DIR=\"$dependency_install_prefix\" \
-DCMAKE_INSTALL_PREFIX=\"$ffmpeg_kit_install\" \
-DFFMPEG_KIT_BUNDLE_TYPE=\"$(get_bundle_type)\" \
-DFFMPEG_KIT_VERSION=\"$(get_latest_version_from_changelog)\""

	if [[ "$build_ffmpeg_kit_type" == "static" ]]; then
		cmake_params+=" -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON"
	else
		cmake_params+=" -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF"
	fi

	if truthy "$build_tests"; then
		cmake_params+=" -DBUILD_TESTS=ON"
	else
		cmake_params+=" -DBUILD_TESTS=OFF"
	fi

	truthy "$enable_libplacebo" && cmake_params+=" -DENABLE_LIBPLACEBO=ON"
	truthy "$enable_libtensorflow" && cmake_params+=" -DENABLE_LIBTENSORFLOW=ON"
	truthy "$enable_libopenvino" && cmake_params+=" -DENABLE_OPENVINO=ON"

	if truthy "$do_debug_build"; then
		export STRIP=true
		cmake_params+=" -DCMAKE_BUILD_TYPE=Debug"
		CFLAGS+=" -g -fno-omit-frame-pointer -ggdb"
		CXXFLAGS+=" -g -fno-omit-frame-pointer -ggdb -D_GLIBCXX_DEBUG"
		LDFLAGS+=" -Wl,-Map,libffmpegkit.map"
		cmake_params+=" -DCMAKE_SHARED_LINKER_FLAGS=\"-static-libgcc -static-libstdc++ -Wl,--exclude-libs,libstdc++.a -Wl,--exclude-libs,libgcc.a -Wl,-Map,libffmpegkit.map\""
	else
		cmake_params+=" -DCMAKE_BUILD_TYPE=Release"
		cmake_params+=" -DCMAKE_SHARED_LINKER_FLAGS=\"-static-libgcc -static-libstdc++ -Wl,--exclude-libs,libstdc++.a -Wl,--exclude-libs,libgcc.a\""
	fi

	change_dir "${ffmpeg_kit_src_dir}"
	
	change_dir "${ffmpeg_kit_src_dir}/build" 1
	
	do_cmake_from_build_dir "$ffmpeg_kit_src_dir" "$cmake_params" "${type_postfix}" 1

	echo -e "INFO: Done configuring ffmpeg kit" | tee -a "$LOG_FILE"
}

get_static_macro_from_header() {
		local base_name="$1"
		local inc_dirs="$2"
		# 1. Gather all possible header paths
		IFS=' ' read -r -a paths <<< "$inc_dirs"
		paths+=("-I${INCLUDE_ROOT}")
		for path_flag in "${paths[@]}"; do
				local search_dir="${path_flag#-I}"
				[[ -d "$search_dir" ]] || continue
				# Look for the header
				local header_found=$(find "$search_dir" -maxdepth 2 \
						\( -name "${base_name}.h" -o -name "lib${base_name}.h" \) | head -n 1)
				if [[ -n "$header_found" ]]; then
						# 2a. Check for 'defined(MACRO)'
						# We use gsed -nE to match the pattern and print ONLY the capture group (\1)
						local macro=$(gsed -nE 's/.*defined\(([A-Z0-9_]+_(NODLL|STATIC|STATICLIB|STATIC_LIB))\).*/\1/p' "$header_found" | head -n 1)
						if [[ -n "$macro" ]]; then
								echo "-D${macro}"
								return 0
						fi
						# 2b. Fallback: Check for '#ifdef MACRO'
						# Matches: #ifdef MACRO, # ifdef MACRO, etc.
						# Captures the MACRO name into \1 and prints it.
						local ifdef_macro=$(gsed -nE 's/^\s*#\s*ifdef\s+([A-Z0-9_]+_(NODLL|STATIC|STATICLIB|STATIC_LIB)).*/\1/p' "$header_found" | head -n 1)
						if [[ -n "$ifdef_macro" ]]; then
								 echo "-D${ifdef_macro}"
								 return 0
						fi
				fi
		done
		return 1
}

fix_pkgconfig_flags() {
	local ORIG_PKG_CONFIG_PATH=$PKG_CONFIG_PATH
	local ORIG_PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR
	local ORIG_PKG_CONFIG_SYSROOT_DIR=$PKG_CONFIG_SYSROOT_DIR

	export PKG_CONFIG_PATH=""
	export PKG_CONFIG_LIBDIR="$install_pkgconfig_dir"
	export PKG_CONFIG_SYSROOT_DIR="$dependency_install_prefix"

	echo "INFO: Scanning .pc files in $PKG_CONFIG_LIBDIR..."

	find "${dependency_install_prefix}/lib" -name "*.dll.a" | while read -r dll_a; do
		static_a="${dll_a%.dll.a}.a"
		if [ -f "$static_a" ]; then
			echo "Removing $dll_a (found static alternative: $static_a)" > >(redirect_output)
			rm "$dll_a"
		fi
	done

	while IFS= read -r -d '' file; do
		if grep -q "whole-archive" "$file" >/dev/null || \
		grep -q "no-whole-archive" "$file" >/dev/null || \
		grep -oE '/[^[:space:]]*/lib[a-zA-Z0-9_+.-]+\.a' "$file" >/dev/null; then
			gsed -i -E 's/-Wl,(--whole-archive|--no-whole-archive)//g; s|[[:space:]]*/[^[:space:]]*/lib([a-zA-Z0-9_+.-]+)\.a| -l\1|g' "$file"
		fi
	done < <(find "$ffmpeg_install_prefix/lib/pkgconfig" -name "*.pc" -print0)

	for pc_file in "$PKG_CONFIG_LIBDIR"/*.pc; do
			gsed -i "s|-l/|/|g" "$pc_file"
			gsed -i "s|-lstdc++||g" "$pc_file"
			gsed -i "s|-lgcc_s||g" "$pc_file"
			gsed -i "s|-lgcc||g" "$pc_file"
			gsed -i 's|\b-lwinpthread\b|-lpthreadwin32|g' "$pc_file"
			gsed -i 's|\b-lpthread\b|-lpthreadwin32|g' "$pc_file"
			gsed -i "s|-latomic|$(realpath "$("$CXX" -print-file-name=libatomic.a)")|g" "$pc_file"
			gsed -i "s|/usr/local/mingw-w64/[^ ]*libstdc++[^ ]*|${stdcpp_path}|g" "$pc_file"
			gsed -i 's|/usr/local/mingw-w64/[^ ]*libstdc++\.a||g' "$pc_file"
			gsed -i "s|/usr/local/mingw-w64/[^ ]*libgcc[^ ]*|${stdgcc_path}|g" "$pc_file"
			gsed -i 's|/usr/local/mingw-w64/[^ ]*libgcc[^ ]*||g' "$pc_file"
			gsed -i 's|-static-libgcc||g' "$pc_file"
			gsed -i 's|-static-libstdc++||g' "$pc_file"
			[[ -e "$pc_file" ]] || continue
			pkg_name=$(basename "$pc_file" .pc)
			# Get Libs
			lib_flags=$(pkg-config --static --libs-only-l "$pkg_name" 2>/dev/null)
			clean_lib_name=$(echo "$lib_flags" | awk '{print $1}' | gsed 's/^-l//')
			[[ -z "$clean_lib_name" ]] && continue
			# Get Cflags (Include Paths)
			inc_flags=$(pkg-config --static --cflags-only-I "$pkg_name" 2>/dev/null)
			search_name="${clean_lib_name#lib}"
			# --- STRATEGY 1: EXCEPTION MAP ---
			local flag=""
			case "$pkg_name" in
					kvazaar) flag="-DKVZ_STATIC_LIB" ;;
					lc3)     flag="-DLC3_STATIC" ;;
			esac
			# --- STRATEGY 2: HEADER SCAN ---
			if [[ -z "$flag" ]]; then
					flag=$(get_static_macro_from_header "$search_name" "$inc_flags")
			fi
			# --- STRATEGY 3: FALLBACK GUESSING ---
			if [[ -z "$flag" ]]; then
					local upper=$(echo "$search_name" | tr '[:lower:]-' '[:upper:]_')
					local guess="-D${upper}_STATIC"
					if [[ "$search_name" == "ssh" || "$search_name" == "twolame" ]]; then
							guess="-DLIB${upper}_STATIC"
					fi
					flag="$guess"
			fi
			# --- 5. DUPLICATION CHECK (UPDATED) ---
			# CRITICAL FIX: Only grep the 'Cflags:' line, not the whole file.
			# This allows adding the flag to Cflags even if it already exists in Cflags.private.
			if grep "^Cflags:" "$pc_file" | grep -Fq -e "$flag"; then
					 echo "  [OK]    $pkg_name: Already has flag $flag in Cflags" >>"$LOG_FILE"
					 continue
			fi
			# 6. APPLY PATCH
			cp -fv "$pc_file" "$pc_file.bak" >>"$LOG_FILE" 2>&1
			if [[ -n "$flag" ]]; then
					echo "  [FIX]   $pkg_name: Appending $flag to $pc_file" >>"$LOG_FILE"
					add_libs_to_pkg -t="$pc_file" -c="$flag"
			fi
	done

	export PKG_CONFIG_PATH="$ORIG_PKG_CONFIG_PATH"
	export PKG_CONFIG_LIBDIR="$ORIG_PKG_CONFIG_LIBDIR"
	export PKG_CONFIG_SYSROOT_DIR="$ORIG_PKG_CONFIG_SYSROOT_DIR"
	echo "INFO: Update Complete."
}

# 1. variant
# @. custom values
# Usage: get_generic_cmake_toolchain [variant_suffix] [VAR="VALUE" ...]
# Example: get_generic_cmake_toolchain "rabbitmq" CMAKE_C_FLAGS_INIT="-static -Wno-error"
get_generic_cmake_toolchain() {
		local variant="$1"
		local base_filename="$host_name-toolchain.cmake"
		local base_filepath="$src_dir/$base_filename"
		shift
		# Determine filename based on variant presence
		local toolchain_filename="$host_name-toolchain.cmake"
		if [[ -n "$variant" ]]; then
			toolchain_filename="$host_name-toolchain-$variant.cmake"
			local toolchain_path="$(pwd)/$toolchain_filename"
		else
			toolchain_filename="$host_name-toolchain.cmake"
			local toolchain_path="$src_dir/$toolchain_filename"
		fi
		local cpu_family="x86_64"
		if [ "$bits_target" = 32 ]; then
				cpu_family="x86"
		fi
		declare -A cmake_config
		# System info
		cmake_config["CMAKE_SYSTEM_NAME"]="Windows"
		cmake_config["CMAKE_SYSTEM_PROCESSOR"]="${target_proc:-$cpu_family}"
		# Toolchain locations
		cmake_config["TOOLCHAIN_PREFIX"]="${host_target}"
		cmake_config["TOOLCHAIN_ROOT"]="${toolchain_root_dir}"
		# Compilers
		cmake_config["CMAKE_C_COMPILER"]="${cross_prefix}gcc"
		cmake_config["CMAKE_CXX_COMPILER"]="${cross_prefix}g++"
		# cmake_config["CMAKE_RC_COMPILER"]="${cross_prefix}windres"
		cmake_config["CMAKE_AR"]="${cross_prefix}ar"
		cmake_config["CMAKE_RANLIB"]="${cross_prefix}ranlib"
		cmake_config["CMAKE_STRIP"]="${cross_prefix}strip"
		# Loop through remaining args in format KEY="VALUE"
		for arg in "$@"; do
				local key="${arg%%=*}"
				local value="${arg#*=}"
				echo "DEBUG: adding KEY:$key and VALUE:$value to cmake toolchain file for $variant" >>"$LOG_FILE"
				cmake_config["$key"]="$value"
		done
		echo "# Generated via get_generic_cmake_toolchain" > "$toolchain_path"
		# Write CMAKE_SYSTEM_NAME first (convention)
		echo "set(CMAKE_SYSTEM_NAME \"${cmake_config[CMAKE_SYSTEM_NAME]}\")" >> "$toolchain_path"
		unset 'cmake_config[CMAKE_SYSTEM_NAME]'
		# Write the rest
		for key in "${!cmake_config[@]}"; do
				echo "set($key \"${cmake_config[$key]}\")" >> "$toolchain_path"
		done
		echo "$toolchain_path"
}

get_generic_meson_cross_file() {
	local variant_name="$1"      # e.g., "librist"
	local extra_content="$2"     # e.g., "[built-in options]..."
	local base_filename="$host_name-meson-cross.mingw.txt"
	local base_filepath="$src_dir/$base_filename"
	# 1. Generate the BASE file if it doesn't exist (Standard Logic)
	local cpu_family="x86_64"
	if [ "$bits_target" = 32 ]; then
			cpu_family="x86"
	fi
	local meson_stdcpp="'$stdcpp_path'"
	local meson_stdgcc="'$stdgcc_path'"
	cat >"$base_filepath" <<EOF
[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'
default_library = 'static'
prefer_static = true
backend = 'ninja'
prefix = '$dependency_install_prefix'
libdir = '$dependency_install_prefix/lib'
b_lto = false
b_staticpic = true
c_link_args = ['-static', $meson_stdgcc]
cpp_link_args = ['-static', $meson_stdcpp, $meson_stdgcc]
c_args = ['-static-libgcc', '-DGLIB_STATIC_COMPILATION', '-mstackrealign']
cpp_args = ['-static-libgcc', '-static-libstdc++', '-DGLIB_STATIC_COMPILATION', '-mstackrealign']

[binaries]
c = '${cross_prefix}gcc'
cpp = '${cross_prefix}g++'
ld = '${cross_prefix}ld'
ar = '${cross_prefix}ar'
strip = '${cross_prefix}strip'
nm = '${cross_prefix}nm'
dlltool = '${cross_prefix}dlltool'
windres = '/usr/bin/true'
pkg-config = 'pkg-config'
nasm = 'nasm'
cmake = 'cmake'

[host_machine]
system = 'windows'
cpu_family = '$cpu_family'
cpu = '$cpu_family'
endian = 'little'

[properties]
pkg_config_libdir = '$pkg_config_sysroot_dir/lib/pkgconfig'
needs_exe_wrapper = true
EOF
	# 2. Handle Custom Variant logic
	if [[ -n "$variant_name" ]]; then
			local custom_filepath="$(pwd)/$host_name-meson-cross.mingw.${variant_name}.txt"
			# Always overwrite the variant with a fresh copy of the base
			cp "$base_filepath" "$custom_filepath" 2>"$LOG_FILE"
			# Append custom options if provided
			if [[ -n "$extra_content" ]]; then
					# Add a newline for safety
					echo "" >> "$custom_filepath"
					echo -e "$extra_content" >> "$custom_filepath"
			fi
			# Return the path to the NEW custom file
			echo "$custom_filepath"
	else
			# No customization requested, return the standard base file
			echo "$base_filepath"
	fi
}

ffmpeg_patches() {
	if iswindows; then
		echo "INFO: Patching ffmpeg for windows Mingw quirks..." >>"$LOG_FILE"
		gsed -i 's/#define HAVE_SCHED_GETAFFINITY 1/#define HAVE_SCHED_GETAFFINITY 0/g' "$ffmpeg_source_dir/config.h"
		if [[ -f "$ffmpeg_source_dir/libavfilter/dnn/dnn_backend_tf.c" ]]; then
			gsed -i 's/ctx->options.async/ctx->async/g' "$ffmpeg_source_dir/libavfilter/dnn/dnn_backend_tf.c"
		fi
		echo "INFO: Done patching ffmpeg for windows Mingw quirks." >>"$LOG_FILE"
	fi
}

disable_windows_rsrc() {
  local src_dir="${1:-"$(pwd)"}"
  if iswindows; then
    echo "INFO: Patching build files in $src_dir to remove Windows resource objects..." >>"$LOG_FILE"

    # --- Pass 1: Autotools/Make (Handles build/version.o and similar) ---
    find "$src_dir" \( -name "Makefile" -o -name "Makefile.in" -o -name "Makefile.am" -o -name "*.make" \) -exec sh -c '
      for file do
        if grep -qE "(\.res(\.lo)?|w32res\.lo|version(info|-metadata)\.(lo|res|o)|version\.rc\.(lo|res|o))" "$file"; then
          echo "  PATCHING MAKE: $file" >>"$LOG_FILE"
          gsed -i -e -E "/=/ { 
            w /tmp/sed_before
            s|[^ ]*/version(info|-metadata|info\.rc|info\.res)?\.(lo|res|o)\b||g
            s|[^ ]*/version\.rc\.(lo|res|o)\b||g
            s|[^ ]*\.res(\.lo)?\b||g
            w /tmp/sed_after
          }" "$file"
          diff /tmp/sed_before /tmp/sed_after | grep "^<" | gsed -e "s/^</    REMOVED: /" >>"$LOG_FILE"
        fi
      done
    ' sh {} +

    # --- Pass 2: CMake (Surgical Path & Rule Removal) ---
    find "$src_dir" \( -name "*.make" -o -name "*.cmake" -o -name "*.rsp" \) -exec sh -c '
      for file do
        if grep -qE "version\.rc\.res" "$file"; then
          echo "  PATCHING CMAKE: $file" >>"$LOG_FILE"
          gsed -i -e -E "s/\"[^\"]*version\.rc\.res\"//g; s/[^ ]*version\.rc\.res//g" "$file"
        fi
      done
    ' sh {} +

    # --- Pass 3: Meson (Multi-line Block Commenting) ---
    find "$src_dir" -name "meson.build" -exec sh -c '
      for file do
        if grep -q "windows.compile_resources" "$file"; then
          echo "  PATCHING MESON: $file" >>"$LOG_FILE"
          gsed -i -e "/windows\.compile_resources(/,/)/ s/^/# /" "$file"
          gsed -i -e -E "/(libplacebo_rc|demos_rc|ft2_res|version_res)\s*=\s*configure_file/,/)/ s/^/# /" "$file"
        fi
      done
    ' sh {} +
  fi
}