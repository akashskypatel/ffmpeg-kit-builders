#!/bin/bash

#echo "${SCRIPTDIR}/variable.sh"
#echo "${SCRIPTDIR}/function.sh"

source "${SCRIPTDIR}/variable.sh"
source "${SCRIPTDIR}/function.sh"

find_all_build_exes() {
  local found=""
# NB that we're currently in the prebuilt dir...
  for file in $(find . -name ffmpeg.exe) $(find . -name ffmpeg_g.exe) $(find . -name ffplay.exe) $(find . -name ffmpeg) $(find . -name ffplay) $(find . -name ffprobe) $(find . -name MP4Box.exe) $(find . -name mplayer.exe) $(find . -name mencoder.exe) $(find . -name avconv.exe) $(find . -name avprobe.exe) $(find . -name x264.exe) $(find . -name writeavidmxf.exe) $(find . -name writeaviddv50.exe) $(find . -name rtmpdump.exe) $(find . -name x265.exe) $(find . -name ismindex.exe) $(find . -name dvbtee.exe) $(find . -name boxdumper.exe) $(find . -name muxer.exe ) $(find . -name remuxer.exe) $(find . -name timelineeditor.exe) $(find . -name lwcolor.auc) $(find . -name lwdumper.auf) $(find . -name lwinput.aui) $(find . -name lwmuxer.auf) $(find . -name vslsmashsource.dll); do
    found="$found $(readlink -f "$file")"
  done

  # bash recursive glob fails here again?
  for file in $(find . -name vlc.exe | grep -- -); do
    found="$found $(readlink -f "$file")"
  done
  echo "$found" # pseudo return value...
}

check_native() {
  echo "Building ffmpeg dependency libraries..."
  if [[ $compiler_flavors != "native" ]]; then # build some stuff that don't build native...
    build_dlfcn
    build_libxavs
  fi
}

check_host_target() {
  if [[ $host_target != 'i686-w64-mingw32' ]]; then
    build_libxavs2
  fi
}

check_gpulibs() {
  if [[ $build_amd_amf = y ]]; then
    build_amd_amf_headers
  fi
  if [[ $compiler_flavors != "native" ]]; then
    build_libvpl
  fi
}

check_build_libsndfile() {
  build_libsndfile "install-libgsm"
}

check_svt() {
  if [[ "$bits_target" != "32" ]]; then
    if [[ $build_svt_hevc = y ]]; then
      build_svt-hevc
    fi
    if [[ $build_svt_vp9 = y ]]; then
      build_svt-vp9
    fi
    build_svt-av1
  fi
}

check_audiotoolbox() {
  # if [[ "$non_free" = "y" ]]; then
  #   build_fdk-aac # Uses dlfcn.
	# if [[ $OSTYPE != darwin* ]]; then
  #     build_AudioToolboxWrapper # This wrapper library enables FFmpeg to use AudioToolbox codecs on Windows, with DLLs shipped with iTunes.
	# fi
  if [[ $compiler_flavors != "native" ]]; then
    build_libdecklink # Error finding rpc.h in native builds even if it's available
  fi
  #fi
}

check_libaribcaption() {
  if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then 
    # Disable libaribcatption on old versions
    build_libaribcaption
  fi
}

check_libtensorflow() {
  if [[ $compiler_flavors != "native" ]]; then
    build_libtensorflow # requires tensorflow.dll
  fi	
}

check_vulkan_libplacebo() {
  if [[ $OSTYPE != darwin* ]]; then
    build_vulkan
    build_libplacebo
  fi
}

build_ffmpeg_dependencies_only() {
  step=$1
  if [[ -n "$step" ]]; then
    if declare -F "$step" > /dev/null; then
      echo "Executing step: $step"
      "$step"  # Execute the function
    else
      echo "Error: Function '$step' not found."
      return 1  # Indicate an error
    fi
  else
    echo "Error: Step argument is missing."
    return 1  # Indicate an error
  fi
}

build_ffmpeg_dependencies() {
  echo -e "DEBUG: Building dependencies\n" 1>>$LOG_FILE 2>&1
  if [[ $build_dependencies = "n" && $build_dependencies_only != "y" ]]; then
    echo "Skip build ffmpeg dependency libraries..."
    return
  fi

  echo "Building ffmpeg dependency libraries..."
  if [[ $compiler_flavors != "native" ]]; then # build some stuff that don't build native...
    build_dlfcn
    build_libxavs
  fi

  build_libdavs2
  
  if [[ $host_target != 'i686-w64-mingw32' ]]; then
    build_libxavs2
  fi

  build_meson_cross
  build_mingw_std_threads
  build_zlib # Zlib in FFmpeg is autodetected.
  build_libcaca # Uses zlib and dlfcn (on windows).
  build_bzip2 # Bzlib (bzip2) in FFmpeg is autodetected.
  build_liblzma # Lzma in FFmpeg is autodetected. Uses dlfcn.
  build_iconv # Iconv in FFmpeg is autodetected. Uses dlfcn.
  build_sdl2 # Sdl2 in FFmpeg is autodetected. Needed to build FFPlay. Uses iconv and dlfcn.
  
  if [[ $build_amd_amf = y ]]; then
    build_amd_amf_headers
  fi
  if [[ $compiler_flavors != "native" ]]; then
    build_libvpl
  fi

  build_nv_headers
  build_libzimg # Uses dlfcn.
  build_libopenjpeg
  build_glew
  build_glfw
  #build_libjpeg_turbo # mplayer can use this, VLC qt might need it? [replaces libjpeg] (ffmpeg seems to not need it so commented out here)
  build_libpng # Needs zlib >= 1.0.4. Uses dlfcn.
  build_libwebp # Uses dlfcn.
  build_libxml2 # Uses zlib, liblzma, iconv and dlfcn
  build_brotli
  build_harfbuzz # Uses freetype zlib, bzip2, brotli and libpng.
  build_libvmaf
  build_fontconfig # uses libpng bzip2 libxml2 and zlib
  build_gmp # For rtmp support configure FFmpeg with '--enable-gmp'. Uses dlfcn.
  #build_librtmfp # mainline ffmpeg doesn't use it yet
  build_libnettle # Needs gmp >= 3.0. Uses dlfcn. GCC 15 does not yet detect gmp properly yet
  build_unistring
  build_libidn2 # needs iconv and unistring
  build_zstd
  build_gnutls # Needs nettle >= 3.1, hogweed (nettle) >= 3.1. Uses libidn2, unistring, zlib, and dlfcn.
  build_curl
  #if [[ "$non_free" = "y" ]]; then
  #  build_openssl-1.0.2 # Nonfree alternative to GnuTLS. 'build_openssl-1.0.2 "dllonly"' to build shared libraries only.
  #  build_openssl-1.1.1 # Nonfree alternative to GnuTLS. Can't be used with LibRTMP. 'build_openssl-1.1.1 "dllonly"' to build shared libraries only.
  #fi
  build_libogg # Uses dlfcn.
  build_libvorbis # Needs libogg >= 1.0. Uses dlfcn.
  build_libopus # Uses dlfcn.
  build_libspeexdsp # Needs libogg for examples. Uses dlfcn.
  build_libspeex # Uses libspeexdsp and dlfcn.
  build_libtheora # Needs libogg >= 1.1. Needs libvorbis >= 1.0.1, sdl and libpng for test, programs and examples [disabled]. Uses dlfcn.
  
  build_libsndfile "install-libgsm" # Needs libogg >= 1.1.3 and libvorbis >= 1.2.3 for external support [disabled]. Uses dlfcn. 'build_libsndfile "install-libgsm"' to install the included LibGSM 6.10.
  
  build_mpg123
  build_lame # Uses dlfcn, mpg123
  build_twolame # Uses libsndfile >= 1.0.0 and dlfcn.
  build_openmpt
  build_libopencore # Uses dlfcn.
  build_libilbc # Uses dlfcn.
  build_libmodplug # Uses dlfcn.
  build_libgme
  build_libbluray # Needs libxml >= 2.6, freetype, fontconfig. Uses dlfcn.
  build_libbs2b # Needs libsndfile. Uses dlfcn.
  build_libsoxr
  build_libflite
  build_libsnappy # Uses zlib (only for unittests [disabled]) and dlfcn.
  build_vamp_plugin # Needs libsndfile for 'vamp-simple-host.exe' [disabled].
  build_fftw # Uses dlfcn.
  build_chromaprint
  build_libsamplerate # Needs libsndfile >= 1.0.6 and fftw >= 0.15.0 for tests. Uses dlfcn.
  build_librubberband # Needs libsamplerate, libsndfile, fftw and vamp_plugin. 'configure' will fail otherwise. Eventhough librubberband doesn't necessarily need them (libsndfile only for 'rubberband.exe' and vamp_plugin only for "Vamp audio analysis plugin"). How to use the bundled libraries '-DUSE_SPEEX' and '-DUSE_KISSFFT'?
  build_frei0r # Needs dlfcn. could use opencv...
  
  if [[ "$bits_target" != "32" ]]; then
    if [[ $build_svt_hevc = y ]]; then
      build_svt-hevc
    fi
    if [[ $build_svt_vp9 = y ]]; then
      build_svt-vp9
    fi
    build_svt-av1
  fi

  build_vidstab
  #build_facebooktransform360 # needs modified ffmpeg to use it so not typically useful
  build_libmysofa # Needed for FFmpeg's SOFAlizer filter (https://ffmpeg.org/ffmpeg-filters.html#sofalizer). Uses dlfcn.
  
  # if [[ "$non_free" = "y" ]]; then
  #   build_fdk-aac # Uses dlfcn.
	# if [[ $OSTYPE != darwin* ]]; then
  #     build_AudioToolboxWrapper # This wrapper library enables FFmpeg to use AudioToolbox codecs on Windows, with DLLs shipped with iTunes.
	# fi
  if [[ $compiler_flavors != "native" ]]; then
    build_libdecklink # Error finding rpc.h in native builds even if it's available
  fi
  #fi

  build_zvbi # Uses iconv, libpng and dlfcn.
  build_fribidi # Uses dlfcn.
  build_libass # Needs freetype >= 9.10.3 (see https://bugs.launchpad.net/ubuntu/+source/freetype1/+bug/78573 o_O) and fribidi >= 0.19.0. Uses fontconfig >= 2.10.92, iconv and dlfcn.

  build_libxvid # FFmpeg now has native support, but libxvid still provides a better image.
  build_libsrt # requires gnutls, mingw-std-threads

  if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then 
    # Disable libaribcatption on old versions
    build_libaribcaption
  fi

  build_libaribb24
  build_libtesseract
  build_lensfun  # requires png, zlib, iconv

  if [[ $compiler_flavors != "native" ]]; then
    build_libtensorflow # requires tensorflow.dll
  fi	

  build_libvpx
  build_libx265
  build_libopenh264
  build_libaom
  build_dav1d

  if [[ $OSTYPE != darwin* ]]; then
    build_vulkan
    build_libplacebo
  fi

  build_avisynth
  build_libvvenc
  build_libvvdec
  build_libx264 # at bottom as it might internally build a copy of ffmpeg (which needs all the above deps...
  echo -e "INFO: Done Building dependencies\n" 1>>$LOG_FILE 2>&1
 }

build_apps() {
  if [[ $build_dvbtee = "y" ]]; then
    build_dvbtee_app
  fi
  # now the things that use the dependencies...
  if [[ $build_libmxf = "y" ]]; then
    build_libMXF
  fi
  if [[ $build_mp4box = "y" ]]; then
    build_mp4box
  fi
  if [[ $build_mplayer = "y" ]]; then
    build_mplayer
  fi
  if [[ $build_ffmpeg_static = "y" ]]; then
    build_ffmpeg static
  fi
  if [[ $build_ffmpeg_shared = "y" ]]; then
    build_ffmpeg shared
  fi
  if [[ $build_vlc = "y" ]]; then
    build_vlc
  fi
  if [[ $build_lsw = "y" ]]; then
    build_lsw
  fi
}

# This new function centralizes the setup for each build target.
setup_build_environment() {
  local flavor="$1"
  echo
  echo "************** Setting up environment for $flavor build... **************"
  if [[ $flavor == "win32" ]]; then
    export ARCH=$(get_arch_name $(from_arch_name $flavor))
    export FULL_ARCH="i686"
    export work_dir="$(realpath "$WORKDIR"/"$FFMPEG_KIT_BUILD_TYPE"-"$FULL_ARCH")"
    export host_target='i686-w64-mingw32'
    export mingw_w64_x86_64_prefix="$(realpath $work_dir/cross_compilers/mingw-w64-i686/$host_target)"
    export mingw_bin_path="$(realpath $work_dir/cross_compilers/mingw-w64-i686/bin)"
    export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
    export PATH="$mingw_bin_path:$original_path"
    export bits_target=32
    export cross_prefix="$mingw_bin_path/i686-w64-mingw32-"
    export make_prefix_options="--cc=${cross_prefix}gcc \
--ar=$(realpath ${cross_prefix}ar) \
--as=$(realpath ${cross_prefix}as) \
--nm=$(realpath ${cross_prefix}nm) \
--ranlib=$(realpath ${cross_prefix}ranlib) \
--ld=$(realpath ${cross_prefix}ld) \
--strip=$(realpath ${cross_prefix}strip) \
--cxx=$(realpath ${cross_prefix}g++)"
  elif [[ $flavor == "win64" ]]; then
    export ARCH=$(get_arch_name $(from_arch_name $flavor))
    export FULL_ARCH="x86_64"
    export work_dir="$(realpath "$WORKDIR"/"$FFMPEG_KIT_BUILD_TYPE"-"$FULL_ARCH")"
    export host_target='x86_64-w64-mingw32'
    export mingw_w64_x86_64_prefix="$(realpath $work_dir/cross_compilers/mingw-w64-x86_64/$host_target)"
    export mingw_bin_path="$(realpath $work_dir/cross_compilers/mingw-w64-x86_64/bin)"
    export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
    export PATH="$mingw_bin_path:$original_path"
    export bits_target=64
    export cross_prefix="$mingw_bin_path/x86_64-w64-mingw32-"
    export make_prefix_options="--cc=${cross_prefix}gcc \
--ar=$(realpath ${cross_prefix}ar) \
--as=$(realpath ${cross_prefix}as) \
--nm=$(realpath ${cross_prefix}nm) \
--ranlib=$(realpath ${cross_prefix}ranlib) \
--ld=$(realpath ${cross_prefix}ld) \
--strip=$(realpath ${cross_prefix}strip) \
--cxx=$(realpath ${cross_prefix}g++)"
    export LIB_INSTALL_BASE=$work_dir
  elif [[ $flavor == "native" ]]; then
    export mingw_w64_x86_64_prefix="$(realpath "$WORKDIR"/native/cross_compilers/native)"
    export mingw_bin_path="$(realpath "$WORKDIR"/native/cross_compilers/native/bin)"
    export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
    export PATH="$mingw_bin_path:$original_path"
    export make_prefix_options="--prefix=$mingw_w64_x86_64_prefix"
    if [[ $(uname -m) =~ 'i686' ]]; then 
      export ARCH="i686"
      export FULL_ARCH="i686"
      export bits_target=32; 
    else 
      export ARCH="x86-64"
      export FULL_ARCH="x86_64"
      export bits_target=64; 
    fi
    export CPATH=$WORKDIR/cross_compilers/native/include:/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Headers # C_INCLUDE_PATH
    export LIBRARY_PATH=$WORKDIR/cross_compilers/native/lib
    export work_dir="$(realpath "$WORKDIR"/native)"
    export LIB_INSTALL_BASE=$work_dir
  else
    echo "Error: Unknown compiler flavor '$flavor'"
    exit 1
  fi
  export src_dir="${work_dir}/src"
  export LIB_INSTALL_BASE="$work_dir"
  export FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY="$work_dir/ffmpeg-kit/pkgconfig"
  export INSTALL_PKG_CONFIG_DIR="$work_dir/pkgconfig"
  echo "Environment:\n \
    ARCH: $ARCH\n \
    FULL_ARCH: $FULL_ARCH\n \
    host_target: $host_target\n \
    mingw_w64_x86_64_prefix: $mingw_w64_x86_64_prefix\n \
    mingw_bin_path: $mingw_bin_path\n \
    PKG_CONFIG_PATH: $PKG_CONFIG_PATH\n \
    PATH: $PATH\n \
    bits_target: $bits_target\n \
    cross_prefix: $cross_prefix\n \
    make_prefix_options: $make_prefix_options\n \
    work_dir: $work_dir" 1>> $LOG_FILE 2>&1
  create_dir "$work_dir"
  change_dir "$work_dir" || exit
}

create_ffmpegkit_package_config() {
  local FFMPEGKIT_VERSION="$1"

  cat >"${INSTALL_PKG_CONFIG_DIR}/ffmpeg-kit.pc" <<EOF
prefix=${LIB_INSTALL_BASE}/ffmpeg-kit
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: ffmpeg-kit
Description: FFmpeg for applications on Windows
Version: ${FFMPEGKIT_VERSION}

# Public dependencies that have their own .pc files
Requires: libavfilter, libswscale, libavformat, libavcodec, libswresample, libavutil

# Linker flags for the ffmpeg-kit library itself
Libs: -L\${libdir} -lffmpegkit

# Private dependencies needed for linking on Windows that are not covered by 'Requires'
# These are system libraries and the C++ standard library.
Libs.private: -lstdc++ -lws2_32 -lpsapi -lole32 -lshlwapi -lgdi32 -lbcrypt -luser32 -luuid

# Compiler flags for the ffmpeg-kit headers
Cflags: -I\${includedir}
EOF
}

get_arch_specific_ldflags() {
  case ${ARCH} in
  x86-64)
    echo "-march=x86-64 -Wl,-z,text"
    ;;
  esac
}

get_size_optimization_ldflags() {
  if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
    local LINK_TIME_OPTIMIZATION_FLAGS="-flto"
  else
    local LINK_TIME_OPTIMIZATION_FLAGS=""
  fi

  case ${ARCH} in
  x86-64)
    case $1 in
    ffmpeg)
      echo "${LINK_TIME_OPTIMIZATION_FLAGS} -O2 -ffunction-sections -fdata-sections -finline-functions"
      ;;
    *)
      echo "-Os -ffunction-sections -fdata-sections"
      ;;
    esac
    ;;
  esac
}

get_common_linked_libraries() {
  local COMMON_LIBRARIES=""

  case $1 in
  chromaprint | ffmpeg-kit | kvazaar | srt | zimg)
    echo "-stdlib=libstdc++ -lstdc++ -lc -lm ${COMMON_LIBRARIES}"
    ;;
  *)
    echo "-lc -lm -ldl ${COMMON_LIBRARIES}"
    ;;
  esac
}

get_ldflags() {
  local ARCH_FLAGS=$(get_arch_specific_ldflags)
  if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
    local OPTIMIZATION_FLAGS="$(get_size_optimization_ldflags "$1")"
  else
    local OPTIMIZATION_FLAGS="${FFMPEG_KIT_DEBUG}"
  fi
  local COMMON_LINKED_LIBS=$(get_common_linked_libraries "$1")

  echo "${ARCH_FLAGS} ${OPTIMIZATION_FLAGS} ${COMMON_LINKED_LIBS} ${LLVM_CONFIG_LDFLAGS} -Wl,--hash-style=both -fuse-ld=lld"
}

get_cxxflags() {
  if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
    local LINK_TIME_OPTIMIZATION_FLAGS="-flto"
  else
    local LINK_TIME_OPTIMIZATION_FLAGS=""
  fi

  if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
    local OPTIMIZATION_FLAGS="-Os -ffunction-sections -fdata-sections"
  else
    local OPTIMIZATION_FLAGS="${FFMPEG_KIT_DEBUG}"
  fi

  local BUILD_DATE="-DFFMPEG_KIT_BUILD_DATE=$(date +%Y%m%d 2>>$LOG_FILE)"
  local COMMON_FLAGS="-stdlib=libstdc++ -std=c++11 ${OPTIMIZATION_FLAGS} ${BUILD_DATE} $(get_arch_specific_cflags)"

  case $1 in
  ffmpeg)
    if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
      echo "${LINK_TIME_OPTIMIZATION_FLAGS} -stdlib=libstdc++ -std=c++11 -O2 -ffunction-sections -fdata-sections"
    else
      echo "${FFMPEG_KIT_DEBUG} -stdlib=libstdc++ -std=c++11"
    fi
    ;;
  ffmpeg-kit)
    echo "${COMMON_FLAGS}"
    ;;
  srt | tesseract | zimg)
    echo "${COMMON_FLAGS} -fcxx-exceptions -fPIC"
    ;;
  *)
    echo "${COMMON_FLAGS} -fno-exceptions -fno-rtti"
    ;;
  esac
}

get_common_includes() {
  echo "-I${LLVM_CONFIG_INCLUDEDIR:-.}"
}

get_size_optimization_cflags() {
  if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
    local LINK_TIME_OPTIMIZATION_FLAGS="-flto"
  else
    local LINK_TIME_OPTIMIZATION_FLAGS=""
  fi

  local ARCH_OPTIMIZATION=""
  case ${ARCH} in
  x86-64 | x86_64)
    case $1 in
    ffmpeg)
      ARCH_OPTIMIZATION="${LINK_TIME_OPTIMIZATION_FLAGS} -Os -ffunction-sections -fdata-sections"
      ;;
    *)
      ARCH_OPTIMIZATION="-Os -ffunction-sections -fdata-sections"
      ;;
    esac
    ;;
  esac

  local LIB_OPTIMIZATION=""

  echo "${ARCH_OPTIMIZATION} ${LIB_OPTIMIZATION}"
}

get_common_cflags() {
  if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
    local LTS_BUILD_FLAG="-DFFMPEG_KIT_LTS "
  fi

  echo "-fstrict-aliasing -fPIC -DWINDOWS ${LTS_BUILD_FLAG} ${LLVM_CONFIG_CFLAGS}"
}

get_app_specific_cflags() {
  local APP_FLAGS=""
  case $1 in
  ffmpeg)
    APP_FLAGS="-Wno-unused-function"
    ;;
  ffmpeg-kit)
    APP_FLAGS="-Wno-unused-function -Wno-pointer-sign -Wno-switch -Wno-deprecated-declarations"
    ;;
  kvazaar)
    APP_FLAGS="-std=gnu99 -Wno-unused-function"
    ;;
  openh264)
    APP_FLAGS="-std=gnu99 -Wno-unused-function -fstack-protector-all"
    ;;
  srt)
    APP_FLAGS="-Wno-unused-function"
    ;;
  *)
    APP_FLAGS="-std=c99 -Wno-unused-function"
    ;;
  esac

  echo "${APP_FLAGS}"
}

get_arch_specific_cflags() {
  case ${ARCH} in
  x86-64 | x86_64)
    echo "-target $(get_target) -DFFMPEG_KIT_X86_64"
    ;;
  esac
}

get_cflags() {
  local ARCH_FLAGS=$(get_arch_specific_cflags)
  local APP_FLAGS=$(get_app_specific_cflags "$1")
  local COMMON_FLAGS=$(get_common_cflags)
  if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
    local OPTIMIZATION_FLAGS=$(get_size_optimization_cflags "$1")
  else
    local OPTIMIZATION_FLAGS="${FFMPEG_KIT_DEBUG}"
  fi
  local COMMON_INCLUDES=$(get_common_includes)

  echo "${ARCH_FLAGS} ${APP_FLAGS} ${COMMON_FLAGS} ${OPTIMIZATION_FLAGS} ${COMMON_INCLUDES}"
}

get_target_cpu() {
  case ${ARCH} in
  i686 | x86 | win32)
    echo "i686" 
    ;;
  x86-64 | x86_64 | win64)
    echo "x86_64"
    ;;
  esac
}

get_build_directory() {
  local LTS_POSTFIX=""
  if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
    LTS_POSTFIX="-lts"
  fi

  echo "windows-$(get_target_cpu)${LTS_POSTFIX}"
}

detect_clang_version() {
  if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
    for clang_version in 6 .. 10; do
      if [[ $(command_exists "clang-$clang_version") -eq 0 ]]; then
        echo "$clang_version"
        return
      elif [[ $(command_exists "clang-$clang_version.0") -eq 0 ]]; then
        echo "$clang_version.0"
        return
      fi
    done
    echo "none"
  else
    for clang_version in 11 .. 20; do
      if [[ $(command_exists "clang-$clang_version") -eq 0 ]]; then
        echo "$clang_version"
        return
      elif [[ $(command_exists "clang-$clang_version.0") -eq 0 ]]; then
        echo "$clang_version.0"
        return
      fi
    done
    echo "none"
  fi
}

set_toolchain_paths() {
  HOST=$(get_host)
  CLANG_VERSION=$(detect_clang_version)

  if [[ $CLANG_VERSION != "none" ]]; then
    local CLANG_POSTFIX="-$CLANG_VERSION"
    export LLVM_CONFIG_CFLAGS=$(llvm-config-$CLANG_VERSION --cflags 2>>$LOG_FILE)
    export LLVM_CONFIG_INCLUDEDIR=$(llvm-config-$CLANG_VERSION --includedir 2>>$LOG_FILE)
    export LLVM_CONFIG_LDFLAGS=$(llvm-config-$CLANG_VERSION --ldflags 2>>$LOG_FILE)
  else
    local CLANG_POSTFIX=""
    export LLVM_CONFIG_CFLAGS=$(llvm-config --cflags 2>>$LOG_FILE)
    export LLVM_CONFIG_INCLUDEDIR=$(llvm-config --includedir 2>>$LOG_FILE)
    export LLVM_CONFIG_LDFLAGS=$(llvm-config --ldflags 2>>$LOG_FILE)
  fi

  export CC=$(command -v "${cross_prefix}gcc")
  export CXX=$(command -v "${cross_prefix}g++")
  export AS=$(command -v "${cross_prefix}as")
  export AR=$(command -v "${cross_prefix}ar")
  export LD=$(command -v "${cross_prefix}ld")
  export RANLIB=$(command -v "${cross_prefix}ranlib")
  export STRIP=$(command -v "${cross_prefix}strip")
  export NM=$(command -v "${cross_prefix}nm")

  if [ ! -d "${INSTALL_PKG_CONFIG_DIR}" ]; then
    create_dir "${INSTALL_PKG_CONFIG_DIR}" 1>>$LOG_FILE 2>&1
  fi
}

enable_lts_build() {
  export FFMPEG_KIT_LTS_BUILD="1"
}

install_pkg_config_file() {
  local FILE_NAME="$1"
  local SOURCE="${INSTALL_PKG_CONFIG_DIR}/${FILE_NAME}"
  local DESTINATION="${FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY}/${FILE_NAME}"

  # DELETE OLD FILE
  remove_dir -f "$DESTINATION" 2>>$LOG_FILE
  if [[ $? -ne 0 ]]; then
    echo -e "failed\n\nSee $LOG_FILE for details\n"
    exit 1
  fi

  # INSTALL THE NEW FILE
  copy_path "$SOURCE" "$DESTINATION" 2>>$LOG_FILE
  if [[ $? -ne 0 ]]; then
    echo -e "failed\n\nSee $LOG_FILE for details\n"
    exit 1
  fi

  # UPDATE PATHS
  ${SED_INLINE} "s|${LIB_INSTALL_BASE}/ffmpeg-kit|${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit|g" "$DESTINATION" 1>>$LOG_FILE 2>&1 || return 1
  ${SED_INLINE} "s|${LIB_INSTALL_BASE}/ffmpeg|${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit|g" "$DESTINATION" 1>>$LOG_FILE 2>&1 || return 1
}

get_ffmpeg_kit_version() {
  local FFMPEG_KIT_VERSION=$(grep -Eo 'FFmpegKitVersion = .*' "${BASEDIR}/windows/src/FFmpegKitConfig.h" 2>>$LOG_FILE | grep -Eo ' \".*' | tr -d '"; ')

  echo "${FFMPEG_KIT_VERSION}"
}


get_bundle_directory() {
  local LTS_POSTFIX=""
  if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]]; then
    LTS_POSTFIX="-lts"
  fi

  echo "bundle-windows${LTS_POSTFIX}"
}

create_windows_bundle() {
  echo -e "INFO: Creating bundle\n" 1>>$LOG_FILE 2>&1
  set_toolchain_paths ""

  local FFMPEG_KIT_VERSION=$(get_ffmpeg_kit_version)

  local FFMPEG_KIT_BUNDLE_DIRECTORY="${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit"
  local FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY="${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit/include"
  local FFMPEG_KIT_BUNDLE_LIB_DIRECTORY="${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit/lib"
  local FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY="${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit/pkgconfig"

  initialize_folder "${FFMPEG_KIT_BUNDLE_INCLUDE_DIRECTORY}"
  initialize_folder "${FFMPEG_KIT_BUNDLE_LIB_DIRECTORY}"
  initialize_folder "${FFMPEG_KIT_BUNDLE_PKG_CONFIG_DIRECTORY}"

  # COPY HEADERS
  copy_path "${LIB_INSTALL_BASE}"/ffmpeg-kit/include/* "${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit/include" "-rP" 2>>$LOG_FILE
  copy_path "${LIB_INSTALL_BASE}"/ffmpeg/include/* "${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit/include" "-rP" 2>>$LOG_FILE

  # COPY LIBS
  copy_path "${LIB_INSTALL_BASE}"/ffmpeg-kit/lib/lib* "${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit/lib" "-P" 2>>$LOG_FILE
  copy_path "${LIB_INSTALL_BASE}"/ffmpeg/lib/lib* "${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit/lib" "-P" 2>>$LOG_FILE

  install_pkg_config_file "libavformat.pc"
  install_pkg_config_file "libswresample.pc"
  install_pkg_config_file "libswscale.pc"
  install_pkg_config_file "libavdevice.pc"
  install_pkg_config_file "libavfilter.pc"
  install_pkg_config_file "libavcodec.pc"
  install_pkg_config_file "libavutil.pc"
  install_pkg_config_file "ffmpeg-kit.pc"

  copy_path "${BASEDIR}"/tools/source/SOURCE "${LICENSE_BASEDIR}"/source.txt 1>>$LOG_FILE 2>&1 || exit 1

  echo -e "DEBUG: Copied the ffmpeg-kit license successfully\n" 1>>$LOG_FILE 2>&1
  echo -e "INFO: Done creating bundle\n" 1>>$LOG_FILE 2>&1
}

copy_library_licenses() {
  # COPY EXTERNAL LIBRARY LICENSES
  local LICENSE_BASEDIR="${BASEDIR}/prebuilt/$(get_bundle_directory)/ffmpeg-kit/lib"
  remove_dir -f "${LICENSE_BASEDIR}"/*.txt 1>>$LOG_FILE 2>&1 || exit 1
  for library in {0..49}; do
    if [[ ${ENABLED_LIBRARIES[$library]} -eq 1 ]]; then
      ENABLED_LIBRARY=$(get_library_name ${library} | sed 's/-/_/g')
      LICENSE_FILE="${LICENSE_BASEDIR}/license_${ENABLED_LIBRARY}.txt"

      RC=$(copy_external_library_license_file ${library} "${LICENSE_FILE}")

      if [[ ${RC} -ne 0 ]]; then
        echo -e "DEBUG: Failed to copy the license file of ${ENABLED_LIBRARY}\n" 1>>$LOG_FILE 2>&1
        echo -e "failed\n\nSee $LOG_FILE for details\n"
        exit 1
      fi

      echo -e "DEBUG: Copied the license file of ${ENABLED_LIBRARY} successfully\n" 1>>$LOG_FILE 2>&1
    fi
  done

  # COPY CUSTOM LIBRARY LICENSES
  for custom_library_index in "${CUSTOM_LIBRARIES[@]}"; do
    library_name="CUSTOM_LIBRARY_${custom_library_index}_NAME"
    relative_license_path="CUSTOM_LIBRARY_${custom_library_index}_LICENSE_FILE"

    destination_license_path="${LICENSE_BASEDIR}/license_${!library_name}.txt"

    copy_path "${BASEDIR}/prebuilt/src/${!library_name}/${!relative_license_path}" "${destination_license_path}" 1>>$LOG_FILE 2>&1

    RC=$?

    if [[ ${RC} -ne 0 ]]; then
      echo -e "DEBUG: Failed to copy the license file of custom library ${!library_name}\n" 1>>$LOG_FILE 2>&1
      echo -e "failed\n\nSee $LOG_FILE for details\n"
      exit 1
    fi

    echo -e "DEBUG: Copied the license file of custom library ${!library_name} successfully\n" 1>>$LOG_FILE 2>&1
  done

  # COPY LIBRARY LICENSES
  if [[ ${GPL_ENABLED} == "yes" ]]; then
    copy_path "${BASEDIR}"/tools/license/LICENSE.GPLv3 "${LICENSE_BASEDIR}"/license.txt 1>>$LOG_FILE 2>&1 || exit 1
  else
    copy_path "${BASEDIR}"/LICENSE "${LICENSE_BASEDIR}"/license.txt 1>>$LOG_FILE 2>&1 || exit 1
  fi
}

build_ffmpeg_kit() {
  echo -e "INFO: Building ffmpeg kit\n" 1>>$LOG_FILE 2>&1
  # BUILD FFMPEG KIT
  . ${SCRIPTDIR}/windows/ffmpeg-kit.sh "$@" || return 1
  echo -e "INFO: Done building ffmpeg kit\n" 1>>$LOG_FILE 2>&1
}

download_ffmpeg() {
  local output_dir="$work_dir/ffmpeg"
  local desired_version="$ffmpeg_git_checkout_version"

  if [[ -z $desired_version ]]; then
    desired_version="master"
  fi

  do_git_checkout "$ffmpeg_git_checkout" "$output_dir" "$desired_version" || exit 1
  ffmpeg_source_dir=$output_dir
  echo $output_dir
}

install_cross_compiler() {
  local win32_gcc="cross_compilers/mingw-w64-i686/bin/i686-w64-mingw32-gcc"
  local win64_gcc="cross_compilers/mingw-w64-x86_64/bin/x86_64-w64-mingw32-gcc"
  if [[ -f $win32_gcc && -f $win64_gcc ]]; then
   echo "MinGW-w64 compilers both already installed, not re-installing..."
   if [[ -z $compiler_flavors ]]; then
     echo "selecting multi build (both win32 and win64)...since both cross compilers are present assuming you want both..."
     compiler_flavors=multi
   fi
   return # early exit they've selected at least some kind by this point...
  fi

  if [[ -z $compiler_flavors ]]; then
    pick_compiler_flavors
  fi
  if [[ $compiler_flavors == "native" ]]; then
    echo "native build, not building any cross compilers..."
    return
  fi
  setup_build_environment "$compiler_flavors"
  create_dir cross_compilers
  change_dir cross_compilers

  unset CFLAGS # don't want these "windows target" settings used the compiler itself since it creates executables to run on the local box (we have a parameter allowing them to set them for the script "all builds" basically)
  # pthreads version to avoid having to use cvs for it
  echo "Starting to download and build cross compile version of gcc [requires working internet access] with thread count $gcc_cpu_count..."
  echo ""

  # --disable-shared allows c++ to be distributed at all...which seemed necessary for some random dependency which happens to use/require c++...
  local zeranoe_script_name=mingw-w64-build
  local zeranoe_script_options="--gcc-branch=releases/gcc-14 --mingw-w64-branch=master --binutils-branch=binutils-2_44-branch" # --cached-sources"
  if [[ ($compiler_flavors == "win32" || $compiler_flavors == "multi") && ! -f ../$win32_gcc ]]; then
    echo "Building win32 cross compiler..."
    download_gcc_build_script $zeranoe_script_name
    if [[ `uname` =~ "5.1" ]]; then # Avoid using secure API functions for compatibility with msvcrt.dll on Windows XP.
      sed -i "s/ --enable-secure-api//" $zeranoe_script_name
    fi
    CFLAGS='-O2 -pipe' CXXFLAGS='-O2 -pipe' nice ./$zeranoe_script_name $zeranoe_script_options i686 || exit 1 # i586 option needs work to implement
    if [[ ! -f ../$win32_gcc ]]; then
      echo "Failure building 32 bit gcc? Recommend nuke prebuilt (rm -rf prebuilt) and start over..."
      exit 1
    fi
    if [[ ! -f  ../cross_compilers/mingw-w64-i686/i686-w64-mingw32/lib/libmingwex.a ]]; then
      echo "failure building mingwex? 32 bit"
      exit 1
    fi
  fi
  if [[ ($compiler_flavors == "win64" || $compiler_flavors == "multi") && ! -f ../$win64_gcc ]]; then
    echo "Building win64 x86_64 cross compiler..."
    download_gcc_build_script $zeranoe_script_name
    CFLAGS='-O3 -pipe' CXXFLAGS='-O3 -pipe' nice ./$zeranoe_script_name $zeranoe_script_options x86_64 || exit 1
    if [[ ! -f ../$win64_gcc ]]; then
      echo "Failure building 64 bit gcc? Recommend nuke prebuilt (rm -rf prebuilt) and start over..."
      exit 1
    fi
    if [[ ! -f  ../cross_compilers/mingw-w64-x86_64/x86_64-w64-mingw32/lib/libmingwex.a ]]; then
      echo "failure building mingwex? 64 bit"
      exit 1
    fi
  fi

  # rm -f build.log # leave resultant build log...sometimes useful...
  reset_cflags
  change_dir ..
  echo "Done building (or already built) MinGW-w64 cross-compiler(s) successfully..."
  echo `date` # so they can see how long it took :)
}

install_ffmpeg() {
  echo -e "INFO: Installing ffmpeg\n" 1>>$LOG_FILE 2>&1
  change_dir $ffmpeg_source_dir

  # DELETE THE PREVIOUS BUILD OF THE LIBRARY BEFORE INSTALLING
  if [ ! -z "$install_prefix" ] && [ -e "$install_prefix" ] && [[ $BUILD_FORCE == "1" ]]; then
    echo -e "INFO: Clearing install directory\n" 1>>$LOG_FILE 2>&1
    remove_path -rf "$install_prefix" 1>>"${BASEDIR}"/build.log 2>&1
    rm -f */*.a */*.dll *.exe 1>>"${BASEDIR}"/build.log 2>&1
    rm -f already_ran_make* 1>>"${BASEDIR}"/build.log 2>&1
  fi

  echo "doing ffmpeg make $(pwd)"

  create_dir $install_prefix

  do_make_and_make_install 1>>"${BASEDIR}"/build.log 2>&1

  echo -e "INFO: Done installing ffmpeg\n" 1>>$LOG_FILE 2>&1
  install_ffmpeg_pkg
}

install_ffmpeg_pkg() {
  echo "Checking deployment files...\n"  1>>$LOG_FILE 2>&1

  required_files=(
    "${install_prefix}/lib/pkgconfig/libavformat.pc"
    "${install_prefix}/lib/pkgconfig/libswresample.pc"
    "${install_prefix}/lib/pkgconfig/libswscale.pc"
    "${install_prefix}/lib/pkgconfig/libavdevice.pc"
    "${install_prefix}/lib/pkgconfig/libavfilter.pc"
    "${install_prefix}/lib/pkgconfig/libavcodec.pc"
    "${install_prefix}/lib/pkgconfig/libavutil.pc"
  )

  check_files_exist "false" "${required_files[@]}"

  echo "Done checking deployment files.\n"  1>>$LOG_FILE 2>&1

  echo -e "INFO: Installing ffmpeg pkg-config\n" 1>>$LOG_FILE 2>&1

  create_dir "$INSTALL_PKG_CONFIG_DIR"

  # MANUALLY COPY PKG-CONFIG FILES
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavformat.pc "${INSTALL_PKG_CONFIG_DIR}/libavformat.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libswresample.pc "${INSTALL_PKG_CONFIG_DIR}/libswresample.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libswscale.pc "${INSTALL_PKG_CONFIG_DIR}/libswscale.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavdevice.pc "${INSTALL_PKG_CONFIG_DIR}/libavdevice.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavfilter.pc "${INSTALL_PKG_CONFIG_DIR}/libavfilter.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavcodec.pc "${INSTALL_PKG_CONFIG_DIR}/libavcodec.pc" || return 1
  overwrite_file "${install_prefix}"/lib/pkgconfig/libavutil.pc "${INSTALL_PKG_CONFIG_DIR}/libavutil.pc" || return 1

  # # MANUALLY ADD REQUIRED HEADERS
  mkdir -p "${install_prefix}"/include/libavutil/x86 1>>"${BASEDIR}"/build.log 2>&1
  mkdir -p "${install_prefix}"/include/libavutil/arm 1>>"${BASEDIR}"/build.log 2>&1
  mkdir -p "${install_prefix}"/include/libavutil/aarch64 1>>"${BASEDIR}"/build.log 2>&1
  mkdir -p "${install_prefix}"/include/libavcodec/x86 1>>"${BASEDIR}"/build.log 2>&1
  mkdir -p "${install_prefix}"/include/libavcodec/arm 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/config.h "${install_prefix}"/include/config.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavcodec/mathops.h "${install_prefix}"/include/libavcodec/mathops.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavcodec/x86/mathops.h "${install_prefix}"/include/libavcodec/x86/mathops.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavcodec/arm/mathops.h "${install_prefix}"/include/libavcodec/arm/mathops.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavformat/network.h "${install_prefix}"/include/libavformat/network.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavformat/os_support.h "${install_prefix}"/include/libavformat/os_support.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavformat/url.h "${install_prefix}"/include/libavformat/url.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/attributes_internal.h "${install_prefix}"/include/libavutil/attributes_internal.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/bprint.h "${install_prefix}"/include/libavutil/bprint.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/getenv_utf8.h "${install_prefix}"/include/libavutil/getenv_utf8.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/internal.h "${install_prefix}"/include/libavutil/internal.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/libm.h "${install_prefix}"/include/libavutil/libm.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/reverse.h "${install_prefix}"/include/libavutil/reverse.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/thread.h "${install_prefix}"/include/libavutil/thread.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/timer.h "${install_prefix}"/include/libavutil/timer.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/x86/asm.h "${install_prefix}"/include/libavutil/x86/asm.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/x86/timer.h "${install_prefix}"/include/libavutil/x86/timer.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/arm/timer.h "${install_prefix}"/include/libavutil/arm/timer.h 1>>"${BASEDIR}"/build.log 2>&1
  overwrite_file "${ffmpeg_source_dir}"/libavutil/aarch64/timer.h "${install_prefix}"/include/libavutil/aarch64/timer.h 1>>"${BASEDIR}"/build.log 2>&1

  echo -e "INFO: Done installing ffmpeg pkg-config\n" 1>>$LOG_FILE 2>&1
}

configure_ffmpeg() {
  echo -e "INFO: Configuering ffmpeg\n" 1>>$LOG_FILE 2>&1
  # SKIP TO SPEED UP THE BUILD
  # PREPARE PATHS & DEFINE ${INSTALL_PKG_CONFIG_DIR}
  LIB_NAME="ffmpeg"

  set_toolchain_paths "${LIB_NAME}"

  change_dir "$ffmpeg_source_dir" 1>>$LOG_FILE 2>&1 || return 1

  # SET DEBUG OPTIONS
  if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
    # SET LTO FLAGS
    DEBUG_OPTIONS=" --disable-debug"
  else
    DEBUG_OPTIONS=" --enable-debug --disable-stripping"
  fi
  local extra_postpend_configure_options=$2

  local postpend_configure_opts=""
  install_prefix="$ffmpeg_source_dir/build" # install them to their a separate dir

  # can't mix and match --enable-static --enable-shared unfortunately, or the final executable seems to just use shared if the're both present
  if [[ $build_ffmpeg_shared == "y" || $build_ffmpeg_shared == "yes" || $build_ffmpeg_shared == "1" ]]; then
    install_prefix+="${install_prefix}_shared"
    postpend_configure_opts="--enable-shared --disable-static --prefix=${install_prefix}" # I guess this doesn't have to be at the end...
  else
    install_prefix+="${install_prefix}_static"
    postpend_configure_opts="--enable-static --disable-shared --prefix=${install_prefix}"
  fi

  if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
    postpend_configure_opts="${postpend_configure_opts} --disable-libdav1d " # dav1d has diverged since so isn't compat with older ffmpegs
  fi

  change_dir "$ffmpeg_source_dir" || exit
    apply_patch file://"$WINPATCHDIR"/frei0r_load-shared-libraries-dynamically.diff
    if [ "$bits_target" = "32" ]; then
      local arch=x86
    else
      local arch=amd64
    fi

    local init_options="--pkg-config=pkg-config --pkg-config-flags=--static --enable-version3 --disable-debug --disable-w32threads"
    if [[ $compiler_flavors != "native" ]]; then
      init_options+=" --arch=$arch --target-os=mingw32 --cross-prefix=$cross_prefix"
    else
      if [[ $OSTYPE != darwin* ]]; then
        unset PKG_CONFIG_LIBDIR # just use locally packages for all the xcb stuff for now, you need to install them locally first...
        init_options+=" --enable-libv4l2 --enable-libxcb --enable-libxcb-shm --enable-libxcb-xfixes --enable-libxcb-shape "
      fi
    fi
    if [[ $(uname) =~ "5.1" ]]; then
      init_options+=" --disable-schannel"
      # Fix WinXP incompatibility by disabling Microsoft's Secure Channel, because Windows XP doesn't support TLS 1.1 and 1.2, but with GnuTLS or OpenSSL it does.  XP compat!
    fi

    local config_options=" $init_options"
    config_options+=" --disable-w32threads"
    config_options+=" --disable-autodetect"
    config_options+=" --enable-cross-compile"
    config_options+=" --enable-pic"
    config_options+=" --enable-optimizations"
    config_options+=" --enable-swscale"
    config_options+=" --enable-pthreads"
    #config_options+=" --enable-small"
    config_options+=" --disable-xmm-clobber-test"
    config_options+=" --disable-neon-clobber-test"
    config_options+=" --disable-v4l2-m2m"  # Corrected: use disable instead of enable

    # Essential libraries for Win64 (RECOMMENDED)
    config_options+=" --enable-zlib"
    config_options+=" --enable-libmp3lame"
    config_options+=" --enable-bzlib"

    # Video codecs (RECOMMENDED for common use)
    config_options+=" --enable-libx264"
    config_options+=" --enable-libvpx"
    config_options+=" --enable-libopus"
    config_options+=" --disable-openssl"
    # OR for Windows-native: config_options+=" --disable-schannel" (but don't use both)

    # Optional but useful libraries
    config_options+=" --enable-libass"
    config_options+=" --enable-libfreetype"
    config_options+=" --enable-libfontconfig"  # Needed for libass
    config_options+=" --enable-libvorbis"
    config_options+=" --enable-libwebp"
    config_options+=" --enable-filter=drawtext"  # Requires libfreetype

    # Hardware acceleration (optional)
    config_options+=" --enable-cuda"
    # config_options+=" --enable-cuda-llvm"  # Choose one CUDA method
    config_options+=" --enable-cuvid"
    config_options+=" --enable-ffnvcodec"
    config_options+=" --enable-nvenc"
    config_options+=" --enable-nvdec"

    # ==================== DISABLED LIBRARIES (Win64 appropriate) ====================

    # Linux-specific (correctly disabled)
    config_options+=" --disable-alsa"
    config_options+=" --disable-libv4l2"
    config_options+=" --disable-sndio"

    # macOS/iOS specific (correctly disabled)
    config_options+=" --disable-appkit"
    config_options+=" --disable-audiotoolbox"
    config_options+=" --disable-videotoolbox"
    config_options+=" --disable-securetransport"

    # Unnecessary or problematic for minimal Win64 build
    config_options+=" --disable-gmp"
    config_options+=" --disable-gnutls"
    config_options+=" --disable-iconv"
    config_options+=" --disable-libdav1d"
    config_options+=" --disable-libfribidi"
    config_options+=" --disable-libilbc"
    config_options+=" --disable-libkvazaar"
    config_options+=" --disable-libopencore-amrnb"
    config_options+=" --disable-libopencore-amrwb"
    config_options+=" --disable-libopenh264"
    config_options+=" --disable-librubberband"
    config_options+=" --disable-libshine"
    config_options+=" --disable-libsnappy"
    config_options+=" --disable-libsoxr"
    config_options+=" --disable-libspeex"
    config_options+=" --disable-libsrt"
    config_options+=" --disable-libtesseract"
    config_options+=" --disable-libtheora"
    config_options+=" --disable-libtwolame"
    config_options+=" --disable-libvidstab"
    config_options+=" --disable-libvo-amrwbenc"
    config_options+=" --disable-libxml2"
    config_options+=" --disable-libxvid"
    config_options+=" --disable-libzimg"

    # Documentation and programs
    config_options+=" --disable-doc"
    config_options+=" --disable-htmlpages"
    config_options+=" --disable-manpages"
    config_options+=" --disable-podpages"
    config_options+=" --disable-txtpages"

    # Platform-specific graphics
    config_options+=" --disable-xlib"
    config_options+=" --disable-sdl2"

    # Other hardware acceleration APIs
    config_options+=" --disable-vaapi"
    config_options+=" --disable-vdpau"
    config_options+=${SIZE_OPTIONS}
    config_options+=${DEBUG_OPTIONS}
    
    # ==================== ORIGINAL OPTIONAL FEATURES (conditionally kept) ====================
    
    if [[ $build_svt_hevc = y ]]; then
      # SVT-HEVC patches and enable
      if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
        git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/n4.4-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
        git apply "$WINPATCHDIR/SVT-HEVC-0002-doc-Add-libsvt_hevc-encoder-docs.patch"
      elif [[ $ffmpeg_git_checkout_version == *"n4.1"* ]] || [[ $ffmpeg_git_checkout_version == *"n3"* ]] || [[ $ffmpeg_git_checkout_version == *"n2"* ]]; then
        : # too old...
      else
        git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/master-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
      fi
      config_options+=" --enable-libsvthevc"
    fi

    if [[ $build_svt_vp9 = y ]]; then
      # SVT-VP9 patches and enable
      if [[ $ffmpeg_git_checkout_version == *"n4.3.1"* ]]; then
        git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/n4.3.1-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
      elif [[ $ffmpeg_git_checkout_version == *"n4.2.3"* ]]; then
        git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/n4.2.3-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
      elif [[ $ffmpeg_git_checkout_version == *"n4.2.2"* ]]; then
        git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
      else 
        git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/master-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
      fi
      config_options+=" --enable-libsvtvp9"
    fi
    local enable_libsvtav1=" --enable-libsvtav1"
    # SVT-AV1
    if [[ $ffmpeg_git_checkout_version != *"n6"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then
      git apply "$work_dir/SVT-AV1_git/.gitlab/workflows/linux/ffmpeg_n7_fix.patch" >/dev/null 2>&1 
      patch_exists=$?
      if [[ $patch_exists != 0 ]]; then
        enable_libsvtav1=" --disable-libsvtav1"
      fi
    fi
    config_options+=$enable_libsvtav1

    config_options+=" --enable-libaom"

    # ==================== ORIGINAL EXTRAS (conditionally kept) ====================
    
    if [[ $build_amd_amf = n ]]; then
      config_options+=" --disable-amf"
    else
      config_options+=" --enable-amf"
    fi

    if [[ $compiler_flavors != "native" ]]; then 
      config_options+=" --enable-libvpl"
    else
      config_options+=" --disable-libvpl"
    fi
    
    if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then
      config_options+=" --enable-libaribcaption"
    fi
    
    if [[ $GPL_ENABLED == 'y' ]] || [[ $GPL_ENABLED == 'yes' ]]; then
      config_options+=" --enable-gpl --enable-frei0r --enable-librubberband --enable-libvidstab --enable-libx265 --enable-avisynth"
      config_options+=" --enable-libxvid --enable-libdavs2"
      if [[ $host_target != 'i686-w64-mingw32' ]]; then
        config_options+=" --enable-libxavs2"
      fi
      if [[ $compiler_flavors != "native" ]]; then
        config_options+=" --enable-libxavs"
      fi
    fi

    # Extra libs and flags
    config_options+=" --extra-libs=-lz"
    config_options+=" --extra-libs=-lpng"
    config_options+=" --extra-libs=-lm"
    config_options+=" --extra-libs=-lfreetype"

    if [[ $compiler_flavors != "native" ]]; then
      config_options+=" --extra-libs=-lshlwapi"
    fi
    config_options+=" --extra-libs=-lmpg123"
    config_options+=" --extra-libs=-lpthread"

    config_options+=" --extra-cflags=-DLIBTWOLAME_STATIC --extra-cflags=-DMODPLUG_STATIC --extra-cflags=-DCACA_STATIC"

    for i in $CFLAGS; do
      config_options+=" --extra-cflags=$i"
    done

    config_options+=" $postpend_configure_opts"

    # if [[ "$non_free" = "y" ]]; then
    #   config_options+=" --enable-nonfree --enable-libfdk-aac"
    #   if [[ $OSTYPE != darwin* ]]; then
    #     config_options+=" --enable-audiotoolbox --disable-outdev=audiotoolbox --extra-libs=-lAudioToolboxWrapper" && apply_patch file://"$WINPATCHDIR"/AudioToolBox.patch -p1
    #   fi
    #   if [[ $compiler_flavors != "native" ]]; then
    #     config_options+=" --enable-decklink"
    #   fi
    # fi

    do_debug_build=n
    if [[ "$do_debug_build" = "y" ]]; then
      config_options+=" --disable-optimizations --extra-cflags=-Og --extra-cflags=-fno-omit-frame-pointer --enable-debug=3 --extra-cflags=-fno-inline $postpend_configure_opts"
      config_options+=" --disable-libgme"
    fi
    config_options+=" $extra_postpend_configure_options"

    do_configure "$config_options"

  echo -e "INFO: Done configuering ffmpeg\n" 1>>$LOG_FILE 2>&1
}

# build_ffmpeg() {
#   remove_path -f */*.a */*.dll *.exe
#   remove_path -f already_ran_make*
#   echo "doing ffmpeg make $(pwd)"

#   do_make_and_make_install

#   if [[ $build_ismindex == "y" ]]; then
#     make tools/ismindex.exe || exit 1
#   fi

#   # if [[ $non_free == "y" ]]; then
#   #   if [[ $build_type == "shared" ]]; then
#   #     echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)/bin"
#   #   else
#   #     echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)"
#   #   fi
#   # else
#   create_dir "$WORKDIR"/redist
#   archive="$WORKDIR/redist/ffmpeg-$(git describe --tags --match N)-win$bits_target-$1"
#   if [[ $original_cflags =~ "pentium3" ]]; then
#     archive+="_legacy"
#   fi
#   if [[ $build_type == "shared" ]]; then
#     echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)/bin"
#     if [[ ! -f $archive.7z ]]; then
#       sed "s/$/\r/" COPYING.GPLv3 > bin/COPYING.GPLv3.txt
#       cp -r include bin
#       change_dir bin || exit
#         7z a -mx=9 "$archive".7z include *.exe *.dll *.lib COPYING.GPLv3.txt && remove_dir -f COPYING.GPLv3.txt
#       change_dir ..
#     fi
#   else
#     echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)" $(date)
#     if [[ ! -f $archive.7z ]]; then
#       sed "s/$/\r/" COPYING.GPLv3 > COPYING.GPLv3.txt
#       echo "creating distro zip..."
#       7z a -mx=9 "$archive".7z ffmpeg.exe ffplay.exe ffprobe.exe COPYING.GPLv3.txt && remove_dir -f COPYING.GPLv3.txt
#     else
#       echo "not creating distro zip as one already exists..."
#     fi
#   fi
#   echo "You will find redistributable archive .7z file in $archive.7z"
#   #fi

#   if [[ -z $ffmpeg_source_dir ]]; then
#     change_dir ..
#   else
#     change_dir "$work_dir" || exit
#   fi
# }
