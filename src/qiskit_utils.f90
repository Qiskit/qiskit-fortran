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

!> @brief Utility functions for Qiskit Fortran API
!>
!> Provides error checking and type conversion utilities.
module qiskit_utils
  use, intrinsic :: iso_c_binding, only : c_int, c_int32_t
  
#ifdef USE_SWIG_BINDINGS
  ! use SWIG-generated module
  use qiskit_swigf, only : &
      QkExitCode_Success, &
      QkExitCode_CInputError, &
      QkExitCode_NullPointerError, &
      QkExitCode_AlignmentError, &
      QkExitCode_IndexError, &
      QkExitCode_ArithmeticError, &
      QkExitCode_MismatchedQubits
#else
  ! Handwritten mode: use separate modules
  use qiskit_c_api_types
#endif

  implicit none (type, external)
  private

#ifdef USE_SWIG_BINDINGS
  ! define QK_QUBIT_KIND locally
  integer, parameter :: QK_QUBIT_KIND = c_int32_t
  public :: check_rc, to_qubit, QK_QUBIT_KIND
#else
  ! In handwritten mode, QK_QUBIT_KIND comes from qiskit_c_api_types
  public :: check_rc, to_qubit, QK_QUBIT_KIND
#endif

contains

  !> @brief Check exit code and stop program with diagnostic if non-zero
  !> @param rc exit code from C API
  !> @param context descriptive context string for error message
  subroutine check_rc(rc, context)
    integer(c_int), intent(in) :: rc
    character(len=*), intent(in) :: context

    if (rc == QkExitCode_Success) return

    select case (rc)
    case (QkExitCode_CInputError)
      error stop "[qiskit] " // context // ": Error related to C data input."
    case (QkExitCode_NullPointerError)
      error stop "[qiskit] " // context // ": Unexpected null pointer."
    case (QkExitCode_AlignmentError)
      error stop "[qiskit] " // context // ": Pointer is not aligned to expected data."
    case (QkExitCode_IndexError)
      error stop "[qiskit] " // context // ": Index out of bounds."
    case (QkExitCode_ArithmeticError)
      error stop "[qiskit] " // context // ": Error related to arithmetic operations or similar."
    case (QkExitCode_MismatchedQubits)
      error stop "[qiskit] " // context // ": Mismatching number of qubits."
    case default
      error stop "[qiskit] " // context // ": Unrecognized error code from Qiskit."
    end select
  end subroutine check_rc

  !> @brief Convert default-kind integer to qubit index kind
  !> @param idx qubit index (default integer kind)
  !> @return qubit index in QK_QUBIT_KIND (c_int32_t)
  pure function to_qubit(idx) result(q)
    integer, intent(in) :: idx
    integer(QK_QUBIT_KIND) :: q
    q = int(idx, QK_QUBIT_KIND)
  end function to_qubit

end module qiskit_utils
