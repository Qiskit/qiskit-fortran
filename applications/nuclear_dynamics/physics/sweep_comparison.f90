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

!> Comparison module for sweep results vs exact oracle
!> Generates structured output (CSV) with convergence metrics

module sweep_comparison
    use iso_c_binding
    implicit none
    private

    public :: write_sweep_results_csv, compute_sweep_metrics

    type, public :: sweep_metrics
        real(8) :: oracle_energy
        real(8) :: min_sweep_energy
        real(8) :: error_absolute
        real(8) :: error_relative
        real(8) :: mean_energy
        real(8) :: std_dev
    end type sweep_metrics

contains

    !> Compute convergence metrics
    subroutine compute_sweep_metrics(energies, n_theta, oracle_E0, metrics)
        real(8), intent(in) :: energies(:)
        integer, intent(in) :: n_theta
        real(8), intent(in) :: oracle_E0
        type(sweep_metrics), intent(out) :: metrics

        integer :: i
        real(8) :: sum_E, sum_E2, E_min

        if (n_theta < 1) error stop "compute_sweep_metrics: n_theta must be >= 1"

        E_min = minval(energies(1:n_theta))
        sum_E = sum(energies(1:n_theta))
        sum_E2 = sum(energies(1:n_theta)**2)

        metrics%oracle_energy = oracle_E0
        metrics%min_sweep_energy = E_min
        metrics%error_absolute = abs(E_min - oracle_E0)
        metrics%error_relative = metrics%error_absolute / abs(oracle_E0)
        metrics%mean_energy = sum_E / real(n_theta, 8)
        metrics%std_dev = sqrt(sum_E2 / real(n_theta, 8) - (sum_E / real(n_theta, 8))**2)
    end subroutine compute_sweep_metrics

    !> Write sweep results to CSV file with detailed per-theta data and summary
    subroutine write_sweep_results_csv(filename, thetas, energies, n_theta, oracle_E0)
        character(len=*), intent(in) :: filename
        real(8), intent(in) :: thetas(:)
        real(8), intent(in) :: energies(:)
        integer, intent(in) :: n_theta
        real(8), intent(in) :: oracle_E0

        type(sweep_metrics) :: metrics
        integer :: i, unit
        character(len=512) :: line

        if (n_theta < 1) error stop "write_sweep_results_csv: n_theta must be >= 1"

        call compute_sweep_metrics(energies, n_theta, oracle_E0, metrics)

        open(newunit=unit, file=trim(filename), status='replace', action='write')

        write(unit, '(A)') "# Nuclear Dynamics Parameter Sweep Results"
        write(unit, '(A)') "# Generated from fixed-ansatz variational sweep"
        write(unit, '(A)') "#"
        write(unit, '(A)') "# Oracle (exact j^2 pairing): " // fmt_real(oracle_E0) // " MeV"
        write(unit, '(A)') "# Minimum found: " // fmt_real(metrics%min_sweep_energy) // " MeV"
        write(unit, '(A)') "# Absolute error: " // fmt_real(metrics%error_absolute) // " MeV"
        write(unit, '(A,F8.4,A)') "# Relative error: ", metrics%error_relative * 100.0d0, "%"
        write(unit, '(A)') "# Mean energy: " // fmt_real(metrics%mean_energy) // " MeV"
        write(unit, '(A)') "# Std deviation: " // fmt_real(metrics%std_dev) // " MeV"
        write(unit, '(A)') "#"
        write(unit, '(A)') "theta_idx,theta,E_sweep_MeV,error_vs_oracle_MeV,error_vs_oracle_pct"

        do i = 1, n_theta
            write(unit, '(I4,A,ES16.8,A,ES16.8,A,ES16.8,A,F8.4)') &
                i, ",", thetas(i), ",", energies(i), ",", &
                abs(energies(i) - oracle_E0), ",", &
                abs(energies(i) - oracle_E0) / abs(oracle_E0) * 100.0d0
        end do

        close(unit)
        print *, "Sweep results written to: ", trim(filename)

    end subroutine write_sweep_results_csv

    function fmt_real(val) result(str)
        real(8), intent(in) :: val
        character(len=32) :: str
        write(str, '(ES16.8)') val
    end function fmt_real

end module sweep_comparison
