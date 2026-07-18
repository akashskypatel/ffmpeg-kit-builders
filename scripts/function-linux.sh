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

  local cmake_params="-DCMAKE_SYSTEM_NAME=Linux \
-DCMAKE_SYSTEM_PROCESSOR=\"$cmake_host_arch\" \
-DCMAKE_C_COMPILER=\"$CC\" \
-DCMAKE_CXX_COMPILER=\"$CXX\" \
-DFFMPEG_SRC_DIR=\"$ffmpeg_source_dir\" \
-DFFMPEG_BUILD_DIR=\"$ffmpeg_install_prefix\" \
-DDEPENDENCY_BUILD_DIR=\"$dependency_install_prefix\" \
-DCMAKE_INSTALL_PREFIX=\"$ffmpeg_kit_install\" \
-DFFMPEG_KIT_BUNDLE_TYPE=\"$(get_bundle_type)\" \
-DFFMPEG_KIT_VERSION=\"$(get_latest_version_from_changelog)\""

  if [[ "$host_arch" == "aarch64" && -n "$SYSROOT" ]]; then
    cmake_params+=" -DCMAKE_SYSROOT=\"$SYSROOT\""
  fi

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
  if [[ "$host_arch" == "aarch64" ]]; then
    export SYSROOT="${SYSROOT:-/opt/sysroots/aarch64-linux-gnu}"
    export host_target="${host_target:-aarch64-linux-gnu}"
    export CROSS_COMPILE="$host_target-"
    export CC="clang"
    export CXX="clang++"
    export AS="${host_target}-as"
    export AR="${host_target}-ar"
    export LD="${host_target}-ld"
    export RANLIB="${host_target}-ranlib"
    export STRIP="${host_target}-strip"
    export NM="${host_target}-nm"
    export CFLAGS="$CFLAGS --target=aarch64-redhat-linux-gnu --sysroot=$SYSROOT"
    export CXXFLAGS="$CXXFLAGS --target=aarch64-redhat-linux-gnu --sysroot=$SYSROOT -I$SYSROOT/usr/include/c++/8 -I$SYSROOT/usr/include/c++/8/aarch64-redhat-linux"
    export LDFLAGS="$LDFLAGS --sysroot=$SYSROOT -fuse-ld=lld -B/usr/local/arm-gnu-toolchain/lib/gcc/aarch64-none-linux-gnu/13.2.1 -L$SYSROOT/usr/lib/gcc/aarch64-redhat-linux/8 -L$SYSROOT/usr/lib64 -L$SYSROOT/lib64 -L/usr/local/arm-gnu-toolchain/lib/gcc/aarch64-none-linux-gnu/13.2.1"
    export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
    export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib64/pkgconfig:$SYSROOT/usr/share/pkgconfig"
  else
    export CROSS_COMPILE=
    export CC=gcc
    export CXX=g++
    export AS=as
    export AR=ar
    export LD=ld
    export RANLIB=ranlib
    export STRIP=strip
    export NM=nm
    unset PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR
  fi
  export CFLAGS="$CFLAGS -Wl,--allow-multiple-definition,--warn-once -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"
  export CXXFLAGS="$CXXFLAGS -I${ffmpeg_source_dir} -I${ffmpeg_source_dir}/compat"
  export LDFLAGS="$LDFLAGS -Wl,--allow-multiple-definition,--warn-once -ljsoncpp -L${ffmpeg_install_prefix}/lib"
}

ffmpeg_patches() {
	if islinux; then
		echo "INFO: Patching ffmpeg for linux quirks..." >>"$LOG_FILE"
		
		echo "INFO: Done patching ffmpeg for linux quirks." >>"$LOG_FILE"
	fi
}
