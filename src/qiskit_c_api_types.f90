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
!> Defines the C-ABI types and exit-code constants needed by the non-SWIG
!> (hand-written) build path.  In SWIG mode these are all provided by
!> qiskit_swigf instead and this module is not imported.
!>
!> QkComplex (the Fortran-native arithmetic wrapper) has moved to
!> qiskit_utils so it is available unconditionally in both build paths.
module qiskit_c_api_types
  use, intrinsic :: iso_c_binding, only : &
      c_int, c_int32_t, c_double

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
  public :: QkComplex64
  public :: to_qubit
  public :: complex64_from_components

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

  !> @brief C-interoperable complex number type matching the C API QkComplex64
  !> @note Two consecutive c_doubles; layout must stay ABI-compatible with the C struct.
  type, bind(C) :: QkComplex64
    real(c_double) :: re = 0.0_c_double
    real(c_double) :: im = 0.0_c_double
  end type QkComplex64

contains

  ! Elemental Conversion Functions

  !> @brief Convert integer to qubit kind (elemental for array operations)
  !> @param q integer qubit index
  !> @return qubit index as QK_QUBIT_KIND
  !> @note Elemental allows this to work on arrays: to_qubit([0,1,2])
  elemental integer(QK_QUBIT_KIND) function to_qubit(q)
    integer, intent(in) :: q
    to_qubit = int(q, QK_QUBIT_KIND)
  end function to_qubit

  !> @brief Create QkComplex64 from real and imaginary components (elemental)
  !> @param re real part
  !> @param im imaginary part
  !> @return QkComplex64 structure
  !> @note Elemental allows array operations: complex64_from_components(re_arr, im_arr)
  elemental type(QkComplex64) function complex64_from_components(re, im)
    real(c_double), intent(in) :: re
    real(c_double), intent(in) :: im
    complex64_from_components%re = re
    complex64_from_components%im = im
  end function complex64_from_components

end module qiskit_c_api_types
