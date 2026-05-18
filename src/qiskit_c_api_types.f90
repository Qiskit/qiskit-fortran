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

!> @brief Type definitions and exit codes for Qiskit C API
!>
!> Defines Fortran-specific type mappings. Exit code meanings are documented
!> in the Qiskit C API reference.
module qiskit_c_api_types
  use, intrinsic :: iso_c_binding, only : &
      c_int, c_int32_t

  implicit none (type, external)
  private

  public :: QK_QUBIT_KIND
  public :: QkExitCode_Success
  public :: QkExitCode_CInputError
  public :: QkExitCode_NullPointerError
  public :: QkExitCode_AlignmentError
  public :: QkExitCode_IndexError
  public :: QkExitCode_ArithmeticError
  public :: QkExitCode_MismatchedQubits

  !> @brief Integer kind for qubit indices (matches C API int32_t)
  integer, parameter :: QK_QUBIT_KIND = c_int32_t

  ! Exit codes from qiskit.h
  integer(c_int), parameter :: QkExitCode_Success          = 0_c_int
  integer(c_int), parameter :: QkExitCode_CInputError      = 100_c_int
  integer(c_int), parameter :: QkExitCode_NullPointerError = 101_c_int
  integer(c_int), parameter :: QkExitCode_AlignmentError   = 102_c_int
  integer(c_int), parameter :: QkExitCode_IndexError       = 103_c_int
  integer(c_int), parameter :: QkExitCode_ArithmeticError  = 200_c_int
  integer(c_int), parameter :: QkExitCode_MismatchedQubits = 201_c_int

end module qiskit_c_api_types