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

configure_ffmpeg_kit() {
  echo -e "INFO: Configuring ffmpeg kit" | tee -a "$LOG_FILE"
  reset_allflags
  set_toolchain_paths
  
	local type_postfix="$build_ffmpeg_kit_type"

	if truthy "$build_force"; then
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

  local cmake_params="-DCMAKE_SYSTEM_NAME=Darwin \
-DCMAKE_C_COMPILER=$CC \
-DCMAKE_CXX_COMPILER=$CXX \
-DFFMPEG_SRC_DIR=\"$ffmpeg_source_dir\" \
-DFFMPEG_BUILD_DIR=\"$ffmpeg_install_prefix\" \
-DDEPENDENCY_BUILD_DIR=\"$dependency_install_prefix\" \
-DCMAKE_INSTALL_PREFIX=\"$ffmpeg_kit_install\" \
-DFFMPEG_KIT_BUNDLE_TYPE=\"$(get_bundle_type)\" \
-DCMAKE_OSX_ARCHITECTURES=$host_arch \
-DCMAKE_OSX_PLATFORM=$host_platform \
-DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_MACOS_VERSION \
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
  truthy "$enable_libtensorflow" && cmake_params+=" -DENABLE_LIBTENSORFLOW=ON"
  truthy "$enable_libopenvino" && cmake_params+=" -DENABLE_OPENVINO=ON"
  truthy "$enable_libtorch" && cmake_params+=" -DENABLE_LIBTORCH=ON"

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
		cmake_params+=" -DCMAKE_BUILD_TYPE=Release"
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
	# 1. Generate the BASE file if it doesn't exist (Standard Logic)
	local cpu_family="x86_64"
	if [ "$bits_target" = 32 ]; then
			cpu_family="x86"
	fi
	cat >"$base_filepath" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ld = '$LD'
ar = '$AR'
strip = '$STRIP'
nm = '$NM'
objc = '$CC'
objcpp = '$CXX'
pkgconfig = 'pkg-config'

[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'
default_library = 'static'
prefer_static = true
backend = 'ninja'
b_lto = false
b_staticpic = true
c_args = ['-I${dependency_install_prefix}/include', '-arch', '$host_arch', '-isysroot', '${SDKROOT}']
c_link_args = ['-L${dependency_install_prefix}/lib', '-arch', '$host_arch', '-isysroot', '${SDKROOT}']
cpp_args = ['-I${dependency_install_prefix}/include', '-arch', '$host_arch', '-DGLIB_STATIC_COMPILATION', '-isysroot', '${SDKROOT}']
cpp_link_args = ['-L${dependency_install_prefix}/lib', '-arch', '$host_arch', '-DGLIB_STATIC_COMPILATION', '-isysroot', '${SDKROOT}']
prefix = '$dependency_install_prefix'
libdir = '$dependency_install_prefix/lib'
pkg_config_path = '$PKG_CONFIG_PATH'

[host_machine]
system = 'darwin'
cpu_family = '$host_arch'
cpu = '$host_arch'
endian = 'little'

[properties]
needs_exe_wrapper    = true

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

create_macos_xcframework() {
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

  # Create staging directory for this platform-arch
  local staging_dir="${WORKDIR}/apple/xcframework-staging/macos-${host_arch}"
  if [[ -d "${staging_dir}" ]]; then
    rm -rf "${staging_dir}"
  fi
  mkdir -p "${staging_dir}/Headers/json"

  # Copy library and headers
  {
    find "${work_dir}/${kit_dir}/lib" -exec cp -fv {} "${staging_dir}" \;
    find "${ffmpeg_kit_install}/include" -exec cp -fv {} "${staging_dir}/Headers" \;
    find "${work_dir}/${kit_dir}/include" -exec cp -fv {} "${staging_dir}/Headers" \;
  } > >(redirect_output) 2>&1

  echo "INFO: Created macOS XCFramework staging for macos-${host_arch}"
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
