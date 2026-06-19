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

!> @brief Utility functions and shared types for Qiskit Fortran API
!>
!> Provides error checking, type conversion utilities, and the QkComplex
!> arithmetic wrapper.  Everything here is unconditional (no #ifdef guards on
!> the type definitions) so both the SWIG and hand-written build paths see
!> identical public symbols.  The only guarded section is the error-code
!> import, where SWIG mode pulls from qiskit_swigf and non-SWIG mode pulls
!> from qiskit_c_api_types.
module qiskit_utils
  use, intrinsic :: iso_c_binding, only : c_int, c_int32_t, c_double, c_double_complex

#ifdef USE_SWIG_BINDINGS
  use qiskit_swigf, only : &
      QkExitCode_Success, &
      QkExitCode_CInputError, &
      QkExitCode_NullPointerError, &
      QkExitCode_AlignmentError, &
      QkExitCode_IndexError, &
      QkExitCode_ArithmeticError, &
      QkExitCode_MismatchedQubits
#else
  use qiskit_c_api_types
#endif

  implicit none (type, external)
  private

#ifdef USE_SWIG_BINDINGS
  integer, parameter :: QK_QUBIT_KIND = c_int32_t
#endif
  public :: check_rc, to_qubit, QK_QUBIT_KIND
  public :: QkComplex

  !> @brief Fortran-native complex arithmetic wrapper
  !>
  !> Stores a complex(c_double_complex) value internally so all of Fortran's
  !> intrinsic complex arithmetic (conjg, abs, atan2, cmplx, +, -, *, /) works
  !> directly on the stored value without any manual re, im bookkeeping.
  !>
  !> This type is independent of QkComplex64 / the SWIG ABI; it exists purely
  !> on the Fortran side.  At the point where a value must cross the C boundary
  !> (e.g. as an observable coefficient) call %to_re() / %to_im() and pack into
  !> whichever bind(C) struct the call site requires.  Because this is defined
  !> in qiskit_utils (imported unconditionally by every module in both build
  !> paths) it is available regardless of whether USE_SWIG_BINDINGS is set,
  !> unlike the QkComplex that previously lived only in qiskit_c_api_types.
  !>
  !> Construct with:
  !>   z = QkComplex(re, im)           ! from two c_doubles
  !>   z = QkComplex(native_complex)   ! from complex(c_double_complex)
  type :: QkComplex
    private
    complex(c_double_complex) :: value = (0.0_c_double, 0.0_c_double)
  contains
    procedure, public :: re        => qkc_re
    procedure, public :: im        => qkc_im
    procedure, public :: magnitude => qkc_magnitude
    procedure, public :: phase     => qkc_phase
    procedure, public :: conjugate => qkc_conjugate
    procedure, public :: to_native => qkc_to_native
    ! Arithmetic via native complex — no boilerplate, compiler optimises freely.
    procedure, private :: qkc_add
    procedure, private :: qkc_sub
    procedure, private :: qkc_mul
    procedure, private :: qkc_div
    generic, public :: operator(+) => qkc_add
    generic, public :: operator(-) => qkc_sub
    generic, public :: operator(*) => qkc_mul
    generic, public :: operator(/) => qkc_div
  end type QkComplex

  !> @brief Overloaded constructor for QkComplex
  !> Accepts either (re, im) as two c_doubles or a single complex(c_double_complex).
  interface QkComplex
    module procedure qkc_from_components
    module procedure qkc_from_native
  end interface QkComplex

contains

  ! QkComplex type-bound procedures

  pure real(c_double) function qkc_re(self)
    class(QkComplex), intent(in) :: self
    qkc_re = real(self%value, c_double)
  end function qkc_re

  pure real(c_double) function qkc_im(self)
    class(QkComplex), intent(in) :: self
    qkc_im = aimag(self%value)
  end function qkc_im

  pure real(c_double) function qkc_magnitude(self)
    class(QkComplex), intent(in) :: self
    qkc_magnitude = abs(self%value)
  end function qkc_magnitude

  !> @note Range [-pi, pi] as per atan2 convention.
  pure real(c_double) function qkc_phase(self)
    class(QkComplex), intent(in) :: self
    qkc_phase = atan2(aimag(self%value), real(self%value, c_double))
  end function qkc_phase

  pure type(QkComplex) function qkc_conjugate(self)
    class(QkComplex), intent(in) :: self
    qkc_conjugate%value = conjg(self%value)
  end function qkc_conjugate

  !> @brief Return the underlying complex(c_double_complex) value.
  !> Use this when packing into a bind(C) struct at a C call site.
  pure complex(c_double_complex) function qkc_to_native(self)
    class(QkComplex), intent(in) :: self
    qkc_to_native = self%value
  end function qkc_to_native

  pure type(QkComplex) function qkc_add(lhs, rhs)
    class(QkComplex), intent(in) :: lhs
    type(QkComplex),  intent(in) :: rhs
    qkc_add%value = lhs%value + rhs%value
  end function qkc_add

  pure type(QkComplex) function qkc_sub(lhs, rhs)
    class(QkComplex), intent(in) :: lhs
    type(QkComplex),  intent(in) :: rhs
    qkc_sub%value = lhs%value - rhs%value
  end function qkc_sub

  pure type(QkComplex) function qkc_mul(lhs, rhs)
    class(QkComplex), intent(in) :: lhs
    type(QkComplex),  intent(in) :: rhs
    qkc_mul%value = lhs%value * rhs%value
  end function qkc_mul

  pure type(QkComplex) function qkc_div(lhs, rhs)
    class(QkComplex), intent(in) :: lhs
    type(QkComplex),  intent(in) :: rhs
    qkc_div%value = lhs%value / rhs%value
  end function qkc_div

  ! QkComplex constructors (backing the overloaded interface above)

  pure type(QkComplex) function qkc_from_components(re, im)
    real(c_double), intent(in) :: re, im
    qkc_from_components%value = cmplx(re, im, c_double_complex)
  end function qkc_from_components

  pure type(QkComplex) function qkc_from_native(z)
    complex(c_double_complex), intent(in) :: z
    qkc_from_native%value = z
  end function qkc_from_native

  ! Error checking and qubit conversion

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
  !> @note Elemental so callers can write to_qubit([0,1,2]) to convert whole arrays
  !>       in a single expression rather than a manual loop.
  elemental integer(QK_QUBIT_KIND) function to_qubit(idx)
    integer, intent(in) :: idx
    to_qubit = int(idx, QK_QUBIT_KIND)
  end function to_qubit

end module qiskit_utils
