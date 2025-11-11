#!/bin/bash

echo -e "INFO: Running windows/ffmpeg.sh\n" 1>>"${BASEDIR}"/build.log 2>&1

HOST_PKG_CONFIG_PATH=$(command -v pkg-config)
if [ -z "${HOST_PKG_CONFIG_PATH}" ]; then
  echo -e "\n(*) pkg-config command not found\n"
  exit 1
fi

LIB_NAME="ffmpeg"

echo -e "----------------------------------------------------------------" 1>>"${BASEDIR}"/build.log 2>&1
echo -e "\nINFO: Building ${LIB_NAME} for ${HOST} with the following environment variables\n" 1>>"${BASEDIR}"/build.log 2>&1
env 1>>"${BASEDIR}"/build.log 2>&1
echo -e "----------------------------------------------------------------\n" 1>>"${BASEDIR}"/build.log 2>&1
echo -e "INFO: System information\n" 1>>"${BASEDIR}"/build.log 2>&1
echo -e "INFO: $(uname -a)\n" 1>>"${BASEDIR}"/build.log 2>&1
echo -e "----------------------------------------------------------------\n" 1>>"${BASEDIR}"/build.log 2>&1

FFMPEG_LIBRARY_PATH="${LIB_INSTALL_BASE}/${LIB_NAME}"

# SET PATHS
set_toolchain_paths "${LIB_NAME}"

# SET BUILD FLAGS
HOST=$(get_host)
export CFLAGS=$(get_cflags "${LIB_NAME}")
export CXXFLAGS=$(get_cxxflags "${LIB_NAME}")
export LDFLAGS=$(get_ldflags "${LIB_NAME}")
export PKG_CONFIG_PATH="${INSTALL_PKG_CONFIG_DIR}:$(pkg-config --variable pc_path pkg-config)"

echo -e "\nINFO: Using PKG_CONFIG_PATH: ${PKG_CONFIG_PATH}\n" 1>>"${BASEDIR}"/build.log 2>&1

cd "${BASEDIR}"/prebuilt/src/"${LIB_NAME}" 1>>"${BASEDIR}"/build.log 2>&1 || return 1

# SET BUILD OPTIONS
TARGET_CPU=""
TARGET_ARCH=""
case ${ARCH} in
x86-64 | win64)
  TARGET_CPU="x86_64"
  TARGET_ARCH="x86_64"
  ;;
x86 | i686 | win32)
  TARGET_CPU="i686"
  TARGET_ARCH="x86"
  ;;
esac

CONFIGURE_POSTFIX=""
HIGH_PRIORITY_INCLUDES=""

# SET ENABLE GPL FLAG WHEN REQUESTED
if [ "$GPL_ENABLED" == "yes" ]; then
  CONFIGURE_POSTFIX+=" --enable-gpl"
fi

# ALWAYS BUILD SHARED LIBRARIES
BUILD_LIBRARY_OPTIONS="--disable-static --enable-shared"

# OPTIMIZE FOR SPEED INSTEAD OF SIZE
if [[ -z ${FFMPEG_KIT_OPTIMIZED_FOR_SPEED} ]]; then
  SIZE_OPTIONS="--enable-small"
else
  SIZE_OPTIONS=""
fi

# SET DEBUG OPTIONS
if [[ -z ${FFMPEG_KIT_DEBUG} ]]; then
  # SET LTO FLAGS
  if [[ -z ${NO_LINK_TIME_OPTIMIZATION} ]]; then
    DEBUG_OPTIONS="--disable-debug --enable-lto"
  else
    DEBUG_OPTIONS="--disable-debug --disable-lto"
  fi
else
  DEBUG_OPTIONS="--enable-debug --disable-stripping"
fi

echo -n -e "\n${LIB_NAME}: "

if [[ -z ${NO_WORKSPACE_CLEANUP_ffmpeg} ]]; then
  echo -e "INFO: Cleaning workspace for ${LIB_NAME}\n" 1>>"${BASEDIR}"/build.log 2>&1
  make distclean 2>/dev/null 1>/dev/null
fi

echo "INFO: Building FFMPEG with config:\n \
  --cross-prefix=$HOST-\n \
  --prefix=$FFMPEG_LIBRARY_PATH\n \
  --pkg-config=$HOST_PKG_CONFIG_PATH\n \
  --enable-version3\n \
  --arch=$TARGET_ARCH\n \
  --cpu=$TARGET_CPU\n \
  --target-os=mingw32\n \
  --ar=$AR\n \
  --cc=$CC\n \
  --cxx=$CXX\n \
  --ranlib=$RANLIB\n \
  --strip=$STRIP\n \
  --nm=$NM\n \
  --disable-autodetect\n \
  --enable-cross-compile\n \
  --enable-pic\n \
  --enable-optimizations\n \
  --enable-swscale\n \
  $BUILD_LIBRARY_OPTIONS\n \
  --enable-pthreads\n \
  --disable-v4l2-m2m\n \
  $SIZE_OPTIONS\n \
  --disable-xmm-clobber-test\n \
  $DEBUG_OPTIONS\n \
  --disable-doc\n \
  --disable-htmlpages\n \
  --disable-manpages\n \
  --disable-podpages\n \
  --disable-txtpages\n \
  $CONFIGURE_POSTFIX" 1>> $LOG_FILE 2>&1

  #--disable-postproc \
./configure \
  --cross-prefix="${HOST}-" \
  --prefix="${FFMPEG_LIBRARY_PATH}" \
  --pkg-config="${HOST_PKG_CONFIG_PATH}" \
  --enable-version3 \
  --arch="${TARGET_ARCH}" \
  --cpu="${TARGET_CPU}" \
  --target-os=mingw32 \
  --ar="${AR}" \
  --cc="${CC}" \
  --cxx="${CXX}" \
  --ranlib="${RANLIB}" \
  --strip="${STRIP}" \
  --nm="${NM}" \
  --disable-autodetect \
  --enable-cross-compile \
  --enable-pic \
  --enable-optimizations \
  --enable-swscale \
  --disable-static \
  --enable-shared \
  --enable-pthreads \
  --disable-v4l2-m2m \
  ${SIZE_OPTIONS} \
  --disable-xmm-clobber-test \
  ${DEBUG_OPTIONS} \
  --disable-doc \
  --disable-htmlpages \
  --disable-manpages \
  --disable-podpages \
  --disable-txtpages \
  ${CONFIGURE_POSTFIX} 1>>"${BASEDIR}"/build.log 2>&1

if [[ $? -ne 0 ]]; then
  echo -e "failed\n\nSee build.log for details\n"
  exit 1
fi

if [[ -z ${NO_OUTPUT_REDIRECTION} ]]; then
  make -j$(get_cpu_count) 1>>"${BASEDIR}"/build.log 2>&1

  if [[ $? -ne 0 ]]; then
    echo -e "failed\n\nSee build.log for details\n"
    exit 1
  fi
else
  echo -e "started\n"
  make -j$(get_cpu_count)

  if [[ $? -ne 0 ]]; then
    echo -n -e "\n${LIB_NAME}: failed\n\nSee build.log for details\n"
    exit 1
  else
    echo -n -e "\n${LIB_NAME}: "
  fi
fi

# DELETE THE PREVIOUS BUILD OF THE LIBRARY BEFORE INSTALLING
if [ -d "${FFMPEG_LIBRARY_PATH}" ]; then
  rm -rf "${FFMPEG_LIBRARY_PATH}" 1>>"${BASEDIR}"/build.log 2>&1 || return 1
fi
make install 1>>"${BASEDIR}"/build.log 2>&1

if [[ $? -ne 0 ]]; then
  echo -e "failed\n\nSee build.log for details\n"
  exit 1
fi

# MANUALLY COPY PKG-CONFIG FILES
overwrite_file "${FFMPEG_LIBRARY_PATH}"/lib/pkgconfig/libavformat.pc "${INSTALL_PKG_CONFIG_DIR}/libavformat.pc" || return 1
overwrite_file "${FFMPEG_LIBRARY_PATH}"/lib/pkgconfig/libswresample.pc "${INSTALL_PKG_CONFIG_DIR}/libswresample.pc" || return 1
overwrite_file "${FFMPEG_LIBRARY_PATH}"/lib/pkgconfig/libswscale.pc "${INSTALL_PKG_CONFIG_DIR}/libswscale.pc" || return 1
overwrite_file "${FFMPEG_LIBRARY_PATH}"/lib/pkgconfig/libavdevice.pc "${INSTALL_PKG_CONFIG_DIR}/libavdevice.pc" || return 1
overwrite_file "${FFMPEG_LIBRARY_PATH}"/lib/pkgconfig/libavfilter.pc "${INSTALL_PKG_CONFIG_DIR}/libavfilter.pc" || return 1
overwrite_file "${FFMPEG_LIBRARY_PATH}"/lib/pkgconfig/libavcodec.pc "${INSTALL_PKG_CONFIG_DIR}/libavcodec.pc" || return 1
overwrite_file "${FFMPEG_LIBRARY_PATH}"/lib/pkgconfig/libavutil.pc "${INSTALL_PKG_CONFIG_DIR}/libavutil.pc" || return 1

# MANUALLY ADD REQUIRED HEADERS
mkdir -p "${FFMPEG_LIBRARY_PATH}"/include/libavutil/x86 1>>"${BASEDIR}"/build.log 2>&1
mkdir -p "${FFMPEG_LIBRARY_PATH}"/include/libavutil/arm 1>>"${BASEDIR}"/build.log 2>&1
mkdir -p "${FFMPEG_LIBRARY_PATH}"/include/libavutil/aarch64 1>>"${BASEDIR}"/build.log 2>&1
mkdir -p "${FFMPEG_LIBRARY_PATH}"/include/libavcodec/x86 1>>"${BASEDIR}"/build.log 2>&1
mkdir -p "${FFMPEG_LIBRARY_PATH}"/include/libavcodec/arm 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/config.h "${FFMPEG_LIBRARY_PATH}"/include/config.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavcodec/mathops.h "${FFMPEG_LIBRARY_PATH}"/include/libavcodec/mathops.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavcodec/x86/mathops.h "${FFMPEG_LIBRARY_PATH}"/include/libavcodec/x86/mathops.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavcodec/arm/mathops.h "${FFMPEG_LIBRARY_PATH}"/include/libavcodec/arm/mathops.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavformat/network.h "${FFMPEG_LIBRARY_PATH}"/include/libavformat/network.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavformat/os_support.h "${FFMPEG_LIBRARY_PATH}"/include/libavformat/os_support.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavformat/url.h "${FFMPEG_LIBRARY_PATH}"/include/libavformat/url.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/attributes_internal.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/attributes_internal.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/bprint.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/bprint.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/getenv_utf8.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/getenv_utf8.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/internal.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/internal.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/libm.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/libm.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/reverse.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/reverse.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/thread.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/thread.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/timer.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/timer.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/x86/asm.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/x86/asm.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/x86/timer.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/x86/timer.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/arm/timer.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/arm/timer.h 1>>"${BASEDIR}"/build.log 2>&1
overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/aarch64/timer.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/aarch64/timer.h 1>>"${BASEDIR}"/build.log 2>&1

if [ $? -eq 0 ]; then
  echo "ok"
else
  echo -e "failed\n\nSee build.log for details\n"
  exit 1
fi