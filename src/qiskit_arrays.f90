!> @brief Array utilities for quantum circuit operations
!>
!> Provides type-safe wrappers for passing qubit indices and gate parameters to C API.
module qiskit_arrays
  use, intrinsic :: iso_c_binding, only : c_ptr, c_null_ptr, c_loc, c_double
  use qiskit_c_api_types,          only : QK_QUBIT_KIND
  implicit none (type, external)
  private

  public :: QubitArray, ParamArray
  public :: q, p
  public :: to_c

  !> @brief Array of qubit indices for gate operations
  !> @warning Direct access to v(:) field may break C ABI contract; use to_c() interface
  type :: QubitArray
    integer(QK_QUBIT_KIND), allocatable :: v(:)
  end type QubitArray

  !> @brief Array of gate parameters (angles, etc.)
  !> @warning Direct access to v(:) field may break C ABI contract; use to_c() interface
  type :: ParamArray
    real(c_double), allocatable :: v(:)
  end type ParamArray

  !> @brief Convert QubitArray or ParamArray to C pointer
  !>
  !> Overloaded interface for type-safe conversion to C API.
  !> @note Returns c_null_ptr if array is unallocated or empty
  interface to_c
    module procedure qubit_array_to_c
    module procedure param_array_to_c
  end interface to_c

contains

  ! Internal: create single-qubit array
  function q1(i0) result(qa)
    integer, intent(in) :: i0
    type(QubitArray)    :: qa
    allocate(qa%v(1))
    qa%v(1) = int(i0, QK_QUBIT_KIND)
  end function q1

  ! Internal: create two-qubit array
  function q2(i0, i1) result(qa)
    integer, intent(in) :: i0, i1
    type(QubitArray)    :: qa
    allocate(qa%v(2))
    qa%v(1) = int(i0, QK_QUBIT_KIND)
    qa%v(2) = int(i1, QK_QUBIT_KIND)
  end function q2

  ! Internal: create three-qubit array
  function q3(i0, i1, i2) result(qa)
    integer, intent(in) :: i0, i1, i2
    type(QubitArray)    :: qa
    allocate(qa%v(3))
    qa%v(1) = int(i0, QK_QUBIT_KIND)
    qa%v(2) = int(i1, QK_QUBIT_KIND)
    qa%v(3) = int(i2, QK_QUBIT_KIND)
  end function q3

  !> @brief Create qubit array with 1-3 indices
  !> @param i0 first qubit index
  !> @param i1 optional second qubit index
  !> @param i2 optional third qubit index
  !> @note Intended for inline use: call circuit%cx(q(0,1)) not as standalone arrays
  function q(i0, i1, i2) result(qa)
    integer, intent(in)           :: i0
    integer, intent(in), optional :: i1, i2
    type(QubitArray)              :: qa
    if (present(i2)) then
      qa = q3(i0, i1, i2)
    else if (present(i1)) then
      qa = q2(i0, i1)
    else
      qa = q1(i0)
    end if
  end function q

  ! Internal: create single-parameter array
  function p1(x0) result(pa)
    real(c_double), intent(in) :: x0
    type(ParamArray)           :: pa
    allocate(pa%v(1))
    pa%v(1) = x0
  end function p1

  ! Internal: create two-parameter array
  function p2(x0, x1) result(pa)
    real(c_double), intent(in) :: x0, x1
    type(ParamArray)           :: pa
    allocate(pa%v(2))
    pa%v(1) = x0
    pa%v(2) = x1
  end function p2

  ! Internal: create three-parameter array
  function p3(x0, x1, x2) result(pa)
    real(c_double), intent(in) :: x0, x1, x2
    type(ParamArray)           :: pa
    allocate(pa%v(3))
    pa%v(1) = x0
    pa%v(2) = x1
    pa%v(3) = x2
  end function p3

  !> @brief Create parameter array with 1-3 values
  !> @param x0 first parameter value (e.g., rotation angle in radians)
  !> @param x1 optional second parameter value
  !> @param x2 optional third parameter value
  !> @note Intended for inline use: call circuit%u(theta,phi,lam,q(0)) not as standalone arrays
  function p(x0, x1, x2) result(pa)
    real(c_double), intent(in)           :: x0
    real(c_double), intent(in), optional :: x1, x2
    type(ParamArray)                     :: pa
    if (present(x2)) then
      pa = p3(x0, x1, x2)
    else if (present(x1)) then
      pa = p2(x0, x1)
    else
      pa = p1(x0)
    end if
  end function p

  ! Internal: convert QubitArray to C pointer (via to_c interface)
  function qubit_array_to_c(qa) result(ptr)
    type(QubitArray), intent(in), target :: qa
    type(c_ptr)                          :: ptr
    ! Must use nested if to avoid evaluating size() on unallocated array
    ! (Fortran .and. does not short-circuit)
    if (allocated(qa%v)) then
      if (size(qa%v) > 0) then
        ptr = c_loc(qa%v)
      else
        ptr = c_null_ptr
      end if
    else
      ptr = c_null_ptr
    end if
  end function qubit_array_to_c

  ! Internal: convert ParamArray to C pointer (via to_c interface)
  function param_array_to_c(pa) result(ptr)
    type(ParamArray), intent(in), target :: pa
    type(c_ptr)                          :: ptr
    ! Must use nested if to avoid evaluating size() on unallocated array
    ! (Fortran .and. does not short-circuit)
    if (allocated(pa%v)) then
      if (size(pa%v) > 0) then
        ptr = c_loc(pa%v)
      else
        ptr = c_null_ptr
      end if
    else
      ptr = c_null_ptr
    end if
  end function param_array_to_c

end module qiskit_arrays