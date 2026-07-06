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
  generic_meson
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
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No ladspa library to compile. Library built into OS." >>"$LOG_FILE"
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
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No alsa library to compile. Library built into OS." >>"$LOG_FILE"
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
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libdc1394 library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_libdc1394         # config_options+= --enable-libdc1394           # enable IIDC-1394 grabbing using libdc1394 and libraw1394 [no]
build_libdc1394() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libdc1394 library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_libdrm            # config_options+= --disable-libdrm             # disable DRM code (Linux) [autodetect]
build_libdrm() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libdrm library to compile. Library built into OS." >>"$LOG_FILE"
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
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libiec61883 library to compile. Library built into OS." >>"$LOG_FILE"
}
build_libjsonc() {
  local lib="json-c"
  local repo="https://github.com/json-c/json-c"
  local repo_ver="json-c-0.18-20240915"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DBUILD_SHARED_LIBS=OFF"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libv4l2           # config_options+= --enable-libv4l2             # enable libv4l2/v4l-utils [no]
build_libv4l2() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libv4l2 library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_libxcb_shape      # config_options+= --enable-libxcb-shape        # enable X11 grabbing shape rendering [autodetect]
build_libxcb_shape() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libxcb-shape library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_libxcb_shm        # config_options+= --enable-libxcb-shm          # enable X11 grabbing shm communication [autodetect]
build_libxcb_shm() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libxcb-shm library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_libxcb_xfixes     # config_options+= --enable-libxcb-xfixes       # enable X11 grabbing mouse rendering [autodetect]
build_libxcb_xfixes() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libxcb-xfixes library to compile. Library built into OS." >>"$LOG_FILE"
}
build_xcbproto() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
build_libxau() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_libxcb            # config_options+= --enable-libxcb              # enable X11 grabbing using XCB [autodetect]
build_libxcb() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_rkmpp             # config_options+= --enable-rkmpp               # enable Rockchip Media Process Platform code [no]
build_rkmpp() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_v4l2_m2m          # config_options+= --disable-v4l2-m2m           # disable V4L2 mem2mem code [autodetect]
build_v4l2_m2m() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No v4l2-m2m library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_vaapi             # config_options+= --disable-vaapi              # disable Video Acceleration API (mainly Unix/Intel) code [autodetect]
build_vaapi() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No vaapi library to compile. Library built into OS." >>"$LOG_FILE"
}
build_xtrans() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
build_xorgproto() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
build_xorg_macros() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
build_libxext() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
build_libxdmcp() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
build_libxrender() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
build_libxft() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
build_x11() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No rkmpp library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_xlib              # config_options+= --disable-xlib               # disable xlib [autodetect]
build_xlib() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No xlib library to compile. Library built into OS." >>"$LOG_FILE"
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
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No libvpl library to compile. Library built into OS." >>"$LOG_FILE"
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
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No avisynth library to compile." >>"$LOG_FILE"
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
  generic_make_install "CFLAGS=\"${CFLAGS}\""
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
  generic_configure "--enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  rm -f "$dependency_install_prefix/bin/xz"
}
# build_sdl2              # config_options+= --disable-sdl2               # disable sdl2 [autodetect]
build_sdl2() {
  local lib="sdl2"
  local repo="https://github.com/libsdl-org/SDL"
  local repo_ver="release-2.32.8"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_options="-DCMAKE_BUILD_TYPE=Release \
-DSDL_SHARED=OFF \
-DSDL_STATIC=ON \
-DSDL_STATIC_PIC=ON \
-DSDL_TEST=OFF \
-DSDL_TESTS=OFF \
-DSDL_HIDAPI=OFF \
-DSDL_AUDIO=ON \
-DSDL_VIDEO=ON \
-DSDL_PTHREADS=ON \
-DSDL_RENDER=ON"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_options"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_sndio             # config_options+= --disable-sndio              # disable sndio support [autodetect]
build_sndio() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No sndio library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_zlib              # config_options+= --disable-zlib               # disable zlib [autodetect]
build_zlib() {
  # https://github.com/madler/zlib
  local lib="zlib"
  local repo="https://github.com/madler/zlib"
  local repo_ver="v1.3.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_args="-DZLIB_BUILD_EXAMPLES=OFF"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_args"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  copy_path "$src_dir/$lib/build/zlib.pc" "$install_pkgconfig_dir/zlib.pc"
  change_dir "$src_dir"
}
# build_libvo_amrwbenc    # config_options+= --enable-libvo-amrwbenc      # enable AMR-WB encoding via libvo-amrwbenc [no]
build_libvo_amrwbenc() {
  local lib="libvo_amrwbenc"
  local repo="https://sourceforge.net/projects/opencore-amr/files/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\" \
--enable-static --disable-shared"
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
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\" \
--enable-static --disable-shared"
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
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
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
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_TOOLS=OFF \
-DBUILD_TESTS=OFF \
-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
-DFFTW3_DIR=$dependency_install_prefix \
-DFFT_LIB=fftw3" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  add_libs_to_pkg -t="$install_pkgconfig_dir/libchromaprint.pc" -l="-lfftw3"
}
# build_frei0r            # config_options+= --enable-frei0r              # enable frei0r video filtering [no]
build_frei0r() {
  # https://github.com/dyne/frei0r
  local lib="frei0r"
  local repo="https://github.com/dyne/frei0r"
  local repo_ver="v2.5.1"
  local CAIRO_LIBS=$(pkg-config --libs --static cairo)
  export LDFLAGS="$LDFLAGS $CAIRO_LIBS -lpixman-1 -lpng -lfontconfig -lfreetype -lcairo -framework CoreFoundation -framework CoreGraphics -framework CoreText"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWITHOUT_OPENCV=1"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
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
  generic_configure "--with-libgpg-error-prefix=$dependency_install_prefix LIBS=\"-lpthread -ldl\" --disable-doc"
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
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DCMAKE_INSTALL_BUNDLEDIR=bin \
-DMACOSX_BUNDLE=OFF \
-DBROTLI_BUNDLED_MODE=OFF \
-DBROTLI_BUILD_TOOLS=OFF" "$src_dir/$lib"
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
  change_dir "$src_dir/$lib/build" 1
  local cmake_args="-DPNG_STATIC=ON \
-DPNG_TESTS=OFF \
-DPNG_TOOLS=OFF \
-DPNG_FRAMEWORK=OFF \
-DZLIB_LIBRARY=${dependency_install_prefix}/lib/libz.a \
-DZLIB_INCLUDE_DIR=${dependency_install_prefix}/include \
-DPNG_TARGET_ARCHITECTURE=$host_arch"
  if [[ $host_arch == "arm64" ]]; then
    cmake_args+=" -DPNG_ARM_NEON=on"
  else
    cmake_args+=" -DPNG_ARM_NEON=off"
  fi
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_args"
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
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\" LIBS=\"-lpng16\""
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
  generic_cmake "-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libass            # config_options+= --enable-libass              # enable libass subtitles rendering, needed for subtitles and ass filter [no]
build_libass() {
  # run_valid_function "build_libfribidi"
  # run_valid_function "build_libharfbuzz"
  activate_meson
  local lib="libass"
  local repo="https://github.com/libass/libass"
  local repo_ver="0.17.4"
  if [[ "$host_arch" == "x86_64" ]]; then
    export AS=nasm
  else
    get_gas_preprocessor
    export AS="'gas-preprocessor.pl -arch $meson_cpu_family -- $(xcrun --sdk "$toolchain_sys" --find clang)'"
  fi
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local config="--disable-shared --enable-static"
  if [[ $host_arch == "arm64" ]]; then
    config+=" --enable-neon"
  fi
  if isiossimulator; then
    config+=" --host=$meson_cpu_family-apple-ios-simulator"
  else
    config+=" --host=$meson_cpu_family-apple-$host_platform"
  fi
  # generic_configure "$config"
  # disable_nonessential "$src_dir/$lib"
  # do_make_and_make_install
  local meson_options=" -Dtest=disabled \
-Dcompare=disabled \
-Dprofile=disabled \
-Dfuzz=disabled \
-Dcheckasm=disabled \
-Dcoretext=enabled \
-Dasm=enabled"
  sed -i'.bak' -e "s/== 'darwin'/ in ['darwin', 'ios', 'ios-simulator']/g" "$src_dir/$lib/meson.build"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
  set_toolchain_paths
}
# build_libbluray         # config_options+= --enable-libbluray           # enable BluRay reading using libbluray [no]
build_libbluray() {
  # run_valid_function "build_lzma" 1
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No libbluray library to compile." >>"$LOG_FILE"
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
  sed -i'.bak' "s/dist-lzma//" configure.ac
  export LIBS="-lm"                              # avoid pow failure linux native
  export CFLAGS="$CFLAGS -I${dependency_install_prefix}/include"
  export CXXFLAGS=" $CXXFLAGS -I${dependency_install_prefix}/include"
  export LDFLAGS="$LDFLAGS -L${dependency_install_prefix}/lib"
  get_config_sub "$src_dir/$lib/build-aux"
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
  sed -i'.bak' 's/AC_PREREQ([2.71])/# AC_PREREQ([2.71])/g' configure.ac
  apply_patch "$PATCHDIR/caca_dither_c.patch"
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\" --libdir=$dependency_install_prefix/lib \
--disable-csharp \
--disable-java  \
--disable-python \
--disable-ruby \
--disable-doc \
--disable-cocoa \
--disable-tools \
--disable-ncurses \
--disable-pango"
  disable_nonessential "$src_dir/$lib" "src"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_ldflags
}
# build_libcdio           # config_options+= --enable-libcdio             # enable audio CD grabbing with libcdio [no]
build_libcdio() {
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No libcdio library to compile." >>"$LOG_FILE"
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
build_libcodec2() {
  local lib="libcodec2"
  local repo_ver="1.2.0"
  local repo="https://github.com/drowe67/codec2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build_native" 1
  sed -i'.bak' -E "s/set\(CMAKE_OSX_DEPLOYMENT_TARGET.*//g" "$src_dir/$lib/CMakeLists.txt"
  native_cross_vars
  do_cmake_from_build_dir "$src_dir/$lib" "-DUNITTEST=OFF -DBUILD_SHARED_LIBS=OFF -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_OSX_ARCHITECTURES=$BUILD_ARCH -DCMAKE_INSTALL_PREFIX=\"$src_dir/$lib/build_native/install\""
  disable_nonessential "$src_dir/$lib/build_native"
  do_make
  reset_cross_vars
  reset_allflags
  change_dir "$src_dir/$lib"
  apply_patch "$PATCHDIR/codec2.patch"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DUNITTEST=OFF \
-DBUILD_SHARED_LIBS=OFF \
-DCMAKE_OSX_SYSROOT=$(xcrun --sdk "$toolchain_sys" --show-sdk-path) \
-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
-DCMAKE_CROSSCOMPILING=ON \
-DGENERATE_CODEBOOK=\"$src_dir/$lib/build_native/src/generate_codebook\""
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
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
  if isiossimulator; then
  sed -i'.bak' -e "s/'ios'/'ios', 'ios-simulator'/g" "$src_dir/$lib/meson.build"
  fi
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
  get_config_guess "$src_dir/$lib/build/linux"
  get_config_sub "$src_dir/$lib/build/linux"
  touch "no.autoreconf"
  if [[ $host_arch == "arm64" ]]; then
    sed -i'.bak' 's/arch=armv7/arch=arm64/g' configure
  elif [[ $host_arch == "x86_64" ]]; then
    export AS=nasm
  fi
  do_configure "--host=arm64-apple-darwin --enable-pic --disable-cli --enable-static --disable-shared --prefix=$dependency_install_prefix"
  sed -i'.bak' 's/^SYS_ARCH=AARCH64/SYS_ARCH=/' "config.mak"
  sed -i'.bak' -E 's/\$\(AR\)\$@/\$\(AR\) rc \$@/g' Makefile
  disable_nonessential "$src_dir/$lib/build/linux"
  do_make_and_make_install ""
  if [[ ! -f "$install_pkgconfig_dir/davs2.pc" && -f "$src_dir/$lib/build/linux/davs2.pc" ]]; then
    copy_path "$src_dir/$lib/build/linux/davs2.pc" "$install_pkgconfig_dir/davs2.pc" "-f"
  fi
  sed -i'.bak' "s/Version:.*/Version: ${repo_ver}.0/g" "$install_pkgconfig_dir/davs2.pc"
  change_dir "$src_dir"
  set_toolchain_paths
}
# build_libdvdnav         # config_options+= --enable-libdvdnav           # enable libdvdnav, needed for DVD demuxing [no]
build_libdvdnav() {
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No libdvdnav library to compile." >>"$LOG_FILE"
}
build_libdvdcss() {
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No libdvdcss library to compile." >>"$LOG_FILE"
}
# build_libdvdread        # config_options+= --enable-libdvdread          # enable libdvdread, needed for DVD demuxing [no]
build_libdvdread() {
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No libdvdread library to compile." >>"$LOG_FILE"
}
build_libasound2() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libasound2 library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_libflite          # config_options+= --enable-libflite            # enable flite (voice synthesis) support via libflite [no]
build_libflite() {
  # run_valid_function "build_libasound2"
  local lib="flite"
  local repo="https://github.com/festvox/flite"
  local repo_ver="v2.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LDFLAGS="$LDFLAGS -lpthread -ldl"
  get_config_sub "$src_dir/$lib"
  get_config_guess "$src_dir/$lib"
  generic_configure "--disable-shared --with-pic"
  disable_nonessential "$src_dir/$lib"
  find . -name "Makefile" -exec sed -i'.bak' 's/cp -pd/cp -p/' {} \;
  do_make_and_make_install
  change_dir "$src_dir"
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
-Dc_link_args=\"-arch $host_arch -L$dependency_install_prefix/lib $LIBS\""
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
  local meson_options="-Dtests=disabled \
-Dharfbuzz=disabled \
-Dpng=enabled \
-Dbzip2=disabled \
-Dzlib=enabled \
-Dbrotli=enabled \
-Dc_link_args=\"-arch $host_arch -L$dependency_install_prefix/lib -lpng\""
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
  export SDKROOT=$(xcrun --sdk "$toolchain_sys" --show-sdk-path)
  export CC=$(xcrun --sdk "$toolchain_sys" --find clang)
  export CC_FOR_BUILD=$(xcrun --sdk macosx --find clang)
  if isiossimulator; then
  export CFLAGS="-arch $host_arch -isysroot $SDKROOT -mios-simulator-version-min=12.0"
  else
  export CFLAGS="-arch $host_arch -isysroot $SDKROOT -mios-version-min=12.0"
  fi
  export LDFLAGS="-arch $host_arch -isysroot $SDKROOT"
  export CFLAGS_FOR_BUILD="-arch $BUILD_ARCH -isysroot $(xcrun --sdk macosx --show-sdk-path)"
  get_config_sub "$src_dir/$lib"
  get_config_guess "$src_dir/$lib"
  if isiossimulator; then
    do_autogen "--host=$meson_cpu_family-apple-ios-simulator --disable-shared --enable-static --disable-docs --disable-deprecated --prefix=$dependency_install_prefix"
  else
    do_autogen "--host=$meson_cpu_family-apple-$host_platform --disable-shared --enable-static --disable-docs --disable-deprecated --prefix=$dependency_install_prefix"
  fi
  # {
  #   ./configure --host=aarch64-apple-ios --disable-shared --enable-static --disable-docs --disable-deprecated --prefix=$dependency_install_prefix
  # } > >(redirect_output) 2>&1 || exit_message 1 "build_libfribidi: could not configure"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
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
  local cmake_params="-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix} \
-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DSPIRV_SKIP_TESTS=ON \
-DSPIRV_WERROR=OFF \
-DSPIRV_SKIP_EXECUTABLES=ON \
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
-DCMAKE_PREFIX_PATH=${dependency_install_prefix} \
-DSPIRV-Tools_DIR=${dependency_install_prefix}/lib/cmake/SPIRV-Tools \
-DSPIRV-Tools-opt_DIR=${dependency_install_prefix}/lib/cmake/SPIRV-Tools-opt"
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
  generic_cmake "-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DENABLE_UBSAN=0 -DCMAKE_CXX_STANDARD=11 -DCMAKE_CXX_STANDARD_REQUIRED=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5" "$src_dir/$lib"
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
  sed -i'.bak' -e "s|^INSTALL_ROOT.*|INSTALL_ROOT = $dependency_install_prefix|g" \
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
  sed -i'.bak' "s/add_subdirectory(tests)/#add_subdirectory(tests)/g" "$src_dir/$lib/CMakeLists.txt"
  sed -i'.bak' "s/add_subdirectory(doc)/#add_subdirectory(doc)/g" "$src_dir/$lib/CMakeLists.txt"
  sed -i'.bak' "s/add_subdirectory(gr2fonttest)/#add_subdirectory(gr2fonttest)/g" "$src_dir/$lib/CMakeLists.txt"
  sed -i'.bak' "s/nolib_test(stdc++ $<TARGET_SONAME_FILE:graphite2>)/#nolib_test(stdc++ $<TARGET_SONAME_FILE:graphite2>)/g" "$src_dir/$lib/src/CMakeLists.txt"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DGRAPHITE2_TESTS=OFF \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  ln -sf "$dependency_install_prefix/lib/libgraphite2.a" "$dependency_install_prefix/lib/libgraphite2.so"
  change_dir "$src_dir"
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
-Dcoretext=enabled \
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
  sed -i'.bak' -E "s/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/CMakeLists.txt"
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DABSL_USE_EXTERNAL_GOOGLETEST=ON \
-DABSL_USE_GOOGLETEST_HEAD=OFF \
-DABSL_RUN_TESTS=OFF \
-DBUILD_SHARED_LIBS=OFF \
-DENABLE_UBSAN=0" "$src_dir/$lib"
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
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libjack library to compile. Library built into OS." >>"$LOG_FILE"
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
  change_dir "$src_dir/$lib/build" 1
  sed -i'.bak' -E "s/RUNTIME DESTINATION (\"?)\\$\{CMAKE_INSTALL_BINDIR\}(\"?)/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/CMakeLists.txt"
  sed -i'.bak' -E "s/RUNTIME DESTINATION (\"?)\\$\{CMAKE_INSTALL_BINDIR\}(\"?)/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/third_party/highway/CMakeLists.txt"
  sed -i'.bak' -E "s/RUNTIME DESTINATION (\"?)\\$\{CMAKE_INSTALL_BINDIR\}(\"?)/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/third_party/brotli/CMakeLists.txt"
  sed -i'.bak' -E "s/RUNTIME DESTINATION (\"?)\\$\{CMAKE_INSTALL_BINDIR\}(\"?)/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/CMakeLists.txt"
  sed -i'.bak' -E "s/RUNTIME DESTINATION (\"?)\\$\{CMAKE_INSTALL_BINDIR\}(\"?)/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/tools/CMakeLists.txt"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
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
-DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
-DBUILD_TESTING=OFF \
-DJPEGXL_STATIC=ON \
-DJPEGXL_ENABLE_TOOLS=OFF \
-DJPEGXL_ENABLE_BENCHMARK=OFF \
-DJPEGXL_ENABLE_EXAMPLES=OFF \
-DCMAKE_PREFIX_PATH=\"$dependency_install_prefix\" \
-DJPEGXL_ENABLE_DOXYGEN=OFF \
-DJPEGXL_ENABLE_MANPAGES=OFF \
-DJPEGXL_ENABLE_FUZZERS=OFF \
-DJPEGXL_ENABLE_VIEWERS=OFF \
-DJPEGXL_ENABLE_SJPEG=OFF \
-DJPEGXL_ENABLE_PLUGINS=OFF \
-DJPEGXL_BUNDLE_LIBPNG=OFF \
-DBUILD_TESTING=OFF \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DPNG_LIBRARY=$dependency_install_prefix/lib/libpng.a \
-DPNG_PNG_INCLUDE_DIR=$dependency_install_prefix/include \
-DJPEG_LIBRARY=$dependency_install_prefix/lib/libjpeg.a \
-DJPEG_INCLUDE_DIR=$dependency_install_prefix/include \
-DHWY_LIBRARY=$dependency_install_prefix/lib/libhwy.a \
-DHWY_INCLUDE_DIR=$dependency_install_prefix/include \
-DBROTLI_INCLUDE_DIR=$dependency_install_prefix/include \
-DBROTLICOMMON_LIBRARY=$dependency_install_prefix/lib/libbrotlicommon.a \
-DBROTLIENC_LIBRARY=$dependency_install_prefix/lib/libbrotlienc.a \
-DBROTLIDEC_LIBRARY=$dependency_install_prefix/lib/libbrotlidec.a \
-DJPEGXL_FORCE_SYSTEM_LCMS2=ON"
  # force third party PIC
  sed -i'.bak' '1s/^/set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "Force PIC" FORCE)\n/' "$src_dir/$lib/third_party/CMakeLists.txt"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  reset_ldflags
  change_dir "$src_dir"
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
  change_dir "$src_dir/$lib/build" 1
  export ASFLAGS="$ASFLAGS -DPIC"
  local cmake_params="-DCMAKE_BUILD_TESTS=OFF \
-DCMAKE_ASM_NASM_FLAGS=\"-DPIC\" \
-DBUILD_SHARED_LIBS=OFF"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
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
  if isiossimulator; then
  get_config_sub "$src_dir/$lib/build-aux"
  get_config_guess "$src_dir/$lib/build-aux"
  get_config_sub "$src_dir/$lib/libcharset/build-aux"
  get_config_guess "$src_dir/$lib/libcharset/build-aux"
  fi
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
CFLAGS=\"$CFLAGS\"" "" "minimal"
  disable_nonessential "$src_dir/$lib"
  do_make "" "minimal"
  do_make_install "" "-C lib install" "minimal"
  remove_path -f "$dependency_install_prefix/include/iconv.h"
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
  if isiossimulator; then
  get_config_sub "$src_dir/$lib/build-aux"
  get_config_guess "$src_dir/$lib/build-aux"
  get_config_sub "$src_dir/$lib/libcharset/build-aux"
  get_config_guess "$src_dir/$lib/libcharset/build-aux"
  fi
  touch "no.autoreconf"
  generic_configure "--prefix=${dependency_install_prefix} \
--enable-static \
--disable-shared \
--enable-pic \
--with-pic \
--disable-nls \
--with-libintl-prefix=${dependency_install_prefix} \
CFLAGS=\"$CFLAGS\"" "" "full"
  do_make_and_make_install "" "" "full"
  cat > "$src_dir/$lib/iconv-compat.c" <<'EOF'
#include <stddef.h>

typedef void *iconv_t;

extern iconv_t libiconv_open(const char *tocode, const char *fromcode);
extern size_t libiconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
extern int libiconv_close(iconv_t cd);

iconv_t iconv_open(const char *tocode, const char *fromcode) {
  return libiconv_open(tocode, fromcode);
}

size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft) {
  return libiconv(cd, inbuf, inbytesleft, outbuf, outbytesleft);
}

int iconv_close(iconv_t cd) {
  return libiconv_close(cd);
}
EOF
  "$CC" $CFLAGS -c "$src_dir/$lib/iconv-compat.c" -o "$src_dir/$lib/iconv-compat.o"
  ar -q "$dependency_install_prefix/lib/libiconv.a" "$src_dir/$lib/iconv-compat.o"
  ranlib "$dependency_install_prefix/lib/libiconv.a"
  remove_path -f "$dependency_install_prefix/include/iconv.h"
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
  change_dir "$src_dir"
  reset_cflags
  reset_cxxflags
}
build_gettext() {
  local lib="gettext"
  local repo="https://ftp.gnu.org/pub/gnu/gettext/gettext-1.0.tar.gz"
  local mirror="https://ftpmirror.gnu.org/pub/gnu/gettext/gettext-1.0.tar.gz"
  local repo_ver="1.0"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib" --alt="$mirror"
  change_dir "$src_dir/$lib"
  do_autogen --skip-gnulib
  touch "no.autoreconf"
  change_dir "$src_dir/$lib/gettext-runtime"
  local cflags="$CFLAGS -Dlibintl_STATIC -D_GNU_SOURCE -std=gnu11 -I$(xcrun --sdk macosx --show-sdk-path)/usr/include"
  export CFLAGS=$cflags
  local config="--prefix=${dependency_install_prefix} \
--with-sysroot=\"${dependency_install_prefix}\" \
--with-included-libintl \
--without-libintl-prefix \
--with-included-gettext \
--enable-static \
--disable-shared \
--disable-java \
--disable-csharp \
--disable-native-java \
--disable-libasprintf \
--disable-openmp \
--disable-doc \
am_cv_func_iconv=yes \
am_cv_func_iconv_works=yes \
am_cv_lib_iconv=yes \
LIBICONV=-liconv \
LTLIBICONV=-liconv \
LIBS=-liconv"
  find "$src_dir/$lib" -type f -name configure -exec sed -i \
    -e 's/ACLOCAL=${ACLOCAL-"${am_missing_run}aclocal-${am__api_version}"}/ACLOCAL=${ACLOCAL-"${am_missing_run}aclocal"}/g' \
    -e 's/AUTOMAKE=${AUTOMAKE-"${am_missing_run}automake-${am__api_version}"}/AUTOMAKE=${AUTOMAKE-"${am_missing_run}automake"}/g' {} +
  touch "no.autoreconf"
  touch "no.autogen"
  generic_configure "$config \
CFLAGS=\"$cflags\" \
LIBS=\"-liconv\""
  # disable_nonessential "$src_dir/$lib"
  change_dir "$src_dir/$lib/gettext-runtime/intl"
  MAKE_INSTALL_JOBS=1 do_make_and_make_install "CFLAGS=\"$cflags\" LIBS=\"-liconv\"" "CFLAGS=\"$cflags\" LIBS=\"-liconv\""
  change_dir "$src_dir/$lib/gettext-runtime"
  MAKE_INSTALL_JOBS=1 do_make_and_make_install "CFLAGS=\"$cflags\" LIBS=\"-liconv\"" "CFLAGS=\"$cflags\" LIBS=\"-liconv\""
  cat > "$install_pkgconfig_dir/intl.pc" <<EOF
prefix=${dependency_install_prefix}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: intl
Description: GNU gettext library
Version: ${repo_ver}
Libs: -L\${libdir} -lintl
Cflags: -I\${includedir} -Dlibintl_STATIC
EOF
  cat > "$install_pkgconfig_dir/iconv.pc" <<EOF
prefix=${dependency_install_prefix}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: iconv
Description: Apple SDK iconv shim
Version: 1.0
Libs: -liconv
Cflags:
EOF
  change_dir "$src_dir/$lib/libtextstyle"
  touch "no.autoreconf"
  touch "no.autogen"
  generic_configure "$config \
CFLAGS=\"$cflags\" \
LIBS=\"-liconv\""
  MAKE_INSTALL_JOBS=1 do_make_and_make_install
#   change_dir "$src_dir/$lib/gettext-tools"
#   touch "no.autoreconf"
#   config+=" --disable-curses \
# --disable-examples \
# --disable-nls \
# --disable-libasprintf \
# --without-libtextstyle-prefix"
#   generic_configure "$config \
# CFLAGS=\"$cflags\" \
# LIBS=\"$LIBS\" \
# LDFLAGS=\"$LDFLAGS $LIBS\""
#   disable_nonessential "$src_dir/$lib/gettext-tools" "examples" "tests"
#   local make_config="LDFLAGS=\"-L$src_dir/$lib/gettext-tools/.libs -L$src_dir/$lib/gettext-tools/src/.libs ${LDFLAGS}\" LIBS=\"$LIBS\""
#   do_make_and_make_install "$make_config" "$make_config"
  reset_allflags
}
build_libffi() {
  local lib="libffi"
  local repo="https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--disable-multi-os-directory --host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\""
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
-DOAPV_BUILD_STATIC_LIB=ON \
-DOAPV_BUILD_SHARED_LIB=ON \
-DPCRE2_BUILD_PCRE2_8=ON"
  sed -i'.bak' -E "s/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/CMakeLists.txt"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_glib() {
  # run_valid_function "build_libffi"
  # run_valid_function "build_pcre2"
  activate_meson
  local lib="glib"
  local repo="https://github.com/GNOME/glib"
  local repo_ver="2.82.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export C_INCLUDE_PATH="${dependency_install_prefix}/include"
  export LIBRARY_PATH="${dependency_install_prefix}/lib"
  export PKG_CONFIG_LIBDIR="${dependency_install_prefix}/lib/pkgconfig"
  export LDFLAGS="$LDFLAGS -lintl -lresolv -framework CoreFoundation"
  local meson_options="-Dforce_posix_threads=true \
-Dman-pages=disabled \
-Dsysprof=disabled \
-Dglib_debug=disabled \
-Dnls=disabled \
-Dtests=false \
-Dglib_checks=false \
-Dinstalled_tests=false \
-Dxattr=false \
-Dlibmount=disabled \
-Ddtrace=false \
-Dsystemtap=false \
--includedir=\"${dependency_install_prefix}/include\" \
-Dc_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -lintl -lresolv -framework CoreFoundation -isysroot ${IOS_SYSROOT}\" \
-Dcpp_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -lintl -lresolv -framework CoreFoundation -isysroot ${IOS_SYSROOT}\" \
--wrap-mode=nofallback"
  sed -i'.bak' \
    -e "s|libiconv = dependency('iconv')|libiconv = declare_dependency(link_args : ['-liconv'])|" \
    -e "s|libiconv = cc.find_library('iconv', required : true)|libiconv = declare_dependency(link_args : ['-liconv'])|" \
    "$src_dir/$lib/meson.build"
  sed -i'.bak' \
    -e "s|libintl = dependency('intl', required: false)|libintl = declare_dependency(link_args : ['-lintl', '-liconv'])|" \
    -e "s|if libintl.found() and libintl.type_name() != 'internal'|if libintl.found()|g" \
    "$src_dir/$lib/meson.build"
  sed -i'.bak' '/#ifdef HAVE_PIPE2/,/#endif/d' "$src_dir/$lib/glib/glib-unixprivate.h"
  generic_meson "$meson_options"
  do_ninja_and_ninja_install
  sed -i'.bak' 's/-lglib-2.0.*$/-lglib-2.0 -lm -lintl/' "$install_pkgconfig_dir/glib-2.0.pc"
  change_dir "$src_dir"
  reset_cflags
  unset C_INCLUDE_PATH
  unset LIBRARY_PATH
  unset PKG_CONFIG_LIBDIR
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
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DBUILD_STATIC=on \
-DCMAKE_INSTALL_DATAROOTDIR=$dependency_install_prefix \
-DBUILD_TESTS=off \
-DBUILD_DOC=off \
-DINSTALL_HELPER_SCRIPTS=off \
-DINSTALL_PYTHON_MODULE=OFF" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  sed -i'.bak' 's/-llensfun/-llensfun -framework CoreText -framework CoreFoundation/' "$install_pkgconfig_dir/lensfun.pc"
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
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\""
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
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\" --disable-programs --with-audio=dummy --with-cpu=aarch64"
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
  get_config_sub "$src_dir/$lib"
  generic_configure "--enable-nasm --enable-libmpg123 --disable-frontend"
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
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  sed -i'.bak' 's|libdir=.*|libdir=\${prefix}/lib/oapv|g' "$install_pkgconfig_dir/oapv.pc"
  sed -i'.bak' 's|includedir=.*|includedir=\${prefix}/include|g' "$install_pkgconfig_dir/oapv.pc"
  ln -sf "$dependency_install_prefix/lib/oapv/liboapv.a" "$dependency_install_prefix/lib/liboapv.a"
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
-DBUILD_opencv_dnn=OFF \
-DOAPV_BUILD_STATIC_LIB=ON \
-DOAPV_BUILD_SHARED_LIB=OFF \
-DOPENCV_GENERATE_PKGCONFIG=ON \
-DOPENCV_FORCE_3RDPARTY_BUILD=ON \
-DBUILD_PROTOBUF=ON \
-DPROTOBUF_UPDATE_FILES=OFF \
-DCMAKE_CXX_FLAGS=\"-Wno-unknown-warning-option\" \
-DCMAKE_C_FLAGS=\"-Wno-unknown-warning-option\" \
-DCMAKE_IGNORE_PATH=${dependency_install_prefix}/include/google/protobuf \
-DOPENCV_INCLUDE_INSTALL_PATH=${dependency_install_prefix}/include \
-DHAVE_DSHOW=0"
  if [[ "$host_arch" == "arm64" ]]; then
    cmake_params+=" -DENABLE_NEON=ON \
-DENABLE_SSE=OFF \
-DENABLE_SSE2=OFF \
-DENABLE_SSSE3=OFF \
-DENABLE_AVX=OFF \
-DENABLE_AVX2=OFF \
-DBUILD_ITT=OFF \
-DWITH_ITT=OFF \
-DHAVE_ITT=OFF"
  else
    cmake_params+=" -DENABLE_NEON=OFF \
-DENABLE_SSE=ON \
-DENABLE_SSE2=ON \
-DENABLE_SSSE3=ON \
-DENABLE_AVX=ON \
-DENABLE_AVX2=ON"
  fi
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  if [[ -f "$install_pkgconfig_dir/opencv4.pc" ]]; then
    copy_path "$install_pkgconfig_dir/opencv4.pc" "$install_pkgconfig_dir/opencv.pc" -f
  else
    copy_path "$src_dir/$lib/build/unix-install/opencv4.pc" "$install_pkgconfig_dir/opencv.pc" -f
  fi
  export PKG_CONFIG_PATH=$original_pkg_path
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
  if isiossimulator; then
    sed -i'.bak' "s/'ios',/'ios', 'ios-simulator',/g" "$src_dir/$lib/meson.build"
  fi
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
  if [[ -f "$install_pkgconfig_dir/libopenjp2.pc" ]]; then
    sed -i'.bak' 's/-l-lpthread/-lpthread/g' "$install_pkgconfig_dir/libopenjp2.pc"
  fi
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
-DINSTALL_MANPAGES=OFF \
-DOGG_INCLUDE_DIR=$dependency_install_prefix/include \
-DOGG_LIBRARY=$dependency_install_prefix/lib/libogg.a"
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
  export CXXFLAGS="$CXXFLAGS -I${dependency_install_prefix}/include -std=c++17"
  export LDFLAGS="$LDFLAGS -L${dependency_install_prefix}/lib -L${dependency_install_prefix}/lib/${host_target} "
  get_config_guess "$src_dir/$lib/build-aux"
  get_config_sub "$src_dir/$lib/build-aux"
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
  # change_dir "$src_dir"
  # do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  # change_dir "$src_dir/$lib"
  # generic_configure "--disable-shared --enable-static"
  # disable_nonessential "$src_dir/$lib"
  # do_make_and_make_install
  # change_dir "$src_dir"
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
  export LIBS="-ldovi -liconv -lxxhash"
  local config_options+=" -Dvulkan-registry=$dependency_install_prefix/share/vulkan/registry/vk.xml"
  local meson_options=" -Ddemos=false \
-Dtests=false \
-Dbench=false \
-Dfuzz=false \
-Dvulkan=enabled \
-Dvk-proc-addr=disabled \
-Dshaderc=disabled \
-Dglslang=disabled \
-Dc_link_args=\"-arch $host_arch -L$dependency_install_prefix/lib $LIBS\" \
$config_options" # https://mesonbuild.com/Dependencies.html#shaderc trigger use of shaderc_combined
  generic_meson "$meson_options"
  # Fix Python 3.14 ElementTree compatibility in libplacebo
  sed -i'.bak' 's/ET.parse(xmlfile)/ET.parse(xmlfile).getroot()/g' \
    "$src_dir/$lib/src/vulkan/utils_gen.py"
  # disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  sed -i'.bak' 's/-lplacebo.*$/-lplacebo -lm -lxxhash -lstdc++/' "$install_pkgconfig_dir/libplacebo.pc"
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
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libpulse library to compile. Library built into OS." >>"$LOG_FILE"
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
  sed -i'.bak' 's/all: libquirc.$(LIB_SUFFIX) qrtest/all: libquirc.$(LIB_SUFFIX)/g' "$src_dir/$lib/Makefile"
  sed -i'.bak' 's|install -o root -g root -m 0755 quirc-demo $(DESTDIR)$(PREFIX)/bin|# install -o root -g root -m 0755 quirc-demo $(DESTDIR)$(PREFIX)/bin|g' "$src_dir/$lib/Makefile"
  sed -i'.bak' 's|install -o root -g root -m 0755 quirc-scanner $(DESTDIR)$(PREFIX)/bin|# install -o root -g root -m 0755 quirc-scanner $(DESTDIR)$(PREFIX)/bin|g' "$src_dir/$lib/Makefile"
  sed -i'.bak' 's|install: libquirc.a libquirc.$(LIB_SUFFIX) quirc-demo quirc-scanner|install: libquirc.a libquirc.$(LIB_SUFFIX)|g' "$src_dir/$lib/Makefile"
  sed -i'.bak' 's/SDL_CFLAGS := .*/SDL_CFLAGS := /g' "$src_dir/$lib/Makefile"
  sed -i'.bak' 's/SDL_LIBS = .*/SDL_LIBS = /g' "$src_dir/$lib/Makefile"
  sed -i'.bak' 's/OPENCV_CFLAGS := .*/OPENCV_CFLAGS := /g' "$src_dir/$lib/Makefile"
  sed -i'.bak' 's/OPENCV_LIBS = .*/OPENCV_LIBS = /g' "$src_dir/$lib/Makefile"
  sed -i'.bak' 's/-o root -g root//g' "$src_dir/$lib/Makefile"
  sed -i'.bak' 's/cp -d/cp -P/g' "$src_dir/$lib/Makefile"
  do_make "libquirc.a PREFIX=${dependency_install_prefix}"
  disable_nonessential "$src_dir/$lib"
  do_make_install "PREFIX=${dependency_install_prefix} INSTALL=\"install -m 0644\""
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
  sed -i'.bak' 's/Libs.private:.*//g' "$dependency_install_prefix/lib/pkgconfig/librabbitmq.pc"
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
  cargo_build_and_install "--no-default-features --features=asm,binaries --profile release-no-lto" "--no-default-features --library-type=staticlib --features=asm,binaries"
  change_dir "$src_dir"
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
  generic_meson "$meson_options"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
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
  export CFLAGS="$CFLAGS -DCAIRO_HAS_INT64_T=1"
  export CXXFLAGS="$CXXFLAGS -DCAIRO_HAS_INT64_T=1"
  export LDFLAGS="$LDFLAGS -lpthread"
  export LIBS="-lfontconfig -lfreetype -lpng -lpthread -lbrotlidec -lbrotlicommon -ldl -lstdc++"
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
-Dc_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -isysroot ${SDKROOT} $LIBS\" \
-Dcpp_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -isysroot ${SDKROOT} $LIBS\""
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
  get_config_sub "$src_dir/$lib/expat/conftools"
  get_config_guess "$src_dir/$lib/expat/conftools"
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
  generic_configure "--enable-static --disable-shared --disable-doxygen-doc"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libthai() {
  # run_valid_function "build_libdatrie"
  local lib="libthai"
  local repo="https://github.com/tlwg/libthai/releases/download/v0.1.29/libthai-0.1.29.tar.xz"
  local repo_ver="v0.1.29"
  install_missing_packages "libdatrie"
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  generic_configure "--enable-static --disable-shared --disable-doxygen-doc"
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
  export LIBS="-lfontconfig -lexpat -lfreetype -lbrotlidec -lbrotlicommon -lpng -lz -lbz2 -lintl -liconv -ldl -framework CoreFoundation"
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
-Dc_args=\"-arch $host_arch -I${dependency_install_prefix}/include -isysroot ${SDKROOT} -DGLIB_STATIC_COMPILATION\" \
-Dcpp_args=\"-arch $host_arch -I${dependency_install_prefix}/include -isysroot ${SDKROOT} -DGLIB_STATIC_COMPILATION\" \
-Dc_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -isysroot ${SDKROOT} $LIBS\" \
-Dcpp_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -isysroot ${SDKROOT} $LIBS\""
  # disable tools - not needed for ffmpeg
  sed -i'.bak' "s/subdir('utils')/# subdir('utils')/g" meson.build
  sed -i'.bak' "s/ApplicationServices/CoreFoundation/g" meson.build
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
  if isiossimulator; then
    min_ver="-mios-simulator-version-min=$MIN_IOS_VERSION"
    target_min="$host_arch-apple-ios$MIN_IOS_VERSION-simulator"
  else
    min_ver="-miphoneos-version-min=$MIN_IOS_VERSION"
    target_min="$host_arch-apple-ios$MIN_IOS_VERSION"
  fi
  local meson_options="-Ddocs=disabled \
-Dintrospection=disabled \
-Dvala=disabled \
-Davif=disabled \
-Dpixbuf-loader=disabled \
-Dtests=false \
-Drsvg-convert=disabled \
-Dtriplet=$rust_target \
-Dc_args=\"-arch $host_arch -I${dependency_install_prefix}/include -target $target_min $min_ver -isysroot ${SDKROOT} -DGLIB_STATIC_COMPILATION\" \
-Dcpp_args=\"-arch $host_arch -I${dependency_install_prefix}/include -target $target_min $min_ver -isysroot ${SDKROOT} -DGLIB_STATIC_COMPILATION\" \
-Dc_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -target $target_min $min_ver -lresolv -isysroot ${SDKROOT}\" \
-Dcpp_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -target $target_min $min_ver -lresolv -isysroot ${SDKROOT}\""
  generic_meson "$meson_options"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
  add_libs_to_pkg -t="$install_pkgconfig_dir/librsvg-2.0.pc" -p="-lresolv"
  sed -i'.bak' 's/-lrsvg-2/-lrsvg-2 -framework CoreFoundation/g' "$install_pkgconfig_dir/librsvg-2.0.pc"
  if [[ $host_arch == "x86_64" ]]; then
    # png.o always compiles to arm64 for some reason. remove png.o and thin the library
    if ar t $dependency_install_prefix/lib/librsvg-2.a | grep png.o > /dev/null; then
      ar d $dependency_install_prefix/lib/librsvg-2.a png.o > >(redirect_output) || exit_message 1 "Failed to remove incorrectly compiled png.o from librsvg-2.a"
      lipo $dependency_install_prefix/lib/librsvg-2.a -thin x86_64 -output $dependency_install_prefix/lib/librsvg-2.a.thin > >(redirect_output) || exit_message 1 "Failed to thin librsvg-2.a"
      mv -f $dependency_install_prefix/lib/librsvg-2.a.thin $dependency_install_prefix/lib/librsvg-2.a > >(redirect_output) || exit_message 1 "Failed to replace librsvg-2.a with thin version"
    fi
  fi
}
# build_librtmp           # config_options+= --enable-librtmp             # enable RTMP[E] support via librtmp [no]
build_librtmp() {
  # https://github.com/mirror/rtmpdump
  local lib="librtmp"
  local repo="git://git.ffmpeg.org/rtmpdump"
  local repo_ver="v2.6"
  activate_meson
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LIBS="-lpthread -ldl -lssl"
  do_make "-C librtmp SHARED= INC=\"-I$dependency_install_prefix/include\" \
LDFLAGS=\"$LDFLAGS\" \
XCFLAGS=\"$CFLAGS\" \
INC=\"${dependency_install_prefix}/include\" \
XLDFLAGS=\"$LDFLAGS $LIBS\" \
prefix=${dependency_install_prefix}"
  disable_nonessential "$src_dir/$lib"
  do_make_install "SHARED= prefix=${dependency_install_prefix} LDFLAGS=\"$LDFLAGS\""
  change_dir "$src_dir"
  unset LIBS
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
  local meson_options="-Dtests=disabled -Dcmdline=disabled -Dladspa=disabled -Dlv2=disabled"
  generic_meson "$meson_options"
  local FILE_PATH="$src_dir/$lib/src/common/mathmisc.cpp"
  if ! grep -q "<cstddef>" "$FILE_PATH"; then
    # Create a temporary file and add the include after the first line (or at the top)
    sed -i'.bak' '1i\
#include <cstddef>' "$FILE_PATH"
  fi
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  change_dir "$src_dir"
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
  change_dir "$src_dir/$lib/build" 1
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
-DBUILD_SHARED_LIBS=OFF"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  if [[ -f "$src_dir/$lib/build/libshaderc_util/libshaderc_util.a" ]] ; then
    copy_path "$src_dir/$lib/build/libshaderc_util/libshaderc_util.a" "$dependency_install_prefix/lib/libshaderc_util.a" >>"$LOG_FILE"
  fi
  sed -i'.bak' "s/Libs: .*/& -lstdc++/g" "$install_pkgconfig_dir/shaderc_combined.pc"
  sed -i'.bak' "s/Libs: .*/& -lstdc++/g" "$install_pkgconfig_dir/shaderc_static.pc"
  sed -i'.bak' "s/-lshaderc_shared/-lshaderc -lshaderc_util/g" "$install_pkgconfig_dir/shaderc.pc"
  add_libs_to_pkg -t="$install_pkgconfig_dir/shaderc.pc" -l="-lglslang -lSPIRV -lSPIRV-Tools -lSPIRV-Tools-opt"
  find "$dependency_install_prefix/lib" -name 'libshaderc*.dylib' -delete
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
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--enable-static --disable-shared --host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\""
  sed -i'.bak' -E 's/void shine_mdct_initialise.*/void shine_mdct_initialise(shine_global_config *config);/' "$src_dir/$lib/src/lib/l3mdct.h"
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
  if [[ "$host_arch" == "arm64" || "$host_arch" == "aarch64" ]]; then
    # Upstream libsoxr assumes ARM SIMD is only exposed as __arm__ and probes
    # 32-bit ARM-only NEON flags. Apple Silicon needs a small source patch.
    perl -0pi -e 's/elseif \(CMAKE_SYSTEM_PROCESSOR MATCHES "\^arm"\)/elseif (CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm64|aarch64)")\n  set (TRIAL_C_FLAGS\n    " "\n  )\n  set (TEST_C_SOURCE "\n    #include <arm_neon.h>\n    int main(int c, char * * v) {\n      float32x4_t a = vdupq_n_f32((float)c), b = vdupq_n_f32((float)!!v);\n      return !vgetq_lane_u32(vceqq_f32(a,b),0);\n    }\n  ")\nelseif (CMAKE_SYSTEM_PROCESSOR MATCHES "^arm")/' \
      cmake/Modules/FindSIMD32.cmake
    sed -i '.bak' 's/#elif !defined(PFFFT_SIMD_DISABLE) && defined(__arm__)/#elif !defined(PFFFT_SIMD_DISABLE) \&\& (defined(__arm__) || defined(__aarch64__) || defined(__arm64__))/g' src/pffft.c
    sed -i '.bak' 's/#ifdef __arm__/#if defined(__arm__) || defined(__aarch64__) || defined(__arm64__)/g' src/pffft.c src/pffft-wrap.c
    sed -i '.bak' 's/#elif defined __arm__/#elif defined __arm__ || defined __aarch64__ || defined __arm64__/g' src/dev32s.h
    sed -i '.bak' 's/#if defined __arm__/#if defined __arm__ || defined __aarch64__ || defined __arm64__/g' src/cr-core.c
  fi
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
  generic_cmake "-DCMAKE_BUILD_TYPE=Release \
-DENABLE_STATIC=ON \
-DENABLE_SHARED=OFF \
-DENABLE_APPS=OFF \
-DUSE_STATIC_LIBSTDCXX=ON \
-DUSE_ENCLIB=openssl \
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
  local cmake_params="-DBUILD_SHARED_LIBS=OFF \
-DWITH_STATIC_LIB=ON \
-DWITH_EXAMPLES=OFF \
-DWITH_TESTING=OFF \
-DWITH_SERVER=OFF \
-DWITH_ZLIB=ON \
-DWITH_SFTP=ON \
-DWITH_GSSAPI=OFF \
-DWITH_NACL=OFF \
-DWITH_PCAP=OFF \
-DOPENSSL_INCLUDE_DIR=${dependency_install_prefix}/include \
-DOPENSSL_LIBRARY=${dependency_install_prefix}/lib/libssl.a \
-DOPENSSL_CRYPTO_LIBRARY=${dependency_install_prefix}/lib/libcrypto.a \
-DOPENSSL_ROOT_DIR=${dependency_install_prefix} \
-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix}"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
  add_libs_to_pkg -t="$install_pkgconfig_dir/libssh.pc" -l="-lcrypto"
}
build_cpuinfo() {
  local lib="cpuinfo"
  local repo="https://github.com/pytorch/cpuinfo"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "main"
  change_dir "$src_dir/$lib/build" 1
  sed -i'.bak' -E "s/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/CMakeLists.txt"
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release \
-DCPUINFO_LIBRARY_TYPE=static \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DBUILD_SHARED_LIBS=OFF"
  change_dir "$src_dir/$lib/deps/googletest/build" 1
  do_cmake_from_build_dir "$src_dir/$lib/deps/googletest" "-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DBUILD_SHARED_LIBS=OFF"
  do_make_and_make_install
  change_dir "$src_dir/$lib/deps/googlebenchmark/build" 1
  do_cmake_from_build_dir "$src_dir/$lib/deps/googlebenchmark" "-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DGOOGLETEST_PATH=\"$src_dir/$lib/deps/googletest\" \
-DBENCHMARK_ENABLE_WERROR=OFF \
-DBUILD_SHARED_LIBS=OFF"
  do_make_and_make_install
  change_dir "$src_dir/$lib/deps/clog/build" 1
  do_cmake_from_build_dir "$src_dir/$lib/deps/clog" "-DCMAKE_BUILD_TYPE=Release \
-DCLOG_BUILD_TESTS=OFF \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DBUILD_SHARED_LIBS=OFF"
  do_make_and_make_install
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release \
-DUSE_SYSTEM_LIBS=ON \
-DUSE_SYSTEM_GOOGLEBENCHMARK=ON \
-DUSE_SYSTEM_GOOGLETEST=ON \
-DCPUINFO_BUILD_UNIT_TESTS=OFF \
-DCPUINFO_BUILD_TOOLS=OFF \
-DCPUINFO_BUILD_MOCK_TESTS=OFF \
-DCPUINFO_BUILD_BENCHMARKS=OFF \
-DCPUINFO_LIBRARY_TYPE=static \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DBUILD_SHARED_LIBS=OFF"
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
      sed -i'.bak' -E "s/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_FULL_BINDIR\}/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_FULL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/Source/App/CMakeLists.txt"
      do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DUSE_CPUINFO=SYSTEM" # -DSVT_AV1_LTO=OFF if fails try adding this
      disable_nonessential "$src_dir/$lib"
      do_make_and_make_install
          change_dir "$src_dir"
    else
      echo -e "WARNING: 32bit not supported" >>"$LOG_FILE"
    fi
}
# build_libopenvino       # config_options+= --enable-libopenvino         # enable OpenVINO as a DNN module backend for DNN based filters like dnn_processing [no]
build_libopenvino() {
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No libopenvino library to compile." >>"$LOG_FILE"
}
# build_libtorch          # config_options+= --enable-libtorch            # enable Torch as one DNN backend [no]
build_libtorch() {
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No libtorch library to compile." >>"$LOG_FILE"
}
# build_libtensorflow     # config_options+= --enable-libtensorflow       # enable TensorFlow as a DNN module backend for DNN based filters like sr [no]
build_libtensorflow() {
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No libtensorflow library to compile." >>"$LOG_FILE"
}
build_libdeflate() {
  local lib="libdeflate"
  local repo="https://github.com/ebiggers/libdeflate"
  local repo_ver="v1.25"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=$dependency_install_prefix -DENABLE_SHARED=0 -DLIBDEFLATE_BUILD_GZIP=OFF"
  generic_cmake "$cmake_params" "$src_dir/$lib"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  find "$dependency_install_prefix/lib" -name "libdeflate*.dylib" -delete
}
build_jbig() {
  local lib="jbig"
  local repo="https://github.com/ImageMagick/jbig"
  local repo_ver="master"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  sed -i'.bak' "s|CCFLAGS = -O2 -W|CCFLAGS = -O2 -W ${CFLAGS}|g" Makefile
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
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--enable-static --disable-shared --disable-docs --disable-tools --disable-tests LIBS='-lsharpyuv' --host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\""
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  add_libs_to_pkg -t="$install_pkgconfig_dir/libtiff-4.pc" -l="-ltiff -llzma -ljpeg -lz -ljbig -lwebp -lLerc -lsharpyuv"
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
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\""
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
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
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\" \
--enable-static --disable-shared --disable-programs --disable-tests"
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
  export CFLAGS="$CFLAGS -I${dependency_install_prefix}/include "
  export LDFLAGS="$LDFLAGS -L${dependency_install_prefix}/lib -L${dependency_install_prefix}/lib/${host_target}"
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\" --enable-static --disable-shared --bindir=$dependency_install_prefix/bin"
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
  sed -i'.bak' "s/Libs: .*/& -lidn2 -lunistring -liconv/" "$install_pkgconfig_dir/libpsl.pc"
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
  export LDFLAGS="${LDFLAGS} -lleptonica -lz -larchive -ltiff -lpng16 \
        -ljpeg -lgif -lwebpmux -lwebp -lopenjp2 -ljbig -lLerc \
        -lsharpyuv -llzma -lzstd -ldeflate"
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot='$IOS_SYSROOT' \
--disable-openmp \
--with-archive \
--disable-graphics \
--disable-tessdata-prefix \
--without-curl \
--without-archive \
--disable-training \
--disable-doc \
LIBLEPT_HEADERSDIR=$dependency_install_prefix/include \
--datadir=$dependency_install_prefix/bin"
  sed -i'.bak' 's/-lrt//g' "$src_dir/$lib/Makefile"
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
        -lsharpyuv -llzma -lzstd -ldeflate" \
   -rp="lept libarchive liblzma libtiff-4"
   sed -i'.bak' 's/-ltesseract/-ltesseract -framework Accelerate /g' "$install_pkgconfig_dir/tesseract.pc"
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
    sed -i'.bak' "/^SUBDIRS/s/ frontend.*//" Makefile.am || exit_message 1 "build_libtwolame: could not update makefile for twolame"
  fi
  touch "no.autogen"
  generic_configure "--enable-static --disable-shared"
  find . -name "Makefile" -exec sed -i'.bak' 's/-std=gnu23/-std=gnu99/g' {} +
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libuavs3d         # config_options+= --enable-libuavs3d           # enable AVS3 decoding via libuavs3d [no]
build_libuavs3d() {
  local lib="libuavs3d"
  # https://github.com/uavs3/uavs3d
  local repo="https://github.com/uavs3/uavs3d"
  local repo_ver="master"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  chmod -R a+rwx "$src_dir/$lib/version.sh"
  eval "$src_dir/$lib/version.sh" > >(redirect_output) 2>&1
  change_dir "$src_dir/$lib/build" 1
  sed -i'.bak' 's/add_executable(uavs3dec/#add_executable(uavs3dec/g' "$src_dir/$lib/CMakeLists.txt"
  sed -i'.bak' 's/target_link_libraries(uavs3dec/#target_link_libraries(uavs3dec/g' "$src_dir/$lib/CMakeLists.txt"
  sed -i'.bak' 's|aux_source_directory(./test|#aux_source_directory(./test|g' "$src_dir/$lib/CMakeLists.txt"
  local cmake_params="-DCOMPILE_10BIT=0 \
-DBUILD_SHARED_LIBS=0 \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
-DBUILD_DECODER=OFF \
-DCMAKE_BUILD_TYPE=Release"
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
-DBUILD_SHARED_LIBS=0" "$src_dir/$lib" # '-DUSE_OMP' is on by default, but somehow libomp ('cygwin_local_install/lib/gcc/i686-pc-cygwin/5.4.0/include/omp.h') can't be found, so '-DUSE_OMP=0' to prevent a compilation error.
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
  export CFLAGS="$CFLAGS -D_DARWIN_C_SOURCE"
  local meson_options="-Denable_float=true \
-Dbuilt_in_models=true \
-Denable_tests=false \
-Denable_docs=false \
-Dc_args='-arch $host_arch -I${dependency_install_prefix}/include -isysroot ${SDKROOT} -D_DARWIN_C_SOURCE'"
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  do_ninja_and_ninja_install
  sed -i'.bak' "s/Libs: .*/& -lstdc++/" "$install_pkgconfig_dir/libvmaf.pc"
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
  find . -name "Makefile" -exec sed -i'.bak' 's/-force_cpusubtype_ALL//g' {} +
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libvpx            # config_options+= --enable-libvpx              # enable VP8 and VP9 de/encoding via libvpx [no]
build_libvpx() {
  local lib="libvpx"
  local repo="https://chromium.googlesource.com/webm/libvpx"
  local repo_ver="v1.15.2"
  local config="--prefix=$dependency_install_prefix \
--enable-static \
--disable-shared \
--disable-examples \
--disable-tools \
--disable-docs \
--disable-unit-tests \
--enable-vp9-highbitdepth \
--extra-cflags=-fno-asynchronous-unwind-tables"
  local saved_CPPFLAGS="$CPPFLAGS"
  local saved_CFLAGS="$CFLAGS"
  local saved_CXXFLAGS="$CXXFLAGS"
  local saved_LDFLAGS="$LDFLAGS"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  if [[ "$host_arch" == "x86_64" ]]; then
    export AS=nasm
  else
    export LD="$CC"
    export AS="$CC"
  fi
  export CPPFLAGS="$original_cppflags -arch $ios_arch -I${dependency_install_prefix}/include -DIOS"
  export CFLAGS="$original_cflags -arch $ios_arch -I${dependency_install_prefix}/include -isysroot $IOS_SYSROOT"
  export CXXFLAGS="$original_cxxflags -arch $ios_arch -I${dependency_install_prefix}/include -isysroot $IOS_SYSROOT"
  export LDFLAGS="$original_ldflags -arch $ios_arch -L${dependency_install_prefix}/lib -isysroot $IOS_SYSROOT"
  if isiossimulator; then
    local toolchain_files=("$src_dir/$lib/configure" "$src_dir/$lib/build/make/configure.sh")
    local toolchain_file=""
    for toolchain_file in "${toolchain_files[@]}"; do
      if ! grep -q 'arm64-iphonesimulator-gcc' "$toolchain_file"; then
        awk '
          !done && /arm64-darwin2[0-9]-gcc/ {
            print
            print "all_platforms=\"${all_platforms} arm64-iphonesimulator-gcc\""
            done=1
            next
          }
          { print }
        ' "$toolchain_file" > "${toolchain_file}.tmp" && mv -f "${toolchain_file}.tmp" "$toolchain_file"
      fi
    done
    sed -i '' 's/-miphoneos-version-min=\${IOS_VERSION_MIN}"$/-mios-simulator-version-min=${IOS_VERSION_MIN}"/g' "$src_dir/$lib/build/make/configure.sh"
    vpx_target="arm64-iphonesimulator-gcc"
  else
    vpx_target="arm64-darwin-gcc"
  fi
  sed -i'.bak' \
    -e "s/IOS_VERSION_MIN=\"8.0\"/IOS_VERSION_MIN=\"${MIN_IOS_VERSION}\"/g" \
    -e "s/IOS_VERSION_MIN=\"7.0\"/IOS_VERSION_MIN=\"${MIN_IOS_VERSION}\"/g" \
    "$src_dir/$lib/build/make/configure.sh"
  sed -i'.bak' \
    -e 's/[[:space:]]*check_add_cflags -fembed-bitcode/:/' \
    -e '/check_add_asflags -fembed-bitcode/d' \
    -e '/check_add_ldflags -fembed-bitcode/d' \
    "$src_dir/$lib/build/make/configure.sh"
  touch "no.autoreconf"
  do_configure "$config --target=$vpx_target" # fno for Error: invalid register for .seh_savexmm
  # disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  export CPPFLAGS="$saved_CPPFLAGS"
  export CFLAGS="$saved_CFLAGS"
  export CXXFLAGS="$saved_CXXFLAGS"
  export LDFLAGS="$saved_LDFLAGS"
  change_dir "$src_dir"
  set_toolchain_paths
}
# build_libvvenc          # config_options+= --enable-libvvenc            # enable H.266/VVC encoding via vvenc [no]
build_libvvenc() {
  local lib="libvvenc"
  local repo="https://github.com/fraunhoferhhi/vvenc"
  local repo_ver="v1.13.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  sed -i'.bak' -E "s/RUNTIME DESTINATION \\$\{RUNTIME_DEST\}/RUNTIME DESTINATION \\$\{RUNTIME_DEST\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$lib/cmake/modules/vvencInstall.cmake"
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release -DVVENC_ENABLE_LINK_TIME_OPT=OFF -DBUILD_SHARED_LIBS=0 -DVVENC_INSTALL_FULLFEATURE_APP=ON"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  # Fix corrupted pkg-config file generated by static libvvenc install
  sed -i'.bak' 's/interface_libs-NOTFOUND//g' "$install_pkgconfig_dir/libvvenc.pc"
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
  if [[ "$host_arch" == "x86_64" ]]; then
    export AS=nasm
  fi
  get_config_guess "$src_dir/$lib"
  get_config_sub "$src_dir/$lib"
  unset CFLAGS ASFLAGS LDFLAGS CPPFLAGS CXXFLAGS
  {
    copy_path "$PATCHDIR/build-x264.sh" "$src_dir/$lib/build-x264.sh" "-f"
    chmod +x "$src_dir/$lib/build-x264.sh"
    if isiossimulator; then
      IS_SIMULATOR=y ./build-x264.sh "$host_arch"
    else
      CFLAGS="$CFLAGS -mfpu=neon" ./build-x264.sh "$host_arch"
    fi
  } > >(redirect_output) 2>&1 || exit_message 1 "build_libx264: Failed to build x264"
  copy_path "$src_dir/$lib/thin-x264/$host_arch/lib/libx264.a" "$dependency_install_prefix/lib/libx264.a" "-f"
  change_dir "$src_dir"
  reset_allflags
  reset_cross_vars
}
# build_libx265           # config_options+= --enable-libx265             # enable HEVC encoding via x265 [no]
build_libx265() {
  local lib="libx265"
  local repo="https://bitbucket.org/multicoreware/x265_git"
  local repo_ver="4.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/12bit" 1
  # Fix for CMake > 3.0 dropping support for OLD policy behaviors
  sed -i'.bak' 's/cmake_policy(SET CMP0025 OLD)//g' "$src_dir/$lib/source/CMakeLists.txt"
  sed -i'.bak' 's/cmake_policy(SET CMP0054 OLD)//g' "$src_dir/$lib/source/CMakeLists.txt"
  local cmake_args="-DENABLE_ASSEMBLY=OFF \
-DHIGH_BIT_DEPTH=ON \
-DENABLE_CLI=OFF \
-DCMAKE_EXE_LINKER_FLAGS=\"-ldl\" \
-DCMAKE_SHARED_LINKER_FLAGS=\"-ldl\" \
-DCMAKE_CXX_STANDARD=11 \
-DCMAKE_CXX_STANDARD_REQUIRED=ON \
-DENABLE_PIC=ON \
-DENABLE_SHARED=OFF \
-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  if [[ "$host_arch" == "arm64" ]]; then
    cmake_args+=" -DCMAKE_SYSTEM_PROCESSOR=arm64 -DARM64=ON -DENABLE_NEON=ON -DCMAKE_C_FLAGS=\"-fPIC -include arm_neon.h\" -DCMAKE_CXX_FLAGS=\"-fPIC -include arm_neon.h\""
  else
    cmake_args+=" -DCMAKE_C_FLAGS=\"-fPIC -fvisibility=hidden\" -DCMAKE_CXX_FLAGS=\"-fPIC -fvisibility=hidden\" -DCMAKE_ASM_NASM_FLAGS=\"-DPIC\""
  fi
  local cmake_bit_args="-DMAIN12=ON -DEXPORT_C_API=OFF"
  do_cmake_from_build_dir "$src_dir/$lib/source" "$cmake_args $cmake_bit_args"
  disable_nonessential "$src_dir/$lib/12bit"
  do_make
  change_dir "$src_dir/$lib/10bit" 1
  cmake_bit_args="-DENABLE_HDR10_PLUS=ON -DEXPORT_C_API=OFF"
  do_cmake_from_build_dir "$src_dir/$lib/source" "$cmake_args $cmake_bit_args"
  disable_nonessential "$src_dir/$lib/10bit"
  do_make
  change_dir "$src_dir/$lib/8bit" 1
  cmake_bit_args="-DLINKED_10BIT=ON \
-DEXPORT_C_API=ON \
-DLINKED_12BIT=ON \
-DEXTRA_LINK_FLAGS=-L. \
-DEXTRA_LIB=\"../10bit/libx265.a;../12bit/libx265.a\""
  do_cmake_from_build_dir "$src_dir/$lib/source" "$cmake_args $cmake_bit_args"
  change_dir "$src_dir/$lib/8bit"
  disable_nonessential "$src_dir/$lib/8bit"
  do_make
  mv -f "libx265.a" "libx265_main.a"
  libtool -static -o libx265.a libx265_main.a ../10bit/libx265.a ../12bit/libx265.a > >(redirect_output) 2>&1
  do_make_install
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
  get_config_sub "$src_dir/$lib"
  get_config_guess "$src_dir/$lib"
  LC_ALL=C sed -i'.bak' 's/-lm -lmx/-lm/g' "$src_dir/$lib/configure"
  generic_configure "--host=arm64-apple-darwin \
--enable-static \
--disable-shared \
--enable-pic \
--with-pic \
--disable-asm \
--extra-cflags=\"-fPIC\""
  LC_ALL=C sed -i'.bak' 's/, tmp\[0\]);/, \&tmp[0]);/g' "$src_dir/$lib/common/i386/dct-c.c"
  LC_ALL=C sed -i'.bak' 's/, tmp\[1\]);/, \&tmp[1]);/g' "$src_dir/$lib/common/i386/dct-c.c"
  LC_ALL=C sed -i'.bak' 's/, tmp\[2\]);/, \&tmp[2]);/g' "$src_dir/$lib/common/i386/dct-c.c"
  LC_ALL=C sed -i'.bak' 's/, tmp\[3\]);/, \&tmp[3]);/g' "$src_dir/$lib/common/i386/dct-c.c"
  LC_ALL=C sed -i'.bak' -E 's/extern void predict_8x8c_p_core_mmxext.*/extern void predict_8x8c_p_core_mmxext\( uint8_t \*src, int i00, int b, int c \);/' common/i386/predict-c.c
  if [[ $host_arch == "x86_64" ]]; then
    # Remove unsupported -m amd64 flag if it exists
    LC_ALL=C sed -i'.bak' 's/-m amd64//g' "$src_dir/$lib/config.mak"
    # Nullify AS to prevent NASM execution
    LC_ALL=C sed -i'.bak' 's/^AS=.*/AS=/g' "$src_dir/$lib/config.mak"
    # Remove assembly files from the source list to prevent them being built as dependencies
    LC_ALL=C sed -i'.bak' 's/[^ ]*\.asm//g' "$src_dir/$lib/config.mak"
    export CFLAGS="$CFLAGS -Wno-error=strict-prototypes"
    export AS=
  fi
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_allflags
  set_toolchain_paths
}
# build_libxavs2          # config_options+= --enable-libxavs2            # enable AVS2 encoding via xavs2 [no]
build_libxavs2() {
  local lib="libxavs2"
  local repo="https://github.com/pkuvcl/xavs2"
  local repo_ver="1.4"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build/linux"
  get_config_sub "$src_dir/$lib/build/linux"
  get_config_guess "$src_dir/$lib/build/linux"
  LC_ALL=C sed -i'.bak' 's/-lm -lmx/-lm/g' "$src_dir/$lib/build/linux/configure"
  generic_configure "--host=arm64-apple-darwin \
--disable-cli \
--enable-static \
--disable-shared \
--enable-pic \
--with-pic \
--disable-asm \
--extra-cflags=\"$CFLAGS -Wno-error=incompatible-pointer-types\""
  if [[ $host_arch == "x86_64" ]]; then
    export AS=nasm
  fi
  sed -i'.bak' 's/^SYS_ARCH=AARCH64/SYS_ARCH=/' "$src_dir/$lib/build/linux/config.mak"
  sed -i'.bak' -E 's/\$\(AR\)\$@/\$\(AR\) rc \$@/g' Makefile
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  sed -i'.bak' "s/Version:.*/Version: ${repo_ver}.0/g" "$dependency_install_prefix"/lib/pkgconfig/xavs2.pc
  change_dir "$src_dir"
  set_toolchain_paths
}
# build_libxevd           # config_options+= --enable-libxevd             # enable EVC decoding via libxevd [no]
build_libxevd() {
  local lib="libxevd"
  local repo="https://github.com/mpeg5/xevd"
  local repo_ver="v0.5.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  # needs a version.txt file but git repo doesnt have one for some reason
  if [[ -d .git && ! -f "$src_dir/$lib/version.txt" ]]; then
      # Get version from git tags
      VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.5.0")
  else
      # Use default version
      VERSION="v0.5.0"
  fi
cat >"$src_dir/$lib/version.txt" <<EOF
$VERSION
EOF
  local cmake_args="-DBUILD_SHARED_LIBS=OFF \
-DENABLE_SHARED=OFF \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_C_FLAGS=\"-Wno-unknown-warning-option -Wno-error -Wno-typedef-redefinition -Wno-header-guard -I$src_dir/$lib/src_base -I$src_dir/$lib/src_base/neon\""
  if [[ "$host_arch" == "arm64" ]]; then
    # Use TRUE instead of ON to match: if("${ARM}" STREQUAL "TRUE")
    cmake_args+=" -DARM=TRUE -DSET_PROF=MAIN"

    # Remove the -static linker flag that breaks iOS builds
    sed -i'.bak' 's/set(CMAKE_EXE_LINKER_FLAGS "-static")//g' "$src_dir/$lib/CMakeLists.txt"
  fi
  sed -i '.bak' 's/_XEVD_DBK_NOEN_H_/_XEVD_DBK_NEON_H_/g' "$src_dir/$lib/src_base/neon/xevd_dbk_neon.h"
  sed -i '.bak' 's/-Werror//g' "$src_dir/$lib/CMakeLists.txt"
  sed -i '.bak' 's/add_subdirectory(app)//g' "$src_dir/$lib/CMakeLists.txt"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_args"
  disable_nonessential "$src_dir/$lib/build"
  # do_make "xevd"
  do_make_and_make_install
  # XXX replace version if repo_ver is changed
  sed -i'.bak' "s/Version:.*/Version: 1.5.0/g" "$src_dir/$lib/build/xevd.pc"
  # manually install static library only
  { cp -fv "$src_dir/$lib/build/src_main/libxevd.a" "$dependency_install_prefix/lib/" >>"$LOG_FILE"; } || exit_message 1 "build_libxevd: could not install $lib static lib"
  { cp -fv "$src_dir/$lib/inc/xevd.h" "$dependency_install_prefix/include/" >>"$LOG_FILE"; } || exit_message 1 "build_libxevd: could not install $lib headers"
  { cp -fv "$src_dir/$lib/build/xevd_exports.h" "$dependency_install_prefix/include/" >>"$LOG_FILE"; } || exit_message 1 "build_libxevd: could not install $lib headers"
  { cp -fv "$src_dir/$lib/build/xevd.pc" "$install_pkgconfig_dir/" >>"$LOG_FILE"; } || exit_message 1 "build_libxevd: could not install $lib pkg-config"
  change_dir "$src_dir"
}
# build_libxeve           # config_options+= --enable-libxeve             # enable EVC encoding via libxeve [no]
build_libxeve() {
  local lib="libxeve"
  # https://github.com/mpeg5/xeve
  local repo="https://github.com/mpeg5/xeve"
  local repo_ver="v0.5.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  # needs a version.txt file but git repo doesnt have one for some reason
  if [[ -d .git && ! -f "$src_dir/$lib/version.txt" ]]; then
      # Get version from git tags
      VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.5.1")
  else
      # Use default version
      VERSION="0.5.1"
  fi
cat >"$src_dir/$lib/version.txt" <<EOF
$VERSION
EOF
  local cmake_args="-DBUILD_SHARED_LIBS=OFF \
-DENABLE_SHARED=OFF \
-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_C_FLAGS=\"-Wno-unknown-warning-option -Wno-error -Wno-typedef-redefinition -Wno-header-guard -I$src_dir/$lib/src_base -I$src_dir/$lib/src_base/neon\""
  if [[ "$host_arch" == "arm64" ]]; then
    # Use TRUE instead of ON to match: if("${ARM}" STREQUAL "TRUE")
    cmake_args+=" -DARM=TRUE -DSET_PROF=MAIN"

    # Remove the -static linker flag that breaks iOS builds
    sed -i'.bak' 's/set(CMAKE_EXE_LINKER_FLAGS "-static")//g' "$src_dir/$lib/CMakeLists.txt"
    wget https://raw.githubusercontent.com/DLTcollab/sse2neon/master/sse2neon.h -O "$src_dir/$lib/src_base/neon/sse2neon.h" > >(redirect_output) 2>&1
  fi
  sed -i '.bak' 's/-Werror//g' "$src_dir/$lib/CMakeLists.txt"
  sed -i '.bak' 's/add_subdirectory(app)//g' "$src_dir/$lib/CMakeLists.txt"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_args"
  disable_nonessential "$src_dir/$lib/build"
  # do_make "xevd"
  do_make_and_make_install
  # XXX replace version if repo_ver is changed
  sed -i'.bak' "s/Version:.*/Version: 0.5.1/g" "$src_dir/$lib/build/xeve.pc"
  # manually install static library only
  { cp -fv "$src_dir/$lib/build/src_main/libxeve.a" "$dependency_install_prefix/lib/" >>"$LOG_FILE"; } || exit_message 1 "build_libxeve: could not install $lib static lib"
  { cp -fv "$src_dir/$lib/inc/xeve.h" "$dependency_install_prefix/include/" >>"$LOG_FILE"; } || exit_message 1 "build_libxeve: could not install $lib headers"
  { cp -fv "$src_dir/$lib/build/xeve_exports.h" "$dependency_install_prefix/include/" >>"$LOG_FILE"; } || exit_message 1 "build_libxeve: could not install $lib headers"
  { cp -fv "$src_dir/$lib/build/xeve.pc" "$install_pkgconfig_dir/" >>"$LOG_FILE"; } || exit_message 1 "build_libxeve: could not install $lib pkg-config"
  change_dir "$src_dir"
}
# build_libxml2           # config_options+= --enable-libxml2             # enable XML parsing using the C library libxml2, needed for dash and imf demuxing support [no]
build_libxml2() {
  local lib="libxml2"
  local repo="https://gitlab.gnome.org/GNOME/libxml2"
  local repo_ver="v2.10.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  do_autogen
  touch "no.autoreconf"
  generic_configure "--with-ftp=no --with-http=no --with-python=no --with-iconv" # using configure. meson doesnt work
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
  generic_configure "--enable-pic --with-pic --enable-static --disable-shared"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libxvid           # config_options+= --enable-libxvid             # enable Xvid encoding via xvidcore, native MPEG-4/Xvid encoder exists [no]
build_libxvid() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No libxvid library to compile. Library built into OS." >>"$LOG_FILE"
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
  do_autogen
  touch "no.autoreconf"
  generic_configure "--enable-static \
--disable-shared \
--with-pic"
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
  change_dir "$src_dir/$lib/build" 1
  local cmake_args="-DBUILD_STATIC=ON \
  -DBUILD_SHARED=OFF \
  -DZMQ_BUILD_TESTS=OFF \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DWITH_PERF_TOOL=OFF"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_args"
  # change_dir "$src_dir/$lib"
#   generic_configure "--enable-static \
# --disable-shared \
# --without-docs \
# --without-libsodium \
# --disable-libunwind \
# --disable-perf \
# --disable-werror \
# --disable-curve-keygen \
# --disable-curve"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
}
# build_libzvbi           # config_options+= --enable-libzvbi             # enable teletext support via libzvbi [no]
build_libzvbi() {
  local lib="libzvbi"
  local repo="https://github.com/zapping-vbi/zvbi"
  local repo_ver="v0.2.44"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  export LIBS="-lpng -lz -liconv -lm"
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
--with-libiconv-prefix=\"$dependency_install_prefix\" \
ac_cv_func_realloc_0_nonnull=yes \
ac_cv_func_malloc_0_nonnull=yes"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_ldflags
  unset LIBS
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
  local meson_options="-Dtests=disabled \
-Dbenchmarks=disabled \
-Dc_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -isysroot ${SDKROOT} -framework CoreFoundation -framework Foundation\" \
-Dtests_cpp=disabled \
-Ddocs=disabled"
  generic_meson "$meson_options"
  perl -i'.bak' -0pe \
  's/#ifdef __APPLE__\n  const int rc = dst_fd >= 0 \? fcntl\(dst_fd, F_FULLFSYNC\) : 0;\n#else\n  const int rc = dst_fd >= 0 \? fdatasync\(dst_fd\) : 0;/#if defined(__APPLE__) \&\& defined(F_FULLFSYNC)\n  const int rc = dst_fd >= 0 ? fcntl(dst_fd, F_FULLFSYNC) : 0;\n#elif defined(__APPLE__)\n  const int rc = dst_fd >= 0 ? fsync(dst_fd) : 0;\n#else\n  const int rc = dst_fd >= 0 ? fdatasync(dst_fd) : 0;/' \
  "$src_dir/$lib/src/posix/filesystem_posix.c"
  perl -i'.bak' -0pe \
  's/(#include <zix\/filesystem\.h>)/#ifdef __APPLE__\nchar* mkdtemp(char*);\n#endif\n$1/' \
  "$src_dir/$lib/src/posix/filesystem_posix.c"
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
  find "$install_pkgconfig_dir" -type f -name "*.pc" -exec sed -i'.bak' \
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
-DALSOFT_STATIC_LIBGCC=OFF \
-DALSOFT_STATIC_STDCXX=OFF \
-DLIBTYPE=STATIC \
-DALSOFT_UTILS=OFF \
-DALSOFT_EXAMPLES=OFF \
-DALSOFT_TESTS=OFF \
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
  sed -i'.bak' "s|@PKGCONFIG_PREFIX@|${dependency_install_prefix}|g" "$install_pkgconfig_dir/OpenCL-Headers.pc"
  sed -i'.bak' "s|@OPENCL_INCLUDEDIR_PC@|\${prefix}/include|g" "$install_pkgconfig_dir/OpenCL-Headers.pc"
  ln -sf "$dependency_install_prefix/include/CL" "$dependency_install_prefix/include/OpenCL"
  local lib="OpenCL-ICD-Loader"
  local repo="https://github.com/KhronosGroup/OpenCL-ICD-Loader"
  local repo_ver="v2025.07.22"
  change_dir "$src_dir/$parentlib"
  do_git_checkout "$repo" "$lib" "$repo_ver"
  change_dir "$src_dir/$parentlib/$lib/build" 1
  sed -i '' '/RUNTIME$/{N;s/RUNTIME\n[[:space:]]*/RUNTIME /;}' "$src_dir/$parentlib/$lib/CMakeLists.txt"
  sed -i'.bak' -E "s/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}/RUNTIME DESTINATION \\$\{CMAKE_INSTALL_BINDIR\}\\
BUNDLE DESTINATION \\$\{CMAKE_SOURCE_DIR\}/g" "$src_dir/$parentlib/$lib/CMakeLists.txt"
  local cmake_params="-DCMAKE_INSTALL_PREFIX=${dependency_install_prefix} \
-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DBUILD_TESTING=OFF \
-DOPENCL_ICD_LOADER_BUILD_TESTING=OFF \
-DOPENCL_ICD_LOADER_HEADERS_DIR=${dependency_install_prefix}/include"
  do_cmake_from_build_dir "$src_dir/$parentlib/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$parentlib/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_glew() {
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No glew library to compile." >>"$LOG_FILE"
}
build_glfw() {
  echo "INFO: Not available on iOS build" >>"$LOG_FILE"
  echo "INFO: No glew library to compile." >>"$LOG_FILE"
}
# build_opengl            # config_options+= --enable-opengl              # enable OpenGL rendering [no]
build_opengl() {
  local lib="opengl"
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
  unset CROSS_COMPILE
  local host="ios64-xcrun"
  do_configure "$host --release --prefix=$dependency_install_prefix --openssldir=$dependency_install_prefix/ssl --libdir=lib no-shared no-tests no-docs no-demos no-legacy"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  change_dir "$src_dir"
  reset_cross_vars
}
build_lapack() {
  install_missing_packages gfortran
  local lib="lapack"
  local repo="https://github.com/Reference-LAPACK/lapack"
  local repo_ver="v3.12.1"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  do_cmake_from_build_dir "$src_dir/$lib" "-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_bison() {
  if [[ "$VENDOR" == "redhat" ]]; then
    local lib="bison"
    local repo="https://github.com/akimd/bison"
    local repo_ver="v3.8.2"
    local min_ver="3.8.0"
    if command -v $lib &>/dev/null; then
      local installed_ver="$("$lib" --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
    else
      local installed_ver=0
    fi
    if [ "$(printf '%s\n' "$min_ver" "$installed_ver" | sort -V | head -n 1)" = "$installed_ver" ] && [ "$installed_ver" != "$min_ver" ]; then
      echo "INFO: $lib version mismatch installed: $installed_ver vs required: $min_ver. Building from source."
      change_dir "$src_dir"
      do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
      change_dir "$src_dir/$lib"
      generic_configure "--enable-static --disable-shared --enable-pic --with-pic"
      disable_nonessential "$src_dir/$lib"
      do_make_and_make_install
      change_dir "$src_dir"
    fi
  fi
}
build_swig() {
  local lib="swig"
  local repo="https://sourceforge.net/projects/swig/files/swig/swig-2.0.12/swig-2.0.12.tar.gz/download"
  local repo_ver="v2.0.12"
  export CXXFLAGS="$CXXFLAGS -DSWIG_LIB='\"${dependency_install_prefix}/share/swig\"' "
  change_dir "$src_dir"
  download_and_unpack_file "$repo" "$lib"
  change_dir "$src_dir/$lib"
  touch "no.autoreconf"
  get_config_sub "$src_dir/$lib/Tools/config"
  touch "no.autogen"
  do_configure "--host=$host_target \
--prefix=$dependency_install_prefix \
--libdir=$dependency_install_prefix/lib \
--without-pcre \
--enable-static --disable-shared --enable-pic --with-pic"
  do_make_and_make_install
  reset_cxxflags
}
build_sphinxbase() {
  local lib="sphinxbase"
  local repo="https://github.com/cmusphinx/sphinxbase"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib"
  change_dir "$src_dir/$lib"
  export CPPFLAGS="$CPPFLAGS -I$dependency_install_prefix/include"
  export LDFLAGS="$LDFLAGS -L$dependency_install_prefix/lib -lopenal -lc++ -framework CoreAudio -framework AudioToolbox -framework CoreFoundation"
  touch "no.autogen"
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\" \
--enable-static \
--disable-shared \
--without-python \
--without-lapack"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  reset_allflags
  change_dir "$src_dir"
}
build_gstreamer() {
  activate_meson
  local lib="gstreamer"
  local repo="https://gitlab.freedesktop.org/gstreamer/gstreamer"
  local repo_ver="1.26.10"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib"
  export LDFLAGS="$LDFLAGS -framework CoreFoundation -framework Foundation"
  local meson_options="-Ddoc=disabled \
-Dexamples=disabled \
-Dtests=disabled \
-Dtools=disabled \
-Dbenchmarks=disabled \
-Dgst_debug=false \
-Dnls=disabled \
-Dcpp_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -isysroot ${SDKROOT} -lresolv -framework CoreFoundation -framework Foundation -framework ObjectiveC\" \
-Dc_link_args=\"-arch $host_arch -L${dependency_install_prefix}/lib -isysroot ${SDKROOT} -lresolv -framework CoreFoundation -framework Foundation -lobjc -llzma\""
  generic_meson "$meson_options"
  disable_nonessential "$src_dir/$lib"
  sed -i'.bak' 's/-Wl,--export-dynamic//g' "$src_dir/$lib/build/build.ninja"
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
  install_missing_packages python3-dev
  local lib="pocketsphinx"
  local repo="https://svn.code.sf.net/p/cmusphinx/code/trunk/pocketsphinx"
  local repo_ver="r13291"
  change_dir "$src_dir"
  do_svn_checkout "$repo" "$src_dir/$lib"
  change_dir "$src_dir/$lib"
  export CPPFLAGS="$CPPFLAGS -I$dependency_install_prefix/include"
  export LDFLAGS="$LDFLAGS -L$dependency_install_prefix/lib -lopenal -lc++ -framework CoreAudio -framework AudioToolbox -framework CoreFoundation"
  touch "no.autogen"
  local ffi_host="$host_target"
  if isiossimulator; then
    ffi_host="${host_arch}-apple-darwin"
  fi
  generic_configure "--host=$ffi_host --with-sysroot=\"$IOS_SYSROOT\" \
--enable-static \
--disable-shared \
--without-python \
--without-lapack"
  disable_nonessential "$src_dir/$lib"
  do_make_and_make_install
  reset_allflags
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
  local cython_shim_dir="$work_dir/bin"
local cython_venv_dir="$work_dir/cython-venv"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib"
  install_missing_packages python3-dev cython
  if ! python3 - <<'PY' >/dev/null 2>&1
import Cython
PY
  then
    rm -rf "$cython_venv_dir"
    python3 -m venv "$cython_venv_dir" > >(redirect_output) 2>&1 || exit_message 1 "build_vapoursynth: could not create cython venv"
    "$cython_venv_dir/bin/python" -m pip install --upgrade pip > >(redirect_output) 2>&1 || exit_message 1 "build_vapoursynth: could not upgrade pip in cython venv"
    "$cython_venv_dir/bin/python" -m pip install cython > >(redirect_output) 2>&1 || exit_message 1 "build_vapoursynth: could not install cython in venv"
  fi
  create_dir "$cython_shim_dir"
  cat > "$cython_shim_dir/cython" <<'EOF'
#!/usr/bin/env bash
if [[ -x "__CYTHON_VENV__/bin/python" ]]; then
  exec "__CYTHON_VENV__/bin/python" -m cython "$@"
fi
exec python3 -m cython "$@"
EOF
  cat > "$cython_shim_dir/cython3" <<'EOF'
#!/usr/bin/env bash
if [[ -x "__CYTHON_VENV__/bin/python" ]]; then
  exec "__CYTHON_VENV__/bin/python" -m cython "$@"
fi
exec python3 -m cython "$@"
EOF
  sed -i'.bak' "s|__CYTHON_VENV__|$cython_venv_dir|g" "$cython_shim_dir/cython" "$cython_shim_dir/cython3"
  chmod +x "$cython_shim_dir/cython" "$cython_shim_dir/cython3"
  prepend_path_once "$cython_shim_dir"
  generic_meson "-Denable_vspipe=false -Denable_python_module=false"
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
build_omp() {
  local lib="omp"
  local repo="https://github.com/llvm/llvm-project"
  local repo_ver="llvmorg-22.1.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/openmp"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF \
-DLIBOMP_INSTALL_ALIASES=OFF \
-DLIBOMP_ENABLE_SHARED=OFF \
-DOPENMP_ENABLE_LIBOMPTARGET=OFF"
  generic_cmake "$cmake_params"
  disable_nonessential "$src_dir/$lib/openmp"
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
-DGGML_AVX2=ON \
-DGGML_FMA=ON \
-DGGML_METAL=ON \
-DGGML_ACCELERATE=ON \
-DGGML_F16C=ON"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  while IFS= read -r -d '' file; do
    add_libs_to_pkg -t="$file" -l="-lwhisper -lggml -lggml-base -lggml-cpu -lggml-blas -lggml-metal -lomp -lpthread"
    sed -i'.bak' 's/-lwhisper/-lwhisper -framework Accelerate -framework Metal -framework MetalKit -framework Foundation /g' "$file"
  done < <(find "$install_pkgconfig_dir" -name "whisper*.pc" -print0)
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
build_libsvtjpegxs() {
  if [[ "$host_arch" != "x86_64" ]]; then
    echo -e "\nWARNING: libsvtjpegxs is only supported on x86_64, skipping..."
    return 0
  fi
  local lib="libsvtjpegxs"
  local repo="https://github.com/OpenVisualCloud/SVT-JPEG-XS"
  local repo_ver="v0.9.0"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_APPS=OFF \
  -DBUILD_TESTING=OFF"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libopencolorio() {
  local lib="libopencolorio"
  local repo="https://github.com/AcademySoftwareFoundation/OpenColorIO"
  local repo_ver="v2.5.2"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  export LDFLAGS="$LDFLAGS"
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DOCIO_BUILD_APPS=OFF \
  -DOCIO_BUILD_TESTS=OFF \
  -DOCIO_BUILD_GPU_TESTS=OFF \
  -DOCIO_USE_HEADLESS=ON \
  -DCMAKE_C_FLAGS=\"-DOCIO_HEADLESS_ENABLED\" \
  -DCMAKE_CXX_FLAGS=\"-DOCIO_HEADLESS_ENABLED\" \
  -DOCIO_BUILD_PYTHON=OFF \
  -DOCIO_INSTALL_EXT_PACKAGES=\"MISSING\""
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
build_libmpeghdec() {
  local lib="libmpeghdec"
  local repo="https://github.com/Fraunhofer-IIS/mpeghdec"
  local repo_ver="r3.0.3"
  change_dir "$src_dir"
  do_git_checkout "$repo" "$src_dir/$lib" "$repo_ver"
  change_dir "$src_dir/$lib/build" 1
  local cmake_params="-DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -Dmpeghdec_BUILD_BINARIES=OFF"
  do_cmake_from_build_dir "$src_dir/$lib" "$cmake_params"
  disable_nonessential "$src_dir/$lib/build"
  do_make_and_make_install
  change_dir "$src_dir"
}
#region-------------------- non-gpl hardware features -------------------------
# build_cuda_llvm         # config_options+= --disable-cuda-llvm          # disable CUDA compilation using clang [autodetect]
build_cuda_llvm() {
  echo "INFO: Only available on Windows and Linux build" >>"$LOG_FILE"
  echo "INFO: No cuda-llvm library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_cuvid             # config_options+= --disable-cuvid              # disable Nvidia CUVID support [autodetect]
build_cuvid() {
  echo "WARNING: This is a non-gpl library." >>"$LOG_FILE"  # run_valid_function "build_nvenc" 1
}
# build_ffnvcodec         # config_options+= --disable-ffnvcodec          # disable dynamically linked Nvidia code [autodetect]
build_ffnvcodec() {
  echo "WARNING: This is a non-gpl library." >>"$LOG_FILE"  # run_valid_function "build_nvenc" 1
}
# build_nvdec             # config_options+= --disable-nvdec              # disable Nvidia video decoding acceleration (via hwaccel) [autodetect]
build_nvdec() {
  echo "WARNING: This is a non-gpl library." >>"$LOG_FILE"  # run_valid_function "build_nvenc" 1
}
# build_nvenc             # config_options+= --disable-nvenc              # disable Nvidia video encoding code [autodetect]
build_nvenc() {
  echo "INFO: Only available on Windows and Linux build" >>"$LOG_FILE"
  echo "INFO: No nvenc library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_vdpau             # config_options+= --disable-vdpau              # disable Nvidia Video Decode and Presentation API for Unix code [autodetect]
build_vdpau() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No vdpau library to compile. Library built into OS." >>"$LOG_FILE"
}
build_libnvvm() {
  echo "INFO: Only available on Windows and Linux build" >>"$LOG_FILE"
  echo "INFO: No libnvvm library to compile. Library built into OS." >>"$LOG_FILE"
}
build_cuda_crt() {
  echo "INFO: Only available on Windows and Linux build" >>"$LOG_FILE"
  echo "INFO: No cuda-crt library to compile. Library built into OS." >>"$LOG_FILE"
}
build_cuda_cudart() {
  echo "INFO: Only available on Windows and Linux build" >>"$LOG_FILE"
  echo "INFO: No cuda-cudart library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_cuda_nvcc         # config_options+= --enable-cuda-nvcc           # enable Nvidia CUDA compiler [no]
build_cuda_nvcc() {
  echo "INFO: Only available on Windows and Linux build" >>"$LOG_FILE"
  echo "INFO: No cuda-nvcc library to compile. Library built into OS." >>"$LOG_FILE"
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
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No mmal library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_omx               # config_options+= --enable-omx                 # enable OpenMAX IL code [no]
build_omx() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No omx library to compile. Library built into OS." >>"$LOG_FILE"
}
# build_omx_rpi           # config_options+= --disable-omx-rpi            # enable OpenMAX IL code for Raspberry Pi [no]
build_omx_rpi() {
  echo "INFO: Only available on Linux build" >>"$LOG_FILE"
  echo "INFO: No omx-rpi library to compile. Library built into OS." >>"$LOG_FILE"
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
