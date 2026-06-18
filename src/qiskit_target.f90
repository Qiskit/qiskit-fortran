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

module qiskit_target
  use, intrinsic :: iso_c_binding, only : &
      c_ptr, c_null_ptr, c_associated, c_int, c_double, c_int32_t, c_size_t, c_null_char

  ! qk_target_* all have a dummy arg named 'target'; a module-level import would
  ! embed that name in the .mod file, breaking any consumer that declares type(Target).
  ! Each procedure imports only what it needs at local scope instead.
  use qiskit_utils, only : check_rc, to_qubit, QK_QUBIT_KIND

  implicit none (type, external)
  private

  public :: Target
  public :: InstructionProperties

  !> @brief Quantum hardware constraints: supported gates, connectivity, timing.
  !> @note All qubit indices are 0-indexed, matching the C API and Python.
  type :: Target
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public :: init               => tg_init
    procedure, public :: num_qubits         => tg_num_qubits
    procedure, public :: dt                 => tg_dt
    procedure, public :: granularity        => tg_granularity
    procedure, public :: min_length         => tg_min_length
    procedure, public :: pulse_alignment    => tg_pulse_alignment
    procedure, public :: acquire_alignment  => tg_acquire_alignment
    procedure, public :: set_dt             => tg_set_dt
    procedure, public :: set_granularity    => tg_set_granularity
    procedure, public :: set_min_length     => tg_set_min_length
    procedure, public :: set_pulse_alignment   => tg_set_pulse_alignment
    procedure, public :: set_acquire_alignment => tg_set_acquire_alignment
    procedure, public :: add_instruction    => tg_add_instruction
    procedure, public :: num_instructions   => tg_num_instructions
    procedure, public :: get_c_ptr          => tg_get_c_ptr
    procedure, private :: from_ptr          => tg_from_ptr
    final :: tg_destroy
  end type Target

  !> @brief Per-qubit properties for a single instruction in a Target.
  !> @note Matches Python's qiskit.transpiler.InstructionProperties.
  type :: InstructionProperties
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public  :: init_gate    => ip_init_gate
    procedure, public  :: init_measure => ip_init_measure
    procedure, public  :: init_reset   => ip_init_reset
    procedure, public  :: add_property => ip_add_property
    procedure, public  :: set_name     => ip_set_name
    procedure, private :: get_c_ptr    => ip_get_c_ptr
    final :: ip_destroy
  end type InstructionProperties

contains

  ! ============================================================================
  ! Target
  ! ============================================================================

  subroutine tg_init(self, num_qubits)
    use qiskit_swigf, only : qk_target_new, qk_target_free
    class(Target), intent(inout) :: self
    integer, intent(in) :: num_qubits

    if (c_associated(self%ptr)) then
      call qk_target_free(self%ptr)
      self%ptr = c_null_ptr
    end if
    self%ptr = qk_target_new(to_qubit(num_qubits))
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] init: qk_target_new returned null"
  end subroutine tg_init

  subroutine tg_destroy(self)
    use qiskit_swigf, only : qk_target_free
    type(Target), intent(inout) :: self
    if (c_associated(self%ptr)) then
      call qk_target_free(self%ptr)
      self%ptr = c_null_ptr
    end if
  end subroutine tg_destroy

  function tg_num_qubits(self) result(n)
    use qiskit_swigf, only : qk_target_num_qubits
    class(Target), intent(in) :: self
    integer :: n
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] num_qubits: uninitialised target"
    n = int(qk_target_num_qubits(self%ptr))
  end function tg_num_qubits

  function tg_dt(self) result(dt)
    use qiskit_swigf, only : qk_target_dt
    class(Target), intent(in) :: self
    real(c_double) :: dt
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] dt: uninitialised target"
    dt = qk_target_dt(self%ptr)
  end function tg_dt

  function tg_granularity(self) result(g)
    use qiskit_swigf, only : qk_target_granularity
    class(Target), intent(in) :: self
    integer :: g
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] granularity: uninitialised target"
    g = int(qk_target_granularity(self%ptr))
  end function tg_granularity

  function tg_min_length(self) result(ml)
    use qiskit_swigf, only : qk_target_min_length
    class(Target), intent(in) :: self
    integer :: ml
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] min_length: uninitialised target"
    ml = int(qk_target_min_length(self%ptr))
  end function tg_min_length

  function tg_pulse_alignment(self) result(pa)
    use qiskit_swigf, only : qk_target_pulse_alignment
    class(Target), intent(in) :: self
    integer :: pa
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] pulse_alignment: uninitialised target"
    pa = int(qk_target_pulse_alignment(self%ptr))
  end function tg_pulse_alignment

  function tg_acquire_alignment(self) result(aa)
    use qiskit_swigf, only : qk_target_acquire_alignment
    class(Target), intent(in) :: self
    integer :: aa
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] acquire_alignment: uninitialised target"
    aa = int(qk_target_acquire_alignment(self%ptr))
  end function tg_acquire_alignment

  subroutine tg_set_dt(self, dt)
    use qiskit_swigf, only : qk_target_set_dt
    class(Target), intent(inout) :: self
    real(c_double), intent(in) :: dt
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] set_dt: uninitialised target"
    call check_rc(qk_target_set_dt(self%ptr, dt), "set_dt")
  end subroutine tg_set_dt

  subroutine tg_set_granularity(self, granularity)
    use qiskit_swigf, only : qk_target_set_granularity
    class(Target), intent(inout) :: self
    integer, intent(in) :: granularity
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] set_granularity: uninitialised target"
    call check_rc(qk_target_set_granularity(self%ptr, int(granularity, c_int32_t)), "set_granularity")
  end subroutine tg_set_granularity

  subroutine tg_set_min_length(self, min_length)
    use qiskit_swigf, only : qk_target_set_min_length
    class(Target), intent(inout) :: self
    integer, intent(in) :: min_length
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] set_min_length: uninitialised target"
    call check_rc(qk_target_set_min_length(self%ptr, int(min_length, c_int32_t)), "set_min_length")
  end subroutine tg_set_min_length

  subroutine tg_set_pulse_alignment(self, pulse_alignment)
    use qiskit_swigf, only : qk_target_set_pulse_alignment
    class(Target), intent(inout) :: self
    integer, intent(in) :: pulse_alignment
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] set_pulse_alignment: uninitialised target"
    call check_rc(qk_target_set_pulse_alignment(self%ptr, int(pulse_alignment, c_int32_t)), &
                  "set_pulse_alignment")
  end subroutine tg_set_pulse_alignment

  subroutine tg_set_acquire_alignment(self, acquire_alignment)
    use qiskit_swigf, only : qk_target_set_acquire_alignment
    class(Target), intent(inout) :: self
    integer, intent(in) :: acquire_alignment
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] set_acquire_alignment: uninitialised target"
    call check_rc(qk_target_set_acquire_alignment(self%ptr, int(acquire_alignment, c_int32_t)), &
                  "set_acquire_alignment")
  end subroutine tg_set_acquire_alignment

  subroutine tg_add_instruction(self, entry)
    use qiskit_swigf, only : qk_target_add_instruction
    class(Target), intent(inout) :: self
    type(InstructionProperties), intent(inout) :: entry
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] add_instruction: uninitialised target"
    if (.not. c_associated(entry%ptr)) &
        error stop "[qiskit_target] add_instruction: uninitialised entry"
    call check_rc(qk_target_add_instruction(self%ptr, entry%ptr), "add_instruction")
    entry%ptr = c_null_ptr
  end subroutine tg_add_instruction

  function tg_num_instructions(self) result(n)
    use qiskit_swigf, only : qk_target_num_instructions
    class(Target), intent(in) :: self
    integer(c_size_t) :: n
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] num_instructions: uninitialised target"
    n = qk_target_num_instructions(self%ptr)
  end function tg_num_instructions

  function tg_get_c_ptr(self) result(ptr)
    class(Target), intent(in) :: self
    type(c_ptr) :: ptr
    ptr = self%ptr
  end function tg_get_c_ptr

  subroutine tg_from_ptr(self, ptr)
    use qiskit_swigf, only : qk_target_free
    class(Target), intent(inout) :: self
    type(c_ptr), intent(in) :: ptr
    if (c_associated(self%ptr)) call qk_target_free(self%ptr)
    self%ptr = ptr
  end subroutine tg_from_ptr

  ! ============================================================================
  ! InstructionProperties
  ! ============================================================================

  subroutine ip_init_gate(self, gate_id)
    use qiskit_swigf, only : qk_target_entry_new, qk_target_entry_free
    class(InstructionProperties), intent(inout) :: self
    integer(c_int), intent(in) :: gate_id
    if (c_associated(self%ptr)) then
      call qk_target_entry_free(self%ptr)
      self%ptr = c_null_ptr
    end if
    self%ptr = qk_target_entry_new(gate_id)
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] init_gate: qk_target_entry_new returned null"
  end subroutine ip_init_gate

  subroutine ip_init_measure(self)
    use qiskit_swigf, only : qk_target_entry_new_measure, qk_target_entry_free
    class(InstructionProperties), intent(inout) :: self
    if (c_associated(self%ptr)) then
      call qk_target_entry_free(self%ptr)
      self%ptr = c_null_ptr
    end if
    self%ptr = qk_target_entry_new_measure()
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] init_measure: returned null"
  end subroutine ip_init_measure

  subroutine ip_init_reset(self)
    use qiskit_swigf, only : qk_target_entry_new_reset, qk_target_entry_free
    class(InstructionProperties), intent(inout) :: self
    if (c_associated(self%ptr)) then
      call qk_target_entry_free(self%ptr)
      self%ptr = c_null_ptr
    end if
    self%ptr = qk_target_entry_new_reset()
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] init_reset: returned null"
  end subroutine ip_init_reset

  !> @brief Add a qubit-configuration property to the entry.
  !> @param qubits 0-indexed qubit indices for this configuration
  !> @param duration operation duration in seconds (optional; negative = unspecified)
  !> @param error gate error rate (optional; negative = unspecified)
  subroutine ip_add_property(self, qubits, duration, error)
    use qiskit_swigf, only : qk_target_entry_add_property
    class(InstructionProperties), intent(inout) :: self
    integer, intent(in) :: qubits(:)
    real(c_double), intent(in), optional :: duration
    real(c_double), intent(in), optional :: error

    integer(QK_QUBIT_KIND), allocatable, target :: q_arr(:)
    real(c_double) :: dur, err
    integer :: i, n

    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] add_property: uninitialised entry"

    n = size(qubits)
    allocate(q_arr(n))
    do i = 1, n
      q_arr(i) = to_qubit(qubits(i))
    end do

    dur = -1.0_c_double
    if (present(duration)) dur = duration
    err = -1.0_c_double
    if (present(error)) err = error

    call check_rc(qk_target_entry_add_property(self%ptr, q_arr(1), to_qubit(n), dur, err), &
                  "add_property")
  end subroutine ip_add_property

  subroutine ip_set_name(self, name)
    use qiskit_swigf, only : qk_target_entry_set_name
    class(InstructionProperties), intent(inout) :: self
    character(len=*), intent(in) :: name
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_target] set_name: uninitialised entry"
    call check_rc(qk_target_entry_set_name(self%ptr, trim(name) // c_null_char), "set_name")
  end subroutine ip_set_name

  function ip_get_c_ptr(self) result(ptr)
    class(InstructionProperties), intent(in) :: self
    type(c_ptr) :: ptr
    ptr = self%ptr
  end function ip_get_c_ptr

  subroutine ip_destroy(self)
    use qiskit_swigf, only : qk_target_entry_free
    type(InstructionProperties), intent(inout) :: self
    if (c_associated(self%ptr)) then
      call qk_target_entry_free(self%ptr)
      self%ptr = c_null_ptr
    end if
  end subroutine ip_destroy

end module qiskit_target
