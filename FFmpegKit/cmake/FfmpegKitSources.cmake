include_guard(GLOBAL)

function(ffmpegkit_prepare_sources OUT_SOURCES OUT_HEADERS)
    message(STATUS "Preparing source tree...")
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/src")

    file(COPY "${FFMPEG_BUILD_DIR}/include/config.h" DESTINATION "${CMAKE_CURRENT_SOURCE_DIR}/src/")
    file(COPY "${FFMPEG_BUILD_DIR}/include/config_components.h" DESTINATION "${CMAKE_CURRENT_SOURCE_DIR}/src/")

    message(STATUS "Patching config.h for SDL compatibility...")
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/config.h" CONFIG_H_CONTENT)
    string(REPLACE "#define HAVE_PTHREAD_SETNAME_NP 0" "" CONFIG_H_CONTENT "${CONFIG_H_CONTENT}")
    file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/src/config.h" "${CONFIG_H_CONTENT}")

    file(GLOB_RECURSE KIT_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp"
    )

    if(APPLE)
        file(GLOB_RECURSE KIT_OBJC_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/*.m")
        list(APPEND KIT_SOURCES ${KIT_OBJC_SOURCES})
    endif()

    file(GLOB_RECURSE KIT_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h")

    list(REMOVE_ITEM KIT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/ffplay.c")
    list(REMOVE_ITEM KIT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/ffprobe.c")

    if(MINGW)
        list(REMOVE_ITEM KIT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/pthread_compat.c")
        list(REMOVE_ITEM KIT_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/src/pthread_compat.h")
    endif()

    list(FILTER KIT_SOURCES EXCLUDE REGEX ".*_(bak|orig)\\.(c|cpp)$")
    list(FILTER KIT_HEADERS EXCLUDE REGEX ".*_(bak|orig)\\.h$")

    if(APPLE)
        generate_apple_resource_files()
    endif()

    set(${OUT_SOURCES} "${KIT_SOURCES}" PARENT_SCOPE)
    set(${OUT_HEADERS} "${KIT_HEADERS}" PARENT_SCOPE)
endfunction()
