# =============================================================================
# PREAMBLE: Project Setup & Platform Validation
# =============================================================================
# - Enforce MinGW for Windows builds to prevent MSVC compatibility issues
# - Prevent in-source builds to maintain clean build directory separation
# - Initialize project with C/C++ support and enable IDE integration
# =============================================================================

cmake_minimum_required(VERSION 3.16)

if(APPLE)
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/AppleResourceGen.cmake")
endif()
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/FfmpegKitSources.cmake")
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/FfmpegKitDependencies.cmake")

# set(CMAKE_MESSAGE_LOG_LEVEL DEBUG)

# Enforce MinGW when building for Windows
if(WIN32 AND NOT MINGW)
    message(FATAL_ERROR "Windows builds require MinGW. Use MinGW-w64 toolchain for cross-compilation. MSVC is currently not supported.")
endif()

if("${CMAKE_SOURCE_DIR}" STREQUAL "${CMAKE_BINARY_DIR}")
    message(FATAL_ERROR "In-source builds are not allowed.")
endif()

# Initialize Project
project(ffmpeg-kit VERSION 8.0 LANGUAGES C CXX)

if(APPLE)
    enable_language(OBJC)
endif()

# Export compile_commands.json for Clangd
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS_DEBUG ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS_RELEASE ON)

option(BUILD_TESTS "Build tests" OFF)
option(ENABLE_LIBPLACEBO "Enable libplacebo" OFF)
option(ENABLE_LIBTENSORFLOW "Enable libtensorflow" OFF)
option(ENABLE_OPENVINO "Enable openvino" OFF)
option(ENABLE_LIBTORCH "Enable libtorch" OFF)

# CMAKE_BUILD_TYPE is a CMake built-in string variable, not a boolean option.
# Using option() on it silently converts it to OFF. Use set() instead.
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type (Debug, Release, RelWithDebInfo, MinSizeRel)" FORCE)
endif()

# =============================================================================
# 1. OPTIONS & CONFIGURATION: Build Parameters & Path Validation
# =============================================================================
# - Configure build type (shared/static library, optional dependencies)
# - Validate FFmpeg source and build directory paths
# - Set build metadata (date, bundle type, version)
# ==============================================================================
option(BUILD_SHARED_LIBS "Build shared library" ON)
set(FFMPEG_KIT_BUILD_DATE "" CACHE STRING "Build date override")
set(FFMPEG_KIT_BUNDLE_TYPE "" CACHE STRING "Bundle type override")
set(FFMPEG_KIT_VERSION "" CACHE STRING "FFmpegKit version override")

# Define Paths
set(FFMPEG_BUILD_DIR "" CACHE PATH "Path to FFmpeg build directory (libs)")
set(DEPENDENCY_BUILD_DIR "" CACHE PATH "Path to dependency install directory")

if(NOT FFMPEG_BUILD_DIR OR NOT EXISTS "${FFMPEG_BUILD_DIR}/include/config.h")
    message(FATAL_ERROR "FFMPEG_BUILD_DIR is invalid. It must contain include/config.h")
endif()

if(NOT FFMPEG_BUILD_DIR OR NOT EXISTS "${FFMPEG_BUILD_DIR}/include/config_components.h")
    message(FATAL_ERROR "FFMPEG_BUILD_DIR is invalid. It must contain include/config_components.h")
endif()

if(NOT FFMPEG_KIT_BUILD_DATE)
    string(TIMESTAMP FFMPEG_KIT_BUILD_DATE "%Y%m%d")
endif()

if(NOT FFMPEG_KIT_BUNDLE_TYPE)
    set(FFMPEG_KIT_BUNDLE_TYPE "custom")
endif()

ffmpegkit_prepare_sources(KIT_SOURCES KIT_HEADERS)

# =============================================================================
# 4. DEPENDENCY MANAGEMENT: Library Resolution & Linking
# =============================================================================
# - Create ffmpegkit target with forced includes for TLS/assert overrides
# - Configure pkg-config for FFmpeg library detection
# - Define library resolution functions for cross-platform compatibility
# - Handle optional dependencies (libplacebo, TensorFlow, OpenVINO)
# - Fix broken include paths in generated pkg-config files
# ==============================================================================
add_library(ffmpegkit ${KIT_SOURCES} ${KIT_HEADERS})

target_compile_options(ffmpegkit PRIVATE
    "-include${CMAKE_CURRENT_SOURCE_DIR}/src/ffmpeg_tls.h"
    "-include${CMAKE_CURRENT_SOURCE_DIR}/src/ffmpeg_kit_assert_override.h"
)

set_source_files_properties(
    ${KIT_SOURCES}
    PROPERTIES COMPILE_OPTIONS "-Wno-attributes"
)

ffmpegkit_configure_dependencies(ffmpegkit BUNDLE_LIBRARIES)

# Do NOT rewrite BUNDLE_LIBRARIES here.
#
# For iOS, LZMA rewriting must happen exactly once, later in the final static
# link branch, after FFMPEG_STATIC_LIBS has been constructed and after the full
# FFmpeg + dependency archive list has been deduplicated.
#
# Rewriting here can cause:
#   - original FFmpeg archives to be linked later without rewriting
#   - original dependency archives to reappear through separate link paths
#   - duplicate symbols when both original and staged archives reach ld

# =============================================================================
# 5. TARGET CONFIGURATION: Compiler Flags & Platform Hardening
# =============================================================================
# - Set compiler standards, include directories, and optimization flags
# - Define preprocessor macros for FFmpeg compatibility
# - Apply platform-specific security hardening (DEP, ASLR, stack protection)
# - Configure Windows/MinGW, Linux, and Android-specific settings
# ==============================================================================
target_include_directories(ffmpegkit PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${FFMPEG_BUILD_DIR}/include"
)

link_directories("${FFMPEG_BUILD_DIR}/lib")
target_include_directories(ffmpegkit PUBLIC ${FFMPEG_INCLUDE_DIRS})

# Set C++ Standard to 17 (Required by prebuilt GoogleTest headers)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

target_compile_options(ffmpegkit PRIVATE -Os -ffunction-sections -fdata-sections)
target_compile_features(ffmpegkit PRIVATE cxx_std_17)

target_compile_definitions(ffmpegkit PRIVATE
    HAVE_CONFIG_H
    __STDC_CONSTANT_MACROS
    __STDC_LIMIT_MACROS
    __STDC_FORMAT_MACROS
)

target_compile_definitions(ffmpegkit PUBLIC
    FFMPEG_KIT_BUILD_DATE=${FFMPEG_KIT_BUILD_DATE}
    FFMPEG_KIT_BUNDLE_TYPE="${FFMPEG_KIT_BUNDLE_TYPE}"
    FFMPEG_KIT_VERSION="${FFMPEG_KIT_VERSION}"
)

if(WIN32)
    set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

    target_compile_definitions(ffmpegkit PRIVATE
        _WIN32 WIN32 TARGET_OS_WINDOWS FFMPEG_KIT_WINDOWS
        FFMPEG_KIT_BUILDING_DLL
    )

    if(MINGW)
        target_compile_definitions(ffmpegkit PRIVATE
            _WIN32_WINNT=0x0600
            _FORTIFY_SOURCE=2
        )

        target_compile_options(ffmpegkit PRIVATE
            -fstack-protector-strong
        )

        target_link_options(ffmpegkit PRIVATE
            "-v"
            "-static-libgcc"
            "-static-libstdc++"
            # "-nodefaultlibs"
            # "-Wl,--entry,_DllMainCRTStartup"
            "-Wl,--enable-runtime-pseudo-reloc"
            "-Wl,-u,__mingw_raise_matherr"
            "-Wl,--exclude-libs,libstdc++.a"
            "-Wl,--exclude-libs,libgcc.a"
            "-Wl,--exclude-libs,libgomp.a"
            "-Wl,--exclude-libs,libssp.a"
            "-Wl,--nxcompat"          # Data Execution Prevention (DEP)
            "-Wl,--dynamicbase"       # ASLR
            "-Wl,--high-entropy-va"   # 64-bit ASLR
            "-Wl,--enable-auto-import"
            "-Wl,--allow-multiple-definition"
            "-Wl,--stack,16777216"
        )

        target_compile_options(ffmpegkit PRIVATE
            "-mstackrealign"
            "-mpreferred-stack-boundary=4"
        )
    endif()
elseif(CMAKE_SYSTEM_NAME MATCHES "Linux")
    target_compile_definitions(ffmpegkit PRIVATE TARGET_OS_LINUX _FORTIFY_SOURCE=2)

    # Compilation flags for hardening
    target_compile_options(ffmpegkit PRIVATE
        -fstack-protector-strong
        -fvisibility=default
        -fPIC
    )

    # Linker hardening (RELRO and Bind Now)
    target_link_options(ffmpegkit PRIVATE
        "-Wl,-z,relro"
        "-Wl,-z,now"
        "-Wl,-z,noexecstack"
        "-Wl,--warn-common"
        "-Wl,--no-warn-mismatch"
    )

    pkg_check_modules(ALSA QUIET alsa)
    if(ALSA_FOUND)
        target_link_libraries(ffmpegkit PRIVATE
            ${ALSA_LIBRARIES}
            -lpthread
            -lm
            -ldl
        )
        target_include_directories(ffmpegkit PRIVATE ${ALSA_INCLUDE_DIRS})
    else()
        message(FATAL_ERROR "ALSA not found. Please install libasound-dev")
    endif()

    # Allow libffmpegkit.so to find sibling libs (e.g. libpulsecommon) in the
    # same directory it is installed into (Flutter bundle's lib/ folder)
    set_target_properties(ffmpegkit PROPERTIES
        INSTALL_RPATH "$ORIGIN"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
elseif(ANDROID)
    # Define Android-specific macros for source code compatibility
    target_compile_definitions(ffmpegkit PRIVATE
        TARGET_OS_ANDROID
        __ANDROID_API__=${ANDROID_NATIVE_API_LEVEL}
        _FORTIFY_SOURCE=2
    )

    # Link essential Android system libraries
    target_link_libraries(ffmpegkit PRIVATE
        log
        android
        jnigraphics
        m
        z
        atomic
        dl
    )

    # Android-specific hardening and visibility
    target_compile_options(ffmpegkit PRIVATE
        -fstack-protector-strong
        -fvisibility=default
        -fPIC
    )

    # Linker flags for Android (using LLD)
    target_link_options(ffmpegkit PRIVATE
        "-Wl,-z,relro"
        "-Wl,-z,now"
        "-Wl,-z,noexecstack"
        "-Wl,--warn-shared-textrel"
        "-Wl,--fatal-warnings"
        "-Wl,--allow-multiple-definition"
        "-Wl,--as-needed"
        # "-Wl,--verbose"
    )
elseif(APPLE)
    # iOS/macOS platform configuration
    target_compile_definitions(ffmpegkit PRIVATE TARGET_OS_APPLE _FORTIFY_SOURCE=2)

    target_compile_options(ffmpegkit PRIVATE
        -fstack-protector-strong
        -fvisibility=default
    )

    if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        target_link_libraries(ffmpegkit PRIVATE
            "-framework ForceFeedback"
            "-framework Carbon"
            "-framework AppKit"
            "-framework OpenGL"
            "-framework DiskArbitration"
        )
    elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")
        target_link_libraries(ffmpegkit PRIVATE
            "-framework OpenGLES"
            "-framework UIKit"
        )
    endif()

    target_link_libraries(ffmpegkit PRIVATE
        "-ObjC"
        "-framework AudioToolbox"
        "-framework AVFoundation"
        "-framework CoreAudio"
        "-framework Foundation"
        "-framework GameController"
        "-framework CoreHaptics"
        "-framework QuartzCore"
        "-framework CoreGraphics"
        "-framework CoreMedia"
        "-framework CoreImage"
        "-framework CoreMotion"
        "-framework CoreVideo"
        "-framework CoreText"
        "-framework Metal"
        "-framework Security"
        "-framework VideoToolbox"
        "-framework Accelerate"
        "-framework IOKit"
        "-lresolv"
    )

    # macOS can use SDK libiconv. iOS full/static bundles should use the
    # resolved static libiconv.a from BUNDLE_LIBRARIES instead. Keeping raw
    # -liconv on iOS can reintroduce /usr/lib/libiconv.dylib.
    if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
        target_link_libraries(ffmpegkit PRIVATE "-liconv")
    endif()

    target_link_options(ffmpegkit PRIVATE
        "-v"
        "-ld64"
        "-Wl,-w"
        "-Wl,-dead_strip"
        "-Wl,-twolevel_namespace"
        # "-Wl,-flat_namespace"
        # "-Wl,-undefined,dynamic_lookup"
    )
endif()

# =============================================================================
# 6. LINKING & SCRIPTS: Library Integration & Build Automation
# =============================================================================
# - Configure static vs dynamic linking with proper dependency ordering
# - Generate linker scripts to control symbol visibility
# - Execute post-build scripts for library bundling and merging
# - Handle platform-specific linking requirements (whole-archive, etc.)
# ==============================================================================
option(FFMPEG_STATIC "Link against static FFmpeg libraries" ON)

target_link_directories(ffmpegkit PRIVATE "${FFMPEG_BUILD_DIR}/lib")

if(BUILD_SHARED_LIBS)
    target_compile_definitions(ffmpegkit PRIVATE DLL_EXPORT PIC)

    if(NOT APPLE)
        # Darwin dylibs error on undefined symbols by default; no flag needed.
        # Linux shared libs require this opt-in.
        target_link_options(ffmpegkit PRIVATE -Wl,--no-undefined)
    endif()

    if(FFMPEG_STATIC)
        # Static Link Path: Use absolute paths and whole-archive to prevent symbol stripping
        set(FFMPEG_STATIC_LIBS
            "${FFMPEG_BUILD_DIR}/lib/libavdevice.a"
            "${FFMPEG_BUILD_DIR}/lib/libavfilter.a"
            "${FFMPEG_BUILD_DIR}/lib/libavformat.a"
            "${FFMPEG_BUILD_DIR}/lib/libavcodec.a"
            "${FFMPEG_BUILD_DIR}/lib/libswresample.a"
            "${FFMPEG_BUILD_DIR}/lib/libswscale.a"
            "${FFMPEG_BUILD_DIR}/lib/libavutil.a"
        )

        if(MINGW)
            target_link_libraries(ffmpegkit PRIVATE
                # 1. CRT and threading - must resolve before anything else
                "-Wl,-Bstatic"
                "-lstdc++"
                "-lgcc"
                "-lwinpthread"
                "-Wl,-Bdynamic"

                # 2. FFmpeg core - whole-archive to prevent dead-stripping of
                #    codecs and muxers that are referenced only by string tables
                "-Wl,--whole-archive"
                ${FFMPEG_STATIC_LIBS}
                "-Wl,--no-whole-archive"

                # 3. External dependency libs from pkg-config (SDL2, openmpt, rist,
                #    etc.) - grouped to resolve circular references between them.
                "-Wl,--start-group"
                ${BUNDLE_LIBRARIES}
                "-Wl,--end-group"

                # 4. Windows system DLLs - always dynamic, always last
                "-lkernel32"
                "-ladvapi32"
                "-luser32"
                "-lole32"
                "-lshlwapi"
                "-lbcrypt"
                "-lws2_32"
            )
        elseif(CMAKE_SYSTEM_NAME MATCHES "Linux")
            target_link_libraries(ffmpegkit PRIVATE
                "-Wl,--whole-archive"
                ${FFMPEG_STATIC_LIBS}
                ${ALSA_LIBRARIES}
                "-Wl,--no-whole-archive"
                ${BUNDLE_LIBRARIES}
            )
        elseif(ANDROID)
            target_link_libraries(ffmpegkit PRIVATE
                "-Wl,--whole-archive"
                ${FFMPEG_STATIC_LIBS}
                "-Wl,--no-whole-archive"
                ${BUNDLE_LIBRARIES}
            )
        elseif(APPLE)
            if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
                include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/FfmpegKitiOSStripLzma.cmake")

                set(APPLE_IOS_STATIC_LINK_LIBS
                    ${FFMPEG_STATIC_LIBS}
                    ${BUNDLE_LIBRARIES}
                )

                # Critical:
                # Deduplicate before rewriting so the final link line cannot
                # contain both an original archive and its staged rewritten copy.
                ffmpegkit_dedupe_link_list(APPLE_IOS_STATIC_LINK_LIBS)

                # Rewrites only .a archives and passes frameworks/.tbd/flags through.
                # This must run on the final deduped iOS static link list.
                rewrite_lzma_archives_for_ios(
                    "${APPLE_IOS_STATIC_LINK_LIBS}"
                    APPLE_IOS_STATIC_LINK_LIBS
                )

                target_link_libraries(ffmpegkit PRIVATE
                    ${APPLE_IOS_STATIC_LINK_LIBS}
                )
            else()
                target_link_libraries(ffmpegkit PRIVATE
                    ${FFMPEG_STATIC_LIBS}
                    ${BUNDLE_LIBRARIES}
                )
            endif()
        else()
            target_link_libraries(ffmpegkit PRIVATE
                ${FFMPEG_STATIC_LIBS}
                ${BUNDLE_LIBRARIES}
            )
        endif()
    else()
        if(MINGW)
            target_link_libraries(ffmpegkit PRIVATE
                "-Wl,--start-group"
                "${PTW32_STATIC_LIB}"
                ${BUNDLE_LIBRARIES}
                "pthread"
                "ws2_32"
                "bcrypt"
                "-Wl,--end-group"
            )
        else()
            target_link_libraries(ffmpegkit PRIVATE ${BUNDLE_LIBRARIES})
        endif()
    endif()

    # Append platform-specific trailing dependencies
    if(ANDROID)
        target_link_libraries(ffmpegkit PRIVATE OpenSLES)
    endif()

    # Linker Script
    # Ensure JNI symbols are kept global in the version script
    set(LINKER_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/ffmpeg-linker-script.map")
    file(WRITE ${LINKER_SCRIPT} "
{
    global:
        av*;
        swr*;
        sws*;
        ffmpeg*;
        ffprobe*;
        ffplay*;
        session*;
        media_information*;
        stream_information*;
        chapter*;
        Java_*;
        JNI_OnLoad;
        ffplay_kit_session_get_video_width;
        ffplay_kit_session_get_video_height;
        extern \"C++\" {
            ffmpegkit::*;
            typeinfo*for*ffmpegkit::*;
            typeinfo*name*for*ffmpegkit::*;
            vtable*for*ffmpegkit::*;
            Json::*;
            typeinfo*for*Json::*;
            typeinfo*name*for*Json::*;
            vtable*for*Json::*;
        };
    local:
        *;
};
")

    if(NOT APPLE)
        # --version-script is ELF/GNU ld only; macOS uses -exported_symbols_list instead.
        target_link_options(ffmpegkit PRIVATE "-Wl,--version-script=${LINKER_SCRIPT}")
    else()
        # Darwin exported symbols allow-list.
        #
        # Do NOT use broad patterns like:
        #   _ffmpeg*
        #   _ffprobe*
        #   _ffplay*
        #
        # _ffmpeg* also matches _ffmpegkit_lzma_* and leaks private-prefixed
        # dependency symbols into the final dylib ABI.
        set(APPLE_EXPORTED_SYMBOLS "${CMAKE_CURRENT_BINARY_DIR}/ffmpegkit-exported-symbols.txt")
        file(WRITE "${APPLE_EXPORTED_SYMBOLS}" "
_ffmpeg_kit_*
_ffprobe_kit_*
_ffplay_kit_*
_ffplay_kit_session_get_video_width
_ffplay_kit_session_get_video_height
_media_information*
_stream_information*
_chapter*
_session*
_Java_*
__ZN9ffmpegkit*
__ZTIN9ffmpegkit*
__ZTSN9ffmpegkit*
__ZTVN9ffmpegkit*
__ZN4Json*
__ZTIN4Json*
__ZTSN4Json*
__ZTVN4Json*
")

        target_link_options(ffmpegkit PRIVATE
            "-Wl,-exported_symbols_list,${APPLE_EXPORTED_SYMBOLS}"
        )
    endif()

    if(APPLE AND CMAKE_SYSTEM_NAME STREQUAL "iOS")
        include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/FfmpegKitiOSStripLzma.cmake")
        ffmpegkit_add_final_ios_lzma_check(ffmpegkit)
    endif()

    message(DEBUG "BUNDLE_LIBRARIES: ${BUNDLE_LIBRARIES}")

    # Bundling Manifest (Requires shared-library.sh)
    add_custom_command(TARGET ffmpegkit POST_BUILD
        COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/scripts/shared-library.sh" "${FFMPEG_BUILD_DIR}" "\"${BUNDLE_LIBRARIES}\""
        COMMENT "Generating bundle manifest for shared dependencies..."
    )
else()
    set(OUTPUT_LIB "$<TARGET_FILE:ffmpegkit>")
    add_custom_command(TARGET ffmpegkit POST_BUILD
        COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/scripts/static-library.sh"
                "${OUTPUT_LIB}"
                "${CMAKE_AR}"
                "${CMAKE_RANLIB}"
                "${FFMPEG_BUILD_DIR}"
                "\"${BUNDLE_LIBRARIES}\""
        COMMENT "Merging static libraries into monolithic archive..."
    )
endif()

# Install Hook for Bundled Libs
install(CODE "
    if(EXISTS \"${CMAKE_CURRENT_BINARY_DIR}/bundle_manifest.txt\")
        file(STRINGS \"${CMAKE_CURRENT_BINARY_DIR}/bundle_manifest.txt\" BUNDLE_LIBS)
        foreach(LIB \${BUNDLE_LIBS})
            # Standardize paths for CMake (Backslash to Forward Slash)
            string(REPLACE \"\\\\\" \"/\" LIB_CLEAN \"\${LIB}\")

            if(EXISTS \"\${LIB_CLEAN}\")
                message(STATUS \"Bundling: \${LIB_CLEAN}\")
                if(LIB_CLEAN MATCHES \"\\\\.dll$\")
                    # Windows DLLs go to bin
                    file(INSTALL DESTINATION \"\${CMAKE_INSTALL_PREFIX}/bin\"
                        TYPE SHARED_LIBRARY FILES \"\${LIB_CLEAN}\")
                else()
                    # Linux/Android .so go to lib
                    file(INSTALL DESTINATION \"\${CMAKE_INSTALL_PREFIX}/lib\"
                        TYPE SHARED_LIBRARY FILES \"\${LIB_CLEAN}\")
                endif()
            else()
                message(WARNING \"Bundle source not found: \${LIB_CLEAN}\")
            endif()
        endforeach()
    endif()
")

if(MINGW)
    target_link_libraries(ffmpegkit PRIVATE dbghelp)
endif()

# =============================================================================
# 7. INSTALLATION: Package Distribution Setup
# =============================================================================
# - Install library files (shared/static) to standard locations
# - Install public headers for client application development
# - Generate and install pkg-config file for dependency resolution
# ==============================================================================
install(TARGETS ffmpegkit
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/src/"
    DESTINATION include
    FILES_MATCHING PATTERN "*.h*"
)

configure_file("src/ffmpegkit.pc.in" "ffmpegkit.pc" @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/ffmpegkit.pc" DESTINATION lib/pkgconfig)

# =============================================================================
# 8. TESTING: Unit Test Framework Integration
# =============================================================================
# - Enable testing infrastructure with GoogleTest framework
# - Configure cross-platform test build settings
# - Handle Windows-specific CRT conflicts for test builds
# - Add test directory to build system
# ==============================================================================
if(BUILD_TESTS)
    set_target_properties(ffmpegkit PROPERTIES
        INSTALL_RPATH "$ORIGIN:$ORIGIN/pulseaudio:/usr/lib/pulseaudio:/usr/lib64/pulseaudio:${CMAKE_SOURCE_DIR}/../prebuilt/linux-x86_64/libraries/lib:${CMAKE_SOURCE_DIR}/../prebuilt/linux-x86_64/libraries/lib/pulseaudio"
        BUILD_WITH_INSTALL_RPATH TRUE
    )

    enable_testing()

    include(FetchContent)
    FetchContent_Declare(
        googletest
        URL https://github.com/google/googletest/archive/refs/tags/v1.17.0.zip
    )

    # For Windows: Prevent overriding the parent project's compiler/linker settings
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)

    # Build GoogleTest as static to avoid exporting runtime symbols and conflicting with libgcc_eh
    if(MINGW)
        set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
        set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
    endif()

    FetchContent_MakeAvailable(googletest)

    add_subdirectory(tests)

    install(TARGETS ffmpegkit_tests ffmpegkit_fate_tests DESTINATION bin)
endif()