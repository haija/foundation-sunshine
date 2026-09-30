# NVIDIA SDK code stays inside an optional MSVC DLL. The MinGW host consumes
# only the stable C ABI and therefore remains startable when the component or
# the Microsoft runtime is unavailable.
set(SUNSHINE_RTX_HDR "AUTO" CACHE STRING "Build RTX HDR support: AUTO, ON or OFF")
set_property(CACHE SUNSHINE_RTX_HDR PROPERTY STRINGS AUTO ON OFF)
string(TOUPPER "${SUNSHINE_RTX_HDR}" _rtx_mode)
if (NOT _rtx_mode MATCHES "^(AUTO|ON|OFF)$")
    message(FATAL_ERROR "SUNSHINE_RTX_HDR must be AUTO, ON or OFF")
endif ()
set(SUNSHINE_RTX_HDR_AVAILABLE FALSE CACHE INTERNAL "RTX HDR adapter is configured" FORCE)
if (_rtx_mode STREQUAL "OFF" OR NOT WIN32)
    unset(_SUNSHINE_RTX_VIDEO_SDK_TOKEN)
    if (_rtx_mode STREQUAL "ON" AND NOT WIN32)
        message(FATAL_ERROR "RTX HDR support requires Windows")
    endif ()
    return()
endif ()

include("${CMAKE_CURRENT_LIST_DIR}/FetchRtxVideoSdk.cmake")
sunshine_find_rtx_video_sdk(_rtx_sdk_root _rtx_reason)
unset(_SUNSHINE_RTX_VIDEO_SDK_TOKEN)
if (NOT _rtx_sdk_root)
    if (_rtx_mode STREQUAL "ON")
        message(FATAL_ERROR "RTX HDR is required, but ${_rtx_reason}")
    endif ()
    message(STATUS "RTX HDR disabled: ${_rtx_reason}")
    return()
endif ()

set(RTX_VIDEO_NGX_APPLICATION_ID "" CACHE STRING "NGX application ID; empty uses the environment or development ID 0")
set(_rtx_app_id "$ENV{RTX_VIDEO_NGX_APPLICATION_ID}")
if (_rtx_app_id STREQUAL "")
    set(_rtx_app_id "${RTX_VIDEO_NGX_APPLICATION_ID}")
endif ()
if (_rtx_app_id STREQUAL "")
    set(_rtx_app_id "0")
endif ()
# The application ID is not an access credential. Retain it for Ninja-triggered
# reconfiguration after the CI environment has been cleared.
set(RTX_VIDEO_NGX_APPLICATION_ID "${_rtx_app_id}" CACHE STRING "NGX application ID" FORCE)

set(_rtx_source "${CMAKE_SOURCE_DIR}/src/platform/windows/image_enhancement/rtx_hdr/adapter")
set(_rtx_build "${CMAKE_BINARY_DIR}/image_enhancement/nvidia_rtx_video_adapter")
set(RTX_VIDEO_ADAPTER_PREBUILT "" CACHE FILEPATH "Explicitly supplied RTX Video adapter; provenance and licensing require separate verification")
set(RTX_VIDEO_ADAPTER_EXPECTED_SHA256 "" CACHE STRING "Independently verified SHA256 of the supplied adapter")
set(RTX_VIDEO_RUNTIME_EXPECTED_SHA256 "" CACHE STRING "Independently verified SHA256 of the supplied NVIDIA runtime")
if (RTX_VIDEO_ADAPTER_PREBUILT)
    if (NOT EXISTS "${RTX_VIDEO_ADAPTER_PREBUILT}" OR IS_DIRECTORY "${RTX_VIDEO_ADAPTER_PREBUILT}")
        message(FATAL_ERROR "Prebuilt RTX Video adapter is missing: ${RTX_VIDEO_ADAPTER_PREBUILT}")
    endif ()
    foreach (_component IN ITEMS ADAPTER RUNTIME)
        string(LENGTH "${RTX_VIDEO_${_component}_EXPECTED_SHA256}" _hash_length)
        if (NOT _hash_length EQUAL 64 OR NOT RTX_VIDEO_${_component}_EXPECTED_SHA256 MATCHES "^[0-9a-fA-F]+$")
            message(FATAL_ERROR "Prebuilt mode requires RTX_VIDEO_${_component}_EXPECTED_SHA256 from separately verified inputs")
        endif ()
    endforeach ()
    set(RTX_VIDEO_ADAPTER_DLL "${RTX_VIDEO_ADAPTER_PREBUILT}")
else ()
    set(RTX_VIDEO_ADAPTER_DLL "${_rtx_build}/Release/foundation_rtx_video_adapter.dll")
endif ()
set(RTX_VIDEO_RUNTIME_DLL "${_rtx_sdk_root}/bin/Windows/x64/rel/nvngx_truehdr.dll")
if (RTX_VIDEO_ADAPTER_PREBUILT)
    foreach (_component IN ITEMS ADAPTER RUNTIME)
        file(SHA256 "${RTX_VIDEO_${_component}_DLL}" _actual_hash)
        string(TOLOWER "${RTX_VIDEO_${_component}_EXPECTED_SHA256}" _expected_hash)
        if (NOT _actual_hash STREQUAL _expected_hash)
            message(FATAL_ERROR "Supplied RTX Video ${_component} does not match the expected SHA256")
        endif ()
    endforeach ()
endif ()
set(RTX_VIDEO_TRUST_INCLUDE "${CMAKE_BINARY_DIR}/generated/rtx_video")
set(RTX_VIDEO_TRUST_HEADER "${RTX_VIDEO_TRUST_INCLUDE}/rtx_video_trust.h")
set(_rtx_adapter_sources
    "${_rtx_source}/CMakeLists.txt"
    "${_rtx_source}/src/truehdr_adapter.cpp"
    "${CMAKE_SOURCE_DIR}/src/platform/windows/image_enhancement/rtx_hdr/adapter_abi.h")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${_rtx_adapter_sources}
    "${RTX_VIDEO_RUNTIME_DLL}"
    "${_rtx_sdk_root}/lib/Windows/x64/nvsdk_ngx_d.lib")

file(SHA256 "${_rtx_source}/CMakeLists.txt" _rtx_cmake_hash)
file(SHA256 "${_rtx_source}/src/truehdr_adapter.cpp" _rtx_source_hash)
file(SHA256 "${CMAKE_SOURCE_DIR}/src/platform/windows/image_enhancement/rtx_hdr/adapter_abi.h" _rtx_abi_hash)
file(SHA256 "${RTX_VIDEO_RUNTIME_DLL}" _rtx_runtime_hash)
file(SHA256 "${_rtx_sdk_root}/lib/Windows/x64/nvsdk_ngx_d.lib" _rtx_client_hash)
string(SHA256 _rtx_inputs
    "${_rtx_sdk_root}|${_rtx_app_id}|${_rtx_cmake_hash}|${_rtx_source_hash}|${_rtx_abi_hash}|${_rtx_runtime_hash}|${_rtx_client_hash}")
set(_rtx_previous "")
if (EXISTS "${_rtx_build}/configure-inputs")
    file(READ "${_rtx_build}/configure-inputs" _rtx_previous)
endif ()
if (NOT RTX_VIDEO_ADAPTER_PREBUILT AND (NOT _rtx_inputs STREQUAL _rtx_previous OR NOT EXISTS "${_rtx_build}/CMakeCache.txt"))
    set(_rtx_configured "1")
    set(_rtx_configure_log "")
    foreach (_rtx_generator IN ITEMS "Visual Studio 18 2026" "Visual Studio 17 2022")
        execute_process(COMMAND "${CMAKE_COMMAND}" -S "${_rtx_source}" -B "${_rtx_build}"
            -G "${_rtx_generator}" -A x64
            "-DNVIDIA_RTX_VIDEO_SDK_DIR=${_rtx_sdk_root}"
            "-DRTX_VIDEO_NGX_APPLICATION_ID=${_rtx_app_id}"
            "-DSUNSHINE_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
            RESULT_VARIABLE _rtx_configured OUTPUT_VARIABLE _rtx_stdout ERROR_VARIABLE _rtx_stderr TIMEOUT 120)
        string(APPEND _rtx_configure_log
            "generator=${_rtx_generator}\nresult=${_rtx_configured}\nstdout:\n${_rtx_stdout}\nstderr:\n${_rtx_stderr}\n")
        if (_rtx_configured STREQUAL "0")
            break()
        endif ()

        # A failed configure may leave a generator-specific cache behind. Remove
        # only the generated metadata before trying the older supported toolset.
        file(REMOVE_RECURSE "${_rtx_build}/CMakeCache.txt" "${_rtx_build}/CMakeFiles")
    endforeach ()
    if (NOT _rtx_configured STREQUAL "0")
        file(MAKE_DIRECTORY "${_rtx_build}")
        file(WRITE "${_rtx_build}/configure.log" "${_rtx_configure_log}")
        if (_rtx_mode STREQUAL "ON")
            message(FATAL_ERROR
                "RTX HDR adapter configuration failed:\n${_rtx_configure_log}")
        endif ()
        message(STATUS "RTX HDR disabled: adapter configuration failed; see ${_rtx_build}/configure.log")
        return()
    endif ()
    file(WRITE "${_rtx_build}/configure-inputs" "${_rtx_inputs}")
endif ()

file(MAKE_DIRECTORY "${RTX_VIDEO_TRUST_INCLUDE}")
if (RTX_VIDEO_ADAPTER_PREBUILT)
    add_custom_command(
        OUTPUT "${RTX_VIDEO_TRUST_HEADER}"
        COMMAND "${CMAKE_COMMAND}"
            "-DADAPTER_PATH=${RTX_VIDEO_ADAPTER_DLL}"
            "-DRUNTIME_PATH=${RTX_VIDEO_RUNTIME_DLL}"
            "-DEXPECTED_ADAPTER_SHA256=${RTX_VIDEO_ADAPTER_EXPECTED_SHA256}"
            "-DEXPECTED_RUNTIME_SHA256=${RTX_VIDEO_RUNTIME_EXPECTED_SHA256}"
            "-DOUTPUT_PATH=${RTX_VIDEO_TRUST_HEADER}"
            -P "${CMAKE_CURRENT_LIST_DIR}/GenerateRtxVideoTrustHeader.cmake"
        DEPENDS "${RTX_VIDEO_ADAPTER_DLL}" "${RTX_VIDEO_RUNTIME_DLL}"
            "${CMAKE_CURRENT_LIST_DIR}/GenerateRtxVideoTrustHeader.cmake"
        COMMENT "Checking supplied RTX Video inputs against explicit hashes"
        VERBATIM)
else ()
    add_custom_command(
        OUTPUT "${RTX_VIDEO_TRUST_HEADER}"
        COMMAND "${CMAKE_COMMAND}" --build "${_rtx_build}" --config Release
            --target foundation_rtx_video_adapter
        COMMAND "${CMAKE_COMMAND}"
            "-DADAPTER_PATH=${RTX_VIDEO_ADAPTER_DLL}"
            "-DRUNTIME_PATH=${RTX_VIDEO_RUNTIME_DLL}"
            "-DOUTPUT_PATH=${RTX_VIDEO_TRUST_HEADER}"
            -P "${CMAKE_CURRENT_LIST_DIR}/GenerateRtxVideoTrustHeader.cmake"
        DEPENDS ${_rtx_adapter_sources}
            "${_rtx_build}/configure-inputs"
            "${RTX_VIDEO_RUNTIME_DLL}"
            "${_rtx_sdk_root}/lib/Windows/x64/nvsdk_ngx_d.lib"
            "${CMAKE_CURRENT_LIST_DIR}/GenerateRtxVideoTrustHeader.cmake"
        BYPRODUCTS "${RTX_VIDEO_ADAPTER_DLL}"
        COMMENT "Building and fingerprinting the optional MSVC RTX Video adapter"
        VERBATIM)
endif ()
add_custom_target(sunshine_rtx_video_adapter DEPENDS "${RTX_VIDEO_TRUST_HEADER}")
set(SUNSHINE_RTX_HDR_AVAILABLE TRUE CACHE INTERNAL "RTX HDR adapter is configured" FORCE)
message(STATUS "RTX HDR support enabled; the adapter and NVIDIA runtime remain optional at run time")
