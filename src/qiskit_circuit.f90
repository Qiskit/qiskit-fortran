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

!> @brief Quantum circuit representation module
!>
!> Provides the QuantumCircuit type for building and manipulating quantum circuits.
module qiskit_circuit
  use, intrinsic :: iso_c_binding, only : &
      c_ptr, c_null_ptr, c_associated, c_loc, c_int, c_double, c_size_t
  use qiskit_c_api_types,   only : QK_QUBIT_KIND
  use qiskit_c_api_circuit
  use qiskit_utils,         only : check_rc, to_qubit

  implicit none (type, external)
  private

  public :: QuantumCircuit

  !> @brief Quantum circuit type
  !>
  !> Encapsulates a quantum circuit with qubits, classical bits, and gate operations.
  !> Provides methods for applying gates, measurements, and other quantum operations.
  !> @note All qubit and classical bit indices are 0-indexed, unlike standard Fortran arrays.
  type :: QuantumCircuit
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public :: init             => qc_init
    procedure, public :: num_qubits       => qc_num_qubits
    procedure, public :: num_clbits       => qc_num_clbits
    procedure, public :: num_instructions => qc_num_instructions
    procedure, public :: h    => qc_h
    procedure, public :: x    => qc_x
    procedure, public :: y    => qc_y
    procedure, public :: z    => qc_z
    procedure, public :: s    => qc_s
    procedure, public :: sdg  => qc_sdg
    procedure, public :: sx   => qc_sx
    procedure, public :: t    => qc_t
    procedure, public :: tdg  => qc_tdg
    procedure, public :: rx   => qc_rx
    procedure, public :: ry   => qc_ry
    procedure, public :: rz   => qc_rz
    procedure, public :: p    => qc_p
    procedure, public :: u    => qc_u
    procedure, public :: cx   => qc_cx
    procedure, public :: cy   => qc_cy
    procedure, public :: cz   => qc_cz
    procedure, public :: swap => qc_swap
    procedure, public :: ecr  => qc_ecr
    procedure, public :: measure     => qc_measure
    procedure, public :: measure_all => qc_measure_all
    procedure, public :: reset       => qc_reset
    procedure, public :: barrier     => qc_barrier
    procedure, public :: barrier_all => qc_barrier_all
    final :: qc_destroy
  end type QuantumCircuit

contains

  ! Internal gate dispatch - converts Fortran arrays to C ABI
  subroutine dispatch_gate(ptr, gate_id, qubits, params)
    type(c_ptr),                intent(in)           :: ptr
    integer(c_int),             intent(in)           :: gate_id
    integer(QK_QUBIT_KIND), target, intent(in)       :: qubits(:)
    real(c_double),         target, intent(in), optional :: params(:)

    integer(c_int) :: rc
    type(c_ptr)    :: qubit_ptr, param_ptr

    if (.not. c_associated(ptr)) &
        error stop "[qiskit_circuit] dispatch_gate: uninitialised circuit"

    ! Direct c_loc on Fortran arrays - no intermediate allocations
    qubit_ptr = c_loc(qubits(1))
    
    if (present(params)) then
      param_ptr = c_loc(params(1))
    else
      param_ptr = c_null_ptr
    end if

    rc = qk_circuit_gate(ptr, gate_id, qubit_ptr, param_ptr)

    call check_rc(rc, "dispatch_gate")
  end subroutine dispatch_gate

  !> @brief Initialize quantum circuit
  !> @param num_qubits number of qubits
  !> @param num_clbits optional number of classical bits (default: 0)
  !> @note Calling init on an already-initialized circuit will free the existing circuit first
  subroutine qc_init(self, num_qubits, num_clbits)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in)           :: num_qubits
    integer, intent(in), optional :: num_clbits
    integer :: nc

    if (c_associated(self%ptr)) then
      call qk_circuit_free(self%ptr)
      self%ptr = c_null_ptr
    end if

    nc = 0
    if (present(num_clbits)) nc = num_clbits

    self%ptr = qk_circuit_new(to_qubit(num_qubits), to_qubit(nc))

    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_circuit] init: qk_circuit_new returned null"
  end subroutine qc_init

  !> @brief Finalizer - automatically called when circuit goes out of scope
  !> @note Uses Fortran 2003 `final` semantics; pre-2003 code must call manually
  subroutine qc_destroy(self)
    type(QuantumCircuit), intent(inout) :: self
    if (c_associated(self%ptr)) then
      call qk_circuit_free(self%ptr)
      self%ptr = c_null_ptr
    end if
  end subroutine qc_destroy

  !> @brief Get number of qubits in circuit
  function qc_num_qubits(self) result(n)
    class(QuantumCircuit), intent(in) :: self
    integer :: n
    n = int(qk_circuit_num_qubits(self%ptr))
  end function qc_num_qubits

  !> @brief Get number of classical bits in circuit
  function qc_num_clbits(self) result(n)
    class(QuantumCircuit), intent(in) :: self
    integer :: n
    n = int(qk_circuit_num_clbits(self%ptr))
  end function qc_num_clbits

  !> @brief Get total number of instructions in circuit
  function qc_num_instructions(self) result(n)
    class(QuantumCircuit), intent(in) :: self
    integer(c_size_t) :: n
    n = qk_circuit_num_instructions(self%ptr)
  end function qc_num_instructions

  !> @brief Apply Hadamard gate
  !> @param qubit target qubit index
  subroutine qc_h(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    call dispatch_gate(self%ptr, QkGate_H, q_arr)
  end subroutine qc_h

  !> @brief Apply Pauli-X gate
  !> @param qubit target qubit index
  subroutine qc_x(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    call dispatch_gate(self%ptr, QkGate_X, q_arr)
  end subroutine qc_x

  !> @brief Apply Pauli-Y gate
  !> @param qubit target qubit index
  subroutine qc_y(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    call dispatch_gate(self%ptr, QkGate_Y, q_arr)
  end subroutine qc_y

  !> @brief Apply Pauli-Z gate
  !> @param qubit target qubit index
  subroutine qc_z(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    call dispatch_gate(self%ptr, QkGate_Z, q_arr)
  end subroutine qc_z

  !> @brief Apply S gate
  !> @param qubit target qubit index
  subroutine qc_s(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    call dispatch_gate(self%ptr, QkGate_S, q_arr)
  end subroutine qc_s

  !> @brief Apply S-dagger gate
  !> @param qubit target qubit index
  subroutine qc_sdg(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    call dispatch_gate(self%ptr, QkGate_Sdg, q_arr)
  end subroutine qc_sdg

  !> @brief Apply sqrt(X) gate
  !> @param qubit target qubit index
  subroutine qc_sx(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    call dispatch_gate(self%ptr, QkGate_SX, q_arr)
  end subroutine qc_sx

  !> @brief Apply T gate
  !> @param qubit target qubit index
  subroutine qc_t(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    call dispatch_gate(self%ptr, QkGate_T, q_arr)
  end subroutine qc_t

  !> @brief Apply T-dagger gate
  !> @param qubit target qubit index
  subroutine qc_tdg(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    call dispatch_gate(self%ptr, QkGate_Tdg, q_arr)
  end subroutine qc_tdg

  !> @brief Apply rotation around X-axis
  !> @param theta rotation angle in radians
  !> @param qubit target qubit index
  subroutine qc_rx(self, theta, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: theta
    integer,        intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    real(c_double)         :: p_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    p_arr(1) = theta
    call dispatch_gate(self%ptr, QkGate_Rx, q_arr, p_arr)
  end subroutine qc_rx

  !> @brief Apply rotation around Y-axis
  !> @param theta rotation angle in radians
  !> @param qubit target qubit index
  subroutine qc_ry(self, theta, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: theta
    integer,        intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    real(c_double)         :: p_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    p_arr(1) = theta
    call dispatch_gate(self%ptr, QkGate_Ry, q_arr, p_arr)
  end subroutine qc_ry

  !> @brief Apply rotation around Z-axis
  !> @param lam rotation angle in radians (named lam to avoid Fortran keyword lambda)
  !> @param qubit target qubit index
  subroutine qc_rz(self, lam, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: lam
    integer,        intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    real(c_double)         :: p_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    p_arr(1) = lam
    call dispatch_gate(self%ptr, QkGate_Rz, q_arr, p_arr)
  end subroutine qc_rz

  !> @brief Apply phase gate
  !> @param lam phase angle in radians (named lam to avoid Fortran keyword lambda)
  !> @param qubit target qubit index
  subroutine qc_p(self, lam, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: lam
    integer,        intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    real(c_double)         :: p_arr(1)
    
    q_arr(1) = to_qubit(qubit)
    p_arr(1) = lam
    call dispatch_gate(self%ptr, QkGate_Phase, q_arr, p_arr)
  end subroutine qc_p

  !> @brief Apply general single-qubit unitary gate U(θ,φ,λ)
  !> @param theta rotation angle around Y-axis
  !> @param phi rotation angle around Z-axis (first)
  !> @param lam rotation angle around Z-axis (second)
  !> @param qubit target qubit index
  !> @note U(θ,φ,λ) = Rz(φ)Ry(θ)Rz(λ); the three angles are not interchangeable
  subroutine qc_u(self, theta, phi, lam, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: theta, phi, lam
    integer,        intent(in) :: qubit
    integer(QK_QUBIT_KIND) :: q_arr(1)
    real(c_double)         :: p_arr(3)
    
    q_arr(1) = to_qubit(qubit)
    p_arr(1) = theta
    p_arr(2) = phi
    p_arr(3) = lam
    call dispatch_gate(self%ptr, QkGate_U, q_arr, p_arr)
  end subroutine qc_u

  !> @brief Apply controlled-X (CNOT) gate
  !> @param ctrl control qubit index
  !> @param tgt target qubit index
  subroutine qc_cx(self, ctrl, tgt)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: ctrl, tgt
    integer(QK_QUBIT_KIND) :: q_arr(2)
    
    q_arr(1) = to_qubit(ctrl)
    q_arr(2) = to_qubit(tgt)
    call dispatch_gate(self%ptr, QkGate_CX, q_arr)
  end subroutine qc_cx

  !> @brief Apply controlled-Y gate
  !> @param ctrl control qubit index
  !> @param tgt target qubit index
  subroutine qc_cy(self, ctrl, tgt)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: ctrl, tgt
    integer(QK_QUBIT_KIND) :: q_arr(2)
    
    q_arr(1) = to_qubit(ctrl)
    q_arr(2) = to_qubit(tgt)
    call dispatch_gate(self%ptr, QkGate_CY, q_arr)
  end subroutine qc_cy

  !> @brief Apply controlled-Z gate
  !> @param ctrl control qubit index
  !> @param tgt target qubit index
  subroutine qc_cz(self, ctrl, tgt)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: ctrl, tgt
    integer(QK_QUBIT_KIND) :: q_arr(2)
    
    q_arr(1) = to_qubit(ctrl)
    q_arr(2) = to_qubit(tgt)
    call dispatch_gate(self%ptr, QkGate_CZ, q_arr)
  end subroutine qc_cz

  !> @brief Apply SWAP gate
  !> @param q0 first qubit index
  !> @param q1 second qubit index
  subroutine qc_swap(self, q0, q1)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: q0, q1
    integer(QK_QUBIT_KIND) :: q_arr(2)
    
    q_arr(1) = to_qubit(q0)
    q_arr(2) = to_qubit(q1)
    call dispatch_gate(self%ptr, QkGate_Swap, q_arr)
  end subroutine qc_swap

  !> @brief Apply echoed cross-resonance gate
  !> @param ctrl control qubit index
  !> @param tgt target qubit index
  subroutine qc_ecr(self, ctrl, tgt)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: ctrl, tgt
    integer(QK_QUBIT_KIND) :: q_arr(2)
    
    q_arr(1) = to_qubit(ctrl)
    q_arr(2) = to_qubit(tgt)
    call dispatch_gate(self%ptr, QkGate_ECR, q_arr)
  end subroutine qc_ecr

  !> @brief Measure qubit into classical bit
  !> @param qubit qubit index to measure
  !> @param clbit classical bit index to store result
  subroutine qc_measure(self, qubit, clbit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit, clbit
    call check_rc( &
        qk_circuit_measure(self%ptr, to_qubit(qubit), to_qubit(clbit)), "measure")
  end subroutine qc_measure

  !> @brief Measure all qubits into corresponding classical bits
  !> @note Requires num_clbits >= num_qubits; error stops otherwise
  subroutine qc_measure_all(self)
    class(QuantumCircuit), intent(inout) :: self
    integer :: i, nq, nc
    nq = int(self%num_qubits())
    nc = int(self%num_clbits())
    if (nc < nq) &
        error stop "[qiskit_circuit] measure_all: num_clbits < num_qubits"
    do i = 0, nq - 1
      call check_rc( &
          qk_circuit_measure(self%ptr, to_qubit(i), to_qubit(i)), "measure_all")
    end do
  end subroutine qc_measure_all

  !> @brief Reset qubit to |0⟩ state
  !> @param qubit qubit index to reset
  subroutine qc_reset(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit
    call check_rc(qk_circuit_reset(self%ptr, to_qubit(qubit)), "reset")
  end subroutine qc_reset

  !> @brief Apply barrier on specified qubits
  !> @param qubits array of qubit indices
  !> @note Silently returns if qubits array is empty
  subroutine qc_barrier(self, qubits)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubits(:)

    integer(QK_QUBIT_KIND), allocatable, target :: q_arr(:)
    integer          :: i, n
    integer(c_int)   :: rc

    n = size(qubits)
    if (n == 0) return

    allocate(q_arr(n))
    do i = 1, n
      q_arr(i) = to_qubit(qubits(i))
    end do

    rc = qk_circuit_barrier(self%ptr, c_loc(q_arr(1)), to_qubit(n))
    call check_rc(rc, "barrier")
  end subroutine qc_barrier

  !> @brief Apply barrier on all qubits in circuit
  subroutine qc_barrier_all(self)
    class(QuantumCircuit), intent(inout) :: self

    integer(QK_QUBIT_KIND), allocatable, target :: q_arr(:)
    integer          :: i, nq
    integer(c_int)   :: rc

    nq = int(self%num_qubits())
    allocate(q_arr(nq))
    do i = 1, nq
      q_arr(i) = to_qubit(i - 1)
    end do

    rc = qk_circuit_barrier(self%ptr, c_loc(q_arr(1)), to_qubit(nq))
    call check_rc(rc, "barrier_all")
  end subroutine qc_barrier_all

end module qiskit_circuit
