module qiskit_circuit
  use, intrinsic :: iso_c_binding, only : &
      c_ptr, c_null_ptr, c_associated, c_loc, &
      c_int,                                   &
      c_size_t, c_double
  use qiskit_c_api_types, only : QK_QUBIT_KIND
  use qiskit_c_api_circuit
  use qiskit_utils, only : check_rc, to_qubit

  implicit none
  private

  public :: QuantumCircuit

  type :: QuantumCircuit
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public :: init        => qc_init
    procedure, public :: num_qubits      => qc_num_qubits
    procedure, public :: num_clbits      => qc_num_clbits
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

  subroutine qc_init(self, num_qubits, num_clbits)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: num_qubits
    integer, intent(in), optional :: num_clbits

    integer :: nclbits

    if (c_associated(self%ptr)) then
      call qk_circuit_free(self%ptr)
      self%ptr = c_null_ptr
    end if

    nclbits = 0
    if (present(num_clbits)) nclbits = num_clbits

    self%ptr = qk_circuit_new( &
        to_qubit(num_qubits), &
        to_qubit(nclbits))

    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit] QuantumCircuit%init: allocation failed"
  end subroutine qc_init

  subroutine qc_destroy(self)
    type(QuantumCircuit), intent(inout) :: self
    if (c_associated(self%ptr)) then
      call qk_circuit_free(self%ptr)
      self%ptr = c_null_ptr
    end if
  end subroutine qc_destroy

  function qc_num_qubits(self) result(n)
    class(QuantumCircuit), intent(in) :: self
    integer :: n
    n = int(qk_circuit_num_qubits(self%ptr))
  end function qc_num_qubits

  function qc_num_clbits(self) result(n)
    class(QuantumCircuit), intent(in) :: self
    integer :: n
    n = int(qk_circuit_num_clbits(self%ptr))
  end function qc_num_clbits

  function qc_num_instructions(self) result(n)
    class(QuantumCircuit), intent(in) :: self
    integer(c_size_t) :: n
    n = qk_circuit_num_instructions(self%ptr)
  end function qc_num_instructions

  subroutine qc_h(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    rc = qk_circuit_gate(self%ptr, QkGate_H, c_loc(q), c_null_ptr)
    call check_rc(rc, "h")
  end subroutine qc_h

  subroutine qc_x(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    rc = qk_circuit_gate(self%ptr, QkGate_X, c_loc(q), c_null_ptr)
    call check_rc(rc, "x")
  end subroutine qc_x

  subroutine qc_y(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    rc = qk_circuit_gate(self%ptr, QkGate_Y, c_loc(q), c_null_ptr)
    call check_rc(rc, "y")
  end subroutine qc_y

  subroutine qc_z(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    rc = qk_circuit_gate(self%ptr, QkGate_Z, c_loc(q), c_null_ptr)
    call check_rc(rc, "z")
  end subroutine qc_z

  subroutine qc_s(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    rc = qk_circuit_gate(self%ptr, QkGate_S, c_loc(q), c_null_ptr)
    call check_rc(rc, "s")
  end subroutine qc_s

  subroutine qc_sdg(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    rc = qk_circuit_gate(self%ptr, QkGate_Sdg, c_loc(q), c_null_ptr)
    call check_rc(rc, "sdg")
  end subroutine qc_sdg

  subroutine qc_sx(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    rc = qk_circuit_gate(self%ptr, QkGate_SX, c_loc(q), c_null_ptr)
    call check_rc(rc, "sx")
  end subroutine qc_sx

  subroutine qc_t(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    rc = qk_circuit_gate(self%ptr, QkGate_T, c_loc(q), c_null_ptr)
    call check_rc(rc, "t")
  end subroutine qc_t

  subroutine qc_tdg(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    rc = qk_circuit_gate(self%ptr, QkGate_Tdg, c_loc(q), c_null_ptr)
    call check_rc(rc, "tdg")
  end subroutine qc_tdg

  subroutine qc_rx(self, theta, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: theta
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    real(c_double),      target :: p(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    p(1) = theta
    rc = qk_circuit_gate(self%ptr, QkGate_Rx, c_loc(q), c_loc(p))
    call check_rc(rc, "rx")
  end subroutine qc_rx

  subroutine qc_ry(self, theta, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: theta
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    real(c_double),      target :: p(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    p(1) = theta
    rc = qk_circuit_gate(self%ptr, QkGate_Ry, c_loc(q), c_loc(p))
    call check_rc(rc, "ry")
  end subroutine qc_ry

  subroutine qc_rz(self, lam, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: lam
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    real(c_double),      target :: p(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    p(1) = lam
    rc = qk_circuit_gate(self%ptr, QkGate_Rz, c_loc(q), c_loc(p))
    call check_rc(rc, "rz")
  end subroutine qc_rz

  subroutine qc_p(self, lam, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: lam
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    real(c_double),      target :: p(1)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    p(1) = lam
    rc = qk_circuit_gate(self%ptr, QkGate_Phase, c_loc(q), c_loc(p))
    call check_rc(rc, "p")
  end subroutine qc_p

  subroutine qc_u(self, theta, phi, lam, qubit)
    class(QuantumCircuit), intent(inout) :: self
    real(c_double), intent(in) :: theta, phi, lam
    integer, intent(in) :: qubit

    integer(QK_QUBIT_KIND), target :: q(1)
    real(c_double),      target :: p(3)
    integer(c_int) :: rc

    q(1) = to_qubit(qubit)
    p(1) = theta
    p(2) = phi
    p(3) = lam
    rc = qk_circuit_gate(self%ptr, QkGate_U, c_loc(q), c_loc(p))
    call check_rc(rc, "u")
  end subroutine qc_u

  subroutine qc_cx(self, ctrl, tgt)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: ctrl, tgt

    integer(QK_QUBIT_KIND), target :: q(2)
    integer(c_int) :: rc

    q(1) = to_qubit(ctrl)
    q(2) = to_qubit(tgt)
    rc = qk_circuit_gate(self%ptr, QkGate_CX, c_loc(q), c_null_ptr)
    call check_rc(rc, "cx")
  end subroutine qc_cx

  subroutine qc_cy(self, ctrl, tgt)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: ctrl, tgt

    integer(QK_QUBIT_KIND), target :: q(2)
    integer(c_int) :: rc

    q(1) = to_qubit(ctrl)
    q(2) = to_qubit(tgt)
    rc = qk_circuit_gate(self%ptr, QkGate_CY, c_loc(q), c_null_ptr)
    call check_rc(rc, "cy")
  end subroutine qc_cy

  subroutine qc_cz(self, ctrl, tgt)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: ctrl, tgt

    integer(QK_QUBIT_KIND), target :: q(2)
    integer(c_int) :: rc

    q(1) = to_qubit(ctrl)
    q(2) = to_qubit(tgt)
    rc = qk_circuit_gate(self%ptr, QkGate_CZ, c_loc(q), c_null_ptr)
    call check_rc(rc, "cz")
  end subroutine qc_cz

  subroutine qc_swap(self, q0, q1)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: q0, q1

    integer(QK_QUBIT_KIND), target :: q(2)
    integer(c_int) :: rc

    q(1) = to_qubit(q0)
    q(2) = to_qubit(q1)
    rc = qk_circuit_gate(self%ptr, QkGate_Swap, c_loc(q), c_null_ptr)
    call check_rc(rc, "swap")
  end subroutine qc_swap

  subroutine qc_ecr(self, ctrl, tgt)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: ctrl, tgt

    integer(QK_QUBIT_KIND), target :: q(2)
    integer(c_int) :: rc

    q(1) = to_qubit(ctrl)
    q(2) = to_qubit(tgt)
    rc = qk_circuit_gate(self%ptr, QkGate_ECR, c_loc(q), c_null_ptr)
    call check_rc(rc, "ecr")
  end subroutine qc_ecr

  subroutine qc_measure(self, qubit, clbit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit, clbit

    integer(c_int) :: rc
    rc = qk_circuit_measure(self%ptr, to_qubit(qubit), to_qubit(clbit))
    call check_rc(rc, "measure")
  end subroutine qc_measure

  subroutine qc_measure_all(self)
    class(QuantumCircuit), intent(inout) :: self

    integer :: i, nq, nc
    integer(c_int) :: rc

    nq = self%num_qubits()
    nc = self%num_clbits()

    if (nc < nq) &
        error stop "[qiskit] measure_all: num_clbits < num_qubits"

    do i = 0, nq - 1
      rc = qk_circuit_measure(self%ptr, to_qubit(i), to_qubit(i))
      call check_rc(rc, "measure_all")
    end do
  end subroutine qc_measure_all

  subroutine qc_reset(self, qubit)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubit

    integer(c_int) :: rc
    rc = qk_circuit_reset(self%ptr, to_qubit(qubit))
    call check_rc(rc, "reset")
  end subroutine qc_reset

  subroutine qc_barrier(self, qubits)
    class(QuantumCircuit), intent(inout) :: self
    integer, intent(in) :: qubits(:)

    integer(QK_QUBIT_KIND), allocatable, target :: q(:)
    integer(c_int) :: rc
    integer :: i, n

    n = size(qubits)
    if (n == 0) return

    allocate(q(n))
    do i = 1, n
      q(i) = to_qubit(qubits(i))
    end do

    rc = qk_circuit_barrier(self%ptr, c_loc(q), int(n, QK_QUBIT_KIND))
    call check_rc(rc, "barrier")
    deallocate(q)
  end subroutine qc_barrier

  subroutine qc_barrier_all(self)
    class(QuantumCircuit), intent(inout) :: self

    integer(QK_QUBIT_KIND), allocatable, target :: q(:)
    integer(c_int) :: rc
    integer :: i, nq

    nq = self%num_qubits()
    allocate(q(nq))
    do i = 1, nq
      q(i) = to_qubit(i - 1)
    end do

    rc = qk_circuit_barrier(self%ptr, c_loc(q), int(nq, QK_QUBIT_KIND))
    call check_rc(rc, "barrier_all")
    deallocate(q)
  end subroutine qc_barrier_all

end module qiskit_circuit
