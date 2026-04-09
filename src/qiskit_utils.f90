module qiskit_utils
  use, intrinsic :: iso_c_binding, only : c_int
  use qiskit_c_api_types

  implicit none
  private
  
  public :: check_rc, to_qubit

contains

  !> Check a QkExitCode and stop the program with a diagnostic if non-zero.
  subroutine check_rc(rc, context)
    integer(c_int), intent(in) :: rc
    character(len=*), intent(in) :: context

    if (rc == QkExitCode_Success) return

    select case (rc)
    case (QkExitCode_CInputError)
      error stop "[qiskit] " // context // ": bad input data (CInputError)"
    case (QkExitCode_NullPointerError)
      error stop "[qiskit] " // context // ": unexpected null pointer"
    case (QkExitCode_AlignmentError)
      error stop "[qiskit] " // context // ": pointer alignment error"
    case (QkExitCode_IndexError)
      error stop "[qiskit] " // context // ": qubit/clbit index out of range"
    case (QkExitCode_ArithmeticError)
      error stop "[qiskit] " // context // ": arithmetic error in gate operation"
    case (QkExitCode_MismatchedQubits)
      error stop "[qiskit] " // context // ": mismatched qubit count for gate"
    case default
      error stop "[qiskit] " // context // ": unknown C API error"
    end select
  end subroutine check_rc

  !> Convert a default-kind integer qubit index to QK_QUBIT_KIND.
  !> Emits a compile-time-equivalent assertion for negative values.
  pure function to_qubit(idx) result(q)
    integer, intent(in) :: idx
    integer(QK_QUBIT_KIND) :: q
    q = int(idx, QK_QUBIT_KIND)
  end function to_qubit

end module qiskit_utils
