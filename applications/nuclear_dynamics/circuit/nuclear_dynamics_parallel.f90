! This code is part of Qiskit.
!
! (C) Copyright IBM 2026.
!
! This code is licensed under the Apache License, Version 2.0. You may
! obtain a copy of this license in the LICENSE.txt file in the root directory
! of this source tree or at https://www.apache.org/licenses/LICENSE-2.0.
!
! Any modifications or derivative works of this code must retain this
! copyright notice, and modified files need to carry a notice indicating
! that they have been altered from the originals.

!> @brief Coarray-based PGAS parallel parameter sweep (nuclear dynamics benchmark)
!>
!> Demonstrates PGAS (Partitioned Global Address Space) parallelism for the theta sweep:
!> Each coarray image evaluates one theta value independently (full pipeline per image:
!> bitstring generation -> symmetry filter -> Hamiltonian build -> diagonalisation).
!> Image 1 gathers via coarray indexing and emits RESULT lines.
!>
!> Compile: cmake -B build -DCMAKE_Fortran_FLAGS="-fcoarray=lib" ...
!> Run:     cafrun -n 8 ./nuclear_dynamics_parallel
!>
!> Single-image fallback: if compiled without coarray runtime, n_images=1 and the
!> program runs the serial pipeline for theta step 1.

program nuclear_dynamics_parallel
    use iso_c_binding
    use nuclear_dynamics_driver, only: run_parameter_sweep
    implicit none

    integer, parameter :: N_THETA    = 8
    real(8), parameter :: THETA_MIN  = 0.0d0
    real(8), parameter :: THETA_MAX  = 1.6d0
    ! N_QUBITS is NOT declared here — derived from USDB inside run_parameter_sweep.
    integer, parameter :: N_PROTONS  = 2    ! 20Ne (2p+2n full sd-shell, dim=640)
    integer, parameter :: N_NEUTRONS = 2
    integer, parameter :: SHOTS      = 1024
    real(8), parameter :: ORACLE_E0  = -39.145050266d0  ! MeV; 20Ne USDB/LAPACK

    ! Coarray scalars: each image's result, gathered by image 1 via direct indexing
    real(8)   :: image_energy[*]
    integer(8):: image_wall_ns[*]

    real(8)   :: theta_local
    real(8), allocatable :: energies(:)
    real(8)   :: min_energy_local
    integer   :: n_images, me, k
    integer(8):: t0_wall, t1_wall, tick_rate
    real(8)   :: e_min
    integer(8):: global_wall_ns

    n_images = num_images()
    me       = this_image()

    ! Each image gets one theta step (assumes n_images <= N_THETA).
    ! Step for this image: me-th step on a uniform grid.
    if (n_images > 1) then
        theta_local = THETA_MIN + real(me - 1, 8) * (THETA_MAX - THETA_MIN) / real(n_images - 1, 8)
    else
        theta_local = THETA_MIN
    end if

    if (me == 1) then
        print *, "================================================"
        print *, " Nuclear Dynamics — PGAS Coarray Sweep"
        print *, "================================================"
        print '("  Nucleus  : 20Ne (2p+2n, full sd-shell, dim=640)")'
        print '("  Qubits   : n_qubits derived from USDB.snt at runtime")'
        print '("  Shots    : ",I6)', SHOTS
        print '("  Images   : ",I4)', n_images
        print '("  Theta    : [",F5.3,", ",F5.3,"]")', THETA_MIN, THETA_MAX
        print '("  Steps    : ",I4)', n_images
        print *, ""
    end if

    allocate(energies(1))

    call system_clock(t0_wall, tick_rate)
    call run_parameter_sweep(1_c_int, &
                             real(theta_local, c_double), real(theta_local, c_double), &
                             int(N_PROTONS, c_int), int(N_NEUTRONS, c_int), &
                             int(SHOTS, c_int), energies, min_energy_local)
    call system_clock(t1_wall)

    image_energy   = min_energy_local
    image_wall_ns  = (t1_wall - t0_wall) * (1000000000_8 / tick_rate)

    sync all

    ! ---------------------------------------------------------------
    ! Image 1 gathers, reduces, and emits RESULT lines
    ! ---------------------------------------------------------------
    if (me == 1) then
        print *, "================================================"
        print *, " PGAS Parameter Sweep Results:"
        print *, "================================================"

        e_min          = image_energy[1]
        global_wall_ns = image_wall_ns[1]

        do k = 1, n_images
            print '("  Image ",I3,"  theta=",F6.4,"  E=",F18.9," MeV  wall=",F9.3," ms")', &
                k, &
                THETA_MIN + real(k-1,8)*(THETA_MAX-THETA_MIN)/max(1,n_images-1), &
                image_energy[k], &
                real(image_wall_ns[k], 8) / 1.0d6
            e_min          = min(e_min, image_energy[k])
            global_wall_ns = max(global_wall_ns, image_wall_ns[k])
        end do

        print *, ""
        print '("  Min E (sweep) = ",F18.9," MeV")', e_min
        print '("  Oracle        = ",F18.9," MeV")', ORACLE_E0
        print '("  |dE|          = ",F18.9," MeV")', abs(e_min - ORACLE_E0)
        print *, ""
        print *, "================================================"
        print *, " MACHINE-READABLE  (grep RESULT)"
        print *, "------------------------------------------------"

        write(*,'("RESULT  energy_min     ",F16.9," MeV")') e_min
        write(*,'("RESULT  energy_error   ",F16.9," MeV")') abs(e_min - ORACLE_E0)
        write(*,'("RESULT  sweep_wall     ",I16," ns")') global_wall_ns
        write(*,'("RESULT  n_images       ",I16," images")') int(n_images, 8)
        print *, "================================================"
    end if

    deallocate(energies)

end program nuclear_dynamics_parallel
