include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/FfmpegKitLinkingHelpers.cmake")

function(ffmpegkit_configure_dependencies TARGET_NAME OUT_BUNDLE_LIBRARIES)
    set(BUNDLE_LIBRARIES "")

    set(_FFMPEGKIT_IOS_STATIC_BUNDLE OFF)
    if(APPLE AND CMAKE_SYSTEM_NAME STREQUAL "iOS")
        set(_FFMPEGKIT_IOS_STATIC_BUNDLE ON)
    endif()

    find_package(PkgConfig REQUIRED)

    message(STATUS "Setting PKG_CONFIG_PATH to: \"${FFMPEG_BUILD_DIR}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}\"")
    set(ENV{PKG_CONFIG_PATH} "${FFMPEG_BUILD_DIR}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")

    set(PKG_CONFIG_USE_STATIC_LIBS ON)

    pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET
        libavdevice libavfilter libavformat libavcodec libswresample libswscale libavutil jsoncpp sdl2 iconv bzip2 liblzma zlib
    )

    configure_static_linking(FFMPEG ON)

    if(ENABLE_LIBPLACEBO)
        set(_OLD_PKG_CONFIG_USE_STATIC_LIBS ${PKG_CONFIG_USE_STATIC_LIBS})
        set(PKG_CONFIG_USE_STATIC_LIBS OFF)
        pkg_check_modules(LIBPLACEBO REQUIRED IMPORTED_TARGET libplacebo)
        configure_static_linking(LIBPLACEBO ON)
        if(NOT _FFMPEGKIT_IOS_STATIC_BUNDLE)
            target_link_libraries(${TARGET_NAME} PRIVATE PkgConfig::LIBPLACEBO)
        endif()
        target_compile_definitions(${TARGET_NAME} PRIVATE PL_STATIC PLACEBO_STATIC)
        set(PKG_CONFIG_USE_STATIC_LIBS ${_OLD_PKG_CONFIG_USE_STATIC_LIBS})
    endif()

    if(ENABLE_LIBTENSORFLOW)
        set(_OLD_PKG_CONFIG_USE_STATIC_LIBS ${PKG_CONFIG_USE_STATIC_LIBS})
        set(PKG_CONFIG_USE_STATIC_LIBS OFF)
        pkg_check_modules(LIBTENSORFLOW REQUIRED IMPORTED_TARGET libtensorflow)
        configure_static_linking(LIBTENSORFLOW OFF)
        if(NOT _FFMPEGKIT_IOS_STATIC_BUNDLE)
            target_link_libraries(${TARGET_NAME} PRIVATE PkgConfig::LIBTENSORFLOW)
        endif()
        set(PKG_CONFIG_USE_STATIC_LIBS ${_OLD_PKG_CONFIG_USE_STATIC_LIBS})
    endif()

    if(ENABLE_OPENVINO)
        set(_OLD_PKG_CONFIG_USE_STATIC_LIBS ${PKG_CONFIG_USE_STATIC_LIBS})
        set(PKG_CONFIG_USE_STATIC_LIBS OFF)
        pkg_check_modules(OPENVINO REQUIRED IMPORTED_TARGET openvino)
        configure_static_linking(OPENVINO OFF)
        if(NOT _FFMPEGKIT_IOS_STATIC_BUNDLE)
            target_link_libraries(${TARGET_NAME} PRIVATE PkgConfig::OPENVINO)
        endif()
        set(_tbb_candidates tbb12 tbb libtbb libtbb12)
        foreach(_pkg ${_tbb_candidates})
            pkg_check_modules(TBB QUIET IMPORTED_TARGET ${_pkg})
            if(TBB_FOUND)
                break()
            endif()
        endforeach()
        if(NOT TBB_FOUND OR NOT TARGET PkgConfig::TBB)
            message(FATAL_ERROR "OpenVINO requires TBB but none of the following were found: ${_tbb_candidates}")
        endif()
        configure_static_linking(TBB OFF)
        if(NOT _FFMPEGKIT_IOS_STATIC_BUNDLE)
            target_link_libraries(${TARGET_NAME} PRIVATE PkgConfig::TBB)
        endif()
        set(PKG_CONFIG_USE_STATIC_LIBS ${_OLD_PKG_CONFIG_USE_STATIC_LIBS})
    endif()

    if(ENABLE_LIBTORCH)
        if(NOT WIN32)
            set(_OLD_PKG_CONFIG_USE_STATIC_LIBS ${PKG_CONFIG_USE_STATIC_LIBS})
            set(PKG_CONFIG_USE_STATIC_LIBS OFF)
            pkg_check_modules(LIBTORCH REQUIRED IMPORTED_TARGET libtorch)
            configure_static_linking(LIBTORCH OFF)
            if(NOT APPLE)
                find_library(PYTHON311_LIB
                    NAMES python3.11
                    PATHS /usr/lib64 /usr/lib /usr/local/lib64 /usr/local/lib /opt/homebrew/lib
                    NO_DEFAULT_PATH
                )
                if(NOT PYTHON311_LIB)
                    if(EXISTS "/usr/lib64/libpython3.11.so.1.0")
                        set(PYTHON311_LIB "/usr/lib64/libpython3.11.so.1.0")
                    elseif(EXISTS "/usr/lib/libpython3.11.so.1.0")
                        set(PYTHON311_LIB "/usr/lib/libpython3.11.so.1.0")
                    endif()
                endif()
                if(NOT PYTHON311_LIB)
                    message(FATAL_ERROR "Could not find libpython3.11 in /usr/lib64 or /usr/lib")
                else()
                    message(STATUS "Found Python 3.11 library: ${PYTHON311_LIB}")
                endif()
            endif()
            if(APPLE)
                pkg_check_modules(LIBOMP REQUIRED IMPORTED_TARGET libomp)
                configure_shared_linking(LIBOMP ON)
                if(NOT _FFMPEGKIT_IOS_STATIC_BUNDLE)
                    target_link_libraries(${TARGET_NAME} PRIVATE PkgConfig::LIBOMP)
                endif()
            elseif(CMAKE_SYSTEM_NAME MATCHES "Linux")
                find_library(LLVM17_LIB
                    NAMES LLVM-17 LLVM libLLVM-17
                    PATHS /usr/lib64/llvm17/lib /usr/lib64 /usr/lib
                    NO_DEFAULT_PATH
                )
                if(LLVM17_LIB)
                    message(STATUS "Found system LLVM-17: ${LLVM17_LIB} (linked before libtorch to prevent symbol conflicts)")
                    target_link_libraries(${TARGET_NAME} PRIVATE ${LLVM17_LIB})
                    get_filename_component(LLVM17_LIB_DIR "${LLVM17_LIB}" DIRECTORY)
                else()
                    message(WARNING "System LLVM-17 not found. LLVM symbol conflicts with libtensorflow may cause crashes.")
                endif()
            endif()

            if(NOT _FFMPEGKIT_IOS_STATIC_BUNDLE)
                target_link_libraries(${TARGET_NAME} PRIVATE
                    PkgConfig::LIBTORCH
                    ${PYTHON311_LIB}
                )
            endif()
            if(CMAKE_SYSTEM_NAME MATCHES "Linux")
                target_link_options(${TARGET_NAME} PRIVATE
                    "-Wl,-rpath,/usr/lib64"
                    $<$<BOOL:${LLVM17_LIB_DIR}>:-Wl,-rpath,${LLVM17_LIB_DIR}>
                )
            endif()
            set(PKG_CONFIG_USE_STATIC_LIBS ${_OLD_PKG_CONFIG_USE_STATIC_LIBS})
        endif()
    endif()

    if(TARGET PkgConfig::FFMPEG)
        get_target_property(RAW_INCLUDES PkgConfig::FFMPEG INTERFACE_INCLUDE_DIRECTORIES)
        set(VALID_INCLUDES "")
        if(RAW_INCLUDES)
            foreach(DIR ${RAW_INCLUDES})
                if(EXISTS "${DIR}")
                    list(APPEND VALID_INCLUDES "${DIR}")
                endif()
            endforeach()
            set_target_properties(PkgConfig::FFMPEG PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${VALID_INCLUDES}")
        endif()
    endif()

    set(${OUT_BUNDLE_LIBRARIES} "${BUNDLE_LIBRARIES}" PARENT_SCOPE)
endfunction()
