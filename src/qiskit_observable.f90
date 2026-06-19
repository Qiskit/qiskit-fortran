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

!> @brief Observable module for quantum observables (Pauli operators)
!>
!> Provides types and functions for creating and manipulating quantum observables,
!> which are represented as sums of Pauli terms with complex coefficients.
module qiskit_observable
  use, intrinsic :: iso_c_binding, only : &
      c_ptr, c_null_ptr, c_associated, c_int, c_int32_t, c_int64_t, &
      c_size_t, c_double, c_bool, c_char, c_null_char, c_f_pointer

#ifdef USE_SWIG_BINDINGS
  use qiskit_swigf, only : &
      QkComplex64, QkObsTerm, &
      qk_obs_zero, qk_obs_identity, qk_obs_new, qk_obs_free, &
      qk_obs_add_term, qk_obs_term, qk_obs_num_terms, qk_obs_num_qubits, &
      qk_obs_len, qk_obs_coeffs, qk_obs_indices, qk_obs_boundaries, &
      qk_obs_bit_terms, qk_obs_multiply, qk_obs_multiply_inplace, &
      qk_obs_add, qk_obs_add_inplace, qk_obs_scaled_add, &
      qk_obs_scaled_add_inplace, qk_obs_compose, qk_obs_compose_map, &
      qk_obs_apply_layout, qk_obs_canonicalize, qk_obs_copy, &
      qk_obs_equal, qk_obs_str, qk_obsterm_str
#endif

  use qiskit_utils, only : check_rc, to_qubit, QK_QUBIT_KIND

  implicit none (type, external)
  private

  public :: Observable
  public :: ObsTerm
  public :: Complex64

  !> @brief Complex number type for observable coefficients
  !> @note Matches QkComplex64 from SWIG bindings
  type :: Complex64
    real(c_double) :: re = 0.0_c_double
    real(c_double) :: im = 0.0_c_double
  end type Complex64

  !> @brief Observable term with coefficient and Pauli operators
  !> @note Matches QkObsTerm from SWIG bindings
  type :: ObsTerm
    type(Complex64) :: coeff
    integer(c_size_t) :: len = 0_c_size_t
    type(c_ptr) :: bit_terms = c_null_ptr
    type(c_ptr) :: indices = c_null_ptr
    integer(c_int32_t) :: num_qubits = 0_c_int32_t
  end type ObsTerm

  !> @brief Quantum observable (sum of Pauli terms)
  !>
  !> Represents a quantum observable as a sum of Pauli terms, each with a complex
  !> coefficient. Provides methods for construction, manipulation, and arithmetic
  !> operations on observables.
  type :: Observable
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    ! Constructors
    procedure, public :: init_zero     => obs_init_zero
    procedure, public :: init_identity => obs_init_identity
    procedure, public :: init_new      => obs_init_new
    
    ! Destructor and memory management
    procedure, public :: destroy       => obs_destroy_manual
    procedure, public :: get_c_ptr     => obs_get_c_ptr
    procedure, public :: from_ptr      => obs_from_ptr
    
    ! Query methods
    procedure, public :: num_terms     => obs_num_terms
    procedure, public :: num_qubits    => obs_num_qubits
    procedure, public :: len           => obs_len
    
    ! Data access methods
    procedure, public :: get_coeffs    => obs_get_coeffs
    procedure, public :: get_indices   => obs_get_indices
    procedure, public :: get_boundaries => obs_get_boundaries
    procedure, public :: get_bit_terms => obs_get_bit_terms
    
    ! Term manipulation
    procedure, public :: add_term      => obs_add_term
    procedure, public :: get_term      => obs_get_term
    
    ! Arithmetic operations
    procedure, public :: multiply      => obs_multiply
    procedure, public :: multiply_inplace => obs_multiply_inplace
    procedure, public :: add           => obs_add
    procedure, public :: add_inplace   => obs_add_inplace
    procedure, public :: scaled_add    => obs_scaled_add
    procedure, public :: scaled_add_inplace => obs_scaled_add_inplace
    
    ! Composition
    procedure, public :: compose       => obs_compose
    procedure, public :: compose_map   => obs_compose_map
    
    ! Utility methods
    procedure, public :: apply_layout  => obs_apply_layout
    procedure, public :: canonicalize  => obs_canonicalize
    procedure, public :: copy          => obs_copy
    procedure, public :: equal         => obs_equal
    procedure, public :: to_string     => obs_to_string
    
    ! Finalizer
    final :: obs_destroy
  end type Observable

contains

  ! Constructors

  !> @brief Initialize observable as zero operator
  !> @param num_qubits number of qubits
  subroutine obs_init_zero(self, num_qubits)
    class(Observable), intent(inout) :: self
    integer, intent(in) :: num_qubits

    if (c_associated(self%ptr)) then
      call qk_obs_free(self%ptr)
      self%ptr = c_null_ptr
    end if
    
    self%ptr = qk_obs_zero(to_qubit(num_qubits))
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] init_zero: qk_obs_zero returned null"
  end subroutine obs_init_zero

  !> @brief Initialize observable as identity operator
  !> @param num_qubits number of qubits
  subroutine obs_init_identity(self, num_qubits)
    class(Observable), intent(inout) :: self
    integer, intent(in) :: num_qubits

    if (c_associated(self%ptr)) then
      call qk_obs_free(self%ptr)
      self%ptr = c_null_ptr
    end if
    
    self%ptr = qk_obs_identity(to_qubit(num_qubits))
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] init_identity: qk_obs_identity returned null"
  end subroutine obs_init_identity

  !> @brief Initialize observable from raw data
  !> @param num_qubits number of qubits
  !> @param num_terms number of terms
  !> @param num_bits total number of Pauli operators
  !> @param coeffs complex coefficients for each term
  !> @param bit_terms Pauli operator types (I=0, X=1, Y=2, Z=3)
  !> @param indices qubit indices for each operator
  !> @param boundaries term boundaries in bit_terms/indices arrays
  subroutine obs_init_new(self, num_qubits, num_terms, num_bits, coeffs, bit_terms, indices, boundaries)
    class(Observable), intent(inout) :: self
    integer, intent(in) :: num_qubits
    integer(c_int64_t), intent(in) :: num_terms
    integer(c_int64_t), intent(in) :: num_bits
    type(Complex64), intent(in), target :: coeffs(*)
    integer(c_int), intent(in), target :: bit_terms(*)
    integer(c_int32_t), intent(in), target :: indices(*)
    integer(c_size_t), intent(in), target :: boundaries(*)

    type(QkComplex64), pointer :: c_coeffs(:)
    integer :: i

    if (c_associated(self%ptr)) then
      call qk_obs_free(self%ptr)
      self%ptr = c_null_ptr
    end if

    ! Convert Complex64 array to QkComplex64 for C API
    allocate(c_coeffs(num_terms))
    do i = 1, int(num_terms)
      c_coeffs(i)%re = coeffs(i)%re
      c_coeffs(i)%im = coeffs(i)%im
    end do
    
    self%ptr = qk_obs_new(to_qubit(num_qubits), num_terms, num_bits, &
                          c_coeffs(1), bit_terms(1), indices(1), boundaries(1))
    
    deallocate(c_coeffs)
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] init_new: qk_obs_new returned null"
  end subroutine obs_init_new

  ! Destructor and memory management

  !> @brief Manual destructor (can be called explicitly)
  subroutine obs_destroy_manual(self)
    class(Observable), intent(inout) :: self
    if (c_associated(self%ptr)) then
      call qk_obs_free(self%ptr)
      self%ptr = c_null_ptr
    end if
  end subroutine obs_destroy_manual

  !> @brief Automatic finalizer
  subroutine obs_destroy(self)
    type(Observable), intent(inout) :: self
    if (c_associated(self%ptr)) then
      call qk_obs_free(self%ptr)
      self%ptr = c_null_ptr
    end if
  end subroutine obs_destroy

  !> @brief Get C pointer (for interop with other modules)
  function obs_get_c_ptr(self) result(ptr)
    class(Observable), intent(in) :: self
    type(c_ptr) :: ptr
    ptr = self%ptr
  end function obs_get_c_ptr

  !> @brief Initialize from C pointer (takes ownership)
  subroutine obs_from_ptr(self, ptr)
    class(Observable), intent(inout) :: self
    type(c_ptr), intent(in) :: ptr
    if (c_associated(self%ptr)) call qk_obs_free(self%ptr)
    self%ptr = ptr
  end subroutine obs_from_ptr

  ! Query methods

  !> @brief Get number of terms in observable
  function obs_num_terms(self) result(n)
    class(Observable), intent(in) :: self
    integer(c_size_t) :: n
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] num_terms: uninitialised observable"
    
    n = qk_obs_num_terms(self%ptr)
  end function obs_num_terms

  !> @brief Get number of qubits
  function obs_num_qubits(self) result(n)
    class(Observable), intent(in) :: self
    integer :: n
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] num_qubits: uninitialised observable"
    
    n = int(qk_obs_num_qubits(self%ptr))
  end function obs_num_qubits

  !> @brief Get total length (number of Pauli operators across all terms)
  function obs_len(self) result(n)
    class(Observable), intent(in) :: self
    integer(c_size_t) :: n
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] len: uninitialised observable"
    
    n = qk_obs_len(self%ptr)
  end function obs_len

  ! Data access methods

  !> @brief Get pointer to coefficients array
  !> @note Returns C pointer; use c_f_pointer to access data
  function obs_get_coeffs(self) result(ptr)
    class(Observable), intent(in) :: self
    type(c_ptr) :: ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] get_coeffs: uninitialised observable"
    
    ptr = qk_obs_coeffs(self%ptr)
  end function obs_get_coeffs

  !> @brief Get pointer to indices array
  !> @note Returns C pointer; use c_f_pointer to access data
  function obs_get_indices(self) result(ptr)
    class(Observable), intent(in) :: self
    type(c_ptr) :: ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] get_indices: uninitialised observable"
    
    ptr = qk_obs_indices(self%ptr)
  end function obs_get_indices

  !> @brief Get pointer to boundaries array
  !> @note Returns C pointer; use c_f_pointer to access data
  function obs_get_boundaries(self) result(ptr)
    class(Observable), intent(in) :: self
    type(c_ptr) :: ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] get_boundaries: uninitialised observable"
    
    ptr = qk_obs_boundaries(self%ptr)
  end function obs_get_boundaries

  !> @brief Get pointer to bit_terms array
  !> @note Returns C pointer; use c_f_pointer to access data
  function obs_get_bit_terms(self) result(ptr)
    class(Observable), intent(in) :: self
    type(c_ptr) :: ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] get_bit_terms: uninitialised observable"
    
    ptr = qk_obs_bit_terms(self%ptr)
  end function obs_get_bit_terms

  ! Term manipulation

  !> @brief Add a term to the observable
  !> @param term observable term to add
  subroutine obs_add_term(self, term)
    class(Observable), intent(inout) :: self
    type(ObsTerm), intent(in) :: term
    
    type(QkObsTerm) :: c_term
    integer(c_int) :: rc
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] add_term: uninitialised observable"
    
    ! Convert ObsTerm to QkObsTerm
    c_term%coeff%re = term%coeff%re
    c_term%coeff%im = term%coeff%im
    c_term%len = term%len
    c_term%bit_terms = term%bit_terms
    c_term%indices = term%indices
    c_term%num_qubits = term%num_qubits
    
    rc = qk_obs_add_term(self%ptr, c_term)
    call check_rc(rc, "add_term")
  end subroutine obs_add_term

  !> @brief Get a term from the observable
  !> @param index term index (0-based)
  !> @param term output term
  subroutine obs_get_term(self, index, term)
    class(Observable), intent(in) :: self
    integer(c_int64_t), intent(in) :: index
    type(ObsTerm), intent(out) :: term
    
    type(QkObsTerm) :: c_term
    integer(c_int) :: rc
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] get_term: uninitialised observable"
    
    rc = qk_obs_term(self%ptr, index, c_term)
    call check_rc(rc, "get_term")
    
    ! Convert QkObsTerm to ObsTerm
    term%coeff%re = c_term%coeff%re
    term%coeff%im = c_term%coeff%im
    term%len = c_term%len
    term%bit_terms = c_term%bit_terms
    term%indices = c_term%indices
    term%num_qubits = c_term%num_qubits
  end subroutine obs_get_term

  ! Arithmetic operations

  !> @brief Multiply observable by a scalar (returns new observable)
  !> @param coeff complex coefficient
  function obs_multiply(self, coeff) result(result_obs)
    class(Observable), intent(in) :: self
    type(Complex64), intent(in) :: coeff
    type(Observable) :: result_obs
    
    type(QkComplex64) :: c_coeff
    type(c_ptr) :: result_ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] multiply: uninitialised observable"
    
    c_coeff%re = coeff%re
    c_coeff%im = coeff%im
    
    result_ptr = qk_obs_multiply(self%ptr, c_coeff)
    if (.not. c_associated(result_ptr)) &
        error stop "[qiskit_observable] multiply: operation failed"
    
    call result_obs%from_ptr(result_ptr)
  end function obs_multiply

  !> @brief Multiply observable by a scalar in-place
  !> @param coeff complex coefficient
  subroutine obs_multiply_inplace(self, coeff)
    class(Observable), intent(inout) :: self
    type(Complex64), intent(in) :: coeff
    
    type(QkComplex64) :: c_coeff
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] multiply_inplace: uninitialised observable"
    
    c_coeff%re = coeff%re
    c_coeff%im = coeff%im
    
    call qk_obs_multiply_inplace(self%ptr, c_coeff)
  end subroutine obs_multiply_inplace

  !> @brief Add two observables (returns new observable)
  !> @param other observable to add
  function obs_add(self, other) result(result_obs)
    class(Observable), intent(in) :: self
    type(Observable), intent(in) :: other
    type(Observable) :: result_obs
    
    type(c_ptr) :: result_ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] add: uninitialised observable (self)"
    if (.not. c_associated(other%ptr)) &
        error stop "[qiskit_observable] add: uninitialised observable (other)"
    
    result_ptr = qk_obs_add(self%ptr, other%ptr)
    if (.not. c_associated(result_ptr)) &
        error stop "[qiskit_observable] add: operation failed"
    
    call result_obs%from_ptr(result_ptr)
  end function obs_add

  !> @brief Add observable in-place
  !> @param other observable to add
  subroutine obs_add_inplace(self, other)
    class(Observable), intent(inout) :: self
    type(Observable), intent(in) :: other
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] add_inplace: uninitialised observable (self)"
    if (.not. c_associated(other%ptr)) &
        error stop "[qiskit_observable] add_inplace: uninitialised observable (other)"
    
    call qk_obs_add_inplace(self%ptr, other%ptr)
  end subroutine obs_add_inplace

  !> @brief Scaled addition: self + factor * other (returns new observable)
  !> @param other observable to add
  !> @param factor scaling factor
  function obs_scaled_add(self, other, factor) result(result_obs)
    class(Observable), intent(in) :: self
    type(Observable), intent(in) :: other
    type(Complex64), intent(in) :: factor
    type(Observable) :: result_obs
    
    type(QkComplex64) :: c_factor
    type(c_ptr) :: result_ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] scaled_add: uninitialised observable (self)"
    if (.not. c_associated(other%ptr)) &
        error stop "[qiskit_observable] scaled_add: uninitialised observable (other)"
    
    c_factor%re = factor%re
    c_factor%im = factor%im
    
    result_ptr = qk_obs_scaled_add(self%ptr, other%ptr, c_factor)
    if (.not. c_associated(result_ptr)) &
        error stop "[qiskit_observable] scaled_add: operation failed"
    
    call result_obs%from_ptr(result_ptr)
  end function obs_scaled_add

  !> @brief Scaled addition in-place: self = self + factor * other
  !> @param other observable to add
  !> @param factor scaling factor
  subroutine obs_scaled_add_inplace(self, other, factor)
    class(Observable), intent(inout) :: self
    type(Observable), intent(in) :: other
    type(Complex64), intent(in) :: factor
    
    type(QkComplex64) :: c_factor
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] scaled_add_inplace: uninitialised observable (self)"
    if (.not. c_associated(other%ptr)) &
        error stop "[qiskit_observable] scaled_add_inplace: uninitialised observable (other)"
    
    c_factor%re = factor%re
    c_factor%im = factor%im
    
    call qk_obs_scaled_add_inplace(self%ptr, other%ptr, c_factor)
  end subroutine obs_scaled_add_inplace

  ! Composition

  !> @brief Compose two observables (tensor product)
  !> @param other observable to compose with
  function obs_compose(self, other) result(result_obs)
    class(Observable), intent(in) :: self
    type(Observable), intent(in) :: other
    type(Observable) :: result_obs
    
    type(c_ptr) :: result_ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] compose: uninitialised observable (self)"
    if (.not. c_associated(other%ptr)) &
        error stop "[qiskit_observable] compose: uninitialised observable (other)"
    
    result_ptr = qk_obs_compose(self%ptr, other%ptr)
    if (.not. c_associated(result_ptr)) &
        error stop "[qiskit_observable] compose: operation failed"
    
    call result_obs%from_ptr(result_ptr)
  end function obs_compose

  !> @brief Compose with qubit mapping
  !> @param other observable to compose with
  !> @param qargs qubit indices for mapping
  function obs_compose_map(self, other, qargs) result(result_obs)
    class(Observable), intent(in) :: self
    type(Observable), intent(in) :: other
    integer(c_int32_t), intent(in), target :: qargs(*)
    type(Observable) :: result_obs
    
    type(c_ptr) :: result_ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] compose_map: uninitialised observable (self)"
    if (.not. c_associated(other%ptr)) &
        error stop "[qiskit_observable] compose_map: uninitialised observable (other)"
    
    result_ptr = qk_obs_compose_map(self%ptr, other%ptr, qargs(1))
    if (.not. c_associated(result_ptr)) &
        error stop "[qiskit_observable] compose_map: operation failed"
    
    call result_obs%from_ptr(result_ptr)
  end function obs_compose_map

  ! Utility methods

  !> @brief Apply qubit layout to observable
  !> @param layout qubit layout mapping
  !> @param num_qubits number of qubits in layout
  subroutine obs_apply_layout(self, layout, num_qubits)
    class(Observable), intent(inout) :: self
    integer(c_int32_t), intent(in), target :: layout(*)
    integer, intent(in) :: num_qubits
    
    integer(c_int) :: rc
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] apply_layout: uninitialised observable"
    
    rc = qk_obs_apply_layout(self%ptr, layout(1), to_qubit(num_qubits))
    call check_rc(rc, "apply_layout")
  end subroutine obs_apply_layout

  !> @brief Canonicalize observable (simplify and remove small terms)
  !> @param tol tolerance for removing small coefficients
  function obs_canonicalize(self, tol) result(result_obs)
    class(Observable), intent(in) :: self
    real(c_double), intent(in) :: tol
    type(Observable) :: result_obs
    
    type(c_ptr) :: result_ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] canonicalize: uninitialised observable"
    
    result_ptr = qk_obs_canonicalize(self%ptr, tol)
    if (.not. c_associated(result_ptr)) &
        error stop "[qiskit_observable] canonicalize: operation failed"
    
    call result_obs%from_ptr(result_ptr)
  end function obs_canonicalize

  !> @brief Create a copy of the observable
  function obs_copy(self) result(result_obs)
    class(Observable), intent(in) :: self
    type(Observable) :: result_obs
    
    type(c_ptr) :: result_ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] copy: uninitialised observable"
    
    result_ptr = qk_obs_copy(self%ptr)
    if (.not. c_associated(result_ptr)) &
        error stop "[qiskit_observable] copy: operation failed"
    
    call result_obs%from_ptr(result_ptr)
  end function obs_copy

  !> @brief Check if two observables are equal
  !> @param other observable to compare with
  function obs_equal(self, other) result(is_equal)
    class(Observable), intent(in) :: self
    type(Observable), intent(in) :: other
    logical :: is_equal
    
    logical(c_bool) :: c_result
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] equal: uninitialised observable (self)"
    if (.not. c_associated(other%ptr)) &
        error stop "[qiskit_observable] equal: uninitialised observable (other)"
    
    c_result = qk_obs_equal(self%ptr, other%ptr)
    is_equal = logical(c_result)
  end function obs_equal

  !> @brief Convert observable to string representation
  function obs_to_string(self) result(str)
    class(Observable), intent(in) :: self
    character(len=:), allocatable :: str
    
    type(c_ptr) :: c_str_ptr
    character(kind=c_char), pointer :: c_str(:)
    integer :: i, str_len
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_observable] to_string: uninitialised observable"
    
    c_str_ptr = qk_obs_str(self%ptr)
    if (.not. c_associated(c_str_ptr)) &
        error stop "[qiskit_observable] to_string: string conversion failed"
    
    ! Find string length (up to null terminator)
    call c_f_pointer(c_str_ptr, c_str, [1024])  ! Assume max length
    str_len = 0
    do i = 1, 1024
      if (c_str(i) == c_null_char) exit
      str_len = str_len + 1
    end do
    
    ! Copy to Fortran string
    allocate(character(len=str_len) :: str)
    do i = 1, str_len
      str(i:i) = c_str(i)
    end do
    
    ! Note: qk_str_free expects a character array, not a pointer
    ! The C API should handle cleanup internally
  end function obs_to_string

  !> @brief Convert observable term to string representation
  !> @param term observable term
  function obsterm_to_string(term) result(str)
    type(ObsTerm), intent(in) :: term
    character(len=:), allocatable :: str
    
    type(QkObsTerm) :: c_term
    type(c_ptr) :: c_str_ptr
    character(kind=c_char), pointer :: c_str(:)
    integer :: i, str_len
    
    ! Convert ObsTerm to QkObsTerm
    c_term%coeff%re = term%coeff%re
    c_term%coeff%im = term%coeff%im
    c_term%len = term%len
    c_term%bit_terms = term%bit_terms
    c_term%indices = term%indices
    c_term%num_qubits = term%num_qubits
    
    c_str_ptr = qk_obsterm_str(c_term)
    if (.not. c_associated(c_str_ptr)) &
        error stop "[qiskit_observable] obsterm_to_string: string conversion failed"
    
    ! Find string length (up to null terminator)
    call c_f_pointer(c_str_ptr, c_str, [1024])  ! Assume max length
    str_len = 0
    do i = 1, 1024
      if (c_str(i) == c_null_char) exit
      str_len = str_len + 1
    end do
    
    ! Copy to Fortran string
    allocate(character(len=str_len) :: str)
    do i = 1, str_len
      str(i:i) = c_str(i)
    end do
  end function obsterm_to_string

end module qiskit_observable
