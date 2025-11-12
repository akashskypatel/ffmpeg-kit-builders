#!/bin/bash

echo -e "INFO: Running windows/ffmpeg.sh\n" 1>>"${BASEDIR}"/build.log 2>&1

echo -e "----------------------------------------------------------------" 1>>"${BASEDIR}"/build.log 2>&1
echo -e "\nINFO: Building ${LIB_NAME} for ${HOST} with the following environment variables\n" 1>>"${BASEDIR}"/build.log 2>&1
env 1>>"${BASEDIR}"/build.log 2>&1
echo -e "----------------------------------------------------------------\n" 1>>"${BASEDIR}"/build.log 2>&1
echo -e "INFO: System information\n" 1>>"${BASEDIR}"/build.log 2>&1
echo -e "INFO: $(uname -a)\n" 1>>"${BASEDIR}"/build.log 2>&1
echo -e "----------------------------------------------------------------\n" 1>>"${BASEDIR}"/build.log 2>&1


if [[ $? -ne 0 ]]; then
  echo -e "failed\n\nSee build.log for details\n"
  exit 1
fi

# MANUALLY COPY PKG-CONFIG FILES
overwrite_file "${install_prefix}"/lib/pkgconfig/libavformat.pc "${INSTALL_PKG_CONFIG_DIR}/libavformat.pc" || return 1
overwrite_file "${install_prefix}"/lib/pkgconfig/libswresample.pc "${INSTALL_PKG_CONFIG_DIR}/libswresample.pc" || return 1
overwrite_file "${install_prefix}"/lib/pkgconfig/libswscale.pc "${INSTALL_PKG_CONFIG_DIR}/libswscale.pc" || return 1
overwrite_file "${install_prefix}"/lib/pkgconfig/libavdevice.pc "${INSTALL_PKG_CONFIG_DIR}/libavdevice.pc" || return 1
overwrite_file "${install_prefix}"/lib/pkgconfig/libavfilter.pc "${INSTALL_PKG_CONFIG_DIR}/libavfilter.pc" || return 1
overwrite_file "${install_prefix}"/lib/pkgconfig/libavcodec.pc "${INSTALL_PKG_CONFIG_DIR}/libavcodec.pc" || return 1
overwrite_file "${install_prefix}"/lib/pkgconfig/libavutil.pc "${INSTALL_PKG_CONFIG_DIR}/libavutil.pc" || return 1

# # MANUALLY ADD REQUIRED HEADERS
# mkdir -p "${install_prefix}"/include/libavutil/x86 1>>"${BASEDIR}"/build.log 2>&1
# mkdir -p "${install_prefix}"/include/libavutil/arm 1>>"${BASEDIR}"/build.log 2>&1
# mkdir -p "${install_prefix}"/include/libavutil/aarch64 1>>"${BASEDIR}"/build.log 2>&1
# mkdir -p "${install_prefix}"/include/libavcodec/x86 1>>"${BASEDIR}"/build.log 2>&1
# mkdir -p "${install_prefix}"/include/libavcodec/arm 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/config.h "${install_prefix}"/include/config.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavcodec/mathops.h "${install_prefix}"/include/libavcodec/mathops.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavcodec/x86/mathops.h "${install_prefix}"/include/libavcodec/x86/mathops.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavcodec/arm/mathops.h "${install_prefix}"/include/libavcodec/arm/mathops.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavformat/network.h "${install_prefix}"/include/libavformat/network.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavformat/os_support.h "${install_prefix}"/include/libavformat/os_support.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavformat/url.h "${install_prefix}"/include/libavformat/url.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/attributes_internal.h "${install_prefix}"/include/libavutil/attributes_internal.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/bprint.h "${install_prefix}"/include/libavutil/bprint.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/getenv_utf8.h "${install_prefix}"/include/libavutil/getenv_utf8.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/internal.h "${install_prefix}"/include/libavutil/internal.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/libm.h "${install_prefix}"/include/libavutil/libm.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/reverse.h "${install_prefix}"/include/libavutil/reverse.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/thread.h "${install_prefix}"/include/libavutil/thread.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/timer.h "${install_prefix}"/include/libavutil/timer.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/x86/asm.h "${install_prefix}"/include/libavutil/x86/asm.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/x86/timer.h "${install_prefix}"/include/libavutil/x86/timer.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/arm/timer.h "${install_prefix}"/include/libavutil/arm/timer.h 1>>"${BASEDIR}"/build.log 2>&1
# overwrite_file "${BASEDIR}"/prebuilt/src/ffmpeg/libavutil/aarch64/timer.h "${install_prefix}"/include/libavutil/aarch64/timer.h 1>>"${BASEDIR}"/build.log 2>&1

# if [ $? -eq 0 ]; then
#   echo "ok"
# else
#   echo -e "failed\n\nSee build.log for details\n"
#   exit 1
# fi