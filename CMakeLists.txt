# This code is part of Qiskit.
#
# (C) Copyright IBM 2026.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at https://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

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

project(qiskit-fortran
  VERSION     0.0.0
  DESCRIPTION "Fortran ISO_C_BINDING interface to the Qiskit C API"
  LANGUAGES   Fortran)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(QISKIT_FORTRAN_TESTS "Build and register the test suite" ON)
option(QISKIT_FORTRAN_RUNTIME "Build the IBM Runtime binding (needs libqiskit_ibm_runtime)" OFF)

set(QISKIT_RUNTIME_ROOT "" CACHE PATH
  "Root of qiskit-ibm-runtime-c (needed when QISKIT_FORTRAN_RUNTIME is ON)")

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

# Locate the IBM Runtime client (optional)
if(QISKIT_FORTRAN_RUNTIME)
  find_library(QISKIT_RUNTIME_LIB
    NAMES qiskit_ibm_runtime
    HINTS "${QISKIT_RUNTIME_ROOT}/build"
          "${QISKIT_RUNTIME_ROOT}/target/release"
    REQUIRED)
  message(STATUS "Runtime library: ${QISKIT_RUNTIME_LIB}")
endif()

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
#   qiskit_c_api_types, qiskit_c_api_circuit -> qiskit_utils, qiskit_circuit
#   qiskit_circuit -> qiskit
# ---------------------------------------------------------------------------
set(QISKIT_FORTRAN_SOURCES
  src/qiskit_c_api_types.f90
  src/qiskit_c_api_circuit.f90
  src/qiskit_utils.f90
  src/qiskit_circuit.f90
  src/qiskit.f90)

if(QISKIT_FORTRAN_RUNTIME)
  list(APPEND QISKIT_FORTRAN_SOURCES
    src/qiskit_c_api_runtime.f90
    src/qiskit_runtime.f90)
endif()

add_library(qiskit-fortran STATIC ${QISKIT_FORTRAN_SOURCES})

target_include_directories(qiskit-fortran
  PRIVATE "${QISKIT_INCLUDE_DIR}")

target_link_libraries(qiskit-fortran
  PUBLIC "${QISKIT_LIB}")

if(QISKIT_FORTRAN_RUNTIME)
  target_link_libraries(qiskit-fortran PUBLIC "${QISKIT_RUNTIME_LIB}")
endif()

# Place generated .mod files in a dedicated directory so downstream
# projects can find them with a single -I flag.
set_target_properties(qiskit-fortran PROPERTIES
  Fortran_MODULE_DIRECTORY "${CMAKE_BINARY_DIR}/modules")

# ---------------------------------------------------------------------------
# Test executable
# ---------------------------------------------------------------------------
if(QISKIT_FORTRAN_TESTS)
  add_executable(test_qiskit test/test_qiskit.f90)

  target_link_libraries(test_qiskit PRIVATE qiskit-fortran)
  target_include_directories(test_qiskit PRIVATE "${CMAKE_BINARY_DIR}/modules")
  add_dependencies(test_qiskit qiskit-fortran)

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

  set(RUN_TARGETS run_test)

  # Runtime binding test (hardware-free, but links libqiskit_ibm_runtime)
  if(QISKIT_FORTRAN_RUNTIME)
    add_executable(test_runtime test/test_runtime.f90)
    target_link_libraries(test_runtime PRIVATE qiskit-fortran)
    target_include_directories(test_runtime PRIVATE "${CMAKE_BINARY_DIR}/modules")
    add_dependencies(test_runtime qiskit-fortran)

    get_filename_component(QISKIT_RUNTIME_LIB_DIR "${QISKIT_RUNTIME_LIB}" DIRECTORY)
    if(PYTHON_LIB_DIR)
      set(RUNTIME_RPATH "${QISKIT_LIB_DIR};${QISKIT_RUNTIME_LIB_DIR};${PYTHON_LIB_DIR}")
    else()
      set(RUNTIME_RPATH "${QISKIT_LIB_DIR};${QISKIT_RUNTIME_LIB_DIR}")
    endif()
    set_target_properties(test_runtime PROPERTIES
      BUILD_RPATH   "${RUNTIME_RPATH}"
      INSTALL_RPATH "${RUNTIME_RPATH}"
      BUILD_WITH_INSTALL_RPATH OFF)

    add_custom_target(run_test_runtime
      COMMAND $<TARGET_FILE:test_runtime>
      DEPENDS test_runtime
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
      COMMENT "Running test_runtime"
      VERBATIM)
    list(APPEND RUN_TARGETS run_test_runtime)
  endif()

  add_custom_target(test DEPENDS ${RUN_TARGETS})
endif()

# ---------------------------------------------------------------------------
# Install rules
# ---------------------------------------------------------------------------
include(GNUInstallDirs)

install(TARGETS qiskit-fortran
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}")

install(DIRECTORY "${CMAKE_BINARY_DIR}/modules/"
  DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/qiskit-fortran"
  FILES_MATCHING PATTERN "*.mod")