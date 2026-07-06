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
# Nuclear Subspace Diagonalization Application
#
# Builds nuclear_dynamics_lib (physics + ansatz + driver) and three test
# executables: nuclear_dynamics_driver.
# nuclear_dynamics_parallel is built only when coarray support is detected.
# =============================================================================

# Find LAPACK for exact_solver.f90 (dsyev routine)
# On macOS, use Accelerate framework; on other systems, find LAPACK
if(APPLE)
    # Use LINKER: prefix to pass framework flag directly to linker
    set(LAPACK_LIBRARIES "LINKER:-framework,Accelerate")
    message(STATUS "Using Accelerate framework for LAPACK: ${LAPACK_LIBRARIES}")
else()
    find_package(LAPACK REQUIRED)
    message(STATUS "Using LAPACK libraries: ${LAPACK_LIBRARIES}")
endif()

# Find OpenMP for parallel Hamiltonian build (build_sd_hamiltonian inner loop).
# CMake's FindOpenMP does not auto-detect flang's flags on macOS; we probe manually.
find_package(OpenMP)
if(NOT OpenMP_Fortran_FOUND)
    # Homebrew flang requires -fopenmp + explicit libomp path
    set(_LIBOMP_HINT "/opt/homebrew/opt/libomp/lib")
    find_library(_LIBOMP_LIB NAMES omp HINTS "${_LIBOMP_HINT}" NO_DEFAULT_PATH)
    if(_LIBOMP_LIB)
        set(FLANG_OPENMP_FLAGS "-fopenmp")
        set(FLANG_OPENMP_LIBS  "-L${_LIBOMP_HINT}" "${_LIBOMP_LIB}")
        set(OpenMP_Fortran_FOUND TRUE)
        message(STATUS "Flang OpenMP: ${_LIBOMP_LIB} — parallel Hamiltonian build enabled")
    else()
        message(STATUS "OpenMP not found — Hamiltonian build will be serial")
    endif()
else()
    message(STATUS "OpenMP found (CMake) — parallel Hamiltonian build enabled")
endif()

# Find runtime library (optional, for nuclear_dynamics_driver)
if(NOT QISKIT_RUNTIME_ROOT STREQUAL "")
    find_library(QISKIT_RUNTIME_LIB
        NAMES qiskit_ibm_runtime
        HINTS "${QISKIT_RUNTIME_ROOT}/build/cargo/release"
              "${QISKIT_RUNTIME_ROOT}/build/cargo/debug"
        NO_DEFAULT_PATH)
    if(QISKIT_RUNTIME_LIB)
        message(STATUS "Runtime lib (nuclear_dynamics) : ${QISKIT_RUNTIME_LIB}")
    else()
        message(STATUS "Runtime lib not found in ${QISKIT_RUNTIME_ROOT}")
    endif()
endif()

# Find GSL (GNU Scientific Library) for Clebsch-Gordan coefficients (optional)
find_package(GSL)
if(GSL_FOUND)
    message(STATUS "GSL found - version ${GSL_VERSION}")
    message(STATUS "GSL libraries: ${GSL_LIBRARIES}")
else()
    message(STATUS "GSL not found - building without GSL support (optional)")
endif()

# Setup RPATH for executables (conda lib + qiskit libs)
get_filename_component(_qiskit_lib_dir "${CMAKE_BINARY_DIR}" DIRECTORY)
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

# Build RPATH: conda lib + qiskit lib dirs
set(_rpath "${_python_lib_dir}")
if(CMAKE_BUILD_RPATH)
    set(_rpath "${_rpath};${CMAKE_BUILD_RPATH}")
endif()
set(CMAKE_BUILD_RPATH "${_rpath}")
set(CMAKE_INSTALL_RPATH "${_rpath}")

# Single unified library: nuclear_dynamics_lib
# Contains all physics modules, ansatz, and driver
add_library(nuclear_dynamics_lib
    physics/usdb_reader.f90
    physics/orbital_registry.f90
    physics/clebsch_gordan.f90
    physics/gsl_interface.f90
    physics/exact_solver.f90
    physics/symmetry_filter.f90
    circuit/nuclear_ansatz.f90
    circuit/nuclear_dynamics_driver.f90
)

set_target_properties(nuclear_dynamics_lib PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules
)

target_include_directories(nuclear_dynamics_lib PRIVATE
    ${CMAKE_BINARY_DIR}/modules
)

target_link_libraries(nuclear_dynamics_lib PRIVATE
    qiskit-fortran
    ${LAPACK_LIBRARIES}
)

# Add OpenMP support if available (parallel Hamiltonian build)
if(OpenMP_Fortran_FOUND)
    if(TARGET OpenMP::OpenMP_Fortran)
        target_link_libraries(nuclear_dynamics_lib PRIVATE OpenMP::OpenMP_Fortran)
        target_compile_options(nuclear_dynamics_lib PRIVATE ${OpenMP_Fortran_FLAGS})
    elseif(DEFINED FLANG_OPENMP_FLAGS)
        target_compile_options(nuclear_dynamics_lib PRIVATE ${FLANG_OPENMP_FLAGS})
        target_link_libraries(nuclear_dynamics_lib PRIVATE ${FLANG_OPENMP_LIBS})
    endif()
endif()

# Add GSL support if available
if(GSL_FOUND)
    target_compile_definitions(nuclear_dynamics_lib PRIVATE USE_GSL)
    target_include_directories(nuclear_dynamics_lib PRIVATE ${GSL_INCLUDE_DIRS})
    if(TARGET GSL::gsl)
        target_link_libraries(nuclear_dynamics_lib PRIVATE GSL::gsl GSL::gslcblas)
    else()
        target_link_libraries(nuclear_dynamics_lib PRIVATE ${GSL_LIBRARIES})
    endif()
endif()

# Build nuclear_dynamics_driver executable (with runtime support)
add_executable(nuclear_dynamics_driver
    circuit/nuclear_dynamics_driver.f90
)

target_link_libraries(nuclear_dynamics_driver
    nuclear_dynamics_lib
)

if(QISKIT_RUNTIME_LIB)
    target_link_libraries(nuclear_dynamics_driver
        "${QISKIT_RUNTIME_LIB}"
    )
    get_filename_component(_runtime_lib_dir "${QISKIT_RUNTIME_LIB}" DIRECTORY)
    set(CMAKE_BUILD_RPATH "${CMAKE_BUILD_RPATH};${_runtime_lib_dir}")
    set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_RPATH};${_runtime_lib_dir}")
endif()

target_include_directories(nuclear_dynamics_driver PRIVATE
    ${CMAKE_BINARY_DIR}/modules
)

if(CMAKE_BUILD_RPATH)
    set_target_properties(nuclear_dynamics_driver PROPERTIES
        BUILD_RPATH "${CMAKE_BUILD_RPATH}"
        INSTALL_RPATH "${CMAKE_INSTALL_RPATH}"
        BUILD_WITH_INSTALL_RPATH OFF)
endif()

# Build nuclear_dynamics_parallel executable (requires coarray support)
if(CMAKE_Fortran_COMPILER_SUPPORTS_F2008_COARRAYS)
    message(STATUS "Coarray support detected — building nuclear_dynamics_parallel")
    add_executable(nuclear_dynamics_parallel
        circuit/nuclear_dynamics_parallel.f90
    )

    target_link_libraries(nuclear_dynamics_parallel
        nuclear_dynamics_lib
    )

    target_include_directories(nuclear_dynamics_parallel PRIVATE
        ${CMAKE_BINARY_DIR}/modules
    )

    if(CMAKE_BUILD_RPATH)
        set_target_properties(nuclear_dynamics_parallel PROPERTIES
            BUILD_RPATH "${CMAKE_BUILD_RPATH}"
            INSTALL_RPATH "${CMAKE_INSTALL_RPATH}"
            BUILD_WITH_INSTALL_RPATH OFF)
    endif()
else()
    message(STATUS "Coarray support not detected — skipping nuclear_dynamics_parallel")
endif()

# Make USDB.snt available beside the driver in the build tree.
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/data/USDB.snt
               ${CMAKE_CURRENT_BINARY_DIR}/USDB.snt
               COPYONLY)

# Installation
install(TARGETS nuclear_dynamics_driver
    RUNTIME DESTINATION bin
)