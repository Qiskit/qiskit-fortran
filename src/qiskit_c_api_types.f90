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
      c_int, c_int32_t, c_double, c_double_complex

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
  
  ! QkComplex type and related
  public :: QkComplex
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

  !> @brief C-interoperable complex number type for SWIG bindings
  !> @note Matches QkComplex64 structure from C API (two doubles: re, im)
  type, bind(C) :: QkComplex64
    real(c_double) :: re = 0.0_c_double
    real(c_double) :: im = 0.0_c_double
  end type QkComplex64

  !> @brief Fortran-native complex number wrapper with type-bound procedures
  !>
  !> Provides a high-level interface for complex arithmetic with automatic
  !> conversion to/from C-interoperable QkComplex64 for SWIG interop.
  !> Supports operator overloading and common complex number operations.
  !>
  !> @par Example:
  !> @code{.f90}
  !>   type(QkComplex) :: z1, z2, z3
  !>   z1 = QkComplex(1.0_c_double, 2.0_c_double)
  !>   z2 = QkComplex(3.0_c_double, -1.0_c_double)
  !>   z3 = z1 + z2  ! Operator overloading
  !>   print *, z3%magnitude(), z3%phase()
  !> @endcode
  type :: QkComplex
    private
    complex(c_double_complex) :: value = (0.0_c_double, 0.0_c_double)
  contains
    !> @brief Get real part of complex number
    procedure, public :: real_part => qkc_real_part
    
    !> @brief Get imaginary part of complex number
    procedure, public :: imag_part => qkc_imag_part
    
    !> @brief Calculate magnitude (absolute value) of complex number
    procedure, public :: magnitude => qkc_magnitude
    
    !> @brief Calculate phase (argument) of complex number in radians
    procedure, public :: phase => qkc_phase
    
    !> @brief Return complex conjugate
    procedure, public :: conjugate => qkc_conjugate
    
    !> @brief Convert to C-interoperable QkComplex64 for SWIG
    procedure, public :: to_qk_complex64 => qkc_to_qk_complex64
    
    !> @brief Initialize from C-interoperable QkComplex64
    procedure, public :: from_qk_complex64 => qkc_from_qk_complex64
    
    !> @brief Get native Fortran complex value
    procedure, public :: get_value => qkc_get_value
    
    ! Operator overloading
    procedure, private :: qkc_add
    procedure, private :: qkc_sub
    procedure, private :: qkc_mul
    procedure, private :: qkc_div
    generic, public :: operator(+) => qkc_add
    generic, public :: operator(-) => qkc_sub
    generic, public :: operator(*) => qkc_mul
    generic, public :: operator(/) => qkc_div
  end type QkComplex

  !> @brief Constructor interface for QkComplex
  !>
  !> Supports two forms:
  !> - QkComplex(re, im) - construct from real and imaginary parts
  !> - QkComplex(complex_value) - construct from native complex value
  interface QkComplex
    module procedure qkc_from_components
    module procedure qkc_from_complex
  end interface QkComplex

contains

  ! QkComplex Type-Bound Procedures

  !> @brief Get real part of complex number
  !> @param self complex number
  !> @return real part
  pure function qkc_real_part(self) result(re)
    class(QkComplex), intent(in) :: self
    real(c_double) :: re
    re = real(self%value, c_double)
  end function qkc_real_part

  !> @brief Get imaginary part of complex number
  !> @param self complex number
  !> @return imaginary part
  pure function qkc_imag_part(self) result(im)
    class(QkComplex), intent(in) :: self
    real(c_double) :: im
    im = aimag(self%value)
  end function qkc_imag_part

  !> @brief Calculate magnitude (absolute value) of complex number
  !> @param self complex number
  !> @return magnitude |z|
  pure function qkc_magnitude(self) result(mag)
    class(QkComplex), intent(in) :: self
    real(c_double) :: mag
    mag = abs(self%value)
  end function qkc_magnitude

  !> @brief Calculate phase (argument) of complex number
  !> @param self complex number
  !> @return phase in radians, range [-π, π]
  pure function qkc_phase(self) result(phi)
    class(QkComplex), intent(in) :: self
    real(c_double) :: phi
    phi = atan2(aimag(self%value), real(self%value, c_double))
  end function qkc_phase

  !> @brief Return complex conjugate
  !> @param self complex number
  !> @return conjugate z*
  pure function qkc_conjugate(self) result(conj_z)
    class(QkComplex), intent(in) :: self
    type(QkComplex) :: conj_z
    conj_z%value = conjg(self%value)
  end function qkc_conjugate

  !> @brief Convert to C-interoperable QkComplex64 for SWIG
  !> @param self complex number
  !> @return QkComplex64 structure
  pure function qkc_to_qk_complex64(self) result(c64)
    class(QkComplex), intent(in) :: self
    type(QkComplex64) :: c64
    c64%re = real(self%value, c_double)
    c64%im = aimag(self%value)
  end function qkc_to_qk_complex64

  !> @brief Initialize from C-interoperable QkComplex64
  !> @param self complex number (modified)
  !> @param c64 QkComplex64 structure
  pure subroutine qkc_from_qk_complex64(self, c64)
    class(QkComplex), intent(inout) :: self
    type(QkComplex64), intent(in) :: c64
    self%value = cmplx(c64%re, c64%im, c_double_complex)
  end subroutine qkc_from_qk_complex64

  !> @brief Get native Fortran complex value
  !> @param self complex number
  !> @return native complex(c_double_complex) value
  pure function qkc_get_value(self) result(val)
    class(QkComplex), intent(in) :: self
    complex(c_double_complex) :: val
    val = self%value
  end function qkc_get_value

  ! QkComplex Constructors

  !> @brief Construct QkComplex from real and imaginary components
  !> @param re real part
  !> @param im imaginary part
  !> @return new QkComplex instance
  pure function qkc_from_components(re, im) result(z)
    real(c_double), intent(in) :: re
    real(c_double), intent(in) :: im
    type(QkComplex) :: z
    z%value = cmplx(re, im, c_double_complex)
  end function qkc_from_components

  !> @brief Construct QkComplex from native complex value
  !> @param complex_value native Fortran complex number
  !> @return new QkComplex instance
  pure function qkc_from_complex(complex_value) result(z)
    complex(c_double_complex), intent(in) :: complex_value
    type(QkComplex) :: z
    z%value = complex_value
  end function qkc_from_complex

  ! QkComplex Operator Overloading

  !> @brief Addition operator for QkComplex
  !> @param lhs left operand
  !> @param rhs right operand
  !> @return lhs + rhs
  pure function qkc_add(lhs, rhs) result(res)
    class(QkComplex), intent(in) :: lhs
    type(QkComplex), intent(in) :: rhs
    type(QkComplex) :: res
    res%value = lhs%value + rhs%value
  end function qkc_add

  !> @brief Subtraction operator for QkComplex
  !> @param lhs left operand
  !> @param rhs right operand
  !> @return lhs - rhs
  pure function qkc_sub(lhs, rhs) result(res)
    class(QkComplex), intent(in) :: lhs
    type(QkComplex), intent(in) :: rhs
    type(QkComplex) :: res
    res%value = lhs%value - rhs%value
  end function qkc_sub

  !> @brief Multiplication operator for QkComplex
  !> @param lhs left operand
  !> @param rhs right operand
  !> @return lhs * rhs
  pure function qkc_mul(lhs, rhs) result(res)
    class(QkComplex), intent(in) :: lhs
    type(QkComplex), intent(in) :: rhs
    type(QkComplex) :: res
    res%value = lhs%value * rhs%value
  end function qkc_mul

  !> @brief Division operator for QkComplex
  !> @param lhs left operand
  !> @param rhs right operand
  !> @return lhs / rhs
  pure function qkc_div(lhs, rhs) result(res)
    class(QkComplex), intent(in) :: lhs
    type(QkComplex), intent(in) :: rhs
    type(QkComplex) :: res
    res%value = lhs%value / rhs%value
  end function qkc_div


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
