#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2312,2250,2292,2249

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

set_toolchain_paths() {
	export PATH="${PATH}:${toolchain_bin_path}:${dependency_install_prefix}/bin"
	export CC="$CC"
	export CXX="$CXX"
	export AR="$AR"
	export AS="$AS"
	export NM="$NM"
	export RANLIB="$RANLIB"
	export STRIP="$STRIP"
	export LD="$CC"
}

configure_ffmpeg_kit() {
	echo -e "INFO: Configuring ffmpeg kit" | tee -a "$LOG_FILE"
	local type_postfix="$build_ffmpeg_kit_type"

	if truthy "$build_force"; then
		remove_path -rf "$ffmpeg_kit_src_dir/build"
		remove_path -rf "$ffmpeg_kit_src_dir"/already_configured_*
		remove_path -rf "$ffmpeg_kit_install"
	fi

	create_dir "$ffmpeg_kit_install"

	export PKG_CONFIG_LIBDIR="${install_pkgconfig_dir}:${ffmpeg_install_prefix}/lib/pkgconfig"
	export PKG_CONFIG_SYSROOT_DIR="/"
	set_toolchain_paths

	reset_allflags
	local local_cflags="${CFLAGS} -I${ffmpeg_install_prefix}/include -L${ffmpeg_install_prefix}/lib -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat -DHAVE_W32PTHREADS_H=1"
	local local_cxxfalgs="${CXXFLAGS} -I${ffmpeg_install_prefix}/include -L${ffmpeg_install_prefix}/lib -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"

	change_dir "${ffmpeg_kit_src_dir}"
	make distclean > >(redirect_output) 2>&1

	export CFLAGS="${local_cflags}"
	export CXXFLAGS="${local_cxxfalgs}"
	UNWIND_STATIC=$($CXX -print-file-name=libunwind.a)
    BUILTINS_STATIC=$($CXX -print-file-name=libclang_rt.builtins-"${clang_arch}"-android.a)
    export LDFLAGS="${LDFLAGS} -Wl,--allow-multiple-definition -Wl,--exclude-libs,libunwind.a $UNWIND_STATIC $BUILTINS_STATIC"
    export LDFLAGS=$(echo "${LDFLAGS}" | gsed 's/-Wl,--fatal-warnings//g')
	export LDFLAGS="${LDFLAGS//-static /} -static-libstdc++ -L${ffmpeg_install_prefix}/lib -L${dependency_install_prefix}/lib"

	local cmake_params="-DCMAKE_SYSTEM_NAME=Android \
-DCMAKE_TOOLCHAIN_FILE=$(get_generic_cmake_toolchain) \
-DCMAKE_C_COMPILER=$CC \
-DCMAKE_CXX_COMPILER=$CXX \
-DCMAKE_LINKER=$CC \
-DCMAKE_EXE_LINKER_FLAGS_INIT=\"-L${ffmpeg_install_prefix}/lib -L${dependency_install_prefix}/lib\" \
-DCMAKE_SHARED_LINKER_FLAGS_INIT=\"-L${ffmpeg_install_prefix}/lib -L${dependency_install_prefix}/lib\" \
-DCMAKE_MODULE_LINKER_FLAGS_INIT=\"-L${ffmpeg_install_prefix}/lib -L${dependency_install_prefix}/lib\" \
-DFFMPEG_SRC_DIR=\"$ffmpeg_source_dir\" \
-DFFMPEG_BUILD_DIR=\"$ffmpeg_install_prefix\" \
-DCMAKE_INSTALL_PREFIX=\"$ffmpeg_kit_install\" \
-DFFMPEG_KIT_BUNDLE_TYPE=\"$(get_bundle_type)\" \
-DCMAKE_SHARED_LINKER_FLAGS=\"-Wl,--allow-multiple-definition -Wl,--exclude-libs,libunwind.a $UNWIND_STATIC $BUILTINS_STATIC\" \
-DCMAKE_FIND_LIBRARY_SUFFIXES=\".a;.so\" \
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

	if truthy "$do_debug_build"; then
		cmake_params+=" -DCMAKE_BUILD_TYPE=Debug"
		CFLAGS+=" -g -fno-omit-frame-pointer -ggdb"
		CXXFLAGS+=" -g -fno-omit-frame-pointer -ggdb -D_GLIBCXX_DEBUG"
	else
		cmake_params+=" -DCMAKE_BUILD_TYPE=Release"
	fi

	change_dir "${ffmpeg_kit_src_dir}"

	change_dir "${ffmpeg_kit_src_dir}/build" 1

	do_cmake "$cmake_params" "$ffmpeg_kit_src_dir" "${type_postfix}" 1

	echo -e "INFO: Done configuring ffmpeg kit" | tee -a "$LOG_FILE"
}

# 1. variant
# @. custom values
# Usage: get_generic_cmake_toolchain [variant_suffix] [VAR="VALUE" ...]
get_generic_cmake_toolchain() {
	local variant="$1"
	local toolchain_filename="$host_name-toolchain.cmake"
	[[ -n "$variant" ]] && toolchain_filename="$host_name-toolchain-$variant.cmake"
	local toolchain_path="$src_dir/$toolchain_filename"
	[[ -n "$variant" ]] && toolchain_path="$(pwd)/$toolchain_filename"
	shift

	if [[ ! -e "$toolchain_path" ]]; then
		local abi="x86_64"
		case "$host_arch" in
		"x86_64") abi="x86_64" ;;
		"i686") abi="x86" ;;
		"aarch64") abi="arm64-v8a" ;;
		"armv7a") abi="armeabi-v7a" ;;
		esac

		cat >"$toolchain_path" <<EOF
# Set Android basics
set(ANDROID_PLATFORM android-$ANDROID_API_LEVEL)
set(ANDROID_ABI $abi)

# Include the official NDK toolchain to do the heavy lifting
include($ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake)

# Override/Add specific paths for your build system
set(CMAKE_FIND_ROOT_PATH "$dependency_install_prefix")
set(CMAKE_C_FLAGS_INIT "-fPIC")
set(CMAKE_CXX_FLAGS_INIT "-fPIC")

# Ensure the custom tool paths from your environment are respected if needed
set(CMAKE_AR "$AR" CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB "$RANLIB" CACHE FILEPATH "Ranlib")
EOF
		# Loop through remaining args in format KEY="VALUE"
		for arg in "$@"; do
			local key="${arg%%=*}"
			local value="${arg#*=}"
			echo "set($key \"$value\")" >>"$toolchain_path"
		done
	fi
	echo "$toolchain_path"
}

get_generic_meson_cross_file() {
	local variant_name="$1"  # e.g., "librist"
	local extra_content="$2" # e.g., "[built-in options]..."
	local base_filename="$host_name-meson-cross.android.txt"
	local base_filepath="$src_dir/$base_filename"
	# 1. Generate the BASE file if it doesn't exist (Android Logic)
	local cpu_family="$host_arch"
	case "$host_arch" in
	"armv7a" | "arm") cpu_family="arm" ;;
	"i686" | "x86") cpu_family="x86" ;;
	esac
	cat >"$base_filepath" <<EOF
[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'
default_library = 'static'
prefer_static = 'true'
backend = 'ninja'
prefix = '$dependency_install_prefix'
libdir = '$dependency_install_prefix/lib'
b_staticpic = 'true'

[binaries]
c = '$CC'
cpp = '$CXX'
ld = '$LD'
ar = '$AR'
strip = '$STRIP'
nm = '$NM'
ranlib = '$RANLIB'
pkg-config = 'pkg-config'
cmake = 'cmake'

[host_machine]
system = 'android'
cpu_family = '$cpu_family'
cpu = '$host_arch'
endian = 'little'

[properties]
pkg_config_libdir = '$dependency_install_prefix/lib/pkgconfig'
needs_exe_wrapper = true
EOF
	# 2. Handle Custom Variant logic
	if [[ -n "$variant_name" ]]; then
		local custom_filepath="$(pwd)/$host_name-meson-cross.android.${variant_name}.txt"
		# Always overwrite the variant with a fresh copy of the base
		cp "$base_filepath" "$custom_filepath" 2>"$LOG_FILE"
		# Append custom options if provided
		if [[ -n "$extra_content" ]]; then
			# Add a newline for safety
			echo "" >>"$custom_filepath"
			echo -e "$extra_content" >>"$custom_filepath"
		fi
		# Return the path to the NEW custom file
		echo "$custom_filepath"
	else
		# No customization requested, return the standard base file
		echo "$base_filepath"
	fi
}

fix_pkgconfig_flags() {
	echo "INFO: Fixing pkgconfig files for Android in $install_pkgconfig_dir"
	find "$install_pkgconfig_dir" -name "*.pc" -exec gsed -i -E \
	-e 's/(^|[[:space:]])-lrt([[:space:]]|$)/ /g' \
	-e 's/(^|[[:space:]])-lpthread([[:space:]]|$)/ -pthread /g' \
	-e 's/(^|[[:space:]])-l([[:space:]]|$)/ /g' "{}" + \
	2>>"$LOG_FILE"
	find "$dependency_install_prefix/lib" -name "*.la*" -delete
}

ffmpeg_patches() {
	if isandroid; then
		echo "INFO: Patching ffmpeg for Android..." >>"$LOG_FILE"
		copy_path "$PATCHDIR/binder.c" "$ffmpeg_source_dir/compat/android/binder.c" "-f"
		if [[ "$host_arch" == "armv7a" ]]; then		
			if [[ -f "$ffmpeg_source_dir/libavutil/hwcontext_vulkan.c" ]]; then
				gsed -i 's/static VkBool32 VKAPI_CALL vk_dbg_callback/static VKAPI_ATTR VkBool32 VKAPI_CALL vk_dbg_callback/' "$ffmpeg_source_dir/libavutil/hwcontext_vulkan.c"
			fi
		fi
		echo "INFO: Done patching ffmpeg for Android." >>"$LOG_FILE"
	fi
}

create_android_aar() {
  local arch_pfx="$aar_arch"
  local bundle_pfx="$(get_bundle_type)"
  local license_pfx="$(get_bundle_license)"
  local kit_dir=$(get_ffmpeg_kit_directory)
  local small_pfx=""
  local debug_pfx=""
  if truthy "$do_debug_build"; then
    debug_pfx="-debug"
	fi
  if truthy "$build_small"; then
    small_pfx="-small"
  fi
  local lib_ext=".so"
  if [[ "$build_ffmpeg_kit_type" == "static" ]]; then
    lib_ext=".a"
  fi
  local jni_libs_dir="${WORKDIR}/$host_platform/jniLibs-${bundle_pfx}${small_pfx}${debug_pfx}-${license_pfx}/jniLibs"
  if [[ -d "${WORKDIR}/$host_platform/jniLibs-${bundle_pfx}${small_pfx}${debug_pfx}-${license_pfx}" ]]; then
    rm -rf "${WORKDIR}/$host_platform/jniLibs-${bundle_pfx}${small_pfx}${debug_pfx}-${license_pfx}"
  fi
  mkdir -p "${jni_libs_dir}"/{include,lib/pkgconfig,arm64-v8a,armeabi-v7a,x86,x86_64}

  cp -fv "${work_dir}/${kit_dir}/lib/pkgconfig/ffmpegkit.pc" "${jni_libs_dir}/lib/pkgconfig/ffmpegkit.pc" > >(redirect_output)
  cp -fv "${work_dir}/${kit_dir}/lib/libffmpegkit${lib_ext}" "${jni_libs_dir}/${arch_pfx}/libffmpegkit${lib_ext}" > >(redirect_output)
	local owner="$(get_github_owner)"
  FFMPEG_KIT_NAMESPACE="io.github.$owner.ffmpegkit"
  FFMPEG_KIT_VERSION_CODE="$(date +%Y%m%d)"
  FFMPEG_KIT_VERSION="$(cat "${BASEDIR}/version")-SNAPSHOT"
  FFMPEG_KIT_JNI_LIBS_DIR=$(realpath "${jni_libs_dir}")
  FFMPEG_KIT_OUTPUT_NAME="$(get_bundle_directory)"
  OSSRH_USERNAME="$(get_maven_username)"
  OSSRH_PASSWORD="$(get_maven_password)"
  if [[ "$create_release" == "local" ]]; then
    GRADLE_COMMAND="publishToMavenLocal"
  else
    GRADLE_COMMAND="publishToMavenCentral"
  fi
  USER_HOME="/home/vscode"
  
  change_dir "${BASEDIR}"

  chmod +x "${BASEDIR}/gradlew"

  { exec "./gradlew" :tools:android:${GRADLE_COMMAND} \
    --no-daemon --info --warning-mode all --gradle-user-home "${USER_HOME}/.gradle" \
    -PFFMPEG_KIT_NAMESPACE="${FFMPEG_KIT_NAMESPACE}" \
    -PANDROID_NDK="${ANDROID_NDK}" \
    -PANDROID_API_LEVEL="${ANDROID_API_LEVEL}" \
    -PFFMPEG_KIT_VERSION_CODE="${FFMPEG_KIT_VERSION_CODE}" \
    -PFFMPEG_KIT_VERSION="${FFMPEG_KIT_VERSION}" \
    -PFFMPEG_KIT_JNI_LIBS_DIR="${FFMPEG_KIT_JNI_LIBS_DIR}" \
    -PFFMPEG_KIT_OUTPUT_NAME="${FFMPEG_KIT_OUTPUT_NAME}" \
    -POSSRH_USERNAME="${OSSRH_USERNAME}" \
    -PFFMPEG_KIT_ARCHES="$aar_arch" \
    -POSSRH_PASSWORD="${OSSRH_PASSWORD}" > >(redirect_output); } || { echo "Failed to create AAR for ${FFMPEG_KIT_OUTPUT_NAME}"; exit 1; }
    echo
}