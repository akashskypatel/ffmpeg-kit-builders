#!/bin/bash

echo -e "INFO: Running scripts\variables.sh\n" 1>>"${BASEDIR}"/build.log 2>&1

# DIRECTORY DEFINITIONS
export FFMPEG_KIT_TMPDIR="${BASEDIR}/.tmp"

# ARRAY OF ENABLED ARCHITECTURES
ENABLED_ARCHITECTURES=(0 0 0 0 0 0 0 0 0 0 0 0 0)

# ARRAY OF ENABLED ARCHITECTURE VARIANTS
ENABLED_ARCHITECTURE_VARIANTS=(0 0 0 0 0 0 0 0)

# ARRAY OF ENABLED LIBRARIES
ENABLED_LIBRARIES=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

# ARRAY OF LIBRARIES THAT WILL BE RE-CONFIGURED
RECONF_LIBRARIES=()

# ARRAY OF LIBRARIES THAT WILL BE RE-BUILD
REBUILD_LIBRARIES=()

# ARRAY OF LIBRARIES THAT WILL BE RE-DOWNLOADED
REDOWNLOAD_LIBRARIES=()

# ARRAY OF CUSTOM LIBRARIES
CUSTOM_LIBRARIES=()

# ARCH INDEXES
ARCH_ARM_V7A=0              # android
ARCH_ARM_V7A_NEON=1         # android
ARCH_ARMV7=2                # ios
ARCH_ARMV7S=3               # ios
ARCH_ARM64_V8A=4            # android
ARCH_ARM64=5                # ios, tvos, macos
ARCH_ARM64E=6               # ios
ARCH_I386=7                 # ios
ARCH_X86=8                  # android, windows
ARCH_X86_64=9               # android, ios, linux, macos, tvos, windows
ARCH_X86_64_MAC_CATALYST=10 # ios
ARCH_ARM64_MAC_CATALYST=11  # ios
ARCH_ARM64_SIMULATOR=12     # ios

# ARCH VARIANT INDEXES
ARCH_VAR_IOS=1              # ios
ARCH_VAR_IPHONEOS=2         # ios
ARCH_VAR_IPHONESIMULATOR=3  # ios
ARCH_VAR_MAC_CATALYST=4     # ios
ARCH_VAR_TVOS=5             # tvos
ARCH_VAR_APPLETVOS=6        # tvos
ARCH_VAR_APPLETVSIMULATOR=7 # tvos
ARCH_VAR_MACOS=8            # macos

# LIBRARY INDEXES
LIBRARY_FONTCONFIG=0
LIBRARY_FREETYPE=1
LIBRARY_FRIBIDI=2
LIBRARY_GMP=3
LIBRARY_GNUTLS=4
LIBRARY_LAME=5
LIBRARY_LIBASS=6
LIBRARY_LIBICONV=7
LIBRARY_LIBTHEORA=8
LIBRARY_LIBVORBIS=9
LIBRARY_LIBVPX=10
LIBRARY_LIBWEBP=11
LIBRARY_LIBXML2=12
LIBRARY_OPENCOREAMR=13
LIBRARY_SHINE=14
LIBRARY_SPEEX=15
LIBRARY_DAV1D=16
LIBRARY_KVAZAAR=17
LIBRARY_X264=18 #gpl
LIBRARY_XVIDCORE=19 #gpl
LIBRARY_X265=20 #gpl
LIBRARY_LIBVIDSTAB=21 #gpl
LIBRARY_RUBBERBAND=22 #gpl
LIBRARY_LIBILBC=23
LIBRARY_OPUS=24
LIBRARY_SNAPPY=25
LIBRARY_SOXR=26
LIBRARY_LIBAOM=27
LIBRARY_CHROMAPRINT=28
LIBRARY_TWOLAME=29
LIBRARY_SDL=30
LIBRARY_TESSERACT=31
LIBRARY_OPENH264=32
LIBRARY_VO_AMRWBENC=33
LIBRARY_ZIMG=34
LIBRARY_OPENSSL=35
LIBRARY_SRT=36
LIBRARY_GIFLIB=37
LIBRARY_JPEG=38
LIBRARY_LIBOGG=39
LIBRARY_LIBPNG=40
LIBRARY_LIBUUID=41
LIBRARY_NETTLE=42
LIBRARY_TIFF=43
LIBRARY_EXPAT=44
LIBRARY_SNDFILE=45
LIBRARY_LEPTONICA=46
LIBRARY_LIBSAMPLERATE=47
LIBRARY_HARFBUZZ=48
LIBRARY_CPU_FEATURES=49
LIBRARY_SYSTEM_ZLIB=50
LIBRARY_LINUX_ALSA=51
LIBRARY_ANDROID_MEDIA_CODEC=52
LIBRARY_APPLE_AUDIOTOOLBOX=53
LIBRARY_APPLE_BZIP2=54
LIBRARY_APPLE_VIDEOTOOLBOX=55
LIBRARY_APPLE_AVFOUNDATION=56
LIBRARY_APPLE_LIBICONV=57
LIBRARY_APPLE_LIBUUID=58
LIBRARY_APPLE_COREIMAGE=59
LIBRARY_APPLE_OPENCL=60
LIBRARY_APPLE_OPENGL=61
LIBRARY_LINUX_FONTCONFIG=62
LIBRARY_LINUX_FREETYPE=63
LIBRARY_LINUX_FRIBIDI=64
LIBRARY_LINUX_GMP=65
LIBRARY_LINUX_GNUTLS=66
LIBRARY_LINUX_LAME=67
LIBRARY_LINUX_LIBASS=68
LIBRARY_LINUX_LIBICONV=69
LIBRARY_LINUX_LIBTHEORA=70
LIBRARY_LINUX_LIBVORBIS=71
LIBRARY_LINUX_LIBVPX=72
LIBRARY_LINUX_LIBWEBP=73
LIBRARY_LINUX_LIBXML2=74
LIBRARY_LINUX_OPENCOREAMR=75
LIBRARY_LINUX_SHINE=76
LIBRARY_LINUX_SPEEX=77
LIBRARY_LINUX_OPENCL=78
LIBRARY_LINUX_XVIDCORE=79 #gpl
LIBRARY_LINUX_X265=80
LIBRARY_LINUX_LIBVIDSTAB=81 #gpl
LIBRARY_LINUX_RUBBERBAND=82 #gpl
LIBRARY_LINUX_V4L2=83
LIBRARY_LINUX_OPUS=84
LIBRARY_LINUX_SNAPPY=85
LIBRARY_LINUX_SOXR=86
LIBRARY_LINUX_TWOLAME=87
LIBRARY_LINUX_SDL=88
LIBRARY_LINUX_TESSERACT=89
LIBRARY_LINUX_VAAPI=90
LIBRARY_LINUX_VO_AMRWBENC=91
LIBRARY_AMF_HEADERS=92
LIBRARY_ARIBB24=94 #gpl
LIBRARY_AUDIOTOOLBOXWRAPPER=95
LIBRARY_AVISYNTH=96 #gpl
LIBRARY_BROTLI=97
LIBRARY_BZIP2=98
LIBRARY_CONFIG=99
LIBRARY_CPUINFO=100
LIBRARY_CURL=101
LIBRARY_DAVS2=102 #gpl
LIBRARY_DECKLINK_HEADERS=103
LIBRARY_DLFCN_WIN32=104
LIBRARY_DOVI_TOOL=105
LIBRARY_DOVI_TOOL_BIN=106
LIBRARY_FDK_AAC=107
LIBRARY_FFMPEG=108
LIBRARY_FFTW=109
LIBRARY_FLAC=110
LIBRARY_FLITE=111
LIBRARY_FREI0R=112 #gpl
LIBRARY_GETTEXT=113
LIBRARY_GLFW=114
LIBRARY_GLEW=115
LIBRARY_GLIB=116
LIBRARY_GPAC=117
LIBRARY_L_SMASH=118
LIBRARY_L_SMASH_WORKS=119
LIBRARY_LCMS=120
LIBRARY_LENSFUN=121
LIBRARY_LIBARIBCAPTION=122
LIBRARY_LIBARCHIVE=123
LIBRARY_LIBBLURAY=124
LIBRARY_LIBBS2B=125
LIBRARY_LIBCACA=126
LIBRARY_LIBDVBPSI=127
LIBRARY_LIBDVBTEE=128
LIBRARY_LIBDVDCSS=129
LIBRARY_LIBDVDNAV=130
LIBRARY_LIBDVDREAD=131
LIBRARY_LIBFFI=132
LIBRARY_LIBGME=133
LIBRARY_LIBIDN2=134
LIBRARY_LIBJPEG_TURBO=135
LIBRARY_LIBMODPLUG=136
LIBRARY_LIBMYSOFA=137
LIBRARY_LIBMXF=138
LIBRARY_LIBOPENCORE=139
LIBRARY_LIBOPENJPEG=141
LIBRARY_LIBPLACEBO=143
LIBRARY_LIBPROXY=144
LIBRARY_LIBPSL=145
LIBRARY_LIBRTMFP=146
LIBRARY_LIBSSH2=147
LIBRARY_LIBUNISTRING=149
LIBRARY_LIBUNWIND=150
LIBRARY_LIBVPL=151
LIBRARY_LIBVVDEC=152
LIBRARY_LIBVVENC=153
LIBRARY_LIBXVID=154 #gpl
LIBRARY_LUA=155
LIBRARY_LZ4=156
LIBRARY_MFX_DISPATCH=157
LIBRARY_MINGW_STD_THREADS=158
LIBRARY_MPLAYER=159
LIBRARY_MPLAYER_FFMPEG=160
LIBRARY_MPG123=161
LIBRARY_NGHTTP2=162
LIBRARY_NV_CODEC_HEADERS=163
LIBRARY_OPENMPT=164
LIBRARY_OPENSSL_1_0_2=165
LIBRARY_OPENSSL_1_1_1=166
LIBRARY_OPENCV=167
LIBRARY_QT=168
LIBRARY_SDL2=169
LIBRARY_SHADERC=170
LIBRARY_SPEEXDSP=171
LIBRARY_SPIRV_CROSS=172
LIBRARY_SVT_AV1=173
LIBRARY_SVT_HEVC=174
LIBRARY_SVT_VP9=175
LIBRARY_TENSORFLOW=176
LIBRARY_TRANSFORM360=177
LIBRARY_VAMP_PLUGIN_SDK=178
LIBRARY_VLC=179
LIBRARY_VMAF=180
LIBRARY_VULKAN_HEADERS=181
LIBRARY_VULKAN_SHIM_LOADER=182
LIBRARY_XAVS=183 #gpl
LIBRARY_XAVS2=184 #gpl
LIBRARY_XXHASH=185
LIBRARY_XZ=186
LIBRARY_ZLIB=187
LIBRARY_ZSTD=188
LIBRARY_ZVBI=189

#!/bin/bash

export MINGW_W64_BRANCH="master"
export BINUTILS_BRANCH="binutils-2_44-branch"
export GCC_BRANCH="releases/gcc-14"

export sandbox="prebuilt"
export WORKDIR="$BASEDIR/$sandbox"
export WINWINPATCHDIR="$BASEDIR/windows/patches"
export SCRIPTDIR="$BASEDIR/scripts"

# variables with their defaults
export build_ffmpeg_static=y
export build_ffmpeg_shared=n
export build_dvbtee=n
export build_libmxf=n
export build_mp4box=n
export build_mplayer=n
export build_vlc=n
export build_lsw=n # To build x264 with L-Smash-Works.
export build_dependencies=y
export git_get_latest=y
export prefer_stable=y # Only for x264 and x265.
export build_intel_qsv=y # libvpl 
export build_amd_amf=y
export disable_nonfree=y # comment out to force user y/n selection
export original_cflags='-mtune=generic -O3 -pipe' # high compatible by default, see #219, some other good options are listed below, or you could use -march=native to target your local box:
export original_cppflags='-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3' # Needed for mingw-w64 7 as FORTIFY_SOURCE is now partially implemented, but not actually working
# if you specify a march it needs to first so x264's configure will use it :| [ is that still the case ?]
# original_cflags='-march=znver2 -O3 -pipe'
#flags=$(cat /proc/cpuinfo | grep flags)
#if [[ $flags =~ "ssse3" ]]; then # See https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html, https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html and https://stackoverflow.com/questions/19689014/gcc-difference-between-o3-and-os.
#  original_cflags='-march=core2 -O2'
#elif [[ $flags =~ "sse3" ]]; then
#  original_cflags='-march=prescott -O2'
#elif [[ $flags =~ "sse2" ]]; then
#  original_cflags='-march=pentium4 -O2'
#elif [[ $flags =~ "sse" ]]; then
#  original_cflags='-march=pentium3 -O2 -mfpmath=sse -msse'
#else
#  original_cflags='-mtune=generic -O2'
#fi
export ffmpeg_git_checkout_version=
export build_ismindex=n
export enable_gpl=y
export build_x264_with_libav=n # To build x264 with Libavformat.
export ffmpeg_git_checkout="https://github.com/FFmpeg/FFmpeg.git"
export ffmpeg_source_dir=
export build_svt_hevc=n
export build_svt_vp9=n
export build_dependencies_only=n

export original_cpu_count=$(get_cpu_count) # save it away for some that revert it temporarily

export PKG_CONFIG_LIBDIR= # disable pkg-config from finding [and using] normal linux system installed libs [yikes]
export original_path="$PATH"


export BUILD_STEPS=(
  "check_native"
  "build_libdavs2"
  "check_host_target"
  "build_meson_cross"
  "build_mingw_std_threads"
  "build_zlib"
  "build_libcaca"
  "build_bzip2"
  "build_liblzma"
  "build_iconv"
  "build_sdl2"  
  "check_gpulibs"
  "build_nv_headers"
  "build_libzimg"
  "build_libopenjpeg"
  "build_glew"
  "build_glfw"
  "build_libpng"
  "build_libwebp"
  "build_libxml2"
  "build_brotli"
  "build_harfbuzz"
  "build_libvmaf"
  "build_fontconfig"
  "build_gmp"  
  "build_libnettle"
  "build_unistring"
  "build_libidn2"
  "build_zstd"
  "build_gnutls"
  "build_curl"
  "build_libogg"
  "build_libvorbis"
  "build_libopus"
  "build_libspeexdsp"
  "build_libspeex"
  "build_libtheora"
  "check_build_libsndfile"
  "build_mpg123"
  "build_lame"
  "build_twolame"
  "build_openmpt"
  "build_libopencore"
  "build_libilbc"
  "build_libmodplug"
  "build_libgme"
  "build_libbluray"
  "build_libbs2b"
  "build_libsoxr"
  "build_libflite"
  "build_libsnappy"
  "build_vamp_plugin"
  "build_fftw"
  "build_libsamplerate"
  "build_librubberband"
  "build_frei0r"  
  "check_svt"
  "build_vidstab"
  "build_libmysofa"  
  "check_audiotoolbox"
  "build_zvbi"
  "build_fribidi"
  "build_libass"
  "build_libxvid"
  "build_libsrt"
  "check_libaribcaption"
  "build_libaribb24"
  "build_libtesseract"
  "build_lensfun"
  "check_libtensorflow"
  "build_libvpx"
  "build_libx265"
  "build_libopenh264"
  "build_libaom"
  "build_dav1d"
  "check_vulkan_libplacebo"
  "build_avisynth"
  "build_libvvenc"
  "build_libvvdec"
  "build_libx264"
  "build_apps"
)

while true; do
  case $1 in
    -top_dir | --top_dir) echo "$BASEDIR" ; shift;;
    -sandbox | --sandbox) echo "$sandbox" ; shift;;
    -cur_dir | --cur_dir) echo "$cur_dir" ; shift;;
    -patch_dir | --patch_dir) echo "$WINPATCHDIR" ; shift;;
    -cpu_count | --cpu_count) echo "$(get_cpu_count)" ; shift;;
    -build_ffmpeg_static | --build_ffmpeg_static) echo "$build_ffmpeg_static" ; shift;;
    -build_ffmpeg_shared | --build_ffmpeg_shared) echo "$build_ffmpeg_shared" ; shift;;
    -build_dvbtee | --build_dvbtee) echo "$build_dvbtee" ; shift;;
    -build_libmxf | --build_libmxf) echo "$build_libmxf" ; shift;;
    -build_mp4box | --build_mp4box) echo "$build_mp4box" ; shift;;
    -build_mplayer | --build_mplayer) echo "$build_mplayer" ; shift;;
    -build_vlc | --build_vlc) echo "$build_vlc" ; shift;;
    -build_lsw | --build_lsw) echo "$build_lsw" ; shift;;
    -build_dependencies | --build_dependencies) echo "$build_dependencies" ; shift;;
    -git_get_latest | --git_get_latest) echo "$git_get_latest" ; shift;;
    -prefer_stable | --prefer_stable) echo "$prefer_stable" ; shift;;
    -build_intel_qsv | --build_intel_qsv) echo "$build_intel_qsv" ; shift;;
    -build_amd_amf | --build_amd_amf) echo "$build_amd_amf" ; shift;;
    -disable_nonfree | --disable_nonfree) echo "$disable_nonfree" ; shift;;
    -original_cflags | --original_cflags) echo "$original_cflags" ; shift;;
    -original_cppflags | --original_cppflags) echo "$original_cppflags" ; shift;;
    -ffmpeg_git_checkout_version | --ffmpeg_git_checkout_version) echo "$ffmpeg_git_checkout_version" ; shift;;
    -build_ismindex | --build_ismindex) echo "$build_ismindex" ; shift;;
    -enable_gpl | --enable_gpl) echo "$enable_gpl" ; shift;;
    -build_x264_with_libav | --build_x264_with_libav) echo "$build_x264_with_libav" ; shift;;
    -ffmpeg_git_checkout | --ffmpeg_git_checkout) echo "$ffmpeg_git_checkout" ; shift;;
    -ffmpeg_source_dir | --ffmpeg_source_dir) echo "$ffmpeg_source_dir" ; shift;;
    -build_svt_hevc | --build_svt_hevc) echo "$build_svt_hevc" ; shift;;
    -build_svt_vp9 | --build_svt_vp9) echo "$build_svt_vp9" ; shift;;
    -build_dependencies_only | --build_dependencies_only) echo "$build_dependencies_only" ; shift;;
    -original_cpu_count | --original_cpu_count) echo "$original_cpu_count" ; shift;;
    -a | --all) 
    echo -e "top_dir=$BASEDIR\n" \
            "sandbox=$sandbox\n" \
            "cur_dir=$cur_dir\n" \
            "patch_dir=$WINPATCHDIR\n" \
            "cpu_count=$(get_cpu_count)\n" \
            "build_ffmpeg_static=$build_ffmpeg_static\n" \
            "build_ffmpeg_shared=$build_ffmpeg_shared\n" \
            "build_dvbtee=$build_dvbtee\n" \
            "build_libmxf=$build_libmxf\n" \
            "build_mp4box=$build_mp4box\n" \
            "build_mplayer=$build_mplayer\n" \
            "build_vlc=$build_vlc\n" \
            "build_lsw=$build_lsw\n" \
            "build_dependencies=$build_dependencies\n" \
            "git_get_latest=$git_get_latest\n" \
            "prefer_stable=$prefer_stable\n" \
            "build_intel_qsv=$build_intel_qsv\n" \
            "build_amd_amf=$build_amd_amf\n" \
            "disable_nonfree=$disable_nonfree\n" \
            "original_cflags=$original_cflags\n" \
            "original_cppflags=$original_cppflags\n" \
            "ffmpeg_git_checkout_version=$ffmpeg_git_checkout_version\n" \
            "build_ismindex=$build_ismindex\n" \
            "enable_gpl=$enable_gpl\n" \
            "build_x264_with_libav=$build_x264_with_libav\n" \
            "ffmpeg_git_checkout=$ffmpeg_git_checkout\n" \
            "ffmpeg_source_dir=$ffmpeg_source_dir\n" \
            "build_svt_hevc=$build_svt_hevc\n" \
            "build_svt_vp9=$build_svt_vp9\n" \
            "build_dependencies_only=$build_dependencies_only\n" \
            "original_cpu_count=$original_cpu_count\n" ; shift;;
    *) break;;
  esac
done