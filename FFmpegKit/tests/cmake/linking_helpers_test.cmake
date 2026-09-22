cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED FFMPEGKIT_TEST_ROOT OR "${FFMPEGKIT_TEST_ROOT}" STREQUAL "")
    message(FATAL_ERROR "FFMPEGKIT_TEST_ROOT is required")
endif()

set(CMAKE_SYSTEM_NAME Linux)
set(EMSCRIPTEN OFF)
set(DEPENDENCY_BUILD_DIR "${FFMPEGKIT_TEST_ROOT}/dependency")
set(FFMPEG_BUILD_DIR "${FFMPEGKIT_TEST_ROOT}/ffmpeg")
set(_pkg_a "${FFMPEGKIT_TEST_ROOT}/pkg-a/lib/pkgconfig")
set(_pkg_b "${FFMPEGKIT_TEST_ROOT}/pkg-b/lib/pkgconfig")
set(_outside "${FFMPEGKIT_TEST_ROOT}/outside/lib")

file(REMOVE_RECURSE "${FFMPEGKIT_TEST_ROOT}")
file(MAKE_DIRECTORY
    "${DEPENDENCY_BUILD_DIR}/lib"
    "${DEPENDENCY_BUILD_DIR}/lib/nested/project"
    "${FFMPEG_BUILD_DIR}/lib"
    "${_pkg_a}/../nested/a"
    "${_pkg_b}/../nested/b"
    "${_outside}"
)

file(WRITE "${DEPENDENCY_BUILD_DIR}/lib/libdirect.a" "direct")
file(WRITE "${DEPENDENCY_BUILD_DIR}/lib/nested/project/libproject.a" "project")
file(WRITE "${_pkg_a}/../nested/a/libfoo.a" "pkg-a")
file(WRITE "${_pkg_b}/../nested/b/libfoo.a" "pkg-b")
file(WRITE "${_pkg_b}/../nested/b/libshared.a" "pkg-b-decoy")
file(WRITE "${DEPENDENCY_BUILD_DIR}/lib/nested/project/libshared.a" "project-shared")
file(WRITE "${_outside}/libshared.so" "shared")

set(ENV{PKG_CONFIG_PATH} "${_pkg_a}:${_pkg_b}")
include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/FfmpegKitLinkingHelpers.cmake")

function(assert_equal EXPECTED ACTUAL LABEL)
    if(NOT "${EXPECTED}" STREQUAL "${ACTUAL}")
        message(FATAL_ERROR "${LABEL}: expected '${EXPECTED}', got '${ACTUAL}'")
    endif()
endfunction()

find_static_library_in_pkg_config_path("-lfoo" _foo)
assert_equal("${FFMPEGKIT_TEST_ROOT}/pkg-a/lib/nested/a/libfoo.a" "${_foo}" "first pkg-config root wins")

find_static_library_in_pkg_config_path("-ldirect" _direct)
assert_equal("${DEPENDENCY_BUILD_DIR}/lib/libdirect.a" "${_direct}" "direct project archive")

find_static_library_in_pkg_config_path("-lmissing" _missing_first)
find_static_library_in_pkg_config_path("-lmissing" _missing_second)
assert_equal("" "${_missing_first}" "missing archive")
assert_equal("" "${_missing_second}" "cached missing archive")

replace_shared_with_static("${_outside}/libshared.so" _shared_replacement)
assert_equal(
    "${DEPENDENCY_BUILD_DIR}/lib/nested/project/libshared.a"
    "${_shared_replacement}"
    "shared-to-static project resolution"
)

find_project_static_library_for_link("-lproject" _project)
assert_equal("${DEPENDENCY_BUILD_DIR}/lib/nested/project/libproject.a" "${_project}" "project nested archive")

file(REMOVE_RECURSE "${FFMPEGKIT_TEST_ROOT}")
message(STATUS "CMake linking helper fixture passed")
