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

configure_ffmpeg_kit() {
  echo -e "INFO: Configuring ffmpeg kit" | tee -a "$LOG_FILE"
  reset_allflags
  set_toolchain_paths
  
	local type_postfix="$build_ffmpeg_kit_type"

	if truthy "$force_kit"; then
		remove_path -rf "$ffmpeg_kit_src_dir/build"
		remove_path -rf "$ffmpeg_kit_src_dir"/already_configured_*
		remove_path -rf "$ffmpeg_kit_install"
	fi

	create_dir "$ffmpeg_kit_install"

	export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${ffmpeg_install_prefix}/lib/pkgconfig"

  export CFLAGS="$CFLAGS"
  export CXXFLAGS="$CXXFLAGS"
  export LDFLAGS="$LDFLAGS"

	change_dir "${ffmpeg_kit_src_dir}"
	make distclean > >(redirect_output) 2>&1

  local cmake_params="-DCMAKE_TOOLCHAIN_FILE=$(get_generic_cmake_toolchain) \
-DFFMPEG_SRC_DIR=\"$ffmpeg_source_dir\" \
-DFFMPEG_BUILD_DIR=\"$ffmpeg_install_prefix\" \
-DDEPENDENCY_BUILD_DIR=\"$dependency_install_prefix\" \
-DCMAKE_INSTALL_PREFIX=\"$ffmpeg_kit_install\" \
-DFFMPEG_KIT_BUNDLE_TYPE=\"$(get_bundle_type)\" \
-DCMAKE_OSX_ARCHITECTURES=$host_arch \
-DCMAKE_OSX_PLATFORM=$host_platform \
-DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_TVOS_VERSION \
-DCMAKE_OSX_SYSROOT=$(xcrun --sdk "$toolchain_sys" --show-sdk-path) \
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
    CFLAGS+=" -Og -fno-omit-frame-pointer -ggdb"
    CXXFLAGS+=" -Og -fno-omit-frame-pointer -ggdb -D_GLIBCXX_DEBUG"
    case "$test_type" in
      tsan)
        CFLAGS+=" -fsanitize=thread"
        CXXFLAGS+=" -fsanitize=thread"
        LDFLAGS+=" -fsanitize=thread"
        ;;
      asan)
        CFLAGS+=" -fsanitize=address"
        CXXFLAGS+=" -fsanitize=address"
        LDFLAGS+=" -fsanitize=address"
        ;;
      undefined)
        CFLAGS+=" -fsanitize=undefined"
        CXXFLAGS+=" -fsanitize=undefined"
        LDFLAGS+=" -fsanitize=undefined"
        ;;
    esac
	else
		# Preserve optimized DWARF data so build_xcframework.sh can create the
		# release dSYM before stripping the packaged framework binary.
		cmake_params+=" -DCMAKE_BUILD_TYPE=RelWithDebInfo"
	fi

	change_dir "${ffmpeg_kit_src_dir}/build" 1
  
  do_cmake "$cmake_params" "$ffmpeg_kit_src_dir" "${type_postfix}" 1

	echo -e "INFO: Done configuring ffmpeg kit" | tee -a "$LOG_FILE"
}

detect_clang_version() {
  # shellcheck disable=2046,2005
  echo $(clang -v 2>&1 | grep -oP 'Ubuntu clang version \K\d+\.\d+\.\d+' | cut -d. -f1)
}

set_toolchain_paths() {
  export CC="$(xcrun --sdk "$toolchain_sys" --find clang)"
  export CXX="$(xcrun --sdk "$toolchain_sys" --find clang++)"
  export AR="$(xcrun --sdk "$toolchain_sys" --find ar)"
  export AS="$(xcrun --sdk "$toolchain_sys" --find as)"
  export RANLIB="$(xcrun --sdk "$toolchain_sys" --find ranlib)"
  export LD="$(xcrun --sdk "$toolchain_sys" --find ld)"
  export STRIP="$(xcrun --sdk "$toolchain_sys" --find strip)"
  export NM="$(xcrun --sdk "$toolchain_sys" --find nm)"
  export CFLAGS="$CFLAGS -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"
  export CXXFLAGS="$CXXFLAGS -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"
  export LDFLAGS="$LDFLAGS -ljsoncpp -L${ffmpeg_install_prefix}/lib"
}

ffmpeg_patches() {
	if ismacos; then
		echo "INFO: Patching ffmpeg for macOS quirks..." >>"$LOG_FILE"
    if truthy "$enable_vulkan"; then
      gsed -i '/#include <SDL_vulkan.h>/a\
#include "libavutil/hwcontext.h"\
#include "libavutil/hwcontext_vulkan.h"' "$ffmpeg_source_dir/fftools/ffplay_renderer.c"
    fi
		echo "INFO: Done patching ffmpeg for macOS quirks." >>"$LOG_FILE"
	fi
}


get_generic_meson_cross_file() {
	local variant_name="$1"      # e.g., "librist"
	local extra_content="$2"     # e.g., "[built-in options]..."
	local base_filename="$host_name-meson-cross.txt"
	local base_filepath="$src_dir/$base_filename"
  BUILD_ARCH=$(uname -m)
  BUILD_SYS=$(uname)
  if [ "$BUILD_ARCH" = "arm64" ]; then
      BUILD_ARCH="aarch64"
  fi
  export CC_FOR_BUILD=clang
  export CXX_FOR_BUILD=clang++
  if istvossimulator; then
    min_ver="-mtvos-simulator-version-min=$MIN_TVOS_VERSION"
    target_min="$host_arch-apple-tvos$MIN_TVOS_VERSION-simulator"
  else
    min_ver="-mtvos-version-min=$MIN_TVOS_VERSION"
    target_min="$host_arch-apple-tvos$MIN_TVOS_VERSION"
  fi
	cat >"$base_filepath" <<EOF
[binaries]
c = '$(xcrun --sdk "$toolchain_sys" --find clang)'
cpp = '$(xcrun --sdk "$toolchain_sys" --find clang++)'
ld = '$(xcrun --sdk "$toolchain_sys" --find ld)'
ar = '$(xcrun --sdk "$toolchain_sys" --find ar)'
strip = '$(xcrun --sdk "$toolchain_sys" --find strip)'
nm = '$(xcrun --sdk "$toolchain_sys" --find nm)'
objc = '$(xcrun --sdk "$toolchain_sys" --find clang)'
objcpp = '$(xcrun --sdk "$toolchain_sys" --find clang++)'
pkgconfig = 'pkg-config'
nasm = 'nasm'
cmake = 'cmake'

[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'
default_library = 'static'
prefer_static = true
backend = 'ninja'
b_lto = false
b_staticpic = true
c_args = ['-I${dependency_install_prefix}/include', '-arch', '$host_arch', '-target', '$target_min', '$min_ver', '-isysroot', '$TVOS_SYSROOT']
c_link_args = ['-L${dependency_install_prefix}/lib', '-arch', '$host_arch', '-target', '$target_min', '$min_ver', '-isysroot', '$TVOS_SYSROOT']
cpp_args = ['-I${dependency_install_prefix}/include', '-arch', '$host_arch', '-DGLIB_STATIC_COMPILATION', '-target', '$target_min', '$min_ver', '-isysroot', '$TVOS_SYSROOT']
cpp_link_args = ['-L${dependency_install_prefix}/lib', '-arch', '$host_arch', '-DGLIB_STATIC_COMPILATION', '-target', '$target_min', '$min_ver', '-isysroot', '$TVOS_SYSROOT']
prefix = '$dependency_install_prefix'
libdir = '$dependency_install_prefix/lib'
pkg_config_path = '$PKG_CONFIG_PATH'

[build_machine]
system = '${BUILD_SYS,,}'
cpu_family = '$BUILD_ARCH'
cpu = '$BUILD_ARCH'
endian = 'little'

[host_machine]
system = '$( if istvossimulator; then echo tvos-simulator; else echo tvos; fi )'
cpu_family = '$meson_cpu_family'
cpu = '$meson_cpu_family'
endian = 'little'

[properties]
needs_exe_wrapper    = true
pkg_config_libdir = '$dependency_install_prefix/lib/pkgconfig'
has_function_fork = false
has_function_execvp = false
has_function_execv = false

EOF
	# 2. Handle Custom Variant logic
	if [[ -n "$variant_name" ]]; then
			local custom_filepath="$(pwd)/$host_name-meson-cross.${variant_name}.txt"
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

get_generic_meson_native_file() {
	local variant_name="$1"      # e.g., "librist"
	local extra_content="$2"     # e.g., "[built-in options]..."
	local base_filename="$host_name-meson-native.txt"
	local base_filepath="$src_dir/$base_filename"
	BUILD_ARCH=$(uname -m)
  BUILD_SYS=$(uname)
  if [ "$BUILD_ARCH" = "arm64" ]; then
      BUILD_ARCH="aarch64"
  fi
	cat >"$base_filepath" <<EOF
[binaries]
c = '$(xcrun --sdk macosx --find clang)'
cpp = '$(xcrun --sdk macosx --find clang++)'
ld = '$(xcrun --sdk macosx --find ld)'
ar = '$(xcrun --sdk macosx --find ar)'
strip = '$(xcrun --sdk macosx --find strip)'
nm = '$(xcrun --sdk macosx --find nm)'
objc = '$(xcrun --sdk macosx --find clang)'
objcpp = '$(xcrun --sdk macosx --find clang++)'
pkgconfig = 'pkg-config'
nasm = 'nasm'
cmake = 'cmake'

[built-in options]
c_args = ['-O3', '-march=native']
cpp_args = ['-O3', '-march=native']
EOF
	# 2. Handle Custom Variant logic
	if [[ -n "$variant_name" ]]; then
			local custom_filepath="$(pwd)/$host_name-meson-cross.${variant_name}.txt"
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
		cmake_config["CMAKE_SYSTEM_NAME"]="tvOS"
		cmake_config["CMAKE_SYSTEM_PROCESSOR"]="${target_proc:-$cpu_family}"
		cmake_config["CMAKE_SYSROOT"]="$(xcrun --sdk "$toolchain_sys" --show-sdk-path)"
		# Toolchain locations
		cmake_config["TOOLCHAIN_PREFIX"]="${host_target}"
		cmake_config["TOOLCHAIN_ROOT"]="${toolchain_root_dir}"
		# Compilers
		cmake_config["CMAKE_C_COMPILER"]="$CC"
		cmake_config["CMAKE_CXX_COMPILER"]="$CXX"
		cmake_config["CMAKE_AR"]="$AR"
		cmake_config["CMAKE_RANLIB"]="$RANLIB"
		cmake_config["CMAKE_STRIP"]="$STRIP"
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

create_tvos_xcframework() {
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
  local lib_ext=".dylib"
  if [[ "$build_ffmpeg_kit_type" == "static" ]]; then
    lib_ext=".a"
  fi

  # Determine platform name for output
  local platform_name="tvos"
  if istvossimulator; then
    platform_name="appletvsimulator"
  fi

  # Create staging directory for this platform-arch
  local staging_dir="${WORKDIR}/apple/xcframework-staging/${platform_name}-${host_arch}"
  if [[ -d "${staging_dir}" ]]; then
    rm -rf "${staging_dir}"
  fi
  mkdir -p "${staging_dir}/Headers/json"

  # Copy library and headers
  {
    cp -fv "${work_dir}/${kit_dir}/lib/"* "${staging_dir}"
    cp -fv "${ffmpeg_kit_install}/include/"* "${staging_dir}/Headers"
    cp -fv "${work_dir}/${kit_dir}/include/"* "${staging_dir}/Headers"
    cp -fv "${dependency_install_prefix}/include/json/"* "${staging_dir}/Headers/json"
  } > >(redirect_output) 2>&1

  echo "INFO: Created tvOS XCFramework staging for ${platform_name}-${host_arch}"
  echo "INFO: Staging directory: ${staging_dir}"
}

create_bin2c_py() {
	# binc2c python script because bin2c generated executable is no-op on mac due to security policy
	setup_default_python
	local bin2c_py_path="${ffmpeg_source_dir}/ffbuild/bin2c.py"
	cat > "$bin2c_py_path" << 'EOF'
#!/usr/bin/env python3
import sys
import os

def bin2c(inf, outf, name=None):
    if not name:
        name = os.path.basename(inf).replace('.', '_')
    
    with open(inf, 'rb') as f:
        data = f.read()
    
    with open(outf, 'w') as f:
        f.write(f'const unsigned char ff_{name}_data[] = {{ ')
        f.write(', '.join(f'0x{b:02x}' for b in data))
        f.write(', 0x00 };\n')
        f.write(f'const unsigned int ff_{name}_len = {len(data)};\n')

if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(1)
    bin2c(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) == 4 else None)
EOF
	echo "$bin2c_py_path"
}
