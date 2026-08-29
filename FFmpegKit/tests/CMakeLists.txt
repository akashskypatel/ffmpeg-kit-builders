add_executable(ffmpegkit_tests
    main_test.cpp
    wrapper_test.cpp
    callback_test.cpp
    stress_test.cpp
    config_test.cpp
    runtime_reuse_test.cpp
    packages_test.cpp
)

target_link_libraries(ffmpegkit_tests
    PRIVATE
    ffmpegkit
    GTest::gtest_main
)

if(WIN32)
    target_link_libraries(ffmpegkit_tests PRIVATE ws2_32)
endif()

if(MINGW)
    target_link_options(ffmpegkit_tests PRIVATE "-Wl,--allow-multiple-definition")
endif()

# Ensure the test executable finds the shared libraries if needed
target_include_directories(ffmpegkit_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${FFMPEG_BUILD_DIR}/include
)

if(CMAKE_SYSTEM_NAME MATCHES "Linux")
    set_target_properties(ffmpegkit_tests PROPERTIES
        INSTALL_RPATH "$ORIGIN:$ORIGIN/..:$ORIGIN/../lib:/usr/lib/pulseaudio:/usr/lib64/pulseaudio:${CMAKE_SOURCE_DIR}/../prebuilt/linux-x86_64/libraries/lib:${CMAKE_SOURCE_DIR}/../prebuilt/linux-x86_64/libraries/lib/pulseaudio"
        BUILD_WITH_INSTALL_RPATH TRUE
    )

    set(PREBUILT_PULSE_DIR "${CMAKE_SOURCE_DIR}/../prebuilt/linux-x86_64/libraries/lib/pulseaudio")

    find_program(DBUS_RUN_SESSION dbus-run-session)
    if(DBUS_RUN_SESSION)
        add_test(NAME ffmpegkit_tests COMMAND ${DBUS_RUN_SESSION} $<TARGET_FILE:ffmpegkit_tests>)
    else()
        add_test(NAME ffmpegkit_tests COMMAND ffmpegkit_tests)
    endif()

    set_tests_properties(ffmpegkit_tests PROPERTIES
        ENVIRONMENT "LD_LIBRARY_PATH=${PREBUILT_PULSE_DIR}:/usr/lib/pulseaudio:/usr/lib64/pulseaudio:$ENV{LD_LIBRARY_PATH}"
    )
else()
    add_test(NAME ffmpegkit_tests COMMAND ffmpegkit_tests)
endif()

target_compile_definitions(ffmpegkit_tests PRIVATE 
    FFMPEG_KIT_TEST_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)

if(APPLE)
    set(DEBUG_PLIST_PATH "${CMAKE_BINARY_DIR}/debug.plist")
    file(WRITE "${DEBUG_PLIST_PATH}" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>")
    add_custom_command(TARGET ffmpegkit_tests POST_BUILD
        COMMAND codesign -f -s - --entitlements "${DEBUG_PLIST_PATH}" $<TARGET_FILE:ffmpegkit_tests>
        COMMENT "Signing ffmpegkit_tests for debugging"
    )
endif()
