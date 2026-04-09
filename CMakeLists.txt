# =============================================================================
# CMakeLists.txt  —  qiskit-fortran
#
# Builds two targets:
#   qiskit_fortran  — static library containing both modules
#   test_qiskit     — test executable linked against the library
#
# Required CMake variables:
#   QISKIT_ROOT   Path to the Qiskit repo after running `make c`
#                 (contains dist/c/include/qiskit.h and dist/c/lib/libqiskit.so)
#
# =============================================================================

cmake_minimum_required(VERSION 3.20)

project(qiskit_fortran
  VERSION     0.0.0
  DESCRIPTION "Fortran ISO_C_BINDING interface to the Qiskit C API"
  LANGUAGES   Fortran)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(QISKIT_FORTRAN_TESTS "Build and register the test suite" ON)

# ---------------------------------------------------------------------------
# Locate the Qiskit C extension
# ---------------------------------------------------------------------------
set(QISKIT_ROOT "" CACHE PATH
  "Root of the Qiskit repository (must contain dist/c/ after `make c`)")

if(QISKIT_ROOT STREQUAL "")
  message(FATAL_ERROR
    "Set -DQISKIT_ROOT=/path/to/qiskit.  "
    "Build the C extension first with:\n"
    "  cd /path/to/qiskit && make c")
endif()

find_library(QISKIT_LIB
  NAMES qiskit qiskit_cext
  HINTS "${QISKIT_ROOT}/dist/c/lib"
        "${QISKIT_ROOT}/target/release"
  REQUIRED)

find_path(QISKIT_INCLUDE_DIR
  NAMES qiskit.h
  HINTS "${QISKIT_ROOT}/dist/c/include"
  REQUIRED)

message(STATUS "Qiskit library : ${QISKIT_LIB}")
message(STATUS "Qiskit include : ${QISKIT_INCLUDE_DIR}")

# ---------------------------------------------------------------------------
# Compiler flags
# ---------------------------------------------------------------------------
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
  # -std=f2018: Fortran 2018 (covers FINAL, ERROR STOP with message, c_loc)
  # -fcheck=all: runtime bounds/null checks
  # -fbacktrace: better error messages with line numbers
  # -g: debug symbols for better stack traces
  add_compile_options(
    $<$<COMPILE_LANGUAGE:Fortran>:-std=f2018>
    $<$<COMPILE_LANGUAGE:Fortran>:-Wall>
    $<$<COMPILE_LANGUAGE:Fortran>:-Wextra>
    $<$<COMPILE_LANGUAGE:Fortran>:-fcheck=all>
    $<$<COMPILE_LANGUAGE:Fortran>:-fbacktrace>
    $<$<COMPILE_LANGUAGE:Fortran>:-g>
    $<$<AND:$<COMPILE_LANGUAGE:Fortran>,$<CONFIG:Release>>:-O2>)

elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel|IntelLLVM")
  add_compile_options(
    $<$<COMPILE_LANGUAGE:Fortran>:-stand>
    $<$<COMPILE_LANGUAGE:Fortran>:f18>
    $<$<COMPILE_LANGUAGE:Fortran>:-warn>
    $<$<COMPILE_LANGUAGE:Fortran>:all>
    $<$<AND:$<COMPILE_LANGUAGE:Fortran>,$<CONFIG:Release>>:-O3>
    $<$<AND:$<COMPILE_LANGUAGE:Fortran>,$<CONFIG:Release>>:-ipo>)

elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Cray")
  add_compile_options(
    $<$<COMPILE_LANGUAGE:Fortran>:-hstd=f2018>)
endif()

# ---------------------------------------------------------------------------
# Library: qiskit_fortran
#
# Source order matters for Fortran — qiskit_c_api.f90 must be compiled
# before qiskit.f90 because qiskit USEs qiskit_c_api.
# ---------------------------------------------------------------------------
add_library(qiskit_fortran STATIC
  src/qiskit_c_api_types.f90
  src/qiskit_c_api_circuit.f90
  src/qiskit_c_api.f90
  src/qiskit_utils.f90
  src/qiskit_circuit.f90
  src/qiskit.f90)

# Expose the Qiskit C header so that any downstream C/C++ code that also
# includes qiskit.h finds it without extra -I flags.
target_include_directories(qiskit_fortran
  PUBLIC  "${QISKIT_INCLUDE_DIR}"
  PRIVATE "${CMAKE_Fortran_MODULE_DIRECTORY}")

target_link_libraries(qiskit_fortran
  PUBLIC "${QISKIT_LIB}")

# Place generated .mod files in a dedicated directory so downstream
# projects can find them with a single -I flag.
set_target_properties(qiskit_fortran PROPERTIES
  Fortran_MODULE_DIRECTORY "${CMAKE_BINARY_DIR}/modules")

# ---------------------------------------------------------------------------
# Test executable
# ---------------------------------------------------------------------------
if(QISKIT_FORTRAN_TESTS)
  add_executable(test_qiskit test/test_qiskit.f90)

  target_link_libraries(test_qiskit PRIVATE qiskit_fortran)
  
  target_include_directories(test_qiskit PRIVATE "${CMAKE_BINARY_DIR}/modules")

  add_dependencies(test_qiskit qiskit_fortran)

  # Detect Python dynamically for library path resolution
  # Try conda environment first, then system Python
  if(DEFINED ENV{CONDA_PREFIX})
    set(PYTHON_EXECUTABLE "$ENV{CONDA_PREFIX}/bin/python3")
    message(STATUS "Using Python from conda environment: ${PYTHON_EXECUTABLE}")
  else()
    find_package(Python3 COMPONENTS Interpreter)
    if(Python3_FOUND)
      set(PYTHON_EXECUTABLE ${Python3_EXECUTABLE})
      message(STATUS "Using system Python: ${PYTHON_EXECUTABLE}")
    endif()
  endif()
  
  # Build library path list dynamically based on platform
  set(TEST_LIBRARY_PATHS "")
  
  if(DEFINED PYTHON_EXECUTABLE)
    execute_process(
      COMMAND ${PYTHON_EXECUTABLE} -c "import sys; import os; print(os.path.join(sys.prefix, 'lib'))"
      OUTPUT_VARIABLE PYTHON_LIB_DIR
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET
    )
    if(PYTHON_LIB_DIR)
      message(STATUS "Python library directory: ${PYTHON_LIB_DIR}")
      list(APPEND TEST_LIBRARY_PATHS "${PYTHON_LIB_DIR}")
    endif()
  endif()
  
  # Add platform-specific system library paths
  if(APPLE)
    list(APPEND TEST_LIBRARY_PATHS "/usr/lib")
  elseif(UNIX)
    # Linux: add common library paths
    list(APPEND TEST_LIBRARY_PATHS "/usr/lib" "/usr/local/lib")
  endif()
  
  # Convert list to colon-separated string for environment variable
  if(TEST_LIBRARY_PATHS)
    string(REPLACE ";" ":" TEST_LIBRARY_PATH "${TEST_LIBRARY_PATHS}")
    message(STATUS "Test library path: ${TEST_LIBRARY_PATH}")
    
    # Set platform-specific library path environment variable
    if(APPLE)
      set(LIB_PATH_VAR "DYLD_LIBRARY_PATH")
    else()
      set(LIB_PATH_VAR "LD_LIBRARY_PATH")
    endif()
    
    add_custom_target(run_test
      COMMAND ${CMAKE_COMMAND} -E env ${LIB_PATH_VAR}=${TEST_LIBRARY_PATH} $<TARGET_FILE:test_qiskit>
      DEPENDS test_qiskit
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
      COMMENT "Running test_qiskit with ${LIB_PATH_VAR}=${TEST_LIBRARY_PATH}"
      VERBATIM)
  else()
    message(WARNING "No library paths detected - test may fail to load shared libraries")
    add_custom_target(run_test
      COMMAND $<TARGET_FILE:test_qiskit>
      DEPENDS test_qiskit
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
      COMMENT "Running test_qiskit"
      VERBATIM)
  endif()
  
  # Make 'test' an alias for 'run_test' for convenience
  add_custom_target(test
    DEPENDS run_test)
endif()

# ---------------------------------------------------------------------------
# Install rules
# ---------------------------------------------------------------------------
include(GNUInstallDirs)

install(TARGETS qiskit_fortran
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}")

install(DIRECTORY "${CMAKE_BINARY_DIR}/modules/"
  DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/qiskit-fortran"
  FILES_MATCHING PATTERN "*.mod")