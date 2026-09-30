if (NOT DEFINED SOURCE_ROOT OR NOT DEFINED TEST_ROOT)
  message(FATAL_ERROR "SOURCE_ROOT and TEST_ROOT are required")
endif ()
file(MAKE_DIRECTORY "${TEST_ROOT}")
# Inert text fixtures; never loaded as executable code.
file(WRITE "${TEST_ROOT}/adapter.dat" "adapter fixture")
file(WRITE "${TEST_ROOT}/runtime.dat" "runtime fixture")
file(SHA256 "${TEST_ROOT}/adapter.dat" _adapter)
file(SHA256 "${TEST_ROOT}/runtime.dat" _runtime)
set(_arguments
  "-DADAPTER_PATH=${TEST_ROOT}/adapter.dat"
  "-DRUNTIME_PATH=${TEST_ROOT}/runtime.dat"
  "-DOUTPUT_PATH=${TEST_ROOT}/generated.h"
  "-DEXPECTED_ADAPTER_SHA256=${_adapter}"
  "-DEXPECTED_RUNTIME_SHA256=${_runtime}"
  -P "${SOURCE_ROOT}/cmake/dependencies/GenerateRtxVideoTrustHeader.cmake")
execute_process(COMMAND "${CMAKE_COMMAND}" ${_arguments} RESULT_VARIABLE _result)
if (NOT _result EQUAL 0)
  message(FATAL_ERROR "Correct supplied hashes must be accepted")
endif ()
file(WRITE "${TEST_ROOT}/adapter.dat" "changed adapter fixture")
execute_process(COMMAND "${CMAKE_COMMAND}" ${_arguments}
  RESULT_VARIABLE _result OUTPUT_QUIET ERROR_QUIET)
if (_result EQUAL 0)
  message(FATAL_ERROR "Changed adapter must be rejected")
endif ()
file(WRITE "${TEST_ROOT}/adapter.dat" "adapter fixture")
file(WRITE "${TEST_ROOT}/runtime.dat" "changed runtime fixture")
execute_process(COMMAND "${CMAKE_COMMAND}" ${_arguments}
  RESULT_VARIABLE _result OUTPUT_QUIET ERROR_QUIET)
if (_result EQUAL 0)
  message(FATAL_ERROR "Changed runtime must be rejected")
endif ()
message(STATUS "PASS: matching hashes accepted; changed adapter/runtime rejected")
