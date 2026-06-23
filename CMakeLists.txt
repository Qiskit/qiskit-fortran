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
option(USE_SWIG_BINDINGS "Use SWIG-generated bindings instead of manual bindings" OFF)
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
    HINTS "${QISKIT_RUNTIME_ROOT}/build/cargo/release"
          "${QISKIT_RUNTIME_ROOT}/build/cargo/debug"
    REQUIRED)
  message(STATUS "Runtime library: ${QISKIT_RUNTIME_LIB}")
endif()

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
  
  # Compile the pre-generated C wrapper (Fortran module handled separately below)
  add_library(qiskit_swig_wrapper OBJECT "${SWIG_OUTPUT_C}")
  target_include_directories(qiskit_swig_wrapper PRIVATE "${QISKIT_INCLUDE_DIR}")
else()
  message(STATUS "Using hand-written bindings")

  # Explicit list — do not use GLOB (CMake won't re-run configure if a new file is added)
  set(QISKIT_C_API_SOURCES
    src/qiskit_c_api_types.f90
    src/qiskit_c_api_circuit.f90)
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

# Flags common to all supported compilers
add_compile_options(
  $<$<COMPILE_LANGUAGE:Fortran>:-g>
  $<$<AND:$<COMPILE_LANGUAGE:Fortran>,$<CONFIG:Release>>:-O2>)

if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
  add_compile_options(
    $<$<COMPILE_LANGUAGE:Fortran>:-Wall>
    $<$<COMPILE_LANGUAGE:Fortran>:-Wextra>
    $<$<COMPILE_LANGUAGE:Fortran>:-Wconversion>
    $<$<COMPILE_LANGUAGE:Fortran>:-fcheck=all>
    $<$<COMPILE_LANGUAGE:Fortran>:-fbacktrace>
    $<$<AND:$<COMPILE_LANGUAGE:Fortran>,$<CONFIG:Debug>>:-ffpe-trap=invalid,zero,overflow>)
endif()

# ---------------------------------------------------------------------------
# Library: qiskit_fortran
#
# Source order matters for Fortran — modules must be compiled before their
# dependents. Dependency chain:
#   - Manual: qiskit_c_api_types, qiskit_c_api_circuit -> qiskit_utils, qiskit_circuit
#   - SWIG:   qiskit_swigf -> qiskit_utils, qiskit_circuit, qiskit_target, qiskit_transpiler, qiskit
#   - Both:   qiskit_circuit -> qiskit
#
# All .mod files go to a single known directory so every target can find them.
set(CMAKE_Fortran_MODULE_DIRECTORY "${CMAKE_BINARY_DIR}/modules")

# flang does not implement CMake's intra-target Fortran module dependency
# protocol, so parallel builds race on USE statements within a single
# add_library call. Fix: compile each layer as its own OBJECT library so
# CMake's inter-target dependency ordering provides the serialisation barrier.
#
# Layer order (SWIG path):
#   L0: qiskit_swigf       (SWIG-generated, no deps)
#   L1: qiskit_utils       (USE L0; defines QkComplex, to_qubit, check_rc: available
#                           unconditionally in both build paths; no QkComplex64 dep)
#   L2: qiskit_circuit     (USE L1)
#   L3: qiskit_observable  (USE L0, L1; global SWIG imports)
#   L4: qiskit_target      (USE L1; qk_target_* imported locally per procedure)
#   L5: qiskit_transpiler  (USE L2, L4; same local-import pattern)
#   L6: qiskit             (USE L2, L3, L4, L5)
#
# qiskit_target and qiskit_transpiler are SWIG-only (no manual C API equivalents yet).
# Manual path uses a single add_library; gfortran's scanner handles ordering.

macro(fortran_layer NAME)
  add_library(${NAME} OBJECT ${ARGN})
  set_target_properties(${NAME} PROPERTIES
    Fortran_MODULE_DIRECTORY "${CMAKE_BINARY_DIR}/modules")
  target_include_directories(${NAME}
    PRIVATE "${QISKIT_INCLUDE_DIR}"
    PRIVATE "${CMAKE_BINARY_DIR}/modules")
  target_compile_options(${NAME} PRIVATE
    $<$<COMPILE_LANGUAGE:Fortran>:-cpp>
    $<$<COMPILE_LANGUAGE:Fortran>:-DUSE_SWIG_BINDINGS>)
endmacro()

if(USE_SWIG_BINDINGS)
  fortran_layer(qk_layer0 "${SWIG_OUTPUT_F90}")
  fortran_layer(qk_layer1 src/qiskit_utils.f90)
  fortran_layer(qk_layer2 src/qiskit_circuit.f90)
  fortran_layer(qk_layer3 src/qiskit_observable.f90)
  fortran_layer(qk_layer4 src/qiskit_target.f90)
  fortran_layer(qk_layer5 src/qiskit_transpiler.f90)
  fortran_layer(qk_layer6 src/qiskit.f90)

  add_dependencies(qk_layer1 qk_layer0)
  add_dependencies(qk_layer2 qk_layer1)
  add_dependencies(qk_layer3 qk_layer0 qk_layer1)
  add_dependencies(qk_layer4 qk_layer1)
  add_dependencies(qk_layer5 qk_layer2 qk_layer4)
  add_dependencies(qk_layer6 qk_layer3 qk_layer5)

  set(QISKIT_C_API_SOURCES "")
  set(QISKIT_EXTRA_OBJECTS
    $<TARGET_OBJECTS:qiskit_swig_wrapper>
    $<TARGET_OBJECTS:qk_layer0>
    $<TARGET_OBJECTS:qk_layer1>
    $<TARGET_OBJECTS:qk_layer2>
    $<TARGET_OBJECTS:qk_layer3>
    $<TARGET_OBJECTS:qk_layer4>
    $<TARGET_OBJECTS:qk_layer5>
    $<TARGET_OBJECTS:qk_layer6>)

  # Add runtime layers if runtime is enabled
  if(QISKIT_FORTRAN_RUNTIME)
    fortran_layer(qk_layer_rt_api src/qiskit_c_api_runtime.f90)
    fortran_layer(qk_layer_rt src/qiskit_runtime.f90)
    add_dependencies(qk_layer_rt_api qk_layer0)
    add_dependencies(qk_layer_rt qk_layer_rt_api qk_layer2)
    list(APPEND QISKIT_EXTRA_OBJECTS
      $<TARGET_OBJECTS:qk_layer_rt_api>
      $<TARGET_OBJECTS:qk_layer_rt>)
  endif()
endif()

# Library: qiskit-fortran
# ---------------------------------------------------------------------------
if(USE_SWIG_BINDINGS)
  # All Fortran sources compiled as layered OBJECT libs above; just bundle objects.
  add_library(qiskit-fortran STATIC ${QISKIT_EXTRA_OBJECTS})
  add_dependencies(qiskit-fortran qk_layer6 qiskit_swig_wrapper)
else()
  set(QISKIT_FORTRAN_SOURCES
    ${QISKIT_C_API_SOURCES}
    src/qiskit_utils.f90
    src/qiskit_circuit.f90
    src/qiskit.f90)

  if(QISKIT_FORTRAN_RUNTIME)
    list(APPEND QISKIT_FORTRAN_SOURCES
      src/qiskit_c_api_runtime.f90
      src/qiskit_runtime.f90)
  endif()

  add_library(qiskit-fortran STATIC ${QISKIT_FORTRAN_SOURCES})
endif()

target_include_directories(qiskit-fortran
  PRIVATE "${QISKIT_INCLUDE_DIR}"
  PRIVATE "${CMAKE_BINARY_DIR}/modules")

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