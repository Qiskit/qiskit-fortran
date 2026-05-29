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
#                       subdirectory under applications/ containing <name>.f90)
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

# ---------------------------------------------------------------------------
# Helper: list available applications
# ---------------------------------------------------------------------------
function(list_available_apps OUT_VAR)
    file(GLOB _dirs LIST_DIRECTORIES true "${CMAKE_CURRENT_SOURCE_DIR}/*")
    set(_found "")
    foreach(_dir ${_dirs})
        if(IS_DIRECTORY "${_dir}")
            get_filename_component(_name "${_dir}" NAME)
            if(EXISTS "${_dir}/${_name}.f90")
                list(APPEND _found "  ${_name}")
            endif()
        endif()
    endforeach()
    set(${OUT_VAR} "${_found}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
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

if(APP_NAME STREQUAL "")
    list_available_apps(_apps)
    message(FATAL_ERROR
        "APP_NAME is not set. Pass -DAPP_NAME=<name>\n"
        "Available applications:\n${_apps}")
endif()

set(_app_dir "${CMAKE_CURRENT_SOURCE_DIR}/${APP_NAME}")
set(_app_src "${_app_dir}/${APP_NAME}.f90")

if(NOT IS_DIRECTORY "${_app_dir}")
    list_available_apps(_apps)
    message(FATAL_ERROR
        "No application named '${APP_NAME}' found.\n"
        "Available applications:\n${_apps}")
endif()

if(NOT EXISTS "${_app_src}")
    message(FATAL_ERROR
        "Source file not found: ${_app_src}\n"
        "Convention: the main source file must match the directory name.")
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

if(_python_lib_dir)
    set(_rpath "${_qiskit_lib_dir};${_python_lib_dir}")
else()
    set(_rpath "${_qiskit_lib_dir}")
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

target_include_directories(${APP_NAME} PRIVATE
    "${_modules_dir}")

set_target_properties(${APP_NAME} PROPERTIES
    BUILD_RPATH           "${_rpath}"
    INSTALL_RPATH         "${_rpath}"
    BUILD_WITH_INSTALL_RPATH OFF)