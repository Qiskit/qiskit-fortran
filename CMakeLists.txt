# =============================================================================
# CMakeLists.txt  —  qiskit-f90
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

# Resolves libqiskit.so (Linux), libqiskit.dylib (macOS)
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
else()
  message(WARNING
    "Untested Fortran compiler: ${CMAKE_Fortran_COMPILER_ID}. "
    "Only gfortran has been validated. Proceeding without compiler-specific flags.")
endif()

# ---------------------------------------------------------------------------
# Library: qiskit_fortran
#
# Source order matters for Fortran — modules must be compiled before their
# dependents. Dependency chain:
#   qiskit_c_api_types -> qiskit_c_api_circuit, qiskit_utils
#   qiskit_circuit -> qiskit
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

  # Extract the directory containing libqiskit for RPATH
  get_filename_component(QISKIT_LIB_DIR "${QISKIT_LIB}" DIRECTORY)

  # Detect Python lib dir for the libpython transitive dep of libqiskit
  if(DEFINED ENV{CONDA_PREFIX})
    set(PYTHON_LIB_DIR "$ENV{CONDA_PREFIX}/lib")
    message(STATUS "Python lib dir (conda): ${PYTHON_LIB_DIR}")
  else()
    find_package(Python3 COMPONENTS Interpreter)
    if(Python3_FOUND)
      execute_process(
        COMMAND "${Python3_EXECUTABLE}" -c
          "import sys, os; print(os.path.join(sys.prefix, 'lib'))"
        OUTPUT_VARIABLE PYTHON_LIB_DIR
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
      message(STATUS "Python lib dir (system): ${PYTHON_LIB_DIR}")
    endif()
  endif()

  # Embed the runtime search paths directly in the binary — no env var needed
  # Guard PYTHON_LIB_DIR so it's only appended if non-empty
  if(PYTHON_LIB_DIR)
    set_target_properties(test_qiskit PROPERTIES
      BUILD_RPATH  "${QISKIT_LIB_DIR};${PYTHON_LIB_DIR}"
      INSTALL_RPATH "${QISKIT_LIB_DIR};${PYTHON_LIB_DIR}"
      BUILD_WITH_INSTALL_RPATH OFF)
  else()
    set_target_properties(test_qiskit PROPERTIES
      BUILD_RPATH  "${QISKIT_LIB_DIR}"
      INSTALL_RPATH "${QISKIT_LIB_DIR}"
      BUILD_WITH_INSTALL_RPATH OFF)
  endif()

  add_custom_target(run_test
    COMMAND $<TARGET_FILE:test_qiskit>
    DEPENDS test_qiskit
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Running test_qiskit"
    VERBATIM)

  add_custom_target(test DEPENDS run_test)
endif()

# ---------------------------------------------------------------------------
# Install rules
# ---------------------------------------------------------------------------
include(GNUInstallDirs)

install(TARGETS qiskit_fortran
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}")

install(DIRECTORY "${CMAKE_BINARY_DIR}/modules/"
  DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/qiskit-f90"
  FILES_MATCHING PATTERN "*.mod")