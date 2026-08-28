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

set_toolchain_paths() {
  local emscripten_bin="${EMSDK_ROOT}/upstream/emscripten"
  local python_bin="$(dirname "${EMSDK_BOOTSTRAP_PYTHON:-/opt/python/cp312-cp312/bin/python3}")"

  export PATH="${python_bin}:${emscripten_bin}:${ffmpeg_install_prefix}/bin:${dependency_install_prefix}/bin:${original_path:-$PATH}"
  export CROSS_COMPILE=
  export cross_prefix=
  export CC="${emscripten_bin}/emcc"
  export CXX="${emscripten_bin}/em++"
  export AS="$CC"
  export AR="${emscripten_bin}/emar"
  export LD="$CC"
  export RANLIB="${emscripten_bin}/emranlib"
  export STRIP="${emscripten_bin}/emstrip"
  export NM="${emscripten_bin}/emnm"
  export WINDRES=
  export RC=
  export CMAKE_TOOLCHAIN_FILE="$EMSDK_CMAKE_TOOLCHAIN_FILE"

  export PKG_CONFIG_PATH="${install_pkgconfig_dir}:${dependency_install_prefix}/share/pkgconfig:${work_dir}/pkgconfig:${ffmpeg_install_prefix}/lib/pkgconfig"
  export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
  unset PKG_CONFIG_SYSROOT_DIR
}

detect_clang_version() {
  "$CC" --version 2>/dev/null | gsed -nE 's/^.*clang version ([0-9]+).*$/\1/p' | head -n 1
}

# 1. variant
# @. custom CMake KEY=VALUE settings
get_generic_cmake_toolchain() {
  local variant="$1"
  local toolchain_filename="$host_name-toolchain.cmake"
  local toolchain_path="$src_dir/$toolchain_filename"
  [[ -n "$variant" ]] && toolchain_filename="$host_name-toolchain-$variant.cmake"
  [[ -n "$variant" ]] && toolchain_path="$(pwd)/$toolchain_filename"
  shift

  {
    echo "# Generated via get_generic_cmake_toolchain"
    echo "set(EMSCRIPTEN_ROOT_PATH \"$EMSDK_ROOT\" CACHE PATH \"Emscripten SDK root\" FORCE)"
    echo "include(\"$EMSDK_CMAKE_TOOLCHAIN_FILE\")"
    echo "set(CMAKE_C_COMPILER \"$CC\" CACHE FILEPATH \"C compiler\" FORCE)"
    echo "set(CMAKE_CXX_COMPILER \"$CXX\" CACHE FILEPATH \"C++ compiler\" FORCE)"
    echo "set(CMAKE_ASM_COMPILER \"$AS\" CACHE FILEPATH \"ASM compiler\" FORCE)"
    echo "set(CMAKE_AR \"$AR\" CACHE FILEPATH \"Archiver\" FORCE)"
    echo "set(CMAKE_RANLIB \"$RANLIB\" CACHE FILEPATH \"Ranlib\" FORCE)"
    echo "set(CMAKE_STRIP \"$STRIP\" CACHE FILEPATH \"Strip\" FORCE)"
    echo "set(CMAKE_FIND_ROOT_PATH \"$dependency_install_prefix\")"
    echo "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)"
    echo "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)"
    echo "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)"
    echo "set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)"

    local arg key value
    for arg in "$@"; do
      key="${arg%%=*}"
      value="${arg#*=}"
      echo "set($key \"$value\")"
    done
  } >"$toolchain_path"

  echo "$toolchain_path"
}

# 1. variant name
# 2. additional Meson cross-file content
get_generic_meson_cross_file() {
  local variant_name="$1"
  local extra_content="$2"
  local base_filepath="$src_dir/$host_name-meson-cross.emscripten.txt"
  local output_path="$base_filepath"

  cat >"$base_filepath" <<EOF
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

[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'
default_library = 'static'
prefer_static = true
backend = 'ninja'
b_lto = false
b_staticpic = false
c_args = ['-I$dependency_install_prefix/include']
cpp_args = ['-I$dependency_install_prefix/include']
c_link_args = ['-L$dependency_install_prefix/lib']
cpp_link_args = ['-L$dependency_install_prefix/lib']
prefix = '$dependency_install_prefix'
libdir = '$dependency_install_prefix/lib'
pkg_config_path = '$PKG_CONFIG_PATH'

[host_machine]
system = 'emscripten'
cpu_family = 'wasm32'
cpu = 'wasm32'
endian = 'little'

[properties]
needs_exe_wrapper = true
pkg_config_libdir = '$install_pkgconfig_dir'
EOF

  if [[ -n "$variant_name" ]]; then
    output_path="$(pwd)/$host_name-meson-cross.emscripten.$variant_name.txt"
    copy_path "$base_filepath" "$output_path" "-f"
    if [[ -n "$extra_content" ]]; then
      printf '\n%b\n' "$extra_content" >>"$output_path"
    fi
  fi

  echo "$output_path"
}

configure_ffmpeg_kit() {
  echo -e "INFO: Configuring ffmpeg kit for Emscripten" | tee -a "$LOG_FILE"

  if [[ "$build_ffmpeg_kit_type" != "static" ]]; then
    echo "INFO: Emscripten does not use the native shared-library packaging path; building ffmpeg-kit statically." | tee -a "$LOG_FILE"
    export build_ffmpeg_kit_type=static
    export ffmpeg_kit_install="${work_dir}/$(get_ffmpeg_kit_directory)"
    export ffmpeg_kit_bundle="${work_dir}/$(get_bundle_directory)"
  fi

  local type_postfix="$build_ffmpeg_kit_type"

  if truthy "$force_kit"; then
    remove_path -rf "$ffmpeg_kit_src_dir/build"
    remove_path -rf "$ffmpeg_kit_src_dir"/already_configured_*
    remove_path -rf "$ffmpeg_kit_install"
  fi

  create_dir "$ffmpeg_kit_install"
  set_toolchain_paths
  reset_allflags

  export CFLAGS="${CFLAGS} -I${ffmpeg_install_prefix}/include -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"
  export CXXFLAGS="${CXXFLAGS} -I${ffmpeg_install_prefix}/include -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"
  export LDFLAGS="${LDFLAGS} -L${ffmpeg_install_prefix}/lib -L${dependency_install_prefix}/lib"

  change_dir "$ffmpeg_kit_src_dir"
  [[ -f Makefile ]] && make distclean > >(redirect_output) 2>&1 || true

  local cmake_params="-DCMAKE_TOOLCHAIN_FILE=$(get_generic_cmake_toolchain) \
-DEMSCRIPTEN_ROOT_PATH=\"$EMSDK_ROOT\" \
-DCMAKE_SYSTEM_PROCESSOR=wasm32 \
-DCMAKE_C_COMPILER=\"$CC\" \
-DCMAKE_CXX_COMPILER=\"$CXX\" \
-DCMAKE_AR=\"$AR\" \
-DCMAKE_RANLIB=\"$RANLIB\" \
-DFFMPEG_SRC_DIR=\"$ffmpeg_source_dir\" \
-DFFMPEG_BUILD_DIR=\"$ffmpeg_install_prefix\" \
-DDEPENDENCY_BUILD_DIR=\"$dependency_install_prefix\" \
-DCMAKE_INSTALL_PREFIX=\"$ffmpeg_kit_install\" \
-DFFMPEG_KIT_BUNDLE_TYPE=\"$(get_bundle_type)\" \
-DFFMPEG_KIT_VERSION=\"$(get_latest_version_from_changelog)\" \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_STATIC_LIBS=ON \
-DBUILD_TESTS=OFF"

  truthy "$enable_libplacebo" && cmake_params+=" -DENABLE_LIBPLACEBO=ON"
  truthy "$enable_libtensorflow" && cmake_params+=" -DENABLE_LIBTENSORFLOW=ON"
  truthy "$enable_libopenvino" && cmake_params+=" -DENABLE_OPENVINO=ON"
  truthy "$enable_libtorch" && cmake_params+=" -DENABLE_LIBTORCH=ON"
  truthy "$enable_libonnxruntime" && cmake_params+=" -DENABLE_LIBONNXRUNTIME=ON"

  if truthy "$do_debug_build"; then
    cmake_params+=" -DCMAKE_BUILD_TYPE=Debug"
    CFLAGS+=" -O0 -g -fno-omit-frame-pointer"
    CXXFLAGS+=" -O0 -g -fno-omit-frame-pointer"
  else
    cmake_params+=" -DCMAKE_BUILD_TYPE=Release"
  fi

  change_dir "$ffmpeg_kit_src_dir/build" 1
  do_cmake "$cmake_params" "$ffmpeg_kit_src_dir" "$type_postfix" 1

  echo -e "INFO: Done configuring ffmpeg kit for Emscripten" | tee -a "$LOG_FILE"
}

ffmpeg_patches() {
  if iswasm; then
    echo "INFO: No FFmpeg Emscripten source patches required." >>"$LOG_FILE"
  fi
}
