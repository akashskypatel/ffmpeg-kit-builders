#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034

# required for ffmpeg-kit
build_libjsoncpp() {
  activate_meson
  local repo="https://github.com/open-source-parsers/jsoncpp"
  local lib="jsoncpp"
  local repo_ver="1.9.6"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_meson "-Dtests=false -Dcpp_link_args='-lunwind -latomic'"
  do_ninja_and_ninja_install
  license_dir_list+="$src_dir/$lib"
  change_dir "$src_dir"
}


#------------------------------------------------------------------------------     
#region------------------------ android features ------------------------------     
#------------------------------------------------------------------------------      
# build_jni               # config_options+= --disable-jni                # enable JNI support [no]
build_jni() {
  echo "INFO: Only available on Android build" >>"$LOG_FILE"
  echo "INFO: No jni library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_ladspa            # config_options+= --disable-ladspa             # enable LADSPA audio filtering [no]
build_ladspa() {
  local lib="ladspa"
  local repo="http://www.ladspa.org/download/ladspa_sdk_1.17.tgz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib/src"
  local ANDROID_CFLAGS="-Dnl_langinfo\\\(x\\\)=NULL -D__errno=__errno\\\(\\\) -D__assert2=__assert"
  export LDFLAGS="$LDFLAGS -lsndfile -lmpg123 -lmp3lame -lid3tag -lz"
  export CFLAGS="$CFLAGS ${ANDROID_CFLAGS}"
  rm -f "Makefile"
  cp -f "${PATCHDIR}/ladspa_Makefile" "Makefile"
  generic_make "CC=\"$CC\" CPP=\"$CXX\" CFLAGS=\"$CFLAGS ${ANDROID_CFLAGS}\" LDFLAGS=\"$LDFLAGS\""
  disable_nonessential "$src_dir/$lib"
  generic_make_install
  change_dir "$src_dir"
  reset_ldflags
  reset_cflags
}
# build_mediacodec        # config_options+= --disable-mediacodec         # enable Android MediaCodec support [no]
build_mediacodec() {
  echo "INFO: Only available on Android build" >>"$LOG_FILE"
  echo "INFO: No mediacodec library to compile. Library built into OS." >>"$LOG_FILE"
}
#endregion---------------------------------------------------------------------    
#region----------------------- harmony features ------------------------------     
#------------------------------------------------------------------------------    
# build_ohcodec           # config_options+= --disable-ohcodec            # enable OpenHarmony Codec support [no]
build_ohcodec() {
  echo "INFO: Only available on Harmony build" >>"$LOG_FILE"
  echo "INFO: No ohcodec library to compile. Library built into OS." >>"$LOG_FILE"
}
#endregion---------------------------------------------------------------------    
#region---------------------- linux/unix features -----------------------------     
#------------------------------------------------------------------------------    
# build_alsa              # config_options+= --disable-alsa               # disable ALSA support [autodetect]
build_alsa() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "alsa"
}
build_libusb() {
  local repo="https://github.com/libusb/libusb"
  local lib="libusb"
  local repo_ver="v1.0.29"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-udev --enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_sdl12_compat() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "sdl12-compat"
}
# build_libdc1394         # config_options+= --enable-libdc1394           # enable IIDC-1394 grabbing using libdc1394 and libraw1394 [no]
build_libdc1394() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "libdc1394"
}
# build_libdrm            # config_options+= --disable-libdrm             # disable DRM code (Linux) [autodetect]
build_libdrm() {
  install_missing_packages "valgrind-devel"
  activate_meson
  local repo="https://gitlab.freedesktop.org/mesa/libdrm"
  local lib="libdrm"
  local repo_ver="libdrm-2.4.129"
  # if [[ -d "/usr/include/valgrind" ]]; then
  #   create_dir "$dependency_install_prefix/usr/include"
  #   ln -sf /usr/include/valgrind "$dependency_install_prefix/usr/include"
  # fi
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LIBS="-ldl"
  local meson_options="-Dcairo-tests=disabled -Dc_link_args=\"-L${dependency_install_prefix}/lib $LIBS\""
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  unset LIBS
  change_dir "$src_dir"
}
# contains both libavc1394 and librom1394
build_libavc1394() {
  local repo="https://github.com/Distrotech/libavc1394"
  local lib="libavc1394"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib"
  change_dir "$src_dir/$lib/$lib"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libraw1394() {
  local repo="https://github.com/Distrotech/libraw1394"
  local lib="libraw1394"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libiec61883       # config_options+= --enable-libiec61883         # enable iec61883 via libiec61883 [no]
build_libiec61883() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "libiec61883"
}
build_libjsonc() {
  local lib="json-c"
  local repo="https://github.com/json-c/json-c"
  local repo_ver="json-c-0.18-20240915"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local extra_ld="$LDFLAGS -lunwind"
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DBUILD_SHARED_LIBS=OFF \
-DCMAKE_EXE_LINKER_FLAGS=\"$extra_ld\" \
-DCMAKE_SHARED_LINKER_FLAGS=\"$extra_ld\" \
-DCMAKE_MODULE_LINKER_FLAGS=\"$extra_ld\""
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_ldflags
}
# build_libv4l2           # config_options+= --enable-libv4l2             # enable libv4l2/v4l-utils [no]
build_libv4l2() {
  # run_valid_function "build_iconv" 1
  # run_valid_function "build_libjpeg_turbo"
  # run_valid_function "build_libjsonc"
  activate_meson
  local lib="libv4l2"
  local repo="https://github.com/gjasny/v4l-utils"
  local repo_ver="v4l-utils-1.30.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LIBS="-lintl -liconv"
  export LDFLAGS="$LDFLAGS $LIBS"
  local meson_options="-Ddoxygen-doc=disabled \
-Dv4l-utils=false \
-Dv4l-wrappers=false \
-Dqv4l2=disabled \
-Dqvidcap=disabled \
-Dv4l2-tracer=disabled \
-Dgconv=disabled \
-Ddoxygen-html=false \
-Ddoxygen-man=false \
-Dlibdvbv5=disabled \
-Dc_link_args=\"-L${dependency_install_prefix}/lib $LIBS\""
  sed -i "s/find_library('rt')/find_library('rt', required : false)/g" meson.build
  sed -i "s/find_library('argp')/find_library('argp', required : false)/g" meson.build
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  unset LIBS
  reset_ldflags
  change_dir "$src_dir"
}
# build_libxcb_shape      # config_options+= --enable-libxcb-shape        # enable X11 grabbing shape rendering [autodetect]
build_libxcb_shape() {
  # run_valid_function "build_libxcb" 1
    echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
    disable_library "libxcb-shape"
}
# build_libxcb_shm        # config_options+= --enable-libxcb-shm          # enable X11 grabbing shm communication [autodetect]
build_libxcb_shm() {
  # run_valid_function "build_libxcb" 1
    echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
    disable_library "libxcb-shm"
}
# build_libxcb_xfixes     # config_options+= --enable-libxcb-xfixes       # enable X11 grabbing mouse rendering [autodetect]
build_libxcb_xfixes() {
  # run_valid_function "build_libxcb" 1
    echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
    disable_library "libxcb-xfixes"
}
build_xcbproto() {
  install_missing_packages "xorg-x11-proto-devel"
  # https://gitlab.freedesktop.org/xorg/proto/xcbproto
  # local lib="xcbproto"
  # local repo="https://gitlab.freedesktop.org/xorg/proto/xcbproto"
  # local repo_ver="xcb-proto-1.17.0"
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # generic_configure "--enable-static --disable-shared"
  # disable_nonessential "$src_dir/$lib"
  # do_make_and_make_install
  # change_dir "$src_dir"
}
build_libxau() {
  install_missing_packages "libxau-devel"
  # # run_valid_function "build_xorgproto"
  # # https://gitlab.freedesktop.org/xorg/lib/libxau
  # local lib="libxau"
  # local repo="https://gitlab.freedesktop.org/xorg/lib/libxau"
  # local repo_ver="libXau-1.0.12"
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # automake --force-missing --add-missing > >(redirect_output) 2>&1
  # generic_configure "--enable-static --disable-shared"
  # disable_nonessential "$src_dir/$lib"
  # do_make_and_make_install
  # change_dir "$src_dir"
}
# build_libxcb            # config_options+= --enable-libxcb              # enable X11 grabbing using XCB [autodetect]
build_libxcb() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "libxcb"
}
# build_rkmpp             # config_options+= --enable-rkmpp               # enable Rockchip Media Process Platform code [no]
build_rkmpp() {
  # https://github.com/rockchip-linux/mpp
  local lib="rkmpp"
  # local repo="https://github.com/rockchip-linux/mpp"
  local repo="https://github.com/HermanChen/mpp"
  local repo_ver="1.0.11"
  disable_library "rkmpp"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_options="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_TEST=OFF \
-DBUILD_SHARED_LIBS=OFF"
  if [[ "$host_arch" == "aarch64" || "$host_arch" == "armv7a" ]]; then
    local extra_ld="$LDFLAGS -lunwind -ldl"
    cmake_options+=" -DCMAKE_SHARED_LINKER_FLAGS=\"$extra_ld\" \
-DCMAKE_MODULE_LINKER_FLAGS=\"$extra_ld\""
  fi
  generic_cmake "$cmake_options" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_v4l2_m2m          # config_options+= --disable-v4l2-m2m           # disable V4L2 mem2mem code [autodetect]
build_v4l2_m2m() {
  # https://github.com/gjasny/v4l-utils
  local lib="v4l2_m2m"
  # run_valid_function "build_libv4l2" 1
}
# build_vaapi             # config_options+= --disable-vaapi              # disable Video Acceleration API (mainly Unix/Intel) code [autodetect]
build_vaapi() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "vaapi"
}
build_xtrans() {
  install_missing_packages "xorg-x11-xtrans-devel"
  # https://gitlab.freedesktop.org/xorg/lib/libxtrans
  # local lib="xtrans"
  # local repo="https://gitlab.freedesktop.org/xorg/lib/libxtrans"
  # local repo_ver="xtrans-1.5.0"
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # generic_configure "--enable-static --disable-shared"
  # disable_nonessential "$src_dir/$lib"
  # do_make_and_make_install
  # change_dir "$src_dir"
}
build_xorgproto() {
  install_missing_packages "xorg-x11-proto-devel"
  # https://gitlab.freedesktop.org/xorg/proto/xorgproto
  # This package replaces deprecated individual proto packages like
  # xproto, kbproto, inputproto, and xextproto.
  # activate_meson
  # local lib="xorgproto"
  # local repo="https://gitlab.freedesktop.org/xorg/proto/xorgproto"
  # local repo_ver="xorgproto-2024.1"
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # generic_meson "-Dlegacy=true -Ddatadir=$dependency_install_prefix/lib"
  # remove_path -f "$install_pkgconfig_dir/trapproto.pc"
  # disable_nonessential "$src_dir/$lib"
  # do_ninja_and_ninja_install
  # change_dir "$src_dir"
}
build_xorg_macros() {
  local lib="xorg-macros"
  local repo="https://gitlab.freedesktop.org/xorg/util/macros"
  local repo_ver="util-macros-1.20.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared"
  do_make_and_make_install
  cp -f xorg-macros.pc "$install_pkgconfig_dir/xorg-macros.pc"
  change_dir "$src_dir"
}
build_libxext() {
  install_missing_packages "libXext-devel"
  # # run_valid_function "build_xorg_macros"
  # local lib="libxext"
  # local repo="https://gitlab.freedesktop.org/xorg/lib/libxext"
  # local repo_ver="libXext-1.3.6"
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # generic_configure "--enable-static --disable-shared"
  # disable_nonessential "$src_dir/$lib"
  # do_make_and_make_install
  # change_dir "$src_dir"
}
build_libxdmcp() {
  install_missing_packages "libXdmcp-devel"
  # local lib="libxdmcp"
  # local repo="https://gitlab.freedesktop.org/xorg/lib/libxdmcp"
  # local repo_ver="libXdmcp-1.1.5"
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # generic_configure "--enable-static --disable-shared"
  # disable_nonessential "$src_dir/$lib"
  # do_make_and_make_install
  # change_dir "$src_dir"
}
build_libxrender() {
  install_missing_packages "libXrender-devel"
  # local lib="libxrender"
  # local repo="https://gitlab.freedesktop.org/xorg/lib/libxrender"
  # local repo_ver="libXrender-0.9.12"
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # generic_configure "--enable-static --disable-shared"
  # disable_nonessential "$src_dir/$lib"
  # do_make_and_make_install
  # change_dir "$src_dir"
}
build_libxft() {
  install_missing_packages "libXft-devel"
  # activate_meson
  # local lib="libxft"
  # local repo="https://gitlab.freedesktop.org/xorg/lib/libxft"
  # local repo_ver="libXft-2.3.9"
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # local meson_options=""
  # generic_meson "$meson_options"
  # disable_nonessential "$src_dir/$lib"
  # do_ninja_and_ninja_install
  # change_dir "$src_dir"
}
build_x11() {
  install_missing_packages "libX11-devel"
  # # run_valid_function "build_xorgproto"
  # # run_valid_function "build_xtrans"
  # # run_valid_function "build_libxcb" 1
  # # run_valid_function "build_libxdmcp"
  # local lib="xlib"
  # local repo="https://github.com/mirror/libX11"
  # local repo_ver="libX11-1.8.4"
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # automake --force-missing --add-missing > >(redirect_output) 2>&1
  # generic_configure "--enable-static --disable-shared"
  # disable_nonessential "$src_dir/$lib"
  # do_make_and_make_install
  # change_dir "$src_dir"
}
# build_xlib              # config_options+= --disable-xlib               # disable xlib [autodetect]
build_xlib() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "xlib"
}
#endregion---------------------------------------------------------------------
#region------------------------ hardware features ----------------------------- 
#------------------------------------------------------------------------------
# build_amf               # config_options+= --disable-amf                # disable AMF video encoding code [autodetect]
build_amf() {
  # was https://github.com/GPUOpen-LibrariesAndSDKs/AMF
  local lib="amf_headers"
  local repo="https://github.com/GPUOpen-LibrariesAndSDKs/AMF"
  local repo_ver="v1.5.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local touch_name=$(get_small_touchfile_name "${host_name}_already_installed")
  if [ ! -f "$touch_name" ]; then
    if [ ! -d "$dependency_install_prefix/include/AMF" ]; then
      create_dir "$dependency_install_prefix/include/AMF"
    fi
    cp -av "amf/public/include/." "$dependency_install_prefix/include/AMF" >>"$LOG_FILE"
    create_touch_file 0 "$touch_name"
  else
    echo -e "INFO: amf headers already installed" >>"$LOG_FILE"
  fi
  change_dir "$src_dir"
}
# build_vulkan            # config_options+= --disable-vulkan             # disable Vulkan code [autodetect]
build_vulkan() {
  local extra_args="$1"
  # https://github.com/KhronosGroup/Vulkan-Headers  Vulkan-Headers v1.4.326
  local lib="Vulkan-Headers"
  local repo="https://github.com/KhronosGroup/Vulkan-Headers"
  local repo_ver="v1.4.335"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DVULKAN_HEADERS_ENABLE_MODULE=NO \
-DVULKAN_HEADERS_ENABLE_TESTS=NO \
-DVULKAN_HEADERS_ENABLE_INSTALL=YES $extra_args" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libmfx            # config_options+= --enable-libmfx              # enable Intel MediaSDK (AKA Quick Sync Video) code via libmfx [no]
build_libmfx() {
  # https://github.com/Intel-Media-SDK/MediaSDK
  echo "WARNING: [disabled] Library has been archived and has security issues." >>"$LOG_FILE"
}
# build_libvpl            # config_options+= --enable-libvpl              # enable Intel oneVPL code via libvpl if libmfx is not used [no]
build_libvpl() {
  local lib="libvpl"
  local repo="https://github.com/intel/libvpl"
  local repo_ver="v2.15.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release -DINSTALL_EXAMPLES=OFF -DINSTALL_DEV=ON -DBUILD_EXPERIMENTAL=OFF"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_vulkan_static     # config_options+= --enable-vulkan-static       # enable statically link to libvulkan [no]
build_vulkan_static() {
  local lib="Vulkan-Shim-Loader"
  local repo="https://github.com/BtbN/Vulkan-Shim-Loader"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release -DVULKAN_SHIM_IMPERSONATE=ON"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_avisynth          # config_options+= --enable-avisynth            # enable reading of AviSynth script files [no]
build_avisynth() {
  local lib="avisynth"
  local repo="https://github.com/AviSynth/AviSynthPlus"
  local repo_ver="v3.7.5"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/avisynth" "-DHEADERS_ONLY:bool=on"
  disable_nonessential "$src_dir/$lib/build"
  do_make "VersionGen install"
  change_dir "$src_dir"
}
#endregion---------------------------------------------------------------------
#region--------------------- cross-platform features --------------------------
#------------------------------------------------------------------------------ 
# build_bzlib             # config_options+= --disable-bzlib              # disable bzlib [autodetect]
build_bzlib() {
  # https://gitlab.com/bzip2/bzip2
  local lib="bzip2"
  local repo="https://gitlab.com/bzip2/bzip2"
  local repo_ver="bzip2-1.0.8"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_make "libbz2.a CFLAGS=\"${CFLAGS}\""
  disable_nonessential "$src_dir/$lib"
  create_dir "$dependency_install_prefix/include"
  create_dir "$dependency_install_prefix/lib"
  execute "INFO: installing bzip2 header" "ERROR: unable to install bzip2 header" "true" \
    cp -fv "$src_dir/$lib/bzlib.h" "$dependency_install_prefix/include/bzlib.h"
  execute "INFO: installing bzip2 static library" "ERROR: unable to install bzip2 static library" "true" \
    cp -fv "$src_dir/$lib/libbz2.a" "$dependency_install_prefix/lib/libbz2.a"
  change_dir "$src_dir"
    cat > "$install_pkgconfig_dir/bzip2.pc" <<EOF
prefix=$dependency_install_prefix
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: bzip2
Description: bzip2 compression library
Version: 1.0.8
Libs: -L\${libdir} -lbz2
Cflags: -I\${includedir}
EOF
}
# build_lzma              # config_options+= --disable-lzma               # disable lzma [autodetect]
build_lzma() {
  echo "NOTE FROM LZMA DEV: Users of LZMA Utils should 
  move to XZ Utils. XZ Utils support the legacy 
  .lzma format used by LZMA Utils, and can also 
  emulate the command line tools of LZMA Utils." >>"$LOG_FILE"
  local lib="xz"
  local repo="https://sourceforge.net/projects/lzmautils/files/xz-5.8.1.tar.xz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  export CFLAGS="${CFLAGS//-Dnl_langinfo\\(x\\)=NULL/}"
  export CXXFLAGS="${CXXFLAGS//-Dnl_langinfo\\(x\\)=NULL/}"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_cflags
  reset_cxxflags
}
# build_sdl2              # config_options+= --disable-sdl2               # disable sdl2 [autodetect]
build_sdl2() {
  local lib="sdl2"
  local repo="https://github.com/libsdl-org/SDL"
  local repo_ver="release-2.32.8"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # SDL2 2.x requires CMake; autotools support was removed.
  # Build in a separate directory and pass the NDK toolchain file so SDL2's
  # Android-specific audio/video backends (OpenSL ES, AAudio, ANativeWindow)
  # are compiled in.
  local toolchain
  toolchain="$(get_generic_cmake_toolchain)"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" \
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain \
-DSDL_SHARED=OFF \
-DSDL_STATIC=ON \
-DSDL_STATIC_PIC=ON \
-DSDL_TEST=OFF \
-DSDL_TESTS=OFF \
-DSDL_HIDAPI=OFF \
-DSDL_OPENSL=ON \
-DSDL_AAUDIO=ON \
-DSDL_AUDIO=ON \
-DSDL_VIDEO=ON \
-DSDL_RENDER=ON"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_sndio             # config_options+= --disable-sndio              # disable sndio support [autodetect]
build_sndio() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "sndio"
}
# build_zlib              # config_options+= --disable-zlib               # disable zlib [autodetect]
build_zlib() {
  # https://github.com/madler/zlib
  local lib="zlib"
  local repo="https://github.com/madler/zlib"
  local repo_ver="v1.3.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CFLAGS="${CFLAGS//-Dnl_langinfo\\(x\\)=NULL/}"
  export CXXFLAGS="${CXXFLAGS//-Dnl_langinfo\\(x\\)=NULL/}"
  do_configure "--prefix=$dependency_install_prefix --static"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_cflags
  reset_cxxflags
}
# build_libvo_amrwbenc    # config_options+= --enable-libvo-amrwbenc      # enable AMR-WB encoding via libvo-amrwbenc [no]
build_libvo_amrwbenc() {
  local lib="libvo_amrwbenc"
  local repo="https://sourceforge.net/projects/opencore-amr/files/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libopencore_amrnb # config_options+= --enable-libopencore-amrnb   # enable AMR-NB de/encoding via libopencore-amrnb [no]
build_libopencore_amrnb() {
  local lib="libopencore_amrnb"
  local repo="https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-0.1.6.tar.gz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libopencore_amrwb # config_options+= --enable-libopencore-amrwb   # enable AMR-WB decoding via libopencore-amrwb [no]
build_libopencore_amrwb() {
  local lib="libopencore_amrwb"
  # run_valid_function "build_libopencore_amrnb" 1
}
# build_liblcevc_dec      # config_options+= --enable-liblcevc-dec        # enable LCEVC decoding via liblcevc-dec [no]
build_liblcevc_dec() {
  # https://github.com/v-novaltd/LCEVCdec
  local lib="liblcevc"
  local repo="https://github.com/v-novaltd/LCEVCdec"
  local repo_ver="4.0.4"
  change_dir "$src_dir"
  disable_git_lfs_and_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DVN_SDK_EXECUTABLES=OFF \
-DVN_SDK_UNIT_TESTS=OFF \
-DVN_SDK_DOCS=OFF \
-DVN_SDK_SAMPLE_SOURCE=OFF \
-DVN_SDK_PIPELINE_VULKAN=OFF \
-DVN_SDK_PIPELINE_LEGACY=OFF"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  if [[ -f "$install_pkgconfig_dir/lcevc_dec_utility.pc" ]]; then
    remove_path -f "$install_pkgconfig_dir/lcevc_dec_utility.pc"
  fi
}
build_fftw() {
  local lib="fftw"
  local repo="http://fftw.org/fftw-3.3.10.tar.gz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-doc --enable-static --disable-shared --enable-pic"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_chromaprint       # config_options+= --enable-chromaprint         # enable audio fingerprinting with chromaprint [no]
build_chromaprint() {
  # run_valid_function "build_fftw"
  # https://github.com/acoustid/chromaprint
  local lib="chromaprint"
  local repo="https://github.com/acoustid/chromaprint"
  local repo_ver="v1.6.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CXXFLAGS="$CXXFLAGS -fexceptions"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_TOOLS=OFF \
-DBUILD_TESTS=OFF \
-DFFT_LIB=fftw3" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  add_libs_to_pkg -t="$install_pkgconfig_dir/libchromaprint.pc" -l="-lfftw3"
  reset_allflags
}
# build_frei0r            # config_options+= --enable-frei0r              # enable frei0r video filtering [no]
build_frei0r() {
  # https://github.com/dyne/frei0r
  local lib="frei0r"
  local repo="https://github.com/dyne/frei0r"
  local repo_ver="v2.5.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DWITHOUT_GAVL=ON \
-DWITHOUT_OPENCV=1"
  local STATIC_DEPS="-lcairo -lpixman-1 -lfontconfig -lexpat -lfreetype -lpng -lbrotlidec -lbrotlicommon -lz -lm"
  local SYSTEM_DEPS="-llog -landroid -lunwind -lc++_static -lc++abi"
  if [[ $ANDROID_API_LEVEL -lt 26 ]]; then
    local shim_src="$src_dir/$lib/src/android_stdio_fix.c"
    local shim_lib_path="$src_dir/$lib/src/libandroid_stdio_fix.a"

    cat <<EOF > "$shim_src"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
FILE *stderr_shim;
FILE *stdout_shim;
void __attribute__((constructor)) init_android_shim() {
    stderr_shim = stderr;
    stdout_shim = stdout;
}
char *__gnu_strerror_r(int errnum, char *buf, size_t buflen) { return strerror(errnum); }
int mkostemp(char *template, int flags) { return mkstemp(template); }
EOF
  $CC $CFLAGS -fPIC -c "$shim_src" -o "${shim_src%.c}.o"
  $AR rcs "$shim_lib_path" "${shim_src%.c}.o"
  export LDFLAGS="$LDFLAGS -L$src_dir/$lib/src -Wl,--defsym,stderr=stderr_shim -Wl,--defsym,stdout=stdout_shim -landroid_stdio_fix"
  fi
  local link_flags="$LDFLAGS $STATIC_DEPS $SYSTEM_DEPS"
  cmake_params="$cmake_params -DCMAKE_SHARED_LINKER_FLAGS=\"$link_flags\" -DCMAKE_MODULE_LINKER_FLAGS=\"$link_flags\""
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_allflags
}
build_libgpg_error() {
  # https://github.com/gpg/libgpg-error
  local lib="libgpg-error"
  local repo="https://github.com/gpg/libgpg-error"
  local repo_ver="libgpg-error-1.45"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-doc --disable-nls --disable-languages --enable-install-gpg-error-config"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_gcrypt            # config_options+= --enable-gcrypt              # enable gcrypt, needed for rtmp(t)e support if openssl, librtmp or gmp is not used [no]
build_gcrypt() {
  # run_valid_function "build_libgpg_error"
  # https://github.com/gpg/libgcrypt #repo doesnt seem to work
  # https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.11.2.tar.bz2
  local lib="libgcrypt"
  local repo="https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.11.2.tar.bz2"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  generic_configure "--with-libgpg-error-prefix=$dependency_install_prefix LIBS=\"-lpthread -ldl\" --disable-doc --disable-amd64-as-feature-detection"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_gmp               # config_options+= --enable-gmp                 # enable gmp, needed for rtmp(t)e support if openssl or librtmp is not used [no]
build_gmp() {
  local lib="gmp"
  local repo="https://ftp.gnu.org/pub/gnu/gmp/gmp-6.3.0.tar.xz"
  local mirror="https://ftpmirror.gnu.org/pub/gnu/gmp/gmp-6.3.0.tar.xz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" --alt="$mirror"
  change_dir "$src_dir/$lib"
  generic_configure "ABI=$bits_target"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libnettle() {
  local lib="nettle"
  local repo="https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz"
  local mirror="https://ftpmirror.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" --alt="$mirror"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-openssl --disable-documentation --libdir=$dependency_install_prefix/lib" # in case we have both gnutls and openssl, just use gnutls [except that gnutls uses this so...huh?
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  cp -rfv source/. destination/ 
  change_dir "$src_dir"
}
build_brotli() {
  local lib="brotli"
  local repo="https://github.com/google/brotli"
  local repo_ver="v1.2.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CFLAGS="$CFLAGS -fPIC"
  export CXXFLAGS="$CXXFLAGS -fPIC"
  generic_cmake "-DCMAKE_INSTALL_PREFIX=$dependency_install_prefix \
-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  if [[ ! -f "$install_pkgconfig_dir/libbrotlicommon.pc" && -f "$src_dir/$lib/libbrotlicommon.pc" ]]; then
    copy_path "$src_dir/$lib/libbrotlicommon.pc" "$install_pkgconfig_dir/libbrotlicommon.pc"
    add_libs_to_pkg -t="$install_pkgconfig_dir/libbrotlicommon.pc" -l="-lbrotlicommon"
  fi
  if [[ ! -f "$install_pkgconfig_dir/libbrotlidec.pc" && -f "$src_dir/$lib/libbrotlidec.pc" ]]; then
    copy_path "$src_dir/$lib/libbrotlidec.pc" "$install_pkgconfig_dir/libbrotlidec.pc"
    add_libs_to_pkg -t="$install_pkgconfig_dir/libbrotlidec.pc" -l="-lbrotlidec -lbrotlicommon"
  fi
  if [[ ! -f "$install_pkgconfig_dir/libbrotlienc.pc" && -f "$src_dir/$lib/libbrotlienc.pc" ]]; then
    copy_path "$src_dir/$lib/libbrotlienc.pc" "$install_pkgconfig_dir/libbrotlienc.pc"
    add_libs_to_pkg -t="$install_pkgconfig_dir/libbrotlienc.pc" -l="-lbrotlienc -lbrotlicommon"
  fi
  change_dir "$src_dir"
  reset_cflags
  reset_cxxflags
}
# build_gnutls            # config_options+= --enable-gnutls              # enable gnutls, needed for https support if openssl, libtls or mbedtls is not used [no]
build_gnutls() {
  # run_valid_function "build_brotli" 1
  # run_valid_function "build_libnettle"
  local lib="gnutls"
  local repo="https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.9.tar.xz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" # v3.8.10 not found by ffmpeg with identical .pc?
  change_dir "$src_dir/$lib"
  generic_configure "--disable-cxx \
--disable-doc \
--disable-tools \
--disable-tests \
--disable-nls \
--disable-rpath \
--disable-libdane \
--disable-gcc-warnings \
--disable-code-coverage \
--without-p11-kit \
--with-idn \
--without-tpm \
--with-included-unistring \
--with-included-libtasn1 \
--disable-gtk-doc-html \
--with-brotli \
--disable-non-suiteb-curves"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_lcms2             # config_options+= --enable-lcms2               # enable ICC profile support via LittleCMS 2 [no]
build_lcms2() {
  local lib="lcms2"
  local repo_ver="lcms2.17"
  local repo="https://github.com/mm2/Little-CMS"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options=" -Dtests=disabled -Dutils=false"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
# build_libaom            # config_options+= --enable-libaom              # enable AV1 video encoding/decoding via libaom [no]
build_libaom() {
  local lib="libaom"
    local repo_ver="v3.13.1"
    local repo="https://aomedia.googlesource.com/aom"
  change_dir "$src_dir"
    do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
    change_dir "$src_dir/$lib/build" 1
    local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DCONFIG_HIGHWAY=0 \
-DENABLE_EXAMPLES=0 \
-DENABLE_TOOLS=0 \
-DENABLE_TESTS=0 \
-DBUILD_SHARED_LIBS=0 \
-DENABLE_TESTS=0 \
-DENABLE_EXAMPLES=0 \
-DENABLE_TOOLS=0 \
-DENABLE_DOCS=0"
    if [[ "$host_arch" == "aarch64" ]]; then
      cmake_params+=" -DAOM_TARGET_CPU=arm64"
    elif [[ "$host_arch" == "armv7a" ]]; then
      cmake_params+=" -DAOM_TARGET_CPU=armv7"
      export CFLAGS="${CFLAGS//-mfpu=vfpv3-d16/-mfpu=neon}"
      export CXXFLAGS="${CXXFLAGS//-mfpu=vfpv3-d16/-mfpu=neon}"
    fi
    do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
    disable_nonessential "$src_dir/$lib"
    do_make_and_make_install
      change_dir "$src_dir"
}
build_libpng() {
  # run_valid_function "build_zlib" 1
  local lib="libpng"
  local repo_ver="v1.6.53"
  local repo="https://github.com/glennrp/libpng"
  change_dir "$src_dir"
  export CPATH="$CPATH ${dependency_install_prefix}/include"
  export CFLAGS="$CFLAGS -I${dependency_install_prefix}/include"
  export CXXFLAGS=" $CXXFLAGS -I${dependency_install_prefix}/include"
  export CPPFLAGS=" $CPPFLAGS -I${dependency_install_prefix}/include"
  export LDFLAGS="$LDFLAGS -L${dependency_install_prefix}/lib -lz"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  generic_configure
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  reset_cflags
  reset_cxxflags
  reset_cppflags
  reset_ldflags
  unset CPATH
  change_dir "$src_dir"
}
# build_libaribb24        # config_options+= --enable-libaribb24          # enable ARIB text and caption decoding via libaribb24 [no]
build_libaribb24() {
  # run_valid_function "build_libpng"
  local lib="libaribb24"
  local repo_ver="v1.0.3"
  local repo="https://github.com/nkoriyama/aribb24"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  generic_configure
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libaribcaption    # config_options+= --enable-libaribcaption      # enable ARIB text and caption decoding via libaribcaption [no]
build_libaribcaption() {
  # run_valid_function "build_libfontconfig" 1
  local lib="libaribcaption"
  local repo_ver="v1.1.1"
  local repo="https://github.com/xqq/libaribcaption"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_TESTS=OFF \
-DBUILD_EXAMPLES=OFF"
  generic_cmake "$cmake_params" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libass            # config_options+= --enable-libass              # enable libass subtitles rendering, needed for subtitles and ass filter [no]
build_libass() {
  # run_valid_function "build_libfribidi"
  # run_valid_function "build_libharfbuzz"
  local lib="libass"
  local repo="https://github.com/libass/libass"
  local repo_ver="0.17.4"
  export AS=nasm
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_cross_vars
}
# build_libbluray         # config_options+= --enable-libbluray           # enable BluRay reading using libbluray [no]
build_libbluray() {
  # run_valid_function "build_lzma" 1
  local lib="libbluray"
  local repo="https://code.videolan.org/videolan/libbluray"
  local repo_ver="1.4.0"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LIBS="-lfontconfig -lfreetype -lz -llzma"
  export LDFLAGS="$LDFLAGS $LIBS"
  local meson_options="-Denable_examples=false \
-Dbdj_jar=disabled \
-Denable_tools=false \
-Denable_docs=false \
--wrap-mode=default \
-Dc_link_args=\"-L${dependency_install_prefix}/lib $LIBS\""
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
  unset LIBS
  reset_ldflags
}
# build_libbs2b           # config_options+= --enable-libbs2b             # enable bs2b DSP library [no]
build_libbs2b() {
  # run_valid_function "build_libsndfile"
  local lib="libbs2b"
  local repo="https://downloads.sourceforge.net/project/bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.gz"
  local repo_ver="3.1.0"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  touch "no.autoreconf"
  if [ -f "/usr/share/misc/config.sub" ]; then
    cp -f /usr/share/misc/config.sub "$src_dir/$lib/build-aux/config.sub"
    cp -f /usr/share/misc/config.guess "$src_dir/$lib/build-aux/config.guess"
  else
    # Fallback: Download modern versions if not found locally
    curl -L "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD" -o "$src_dir/$lib/build-aux/config.sub" > /dev/null 2>&1
    curl -L "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD" -o "$src_dir/$lib/build-aux/config.guess" > /dev/null 2>&1
  fi
  sed -i.bak "s/AC_FUNC_MALLOC//" configure.ac # #270
  export LIBS="-lm"                              # avoid pow failure linux native
  export CFLAGS="$CFLAGS -I${dependency_install_prefix}/include"
  export CXXFLAGS=" $CXXFLAGS -I${dependency_install_prefix}/include"
  export LDFLAGS="$LDFLAGS -L${dependency_install_prefix}/lib"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  reset_cflags
  reset_cxxflags
  reset_ldflags
  unset LIBS
  change_dir "$src_dir"
}
# build_libcaca           # config_options+= --enable-libcaca             # enable textual display using libcaca [no]
build_libcaca() {
  local lib="libcaca"
  local repo_ver="v0.99.beta20"
  local repo="https://github.com/cacalabs/libcaca"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CFLAGS="$CFLAGS -Wno-ignored-optimization-argument"
  sed -i 's/AC_PREREQ([2.71])/# AC_PREREQ([2.71])/g' configure.ac
  generic_configure "--libdir=$dependency_install_prefix/lib \
--disable-csharp \
--disable-java  \
--disable-python \
--disable-ruby \
--disable-doc \
--disable-cocoa \
--disable-tools \
--disable-ncurses \
--disable-pango \
--disable-x11 \
--disable-imlib2 \
--disable-cxx \
ac_cv_func_fldln2=no \
ac_cv_header_fpu_control_h=no"
  disable_nonessential "$src_dir/$lib" "src"
  # If the code still fails, we use sed as a fail-safe to undefine it manually
  if [ -f "config.h" ]; then
    sed -i 's/#define HAVE_FLDLN2 1/\/* #undef HAVE_FLDLN2 *\//g' config.h
  fi
  do_make_and_make_install
  change_dir "$src_dir"
  reset_ldflags
  reset_cflags
  unset LIBS
}
# build_libcdio           # config_options+= --enable-libcdio             # enable audio CD grabbing with libcdio [no]
build_libcdio() {
  local lib="libcdio"
  local repo_ver="2.2.0"
  local repo="https://github.com/libcdio/libcdio"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  if [ -f autogen.sh ]; then
    echo "INFO: autogen.sh found. Running autogen.sh..."
    (./autogen.sh) > >(redirect_output) 2>&1 # some need this to create ./configure :|
    touch "no.autoreconf"
  fi
  generic_configure "--disable-vcd-info \
--disable-cddb \
--without-cd-info \
--without-cd-drive \
--without-cd-read \
--without-cdda-player \
--disable-example-progs \
MAKEINFO=true \
ac_cv_header_glob_h=no \
ac_cv_func_glob=no"
  for prog in cd-drive cd-info cd-read iso-info iso-read mmc-tool; do
    touch src/"$prog".1
  done
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  local lib="libcdio-paranoia"
  local repo_ver="release-10.2+2.0.2"
  local repo="https://github.com/libcdio/libcdio-paranoia"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  if [ -f autogen.sh ]; then
    echo "INFO: autogen.sh found. Running autogen.sh..."
    (./autogen.sh) > >(redirect_output) 2>&1 # some need this to create ./configure :|
    touch "no.autoreconf"
  fi
  generic_configure "--disable-example-progs MAKEINFO=true"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libcelt           # config_options+= --enable-libcelt             # enable CELT decoding via libcelt [no]
build_libcelt() {
  # run_valid_function "build_libopus" 1
  local lib="libcelt"
  echo -e "The celt codec design and implementation have been merged into
the IETF Codec Working Group's \"Opus\" codec. As such, this
repository is no longer under active development.

Please see https://git.xiph.org/?p=opus
and https://git.xiph.org/?p=users/jm/opus-tools.git for more
current work. Visit http://opus-codec.org/ for more
information.

We apologize for any inconvenience this has caused.
" >>"$LOG_FILE"
    # https://github.com/xiph/opus
}
# build_libcodec2         # config_options+= --enable-libcodec2           # enable codec2 en/decoding using libcodec2 [no]
build_libcodec2_codebook() {
  local lib="libcodec2"
  local repo_ver="1.2.0"
  local repo="https://github.com/drowe67/codec2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build_native" 1
  export CFLAGS=""
  export CXXFLAGS=""
  export CPPFLAGS=""
  export LDFLAGS=""
  export CC=gcc
  export AR=ar
  export AS=as
  export RANLIB=ranlib
  export LD=ld
  export STRIP=strip
  export CXX=g++
  export CROSS_COMPILE=
  do_cmake "-DUNITTEST=OFF -DBUILD_SHARED_LIBS=OFF" "$src_dir/$lib"
  do_make "generate_codebook CC=gcc \
AR=ar \
AS=as \
RANLIB=ranlib \
LD=ld \
STRIP=strip \
CXX=g++ \
CROSS_COMPILE="
  reset_cross_vars
	change_dir "$src_dir"
  change_dir "$src_dir"
  copy_path "$src_dir/$lib/build_native/src/generate_codebook" "$dependency_install_prefix/bin/generate_codebook"
  reset_cross_vars
  reset_allflags
}
build_libcodec2() {
  local lib="libcodec2"
  local repo_ver="1.2.0"
  local repo="https://github.com/drowe67/codec2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local host_codebook_gen="$dependency_install_prefix/bin/generate_codebook"
  sed -i '/if(CMAKE_CROSSCOMPILING)/,/endif(CMAKE_CROSSCOMPILING)/d' "$src_dir/$lib/src/CMakeLists.txt"
  sed -i "s|COMMAND generate_codebook|COMMAND ${host_codebook_gen}|g" "$src_dir/$lib/src/CMakeLists.txt"
  sed -i "s|DEPENDS generate_codebook|DEPENDS |g" "$src_dir/$lib/src/CMakeLists.txt"
  if [[ "$host_arch" == "aarch64" && $ANDROID_API_LEVEL -lt 26 ]]; then
    copy_path "$PATCHDIR/libcodec2_math_shim.h" "$src_dir/$lib/src/math_shim.h" "-f"
    export CFLAGS="$CFLAGS -include $src_dir/$lib/src/math_shim.h"
  fi
  sed -i 's/\bcomplex\b/is_complex/g' "$src_dir/$lib/src/fsk_mod.c"
  do_cmake_from_build_dir "$src_dir/$lib" "-DUNITTEST=OFF -DBUILD_SHARED_LIBS=OFF -DGENERATE_CODEBOOK=${host_codebook_gen}"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_cflags
}
# build_libdav1d          # config_options+= --enable-libdav1d            # enable AV1 decoding via libdav1d [no]
build_libdav1d() {
  local lib="libdav1d"
  local repo_ver="1.5.2"
  local repo="https://code.videolan.org/videolan/dav1d"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options=" -Denable_tools=false -Denable_examples=false -Denable_tests=false"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
# build_libdavs2          # config_options+= --enable-libdavs2            # enable AVS2 decoding via libdavs2 [no]
build_libdavs2() {
  local lib="davs2"
  local repo_ver="1.7"
  local repo="https://github.com/pkuvcl/davs2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build/linux"
  touch "no.autoreconf"
  local config="--enable-pic --disable-cli --enable-static --disable-shared --prefix=$dependency_install_prefix"
  if [[ "$host_arch" == "x86_64" || "$host_arch" == "x86" ]]; then
    export AS=nasm
  elif [[ "$host_arch" == "aarch64" ]]; then
    config="$config --host=aarch64-linux --disable-asm"
    export AS=""
  elif [[ "$host_arch" == "armv7a" ]]; then
    config="$config --host=arm-linux --disable-asm"
    export AS=""
  fi
  if [[ "$host_arch" != "x86_64" && "$host_arch" != "x86" ]]; then
    sed -i -e 's/-mmmx//g' \
           -e 's/-msse[0-9.a]*//g' \
           -e 's/-mssse3//g' \
           -e 's/-mavx[0-9]*//g' \
           Makefile 2>/dev/null || true
  fi
  do_configure "$config"
  if [[ "$host_arch" == "aarch64" ]]; then
    sed -i 's/SYS_ARCH=X86_64/SYS_ARCH=AARCH64/g' "$src_dir/$lib/build/linux/config.mak"
    sed -i 's/SYS_ARCH=X86/SYS_ARCH=AARCH64/g' "$src_dir/$lib/build/linux/config.mak"
  elif [[ "$host_arch" == "armv7a" ]]; then
    sed -i 's/SYS_ARCH=X86_64/SYS_ARCH=ARM/g' "$src_dir/$lib/build/linux/config.mak"
    sed -i 's/SYS_ARCH=X86/SYS_ARCH=ARM/g' "$src_dir/$lib/build/linux/config.mak"
  fi
  disable_nonessential "$src_dir/$lib/build/linux"
  sed -i 's/$(AR)$@/$(AR) rcs $@/g' Makefile
  do_make_and_make_install ""
  if [[ ! -f "$install_pkgconfig_dir/davs2.pc" && -f "$src_dir/$lib/build/linux/davs2.pc" ]]; then
    copy_path "$src_dir/$lib/build/linux/davs2.pc" "$install_pkgconfig_dir/davs2.pc" "-f"
  fi
  sed -i "s/Version:.*/Version: ${repo_ver}.0/g" "$install_pkgconfig_dir/davs2.pc"
  change_dir "$src_dir"
  reset_cross_vars
}
# build_libdvdnav         # config_options+= --enable-libdvdnav           # enable libdvdnav, needed for DVD demuxing [no]
build_libdvdnav() {
  # run_valid_function "build_libdvdread" 1
  activate_meson
  local lib="libdvdnav"
  local repo="https://code.videolan.org/videolan/libdvdnav"
  local repo_ver="7.0.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options=" -Denable_docs=false -Denable_examples=false"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  #sed -i.bak 's/-ldvdnav.*/-ldvdnav -ldvdread -ldvdcss -lpsapi/' "$install_pkgconfig_dir/dvdnav.pc" # psapi for dlfcn ... [hrm?]
  change_dir "$src_dir"
}
build_libdvdcss() {
  activate_meson
  local lib="libdvdcss"
  local repo="https://code.videolan.org/videolan/libdvdcss"
  local repo_ver="1.5.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options=" -Denable_docs=false -Denable_examples=false"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
# build_libdvdread        # config_options+= --enable-libdvdread          # enable libdvdread, needed for DVD demuxing [no]
build_libdvdread() {
  # run_valid_function "build_libdvdcss"
  activate_meson
  local lib="libdvdread"
  local repo="https://code.videolan.org/videolan/libdvdread"
  local repo_ver="7.0.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CFLAGS="$CFLAGS -I${dependency_install_prefix}/include"
  export CXXFLAGS=" $CXXFLAGS -I${dependency_install_prefix}/include"
  export LDFLAGS="$LDFLAGS -L${dependency_install_prefix}/lib"
  local meson_options=" -Denable_docs=false"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  #sed -i.bak 's/-ldvdread.*/-ldvdread -ldvdcss/' "$install_pkgconfig_dir/dvdread.pc"
  change_dir "$src_dir"
  reset_cflags
  reset_cxxflags
  reset_ldflags
}
build_libasound2() {
  local lib="libasound2"
  local repo="https://github.com/pop-os/libasound2"
  local repo_ver="v1.2.7"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libflite          # config_options+= --enable-libflite            # enable flite (voice synthesis) support via libflite [no]
build_libflite() {
  local lib="flite"
  local repo="https://github.com/festvox/flite"
  local repo_ver="v2.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LDFLAGS="$LDFLAGS -ldl"
  generic_configure "--disable-shared --with-pic"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  add_libs_to_pkg -t="$install_pkgconfig_dir/libtiff-4.pc" -l="-llzma -ljpeg -lz -ljbig -lwebp -lLerc"
  reset_ldflags
}
# build_libfontconfig     # config_options+= --enable-libfontconfig       # enable libfontconfig, useful for drawtext filter [no]
build_libfontconfig() {
  # run_valid_function "build_libfreetype"
  # run_valid_function "build_libexpat" 1
  # run_valid_function "build_lzma" 1
  activate_meson
  local lib="fontconfig"
  local repo="https://gitlab.freedesktop.org/fontconfig/fontconfig"
  local repo_ver="2.17.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  # export LIBS="-lz -lbrotlidec -lbrotlicommon -lexpat"
  local meson_options="-Ddoc=disabled \
-Diconv=disabled \
-Dnls=disabled \
-Dtests=disabled \
-Dxml-backend=expat \
-Dtools=disabled \
-Dc_link_args=\"-L$dependency_install_prefix/lib $LIBS\""
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
  reset_ldflags
  unset LIBS
}
# build_libfreetype       # config_options+= --enable-libfreetype         # enable libfreetype, needed for drawtext filter [no]
build_libfreetype() {
  # run_valid_function "build_brotli"
  # run_valid_function "build_libpng"
  local lib="freetype"
  local repo="https://github.com/freetype/freetype"
  local repo_ver="VER-2-14-1"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dtests=disabled -Dharfbuzz=disabled -Dpng=enabled -Dbzip2=disabled -Dzlib=enabled -Dbrotli=enabled"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
# build_libfribidi        # config_options+= --enable-libfribidi          # enable libfribidi, improves drawtext filter [no]
build_libfribidi() {
  local lib="fribidi"
  local repo="https://github.com/fribidi/fribidi"
  local repo_ver="v1.0.16"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options=" -Ddeprecated=false -Ddocs=false -Dtests=false"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
build_spirv_headers() {
  local lib="SPIRV-Headers"
  local repo="https://github.com/KhronosGroup/SPIRV-Headers"
  local repo_ver="vulkan-sdk-1.4.328.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_params="-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix} \
-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DSPIRV_HEADERS_SKIP_EXAMPLES=ON"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_spirv_tools() {
  # run_valid_function "build_spirv_headers"
  local lib="SPIRV-Tools"
  local repo="https://github.com/KhronosGroup/SPIRV-Tools"
  local repo_ver="v2025.4"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local extra_ld="$LDFLAGS -lunwind"
  local cmake_params="-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix} \
-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DSPIRV_SKIP_TESTS=ON \
-DSPIRV_WERROR=OFF \
-DSPIRV_SKIP_EXECUTABLES=ON \
-DCMAKE_SHARED_LINKER_FLAGS=\"$extra_ld\" \
-DCMAKE_MODULE_LINKER_FLAGS=\"$extra_ld\" \
-DCMAKE_EXE_LINKER_FLAGS=\"$extra_ld\" \
-DSPIRV-Headers_SOURCE_DIR=${dependency_install_prefix}"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libglslang        # config_options+= --enable-libglslang          # enable GLSL->SPIRV compilation via libglslang [no]
build_libglslang() {
  # run_valid_function "build_spirv_tools"
  local lib="libglslang"
  local repo="https://github.com/KhronosGroup/glslang"
  local repo_ver="Release 16.1.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_params="-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix} \
-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DENABLE_OPT=ON \
-DENABLE_HLSL=ON \
-DBUILD_TESTING=OFF \
-DENABLE_GLSLANG_BINARIES=OFF \
-DGLSLANG_TESTS=OFF \
-DALLOW_EXTERNAL_SPIRV_TOOLS=ON \
-DCMAKE_PREFIX_PATH=${dependency_install_prefix}"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  cat > "$install_pkgconfig_dir/glslang.pc" <<EOF
prefix=${dependency_install_prefix}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: glslang
Description: Khronos glslang validator and generator
Version: 16.1.0
Requires:
Libs: -L\${libdir} -lglslang -lMachineIndependent -lGenericCodeGen -lOSDependent -lSPIRV -lSPVRemapper -lSPIRV-Tools-opt -lSPIRV-Tools -lstdc++
Cflags: -I\${includedir}
EOF
  change_dir "$src_dir"
}
# build_libgme            # config_options+= --enable-libgme              # enable Game Music Emu via libgme [no]
build_libgme() {
  local lib="libgme"
  local repo="https://bitbucket.org/mpyne/game-music-emu/downloads/game-music-emu-0.6.3.tar.xz"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DENABLE_UBSAN=0 -DCMAKE_POLICY_VERSION_MINIMUM=3.5" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libsndfile() {
  local lib="libsndfile"
  local repo="https://github.com/libsndfile/libsndfile"
  local repo_ver="1.2.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
	change_dir "$src_dir/$lib/build" 1
  local cmake_options="-DENABLE_EXTERNAL_LIBS=OFF \
-DENABLE_MPEG=OFF \
-DBUILD_PROGRAMS=OFF \
-DBUILD_EXAMPLES=OFF \
-DBUILD_TESTING=OFF \
-DENABLE_PACKAGE_CONFIG=ON \
-DINSTALL_PKGCONFIG_MODULE=ON \
-DINSTALL_MANPAGES=OFF \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_options"
  #generic_configure "--disable-sqlite --disable-external-libs --disable-full-suite --disable-mpeg --disable-alsa"
  #disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libgsm            # config_options+= --enable-libgsm              # enable GSM de/encoding via libgsm [no]
build_libgsm() {
  # run_valid_function "build_libsndfile"
  # local lib="libsndfile"
  # local repo="https://github.com/libsndfile/libsndfile"
  # local repo_ver="1.2.2"
  # change_dir "$src_dir/$lib"
  # if [[ ! -f $dependency_install_prefix/lib/libgsm.a ]]; then
  #   [[ -f "src/GSM610/gsm.h" ]] && { install -m644 src/GSM610/gsm.h "$dependency_install_prefix/include/gsm.h" || exit_message 1 "build_libgsm: could not install src/GSM610/gsm.h"; }
  #   [[ -f "src/GSM610/.libs/libgsm.a" ]] && { install -m644 src/GSM610/.libs/libgsm.a "$dependency_install_prefix/lib/libgsm.a" || exit_message 1 "build_libgsm: could not install src/GSM610/.libs/libgsm.a"; }
  # else
  #   echo -e "already installed GSM 6.10 ..." >>"$LOG_FILE"
  # fi
  # change_dir "$src_dir"
  local lib="libgsm"
  local repo="https://www.quut.com/gsm/gsm-1.0.23.tar.gz"
  local repo_ver="1.0.23"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  sed -i -e "s|^INSTALL_ROOT.*|INSTALL_ROOT = $dependency_install_prefix|g" \
  -e "s|^GSM_INSTALL_LIB.*|GSM_INSTALL_LIB = $dependency_install_prefix/lib|g" \
  -e "s|^GSM_INSTALL_INC.*|GSM_INSTALL_INC = $dependency_install_prefix/include|g" \
  -e "s|^GSM_INSTALL_MAN.*|GSM_INSTALL_MAN = $dependency_install_prefix/man|g" \
  Makefile
  export CFLAGS="$CFLAGS -c -O2 -DNeedFunctionPrototypes=1 -Wall -Wno-comment -DSASR -DWAV49 -I./inc"
  generic_make "lib/libgsm.a CFLAGS='${CFLAGS}'" "make"
  generic_make "gsminstall CFLAGS='${CFLAGS}'" "install"
  cat > "$install_pkgconfig_dir/gsm.pc" <<EOF
prefix=${dependency_install_prefix}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: gsm
Description: GSM de/encoding via libgsm
Version: 1.0.23
Requires:
Libs: -L\${libdir} -lgsm
Cflags: -I\${includedir}
EOF
}
build_graphite() {
  local lib="graphite"
  local repo="https://github.com/silnrsi/graphite"
  local repo_ver="1.3.14"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  sed -i "s/add_subdirectory(tests)/#add_subdirectory(tests)/g" CMakeLists.txt
  sed -i "s/add_subdirectory(gr2fonttest)/#add_subdirectory(gr2fonttest)/g" CMakeLists.txt
  sed -i "s/add_subdirectory(doc)/#add_subdirectory(doc)/g" CMakeLists.txt
  export LDFLAGS="$LDFLAGS -ldl"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_TESTING=OFF \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  if [[ "$host_arch" == "aarch64" ]]; then
    sed -i 's/add_definitions(-mfpmath=sse -msse2)//g' src/CMakeLists.txt
  fi
  generic_cmake "$cmake_params" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  ln -sf "$dependency_install_prefix/lib/libgraphite2.a" "$dependency_install_prefix/lib/libgraphite2.so"
  change_dir "$src_dir"
  reset_ldflags
}
# build_libharfbuzz       # config_options+= --enable-libharfbuzz         # enable libharfbuzz, needed for drawtext filter [no]
build_libharfbuzz() {
  # run_valid_function "build_graphite"
  # run_valid_function "build_cairo"
  local lib="harfbuzz"
  local repo_ver="10.4.0"
  local repo="https://github.com/harfbuzz/harfbuzz"
  activate_meson
  change_dir "$src_dir"
  # 11.0.0 no longer found by ffmpeg via this method, multiple issues, breaks harfbuzz freetype circular depends hack
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dglib=disabled \
-Dgobject=enabled \
-Dcairo=enabled \
-Dicu=disabled \
-Dtests=disabled \
-Dintrospection=disabled \
-Ddocs=disabled \
-Dgraphite=enabled \
-Dgraphite2=enabled"
  export LDFLAGS="$LDFLAGS -lbrotlidec"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  reset_ldflags
  change_dir "$src_dir"
}
# build_libilbc           # config_options+= --enable-libilbc             # enable iLBC de/encoding via libilbc [no]
build_libilbc() {
  local lib="libilbc"
  local repo="https://github.com/TimothyGu/libilbc"
  local repo_ver="v3.0.4"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DABSL_USE_EXTERNAL_GOOGLETEST=ON \
-DABSL_USE_GOOGLETEST_HEAD=OFF \
-DABSL_RUN_TESTS=OFF \
-DBUILD_SHARED_LIBS=OFF \
-DENABLE_UBSAN=0 \
-DBUILD_TESTING=OFF \
-DCMAKE_EXE_LINKER_FLAGS='-lunwind -latomic'" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}

build_tre() {
# https://github.com/laurikari/tre
  local lib="tre"
  local repo="https://github.com/laurikari/tre"
  local repo_ver="v0.9.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-nls"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}

download_asiosdk() {
  local lib="$1"
  local DIR="$src_dir/$lib/opt/asiosdk/common"
  if [[ ! -d "$DIR" ]] || [[ -z "$(find "$DIR" -maxdepth 0 -type d -empty)" ]]; then
    change_dir "$src_dir"
    download_and_unpack_file "https://download.steinberg.net/sdk_downloads/ASIO-SDK_2.3.4_2025-10-15.zip" "ASIOSDK"
    change_dir "$src_dir/ASIOSDK"
    touch "$src_dir/ASIOSDK/${host_name}_src_state.touch"
    copy_path "$src_dir/ASIOSDK" "$src_dir/$lib/opt/asiosdk" "-Rfv"
  fi
}
build_portaudio() {
  # https://github.com/PortAudio/portaudio
    local lib="portaudio"
    local repo="https://github.com/PortAudio/portaudio"
    local repo_ver="v19.7.0"
  change_dir "$src_dir"
    do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver" # meson build for fontconfig no good
    create_dir "$src_dir/$lib/opt"
    download_asiosdk "$lib"
    change_dir "$src_dir/$lib"
    touch "no.autoreconf"
    generic_configure "--with-asiodir=$src_dir/$lib/opt/asiosdk"
    # disable_nonessential "$src_dir/$lib"
    do_make_and_make_install
      change_dir "$src_dir"
}
# build_libjack           # config_options+= --enable-libjack             # enable JACK audio sound server [no]
build_libjack() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "libjack"
}
# build_libjxl            # config_options+= --enable-libjxl              # enable JPEG XL de/encoding via libjxl [no]
build_libjxl() {
  # run_valid_function "build_brotli"
  # run_valid_function "build_lcms2" 1
  # run_valid_function "build_cpuinfo"
  local lib="libjxl"
  local repo="https://github.com/libjxl/libjxl"
  local repo_ver="v0.7.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  sed -i 's/if(${ANDROID_ABI} /if("${ANDROID_ABI}" /g' "$src_dir/$lib/third_party/sjpeg/cmake/cpu.cmake"
  sed -i 's|include(third_party/testing.cmake)||g' "$src_dir/$lib/CMakeLists.txt"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_TESTING=OFF \
-DJPEGXL_ENABLE_SJPEG=OFF \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  change_dir "$src_dir/$lib/third_party/highway/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DBUILD_TESTING=OFF \
-DHWY_ENABLE_TESTS=OFF \
-DHWY_ENABLE_EXAMPLES=OFF \
-DCMAKE_POLICY_VERSION_MINIMUM=3.10 \
-DBUILD_SHARED_LIBS=OFF"
  do_cmake_from_build_dir "$src_dir/$lib/third_party/highway" "$cmake_params"
  do_make_and_make_install
  change_dir "$src_dir/$lib/build" 1
  export LDFLAGS="$LDFLAGS -lbrotlidec -lbrotlicommon"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DJPEGXL_FORCE_SYSTEM_GTEST=ON \
-DJPEGXL_FORCE_SYSTEM_HWY=ON \
-DBUILD_TESTING=OFF \
-DJPEGXL_STATIC=ON \
-DJPEGXL_ENABLE_TOOLS=OFF \
-DJPEGXL_ENABLE_BENCHMARK=OFF \
-DJPEGXL_ENABLE_EXAMPLES=OFF \
-DCMAKE_PREFIX_PATH=\"$dependency_install_prefix\" \
-DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
-DJPEGXL_ENABLE_DOXYGEN=OFF \
-DJPEGXL_ENABLE_MANPAGES=OFF \
-DJPEGXL_ENABLE_FUZZERS=OFF \
-DJPEGXL_ENABLE_VIEWERS=OFF \
-DJPEGXL_ENABLE_SJPEG=OFF \
-DJPEGXL_ENABLE_PLUGINS=OFF \
-DJPEGXL_BUNDLE_LIBPNG=OFF \
-DBUILD_TESTING=OFF \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DJPEGXL_ENABLE_JNI=OFF \
-DJPEGXL_ENABLE_TCMALLOC=OFF \
-DTHREADS_PREFER_PTHREAD_FLAG=ON \
-DATOMICS_LOCK_FREE_INSTRUCTIONS=ON \
-DJPEGXL_FORCE_SYSTEM_LCMS2=ON"
  # force third party PIC
  sed -i '1s/^/set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "Force PIC" FORCE)\n/' "$src_dir/$lib/third_party/CMakeLists.txt"
  if [[ "$host_arch" == "armv7a" ]]; then
    # Force 32-bit ARM mode and Optimize for Size (-Os) to prevent 
    # template unrolling from exceeding PC-relative branch limits.
    cmake_params+=" -DCMAKE_C_FLAGS_RELEASE=\"-marm -Os -DNDEBUG\""
    cmake_params+=" -DCMAKE_CXX_FLAGS_RELEASE=\"-marm -Os -DNDEBUG\""
  fi
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  reset_ldflags
  change_dir "$src_dir"
  reset_allflags
}
# build_libklvanc         # config_options+= --enable-libklvanc           # enable Kernel Labs VANC processing [no]
build_libklvanc() {
  local lib="libklvanc"
  local repo="https://github.com/stoth68000/libklvanc"
  local repo_ver="vid.obe.1.6.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  touch "no.autogen"
  generic_configure "--enable-static \
--disable-shared \
--disable-examples"
cat > "$install_pkgconfig_dir/libklvanc.pc" <<EOF
prefix=${dependency_install_prefix}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libklvanc
Description: VANC processing library
Version: 1.6.0
Libs: -L\${libdir} -lklvanc
Libs.private: -lz
Cflags: -I\${includedir}
EOF
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libkvazaar        # config_options+= --enable-libkvazaar          # enable HEVC encoding via libkvazaar [no]
build_libkvazaar() {
  local lib="libkvazaar"
  local repo="https://github.com/ultravideo/kvazaar"
  local repo_ver="v2.3.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  #change_dir "$src_dir/$lib/build" 1
  export ASFLAGS="$ASFLAGS -DPIC"
  local cmake_params="-DCMAKE_BUILD_TESTS=OFF \
-DCMAKE_ASM_NASM_FLAGS=\"-DPIC\"
-DBUILD_SHARED_LIBS=OFF"
  #do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  generic_configure "--disable-shared --enable-static --enable-pic --with-pic ASFLAGS=\"$ASFLAGS\""
  find . -type f -name "Makefile" -exec sed -i 's/-lrt//g' {} +
  sed -i 's/-lrt//g' "$install_pkgconfig_dir/kvazaar.pc"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_liblc3            # config_options+= --enable-liblc3              # enable LC3 de/encoding via liblc3 [no]
build_liblc3() {
  local lib="liblc3"
  local repo="https://github.com/google/liblc3"
  local repo_ver="v1.1.3"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_meson "-Dtools=false -Dpython=false"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
build_iconv_minimal() {
  local lib="libiconv-minimal"
  local repo="https://ftp.gnu.org/gnu/libiconv/libiconv-1.18.tar.gz"
  local mirror="https://ftpmirror.gnu.org/gnu/libiconv/libiconv-1.18.tar.gz"
  local repo_ver="v1.18"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" --alt="$mirror"
  change_dir "$src_dir/$lib"
  touch "no.autoreconf"
  
  generic_configure "--enable-static \
--with-sysroot=${dependency_install_prefix} \
--enable-pic \
--with-pic \
--disable-shared \
--disable-nls \
--disable-rpath \
--disable-tools \
--disable-tests \
--disable-examples \
--disable-docs \
--without-libintl-prefix \
CPPFLAGS=\"$CPPFLAGS -Dlibiconv_open=iconv_open -Dlibiconv=iconv -Dlibiconv_close=iconv_close -Dlibiconv_open_into=iconv_open_into\" \
CFLAGS=\"$CFLAGS\"" "" "minimal"
  
  disable_nonessential "$src_dir/$lib"
  do_make "" "minimal"
  do_make_install "" "-C lib install" "minimal"
  
  if [[ -f "$src_dir/$lib/include/iconv.h.inst" ]]; then
    sed -i -e '/#define iconv /d' \
           -e '/#define iconv_open /d' \
           -e '/#define iconv_close /d' \
           -e '/#define iconv_open_into /d' \
           "$src_dir/$lib/include/iconv.h.inst"

    copy_path "$src_dir/$lib/include/iconv.h.inst" "$dependency_install_prefix/include/iconv.h" "-fv" >>"$LOG_FILE" 2>&1
  fi
  change_dir "$src_dir"
}
# build_iconv             # config_options+= --disable-iconv              # disable iconv [autodetect]
build_iconv() {
  # install gettext
  # run_valid_function "build_iconv_minimal"
  # run_valid_function "build_gettext"
  # install full iconv
  local lib="libiconv"
  local repo="https://ftp.gnu.org/gnu/libiconv/libiconv-1.18.tar.gz"
  local mirror="https://ftpmirror.gnu.org/gnu/libiconv/libiconv-1.18.tar.gz"
  local repo_ver="v1.18"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" --alt="$mirror"
  change_dir "$src_dir/$lib"
  export CFLAGS="$CFLAGS -fPIC"
  export CXXFLAGS="$CXXFLAGS -fPIC"
  touch "no.autoreconf"
  generic_configure "--prefix=${dependency_install_prefix} \
--enable-static \
--disable-shared \
--enable-pic \
--with-pic \
--disable-nls \
--with-libintl-prefix=${dependency_install_prefix} \
CPPFLAGS=\"$CPPFLAGS -Dlibiconv_open=iconv_open -Dlibiconv=iconv -Dlibiconv_close=iconv_close -Dlibiconv_open_into=iconv_open_into\" \
CFLAGS=\"$CFLAGS\"" "" "full"
  do_make_and_make_install "" "" "full"
  cat > "$install_pkgconfig_dir/iconv.pc" << EOF
prefix=$dependency_install_prefix
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libiconv
Description: GNU libiconv character set conversion library
Version: 1.18
Libs: -L\${libdir} -liconv
Cflags: -I\${includedir}
EOF
  if [[ -f "$src_dir/$lib/include/iconv.h.inst" ]]; then
    sed -i -e '/#define iconv /d' \
           -e '/#define iconv_open /d' \
           -e '/#define iconv_close /d' \
           -e '/#define iconv_open_into /d' \
           "$src_dir/$lib/include/iconv.h.inst"

    copy_path "$src_dir/$lib/include/iconv.h.inst" "$dependency_install_prefix/include/iconv.h" "-fv" >>"$LOG_FILE" 2>&1
  fi
  change_dir "$src_dir"
  reset_cflags
  reset_cxxflags
}
build_gettext() {
  local lib="gettext"
  local repo="https://ftp.gnu.org/pub/gnu/gettext/gettext-1.0.tar.gz"
  local mirror="https://ftpmirror.gnu.org/pub/gnu/gettext/gettext-1.0.tar.gz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" --alt="$mirror"
  change_dir "$src_dir/$lib"
  do_autogen --skip-gnulib
  touch "no.autoreconf"
  change_dir "$src_dir/$lib/gettext-runtime"
  local gettext_cflags="$CFLAGS -Dlibintl_STATIC -Dalignof=_Alignof -Dnullptr=NULL"
  local config="--prefix=${dependency_install_prefix} \
--with-sysroot=\"${dependency_install_prefix}\" \
--with-included-libintl \
--without-libintl-prefix \
--with-included-libiconv \
--without-libiconv-prefix \
--with-included-gettext \
--enable-static \
--disable-shared \
--disable-java \
--disable-csharp \
--disable-native-java \
--disable-libasprintf \
--disable-openmp \
--disable-doc"
  export aclocal="/usr/local/bin/aclocal"
  export automake="/usr/local/bin/automake"
  export ACLOCAL="$aclocal"
  export AUTOMAKE="$automake"
  find "$src_dir/$lib" -type f -name configure -exec sed -i \
    -e 's/ACLOCAL=${ACLOCAL-"${am_missing_run}aclocal-${am__api_version}"}/ACLOCAL=${ACLOCAL-"${am_missing_run}aclocal"}/g' \
    -e 's/AUTOMAKE=${AUTOMAKE-"${am_missing_run}automake-${am__api_version}"}/AUTOMAKE=${AUTOMAKE-"${am_missing_run}automake"}/g' {} +
  touch "no.autoreconf"
  touch "no.autogen"
  generic_configure "$config \
CFLAGS=\"$gettext_cflags\" \
LDFLAGS=\"${LDFLAGS}\""
  # disable_nonessential "$src_dir/$lib"
  change_dir "$src_dir/$lib/gettext-runtime/intl"
  do_make_and_make_install "CFLAGS=\"$gettext_cflags\" LDFLAGS=\"${LDFLAGS}\"" "CFLAGS=\"$gettext_cflags\" LDFLAGS=\"${LDFLAGS}\""
  change_dir "$src_dir/$lib/gettext-runtime"
  do_make_and_make_install "CFLAGS=\"$gettext_cflags\" LDFLAGS=\"${LDFLAGS}\"" "CFLAGS=\"$gettext_cflags\" LDFLAGS=\"${LDFLAGS}\""
  cat > "$install_pkgconfig_dir/intl.pc" <<EOF
prefix=${dependency_install_prefix}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: intl
Description: GNU gettext library
Version: 1.0
Libs: -L\${libdir} -lintl -liconv
Cflags: -I\${includedir} -Dlibintl_STATIC
EOF
  change_dir "$src_dir/$lib/libtextstyle"
  touch "no.autoreconf"
  touch "no.autogen"
  generic_configure "$config \
CFLAGS=\"$gettext_cflags\""
  do_make_and_make_install
#   change_dir "$src_dir/$lib/gettext-tools"
#   config+=" --disable-curses \
# --disable-examples \
# --disable-nls \
# --disable-libasprintf \
# --without-libtextstyle-prefix"
#   touch "no.autoreconf"
#   touch "no.autogen"
#   generic_configure "$config \
# CFLAGS=\"$gettext_cflags\" \
# LDFLAGS=\"$LDFLAGS\""
#   disable_nonessential "$src_dir/$lib/gettext-tools" "examples" "tests"
#   local make_config="LDFLAGS=\"-L$src_dir/$lib/gettext-tools/.libs -L$src_dir/$lib/gettext-tools/src/.libs ${LDFLAGS}\""
#   do_make_and_make_install "$make_config" "$make_config"
  reset_allflags
  change_dir "$src_dir"
}
build_libffi() {
  local lib="libffi"
  local repo="https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" 
  change_dir "$src_dir/$lib"
  generic_configure "--disable-multi-os-directory"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_pcre2() {
  # run_valid_function "build_zlib" 1
  # run_valid_function "build_bzlib" 1
  local lib="pcre2"
  local repo="https://github.com/PCRE2Project/pcre2"
  local repo_ver="pcre2-10.47"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DPCRE2_BUILD_STATIC_LIB=ON \
-DPCRE2_BUILD_SHARED_LIB=ON \
-DPCRE2_SUPPORT_LIBBZ2=OFF \
-DPCRE2_SUPPORT_LIBZ=OFF \
-DPCRE2_BUILD_PCRE2_8=ON"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_glib() {
  # run_valid_function "build_iconv" 1
  # run_valid_function "build_libffi"
  # run_valid_function "build_pcre2"
  activate_meson
  local lib="glib"
  local repo="https://github.com/GNOME/glib"
  local repo_ver="2.82.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LIBS="-lintl -liconv"
  export LDFLAGS="$LDFLAGS -lintl -liconv"
  local meson_options="-Dforce_posix_threads=true \
-Dman-pages=disabled \
-Dsysprof=disabled \
-Dglib_debug=disabled \
-Dtests=false \
--includedir=\"${dependency_install_prefix}/include\" \
-Dc_args=\"-I${dependency_install_prefix}/include\" \
-Dcpp_args=\"-I${dependency_install_prefix}/include\" \
-Dc_link_args=\"-L${dependency_install_prefix}/lib -lintl -liconv \" \
-Dcpp_link_args=\"-L${dependency_install_prefix}/lib -lintl -liconv \" \
--wrap-mode=nofallback"
  generic_meson "$meson_options"
  do_ninja_and_ninja_install
  sed -i.bak 's/-lglib-2.0.*$/-lglib-2.0 -lintl -lm -liconv/' "$install_pkgconfig_dir/glib-2.0.pc"
  change_dir "$src_dir"
  unset LIBS
  reset_cflags
  reset_ldflags
}
# build_liblensfun        # config_options+= --enable-liblensfun          # enable lensfun lens correction [no]
build_liblensfun() {
  # run_valid_function "build_glib"
  local lib="liblensfun"
  local repo="https://github.com/lensfun/lensfun"
  local repo_ver="master"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CPPFLAGS="$CFLAGS $CPPFLAGS -DGLIB_STATIC_COMPILATION -I$dependency_install_prefix/lib/glib-2.0/include "
  export CXXFLAGS="$CFLAGS $CXXFLAGS -DGLIB_STATIC_COMPILATION -I$dependency_install_prefix/lib/glib-2.0/include "
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_STATIC=on \
-DCMAKE_INSTALL_DATAROOTDIR=$dependency_install_prefix \
-DBUILD_TESTS=off \
-DBUILD_DOC=off \
-DINSTALL_HELPER_SCRIPTS=off \
-DINSTALL_PYTHON_MODULE=OFF \
-DENABLE_DOCS=0"
  generic_cmake "$cmake_params" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  sed -i.bak 's/-llensfun/-llensfun -lstdc++/' "$install_pkgconfig_dir/lensfun.pc"
  reset_cppflags
  reset_cxxflags
  change_dir "$src_dir"
}
# build_libmodplug        # config_options+= --enable-libmodplug          # enable ModPlug via libmodplug [no]
build_libmodplug() {
  local lib="libmodplug"
  local repo="https://github.com/Konstanty/libmodplug"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib"
  change_dir "$src_dir/$lib"
  generic_configure
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_mpg123() {
  local lib="mpg123"
  local repo="https://sourceforge.net/projects/mpg123/files/mpg123/1.33.3/mpg123-1.33.3.tar.bz2/download"
  local repo_ver="r5008"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  generic_configure
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libmp3lame        # config_options+= --enable-libmp3lame          # enable MP3 encoding via libmp3lame [no]
build_libmp3lame() {
  # run_valid_function "build_mpg123"
  local lib="libmp3lame"
  local repo="https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download"
  local repo_ver="r6525"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" 
  change_dir "$src_dir/$lib"
  touch "no.autoreconf"
  generic_configure "--enable-nasm --enable-libmpg123"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  cat > "$install_pkgconfig_dir/libmp3lame.pc" <<EOF
prefix=${dependency_install_prefix}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libmp3lame
Description: High quality MPEG Audio Layer III (MP3) encoder
Version: 3.100
Libs: -L\${libdir} -lmp3lame
Libs.private: -lm
Cflags: -I\${includedir}
EOF
  change_dir "$src_dir"
}
# build_libmysofa         # config_options+= --enable-libmysofa           # enable libmysofa, needed for sofalizer filter [no]
build_libmysofa() {
  local lib="libmysofa"
  local repo="https://github.com/hoene/libmysofa"
  local repo_ver="latest"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DBUILD_TESTS=0 -DCMAKE_POLICY_VERSION_MINIMUM=3.10 -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params" 
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_liboapv           # config_options+= --enable-liboapv             # enable APV encoding via liboapv [no]
build_liboapv() {
  local lib="liboapv"
  local repo="https://github.com/AcademySoftwareFoundation/openapv"
  local repo_ver="v0.2.0.4"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DOAPV_BUILD_APPS=OFF \
-DOAPV_BUILD_STATIC_LIB=ON \
-DOAPV_BUILD_SHARED_LIB=OFF \
-DCMAKE_INSTALL_LIBDIR=\"${dependency_install_prefix}/lib\" \
-DCMAKE_INSTALL_INCLUDEDIR=\"${dependency_install_prefix}/include\" \
-DENABLE_TESTS=OFF"
  if [[ "$host_arch" == "aarch64" ]]; then
      sed -i 's/set_property(SOURCE ${SSE} APPEND PROPERTY COMPILE_FLAGS "-msse4.1")//g' "$src_dir/$lib/src/CMakeLists.txt"
      sed -i 's/set_property(SOURCE ${AVX} APPEND PROPERTY COMPILE_FLAGS " -mavx2")//g' "$src_dir/$lib/src/CMakeLists.txt"
  fi
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  sed -i 's|libdir=.*|libdir=\${prefix}/lib/oapv|g' "$install_pkgconfig_dir/oapv.pc"
  sed -i 's|includedir=.*|includedir=\${prefix}/include|g' "$install_pkgconfig_dir/oapv.pc"
  change_dir "$src_dir"
}
# build_libopencv         # config_options+= --enable-libopencv           # enable video filtering via libopencv [no]
build_libopencv() {
  # run_valid_function "build_vaapi" 1
  # run_valid_function "build_libtiff"
  # run_valid_function "build_libwebp" 1
  local lib="libopencv"
  local repo="https://github.com/opencv/opencv/"
  local repo_ver="4.12.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  #export LDFLAGS="$LDFLAGS -L${ffmpeg_install_prefix}/lib -L${dependency_install_prefix}/lib -lsharpyuv -ljbig -llzma -ldeflate -lzstd -ljpeg"
  local original_pkg_path=$PKG_CONFIG_PATH
  export PKG_CONFIG_PATH="$install_pkgconfig_dir"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DWITH_FFMPEG=0 \
-DBUILD_DOCS=OFF \
-DBUILD_EXAMPLES=OFF \
-DBUILD_TESTS=OFF \
-DBUILD_PERF_TESTS=OFF \
-DBUILD_opencv_apps=OFF \
-DOAPV_BUILD_STATIC_LIB=ON \
-DOAPV_BUILD_SHARED_LIB=OFF \
-DOPENCV_GENERATE_PKGCONFIG=ON \
-DOPENCV_FORCE_3RDPARTY_BUILD=ON \
-DOPENCV_INSTALL_APPS_LIST="" \
-DWITH_IPP=OFF \
-DHAVE_IPP=OFF \
-DBUILD_IPP_IW=OFF \
-DWITH_ITT=OFF \
-DHAVE_ITT=OFF \
-DBUILD_ITT=OFF \
-DBUILD_JAVA=OFF \
-DBUILD_opencv_java=OFF \
-DBUILD_opencv_java_bindings_generator=OFF \
-DDBUILD_ANDROID_PROJECTS=OFF \
-DBUILD_ANDROID_EXAMPLES=OFF \
-DINSTALL_ANDROID_EXAMPLES=OFF \
-DBUILD_PYTHON_EXAMPLES=OFF \
-DINSTALL_PYTHON_EXAMPLES=OFF \
-DBUILD_C_EXAMPLES=OFF \
-DINSTALL_C_EXAMPLES=OFF \
-DWITH_ANDROID_MEDIANDK=OFF \
-DWITH_ANDROID_NATIVE_CAMERA=OFF \
-DWITH_CPUFEATURES=OFF \
-DWITH_OPENCL=OFF \
-DCV_TRACE=OFF \
-DWITH_PROTOBUF=OFF \
-DWITH_FLATBUFFERS=OFF \
-DWITH_GSTREAMER=OFF \
-DWITH_OPENGL=OFF \
-DWITH_OPENEXR=OFF \
-DBUILD_ZLIB=OFF \
-DBUILD_TIFF=OFF \
-DBUILD_JPEG=OFF \
-DBUILD_PNG=OFF \
-DBUILD_WEBP=OFF \
-DCMAKE_SYSTEM_VERSION=$ANDROID_API_LEVEL \
-DOPENCV_INCLUDE_INSTALL_PATH=include \
-D3P_LIBRARY_OUTPUT_PATH=lib/opencv4/3rdparty \
-DOPENCV_LIB_INSTALL_PATH=lib \
-DLIBRARY_OUTPUT_PATH=lib \
-DCMAKE_INSTALL_LIBDIR=lib \
-DCMAKE_INSTALL_INCLUDEDIR=include \
-DCMAKE_EXE_LINKER_FLAGS=\"-L${dependency_install_prefix}/lib -lsharpyuv -ljbig -llzma -ldeflate -lzstd -ljpeg\" \
-DHAVE_DSHOW=0"
  if [[ $host_arch != "x86_64" ]]; then
    cmake_params+=" -DWITH_CAROTENE=ON"
  fi
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  copy_path "$src_dir/$lib/build/unix-install/opencv4.pc" "$install_pkgconfig_dir/opencv.pc" -f
  copy_path "$src_dir/$lib/build/unix-install/opencv4.pc" "$install_pkgconfig_dir/opencv4.pc" -f
  add_libs_to_pkg -t="$install_pkgconfig_dir/opencv.pc" -p="-lopencv_imgproc -lopencv_core -lkleidicv_hal -lkleidicv_thread -lkleidicv -ltegra_hal -lcarotene_objs -lz -lm -llog"
  add_libs_to_pkg -t="$install_pkgconfig_dir/opencv4.pc" -p="-lopencv_imgproc -lopencv_core -lkleidicv_hal -lkleidicv_thread -lkleidicv -ltegra_hal -lcarotene_objs -lz -lm -llog"
  find "$install_pkgconfig_dir" -name "opencv*.pc" -exec sed -i -E \
  -e 's/(^|[[:space:]])-ldl([[:space:]]|$)/ /g' \
  -e 's/(^|[[:space:]])-lpthread([[:space:]]|$)/ /g' \
  -e 's/(^|[[:space:]])-l3rdparty([[:space:]]|$)/ /g' {} +
  export PKG_CONFIG_PATH=$original_pkg_path
  mapfile -t files < <(find "$dependency_install_prefix/sdk/native/staticlibs" "$dependency_install_prefix/sdk/native/3rdparty/libs" -type f -name "*.a*")
  for file in "${files[@]}"; do
    filename=$(basename "$file")
    if [[ -f "$dependency_install_prefix/lib/$filename" ]]; then
      rm -f "$dependency_install_prefix/lib/$filename"
    fi
    ln -sf "$file" "$dependency_install_prefix/lib/"
  done
  change_dir "$src_dir"
}
# build_libopenh264       # config_options+= --enable-libopenh264         # enable H.264 encoding via OpenH264 [no]
build_libopenh264() {
  activate_meson
  local lib="libopenh264"
  local repo="https://github.com/cisco/openh264.git"
  local repo_ver="v2.6.0" #75b9fcd2669c75a99791 # wels/codec_api.h weirdness
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dtests=disabled"
  generic_meson "$meson_options"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
# build_libopenjpeg       # config_options+= --enable-libopenjpeg         # enable JPEG 2000 encoding via OpenJPEG [no]
build_libopenjpeg() {
  local lib="libopenjpeg"
  local repo="https://github.com/uclouvain/openjpeg"
  local repo_ver="v2.5.4"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DOPJ_BIG_ENDIAN=0 -DBUILD_CODEC=0" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  find "$install_pkgconfig_dir" -name "libopenjp2.pc" -exec sed -i \
  -e 's/-l-lpthread//g' \
  -e 's/-l-pthread//g' {} +
}
build_libogg() {
  local lib="libogg"
  local repo="https://github.com/xiph/ogg"
  local repo_ver="v1.3.6"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_flac() {
  # run_valid_function "build_libogg"
  local lib="flac"
  local repo="https://github.com/xiph/flac"
  local repo_ver="1.5.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DBUILD_DOCS=OFF \
-DBUILD_TESTING=OFF \
-DBUILD_EXAMPLES=OFF \
-DBUILD_PROGRAMS=OFF \
-DBUILD_STATIC_LIBS=ON \
-DBUILD_SHARED_LIBS=OFF \
-DCMAKE_BUILD_TYPE=Release \
-DINSTALL_MANPAGES=OFF"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libopenmpt        # config_options+= --enable-libopenmpt          # enable decoding tracked files via libopenmpt [no]
build_libopenmpt() {
  # run_valid_function "build_flac"
  # run_valid_function "build_zlib" 1
  # run_valid_function "build_mpg123"
  # run_valid_function "build_libogg"
  # run_valid_function "build_libvorbis" 1
  # run_valid_function "build_sdl2" 1
  # run_valid_function "build_sdl12_compat"
  # run_valid_function "build_libsndfile"
  local lib="libopenmpt"
  #local repo="https://github.com/OpenMPT/openmpt" # doesnt work from git for some reason
  local repo="https://lib.openmpt.org/files/libopenmpt/src/libopenmpt-0.8.3+release.autotools.tar.gz"
  local repo_ver="libopenmpt-0.8.3"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  #do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  touch "no.autoreconf"
  export CFLAGS="$CFLAGS -I${dependency_install_prefix}/include "
  export CXXFLAGS="$CXXFLAGS -I${dependency_install_prefix}/include "
  export LDFLAGS="$LDFLAGS -L${dependency_install_prefix}/lib -L${dependency_install_prefix}/lib/${host_target} "
  generic_configure "--enable-shared=no \
--enable-static=yes \
--without-pulseaudio \
--without-portaudiocpp \
--with-sdl2 \
--disable-openmpt123 \
--disable-examples \
--disable-tests \
--disable-doxygen-doc"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install "PREFIX=$dependency_install_prefix \
DYNLINK=0 \
SHARED_LIB=0 \
STATIC_LIB=1 \
SHARED_SONAME=0 \
IS_CROSS=1 \
NO_ZLIB=0 \
NO_LTDL=0 \
NO_DL=0 \
NO_MPG123=0 \
NO_OGG=0 \
NO_VORBIS=0 \
NO_VORBISFILE=0 \
NO_PORTAUDIO=1 \
NO_PORTAUDIOCPP=1 \
NO_PULSEAUDIO=1 \
NO_SDL=0 \
NO_SDL2=0 \
NO_SNDFILE=0 \
NO_FLAC=0 \
EXAMPLES=0 \
OPENMPT123=0 \
TEST=0"
  reset_cflags
  reset_cxxflags
  reset_ldflags
  change_dir "$src_dir"
}

# build_libopus           # config_options+= --enable-libopus             # enable Opus de/encoding via libopus [no]
build_libopus() {
  local lib="libopus"
  local repo="https://github.com/xiph/opus"
  local repo_ver="v1.5.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-doc --disable-extra-programs --disable-stack-protector --enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libunwind() {
  local lib="libunwind"
  local repo="https://github.com/libunwind/libunwind"
  local repo_ver="v1.8.3"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-shared --enable-static --disable-coredump --disable-tests --disable-documentation"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libxxhash() {
  local lib="libxxhash"
  local repo="https://github.com/Cyan4973/xxHash"
  local repo_ver="v0.8.3"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_make "CFLAGS=\"${CFLAGS}\""
  disable_nonessential "$src_dir/$lib"
  generic_make_install
  change_dir "$src_dir"
  find "$dependency_install_prefix/lib" -name "libxxhash.so*" -delete
}
build_spirv_cross() {
  local lib="SPIRV-Cross"
  local repo="https://github.com/KhronosGroup/SPIRV-Cross"
  local repo_ver="vulkan-sdk-1.4.328.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DSPIRV_CROSS_STATIC=ON \
-DSPIRV_CROSS_SHARED=OFF \
-DCMAKE_BUILD_TYPE=Release \
-DSPIRV_CROSS_CLI=OFF \
-DSPIRV_CROSS_ENABLE_TESTS=OFF \
-DSPIRV_CROSS_FORCE_PIC=ON \
-DSPIRV_CROSS_ENABLE_CPP=OFF"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  [[ -f "$install_pkgconfig_dir/spirv-cross-c.pc" ]] && mv "$install_pkgconfig_dir/spirv-cross-c.pc" "$install_pkgconfig_dir/spirv-cross-c-shared.pc"
  change_dir "$src_dir"
}
build_libdovi() {
  local lib="libdovi"
  local repo="https://github.com/quietvoid/dovi_tool"
  local repo_ver="2.3.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/dolby_vision"
  cargo_build_and_install "--release" "--package dolby_vision --release --library-type=staticlib"
  change_dir "$src_dir"
}
build_vulkan_loader() {
  local parentlib="vulkan-loader"
  local lib="Vulkan-Shim-Loader"
  local repo="https://github.com/BtbN/Vulkan-Shim-Loader"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$parentlib"
  change_dir "$src_dir/$parentlib"
  local lib="Vulkan-Headers"
  local repo="https://github.com/KhronosGroup/Vulkan-Headers"
  local repo_ver="v1.4.326"
  do_git_checkout "$repo" "$src_dir/$parentlib/$lib" "$repo_ver"
  change_dir "$src_dir/$parentlib/$lib"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release -DVULKAN_SHIM_IMPERSONATE=ON" "$src_dir/$parentlib/$lib"
  disable_nonessential "$src_dir/$parentlib/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libplacebo        # config_options+= --enable-libplacebo          # enable libplacebo library [no]
build_libplacebo() {
  # run_valid_function "build_vulkan_loader"
  # run_valid_function "build_lcms2" 1
  # run_valid_function "build_libunwind"
  # run_valid_function "build_libxxhash"
  # run_valid_function "build_spirv_cross"
  # run_valid_function "build_libdovi"
  # run_valid_function "build_libshaderc" 1
  activate_meson
  local lib="libplacebo"
  local repo="https://code.videolan.org/videolan/libplacebo"
  local repo_ver="v7.351.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local config_options+=" -Dvulkan-registry=$dependency_install_prefix/share/vulkan/registry/vk.xml"
  local meson_options=" -Ddemos=false -Dbench=false -Dfuzz=false -Dvulkan=enabled -Dvk-proc-addr=disabled -Dshaderc=disabled -Dglslang=disabled -Dc_link_args=-static -Dcpp_link_args=-static $config_options" # https://mesonbuild.com/Dependencies.html#shaderc trigger use of shaderc_combined
  generic_meson "$meson_options"
  # disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  sed -i.bak 's/-lplacebo.*$/-lplacebo -lm -lunwind -lxxhash -lstdc++/' "$install_pkgconfig_dir/libplacebo.pc"
}
build_libid3tag() {
  # run_valid_function "build_zlib" 1
  local lib="libid3tag"
  local repo="https://codeberg.org/tenacityteam/libid3tag"
  local repo_ver="0.16.3"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DBUILD_SHARED_LIBS=NO"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libpulse          # config_options+= --enable-libpulse            # enable Pulseaudio input via libpulse [no]
build_libpulse() {
  echo "INFO: Only available on Linux Desktop build" >>"$LOG_FILE"
  disable_library "libpulse"
}
# build_libqrencode       # config_options+= --enable-libqrencode         # enable QR encode generation via libqrencode [no]
build_libqrencode() {
  local lib="libqrencode"
  local repo="https://github.com/fukuchi/libqrencode"
  local repo_ver="v4.1.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DWITH_TOOLS=NO \
-DWITH_TESTS=NO \
-DWITHOUT_PNG=YES \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DBUILD_SHARED_LIBS=NO"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libquirc          # config_options+= --enable-libquirc            # enable QR decoding via libquirc [no]
build_libquirc() {
  local lib="libquirc"
  local repo="https://github.com/dlbeer/quirc"
  local repo_ver="master"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  create_dir "$src_dir/$lib/build"
  sed -i 's/all: libquirc.$(LIB_SUFFIX) qrtest/all: libquirc.$(LIB_SUFFIX)/g' "$src_dir/$lib/Makefile"
  sed -i 's|install -o root -g root -m 0755 quirc-demo $(DESTDIR)$(PREFIX)/bin|# install -o root -g root -m 0755 quirc-demo $(DESTDIR)$(PREFIX)/bin|g' "$src_dir/$lib/Makefile"
  sed -i 's|install -o root -g root -m 0755 quirc-scanner $(DESTDIR)$(PREFIX)/bin|# install -o root -g root -m 0755 quirc-scanner $(DESTDIR)$(PREFIX)/bin|g' "$src_dir/$lib/Makefile"
  sed -i 's|install: libquirc.a libquirc.$(LIB_SUFFIX) quirc-demo quirc-scanner|install: libquirc.a libquirc.$(LIB_SUFFIX)|g' "$src_dir/$lib/Makefile"
  sed -i 's/SDL_CFLAGS := .*/SDL_CFLAGS :=/g' "$src_dir/$lib/Makefile"
  sed -i 's/SDL_LIBS = .*/SDL_LIBS =/g' "$src_dir/$lib/Makefile"
  sed -i 's/OPENCV_CFLAGS := .*/OPENCV_CFLAGS :=/g' "$src_dir/$lib/Makefile"
  sed -i 's/OPENCV_LIBS = .*/OPENCV_LIBS =/g' "$src_dir/$lib/Makefile"
  do_make "libquirc.a LDFLAGS=\"-static\" PREFIX=${dependency_install_prefix}"
  disable_nonessential "$src_dir/$lib"
  do_make_install "PREFIX=${dependency_install_prefix}"
  find "$dependency_install_prefix/lib" -name "libquirc.so*" -delete
  change_dir "$src_dir"
}
# build_librabbitmq       # config_options+= --enable-librabbitmq         # enable RabbitMQ library [no]
build_librabbitmq() {
  local lib="librabbitmq"
  local repo="https://github.com/alanxz/rabbitmq-c"
  local repo_ver="v0.15.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_STATIC_LIBS=ON \
-DBUILD_EXAMPLES=OFF \
-DBUILD_TESTING=OFF \
-DBUILD_TOOLS=OFF \
-DBUILD_API_DOCS=OFF \
-DENABLE_SSL_SUPPORT=OFF \
-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix}"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  sed -i -E 's/(^|[[:space:]])-l([[:space:]]|$)/ /g' "$install_pkgconfig_dir/librabbitmq.pc"
  change_dir "$src_dir"
}
# build_librav1e          # config_options+= --enable-librav1e            # enable AV1 encoding via rav1e [no]
build_librav1e() {
  # https://github.com/xiph/rav1e
  local lib="librav1e"
  local repo="https://github.com/xiph/rav1e"
  local repo_ver="v0.8.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="${CC}"
  export RUSTFLAGS="-C linker=${CC} -C link-arg=-L${PREFIX}/lib"
  cargo_build_and_install "--no-default-features --features=asm --profile release-no-lto" "--no-default-features --library-type=staticlib --features=asm"
  change_dir "$src_dir"
  unset CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER RUSTFLAGS
}
# build_librist           # config_options+= --enable-librist             # enable RIST via librist [no]
build_librist() {
  # https://code.videolan.org/rist/librist
  local lib="librist"
  local repo="https://code.videolan.org/rist/librist"
  local repo_ver="v0.2.11"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Duse_mbedtls=true -Dbuilt_tools=false -Dtest=false"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
build_pixman() {
  # https://gitlab.freedesktop.org/pixman/pixman
  local lib="pixman"
  local repo="https://gitlab.freedesktop.org/pixman/pixman"
  local repo_ver="pixman-0.46.4"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dtests=disabled -Ddemos=disabled"
  if [[ "$host_arch" == "armv7a" ]]; then
    export CFLAGS="$CFLAGS -I$ANDROID_NDK_ROOT/sources/android/cpufeatures"
    export CPPFLAGS="$CPPFLAGS -I$ANDROID_NDK_ROOT/sources/android/cpufeatures"
    meson_options="$meson_options -Dcpu-features-path=$ANDROID_NDK_ROOT/sources/android/cpufeatures"
  fi
  generic_meson "$meson_options"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
  reset_allflags
}
build_cairo() {
  # run_valid_function "build_libpng"
  # run_valid_function "build_pixman"
  # run_valid_function "build_libfontconfig" 1
  # run_valid_function "build_glib"
   # https://gitlab.freedesktop.org/cairo/cairo
  local lib="cairo"
  local repo="https://gitlab.freedesktop.org/cairo/cairo"
  local repo_ver="1.18.4"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CFLAGS="$CFLAGS -DCAIRO_NO_MUTEX=1 -DCAIRO_HAS_PTHREAD=1 -DHAVE_UINT64_T=1 -DHAVE_STDINT_H=1 -DHAVE_CTIME_R=1"
  export CXXFLAGS="$CXXFLAGS -DCAIRO_NO_MUTEX=1 -DCAIRO_HAS_PTHREAD=1 -DHAVE_UINT64_T=1 -DHAVE_STDINT_H=1 -DHAVE_CTIME_R=1"
  export LDFLAGS="$LDFLAGS"
  export LIBS="-lfontconfig -lfreetype -lpng -lbrotlidec -lbrotlicommon -ldl -lstdc++"
  local meson_options="-Dtests=disabled \
-Dgtk_doc=false \
-Dglib=enabled \
-Dxlib=disabled \
-Dxcb=disabled \
-Dxlib-xcb=disabled \
-Dspectre=disabled \
-Dsymbol-lookup=disabled \
-Dlzo=disabled \
-Dpng=enabled \
-Dfontconfig=enabled \
-Dfreetype=enabled \
-Dtee=enabled \
-Dc_link_args=\"-L${dependency_install_prefix}/lib $LIBS\" \
-Dcpp_link_args=\"-L${dependency_install_prefix}/lib $LIBS\""
  if [[ "$host_arch" == "armv7a" ]]; then
    export CFLAGS="$CFLAGS -I$ANDROID_NDK_ROOT/sources/android/cpufeatures"
    export CPPFLAGS="$CPPFLAGS -I$ANDROID_NDK_ROOT/sources/android/cpufeatures"
  fi
  generic_meson "$meson_options"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
  unset LIBS
  reset_allflags
}
build_libexpat() {
  local lib="libexpat"
  local repo="https://github.com/libexpat/libexpat"
  local repo_ver="R_2_7_3" 
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/expat"
  [[ -f buildconf.sh ]] && ./buildconf.sh > >(redirect_output) 2>&1
  touch "no.autoreconf"
  export aclocal="/usr/local/bin/aclocal"
  export automake="/usr/local/bin/automake"
  export ACLOCAL="$aclocal"
  export AUTOMAKE="$automake"
  find "$src_dir/$lib/expat" -type f -name configure -exec sed -i \
    -e 's/ACLOCAL=${ACLOCAL-"${am_missing_run}aclocal-${am__api_version}"}/ACLOCAL=${ACLOCAL-"${am_missing_run}aclocal"}/g' \
    -e 's/AUTOMAKE=${AUTOMAKE-"${am_missing_run}automake-${am__api_version}"}/AUTOMAKE=${AUTOMAKE-"${am_missing_run}automake"}/g' {} +
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libdatrie() {
  local lib="libdatrie"
  local repo="https://github.com/tlwg/libdatrie/releases/download/v0.2.14/libdatrie-0.2.14.tar.xz"
  local repo_ver="v0.2.14" 
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared --disable-doxygen-doc LIBS=\"-liconv\""
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libthai() {
  # run_valid_function "build_libdatrie"
  local lib="libthai"
  local repo="https://github.com/tlwg/libthai/releases/download/v0.1.29/libthai-0.1.29.tar.xz"
  local repo_ver="v0.1.29" 
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" 
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared --disable-doxygen-doc --disable-dict"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_pango() {
  # run_valid_function "build_libharfbuzz" 1
  # run_valid_function "build_libthai"
  # run_valid_function "build_libexpat"
  # run_valid_function "build_xlib" 1
  # run_valid_function "build_libfribidi" 1
   # https://gitlab.gnome.org/GNOME/pango
  local lib="pango"
  local repo="https://gitlab.gnome.org/GNOME/pango"
  local repo_ver="1.57.0"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LIBS="-lfontconfig -lexpat -lfreetype -lbrotlidec -lbrotlicommon -lpng -lz -lbz2 -lintl -liconv -ldl"
  export LDFLAGS="$LDFLAGS $LIBS"
  local meson_options="-Ddocumentation=false \
-Dgtk_doc=false \
-Dman-pages=false \
-Dfontconfig=enabled \
-Dcairo=enabled \
-Dfreetype=enabled \
-Dbuild-testsuite=false \
-Dbuild-examples=false \
-Dintrospection=disabled \
-Dxft=disabled \
-Dc_args=\" -DGLIB_STATIC_COMPILATION \" \
-Dcpp_args=\" -DGLIB_STATIC_COMPILATION \" \
-Dc_link_args=\"-L${dependency_install_prefix}/lib $LIBS\" \
-Dcpp_link_args=\"-L${dependency_install_prefix}/lib $LIBS\""
  # disable tools - not needed for ffmpeg
  sed -i "s/subdir('utils')/# subdir('utils')/g" meson.build
  generic_meson "$meson_options"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
    unset LIBS
    reset_allflags
}
# build_librsvg           # config_options+= --enable-librsvg             # enable SVG rasterization via librsvg [no]
build_librsvg() {
  # run_valid_function "build_pango"
  activate_meson
  local lib="librsvg"
  local repo="https://gitlab.gnome.org/GNOME/librsvg"
  local repo_ver="2.61.3"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Ddocs=disabled \
-Dintrospection=disabled \
-Dvala=disabled \
-Davif=disabled \
-Dpixbuf-loader=disabled \
-Dtests=false \
-Drsvg-convert=disabled \
-Dtriplet=$rust_target \
-Dc_args=\"-DGLIB_STATIC_COMPILATION\" \
-Dcpp_args=\"-DGLIB_STATIC_COMPILATION\""
  generic_meson "$meson_options"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
# build_librtmp           # config_options+= --enable-librtmp             # enable RTMP[E] support via librtmp [no]
build_librtmp() {
  local lib="librtmp"
  local repo="git://git.ffmpeg.org/rtmpdump"
  local repo_ver="v2.6"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local CLEAN_CFLAGS=$(echo "$CFLAGS" | sed 's/-D__errno=__errno\(\)//g' | sed 's/-D__assert2=__assert//g')
  local RTMP_LIBS="-lpthread -ldl"
  sed -i 's/^CC[[:space:]]*=[[:space:]]*gcc/CC ?= gcc/' Makefile
  sed -i 's/^LD[[:space:]]*=[[:space:]]*$(CC)/LD ?= $(CC)/' Makefile
  sed -i 's/^AR[[:space:]]*=[[:space:]]*ar/AR ?= ar/' Makefile
  do_make "-C librtmp \
    CC=\"$CC\" \
    AR=\"$AR\" \
    RANLIB=\"$RANLIB\" \
    SHARED= \
    INC=\"-I${dependency_install_prefix}/include\" \
    XCFLAGS=\"$CLEAN_CFLAGS\" \
    XLDFLAGS=\"$LDFLAGS $RTMP_LIBS\" \
    prefix=\"${dependency_install_prefix}\""
  do_make_install "-C librtmp SHARED= prefix=${dependency_install_prefix}"
  change_dir "$src_dir"
}
# build_librubberband     # config_options+= --enable-librubberband       # enable rubberband needed for rubberband filter [no]
build_librubberband() {
  # run_valid_function "build_ladspa" 1
  # run_valid_function "build_lv2" 1
  local lib="librubberband"
  local repo="https://github.com/breakfastquay/rubberband"
  local repo_ver="v4.0.0"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local extra_link_args="-Wl,--whole-archive -lunwind -Wl,--no-whole-archive -llog"
  local meson_options="-Dtests=disabled -Dcmdline=disabled -Dc_link_args=\"$extra_link_args\" -Dcpp_link_args=\"$extra_link_args\""
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
  reset_allflags
}
# build_libshaderc        # config_options+= --enable-libshaderc          # enable GLSL->SPIRV compilation via libshaderc [no]
build_libshaderc() {
  # run_valid_function "build_spirv_tools"
  local lib="libshaderc"
  local repo="https://github.com/google/shaderc"
  local repo_ver="v2025.5"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  ./utils/git-sync-deps > >(redirect_output) 2>&1
  change_dir "$src_dir/$lib"
  sed -i 's/add_subdirectory(third_party)/#add_subdirectory(third_party)/g' CMakeLists.txt
  change_dir "$src_dir/$lib/build" 1
  export LDFLAGS="$LDFLAGS -lunwind"
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=release \
-DSHADERC_SKIP_EXAMPLES=ON \
-DSHADERC_SKIP_TESTS=ON \
-DSHADERC_SKIP_EXECUTABLES=ON \
-DSPIRV_SKIP_TESTS=ON \
-DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
-DENABLE_EXCEPTIONS=ON \
-DENABLE_GLSLANG_BINARIES=OFF \
-DSPIRV_SKIP_EXECUTABLES=ON \
-DSPIRV_TOOLS_BUILD_STATIC=ON \
-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
-DSHADERC_ENABLE_WERROR_COMPILE=OFF \
-DCMAKE_CXX_FLAGS=\"$CXXFLAGS -I${dependency_install_prefix}/include/glslang\" \
-DCMAKE_C_FLAGS=\"$CFLAGS -I${dependency_install_prefix}/include/glslang\" \
-DCMAKE_SHARED_LINKER_FLAGS=\"$LDFLAGS\" \
-DCMAKE_MODULE_LINKER_FLAGS=\"$LDFLAGS\" \
-DSHADERC_ENABLE_SHARED_CRT=OFF \
-DSHADERC_ENABLE_INSTALL=ON \
-DBUILD_SHARED_LIBS=OFF"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  if [[ -f "$src_dir/$lib/build/libshaderc_util/libshaderc_util.a" ]] ; then
    copy_path "$src_dir/$lib/build/libshaderc_util/libshaderc_util.a" "$dependency_install_prefix/lib/libshaderc_util.a" >>"$LOG_FILE"
  fi
  find "$install_pkgconfig_dir" -name "shaderc*.pc" -exec sed -i 's/-lshaderc_shared/-lshaderc_combined/g' {} +
  find "$install_pkgconfig_dir" -name "shaderc*.pc" -exec sed -i "s/Libs: .*/& -lglslang -lSPIRV -lSPIRV-Tools -lSPIRV-Tools-opt -lstdc++ -lm/" {} +
  change_dir "$src_dir"
}
# build_libshine          # config_options+= --enable-libshine            # enable fixed-point MP3 encoding via libshine [no]
build_libshine() {
  local lib="libshine"
  local repo="https://github.com/toots/shine"
  local repo_ver="3.1.1" 
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libsmbclient      # config_options+= --enable-libsmbclient        # enable Samba protocol via libsmbclient [no]
build_libsmbclient() {
  local lib="libsmbclient"
  # https://git.samba.org/samba https://gitlab.com/samba-team/samba https://github.com/samba-team/samba https://www.samba.org/
  echo "INFO: [libsmbclient] Its best to just install locally as its a large library with a lot of dependencies https://wiki.samba.org/index.php/Distribution-specific_Package_Installation" >>"$LOG_FILE"
  case "${VENDOR,,}" in
    redhat)
    install_missing_packages samba libsmbclient-dev libsmbclient
    ;;
    freebsd)
    install_missing_packages net/samba44 libsmbclient-dev libsmbclient
    ;;
    sles)
    install_missing_packages samba samba-winbind samba-ad-dc libsmbclient-dev libsmbclient
    ;;
    *)
    install_missing_packages install acl attr samba winbind libpam-winbind libnss-winbind krb5-config krb5-user dnsutils python3-setproctitle ntp libsmbclient-dev libsmbclient
    ;;
  esac
}
# build_libsnappy         # config_options+= --enable-libsnappy           # enable Snappy compression, needed for hap encoding [no]
build_libsnappy() {
  local lib="libsnappy"
  local repo="https://github.com/google/snappy"
  local repo_ver="1.2.2" 
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_BINARY=OFF \
-DSNAPPY_BUILD_TESTS=OFF \
-DSNAPPY_BUILD_BENCHMARKS=OFF" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libsoxr           # config_options+= --enable-libsoxr             # enable Include libsoxr resampling [no]
build_libsoxr() {
  local lib="libsoxr"
  local repo="https://github.com/chirlu/soxr"
  local repo_ver="0.1.3" 
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DWITH_OPENMP=0 \
-DBUILD_TESTS=0 \
-DBUILD_EXAMPLES=0 \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libspeex          # config_options+= --enable-libspeex            # enable Speex de/encoding via libspeex [no]
build_libspeex() {
  local lib="libspeex"
  local repo="https://github.com/xiph/speex"
  local repo_ver="Speex-1.2.1" 
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-binaries --disable-examples"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}

build_libspeexdsp() {
  # run_valid_function "build_libspeex"
  local lib="libspeexdsp"
  local repo="https://github.com/xiph/speexdsp"
  local repo_ver="SpeexDSP-1.2.1" 
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-binaries --disable-examples"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libsrt            # config_options+= --enable-libsrt              # enable Haivision SRT protocol via libsrt [no]
build_libsrt() {
  # run_valid_function "build_openssl" 1
  local lib="libsrt"
  # do_git_checkout https://github.com/Haivision/srt # might be able to use these days...?
  local repo="https://github.com/Haivision/srt"
  local repo_ver="v1.5.4" 
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local enclib
  truthy "$enable_openssl" && enclib=openssl
  truthy "$enable_gnutls" && enclib=gnutls
  truthy "$enable_mbedtls" && enclib=mbedtls
  generic_cmake "-DUSE_ENCLIB=$enclib \
-DCMAKE_BUILD_TYPE=Release \
-DENABLE_STATIC=ON \
-DENABLE_SHARED=OFF \
-DENABLE_APPS=OFF \
-DUSE_STATIC_LIBSTDCXX=ON \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libssh            # config_options+= --enable-libssh              # enable SFTP protocol via libssh [no]
build_libssh() {
  # run_valid_function "build_openssl" 1
  # run_valid_function "build_zlib" 1
  local lib="libssh"
  # https://github.com/canonical/libssh
  local repo="https://github.com/canonical/libssh"
  local repo_ver="libssh-0.11.1" 
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  export CFLAGS="${CFLAGS} -D__func__=__FUNCTION__ -DS_IWRITE=S_IWUSR -DS_IREAD=S_IRUSR -DS_IEXEC=S_IXUSR"
  if [[ "$host_arch" == "armv7a" ]]; then
    export CFLAGS="$CFLAGS -DHAVE_GETIFADDRS=1 -DHAVE_FREEIFADDRS=1"
    sed -i '1i #include <ifaddrs.h>' "$src_dir/$lib/include/libssh/config.h"
  fi
  local cmake_params="-DBUILD_SHARED_LIBS=OFF \
-DWITH_STATIC_LIB=ON \
-DWITH_EXAMPLES=OFF \
-DWITH_TESTING=OFF \
-DWITH_SERVER=OFF \
-DWITH_ZLIB=ON \
-DZLIB_ROOT=\"$dependency_install_prefix\" \
-DZLIB_INCLUDE_DIR=\"$dependency_install_prefix/include\" \
-DZLIB_LIBRARY=\"$dependency_install_prefix/lib/libz.a\" \
-DOPENSSL_USE_STATIC_LIBS=TRUE \
-DOPENSSL_ROOT_DIR=\"$dependency_install_prefix\" \
-DOPENSSL_INCLUDE_DIR=\"$dependency_install_prefix/include\" \
-DOPENSSL_CRYPTO_LIBRARY=\"$dependency_install_prefix/lib/libcrypto.a\" \
-DOPENSSL_SSL_LIBRARY=\"$dependency_install_prefix/lib/libssl.a\" \
-DWITH_SFTP=ON \
-DWITH_GSSAPI=OFF \
-DWITH_NACL=OFF \
-DWITH_PCAP=OFF \
-DHAVE_GETIFADDRS=1 \
-DHAVE_FREEIFADDRS=1 \
-DHAVE_IFADDRS_H=1 \
-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix}"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  sed -i 's/#  error "Your system must provide a __func__ macro"/#  define __func__ __FUNCTION__/g' "$src_dir/$lib/include/libssh/priv.h"
  do_make_and_make_install
  change_dir "$src_dir"
  add_libs_to_pkg -t="$install_pkgconfig_dir/libssh.pc" -l="-lcrypto"
  reset_cflags
}
build_cpuinfo() {
  local lib="cpuinfo"
  local repo="https://github.com/pytorch/cpuinfo"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "main"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DCPUINFO_LIBRARY_TYPE=static \
-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DCPUINFO_BUILD_UNIT_TESTS=OFF \
-DCPUINFO_BUILD_MOCK_TESTS=OFF \
-DCPUINFO_BUILD_BENCHMARKS=OFF \
-DCPUINFO_BUILD_TOOLS=OFF \
-DCPUINFO_TARGET_PROCESSOR=\"${cmake_host_arch}\" \
-DBUILD_SHARED_LIBS=OFF"
#   change_dir "$src_dir/$lib/deps/googletest/build" 1
#   do_cmake_from_build_dir "$src_dir/$lib/deps/googletest" "-DCMAKE_BUILD_TYPE=Release \
# -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
# -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
# -DBUILD_SHARED_LIBS=OFF"
#   do_make_and_make_install
#   change_dir "$src_dir/$lib/deps/googlebenchmark/build" 1
#   do_cmake_from_build_dir "$src_dir/$lib/deps/googlebenchmark" "-DCMAKE_BUILD_TYPE=Release \
# -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
# -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
# -DGOOGLETEST_PATH=\"$src_dir/$lib/deps/googletest\" \
# -DBENCHMARK_ENABLE_WERROR=OFF \
# -DBENCHMARK_HAS_POSIX_REGEX=0 \
# -DBENCHMARK_HAS_STD_REGEX=1 \
# -DBENCHMARK_ENABLE_EXCEPTIONS=ON \
# -DBUILD_SHARED_LIBS=OFF"
#   do_make_and_make_install
#   change_dir "$src_dir/$lib/deps/clog/build" 1
#   do_cmake_from_build_dir "$src_dir/$lib/deps/clog" "-DCMAKE_BUILD_TYPE=Release \
# -DCLOG_BUILD_TESTS=OFF \
# -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
# -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
# -DBUILD_SHARED_LIBS=OFF"
#   do_make_and_make_install
#   change_dir "$src_dir/$lib/build" 1
#   do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release \
# -DUSE_SYSTEM_LIBS=ON \
# -DUSE_SYSTEM_GOOGLEBENCHMARK=ON \
# -DUSE_SYSTEM_GOOGLETEST=ON \
# -DCPUINFO_BUILD_UNIT_TESTS=OFF \
# -DCPUINFO_BUILD_TOOLS=OFF \
# -DCPUINFO_BUILD_MOCK_TESTS=OFF \
# -DCPUINFO_BUILD_BENCHMARKS=OFF \
# -DCPUINFO_LIBRARY_TYPE=static \
# -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
# -DBUILD_SHARED_LIBS=OFF"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libsvtav1         # config_options+= --enable-libsvtav1           # enable AV1 encoding via SVT [no]
build_libsvtav1() {
  if [[ "$bits_target" != "32" ]]; then
  # run_valid_function "build_cpuinfo"
      local lib="libsvtav1"
      local repo="https://gitlab.com/AOMediaCodec/SVT-AV1"
      local repo_ver="v3.1.2"
    change_dir "$src_dir"
      do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
      change_dir "$src_dir/$lib/build" 1
      local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_TESTING=OFF \
-DBUILD_APPS=OFF \
-DUSE_CPUINFO=SYSTEM \
-DCOMPILE_C_ONLY=ON \
-DENABLE_AVX512=OFF \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON" # -DSVT_AV1_LTO=OFF if fails try adding this
      do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
      disable_nonessential "$src_dir/$lib"
      do_make_and_make_install
          change_dir "$src_dir"
    else
      echo -e "WARNING: 32bit not supported" >>"$LOG_FILE"
    fi
}
# build_libopenvino       # config_options+= --enable-libopenvino         # enable OpenVINO as a DNN module backend for DNN based filters like dnn_processing [no]
build_libopenvino() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "libopenvino"
}
# build_libtorch          # config_options+= --enable-libtorch            # enable Torch as one DNN backend [no]
build_libtorch() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "libtorch"
}
# build_libtensorflow     # config_options+= --enable-libtensorflow       # enable TensorFlow as a DNN module backend for DNN based filters like sr [no]
build_libtensorflow() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "libtensorflow"
}
build_libdeflate() {
  local lib="libdeflate"
  local repo="https://github.com/ebiggers/libdeflate"
  local repo_ver="v1.25"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=$dependency_install_prefix -DENABLE_SHARED=0"
  generic_cmake "$cmake_params" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  find "$dependency_install_prefix/lib" -name "libdeflate.so*" -delete
}
build_jbig() {
  local lib="jbig"
  local repo="https://github.com/ImageMagick/jbig"
  local repo_ver="master"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local escaped_cflags=$(echo "${CFLAGS}" | sed 's/(/\\(/g; s/)/\\)/g')
  sed -i "s|CCFLAGS = -O2 -W|CCFLAGS = -O2 -W ${escaped_cflags}|g" Makefile
  do_make
  cp -fv "$src_dir/$lib/libjbig/libjbig.a" "$dependency_install_prefix/lib/" >>"$LOG_FILE"
  cp -fv "$src_dir/$lib/libjbig/jbig.h" "$dependency_install_prefix/include/" >>"$LOG_FILE"
  cat > "$install_pkgconfig_dir/jbig.pc" <<EOF
prefix=${dependency_install_prefix}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: jbig
Description: JBIG-KIT provides a portable library of compression and decompression functions
Version: 1.6.0
Libs: -L\${libdir} -ljbig
Libs.private:
Cflags: -I\${includedir}
EOF
  change_dir "$src_dir"
}
build_lerc() {
  local lib="lerc"
  local repo="https://github.com/Esri/lerc"
  local repo_ver="v4.0.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=$dependency_install_prefix -DENABLE_SHARED=0"
  generic_cmake "$cmake_params" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libtiff() {
  # run_valid_function "build_libjpeg_turbo" # auto uses it?
  # run_valid_function "build_lzma" 1
  # run_valid_function "build_zstd"
  # run_valid_function "build_jbig"
  # run_valid_function "build_libdeflate"
  # run_valid_function "build_lerc"
  local lib="libtiff"
  local repo="https://download.osgeo.org/libtiff/tiff-4.7.1rc1.tar.gz" # "https://gitlab.com/libtiff/libtiff"
  local repo_ver="v4.7.1"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared --disable-docs --disable-tools --disable-tests"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  sed -i.bak "s/-ltiff.*$/-ltiff -llzma -ljpeg -lz/" "$install_pkgconfig_dir/libtiff-4.pc" # static deps
  change_dir "$src_dir"
}
build_libjpeg_turbo() {
  local lib="libjpeg-turbo"
  local repo="https://github.com/libjpeg-turbo/libjpeg-turbo"
  local repo_ver="3.1.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DCMAKE_INSTALL_PREFIX=$dependency_install_prefix \
-DENABLE_SHARED=0 \
-DCMAKE_ASM_NASM_COMPILER=yasm"
  if [[ "$host_arch" == "aarch64" ]]; then
    cmake_params+=" -DENABLE_NEON=ON \
-DWITH_SIMD=ON \
-DNEON_INTRINSICS=ON \
-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a \
-DCMAKE_SYSTEM_PROCESSOR=aarch64"
  fi
  generic_cmake "$cmake_params" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_giflib() {
  local lib="giflib"
  local repo="https://sourceforge.net/projects/giflib/files/giflib-5.1.4.tar.gz"
  local repo_ver="5.1.4"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  export CFLAGS="$CFLAGS -DS_IREAD=S_IRUSR -DS_IWRITE=S_IWUSR"
  generic_configure
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_cflags
}
build_libleptonica() {
  # run_valid_function "build_libpng"
  # run_valid_function "build_libwebp" 1
  # run_valid_function "build_libjpeg_turbo"
  # run_valid_function "build_giflib"
  local lib="libleptonica"
  local repo="https://github.com/DanBloomberg/leptonica"
  local repo_ver="1.86.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CPPFLAGS="$CPPFLAGS -DOPJ_STATIC"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  reset_cppflags
  change_dir "$src_dir"
}
build_lz4() {
  activate_meson
  local lib="lz4"
  local repo="https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz"
  local repo_ver="v1.10.0"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib/build/meson"
  local meson_options="-Dossfuzz=false"
  generic_meson
  # generic_cmake "-DCMAKE_BUILD_TYPE=Release -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
    change_dir "$src_dir"
}
build_libarchive() {
  # run_valid_function "build_lz4"
  local lib="libarchive"
  local repo="https://github.com/libarchive/libarchive"
  local repo_ver="v3.8.4"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  # Fix Android NDK build: remove the internal AOSP android_lf.h include
  sed -i 's|#include "android_lf.h"|/* #include "android_lf.h" */|g' libarchive/archive.h
  sed -i 's|#include "android_lf.h"|/* #include "android_lf.h" */|g' libarchive/archive_entry.h
  export CFLAGS="$CFLAGS -I${dependency_install_prefix}/include "
  export LDFLAGS="$LDFLAGS -L${dependency_install_prefix}/lib -L${dependency_install_prefix}/lib/${host_target} "
  generic_configure "--enable-static \
--disable-shared \
--bindir=$dependency_install_prefix/bin \
--without-bz2lib \
--without-lz4 \
--without-zstd \
--without-lzo2 \
--without-cng \
--without-xml2 \
--without-nettle \
--without-iconv"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  reset_cflags
  reset_ldflags
  change_dir "$src_dir"
}
build_libssh2() {
  local lib="libssh2"
  local repo="https://github.com/libssh2/libssh2"
  local repo_ver="1.11.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_zstd() {
  activate_meson
  local lib="zstd"
  local repo="https://github.com/facebook/zstd"
  local repo_ver="v1.5.7"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
   change_dir "$src_dir/$lib/build/meson"
  local meson_options="-Dbin_programs=false -Dbin_tests=false -Dbin_contrib=false -Ddebug_level=0 -Dlegacy_level=7"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib" "programs"
  do_ninja_and_ninja_install
    change_dir "$src_dir"
}
build_libpsl() {
  local lib="libpsl"
  local repo="https://github.com/rockdaboot/libpsl"
  local repo_ver="0.21.5"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  touch "no.autoreconf"
  export CFLAGS="$CFLAGS -DPSL_STATIC"
  generic_configure "--disable-nls \
--disable-rpath \
--disable-gtk-doc-html \
--disable-man \
--disable-runtime \
--enable-static \
--disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  sed -i.bak "s/Libs: .*/& -lidn2 -lunistring -liconv/" "$install_pkgconfig_dir/libpsl.pc"
  reset_cflags
  change_dir "$src_dir"
}
build_nghttp2() {
  local lib="nghttp2"
  local repo="https://github.com/nghttp2/nghttp2"
  local repo_ver="v1.68.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CFLAGS="$CFLAGS -DNGHTTP2_STATICLIB"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  reset_cflags
  change_dir "$src_dir"
}
build_libidn2() {
  # run_valid_function "build_libunistring"
  local lib="libidn2"
  local repo="https://ftp.gnu.org/gnu/libidn/libidn2-2.3.8.tar.gz"
  local mirror="https://ftpmirror.gnu.org/gnu/libidn/libidn2-2.3.8.tar.gz"
  local repo_ver="2.3.8"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" --alt="$mirror"
  change_dir "$src_dir/$lib"
  touch "no.autoreconf"
  generic_configure "--enable-static --disable-shared --with-libunistring-prefix=$dependency_install_prefix"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libunistring() {
  local lib="libunistring"
  local repo="https://ftp.gnu.org/gnu/libunistring/libunistring-1.4.1.tar.gz"
  local mirror="https://ftpmirror.gnu.org/gnu/libunistring/libunistring-1.4.1.tar.gz"
  local repo_ver="1.4.1"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" --alt="$mirror"
  change_dir "$src_dir/$lib"
  touch "no.autogen"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_curl() {  
  # run_valid_function "build_libidn2"
  # run_valid_function "build_zstd"
  # run_valid_function "build_brotli"
  # run_valid_function "build_libpsl"
  # run_valid_function "build_nghttp2"
  # run_valid_function "build_openssl" 1
  local lib="curl"
  local repo="https://github.com/curl/curl"
  local repo_ver="curl-8_17_0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  local cmake_options="-DBUILD_CURL_EXE=OFF \
-DCURL_USE_PKGCONFIG=ON \
-DBUILD_LIBCURL_DOCS=OFF \
-DBUILD_MISC_DOCS=OFF \
-DENABLE_CURL_MANUAL=OFF \
-DBUILD_TESTING=OFF \
-DBUILD_EXAMPLES=OFF \
-DCURL_USE_LIBSSH=OFF \
-DUSE_LIBRTMP=OFF"
  export CFLAGS="$CFLAGS -DNGHTTP2_STATICLIB -DPSL_STATIC "
  export CPPFLAGS="$CPPFLAGS -DNGHTTP2_STATICLIB -DPSL_STATIC "
  export CXXFLAGS="$CXXFLAGS -DNGHTTP2_STATICLIB -DPSL_STATIC "
  export LIBS="$LIBS -lpsl -lidn2 -lunistring -liconv -lbrotlidec -lbrotlicommon -lz"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_options"
  do_make_and_make_install
  reset_allflags
  unset LIBS
  change_dir "$src_dir"
  add_libs_to_pkg -t="$install_pkgconfig_dir/libcurl.pc" -l="-lcurl $LIBS"
}
# build_libtesseract      # config_options+= --enable-libtesseract        # enable Tesseract, needed for ocr filter [no]
build_libtesseract() {
  # run_valid_function "build_libleptonica"
  # run_valid_function "build_libarchive"
  local lib="libtesseract"
  local repo="https://github.com/tesseract-ocr/tesseract"
  local repo_ver="5.5.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  sed -i '/if(ANDROID)/,/endif()/d' CMakeLists.txt
  sed -i 's/add_executable(tesseract.*//g' CMakeLists.txt
  sed -i 's/target_link_libraries(tesseract.*//g' CMakeLists.txt
  sed -i 's/install(TARGETS tesseract.*//g' CMakeLists.txt
  local cmake_params="-DOPENMP_BUILD=OFF \
-DGRAPHICS_DISABLED=ON \
-DDISABLE_CURL=ON \
-DDISABLE_ARCHIVE=ON \
-DBUILD_TRAINING_TOOLS=OFF \
-DBUILD_TESTS=OFF \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_STATIC_LIBS=ON \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DENABLE_NATIVE=OFF \
-DLeptonica_DIR=$dependency_install_prefix/lib/cmake/leptonica"
  if [[ "$host_arch" == "x86_64" ]]; then
    cmake_params="$cmake_params -DOPENMP_SIMD=OFF -DHAVE_AVX:BOOL=OFF -DHAVE_AVX2:BOOL=OFF -DHAVE_FMA:BOOL=OFF -DHAVE_SSE4_1:BOOL=ON"
    # Update the x86 block to ignore Android
    sed -i 's/if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86|x86_64|AMD64|amd64|i386|i686")/if(NOT ANDROID AND CMAKE_SYSTEM_PROCESSOR MATCHES "x86|x86_64|AMD64|amd64|i386|i686")/' "$src_dir/$lib/CMakeLists.txt"
  fi
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  # TODO: add ability to download tessdata
  # https://github.com/tesseract-ocr/tessdata
  # https://github.com/tesseract-ocr/tessdata_best
  # https://github.com/tesseract-ocr/tessdata_fast
  change_dir "$src_dir"
  reset_cppflags
  add_libs_to_pkg -t="$install_pkgconfig_dir/tesseract.pc" \
  -l="-ltesseract -lleptonica -lz -larchive -ltiff -lpng16 \
      -ljpeg -lgif -lwebpmux -lwebp -lopenjp2 -ljbig -lLerc \
      -lsharpyuv -llzma -lzstd -ldeflate -lstdc++ -lm" \
  -rp="lept libarchive liblzma libtiff-4"
  reset_allflags
  reset_cross_vars
}
# build_libtheora         # config_options+= --enable-libtheora           # enable Theora encoding via libtheora [no]
build_libtheora() {
  # run_valid_function "build_libogg"
  local lib="libtheora"
  local repo="https://github.com/xiph/theora"
  local repo_ver="v1.2.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static \
--disable-shared \
--disable-doc \
--disable-spec \
--disable-oggtest \
--disable-vorbistest \
--disable-examples \
--disable-asm" # disable asm: avoid [theora @ 0x1043144a0]error in unpack_block_qpis in 64 bit... [OK OS X 64 bit tho...]
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libtls            # config_options+= --enable-libtls              # enable LibreSSL (via libtls), needed for https support if openssl, gnutls or mbedtls is not used [no]
build_libtls() {
  local lib="libtls"
  # https://github.com/PowerShell/LibreSSL
  local repo="https://github.com/PowerShell/LibreSSL"
  local repo_ver="V4.0.0.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix} \
-DBUILD_SHARED_LIBS=OFF \
-DLIBRESSL_APPS=OFF \
-DLIBRESSL_TESTS=OFF \
-DCMAKE_BUILD_TYPE=Release"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libtwolame        # config_options+= --enable-libtwolame          # enable MP2 encoding via libtwolame [no]
build_libtwolame() {
  local lib="libtwolame"
  local repo="https://github.com/njh/twolame"
  local repo_ver="0.4.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  if [[ ! -f Makefile.am.bak ]]; then # Library only, front end refuses to build for some reason with git master
    sed -i.bak "/^SUBDIRS/s/ frontend.*//" Makefile.am || exit_message 1 "build_libtwolame: could not update makefile for twolame"
  fi
  touch "no.autogen"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libuavs3d         # config_options+= --enable-libuavs3d           # enable AVS3 decoding via libuavs3d [no]
build_libuavs3d() {
  local lib="libuavs3d"
  local repo="https://github.com/uavs3/uavs3d"
  local repo_ver="master"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  chmod -R a+rwx "$src_dir/$lib/version.sh"
  (cd "$src_dir/$lib" && ./version.sh) >>"$LOG_FILE" 2>&1
  change_dir "$src_dir/$lib"
  sed -i 's/add_executable(uavs3dec ${DIR_SRC_TEST})/#add_executable(uavs3dec ${DIR_SRC_TEST})/' CMakeLists.txt
  sed -i 's|aux_source_directory(./test DIR_SRC_TEST)|#aux_source_directory(./test DIR_SRC_TEST)|' CMakeLists.txt
  sed -i 's|target_link_libraries(uavs3dec m)|#target_link_libraries(uavs3dec m)|' CMakeLists.txt
  sed -i 's|target_link_libraries(uavs3dec uavs3d)|#target_link_libraries(uavs3dec uavs3d)|' CMakeLists.txt
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCOMPILE_10BIT=0 \
-DBUILD_SHARED_LIBS=0 \
-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_THREAD_LIBS_INIT=\"\" \
-DThreads_FOUND=TRUE \
-DCMAKE_USE_PTHREADS_INIT=1 \
-DCMAKE_HAVE_PTHREADS_CREATE=1 \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DTHREADS_PREFER_PTHREAD_FLAG=ON"
  if [[ "$host_arch" == "aarch64" ]]; then
    cmake_params+=" -DUAVS3D_TARGET_CPU=arm64"
  elif [[ "$host_arch" == "armv7a" ]]; then
    cmake_params+=" -DUAVS3D_TARGET_CPU=armv7"
    sed -i 's/-mfloat-abi=hard//g' "$src_dir/$lib/source/CMakeLists.txt"
  fi
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libvidstab        # config_options+= --enable-libvidstab          # enable video stabilization using vid.stab [no]
build_libvidstab() {
  local lib="libvidstab"
  local repo="https://github.com/georgmartius/vid.stab"
  local repo_ver="v1.1.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DUSE_OMP=0 \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DBUILD_SHARED_LIBS=0" "$src_dir/$lib" # '-DUSE_OMP' is on by default, but somehow libgomp ('cygwin_local_install/lib/gcc/i686-pc-cygwin/5.4.0/include/omp.h') can't be found, so '-DUSE_OMP=0' to prevent a compilation error.
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libvmaf           # config_options+= --enable-libvmaf             # enable vmaf filter via libvmaf [no]
build_libvmaf() {
  activate_meson
  local lib="libvmaf"
  local repo="https://github.com/Netflix/vmaf"
  local repo_ver="v3.0.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/libvmaf"
  local extra_link_args="-Wl,--whole-archive -lunwind -Wl,--no-whole-archive -llog"
  local extra_meson_options="-Dc_link_args=\"$extra_link_args\" -Dcpp_link_args=\"$extra_link_args\""
  local meson_options="-Denable_float=true -Dbuilt_in_models=true -Denable_tests=false -Denable_docs=false $extra_meson_options"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  sed -i.bak "s/Libs: .*/& -lstdc++/" "$install_pkgconfig_dir/libvmaf.pc"
  change_dir "$src_dir"
}
# build_libvorbis         # config_options+= --enable-libvorbis           # enable Vorbis en/decoding via libvorbis, native implementation exists [no]
build_libvorbis() {
  # run_valid_function "build_libogg"
  local lib="libvorbis"
  local repo="https://github.com/xiph/vorbis"
  local repo_ver="v1.3.7"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  generic_configure "--disable-docs --disable-examples --disable-oggtest --enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libvpx            # config_options+= --enable-libvpx              # enable VP8 and VP9 de/encoding via libvpx [no]
build_libvpx() {
  local lib="libvpx"
  local repo="https://chromium.googlesource.com/webm/libvpx"
  local repo_ver="v1.15.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local config="--enable-static \
--disable-shared \
--disable-examples \
--disable-tools \
--disable-docs \
--disable-unit-tests \
--enable-vp9-highbitdepth \
--prefix=\"$dependency_install_prefix\""
  local vpx_target=""
  export LD="${CC}"
  export AS="${CC}"
  if [[ "$host_arch" == "x86_64" ]]; then
    export AS=nasm
    config="$config --enable-ssse3"
    vpx_target="x86_64-android-gcc"
  elif [[ "$host_arch" == "aarch64" || "$host_arch" == "armv7a" ]]; then
    export LDFLAGS="$LDFLAGS -lunwind"
    config="$config --disable-webm-io"
    if [[ "$host_arch" == "aarch64" ]]; then
      vpx_target="arm64-android-gcc"
    else
      export CFLAGS="${CFLAGS//-mfpu=vfpv3-d16/-mfpu=neon}"
      export CXXFLAGS="${CXXFLAGS//-mfpu=vfpv3-d16/-mfpu=neon}"
      vpx_target="armv7-android-gcc"
      sed -i '/#error "not hardfp"/d' "$src_dir/$lib/build/make/configure.sh"
      sed -i 's/-mfloat-abi=${float_abi}//g' "$src_dir/$lib/build/make/configure.sh"
      config="$config --disable-thumb"
    fi
  fi
  config="$config --target=$vpx_target"
  do_configure "$config" # fno for Error: invalid register for .seh_savexmm
  # disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_cross_vars
  reset_allflags
}
# build_libvvenc          # config_options+= --enable-libvvenc            # enable H.266/VVC encoding via vvenc [no]
build_libvvenc() {
  local lib="libvvenc"
  local repo="https://github.com/fraunhoferhhi/vvenc"
  local repo_ver="v1.13.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DVVENC_ENABLE_LINK_TIME_OPT=OFF \
-DBUILD_SHARED_LIBS=0 \
-DVVENC_INSTALL_FULLFEATURE_APP=OFF \
-DVVENC_LIBRARY_ONLY=ON"
  if [[ "$host_arch" == "aarch64" || "$host_arch" == "armv7a" ]]; then
    cmake_params+=" -DVVENC_ENABLE_X86_SIMD=OFF -DVVENC_ENABLE_ARM_SIMD=ON"
    export CXXFLAGS="$CXXFLAGS -Droundevenf=roundf"
    export CFLAGS="$CFLAGS -Droundevenf=roundf"
  else
    cmake_params+=" -DVVENC_ENABLE_X86_SIMD=ON"
  fi
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  # Fix corrupted pkg-config file generated by static libvvenc install
  sed -i 's/interface_libs-NOTFOUND//g' "$install_pkgconfig_dir/libvvenc.pc"
  change_dir "$src_dir"
}
# build_libwebp           # config_options+= --enable-libwebp             # enable WebP encoding via libwebp [no]
build_libwebp() {
  # run_valid_function "build_libpng"
  local lib="libwebp"
  local repo="https://chromium.googlesource.com/webm/libwebp"
  local repo_ver="v1.6.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--disable-wic --enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libx264           # config_options+= --enable-libx264             # enable H.264 encoding via x264 [no]
build_libx264() {
  local lib="libx264"
  local repo="https://code.videolan.org/videolan/x264.git"
  local repo_ver="stable"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local config="--enable-static --disable-shared --disable-cli --enable-pic"
  if [[ "$host_arch" == "x86_64" ]]; then
    export AS=nasm
  elif [[ "$host_arch" == "aarch64" ]]; then
    export AS="${CC}"
    export ASFLAGS="-x assembler-with-cpp -fPIC"
    config="$config \
ASFLAGS=\"$ASFLAGS\" \
AS=\"$CC\""
  elif [[ "$host_arch" == "armv7a" ]]; then
    export AS="${CC}"
    export ASFLAGS="-march=armv7-a -mfpu=neon -fPIC"
    config="$config \
ASFLAGS=\"$ASFLAGS\" \
AS=\"$CC\""
  fi
  generic_configure "$config"
  disable_nonessential "$src_dir/$lib"
  export AR="$AR rc "
  do_make_and_make_install "AR=\"$AR\"" "AR=\"$AR\""
  change_dir "$src_dir"
  reset_cross_vars
}
# build_libx265           # config_options+= --enable-libx265             # enable HEVC encoding via x265 [no]
build_libx265() {
  local lib="libx265"
  local repo="https://bitbucket.org/multicoreware/x265_git"
  local repo_ver="4.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # Fix for CMake > 3.0 dropping support for OLD policy behaviors
  sed -i 's/cmake_policy(SET CMP0025 OLD)//g' "$src_dir/$lib/source/CMakeLists.txt"
  sed -i 's/cmake_policy(SET CMP0054 OLD)//g' "$src_dir/$lib/source/CMakeLists.txt"
  local extra_cmake=""
  local extra_cmake_high_bit=""
  if [[ "$host_arch" == "aarch64" ]]; then
    sed -i '/if(INTEL_CXX OR CLANG OR (NOT CC_VERSION VERSION_LESS 4.3))/,/endif()/d' "$src_dir/$lib/source/common/CMakeLists.txt"
    extra_cmake=" -DCROSS_COMPILE_ARM64=ON"
    extra_cmake_high_bit=" -DENABLE_ASSEMBLY=OFF"
    # Inject target triple into hardcoded add_custom_command ARGS
    sed -i 's/ARGS ${ARM_ARGS}/ARGS --target=aarch64-linux-android26 ${ARM_ARGS}/g' "$src_dir/$lib/source/CMakeLists.txt"
  elif [[ "$host_arch" == "armv7a" ]]; then
    sed -i '/if(INTEL_CXX OR CLANG OR (NOT CC_VERSION VERSION_LESS 4.3))/,/endif()/d' "$src_dir/$lib/source/common/CMakeLists.txt"
    extra_cmake=" -DCROSS_COMPILE_ARM=ON"
    extra_cmake_high_bit=" -DENABLE_ASSEMBLY=OFF"
    # Inject target triple into hardcoded add_custom_command ARGS
    sed -i 's/ARGS ${ARM_ARGS}/ARGS --target=armv7a-linux-androideabi26 ${ARM_ARGS}/g' "$src_dir/$lib/source/CMakeLists.txt"
  fi
  sed -i 's/ARGS ${NASM_FLAGS} ${ASM_SRC}/ARGS ${NASM_FLAGS} -DPIC ${ASM_SRC}/g' "$src_dir/$lib/source/CMakeLists.txt"
  sed -i 's/set(ARGS -f elf64)/set(ARGS -f elf64 -DPIC)/g' "$src_dir/$lib/source/cmake/CMakeASM_NASMInformation.cmake"
  sed -i 's/set(ARGS -f elf32)/set(ARGS -f elf32 -DPIC)/g' "$src_dir/$lib/source/cmake/CMakeASM_NASMInformation.cmake"
  # Purge cache to ensure modified CMakeLists.txt is processed
  rm -rf "$src_dir/$lib/12bit" "$src_dir/$lib/10bit" "$src_dir/$lib/8bit"
  mkdir -p "$src_dir/$lib/12bit" "$src_dir/$lib/10bit" "$src_dir/$lib/8bit"
  # --- 12 BIT ---
  change_dir "$src_dir/$lib/12bit" 1
  do_cmake_from_build_dir "$src_dir/$lib/source" "-DHIGH_BIT_DEPTH=ON \
-DEXPORT_C_API=OFF \
-DENABLE_CLI=OFF \
-DMAIN12=ON \
-DCMAKE_EXE_LINKER_FLAGS=\"-ldl\" \
-DCMAKE_SHARED_LINKER_FLAGS=\"-ldl\" \
-DENABLE_CLI=OFF \
-DENABLE_PIC=ON \
-DENABLE_SHARED=OFF \
-DCMAKE_ASM_NASM_FLAGS=\"-DPIC\" \
-DCMAKE_C_FLAGS:STRING=\"-fPIC -fvisibility=hidden\" \
-DCMAKE_CXX_FLAGS:STRING=\"-fPIC -fvisibility=hidden\" \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 ${extra_cmake}${extra_cmake_high_bit}"
  disable_nonessential "$src_dir/$lib/12bit"
  do_make
  # --- 10 BIT ---
  change_dir "$src_dir/$lib/10bit" 1
  do_cmake_from_build_dir "$src_dir/$lib/source" "-DHIGH_BIT_DEPTH=ON \
-DEXPORT_C_API=OFF \
-DENABLE_CLI=OFF \
-DCMAKE_EXE_LINKER_FLAGS=\"-ldl\" \
-DCMAKE_SHARED_LINKER_FLAGS=\"-ldl\" \
-DENABLE_CLI=OFF \
-DENABLE_PIC=ON \
-DENABLE_SHARED=OFF \
-DCMAKE_ASM_NASM_FLAGS=\"-DPIC\" \
-DCMAKE_C_FLAGS:STRING=\"-fPIC -fvisibility=hidden\" \
-DCMAKE_CXX_FLAGS:STRING=\"-fPIC -fvisibility=hidden\" \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 ${extra_cmake}${extra_cmake_high_bit}"
  disable_nonessential "$src_dir/$lib/10bit"
  do_make
  # --- 8 BIT ---
  change_dir "$src_dir/$lib/8bit" 1
  ln -sf "$src_dir/$lib/10bit/libx265.a" libx265_main10.a
  ln -sf "$src_dir/$lib/12bit/libx265.a" libx265_main12.a
  do_cmake_from_build_dir "$src_dir/$lib/source" "-DEXTRA_LIB=\"x265_main10.a;x265_main12.a\" \
-DEXTRA_LINK_FLAGS=-L. \
-DLINKED_10BIT=ON \
-DLINKED_12BIT=ON \
-DCMAKE_EXE_LINKER_FLAGS=\"-ldl\" \
-DCMAKE_SHARED_LINKER_FLAGS=\"-ldl\" \
-DENABLE_CLI=OFF \
-DENABLE_PIC=ON \
-DENABLE_SHARED=OFF \
-DCMAKE_ASM_NASM_FLAGS=\"-DPIC\" \
-DCMAKE_C_FLAGS:STRING=\"-fPIC -fvisibility=hidden\" \
-DCMAKE_CXX_FLAGS:STRING=\"-fPIC -fvisibility=hidden\" \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 ${extra_cmake}"
  change_dir "$src_dir/$lib/8bit"
  disable_nonessential "$src_dir/$lib/8bit"
  do_make
  mv -f "libx265.a" "libx265_main.a"
  ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
  do_make_install
  sed -i -E 's/-l+[-:]*libunwind\.a//g' "$install_pkgconfig_dir/x265.pc"
  change_dir "$src_dir"
}
# build_libxavs           # config_options+= --enable-libxavs             # enable AVS encoding via xavs [no]
build_libxavs() {
  local lib="libxavs"
  local repo="https://github.com/Distrotech/xavs"
  local repo_ver="distrotech-xavs-git"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export AS=yasm
  sed -i 's/, tmp\[0\]);/, \&tmp[0]);/g' "$src_dir/$lib/common/i386/dct-c.c"
  sed -i 's/, tmp\[1\]);/, \&tmp[1]);/g' "$src_dir/$lib/common/i386/dct-c.c"
  sed -i 's/, tmp\[2\]);/, \&tmp[2]);/g' "$src_dir/$lib/common/i386/dct-c.c"
  sed -i 's/, tmp\[3\]);/, \&tmp[3]);/g' "$src_dir/$lib/common/i386/dct-c.c"
  sed -i 's/extern void predict_8x8c_p_core_mmxext.*/extern void predict_8x8c_p_core_mmxext(uint8_t *src, int i00, int b, int c);/' "$src_dir/$lib/common/i386/predict-c.c"
  generic_configure "--enable-static \
--disable-shared \
--enable-pic \
--with-pic \
--disable-asm \
--extra-cflags=\"-fPIC\""
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_cross_vars
}
# build_libxavs2          # config_options+= --enable-libxavs2            # enable AVS2 encoding via xavs2 [no]
build_libxavs2() {
  local lib="libxavs2"
  local repo="https://github.com/pkuvcl/xavs2"
  local repo_ver="1.4"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build/linux"
  export AR="${AR} rcs"
  local config="--disable-cli \
--enable-static \
--disable-shared \
--enable-pic \
--with-pic \
--extra-cflags=\"$CFLAGS -Wno-error=incompatible-pointer-types\" \
AS=$AS"
  if [[ "$host_arch" == "x86_64" ]]; then
    export AS=nasm
  elif [[ "$host_arch" == "armv7a" ]]; then
    export AS="$CC"
    config="$config --disable-asm"
  fi
  generic_configure "$config"
  if [[ "$host_arch" == "aarch64" ]]; then
    sed -i 's/SYS_ARCH=AARCH64/SYS_ARCH=GENERIC/g' config.mak
  elif [[ "$host_arch" == "armv7a" ]]; then
    sed -i 's/SYS_ARCH=ARM/SYS_ARCH=GENERIC/g' config.mak
  fi
  disable_nonessential "$src_dir/$lib"
  sed -i 's/$(AR)$@/$(AR) $@/g' Makefile
  do_make "AR=\"$AR\" AS=$AS"
  do_make_install
  sed -i "s/Version:.*/Version: ${repo_ver}.0/g" "$dependency_install_prefix"/lib/pkgconfig/xavs2.pc
  change_dir "$src_dir"
  reset_cross_vars
}
# build_libxevd           # config_options+= --enable-libxevd             # enable EVC decoding via libxevd [no]
build_libxevd() {
  local lib="libxevd"
  if [[ "${bits_target}" == "64" ]]; then
    local repo="https://github.com/mpeg5/xevd"
    local repo_ver="v0.5.0"
    change_dir "$src_dir"
    do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
    change_dir "$src_dir/$lib/build" 1
    export CFLAGS="$CFLAGS -Wno-error \
  -Wno-error=parentheses-equality \
  -Wno-error=empty-body \
  -Wno-error=typedef-redefinition \
  -Wno-error=unknown-warning-option \
  -Wno-error=shift-negative-value \
  -Wno-error=for-loop-analysis \
  -Wno-error=sometimes-uninitialized"
    # needs a version.txt file but git repo doesnt have one for some reason
    if [[ -d .git && ! -f "$src_dir/$lib/version.txt" ]]; then
        # Get version from git tags
        VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.5.0")
    else
        # Use default version
        VERSION="v0.5.0"
    fi
    echo "$VERSION" >"$src_dir/$lib/version.txt"
    sed -i 's/-Wno-stringop-overflow//g' "$src_dir/$lib/CMakeLists.txt"
    sed -i 's/-Wno-maybe-uninitialized//g' "$src_dir/$lib/CMakeLists.txt"
    sed -i 's/-Werror//g' "$src_dir/$lib/CMakeLists.txt"
    local cmake_options="-DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_BUILD_TYPE=Release"
    if [[ "$host_arch" == "aarch64" || "$host_arch" == "armv7a" ]]; then
      cmake_options+=" -DARM=TRUE"
      sed -i 's/add_definitions(-DARM=1)/add_definitions(-DARM=TRUE)/g' "$src_dir/$lib/CMakeLists.txt"
    fi
    do_cmake_from_build_dir "$src_dir/$lib" "$cmake_options"
    disable_nonessential "$src_dir/$lib/build"
    do_make "xevd"
    sed -i "s/Version:.*/Version: ${VERSION//v/}/g" "$src_dir/$lib/build/xevd.pc"
    { cp -fv "$src_dir/$lib/build/src_main/libxevd.a" "$dependency_install_prefix/lib/" >>"$LOG_FILE"; } || exit_message 1 "build_libxevd: could not install $lib static lib"
    { cp -fv "$src_dir/$lib/inc/xevd.h" "$dependency_install_prefix/include/" >>"$LOG_FILE"; } || exit_message 1 "build_libxevd: could not install $lib headers"
    { cp -fv "$src_dir/$lib/build/xevd_exports.h" "$dependency_install_prefix/include/" >>"$LOG_FILE"; } || exit_message 1 "build_libxevd: could not install $lib headers"
    { cp -fv "$src_dir/$lib/build/xevd.pc" "$install_pkgconfig_dir/" >>"$LOG_FILE"; } || exit_message 1 "build_libxevd: could not install $lib pkg-config"
    change_dir "$src_dir"
  else
    echo -e "INFO: $lib does not support $bits_target bits, skipping" > >(redirect_output) 2>&1
    disable_library "$lib"
  fi
}
# build_libxeve           # config_options+= --enable-libxeve             # enable EVC encoding via libxeve [no]
build_libxeve() {
  local lib="libxeve"
  if [[ "${bits_target}" == "64" ]]; then
    # https://github.com/mpeg5/xeve
    local repo="https://github.com/mpeg5/xeve"
    local repo_ver="v0.5.1"
    change_dir "$src_dir"
    do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
    change_dir "$src_dir/$lib/build" 1
    export CFLAGS="$CFLAGS -Wno-error \
  -Wno-error=parentheses-equality \
  -Wno-error=empty-body \
  -Wno-error=typedef-redefinition \
  -Wno-error=unknown-warning-option \
  -Wno-error=shift-negative-value \
  -Wno-error=for-loop-analysis \
  -Wno-error=sometimes-uninitialized \
  -I$src_dir/$lib/src_base/neon \
  -I$src_dir/$lib/src_main/neon"
    if [[ -d .git && ! -f "$src_dir/$lib/version.txt" ]]; then
        VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.5.1")
    else
        VERSION="0.5.1"
    fi
    echo "$VERSION" > "$src_dir/$lib/version.txt"
    sed -i 's/-Wno-stringop-overflow//g' "$src_dir/$lib/CMakeLists.txt"
    sed -i 's/-Wno-maybe-uninitialized//g' "$src_dir/$lib/CMakeLists.txt"
    sed -i 's/add_subdirectory(app)//g' "$src_dir/$lib/CMakeLists.txt"
    sed -i 's/-Werror//g' "$src_dir/$lib/CMakeLists.txt"
    local cmake_options="-DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_BUILD_TYPE=Release"
    if [[ "$host_arch" == "aarch64" ]]; then
      cmake_options+=" -DARM=TRUE"
      sed -i 's/add_definitions(-DARM=1)/add_definitions(-DARM=TRUE)/g' "$src_dir/$lib/CMakeLists.txt"
      sed -i 's/if("${ARM}" STREQUAL "TRUE")/if(ARM)/g' "$src_dir/$lib/src_base/CMakeLists.txt"
      sed -i 's/if("${ARM}" STREQUAL "TRUE")/if(ARM)/g' "$src_dir/$lib/src_main/CMakeLists.txt"
      sed -i '6006s/float32x4_t/float64x2_t/' "$src_dir/$lib/src_base/neon/sse2neon.h"
      sed -i '6021s/a, p/a, (int32x4_t *) p/' "$src_dir/$lib/src_base/neon/sse2neon.h"
    fi
    do_cmake_from_build_dir "$src_dir/$lib" "$cmake_options"
    disable_nonessential "$src_dir/$lib/build"
    do_make "xeve"
    sed -i "s/Version:.*/Version: ${VERSION//v/}/g" "$src_dir/$lib/build/xeve.pc"
    { cp -fv "$src_dir/$lib/build/src_main/libxeve.a" "$dependency_install_prefix/lib/" >>"$LOG_FILE"; } || exit_message 1 "build_libxeve: could not install $lib static lib"
    { cp -fv "$src_dir/$lib/inc/xeve.h" "$dependency_install_prefix/include/" >>"$LOG_FILE"; } || exit_message 1 "build_libxeve: could not install $lib headers"
    { cp -fv "$src_dir/$lib/build/xeve_exports.h" "$dependency_install_prefix/include/" >>"$LOG_FILE"; } || exit_message 1 "build_libxeve: could not install $lib headers"
    { cp -fv "$src_dir/$lib/build/xeve.pc" "$install_pkgconfig_dir/" >>"$LOG_FILE"; } || exit_message 1 "build_libxeve: could not install $lib pkg-config"
    change_dir "$src_dir"
    reset_cflags
  else
    echo -e "INFO: $lib does not support $bits_target bits, skipping" > >(redirect_output) 2>&1
    disable_library "$lib"
  fi
}
# build_libxml2           # config_options+= --enable-libxml2             # enable XML parsing using the C library libxml2, needed for dash and imf demuxing support [no]
build_libxml2() {
  # run_valid_function "build_iconv" 1
  local lib="libxml2"
  local repo="https://gitlab.gnome.org/GNOME/libxml2"
  local repo_ver="v2.10.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  do_autogen
  touch "no.autoreconf"
  generic_configure "--with-ftp=no --with-http=no --with-python=no --with-iconv=$dependency_install_prefix" # using configure. meson doesnt work
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libxv() {
  # run_valid_function "build_xlib" 1
  local lib="libxv"
  local repo="https://gitlab.freedesktop.org/xorg/lib/libxv"
  local repo_ver="libXv-1.0.13"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export xorg_cv_malloc_0_returns_null=no
  generic_configure "--enable-pic \
--with-pic \
--enable-static \
--disable-shared \
--host=$host_target \
cross_compiling=yes \
xorg_cv_malloc_0_returns_null=no"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libxvid           # config_options+= --enable-libxvid             # enable Xvid encoding via xvidcore, native MPEG-4/Xvid encoder exists [no]
build_libxvid() {
  # run_valid_function "build_libxv"
  local lib="libxvid"
  # local repo="https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz"
  local repo="https://github.com/openkylin/xvidcore"
  local repo_ver="upstream/1.3.7"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build/generic"
  sed -i 's/BUILD_DIR = =build/BUILD_DIR = build/g' Makefile
  sed -i 's|install:.*|install: $(STATIC_LIB)|g' Makefile
  sed -i 's|$(LN_S)|$(LN_S) -f|g' Makefile
  sed -i '/ifeq ($(SHARED_EXTENSION)/,/endif/ s/^/# /' Makefile
  generic_configure "--enable-pic --with-pic --enable-static --disable-shared --disable-assembly"
  do_make "libxvidcore.a CFLAGS=\"$CFLAGS -fvisibility=hidden\""
  do_make "install"
  cat > "$install_pkgconfig_dir/xvidcore.pc" <<EOF
prefix=${dependency_install_prefix}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: xvidcore
Description: MPEG-4 video codec
Version: 1.3.7
Libs: -L\${libdir} -lxvidcore
Libs.private: -lm -lpthread
Cflags: -I\${includedir}
EOF
  change_dir "$src_dir"
}
# build_libzimg           # config_options+= --enable-libzimg             # enable z.lib, needed for zscale filter [no]
build_libzimg() {
  local lib="libzimg"
  local repo="https://github.com/sekrit-twc/zimg"
  local repo_ver="release-3.0.6"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export CFLAGS="$CFLAGS -fPIC"
  export CXXFLAGS="$CXXFLAGS -fPIC"
  local config="--enable-static \
--disable-shared \
--with-pic"
  if [[ "$host_arch" == "armv7a" ]]; then
    export CFLAGS="-march=armv7-a -mfpu=neon-fp16 -mfloat-abi=softfp"
    export CXXFLAGS="-march=armv7-a -mfpu=neon-fp16 -mfloat-abi=softfp"
  fi
  do_autogen
  touch "no.autoreconf"
  generic_configure "$config"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  reset_cflags
  reset_cxxflags
  change_dir "$src_dir"
}
# build_libzmq            # config_options+= --enable-libzmq              # enable message passing via libzmq [no]
build_libzmq() {
  local lib="libzmq"
  local repo="https://github.com/zeromq/libzmq"
  local repo_ver="v4.3.5"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static \
--disable-shared \
--without-docs \
--without-libsodium \
--disable-libunwind \
--disable-perf \
--disable-werror \
--disable-curve-keygen \
--disable-curve"
  # Add these before generic_configure
  # sed -i 's/strlcpy/zmq_strlcpy_internal/g' "$src_dir/$lib/src/compat.hpp"
  # sed -i 's/strnlen/zmq_strnlen_internal/g' "$src_dir/$lib/src/compat.hpp"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_gettext_native() {
  local min_ver="0.21"
  if command -v gettext &>/dev/null; then
    local installed_ver="$(gettext --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
  else
    local installed_ver=0
  fi
  if [ "$(printf '%s\n' "$min_ver" "$installed_ver" | sort -V | head -n 1)" = "$installed_ver" ] && [ "$installed_ver" != "$min_ver" ]; then
  # run_valid_function "build_iconv_minimal_native"
  clear_cross_vars
  local lib="gettext-native"
  local repo="https://ftp.gnu.org/pub/gnu/gettext/gettext-1.0.tar.gz"
  local mirror="https://ftpmirror.gnu.org/gnu/gettext/gettext-1.0.tar.gz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" --alt="$mirror"
  change_dir "$src_dir/$lib"
  do_autogen --skip-gnulib
  change_dir "$src_dir/$lib/gettext-runtime"
  export CFLAGS=" -Wno-incompatible-pointer-types -ffunction-sections -fdata-sections -fstrict-aliasing -fPIC -I$src_dir/$lib"
  export CXXFLAGS="-ffunction-sections -fdata-sections -fstrict-aliasing -fPIC -I$src_dir/$lib"
  export CPPFLAGS=""
  export LDFLAGS=""
  export CC=gcc CXX=g++ AR=ar AS=as RANLIB=ranlib LD=ld STRIP=strip NASM=nasm
  local config="--prefix=/usr \
--with-sysroot=\"/usr\" \
--with-included-libintl \
--with-included-libiconv \
--libdir=/usr/lib \
--with-included-gettext \
--enable-static \
--disable-shared \
--disable-doc"
  touch "no.autoreconf"
  touch "no.autogen"
  do_configure "$config \
CFLAGS=\"$CFLAGS\""
  do_make
  do_make_install "PREFIX=\"/usr\""
  change_dir "$src_dir/$lib/libtextstyle"
  touch "no.autoreconf"
  touch "no.autogen"
  do_configure "$config \
CFLAGS=\"$CFLAGS\""
  do_make
  do_make_install "PREFIX=\"/usr\""
  change_dir "$src_dir/$lib/gettext-tools"
  config+="--disable-examples \
--without-libtextstyle-prefix"
  touch "no.autoreconf"
  touch "no.autogen"
  do_configure "$config \
CFLAGS=\"$CFLAGS\" \
LDFLAGS=\"$LDFLAGS\""
  local make_config="LDFLAGS=\"-L$src_dir/$lib/gettext-tools/.libs -L$src_dir/$lib/gettext-tools/src/.libs ${LDFLAGS}\""
  do_make
  do_make_install "PREFIX=\"/usr\""
  unset LIBS
  reset_allflags
  reset_cross_vars
  fi
}
# build_libzvbi           # config_options+= --enable-libzvbi             # enable teletext support via libzvbi [no]
build_libzvbi() {
  build_gettext_native
  local lib="libzvbi"
  local repo="https://github.com/zapping-vbi/zvbi"
  local repo_ver="v0.2.44"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LIBS="-lpng -lz -liconv -lm"
  export LDFLAGS="$LDFLAGS $LIBS"
  local ORIG_PATH=$PATH
  local ORIG_ACLOCAL_PATH=$ACLOCAL_PATH
  export ACLOCAL_PATH="$dependency_install_prefix/share/aclocal"
  export PATH="$dependency_install_prefix/bin:$PATH"
  export ac_cv_func_malloc_0_nonnull=yes
  export ac_cv_func_realloc_0_nonnull=yes
  export CFLAGS="$CFLAGS -Dpthread_testcancel\(\)=\(void\)0"
  if [[ -e "$dependency_install_prefix/bin/xz" ]]; then
    mv "$dependency_install_prefix/bin/xz" "$dependency_install_prefix/bin/xz.bak"
    ln -s /usr/bin/xz "$dependency_install_prefix/bin/xz"
  fi
  do_autogen "--build-w$bits_target"
  change_dir "$src_dir/$lib"
  touch "no.autoreconf"
  generic_configure "--enable-static \
--disable-shared \
--disable-dvb \
--disable-bktr \
--disable-proxy \
--disable-nls \
--without-doxygen \
--disable-examples \
--disable-tests \
--enable-pic \
--with-pic \
--with-libiconv-prefix=\"$dependency_install_prefix\""
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_ldflags
  reset_cflags
  unset LIBS ac_cv_func_malloc_0_nonnull ac_cv_func_realloc_0_nonnull
  export PATH=$ORIG_PATH
  export ACLOCAL_PATH=$ORIG_ACLOCAL_PATH
}
build_sratom() {
  # run_valid_function "build_sord"
  # run_valid_function "build_lv2_headers"
  activate_meson
  local lib="sratom"
  local repo="https://gitlab.com/lv2/sratom"
  local repo_ver="v0.6.20"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dtests=disabled -Ddocs=disabled"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$dependency_install_prefix/lib"
  # ln -sf "libsratom-0.a" "libsratom.a"
  cp -f "libsratom-0.a" "libsratom.a"
  change_dir "$install_pkgconfig_dir"
  ln -sf "sratom-0.pc" "sratom.pc"
  change_dir "$src_dir"
}
build_sord() {
  # run_valid_function "build_zix"
  activate_meson
  local lib="sord"
  local repo="https://gitlab.com/drobilla/sord"
  local repo_ver="v0.16.20"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dtests=disabled -Dtools=disabled -Ddocs=disabled"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$dependency_install_prefix/lib"
  # ln -sf "libsord-0.a" "libsord.a"
  cp -f "libsord-0.a" "libsord.a"
  change_dir "$install_pkgconfig_dir"
  ln -sf "sord-0.pc" "sord.pc"
  change_dir "$src_dir"
}
build_serd() {
  activate_meson
  local lib="serd"
  local repo="https://gitlab.com/drobilla/serd"
  local repo_ver="v0.32.6"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dtests=disabled -Dtools=disabled -Ddocs=disabled -Dstatic=true"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$dependency_install_prefix/lib"
  # ln -sf "libserd-0.a" "libserd.a"
  cp -f "libserd-0.a" "libserd.a"
  change_dir "$install_pkgconfig_dir"
  ln -sf "serd-0.pc" "serd.pc"
  change_dir "$src_dir"
}
build_zix() {
  # run_valid_function "build_serd"
  activate_meson
  local lib="zix"
  local repo="https://gitlab.com/drobilla/zix"
  local repo_ver="v0.8.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dtests=disabled -Dtests_cpp=disabled -Ddocs=disabled"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$dependency_install_prefix/lib"
  # ln -sf "libzix-0.a" "libzix.a"
  cp -f "libzix-0.a" "libzix.a"
  change_dir "$install_pkgconfig_dir"
  ln -sf "zix-0.pc" "zix.pc"
  change_dir "$src_dir"
}
build_lilv() {
  # run_valid_function "build_sratom"
  activate_meson
  local lib="lilv"
  local repo="https://github.com/lv2/lilv"
  local repo_ver="v0.26.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dtests=disabled -Ddocs=disabled -Dtools=disabled"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$dependency_install_prefix/lib"
  # ln -sf "liblilv-0.a" "liblilv.a"
  cp -f "liblilv-0.a" "liblilv.a"
  change_dir "$install_pkgconfig_dir"
  ln -sf "lilv-0.pc" "lilv.pc"
  change_dir "$src_dir"
}
build_lv2_headers() {
  activate_meson
  local lib="lv2"
  local repo="https://github.com/lv2/lv2"
  local repo_ver="v1.18.10"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Dtests=disabled -Ddocs=disabled -Donline_docs=false -Dplugins=disabled"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
}
# build_lv2               # config_options+= --enable-lv2                 # enable LV2 audio filtering [no]
build_lv2() {
  # run_valid_function "build_lilv"
  find "$install_pkgconfig_dir" -type f -name "*.pc" -exec sed -i \
  -e 's/-lsratom-0\b/-lsratom/g' \
  -e 's/-lsord-0\b/-lsord/g' \
  -e 's/-lserd-0\b/-lserd/g' \
  -e 's/-llilv-0\b/-llilv/g' \
  -e 's/-lzix-0\b/-lzix/g' \
  -e 's/-lilv-0\b/-llilv/g' {} +
}
# build_mbedtls           # config_options+= --enable-mbedtls             # enable mbedTLS, needed for https support if openssl, gnutls or libtls is not used [no]
build_mbedtls() {
  local lib="mbedtls"
  local repo="https://github.com/Mbed-TLS/mbedtls"
  local repo_ver="v3.6.5"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_params="-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix} \
-DCMAKE_BUILD_TYPE=Release \
-DENABLE_TESTING=OFF \
-DENABLE_PROGRAMS=OFF \
-DUSE_STATIC_MBEDTLS_LIBRARY=ON \
-DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
-DMBEDTLS_FATAL_WARNINGS=OFF"
  generic_cmake "$cmake_params" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_openal            # config_options+= --enable-openal              # enable OpenAL 1.1 capture support [no]
build_openal() {
  local lib="openal"
  local repo="https://github.com/kcat/openal-soft"
  local repo_ver="1.24.3"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DLIBTYPE=STATIC \
-DALSOFT_UTILS=OFF \
-DALSOFT_EXAMPLES=OFF \
-DALSOFT_TESTS=OFF \
-DALSOFT_STATIC_LIBGCC=ON \
-DALSOFT_STATIC_STDCXX=ON \
-DALSOFT_REQUIRE_DSOUND=OFF \
-DALSOFT_REQUIRE_WASAPI=OFF \
-DALSOFT_BACKEND_ALSA=OFF \
-DALSOFT_BACKEND_PULSEAUDIO=OFF \
-DALSOFT_BACKEND_PIPEWIRE=OFF"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_opencl            # config_options+= --enable-opencl              # enable OpenCL processing [no]
build_opencl() {
  local parentlib="opencl"
  local lib="OpenCL-Headers"
  local repo="https://github.com/KhronosGroup/OpenCL-Headers"
  local repo_ver="v2025.07.22"
  change_dir "$src_dir"
  change_dir "$src_dir/$parentlib" 1
  do_git_checkout "$repo" "$lib" "$repo_ver"
  change_dir "$src_dir/$parentlib/$lib/build" 1
  local cmake_params="-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix} \
-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_TESTING=OFF \
-DOPENCL_HEADERS_BUILD_TESTING=OFF"
  do_cmake_from_build_dir "$src_dir/$parentlib/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$parentlib/$lib/build"
  do_make_and_make_install
  cp -f "$src_dir/$parentlib/$lib/OpenCL-Headers.pc.in" "$install_pkgconfig_dir/OpenCL-Headers.pc"
  sed -i "s|@PKGCONFIG_PREFIX@|${dependency_install_prefix}|g" "$install_pkgconfig_dir/OpenCL-Headers.pc"
  sed -i "s|@OPENCL_INCLUDEDIR_PC@|\${prefix}/include|g" "$install_pkgconfig_dir/OpenCL-Headers.pc"
  local lib="OpenCL-ICD-Loader"
  local repo="https://github.com/KhronosGroup/OpenCL-ICD-Loader"
  local repo_ver="v2025.07.22"
  change_dir "$src_dir/$parentlib"
  do_git_checkout "$repo" "$lib" "$repo_ver"
  change_dir "$src_dir/$parentlib/$lib/build" 1
  local cmake_params="-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix} \
-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_TESTING=OFF \
-DCMAKE_PREFIX_PATH=${dependency_install_prefix} \
-DOpenCLHeaders_DIR=${dependency_install_prefix}/share/cmake/OpenCLHeaders \
-DOPENCL_ICD_LOADER_BUILD_TESTING=OFF"
  do_cmake_from_build_dir "$src_dir/$parentlib/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$parentlib/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_opengl            # config_options+= --enable-opengl              # enable OpenGL rendering [no]
build_opengl() {
  local lib="opengl"
  mkdir -p "$dependency_install_prefix/include/ES2"
  ln -sf "$toolchain_include_path/GLES2/gl2.h" "$dependency_install_prefix/include/ES2/gl.h"
}
# build_openssl           # config_options+= --enable-openssl             # enable openssl, needed for https support if gnutls, libtls or mbedtls is not used [no]
build_openssl() {
  local lib="openssl"
  # https://github.com/openssl/openssl 
  local repo="https://github.com/openssl/openssl"
  local repo_ver="openssl-3.6.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  install_missing_packages perl-IPC-Cmd perl-Time-Piece
  touch "no.autoreconf"
  local ssl_target="android-${host_arch}"
  case "$host_arch" in
    "x86_64")
      local ssl_target="android-x86_64"
      ;;
    "aarch64")
      local ssl_target="android-arm64"
      ;;
    "armv7a")
      local ssl_target="android-arm"
      ;;
    *)
      exit_message 1 "build_openssl: Unsupported host arch '$host_arch' for Android"
      ;;
  esac
  do_configure "$ssl_target --release --prefix=$dependency_install_prefix --openssldir=$dependency_install_prefix/ssl --libdir=lib no-shared no-tests no-docs no-demos no-legacy"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  find "$dependency_install_prefix/lib" -name "libssl.so*" -delete
  find "$dependency_install_prefix/lib" -name "libcrypto.so*" -delete
  change_dir "$src_dir"
}
build_sphinxbase() {
  local lib="sphinxbase"
  local repo="https://github.com/cmusphinx/sphinxbase"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib"
  change_dir "$src_dir/$lib"
  export LIBS="${LIBS} -llog"
  export LDFLAGS="${LDFLAGS} -llog"
  touch "no.autogen"
  generic_configure "--enable-static \
--disable-shared \
--without-python \
--without-lapack \
--without-pulseaudio \
--without-pulse \
--without-alsa \
--without-swig \
--host=$host_target"
  sed -i 's/ad_oss/ad_base/g' "$src_dir/$lib/Makefile"
  sed -i 's/ad_oss/ad_base/g' "$src_dir/$lib/src/libsphinxad/Makefile"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_ldflags
  unset LIBS
}
build_gstreamer() {
  activate_meson
  local lib="gstreamer"
  local repo="https://gitlab.freedesktop.org/gstreamer/gstreamer"
  local repo_ver="1.26.10"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib"
  local meson_options="-Ddoc=disabled \
-Dexamples=disabled \
-Dtests=disabled \
-Dtools=disabled \
-Dbenchmarks=disabled \
-Dgst_debug=false \
-Dnls=disabled \
-Dc_link_args=\"-L$dependency_install_prefix/lib -llzma\""
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  reset_ldflags
  change_dir "$src_dir"
}
# build_pocketsphinx      # config_options+= --enable-pocketsphinx        # enable PocketSphinx, needed for asr filter [no]
build_pocketsphinx() {
  # run_valid_function "build_alsa"
  # run_valid_function "build_libunwind"
  # run_valid_function "build_lzma"
  # run_valid_function "build_glib"
  local lib="pocketsphinx"
  local repo="https://svn.code.sf.net/p/cmusphinx/code/trunk/pocketsphinx"
  local repo_ver="r13291"
  change_dir "$src_dir"
  do_svn_checkout "$repo" "$src_dir/$lib"
  change_dir "$src_dir/$lib"
  touch "no.autogen"
  generic_configure "--enable-static \
--disable-shared \
--without-python \
--without-lapack"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# new version is not compatible yet
# build_pocketsphinx() {
#   if ! truthy "$disable_pocketsphinx" && truthy "$enable_pocketsphinx"; then
#   local lib="pocketsphinx"
#   local repo="https://github.com/cmusphinx/pocketsphinx"
#   local repo_ver="v5.0.4"
# 	change_dir "$src_dir"
#   do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
# 	change_dir "$src_dir/$lib/build" 1
#   local cmake_params="-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF"
# 	do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
# 	do_make_and_make_install
#   ln -s "$dependency_install_prefix/include/pocketsphinx.h" "$dependency_install_prefix/include/pocketsphinx/pocketsphinx.h"
#   change_dir "$src_dir"
#   fi
# }
# build_vapoursynth       # config_options+= --enable-vapoursynth         # enable VapourSynth demuxer [no]
build_vapoursynth() {
  # run_valid_function "build_libzimg" 1
  activate_meson
  local lib="vapoursynth"
  local repo="https://github.com/vapoursynth/vapoursynth"
  local repo_ver="R73"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local meson_options="-Denable_vspipe=false"
  if [[ "$host_arch" == "aarch64" ]]; then
    local py_root="python_dev_${host_arch}"
    if [[ ! -d "$py_root" ]]; then
      download_and_unpack_file "https://www.python.org/ftp/python/3.14.3/python-3.14.3-aarch64-linux-android.tar.gz" "$py_root"
    fi
  elif [[ "$host_arch" == "x86_64" ]]; then
    local py_root="python_dev_${host_arch}"
    if [[ ! -d "$py_root" ]]; then
      download_and_unpack_file "https://www.python.org/ftp/python/3.14.3/python-3.14.3-x86_64-linux-android.tar.gz" "$py_root"
    fi
  else
    meson_options="$meson_options -Denable_python_module=false -Denable_vsscript=false"
  fi
  if [[ -f "python_dev_${host_arch}/prefix/include/python3.14/Python.h" ]]; then
    meson_options="$meson_options -Denable_python_module=true -Denable_vsscript=true -Dpython3_bin=\"/opt/python/cp314-cp314/bin/python3.14\""
    find "python_dev_${host_arch}/prefix/lib" -name "*.pc" -exec sed -i "s|\(^prefix=\)\(.*\)|\1$dependency_install_prefix|g" {} \;
    find "python_dev_${host_arch}/prefix/lib" -name "python*.pc" -exec sed -i "s|\$(BLDLIBRARY)|-lpython3.14|g" {} \;
    py_root="python_dev_${host_arch}/prefix"
    local py_ver="python3.14"
    remove_path -rf "$dependency_install_prefix/include/$py_ver"
    mkdir -p "$dependency_install_prefix/include/$py_ver"
    copy_path "$py_root/include/$py_ver" "$dependency_install_prefix/include/$py_ver" "-r"
    copy_path "$py_root/lib" "$dependency_install_prefix"
    ln -sf "$install_pkgconfig_dir/python-3.14-embed.pc" "$install_pkgconfig_dir/python-3.12-embed.pc"
    ln -sf "$install_pkgconfig_dir/python-3.14.pc" "$install_pkgconfig_dir/python-3.12.pc"
    export CXXFLAGS="$CXXFLAGS -I$dependency_install_prefix/include/$py_ver/$py_ver"
    export CPPFLAGS="$CPPFLAGS -I$dependency_install_prefix/include/$py_ver/$py_ver"
    export CFLAGS="$CFLAGS -I$dependency_install_prefix/include/$py_ver/$py_ver"
    export LDFLAGS="$LDFLAGS -L$dependency_install_prefix/lib -lpython3.14"
  fi
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
  reset_allflags
}
build_ggml() {
  local lib="ggml"
  local repo="https://github.com/ggml-org/ggml"
  local repo_ver="v0.9.4"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_whisper           # config_options+= --enable-whisper             # enable whisper filter [no]
build_whisper() {
  local lib="whisper"
  local repo="https://github.com/ggerganov/whisper.cpp"
  local repo_ver="v1.8.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DWHISPER_BUILD_EXAMPLES=OFF \
-DWHISPER_BUILD_TESTS=OFF \
-DBUILD_SHARED_LIBS=OFF \
-DGGML_STATIC=ON \
-DGGML_NEON=ON \
-DGGML_AVX=OFF \
-DGGML_AVX2=OFF \
-DGGML_FMA=OFF \
-DGGML_OPENMP_ENABLED=OFF \
-DWHISPER_OPENMP=OFF \
-DGGML_OPENMP=OFF \
-DGGML_F16C=OFF"
  if [[ "$host_arch" == "aarch64" ]]; then
    cmake_params="$cmake_params -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
-DGGML_NATIVE=OFF"
    sed -i 's/list(APPEND ARCH_FLAGS -msse4.2)//g' "$src_dir/$lib/ggml/src/ggml-cpu/CMakeLists.txt"
    sed -i 's/list(APPEND ARCH_FLAGS -mbmi2)//g' "$src_dir/$lib/ggml/src/ggml-cpu/CMakeLists.txt"
  fi
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  while IFS= read -r -d '' file; do
    add_libs_to_pkg -t="$file" -l="-lwhisper -lggml -lggml-base -lggml-cpu -lstdc++ -lm"
  done < <(find "$install_pkgconfig_dir" -name "*whisper*.pc" -print0)
  find "$install_pkgconfig_dir" -name "*whisper*.pc" -exec sed -i -E -e 's/(^|[[:space:]])-lgomp([[:space:]]|$)/ /g' {} +
  change_dir "$src_dir"
}
#endregion---------------------------------------------------------------------
#region------------------------- non-gpl features -----------------------------
#------------------------------------------------------------------------------ 
# build_decklink          # config_options+= --enable-decklink            # enable Blackmagic DeckLink I/O support [no]
build_decklink() {
  echo "WARNING: This is a non-gpl library. Binaries including this library are non-redistributable!" >>"$LOG_FILE"
  local lib="decklink"
  local repo="https://gitlab.com/m-ab-s/decklink-headers"
  local repo_ver="40eb094072004d8a8416e3c57721967df8b1d10c"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  generic_make_install
    change_dir "$src_dir/$lib"
}
# build_libfdk_aac        # config_options+= --enable-libfdk-aac          # enable AAC de/encoding via libfdk-aac [no]
build_libfdk_aac() {
  echo "WARNING: This is a non-gpl library. Binaries including this library are non-redistributable!" >>"$LOG_FILE"
  local lib="libfdk_aac"
  local repo="https://github.com/mstorsjo/fdk-aac"
  local repo_ver="v2.0.3"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
#region-------------------- non-gpl hardware features ------------------------- 
# build_cuda_llvm         # config_options+= --disable-cuda-llvm          # disable CUDA compilation using clang [autodetect]
build_cuda_llvm() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "cuda-llvm"
}
# build_cuvid             # config_options+= --disable-cuvid              # disable Nvidia CUVID support [autodetect]
build_cuvid() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "cuvid"
}
# build_ffnvcodec         # config_options+= --disable-ffnvcodec          # disable dynamically linked Nvidia code [autodetect]
build_ffnvcodec() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "ffnvcodec"
}
# build_nvdec             # config_options+= --disable-nvdec              # disable Nvidia video decoding acceleration (via hwaccel) [autodetect]
build_nvdec() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "nvdec"
}
# build_nvenc             # config_options+= --disable-nvenc              # disable Nvidia video encoding code [autodetect]
build_nvenc() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "nvenc"
}
# build_vdpau             # config_options+= --disable-vdpau              # disable Nvidia Video Decode and Presentation API for Unix code [autodetect]
build_vdpau() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "vdpau"
}
build_libnvvm() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "libnvvm"
}
build_cuda_crt() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "cuda-crt"
}
build_cuda_cudart() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "cuda-cudart"
}
# build_cuda_nvcc         # config_options+= --enable-cuda-nvcc           # enable Nvidia CUDA compiler [no]
build_cuda_nvcc() {
  echo "INFO: Only available on Desktop build" >>"$LOG_FILE"
  disable_library "cuda-nvcc"
}
# build_libnpp            # config_options+= --enable-libnpp              # enable Nvidia Performance Primitives-based code [no]
build_libnpp() {
  echo "WARNING: This is FFmpeg does not support modern npp based filters. Older api has been deprecated by Nvidia. Use scale_cuda instead. Disabling libnpp." >>"$LOG_FILE"
  disable_library "libnpp"
}
#endregion
#region---------- non-gpl linux/unix (Raspberry Pi) features ------------------    
# build_mmal              # config_options+= --disable-mmal               # enable Broadcom Multi-Media Abstraction Layer (Raspberry Pi) via MMAL [no]
build_mmal() {
  echo "INFO: Only available on Raspberry Pi build" >>"$LOG_FILE"
  disable_library "mmal"
}
# build_omx               # config_options+= --enable-omx                 # enable OpenMAX IL code [no]
build_omx() {
  local repo="https://git.code.sf.net/p/omxil/omxil"
  local lib="libomxil-bellagio"
  local repo_ver="0.9.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local orig_path=$PATH
  export PATH="/usr/local/arm-gnu-toolchain/sys-bin:/usr/local/arm-gnu-toolchain/bin:$PATH"
  export CFLAGS="$CFLAGS -Wno-error"
  # disable omxregister utility. not needed for ffmpeg
  sed -i 's/bin_PROGRAMS = omxregister-bellagio/#bin_PROGRAMS = omxregister-bellagio/' src/Makefile.am
  find . -name "configure.ac" -exec sed -i 's/-Werror//g' {} +
  find . -exec touch {} +
  generic_configure "--disable-doc"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  reset_cflags
  change_dir "$src_dir"
  export PATH=$orig_path
}
# build_omx_rpi           # config_options+= --disable-omx-rpi            # enable OpenMAX IL code for Raspberry Pi [no]
build_omx_rpi() {
  echo "INFO: Only available on Raspberry Pi build" >>"$LOG_FILE"
  disable_library "omx-rpi"
}
#endregion
#region-------------------- non-gpl windows features -------------------------- 
# build_d3d11va           # config_options+= --disable-d3d11va            # disable Microsoft Direct3D 11 video acceleration code [autodetect]
build_d3d11va() {
  echo "INFO: Only available on Windows build" >>"$LOG_FILE"
  echo "INFO: No d3d11va library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_d3d12va           # config_options+= --disable-d3d12va            # disable Microsoft Direct3D 12 video acceleration code [autodetect]
build_d3d12va() {
  echo "INFO: Only available on Windows build" >>"$LOG_FILE"
  echo "INFO: No d3d12va library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_dxva2             # config_options+= --disable-dxva2              # disable Microsoft DirectX 9 video acceleration code [autodetect]
build_dxva2() {
  echo "INFO: Only available on Windows build" >>"$LOG_FILE"
  echo "INFO: No dxva2 library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_schannel          # config_options+= --disable-schannel           # disable SChannel SSP, needed for TLS support on Windows if openssl and gnutls are not used [autodetect]
build_schannel() {
  echo "INFO: Only available on Windows build" >>"$LOG_FILE"
  echo "INFO: No schannel library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_mediafoundation   # config_options+= --enable-mediafoundation     # enable encoding via MediaFoundation [auto]
build_mediafoundation() {
  echo "INFO: Only available on Windows build" >>"$LOG_FILE"
  echo "INFO: No mediafoundation library to compile. Library built into OS." >>"$LOG_FILE"
}
#endregion
#region--------------------- non-gpl apple features ---------------------------     
# build_avfoundation      # config_options+= --disable-avfoundation       # disable Apple AVFoundation framework [autodetect]
build_avfoundation() {
  echo "INFO: Only available on Apple build" >>"$LOG_FILE"
  echo "INFO: No avfoundation library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_appkit            # config_options+= --disable-appkit             # disable Apple AppKit framework [autodetect]
build_appkit() {
  echo "INFO: Only available on Apple build" >>"$LOG_FILE"
  echo "INFO: No appkit library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_audiotoolbox      # config_options+= --disable-audiotoolbox       # disable Apple AudioToolbox code [autodetect]
build_audiotoolbox() {
  echo "INFO: Only available on Apple build" >>"$LOG_FILE"
  echo "INFO: No audiotoolbox library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_coreimage         # config_options+= --disable-coreimage          # disable Apple CoreImage framework [autodetect]
build_coreimage() {
  echo "INFO: Only available on Apple build" >>"$LOG_FILE"
  echo "INFO: No coreimage library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_metal             # config_options+= --disable-metal              # disable Apple Metal framework [autodetect]
build_metal() {
  echo "INFO: Only available on Apple build" >>"$LOG_FILE"
  echo "INFO: No metal library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_securetransport   # config_options+= --disable-securetransport    # disable Secure Transport, needed for TLS support on OSX if openssl and gnutls are not used [autodetect]
build_securetransport() {
  echo "INFO: Only available on Apple build" >>"$LOG_FILE"
  echo "INFO: No securetransport library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_videotoolbox      # config_options+= --disable-videotoolbox       # disable VideoToolbox code [autodetect]
build_videotoolbox() {
  echo "INFO: Only available on Apple build" >>"$LOG_FILE"
  echo "INFO: No videotoolbox library to compile. Library built into OS." >>"$LOG_FILE"
}
#endregion
#endregion---------------------------------------------------------------------
#------------------------------------------------------------------------------ 


get_meson_cross_file() {
  local variant_name="$1"      # e.g., "librist"
    local extra_content="$2"     # e.g., "[built-in options]..."
    local base_filename="$host_name-meson-cross.android.txt"
    local base_filepath="$src_dir/$base_filename"
    # 1. Generate the BASE file if it doesn't exist (Android Logic)
    if [[ ! -e "$base_filepath" ]]; then
        local cpu_family="$host_arch"
        case "$host_arch" in
            "armv7a"|"arm") cpu_family="arm" ;;
            "i686"|"x86")   cpu_family="x86" ;;
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
    fi
    # 2. Handle Custom Variant logic
    if [[ -n "$variant_name" ]]; then
        local custom_filepath="$(pwd)/$host_name-meson-cross.android.${variant_name}.txt"
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

get_local_meson_cross_with_propeties() {
  local local_dir="$1"
	if [[ -z $local_dir ]]; then
		local_dir="."
	fi
	copy_path "$src_dir/$host_name-meson-cross.android.txt" "$local_dir/meson-cross.android.txt"
}

#endregion
