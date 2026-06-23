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
# Nuclear SQD Application
#
# Builds the  nuclear_dynamics modules as a library and the test program.
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

# Find GSL (GNU Scientific Library) for Clebsch-Gordan coefficients (optional)
find_package(GSL)
if(GSL_FOUND)
    message(STATUS "GSL found - version ${GSL_VERSION}")
    message(STATUS "GSL libraries: ${GSL_LIBRARIES}")
else()
    message(STATUS "GSL not found - building without GSL support (optional)")
endif()

#  nuclear_dynamics_core: qiskit-free modules (usdb_reader, clebsch_gordan,
# exact_solver, symmetry_filter).  Standalone tests link only this target.
add_library( nuclear_dynamics_core
    physics/usdb_reader.f90
    physics/orbital_registry.f90
    physics/clebsch_gordan.f90
    physics/gsl_interface.f90
    physics/exact_solver.f90
    physics/symmetry_filter.f90
)

set_target_properties( nuclear_dynamics_core PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules
)
target_include_directories( nuclear_dynamics_core PRIVATE
    ${CMAKE_BINARY_DIR}/modules
)

# Add GSL support if available
if(GSL_FOUND)
    target_compile_definitions( nuclear_dynamics_core PRIVATE USE_GSL)
    target_include_directories( nuclear_dynamics_core PRIVATE ${GSL_INCLUDE_DIRS})
    # Use modern CMake targets if available, otherwise fall back to variables
    if(TARGET GSL::gsl)
        target_link_libraries( nuclear_dynamics_core PUBLIC GSL::gsl GSL::gslcblas)
    else()
        target_link_libraries( nuclear_dynamics_core PUBLIC ${GSL_LIBRARIES})
    endif()
endif()

# Link LAPACK to  nuclear_dynamics_core (needed by exact_solver.f90)
target_link_libraries( nuclear_dynamics_core PUBLIC ${LAPACK_LIBRARIES})

#  nuclear_dynamics_lib: adds nuclear_ansatz which depends on qiskit_circuit.
# Also includes nuclear_dynamics_driver (placeholder for future ADAPT loop).
# Used by the main integration executable.
add_library( nuclear_dynamics_lib
    circuit/nuclear_ansatz.f90
    circuit/nuclear_dynamics_driver.f90
)

target_link_libraries( nuclear_dynamics_lib
     nuclear_dynamics_core
    qiskit-fortran
)

set_target_properties( nuclear_dynamics_lib PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules
)
target_include_directories( nuclear_dynamics_lib PRIVATE
    ${CMAKE_BINARY_DIR}/modules
)

# Build test program
add_executable( nuclear_dynamics
    tests/nuclear_dynamics_test.f90
)

# Link test program against full lib (includes nuclear_ansatz + qiskit)
target_link_libraries( nuclear_dynamics
     nuclear_dynamics_lib
    qiskit-fortran
)

# Set module search path
target_include_directories( nuclear_dynamics PRIVATE
    ${CMAKE_BINARY_DIR}/modules
)

# Set RPATH for the executable (inherited from parent if set via CMAKE variables)
# The parent CMakeLists should have set CMAKE_BUILD_RPATH and CMAKE_INSTALL_RPATH
if(CMAKE_BUILD_RPATH)
    set_target_properties( nuclear_dynamics PROPERTIES
        BUILD_RPATH "${CMAKE_BUILD_RPATH}"
        INSTALL_RPATH "${CMAKE_INSTALL_RPATH}"
        BUILD_WITH_INSTALL_RPATH OFF)
endif()

# Build USDB reader test program
add_executable(test_usdb_reader
    tests/test_usdb_reader.f90
)

# No qiskit dependency, link only core
target_link_libraries(test_usdb_reader
     nuclear_dynamics_core
)

# Set module search path
target_include_directories(test_usdb_reader PRIVATE
    ${CMAKE_BINARY_DIR}/modules
)

# Set RPATH for the executable
if(CMAKE_BUILD_RPATH)
    set_target_properties(test_usdb_reader PROPERTIES
        BUILD_RPATH "${CMAKE_BUILD_RPATH}"
        INSTALL_RPATH "${CMAKE_INSTALL_RPATH}"
        BUILD_WITH_INSTALL_RPATH OFF)
endif()

# Build exact solver test program
add_executable(test_exact_solver
    tests/test_exact_solver.f90
)

# LAPACK inherited from  nuclear_dynamics_core
target_link_libraries(test_exact_solver
     nuclear_dynamics_core
)

# Set module search path
target_include_directories(test_exact_solver PRIVATE
    ${CMAKE_BINARY_DIR}/modules
)

# Set RPATH for the executable
if(CMAKE_BUILD_RPATH)
    set_target_properties(test_exact_solver PROPERTIES
        BUILD_RPATH "${CMAKE_BUILD_RPATH}"
        INSTALL_RPATH "${CMAKE_INSTALL_RPATH}"
        BUILD_WITH_INSTALL_RPATH OFF)
endif()

# Build nuclear_dynamics_driver executable
add_executable(nuclear_dynamics_driver
    circuit/nuclear_dynamics_driver.f90
)

target_link_libraries(nuclear_dynamics_driver
     nuclear_dynamics_lib
    qiskit-fortran
)

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
        qiskit-fortran
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

# Make USDB.snt available beside the test executables in the build tree.
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/data/USDB.snt
               ${CMAKE_CURRENT_BINARY_DIR}/USDB.snt
               COPYONLY)

# Installation
install(TARGETS  nuclear_dynamics test_exact_solver nuclear_dynamics_driver
    RUNTIME DESTINATION bin
)