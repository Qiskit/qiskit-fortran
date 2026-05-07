!> @brief Utility functions for Qiskit Fortran API
!>
!> Provides error checking and type conversion utilities.
module qiskit_utils
  use, intrinsic :: iso_c_binding, only : c_int, c_int32_t
  
#ifdef USE_SWIG_BINDINGS
  ! SWIG mode: use unified module
  use qiskit_c_api, only : QK_QUBIT_KIND, &
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

  public :: check_rc, to_qubit, QK_QUBIT_KIND

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
