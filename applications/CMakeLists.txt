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
#
# =============================================================================
# CMakeLists.txt  —  qiskit-fortran/applications
#
# Builds a single application from the applications/ directory.
#
# Required CMake variables:
#   APP_NAME            Name of the application to build (must match a
#                       subdirectory under applications/ containing <name>.f90
#                       or <name>_test.f90 for test-only applications)
#   QISKIT_FORTRAN_ROOT Path to the qiskit-fortran build directory
#                       (contains libqiskit-fortran.a and modules/)
#   QISKIT_ROOT         Path to the Qiskit repository after running `make c`
#                       (contains dist/c/lib/libqiskit.so)
# =============================================================================

cmake_minimum_required(VERSION 3.20)
project(qiskit-fortran-applications LANGUAGES Fortran)

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------
set(APP_NAME            "" CACHE STRING "Application to build")
set(QISKIT_FORTRAN_ROOT "" CACHE PATH   "Path to qiskit-fortran build directory")
set(QISKIT_ROOT         "" CACHE PATH   "Path to Qiskit repository")
set(QISKIT_RUNTIME_ROOT "" CACHE PATH   "Path to qiskit-ibm-runtime-c (apps using the runtime binding)")

# ---------------------------------------------------------------------------
# Setup for subdirectories (if building without APP_NAME)
# ---------------------------------------------------------------------------
if(APP_NAME STREQUAL "" AND NOT QISKIT_FORTRAN_ROOT STREQUAL "")
  # Find qiskit-fortran library for subdirectories
  find_library(QISKIT_FORTRAN_LIB
      NAMES qiskit-fortran
      HINTS "${QISKIT_FORTRAN_ROOT}"
      REQUIRED)
  
  # Find Qiskit C library
  find_library(QISKIT_LIB
      NAMES qiskit qiskit_cext
      HINTS "${QISKIT_ROOT}/dist/c/lib"
            "${QISKIT_ROOT}/target/release"
      REQUIRED)
  
  message(STATUS "qiskit-fortran lib: ${QISKIT_FORTRAN_LIB}")
  message(STATUS "Qiskit C lib: ${QISKIT_LIB}")
  
  # Create imported target for qiskit-fortran with proper dependencies
  add_library(qiskit-fortran STATIC IMPORTED)
  set_target_properties(qiskit-fortran PROPERTIES
      IMPORTED_LOCATION "${QISKIT_FORTRAN_LIB}"
      INTERFACE_LINK_LIBRARIES "${QISKIT_LIB}")
  
  # Set module directory for subdirectories to find qiskit modules
  set(CMAKE_Fortran_MODULE_DIRECTORY "${QISKIT_FORTRAN_ROOT}/modules")
  include_directories("${QISKIT_FORTRAN_ROOT}/modules")
  
  # Setup RPATH for executables (resolve the pyO3 dependencies from build)
  get_filename_component(QISKIT_LIB_DIR "${QISKIT_LIB}" DIRECTORY)
  if(DEFINED ENV{CONDA_PREFIX})
    set(PYTHON_LIB_DIR "$ENV{CONDA_PREFIX}/lib")
    message(STATUS "Python lib dir (conda): ${PYTHON_LIB_DIR}")
    set(CMAKE_BUILD_RPATH "${QISKIT_LIB_DIR};${PYTHON_LIB_DIR}")
    set(CMAKE_INSTALL_RPATH "${QISKIT_LIB_DIR};${PYTHON_LIB_DIR}")
  else()
    find_package(Python3 COMPONENTS Interpreter QUIET)
    if(Python3_FOUND)
      execute_process(
        COMMAND "${Python3_EXECUTABLE}" -c
          "import sys, os; print(os.path.join(sys.prefix, 'lib'))"
        OUTPUT_VARIABLE PYTHON_LIB_DIR
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
      if(PYTHON_LIB_DIR)
        message(STATUS "Python lib dir (system): ${PYTHON_LIB_DIR}")
        set(CMAKE_BUILD_RPATH "${QISKIT_LIB_DIR};${PYTHON_LIB_DIR}")
        set(CMAKE_INSTALL_RPATH "${QISKIT_LIB_DIR};${PYTHON_LIB_DIR}")
      else()
        set(CMAKE_BUILD_RPATH "${QISKIT_LIB_DIR}")
        set(CMAKE_INSTALL_RPATH "${QISKIT_LIB_DIR}")
      endif()
    else()
      set(CMAKE_BUILD_RPATH "${QISKIT_LIB_DIR}")
      set(CMAKE_INSTALL_RPATH "${QISKIT_LIB_DIR}")
    endif()
  endif()
  set(CMAKE_BUILD_WITH_INSTALL_RPATH OFF)
endif()

# ---------------------------------------------------------------------------
# Subdirectories with their own CMakeLists.txt
# ---------------------------------------------------------------------------
if(NOT QISKIT_FORTRAN_ROOT STREQUAL "")
  add_subdirectory(nuclear_shell)
endif()

# ---------------------------------------------------------------------------
# Helper: list available applications
# ---------------------------------------------------------------------------
function(list_available_apps OUT_VAR)
    file(GLOB _dirs LIST_DIRECTORIES true "${CMAKE_CURRENT_SOURCE_DIR}/*")
    set(_found "")
    foreach(_dir ${_dirs})
        if(IS_DIRECTORY "${_dir}")
            get_filename_component(_name "${_dir}" NAME)
            if(EXISTS "${_dir}/${_name}.f90" OR EXISTS "${_dir}/${_name}_test.f90")
                list(APPEND _found "  ${_name}")
            endif()
        endif()
    endforeach()
    set(${OUT_VAR} "${_found}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
# Only validate if APP_NAME is provided (for standalone app builds)
# If APP_NAME is not provided, only subdirectories will be built
if(APP_NAME STREQUAL "")
  # Building subdirectories only, skip standalone app build
  return()
endif()

if(QISKIT_FORTRAN_ROOT STREQUAL "")
    message(FATAL_ERROR
        "QISKIT_FORTRAN_ROOT is not set.\n"
        "Pass -DQISKIT_FORTRAN_ROOT=/path/to/qiskit-fortran/build")
endif()

if(QISKIT_ROOT STREQUAL "")
    message(FATAL_ERROR
        "QISKIT_ROOT is not set.\n"
        "Pass -DQISKIT_ROOT=/path/to/qiskit")
endif()

set(_app_dir "${CMAKE_CURRENT_SOURCE_DIR}/${APP_NAME}")
set(_app_src "${_app_dir}/${APP_NAME}.f90")
# Test-only applications use <name>_test.f90 as source but keep the executable name
if(NOT EXISTS "${_app_src}" AND EXISTS "${_app_dir}/${APP_NAME}_test.f90")
    set(_app_src "${_app_dir}/${APP_NAME}_test.f90")
endif()

if(NOT IS_DIRECTORY "${_app_dir}")
    list_available_apps(_apps)
    message(FATAL_ERROR
        "No application named '${APP_NAME}' found.\n"
        "Available applications:\n${_apps}")
endif()

if(NOT EXISTS "${_app_src}")
    message(FATAL_ERROR
        "Source file not found: ${_app_src} (also tried ${_app_dir}/${APP_NAME}_test.f90)\n"
        "Convention: the main source file must be <name>.f90 or <name>_test.f90.")
endif()

set(_modules_dir "${QISKIT_FORTRAN_ROOT}/modules")
if(NOT IS_DIRECTORY "${_modules_dir}")
    message(FATAL_ERROR
        "Module directory not found: ${_modules_dir}\n"
        "Has qiskit-fortran been built at QISKIT_FORTRAN_ROOT?")
endif()

# ---------------------------------------------------------------------------
# Locate libraries
# ---------------------------------------------------------------------------
find_library(QISKIT_FORTRAN_LIB
    NAMES qiskit-fortran
    HINTS "${QISKIT_FORTRAN_ROOT}"
    REQUIRED)

find_library(QISKIT_LIB
    NAMES qiskit
    HINTS "${QISKIT_ROOT}/dist/c/lib"
          "${QISKIT_ROOT}/target/release"
    REQUIRED)

# Optional: the IBM Runtime client, for apps using the runtime binding
if(NOT QISKIT_RUNTIME_ROOT STREQUAL "")
    find_library(QISKIT_RUNTIME_LIB
        NAMES qiskit_ibm_runtime
        HINTS "${QISKIT_RUNTIME_ROOT}/build/cargo/release"
              "${QISKIT_RUNTIME_ROOT}/build/cargo/debug"
        REQUIRED)
    message(STATUS "Runtime lib          : ${QISKIT_RUNTIME_LIB}")
endif()

message(STATUS "Application          : ${APP_NAME}")
message(STATUS "Source               : ${_app_src}")
message(STATUS "qiskit-fortran lib   : ${QISKIT_FORTRAN_LIB}")
message(STATUS "Qiskit lib           : ${QISKIT_LIB}")
message(STATUS "Module directory     : ${_modules_dir}")

# ---------------------------------------------------------------------------
# RPATH
# ---------------------------------------------------------------------------
get_filename_component(_qiskit_lib_dir "${QISKIT_LIB}" DIRECTORY)

if(DEFINED ENV{CONDA_PREFIX})
    set(_python_lib_dir "$ENV{CONDA_PREFIX}/lib")
    message(STATUS "Python lib dir (conda): ${_python_lib_dir}")
else()
    find_package(Python3 COMPONENTS Interpreter QUIET)
    if(Python3_FOUND)
        execute_process(
            COMMAND "${Python3_EXECUTABLE}" -c
                "import sys, os; print(os.path.join(sys.prefix, 'lib'))"
            OUTPUT_VARIABLE _python_lib_dir
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET)
        message(STATUS "Python lib dir (system): ${_python_lib_dir}")
    endif()
endif()

set(_rpath "${_qiskit_lib_dir}")
if(QISKIT_RUNTIME_LIB)
    get_filename_component(_runtime_lib_dir "${QISKIT_RUNTIME_LIB}" DIRECTORY)
    set(_rpath "${_rpath};${_runtime_lib_dir}")
endif()
if(_python_lib_dir)
    set(_rpath "${_rpath};${_python_lib_dir}")
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
add_compile_options(
  $<$<COMPILE_LANGUAGE:Fortran>:-g>
  $<$<AND:$<COMPILE_LANGUAGE:Fortran>,$<CONFIG:Release>>:-O2>)

# ---------------------------------------------------------------------------
# Target
# ---------------------------------------------------------------------------
add_executable(${APP_NAME} "${_app_src}")

target_link_libraries(${APP_NAME} PRIVATE
    "${QISKIT_FORTRAN_LIB}"
    "${QISKIT_LIB}")

if(QISKIT_RUNTIME_LIB)
    target_link_libraries(${APP_NAME} PRIVATE "${QISKIT_RUNTIME_LIB}")
endif()

target_include_directories(${APP_NAME} PRIVATE
    "${_modules_dir}")

set_target_properties(${APP_NAME} PROPERTIES
    BUILD_RPATH           "${_rpath}"
    INSTALL_RPATH         "${_rpath}"
    BUILD_WITH_INSTALL_RPATH OFF)