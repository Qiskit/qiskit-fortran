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

!> @brief Coarray-based parallel parameter sweep for nuclear dynamics
!>
!> Demonstrates PGAS (Partitioned Global Address Space) parallelism:
!> Each image evaluates one theta value independently, then image 1
!> reduces and reports results.
!>
!> Usage: cafrun -n 8 ./nuclear_dynamics_parallel
!> or standard Fortran coarray runtime

program nuclear_dynamics_parallel
    use iso_c_binding
    use nuclear_dynamics_driver, only: run_parameter_sweep
    implicit none

    real(8) :: energy[*]
    integer, parameter :: N_THETA = 8
    real(8), parameter :: THETA_MIN = 0.0d0, THETA_MAX = 1.6d0
    integer, parameter :: N_QUBITS = 24
    integer, parameter :: N_PROTONS = 4
    integer, parameter :: N_NEUTRONS = 4
    integer, parameter :: SHOTS = 1024

    real(8) :: theta_local
    real(8), allocatable :: energies(:)
    real(8) :: min_energy_local
    integer :: i, n_images

    n_images = num_images()

    if (this_image() == 1) then
        print *, "========================================"
        print *, "Coarray Parameter Sweep"
        print *, "========================================"
        print *, "Number of images:", n_images
        print *, "Theta range: [", THETA_MIN, ",", THETA_MAX, "]"
        print *, "Total steps:", N_THETA
        print *, ""
    end if

    theta_local = THETA_MIN + real(this_image() - 1, 8) * (THETA_MAX - THETA_MIN) / real(N_THETA - 1, 8)

    allocate(energies(1))
    call run_parameter_sweep(1_c_int, real(theta_local, c_double), &
                            real(theta_local, c_double), &
                            int(N_QUBITS, c_int), &
                            int(N_PROTONS, c_int), &
                            int(N_NEUTRONS, c_int), &
                            int(SHOTS, c_int), energies, min_energy_local)

    energy = min_energy_local

    sync all

    if (this_image() == 1) then
        print *, ""
        print *, "========================================"
        print *, "PGAS Parameter Sweep Results:"
        print *, "========================================"
        do i = 1, N_THETA
            if (i <= num_images()) then
                print *, "Image", i, ": E(theta_", i, ") =", energy[i], "MeV"
            end if
        end do
        print *, "Min E =", minval(energy(1:min(N_THETA, num_images()))), "MeV"
        print *, "========================================"
    end if

    deallocate(energies)

end program nuclear_dynamics_parallel
