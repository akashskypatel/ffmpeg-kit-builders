add_executable(ffmpegkit_tests
    main_test.cpp
    wrapper_test.cpp
    callback_test.cpp
    callback_lock_test.cpp
    pthread_failure_test.cpp
    stress_test.cpp
    wrapper_callback_state_test.cpp
    session_id_callback_test.cpp
    wasm_callback_dispatcher_test.cpp
    session_completion_test.cpp
    log_statistics_test.cpp
    ../src/WasmCallbackDispatcher.cpp
    config_test.cpp
    runtime_reuse_test.cpp
    packages_test.cpp
    callback_abi_contract_test.cpp
)

target_link_libraries(ffmpegkit_tests
    PRIVATE
    ffmpegkit
    GTest::gtest_main
)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(OpenSSL REQUIRED)
    target_link_libraries(ffmpegkit_tests PRIVATE OpenSSL::SSL OpenSSL::Crypto ${CMAKE_DL_LIBS})
    target_compile_definitions(ffmpegkit_tests PRIVATE FFMPEG_KIT_TEST_TLS=1)
endif()

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

if(NOT EMSCRIPTEN)
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
endif()

add_test(
    NAME ffmpegkit_cmake_linking_helpers
    COMMAND ${CMAKE_COMMAND}
        -DFFMPEGKIT_TEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/cmake-linking-helpers-fixture
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/linking_helpers_test.cmake
)

target_compile_definitions(ffmpegkit_tests PRIVATE 
    FFMPEG_KIT_TEST_HOOKS
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
if(EMSCRIPTEN)
    foreach(_gtest_target IN ITEMS gtest gtest_main)
        if(TARGET ${_gtest_target})
            target_compile_options(${_gtest_target} PRIVATE
                -pthread
                -fwasm-exceptions
                "-sSUPPORT_LONGJMP=wasm"
            )
        endif()
    endforeach()

    function(add_ffmpegkit_wasm_callback_test target source)
        add_executable(${target}
            ${source}
            ../src/WasmCallbackDispatcher.cpp
        )
        target_link_libraries(${target} PRIVATE ffmpegkit GTest::gtest_main)
        target_include_directories(${target} PRIVATE
            ${CMAKE_SOURCE_DIR}/src
            ${FFMPEG_BUILD_DIR}/include
        )
        target_compile_features(${target} PRIVATE cxx_std_17)
        target_compile_definitions(${target} PRIVATE FFMPEG_KIT_TEST_HOOKS)
        target_compile_options(${target} PRIVATE
            -pthread
            -fwasm-exceptions
            "-sSUPPORT_LONGJMP=wasm"
        )
        target_link_options(${target} PRIVATE
            -pthread
            -fwasm-exceptions
            "-sSUPPORT_LONGJMP=wasm"
            "-sPTHREAD_POOL_SIZE=${FFMPEG_KIT_WASM_PTHREAD_POOL_SIZE}"
            "-sEXIT_RUNTIME=1"
            "-sENVIRONMENT=node"
        )
        add_test(NAME ${target} COMMAND node $<TARGET_FILE:${target}>)
    endfunction()

    set(_ffmpegkit_wasm_callback_test_targets
        ffmpegkit_wasm_authority_tests
        ffmpegkit_wasm_callback_lock_tests
        ffmpegkit_wasm_pthread_failure_tests
        ffmpegkit_wasm_wrapper_state_tests
        ffmpegkit_wasm_session_id_tests
        ffmpegkit_wasm_session_completion_tests
        ffmpegkit_wasm_log_statistics_tests
        ffmpegkit_wasm_callback_abi_tests
        ffmpegkit_wasm_dispatcher_tests
        ffmpegkit_wasm_ffplay_frame_tests
    )

    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_authority_tests wasm_callback_test.cpp)
    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_callback_lock_tests callback_lock_test.cpp)
    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_pthread_failure_tests pthread_failure_test.cpp)
    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_wrapper_state_tests wrapper_callback_state_test.cpp)
    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_session_id_tests session_id_callback_test.cpp)
    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_session_completion_tests session_completion_test.cpp)
    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_log_statistics_tests log_statistics_test.cpp)
    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_callback_abi_tests callback_abi_contract_test.cpp)
    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_dispatcher_tests wasm_callback_dispatcher_test.cpp)
    add_ffmpegkit_wasm_callback_test(ffmpegkit_wasm_ffplay_frame_tests ffplay_frame_callback_test.cpp)

    add_custom_target(ffmpegkit_wasm_callback_tests
        DEPENDS ${_ffmpegkit_wasm_callback_test_targets})

    add_test(
        NAME ffmpegkit_wasm_table_growth
        COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/table_growth_test.mjs"
                "${CMAKE_BINARY_DIR}/ffmpegkit.wasm"
    )
endif()
