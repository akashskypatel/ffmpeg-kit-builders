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

# DIRECTORY DEFINITIONS
export FFMPEG_KIT_TMPDIR="${BASEDIR}/.tmp"

export MINGW_W64_BRANCH="master"
export BINUTILS_BRANCH="binutils-2_44-branch"
export GCC_BRANCH="releases/gcc-14"

# variables with their defaults
export build_cross_compile=n
export build_force=n
export force_kit=n
export force_ffmpeg=n
export build_dvbtee=n
export build_libmxf=n
export build_mp4box=n
export build_mplayer=n
export build_vlc=n
export build_lsw=n # To build x264 with L-Smash-Works.
export build_dependencies=n
export build_ffmpeg_type=static
export do_build_ffmpeg=n
export build_ffmpeg_kit_type=shared
export do_build_ffmpeg_kit=n
export build_tests=n
export skip_validation=n
export skip_package_check=n
export create_bundle=y
export git_get_latest=n
export prefer_stable=y # Only for x264 and x265.
export build_amd_amf=y
export ffmpeg_git_checkout_version="release/9.0"
export build_ismindex=n
export build_gpl=n
export build_nonfree=n
export original_cflags="$CFLAGS -ffunction-sections -fdata-sections -fstrict-aliasing -fPIC"
export original_cxxflags="$CXXFLAGS -ffunction-sections -fdata-sections -fPIC"
export original_cppflags="$CPPFLAGS"
export original_ldflags=""
export build_x264_with_libav=n # To build x264 with Libavformat.
export ffmpeg_git_checkout="https://github.com/FFmpeg/FFmpeg.git"
if [[ "$(uname)" == "Darwin" ]]; then
  export cpu_count=$(sysctl -n hw.ncpu)
else
  export cpu_count=$(nproc)
fi
export original_cpu_count=$cpu_count # save it away for some that revert it temporarily
export PKG_CONFIG_LIBDIR= # disable pkg-config from finding [and using] normal linux system installed libs [yikes]
export original_path=$PATH:$HOME/.local/bin:/usr/local/cargo/bin
export license_dir_list=()
export extra_ffmpeg_c_flags=""

declare -A seen_steps
declare -A INSTALLED_LIBS
declare -A BUILD_STEPS

export OPTIMIZED_BUILD_STEPS=()

# AI Video Focused
CONFIG_VIDEO_AI="\
--enable-libopencv \
--enable-libopenvino \
--enable-libquirc \
--enable-libtensorflow \
--enable-libtesseract \
--enable-libonnxruntime \
--enable-libtorch"

# AI Audio Focused
CONFIG_AUDIO_AI="\
--enable-pocketsphinx \
--enable-whisper"

CONFIG_LINUX="\
--enable-openssl \
--enable-alsa"

# Android general
CONFIG_ANDROID=" \
--enable-jni \
--enable-openssl \
--enable-mediacodec"

CONFIG_WINDOWS="\
--enable-d3d11va \
--enable-d3d12va \
--enable-dxva2 \
--enable-schannel \
--enable-mediafoundation"

CONFIG_OPENHARMONY="\
--enable-openssl \
--enable-ohcodec"

CONFIG_MACOS="\
--enable-appkit"

# Apple general
CONFIG_APPLE="\
--enable-avfoundation \
--enable-audiotoolbox \
--enable-coreimage \
--enable-metal \
--enable-securetransport \
--enable-videotoolbox"

# General libraries
CONFIG_GENERAL="\
--enable-bzlib \
--enable-iconv \
--enable-lzma \
--enable-zlib"

CONFIG_BASE="--enable-libjsoncpp \
--enable-sdl2"

# must pick crypto type for streaming support
CONFIG_STREAMING="\
--enable-libsrt \
--enable-librist \
--enable-librtmp"

# pick_crypto_type
CONFIG_CRYPTO="\
--enable-gcrypt \
--enable-gmp"

# must pick ssl type for https support
# pick_ssl_type
CONFIG_TLS="\
--enable-gnutls \
--enable-libtls \
--enable-mbedtls \
--enable-openssl \
--enable-schannel \
--enable-securetransport"

# Cross-Platform Audio Focused (Codecs + LADSPA)
CONFIG_AUDIO="\
--enable-alsa \
--enable-libbs2b \
--enable-libcodec2 \
--enable-libgsm \
--enable-libilbc \
--enable-liblc3 \
--enable-libmodplug \
--enable-libmp3lame \
--enable-libopencore-amrnb \
--enable-libopencore-amrwb \
--enable-libopenmpt \
--enable-libopus \
--enable-libsoxr \
--enable-libspeex \
--enable-libtwolame \
--enable-libvo-amrwbenc \
--enable-libvorbis \
--enable-openal"

CONFIG_AUDIO_EXTRA="\
--enable-chromaprint \
--enable-ladspa \
--enable-libcdio \
--enable-libflite \
--enable-libgme \
--enable-libjack \
--enable-libmysofa \
--enable-libpulse \
--enable-librubberband \
--enable-libshine \
--enable-lv2 \
--enable-sndio"

# Cross-Platform Audio Focused NON-FREE
CONFIG_AUDIO_NON_FREE="\
--enable-libfdk-aac \
--enable-libmpeghdec \
--enable-audiotoolbox"

# Cross-platform Video Focused
CONFIG_VIDEO="\
--enable-sdl2 \
--enable-lcms2 \
--enable-libaom \
--enable-libaribb24 \
--enable-libaribcaption \
--enable-libass \
--enable-libbluray \
--enable-libcaca \
--enable-libdav1d \
--enable-libdavs2 \
--enable-libdc1394 \
--enable-libdvdnav \
--enable-libdvdread \
--enable-libfontconfig \
--enable-libfreetype \
--enable-libfribidi \
--enable-libharfbuzz \
--enable-libiec61883 \
--enable-libjxl \
--enable-libkvazaar \
--enable-liblcevc-dec \
--enable-liboapv \
--enable-libopenh264 \
--enable-libopenjpeg \
--enable-libsvtjpegxs \
--enable-libopencolorio \
--enable-librav1e \
--enable-librsvg \
--enable-libsnappy \
--enable-libsvtav1 \
--enable-libtheora \
--enable-libuavs3d \
--enable-libvpx \
--enable-libvvenc \
--enable-libwebp \
--enable-libx264 \
--enable-libx265 \
--enable-libxavs \
--enable-libxavs2 \
--enable-libxevd \
--enable-libxeve \
--enable-libxvid \
--enable-libzimg \
--enable-libzvbi \
--enable-libxml2"

CONFIG_VIDEO_EXTRA="\
--enable-avisynth \
--enable-frei0r \
--enable-libklvanc \
--enable-liblensfun \
--enable-libqrencode \
--enable-libv4l2 \
--enable-libvidstab \
--enable-libvmaf \
--enable-libxcb \
--enable-libxcb-shape \
--enable-libxcb-shm \
--enable-libxcb-xfixes \
--enable-vapoursynth \
--enable-xlib"

# Cross-platform Video Focused NON-FREE
CONFIG_VIDEO_EXTRA_NON_FREE="--enable-decklink"

# Hardware Accel Video Focused
CONFIG_HARDWARE="\
--enable-amf \
--enable-libmfx \
--enable-libplacebo \
--enable-libvpl \
--enable-ohcodec \
--enable-opencl \
--enable-opengl \
--enable-vulkan \
--enable-vdpau \
--enable-ffnvcodec \
--enable-cuda-llvm \
--enable-cuvid \
--enable-nvdec \
--enable-nvenc \
--enable-libdrm \
--enable-vaapi \
--enable-mediacodec \
--enable-rkmpp \
--enable-v4l2-m2m \
--enable-vulkan-static"

# Hardware Accel Video Focused NON-FREE
CONFIG_HARDWARE_NON_FREE="\
--enable-coreimage \
--enable-d3d11va \
--enable-d3d12va \
--enable-dxva2 \
--enable-mediafoundation \
--enable-metal \
--enable-mmal \
--enable-cuda-nvcc \
--enable-videotoolbox"

# other advanced config options
CONFIG_MQ="\
--enable-librabbitmq \
--enable-libzmq"

CONFIG_SMB="--enable-libsmbclient"

CONFIG_SSH="--enable-libssh"

CONFIG_GPL="\
--enable-libx264 \
--enable-libx265 \
--enable-libxvid \
--enable-frei0r \
--enable-libdvdread \
--enable-v4l2-m2m \
--enable-avisynth \
--enable-libjack \
--enable-libbs2b \
--enable-libcdio \
--enable-libdvdnav \
--enable-librubberband \
--enable-libsmbclient \
--enable-libvidstab \
--enable-libdavs2 \
--enable-libxavs \
--enable-libxavs2 \
--enable-libaribb24"

CONFIG_AUTODETECT="\
--disable-alsa \
--disable-libdc1394 \
--disable-libdrm \
--disable-libxcb-shape \
--disable-libxcb-shm \
--disable-libxcb-xfixes \
--disable-cuda-llvm \
--disable-v4l2-m2m \
--disable-libxcb \
--disable-vaapi \
--disable-xlib \
--disable-amf \
--disable-vulkan \
--disable-bzlib \
--disable-iconv \
--disable-lzma \
--disable-sdl2 \
--disable-sndio \
--disable-zlib \
--disable-cuvid \
--disable-ffnvcodec \
--disable-nvdec \
--disable-nvenc \
--disable-vdpau \
--disable-d3d11va \
--disable-d3d12va \
--disable-dxva2 \
--disable-schannel \
--disable-mediafoundation \
--disable-avfoundation \
--disable-appkit \
--disable-audiotoolbox \
--disable-coreimage \
--disable-metal \
--disable-securetransport \
--disable-videotoolbox \
--disable-ohcodec"

CONFIG_WINDOWS_UNSUPPORTED="\
--disable-alsa \
--disable-libdc1394 \
--disable-libdrm \
--disable-libiec61883 \
--disable-libv4l2 \
--disable-libxcb-shape \
--disable-libxcb-shm \
--disable-libxcb-xfixes \
--disable-libxcb \
--disable-rkmpp \
--disable-libdrm \
--disable-v4l2-m2m \
--disable-vaapi \
--disable-xlib \
--disable-sndio \
--disable-ladspa \
--disable-libxvid \
--disable-libpulse \
--disable-libjack \
--disable-vdpau \
--disable-jni \
--disable-mediacodec \
--disable-appkit \
--disable-avfoundation \
--disable-audiotoolbox \
--disable-coreimage \
--disable-metal \
--disable-securetransport \
--disable-videotoolbox \
--disable-libtorch \
--disable-cuda-nvcc \
--disable-libsmbclient \
--disable-mmal \
--disable-ohcodec"

CONFIG_LINUX_UNSUPPORTED="\
--disable-jni \
--disable-mediacodec \
--disable-d3d11va \
--disable-d3d12va \
--disable-dxva2 \
--disable-schannel \
--disable-mediafoundation \
--disable-appkit \
--disable-avfoundation \
--disable-audiotoolbox \
--disable-coreimage \
--disable-metal \
--disable-securetransport \
--disable-videotoolbox \
--disable-cuda-llvm \
--disable-mmal \
--disable-ohcodec"

CONFIG_MACOS_UNSUPPORTED="\
--disable-alsa \
--disable-libdc1394 \
--disable-libdrm \
--disable-libiec61883 \
--disable-libv4l2 \
--disable-libxcb-shape \
--disable-libxcb-shm \
--disable-libxcb-xfixes \
--disable-libxcb \
--disable-rkmpp \
--disable-libdrm \
--disable-v4l2-m2m \
--disable-vaapi \
--disable-xlib \
--disable-sndio \
--disable-ladspa \
--disable-libxvid \
--disable-libpulse \
--disable-libjack \
--disable-vdpau \
--disable-jni \
--disable-mediacodec \
--disable-d3d11va \
--disable-d3d12va \
--disable-dxva2 \
--disable-schannel \
--disable-mediafoundation \
--disable-libvpl \
--disable-ffnvcodec \
--disable-nvdec \
--disable-nvenc \
--disable-cuvid \
--disable-cuda-nvcc \
--disable-cuda-llvm \
--disable-mmal \
--disable-ohcodec"

CONFIG_TVOS_UNSUPPORTED="\
--disable-alsa \
--disable-libdc1394 \
--disable-libdrm \
--disable-libiec61883 \
--disable-libv4l2 \
--disable-libxcb-shape \
--disable-libxcb-shm \
--disable-libxcb-xfixes \
--disable-libxcb \
--disable-rkmpp \
--disable-libdrm \
--disable-v4l2-m2m \
--disable-vaapi \
--disable-xlib \
--disable-sndio \
--disable-ladspa \
--disable-libxvid \
--disable-libpulse \
--disable-libjack \
--disable-vdpau \
--disable-frei0r \
--disable-liblensfun \
--disable-librsvg \
--disable-pocketsphinx \
--disable-jni \
--disable-mediacodec \
--disable-d3d11va \
--disable-d3d12va \
--disable-dxva2 \
--disable-schannel \
--disable-mediafoundation \
--disable-appkit \
--disable-libvpl \
--disable-cuvid \
--disable-ffnvcodec \
--disable-nvdec \
--disable-nvenc \
--disable-cuvid \
--disable-libtorch \
--disable-libopenvino \
--disable-libtensorflow \
--disable-cuda-nvcc \
--disable-cuda-llvm \
--disable-avisynth \
--disable-libsmbclient \
--disable-libbluray \
--disable-libcdio \
--disable-libdvdnav \
--disable-libdvdread \
--disable-libsvtjpegxs \
--disable-mmal \
--disable-libonnxruntime \
--disable-ohcodec"

CONFIG_IOS_UNSUPPORTED="\
--disable-alsa \
--disable-libdc1394 \
--disable-libdrm \
--disable-libiec61883 \
--disable-libv4l2 \
--disable-libxcb-shape \
--disable-libxcb-shm \
--disable-libxcb-xfixes \
--disable-libxcb \
--disable-rkmpp \
--disable-libdrm \
--disable-v4l2-m2m \
--disable-vaapi \
--disable-xlib \
--disable-sndio \
--disable-ladspa \
--disable-libxvid \
--disable-libpulse \
--disable-libjack \
--disable-vdpau \
--disable-jni \
--disable-mediacodec \
--disable-d3d11va \
--disable-d3d12va \
--disable-dxva2 \
--disable-schannel \
--disable-mediafoundation \
--disable-appkit \
--disable-libvpl \
--disable-ffnvcodec \
--disable-nvdec \
--disable-nvenc \
--disable-cuvid \
--disable-libtorch \
--disable-libopenvino \
--disable-libtensorflow \
--disable-cuda-nvcc \
--disable-cuda-llvm \
--disable-avisynth \
--disable-libsmbclient \
--disable-libbluray \
--disable-libcdio \
--disable-libdvdnav \
--disable-libdvdread \
--disable-libsvtjpegxs \
--disable-mmal \
--disable-libonnxruntime \
--disable-ohcodec"

CONFIG_ANDROID_UNSUPPORTED="\
--disable-alsa \
--disable-libdc1394 \
--disable-libdrm \
--disable-libiec61883 \
--disable-libv4l2 \
--disable-libxcb-shape \
--disable-libxcb-shm \
--disable-libxcb-xfixes \
--disable-libxcb \
--disable-rkmpp \
--disable-libdrm \
--disable-v4l2-m2m \
--disable-vaapi \
--disable-xlib \
--disable-sndio \
--disable-ladspa \
--disable-libxvid \
--disable-libpulse \
--disable-libjack \
--disable-vdpau \
--disable-d3d11va \
--disable-d3d12va \
--disable-dxva2 \
--disable-schannel \
--disable-mediafoundation \
--disable-appkit \
--disable-avfoundation \
--disable-audiotoolbox \
--disable-coreimage \
--disable-metal \
--disable-securetransport \
--disable-videotoolbox \
--disable-ffnvcodec \
--disable-nvdec \
--disable-nvenc \
--disable-cuvid \
--disable-libtorch \
--disable-libopenvino \
--disable-libtensorflow \
--disable-cuda-nvcc \
--disable-cuda-llvm \
--disable-avisynth \
--disable-libsmbclient \
--disable-libbluray \
--disable-libcdio \
--disable-libdvdnav \
--disable-libdvdread \
--disable-mmal \
--disable-libonnxruntime \
--disable-ohcodec"

CONFIG_WASM_UNSUPPORTED="\
--disable-libtorch \
--disable-libopenvino \
--disable-libtensorflow \
--disable-libonnxruntime \
--disable-opencl \
--disable-cuda-nvcc \
--disable-cuda-llvm \
--disable-ffnvcodec \
--disable-nvdec \
--disable-nvenc \
--disable-cuvid \
--disable-alsa \
--disable-jni \
--disable-mediacodec \
--disable-d3d11va \
--disable-d3d12va \
--disable-dxva2 \
--disable-schannel \
--disable-mediafoundation \
--disable-ohcodec \
--disable-appkit \
--disable-avfoundation \
--disable-audiotoolbox \
--disable-coreimage \
--disable-metal \
--disable-securetransport \
--disable-videotoolbox \
--disable-libdc1394 \
--disable-libdrm \
--disable-libiec61883 \
--disable-libv4l2 \
--disable-libxcb-shape \
--disable-libxcb-shm \
--disable-libxcb-xfixes \
--disable-libxcb \
--disable-rkmpp \
--disable-v4l2-m2m \
--disable-vaapi \
--disable-xlib \
--disable-sndio \
--disable-libxvid \
--disable-libpulse \
--disable-libjack \
--disable-vdpau \
--disable-mmal \
--disable-opencl \
--disable-ladspa \
--disable-opengl \
--disable-alsa \
--disable-libsrt \
--disable-libasound2 \
--disable-libvpl \
--disable-libsvtav1 \
--disable-amf \
--disable-libsvtjpegxs"

# build_jni               # config_options+= --disable-jni                # System # enable JNI support [no]
# build_mediacodec        # config_options+= --disable-mediacodec         # Video  # enable Android MediaCodec support [no]
# build_ohcodec           # config_options+= --disable-ohcodec            # Video  # enable OpenHarmony Codec support [no]
# build_alsa              # config_options+= --disable-alsa               # Audio  # disable ALSA support [autodetect]
# build_libdc1394         # config_options+= --enable-libdc1394           # Video  # enable IIDC-1394 grabbing using libdc1394 and libraw1394 [no]
# build_libdrm            # config_options+= --disable-libdrm             # Video  # disable DRM code (Linux) [autodetect]
# build_libiec61883       # config_options+= --enable-libiec61883         # Video  # enable iec61883 via libiec61883 [no]
# build_libv4l2           # config_options+= --enable-libv4l2             # Video  # enable libv4l2/v4l-utils [no]
# build_libxcb_shape      # config_options+= --enable-libxcb-shape        # Video  # enable X11 grabbing shape rendering [autodetect]
# build_libxcb_shm        # config_options+= --enable-libxcb-shm          # Video  # enable X11 grabbing shm communication [autodetect]
# build_libxcb_xfixes     # config_options+= --enable-libxcb-xfixes       # Video  # enable X11 grabbing mouse rendering [autodetect]
# build_libxcb            # config_options+= --enable-libxcb              # Video  # enable X11 grabbing using XCB [autodetect]
# build_rkmpp             # config_options+= --enable-rkmpp               # Video  # enable Rockchip Media Process Platform code [no]
# build_v4l2_m2m          # config_options+= --disable-v4l2-m2m           # Video  # disable V4L2 mem2mem code [autodetect]
# build_vaapi             # config_options+= --disable-vaapi              # Video  # disable Video Acceleration API (mainly Unix/Intel) code [autodetect]
# build_xlib              # config_options+= --disable-xlib               # Video  # disable xlib [autodetect]
# build_ladspa            # config_options+= --disable-ladspa             # Audio  # enable LADSPA audio filtering [no]
# build_amf               # config_options+= --disable-amf                # Video  # disable AMF video encoding code [autodetect]
# build_vulkan            # config_options+= --disable-vulkan             # Video  # disable Vulkan code [autodetect]
# build_libmfx            # config_options+= --enable-libmfx              # Video  # enable Intel MediaSDK (AKA Quick Sync Video) code via libmfx [no]
# build_libvpl            # config_options+= --enable-libvpl              # Video  # enable Intel oneVPL code via libvpl if libmfx is not used [no]
# build_vulkan_static     # config_options+= --enable-vulkan-static       # Video  # enable statically link to libvulkan [no]
# build_avisynth          # config_options+= --enable-avisynth            # Video  # enable reading of AviSynth script files [no]
# build_bzlib             # config_options+= --disable-bzlib              # System # disable bzlib [autodetect]
# build_iconv             # config_options+= --disable-iconv              # System # disable iconv [autodetect]
# build_lzma              # config_options+= --disable-lzma               # System # disable lzma [autodetect]
# build_sdl2              # config_options+= --disable-sdl2               # Video  # disable sdl2 [autodetect]
# build_sndio             # config_options+= --disable-sndio              # Audio  # disable sndio support [autodetect]
# build_zlib              # config_options+= --disable-zlib               # System # disable zlib [autodetect]
# build_libvo_amrwbenc    # config_options+= --enable-libvo-amrwbenc      # Audio  # enable AMR-WB encoding via libvo-amrwbenc [no]
# build_libopencore_amrnb # config_options+= --enable-libopencore-amrnb   # Audio  # enable AMR-NB de/encoding via libopencore-amrnb [no]
# build_libopencore_amrwb # config_options+= --enable-libopencore-amrwb   # Audio  # enable AMR-WB decoding via libopencore-amrwb [no]
# build_liblcevc_dec      # config_options+= --enable-liblcevc-dec        # Video  # enable LCEVC decoding via liblcevc-dec [no]
# build_chromaprint       # config_options+= --enable-chromaprint         # Audio  # enable audio fingerprinting with chromaprint [no]
# build_frei0r            # config_options+= --enable-frei0r              # Video  # enable frei0r video filtering [no]
# build_gcrypt            # config_options+= --enable-gcrypt              # System # enable gcrypt, needed for rtmp(t)e support if openssl, librtmp or gmp is not used [no]
# build_gmp               # config_options+= --enable-gmp                 # System # enable gmp, needed for rtmp(t)e support if openssl or librtmp is not used [no]
# build_gnutls            # config_options+= --enable-gnutls              # System # enable gnutls, needed for https support if openssl, libtls or mbedtls is not used [no]
# build_lcms2             # config_options+= --enable-lcms2               # Video  # enable ICC profile support via LittleCMS 2 [no]
# build_libaom            # config_options+= --enable-libaom              # Video  # enable AV1 video encoding/decoding via libaom [no]
# build_libaribb24        # config_options+= --enable-libaribb24          # Video  # enable ARIB text and caption decoding via libaribb24 [no]
# build_libaribcaption    # config_options+= --enable-libaribcaption      # Video  # enable ARIB text and caption decoding via libaribcaption [no]
# build_libass            # config_options+= --enable-libass              # Video  # enable libass subtitles rendering, needed for subtitles and ass filter [no]
# build_libbluray         # config_options+= --enable-libbluray           # Video  # enable BluRay reading using libbluray [no]
# build_libbs2b           # config_options+= --enable-libbs2b             # Audio  # enable bs2b DSP library [no]
# build_libcaca           # config_options+= --enable-libcaca             # Video  # enable textual display using libcaca [no]
# build_libcdio           # config_options+= --enable-libcdio             # Audio  # enable audio CD grabbing with libcdio [no]
# build_libcodec2         # config_options+= --enable-libcodec2           # Audio  # enable codec2 en/decoding using libcodec2 [no]
# build_libdav1d          # config_options+= --enable-libdav1d            # Video  # enable AV1 decoding via libdav1d [no]
# build_libdavs2          # config_options+= --enable-libdavs2            # Video  # enable AVS2 decoding via libdavs2 [no]
# build_libdvdnav         # config_options+= --enable-libdvdnav           # Video  # enable libdvdnav, needed for DVD demuxing [no]
# build_libdvdread        # config_options+= --enable-libdvdread          # Video  # enable libdvdread, needed for DVD demuxing [no]
# build_libflite          # config_options+= --enable-libflite            # Audio  # enable flite (voice synthesis) support via libflite [no]
# build_libfontconfig     # config_options+= --enable-libfontconfig       # Video  # enable libfontconfig, useful for drawtext filter [no]
# build_libfreetype       # config_options+= --enable-libfreetype         # Video  # enable libfreetype, needed for drawtext filter [no]
# build_libfribidi        # config_options+= --enable-libfribidi          # Video  # enable libfribidi, improves drawtext filter [no]
# build_libgme            # config_options+= --enable-libgme              # Audio  # enable Game Music Emu via libgme [no]
# build_libgsm            # config_options+= --enable-libgsm              # Audio  # enable GSM de/encoding via libgsm [no]
# build_libharfbuzz       # config_options+= --enable-libharfbuzz         # Video  # enable libharfbuzz, needed for drawtext filter [no]
# build_libilbc           # config_options+= --enable-libilbc             # Audio  # enable iLBC de/encoding via libilbc [no]
# build_libjack           # config_options+= --enable-libjack             # Audio  # enable JACK audio sound server [no]
# build_libjxl            # config_options+= --enable-libjxl              # Video  # enable JPEG XL de/encoding via libjxl [no]
# build_libklvanc         # config_options+= --enable-libklvanc           # Video  # enable Kernel Labs VANC processing [no]
# build_libkvazaar        # config_options+= --enable-libkvazaar          # Video  # enable HEVC encoding via libkvazaar [no]
# build_liblc3            # config_options+= --enable-liblc3              # Audio  # enable LC3 de/encoding via liblc3 [no]
# build_liblensfun        # config_options+= --enable-liblensfun          # Video  # enable lensfun lens correction [no]
# build_libmodplug        # config_options+= --enable-libmodplug          # Audio  # enable ModPlug via libmodplug [no]
# build_libmp3lame        # config_options+= --enable-libmp3lame          # Audio  # enable MP3 encoding via libmp3lame [no]
# build_libmysofa         # config_options+= --enable-libmysofa           # Audio  # enable libmysofa, needed for sofalizer filter [no]
# build_liboapv           # config_options+= --enable-liboapv             # Video  # enable APV encoding via liboapv [no]
# build_libopencv         # config_options+= --enable-libopencv           # Video  # enable video filtering via libopencv [no]
# build_libopenh264       # config_options+= --enable-libopenh264         # Video  # enable H.264 encoding via OpenH264 [no]
# build_libopenjpeg       # config_options+= --enable-libopenjpeg         # Video  # enable JPEG 2000 encoding via OpenJPEG [no]
# build_libopenmpt        # config_options+= --enable-libopenmpt          # Audio  # enable decoding tracked files via libopenmpt [no]
# build_libopenvino       # config_options+= --enable-libopenvino         # Video  # enable OpenVINO as a DNN module backend for DNN based filters like dnn_processing [no]
# build_libopus           # config_options+= --enable-libopus             # Audio  # enable Opus de/encoding via libopus [no]
# build_libplacebo        # config_options+= --enable-libplacebo          # Video  # enable libplacebo library [no]
# build_libpulse          # config_options+= --enable-libpulse            # Audio  # enable Pulseaudio input via libpulse [no]
# build_libqrencode       # config_options+= --enable-libqrencode         # Video  # enable QR encode generation via libqrencode [no]
# build_libquirc          # config_options+= --enable-libquirc            # Video  # enable QR decoding via libquirc [no]
# build_librabbitmq       # config_options+= --enable-librabbitmq         # System # enable RabbitMQ library [no]
# build_librav1e          # config_options+= --enable-librav1e            # Video  # enable AV1 encoding via rav1e [no]
# build_librist           # config_options+= --enable-librist             # System # enable RIST via librist [no]
# build_librsvg           # config_options+= --enable-librsvg             # Video  # enable SVG rasterization via librsvg [no]
# build_librtmp           # config_options+= --enable-librtmp             # System # enable RTMP[E] support via librtmp [no]
# build_librubberband     # config_options+= --enable-librubberband       # Audio  # enable rubberband needed for rubberband filter [no]
# build_libshine          # config_options+= --enable-libshine            # Audio  # enable fixed-point MP3 encoding via libshine [no]
# build_libsmbclient      # config_options+= --enable-libsmbclient        # System # enable Samba protocol via libsmbclient [no]
# build_libsnappy         # config_options+= --enable-libsnappy           # System # enable Snappy compression, needed for hap encoding [no]
# build_libsoxr           # config_options+= --enable-libsoxr             # Audio  # enable Include libsoxr resampling [no]
# build_libspeex          # config_options+= --enable-libspeex            # Audio  # enable Speex de/encoding via libspeex [no]
# build_libsrt            # config_options+= --enable-libsrt              # System # enable Haivision SRT protocol via libsrt [no]
# build_libssh            # config_options+= --enable-libssh              # System # enable SFTP protocol via libssh [no]
# build_libsvtav1         # config_options+= --enable-libsvtav1           # Video  # enable AV1 encoding via SVT [no]
# build_libtensorflow     # config_options+= --enable-libtensorflow       # Video  # enable TensorFlow as a DNN module backend for DNN based filters like sr [no]
# build_libtesseract      # config_options+= --enable-libtesseract        # Video  # enable Tesseract, needed for ocr filter [no]
# build_libtheora         # config_options+= --enable-libtheora           # Video  # enable Theora encoding via libtheora [no]
# build_libtls            # config_options+= --enable-libtls              # System # enable LibreSSL (via libtls), needed for https support if openssl, gnutls or mbedtls is not used [no]
# build_libtorch          # config_options+= --enable-libtorch            # Video  # enable Torch as one DNN backend [no]
# build_libtwolame        # config_options+= --enable-libtwolame          # Audio  # enable MP2 encoding via libtwolame [no]
# build_libuavs3d         # config_options+= --enable-libuavs3d           # Video  # enable AVS3 decoding via libuavs3d [no]
# build_libvidstab        # config_options+= --enable-libvidstab          # Video  # enable video stabilization using vid.stab [no]
# build_libvmaf           # config_options+= --enable-libvmaf             # Video  # enable vmaf filter via libvmaf [no]
# build_libvorbis         # config_options+= --enable-libvorbis           # Audio  # enable Vorbis en/decoding via libvorbis, native implementation exists [no]
# build_libvpx            # config_options+= --enable-libvpx              # Video  # enable VP8 and VP9 de/encoding via libvpx [no]
# build_libvvenc          # config_options+= --enable-libvvenc            # Video  # enable H.266/VVC encoding via vvenc [no]
# build_libwebp           # config_options+= --enable-libwebp             # Video  # enable WebP encoding via libwebp [no]
# build_libx264           # config_options+= --enable-libx264             # Video  # enable H.264 encoding via x264 [no]
# build_libx265           # config_options+= --enable-libx265             # Video  # enable HEVC encoding via x265 [no]
# build_libxavs           # config_options+= --enable-libxavs             # Video  # enable AVS encoding via xavs [no]
# build_libxavs2          # config_options+= --enable-libxavs2            # Video  # enable AVS2 encoding via xavs2 [no]
# build_libxevd           # config_options+= --enable-libxevd             # Video  # enable EVC decoding via libxevd [no]
# build_libxeve           # config_options+= --enable-libxeve             # Video  # enable EVC encoding via libxeve [no]
# build_libxml2           # config_options+= --enable-libxml2             # System # enable XML parsing using the C library libxml2, needed for dash and imf demuxing support [no]
# build_libxvid           # config_options+= --enable-libxvid             # Video  # enable Xvid encoding via xvidcore, native MPEG-4/Xvid encoder exists [no]
# build_libzimg           # config_options+= --enable-libzimg             # Video  # enable z.lib, needed for zscale filter [no]
# build_libzmq            # config_options+= --enable-libzmq              # System # enable message passing via libzmq [no]
# build_libzvbi           # config_options+= --enable-libzvbi             # Video  # enable teletext support via libzvbi [no]
# build_lv2               # config_options+= --enable-lv2                 # Audio  # enable LV2 audio filtering [no]
# build_mbedtls           # config_options+= --enable-mbedtls             # System # enable mbedTLS, needed for https support if openssl, gnutls or libtls is not used [no]
# build_openal            # config_options+= --enable-openal              # Audio  # enable OpenAL 1.1 capture support [no]
# build_opencl            # config_options+= --enable-opencl              # Video  # enable OpenCL processing [no]
# build_opengl            # config_options+= --enable-opengl              # Video  # enable OpenGL rendering [no]
# build_openssl           # config_options+= --enable-openssl             # System # enable openssl, needed for https support if gnutls, libtls or mbedtls is not used [no]
# build_pocketsphinx      # config_options+= --enable-pocketsphinx        # Audio  # enable PocketSphinx, needed for asr filter [no]
# build_vapoursynth       # config_options+= --enable-vapoursynth         # Video  # enable VapourSynth demuxer [no]
# build_whisper           # config_options+= --enable-whisper             # Audio  # enable whisper filter [no]
# build_decklink          # config_options+= --enable-decklink            # Video  # enable Blackmagic DeckLink I/O support [no]
# build_libfdk_aac        # config_options+= --enable-libfdk-aac          # Audio  # enable AAC de/encoding via libfdk-aac [no]
# build_cuda_llvm         # config_options+= --disable-cuda-llvm          # Video  # disable CUDA compilation using clang [autodetect]
# build_cuvid             # config_options+= --disable-cuvid              # Video  # disable Nvidia CUVID support [autodetect]
# build_ffnvcodec         # config_options+= --disable-ffnvcodec          # Video  # disable dynamically linked Nvidia code [autodetect]
# build_nvdec             # config_options+= --disable-nvdec              # Video  # disable Nvidia video decoding acceleration (via hwaccel) [autodetect]
# build_nvenc             # config_options+= --disable-nvenc              # Video  # disable Nvidia video encoding code [autodetect]
# build_vdpau             # config_options+= --disable-vdpau              # Video  # disable Nvidia Video Decode and Presentation API for Unix code [autodetect]
# build_cuda_nvcc         # config_options+= --enable-cuda-nvcc           # Video  # enable Nvidia CUDA compiler [no]
# build_mmal              # config_options+= --disable-mmal               # Video  # enable Broadcom Multi-Media Abstraction Layer (Raspberry Pi) via MMAL [no]
# build_d3d11va           # config_options+= --disable-d3d11va            # Video  # disable Microsoft Direct3D 11 video acceleration code [autodetect]
# build_d3d12va           # config_options+= --disable-d3d12va            # Video  # disable Microsoft Direct3D 12 video acceleration code [autodetect]
# build_dxva2             # config_options+= --disable-dxva2              # Video  # disable Microsoft DirectX 9 video acceleration code [autodetect]
# build_schannel          # config_options+= --disable-schannel           # System # disable SChannel SSP, needed for TLS support on Windows if openssl and gnutls are not used [autodetect]
# build_mediafoundation   # config_options+= --enable-mediafoundation     # Video  # enable encoding via MediaFoundation [auto]
# build_avfoundation      # config_options+= --disable-avfoundation       # Video  # disable Apple AVFoundation framework [autodetect]
# build_appkit            # config_options+= --disable-appkit             # System # disable Apple AppKit framework [autodetect]
# build_audiotoolbox      # config_options+= --disable-audiotoolbox       # Audio  # disable Apple AudioToolbox code [autodetect]
# build_coreimage         # config_options+= --disable-coreimage          # Video  # disable Apple CoreImage framework [autodetect]
# build_metal             # config_options+= --disable-metal              # Video  # disable Apple Metal framework [autodetect]
# build_securetransport   # config_options+= --disable-securetransport    # System # disable Secure Transport, needed for TLS support on OSX if openssl and gnutls are not used [autodetect]
# build_videotoolbox      # config_options+= --disable-videotoolbox       # Video  # disable VideoToolbox code [autodetect]
# build_libsvtjpegxs      # config_options+= --disable-libsvtjpegxs       # Video  # disable SVT-JPEGXS code [autodetect]
# build_libopencolorio    # config_options+= --disable-libopencolorio     # Video  # disable OpenColorIO code [autodetect]
# build_libmpeghdec       # config_options+= --disable-libmpeghdec        # Audio  # disable MPEG-H 3D Audio decoder code [autodetect]

# disabled on android
# build_alsa
# build_xlib
# build_libxcb
# build_libxcb_shm
# build_libxcb_xfixes
# build_libxcb_shape
# build_vaapi
# build_vdpau
# build_sndio
# build_libpulse
# build_libjack
# build_libdc1394
# build_libiec61883
# build_libtensorflow
# build_libopenvino
# build_libtorch
