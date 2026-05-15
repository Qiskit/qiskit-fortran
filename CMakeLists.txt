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

project(qiskit-f90
  VERSION     0.0.0
  DESCRIPTION "Fortran ISO_C_BINDING interface to the Qiskit C API"
  LANGUAGES   Fortran)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(QISKIT_F90_TESTS "Build and register the test suite" ON)
option(USE_SWIG_BINDINGS "Use SWIG-generated bindings instead of manual bindings" OFF)

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
# SWIG Configuration (if enabled)
# ---------------------------------------------------------------------------
if(USE_SWIG_BINDINGS)
  message(STATUS "Using SWIG-generated direct bindings (fortranbindc mode)")
  
  # Use pre-generated SWIG files
  set(SWIG_OUTPUT_C "${CMAKE_SOURCE_DIR}/fortran-swig/qiskit_swigf_wrap.c")
  set(SWIG_OUTPUT_F90 "${CMAKE_SOURCE_DIR}/fortran-swig/qiskit_swigf.f90")
  
  # Verify pre-generated files exist
  if(NOT EXISTS "${SWIG_OUTPUT_C}")
    message(FATAL_ERROR
      "Pre-generated SWIG C wrapper not found at ${SWIG_OUTPUT_C}. "
      "Run: cd fortran-swig && swig -fortran -I<qiskit_include_path> qiskit_swigf.i")
  endif()
  if(NOT EXISTS "${SWIG_OUTPUT_F90}")
    message(FATAL_ERROR
      "Pre-generated SWIG Fortran module not found at ${SWIG_OUTPUT_F90}. "
      "Run: cd fortran-swig && swig -fortran -I<qiskit_include_path> qiskit_swigf.i")
  endif()
  
  # Enable C for compiling the wrapper
  enable_language(C)
  
  # Compile the pre-generated C wrapper
  add_library(qiskit_swig_wrapper OBJECT "${SWIG_OUTPUT_C}")
  target_include_directories(qiskit_swig_wrapper PRIVATE "${QISKIT_INCLUDE_DIR}")
  target_compile_definitions(qiskit_swig_wrapper PRIVATE QISKIT_C_PYTHON_INTERFACE=0)
  
  # Set the C API source files for SWIG build
  # Use ONLY the SWIG-generated qiskit_swigf.f90 which contains all types, enums and interfaces
  set(QISKIT_C_API_SOURCES "${SWIG_OUTPUT_F90}")
  set(QISKIT_EXTRA_OBJECTS $<TARGET_OBJECTS:qiskit_swig_wrapper>)
else()
  message(STATUS "Using hand-written bindings")
  
  # Glob all manual C API binding files
  file(GLOB QISKIT_C_API_SOURCES "src/*c_api*.f90")
  set(QISKIT_EXTRA_OBJECTS "")
endif()

# ---------------------------------------------------------------------------
# Compiler flags
# ---------------------------------------------------------------------------
# Enable preprocessor for conditional compilation
add_compile_options($<$<COMPILE_LANGUAGE:Fortran>:-cpp>)

# Add preprocessor flag for SWIG bindings
if(USE_SWIG_BINDINGS)
  add_compile_options($<$<COMPILE_LANGUAGE:Fortran>:-DUSE_SWIG_BINDINGS>)
endif()

# Generic flags that work across most Fortran compilers
add_compile_options(
  $<$<COMPILE_LANGUAGE:Fortran>:-g>
  $<$<AND:$<COMPILE_LANGUAGE:Fortran>,$<CONFIG:Release>>:-O2>)

# ---------------------------------------------------------------------------
# Library: qiskit_fortran
#
# Source order matters for Fortran — modules must be compiled before their
# dependents. Dependency chain:
#   - Manual: qiskit_c_api_types, qiskit_c_api_circuit -> qiskit_utils, qiskit_circuit
#   - SWIG:   qiskit_swig_api -> qiskit_utils, qiskit_circuit
#   - Both:   qiskit_circuit -> qiskit
# ---------------------------------------------------------------------------
add_library(qiskit-f90 STATIC
  ${QISKIT_C_API_SOURCES}
  src/qiskit_utils.f90
  src/qiskit_circuit.f90
  src/qiskit.f90
  ${QISKIT_EXTRA_OBJECTS})

target_include_directories(qiskit-f90
  PRIVATE "${QISKIT_INCLUDE_DIR}")

target_link_libraries(qiskit-f90
  PUBLIC "${QISKIT_LIB}")

# Add dependency on SWIG wrapper if using SWIG bindings
if(USE_SWIG_BINDINGS)
  add_dependencies(qiskit-f90 qiskit_swig_wrapper)
endif()

# Place generated .mod files in a dedicated directory so downstream
# projects can find them with a single -I flag.
set_target_properties(qiskit-f90 PROPERTIES
  Fortran_MODULE_DIRECTORY "${CMAKE_BINARY_DIR}/modules")

# ---------------------------------------------------------------------------
# Test executable
# ---------------------------------------------------------------------------
if(QISKIT_F90_TESTS)
  add_executable(test_qiskit test/test_qiskit.f90)

  target_link_libraries(test_qiskit PRIVATE qiskit-f90)
  target_include_directories(test_qiskit PRIVATE "${CMAKE_BINARY_DIR}/modules")
  add_dependencies(test_qiskit qiskit-f90)

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

install(TARGETS qiskit-f90
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}")

install(DIRECTORY "${CMAKE_BINARY_DIR}/modules/"
  DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/qiskit-f90"
  FILES_MATCHING PATTERN "*.mod")