# =============================================================================
# iOS LZMA Symbol Rewrite
# =============================================================================
#
# Purpose:
#   Apple may flag unprefixed _lzma_* symbols as non-public API usage even when
#   liblzma is statically merged. This helper rewrites all _lzma_* symbols in
#   the final static archive link list to _ffmpegkit_lzma_* before those archives
#   are linked into libffmpegkit.dylib.
#
# Important:
#   - Run this only for iOS.
#   - Run it exactly once on the final deduped link list.
#   - The input list may contain .a files, .tbd files, frameworks, and flags.
#   - Non-archive entries are passed through unchanged.
# =============================================================================

function(ffmpegkit_dedupe_link_list INPUT_VAR)
    set(_out "")
    set(_seen "")

    foreach(_item IN LISTS ${INPUT_VAR})
        if("${_item}" STREQUAL "")
            continue()
        endif()

        if(EXISTS "${_item}")
            get_filename_component(_key "${_item}" REALPATH)
        else()
            set(_key "${_item}")
        endif()

        list(FIND _seen "${_key}" _found)
        if(_found EQUAL -1)
            list(APPEND _seen "${_key}")
            list(APPEND _out "${_item}")
        endif()
    endforeach()

    set(${INPUT_VAR} "${_out}" PARENT_SCOPE)
endfunction()

function(rewrite_lzma_archives_for_ios INPUT_LIBS OUTPUT_VAR)
    if(NOT APPLE OR NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
        set(${OUTPUT_VAR} "${INPUT_LIBS}" PARENT_SCOPE)
        return()
    endif()

    set(_llvm_objcopy_hints "")
    foreach(_hint
        "$ENV{LLVM_HOME}/bin"
        "$ENV{LLVM_ROOT}/bin"
        "$ENV{HOMEBREW_PREFIX}/opt/llvm/bin"
        /opt/homebrew/opt/llvm/bin
        /usr/local/opt/llvm/bin
    )
        if(NOT "${_hint}" STREQUAL "/bin" AND NOT "${_hint}" STREQUAL "")
            list(APPEND _llvm_objcopy_hints "${_hint}")
        endif()
    endforeach()

    find_program(LLVM_OBJCOPY_EXE
        NAMES llvm-objcopy
        HINTS ${_llvm_objcopy_hints}
    )
    if(NOT LLVM_OBJCOPY_EXE)
        message(FATAL_ERROR
            "llvm-objcopy is required for iOS LZMA symbol rewriting. "
            "Searched PATH and hints: ${_llvm_objcopy_hints}"
        )
    endif()

    if(NOT CMAKE_RANLIB)
        find_program(CMAKE_RANLIB ranlib)
    endif()

    if(NOT CMAKE_RANLIB)
        message(FATAL_ERROR "ranlib is required for iOS LZMA symbol rewriting")
    endif()

    set(_script_dir "${CMAKE_CURRENT_SOURCE_DIR}/scripts")
    set(_stage_dir "${CMAKE_CURRENT_BINARY_DIR}/ios-lzma-rewritten-libs")
    set(_map_file "${CMAKE_CURRENT_BINARY_DIR}/ios-lzma-symbol-map.txt")
    set(_input_list "${CMAKE_CURRENT_BINARY_DIR}/ios-lzma-input-libs.txt")
    set(_output_list "${CMAKE_CURRENT_BINARY_DIR}/ios-lzma-output-libs.txt")

    foreach(_script
        generate-lzma-map-from-libs.sh
        rewrite-lzma-libs-from-list.sh
        check-rewritten-lzma-libs-from-list.sh
    )
        if(NOT EXISTS "${_script_dir}/${_script}")
            message(FATAL_ERROR "Required script not found: ${_script_dir}/${_script}")
        endif()
    endforeach()

    file(REMOVE_RECURSE "${_stage_dir}")
    file(MAKE_DIRECTORY "${_stage_dir}")

    # Preserve the complete mixed link list. The rewrite script will pass through
    # non-.a entries unchanged so the output list stays 1:1 with this list.
    file(WRITE "${_input_list}" "")
    foreach(_item IN LISTS INPUT_LIBS)
        if(NOT "${_item}" STREQUAL "")
            file(APPEND "${_input_list}" "${_item}\n")
        endif()
    endforeach()

    execute_process(
        COMMAND bash "${_script_dir}/generate-lzma-map-from-libs.sh"
                "${_input_list}"
                "${_map_file}"
        RESULT_VARIABLE _map_result
    )
    if(NOT _map_result EQUAL 0)
        message(FATAL_ERROR "Failed to generate iOS LZMA rename map")
    endif()

    execute_process(
        COMMAND bash "${_script_dir}/rewrite-lzma-libs-from-list.sh"
                "${_input_list}"
                "${_stage_dir}"
                "${_map_file}"
                "${LLVM_OBJCOPY_EXE}"
                "${CMAKE_RANLIB}"
                "${_output_list}"
        RESULT_VARIABLE _rewrite_result
    )
    if(NOT _rewrite_result EQUAL 0)
        message(FATAL_ERROR "Failed to rewrite iOS LZMA symbols")
    endif()

    execute_process(
        COMMAND bash "${_script_dir}/check-rewritten-lzma-libs-from-list.sh"
                "${_output_list}"
        RESULT_VARIABLE _check_result
    )
    if(NOT _check_result EQUAL 0)
        message(FATAL_ERROR "Rewritten iOS archives still contain unprefixed _lzma_* symbols")
    endif()

    file(STRINGS "${_output_list}" _final_libs)

    list(LENGTH INPUT_LIBS _input_count)
    list(LENGTH _final_libs _output_count)
    if(NOT _input_count EQUAL _output_count)
        message(FATAL_ERROR
            "iOS LZMA rewrite changed link list length: "
            "input=${_input_count}, output=${_output_count}"
        )
    endif()

    set(${OUTPUT_VAR} "${_final_libs}" PARENT_SCOPE)
endfunction()

function(ffmpegkit_add_final_ios_lzma_check TARGET_NAME)
    if(NOT APPLE OR NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
        return()
    endif()

    set(_check_script "${CMAKE_CURRENT_SOURCE_DIR}/scripts/check-final-ios-lzma.sh")
    if(NOT EXISTS "${_check_script}")
        message(FATAL_ERROR "Required script not found: ${_check_script}")
    endif()

    add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
        COMMAND bash "${_check_script}" "$<TARGET_FILE:${TARGET_NAME}>"
        VERBATIM
        COMMENT "Checking final iOS dylib for unprefixed/exported LZMA symbols"
    )
endfunction()
