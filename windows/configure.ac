AC_INIT([ffmpeg-kit], [8.0], [https://github.com/akashskypatel/ffmpeg-kit-builders/issues/new])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_SRCDIR([src/FFmpegKit.cpp])

# Use modern canonical macros
AC_CANONICAL_TARGET

AM_INIT_AUTOMAKE([-Wall -Werror foreign subdir-objects])
AM_MAINTAINER_MODE

# Add shared/static library options here
AC_ARG_ENABLE([shared],
    [AS_HELP_STRING([--enable-shared],
        [build shared libraries @<:@default=yes@:>@])],
    [enable_shared=$enableval],
    [enable_shared=yes])

AC_ARG_ENABLE([static],
    [AS_HELP_STRING([--enable-static],
        [build static libraries @<:@default=no@:>@])],
    [enable_static=$enableval],
    [enable_static=no])

# Set library build flags based on options
if test "x$enable_shared" = "xyes"; then
    BUILD_SHARED=yes
else
    BUILD_SHARED=no
fi

if test "x$enable_static" = "xyes"; then
    BUILD_STATIC=yes
else
    BUILD_STATIC=no
fi

AC_SUBST([BUILD_SHARED])
AC_SUBST([BUILD_STATIC])

# Check for cross-compilation
AC_MSG_CHECKING([whether we are cross compiling])
if test "$cross_compiling" = yes; then
    AC_MSG_RESULT([yes])
    IS_CROSS_COMPILE=yes
else
    AC_MSG_RESULT([no])
    IS_CROSS_COMPILE=no
fi

# Set target OS based on TARGET, not HOST
AC_MSG_CHECKING([for target system])
case "$target" in
    *mingw32*|*mingw64*|*windows*|*win32*|*win64*)
        AC_MSG_RESULT([Windows])
        AC_DEFINE([TARGET_OS_WINDOWS], [1], [Windows target])
        AC_DEFINE([_WIN32], [1], [Windows platform])
        VERSION_OS="Windows"
        target_os_clean="windows"
        ;;
    *)
        AC_MSG_RESULT([Linux])
        AC_DEFINE([TARGET_OS_LINUX], [1], [Linux target])
        VERSION_OS="Linux"
        target_os_clean="linux"
        ;;
esac

AC_DEFINE_UNQUOTED(VERSION_OS, "$VERSION_OS", [os version])

# Allow custom toolchain programs to be specified
AC_ARG_VAR([CC], [C compiler command])
AC_ARG_VAR([CXX], [C++ compiler command])
AC_ARG_VAR([AR], [Archive maintainer command])
AC_ARG_VAR([AS], [Assembler command])
AC_ARG_VAR([NM], [Symbol listing command])
AC_ARG_VAR([RANLIB], [Archive indexer command])
AC_ARG_VAR([LD], [Linker command])
AC_ARG_VAR([STRIP], [Symbol stripper command])

# Force Windows toolchain when cross-compiling
if test "x$target_os_clean" = "xwindows"; then
    AC_MSG_NOTICE([Configuring for Windows cross-compilation])
    
    # Set Windows-specific tools with fallbacks
    if test -z "$CC"; then
        CC=x86_64-w64-mingw32-gcc
    fi
    if test -z "$CXX"; then
        CXX=x86_64-w64-mingw32-g++
    fi
    if test -z "$AR"; then
        AR=x86_64-w64-mingw32-ar
    fi
    if test -z "$AS"; then
        AS=x86_64-w64-mingw32-as
    fi
    if test -z "$NM"; then
        NM=x86_64-w64-mingw32-nm
    fi
    if test -z "$RANLIB"; then
        RANLIB=x86_64-w64-mingw32-ranlib
    fi
    if test -z "$LD"; then
        LD=x86_64-w64-mingw32-ld
    fi
    if test -z "$STRIP"; then
        STRIP=x86_64-w64-mingw32-strip
    fi
    if test -z "$WINDRES"; then
        WINDRES=x86_64-w64-mingw32-windres
    fi
    
    # Windows library extensions
    if test "x$enable_shared" = "xyes"; then
        LIBRARY_EXT="dll"
        ARCHIVE_EXT="dll.a"  # Import libraries for MinGW
    else
        LIBRARY_EXT="lib"    # Windows static libraries use .lib
        ARCHIVE_EXT="lib"
    fi
    
    # Additional Windows flags
    WINDOWS_LDFLAGS="-Wl,--export-all-symbols -Wl,--enable-auto-import -Wl,--allow-multiple-definition"
    CFLAGS="$CFLAGS -D_WIN32_WINNT=0x0600"
    CXXFLAGS="$CXXFLAGS -D_WIN32_WINNT=0x0600"
else
    # Linux library extensions
    if test "x$enable_shared" = "xyes"; then
        LIBRARY_EXT="so"
        ARCHIVE_EXT="so"
    else
        LIBRARY_EXT="a"
        ARCHIVE_EXT="a"
    fi
    WINDOWS_LDFLAGS=""
fi

AC_SUBST([LIBRARY_EXT])
AC_SUBST([ARCHIVE_EXT])
AC_SUBST([WINDOWS_LDFLAGS])

# Set conditionals for Makefile.am
AM_CONDITIONAL([WINDOWS], [test "x$target_os_clean" = "xwindows"])
AM_CONDITIONAL([LINUX], [test "x$target_os_clean" = "xlinux"])

# Checks for programs.
AC_LANG([C++])
AC_PROG_CXX
AC_PROG_CC

# Use AM_PROG_AR for automake compatibility
AM_PROG_AR

# Check for other programs
AC_CHECK_TOOL([AS], [as])
AC_CHECK_TOOL([NM], [nm])
AC_CHECK_TOOL([RANLIB], [ranlib])
AC_CHECK_TOOL([LD], [ld])
AC_CHECK_TOOL([STRIP], [strip])

AX_CXX_COMPILE_STDCXX(11, noext)
LT_INIT

# Check for pkg-config
PKG_PROG_PKG_CONFIG

# Set FFmpeg library paths based on target
if test "x$target_os_clean" = "xwindows"; then
    # Windows-specific libraries
    FFMPEG_LIBS="-lavcodec -lavfilter -lavformat -lavutil -lswscale -lswresample -lavdevice -lpsapi -lws2_32 -lbcrypt -luser32 -lole32"
    
    # Add Windows-specific compiler flags
    WINDOWS_CFLAGS="-D_WIN32_WINNT=0x0600"
    WINDOWS_CXXFLAGS="-D_WIN32_WINNT=0x0600"
    CFLAGS="$CFLAGS $WINDOWS_CFLAGS"
    CXXFLAGS="$CXXFLAGS $WINDOWS_CXXFLAGS"
else
    # Linux/Unix libraries  
    FFMPEG_LIBS="-lavcodec -lavfilter -lavformat -lavutil -lswscale -lswresample -lavdevice -lpostproc -lpthread"
fi

AC_SUBST(FFMPEG_LIBS)
AC_SUBST(WINDOWS_CFLAGS)
AC_SUBST(WINDOWS_CXXFLAGS)

# CURRENT INTERFACE:REVISION:AGE
VERSION_INFO="11:0:6"
AC_SUBST(VERSION_INFO)

# Checks for FFmpeg headers using pkg-config
AC_MSG_CHECKING([for FFmpeg headers])

# Try to get CFLAGS from pkg-config
if test -n "$PKG_CONFIG"; then
    # Check for individual FFmpeg libraries
    AC_MSG_CHECKING([for libavformat])
    if $PKG_CONFIG --exists libavformat; then
        AC_MSG_RESULT([yes])
        AVFORMAT_CFLAGS=`$PKG_CONFIG --cflags libavformat`
        AVFORMAT_LIBS=`$PKG_CONFIG --libs libavformat`
    else
        AC_MSG_RESULT([no])
        AC_MSG_WARN([libavformat not found via pkg-config])
    fi

    AC_MSG_CHECKING([for libavcodec])
    if $PKG_CONFIG --exists libavcodec; then
        AC_MSG_RESULT([yes])
        AVCODEC_CFLAGS=`$PKG_CONFIG --cflags libavcodec`
        AVCODEC_LIBS=`$PKG_CONFIG --libs libavcodec`
    else
        AC_MSG_RESULT([no])
        AC_MSG_WARN([libavcodec not found via pkg-config])
    fi

    AC_MSG_CHECKING([for libavutil])
    if $PKG_CONFIG --exists libavutil; then
        AC_MSG_RESULT([yes])
        AVUTIL_CFLAGS=`$PKG_CONFIG --cflags libavutil`
        AVUTIL_LIBS=`$PKG_CONFIG --libs libavutil`
    else
        AC_MSG_RESULT([no])
        AC_MSG_WARN([libavutil not found via pkg-config])
    fi
fi

# Manual check for FFmpeg headers as fallback
saved_CPPFLAGS="$CPPFLAGS"
if test -n "$AVFORMAT_CFLAGS"; then
    CPPFLAGS="$CPPFLAGS $AVFORMAT_CFLAGS"
fi

# Check for individual FFmpeg headers
AC_CHECK_HEADERS([libavformat/avformat.h], [has_avformat=yes], [has_avformat=no])
AC_CHECK_HEADERS([libavcodec/avcodec.h], [has_avcodec=yes], [has_avcodec=no])
AC_CHECK_HEADERS([libavutil/avutil.h], [has_avutil=yes], [has_avutil=no])
AC_CHECK_HEADERS([libavutil/ffversion.h], [has_ffversion=yes], [has_ffversion=no])
AC_CHECK_HEADERS([libavutil/avstring.h], [has_avstring=yes], [has_avstring=no])

CPPFLAGS="$saved_CPPFLAGS"

if test "$has_ffversion" = no; then
    AC_MSG_WARN([libavutil/ffversion.h not found - some features may be limited])
fi

if test "$has_avformat" = no || test "$has_avcodec" = no || test "$has_avutil" = no; then
    AC_MSG_WARN([Some FFmpeg headers not found. Trying direct path...])
    AC_MSG_ERROR([unable to find ffmpeg headers. Check FFmpeg installation and PKG_CONFIG_PATH])
else
    AC_MSG_RESULT([FFmpeg headers found via pkg-config])
fi

# Check for JsonCpp with multiple approaches
AC_MSG_CHECKING([for JsonCpp])

# Method 1: Check via pkg-config first
PKG_CHECK_MODULES([JSONCPP], [jsoncpp], [
    AC_MSG_RESULT([yes (pkg-config)])
    CPPFLAGS="$CPPFLAGS $JSONCPP_CFLAGS"
    LIBS="$LIBS $JSONCPP_LIBS"
], [
    # Method 2: Check standard library locations
    AC_CHECK_HEADERS([json/json.h], [has_jsoncpp_header=yes], [has_jsoncpp_header=no])
    AC_CHECK_LIB([jsoncpp], [jsoncpp_version], [has_jsoncpp_lib=yes], [has_jsoncpp_lib=no])
    
    if test "$has_jsoncpp_header" = yes && test "$has_jsoncpp_lib" = yes; then
        AC_MSG_RESULT([yes (standard library)])
        JSONCPP_LIBS="-ljsoncpp"
    else
        AC_MSG_RESULT([no])
        AC_MSG_ERROR([JsonCpp not found. Install with: sudo apt-get install libjsoncpp-dev])
    fi
])

AC_SUBST([JSONCPP_LIBS])

# OS-specific header checks
if test "x$target_os_clean" = "xwindows"; then
    AC_CHECK_HEADERS([windows.h winsock2.h ws2tcpip.h process.h io.h])
else
    AC_CHECK_HEADERS([fcntl.h limits.h stdint.h stdlib.h string.h sys/ioctl.h sys/time.h termios.h unistd.h])
fi

# Checks for typedefs, structures, and compiler characteristics.
AC_C_BIGENDIAN(AC_DEFINE([HIGHFIRST], [1], [big-endian machine]))
AC_C_INLINE
AC_TYPE_INT32_T
AC_TYPE_INT64_T
AC_TYPE_INT8_T
AC_TYPE_SIZE_T
AC_TYPE_UINT16_T
AC_TYPE_UINT32_T
AC_TYPE_UINT64_T
AC_TYPE_UINT8_T

# Checks for library functions (skip some when cross-compiling)
if test "x$IS_CROSS_COMPILE" != "xyes"; then
    if test "x$target_os_clean" = "xwindows"; then
        AC_CHECK_FUNCS([_dup2 floor memmove memset _select strchr strcspn strerror strrchr strstr strtol malloc strcpy strlen vsnprintf])
    else
        AC_CHECK_FUNCS([dup2 floor memmove memset select strchr strcspn strerror strrchr strstr strtol malloc strcpy strlen vsnprintf])
    fi
fi

# Set build date for FFmpegKit (BEFORE AC_OUTPUT)
AC_MSG_CHECKING([for FFmpegKit build date])
if test -z "$FFMPEG_KIT_BUILD_DATE"; then
    FFMPEG_KIT_BUILD_DATE=$(date +%Y%m%d)
    AC_MSG_RESULT([using current date: $FFMPEG_KIT_BUILD_DATE])
else
    AC_MSG_RESULT([using provided date: $FFMPEG_KIT_BUILD_DATE])
fi

FFMPEG_KIT_BUILD_DATE_DEF="-DFFMPEG_KIT_BUILD_DATE=$FFMPEG_KIT_BUILD_DATE"
CFLAGS="$CFLAGS $FFMPEG_KIT_BUILD_DATE_DEF"
CXXFLAGS="$CXXFLAGS $FFMPEG_KIT_BUILD_DATE_DEF"

AC_DEFINE_UNQUOTED([FFMPEG_KIT_BUILD_DATE], ["$FFMPEG_KIT_BUILD_DATE"], [FFmpegKit build date])
AC_SUBST([FFMPEG_KIT_BUILD_DATE])

AC_CONFIG_FILES([Makefile src/Makefile])

AC_OUTPUT