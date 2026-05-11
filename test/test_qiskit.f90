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

! =============================================================================
! test_qiskit.f90  —  Test suite for the qiskit Fortran binding
!
! A self-contained test harness (no external framework) that validates every
! public procedure in qiskit.f90 and every constant in qiskit_c_api.f90.
!
! Each test_* subroutine:
!   1. Builds a circuit using the high-level API.
!   2. Asserts expected properties (instruction count, qubit count, etc.).
!   3. Reports PASS / FAIL and accumulates a count.
!
! The FINAL destructor on QuantumCircuit is tested implicitly: any circuit
! created inside a subroutine is freed automatically when that subroutine
! returns.
! =============================================================================

program test_qiskit
  use qiskit
  use qiskit_c_api, only : QkGate_H, QkGate_CX, qk_gate_num_qubits, qk_gate_num_params
  use qiskit_c_api_circuit  ! Import all gate constants for verification
  use, intrinsic :: iso_c_binding, only : c_double, c_int32_t, c_int, c_size_t
  implicit none (type, external)

  ! test harness state
  integer :: n_pass = 0
  integer :: n_fail = 0

  ! run all tests
  call test_gate_enum_constants()
  call test_construction()
  call test_bell_state()
  call test_ghz_state()
  call test_single_qubit_clifford_gates()
  call test_rotation_gates()
  call test_u_gate()
  call test_two_qubit_gates()
  call test_measure_and_reset()
  call test_measure_all()
  call test_barrier_explicit()
  call test_barrier_all()
  call test_reinitialisation()
  call test_gate_metadata()
  call test_large_circuit()

  ! comprehensive tests
  call test_optional_clbits_regression()
  call test_num_instructions_type()

  ! contract and edge-case tests
  call test_measure_all_clbit_boundary()
  call test_uninitialised_circuit_guards()

  ! summary
  write(*, '(/, a)') "========================================"
  write(*, '(a, i0)') "  PASS : ", n_pass
  write(*, '(a, i0)') "  FAIL : ", n_fail
  write(*, '(a)')    "========================================"

  if (n_fail > 0) error stop "One or more tests failed."

contains

  ! Harness helpers

  subroutine assert_eq_int(got, expected, label)
    integer, intent(in) :: got, expected
    character(len=*), intent(in) :: label
    if (got == expected) then
      write(*, '("  [PASS] ", a)') label
      n_pass = n_pass + 1
    else
      write(*, '("  [FAIL] ", a, " — expected ", i0, " got ", i0)') &
            label, expected, got
      n_fail = n_fail + 1
    end if
  end subroutine assert_eq_int

  subroutine assert_eq_int_size_t(got, expected, label)
    integer(c_size_t), intent(in) :: got
    integer, intent(in) :: expected
    character(len=*), intent(in) :: label
    if (got == int(expected, c_size_t)) then
      write(*, '("  [PASS] ", a)') label
      n_pass = n_pass + 1
    else
      write(*, '("  [FAIL] ", a, " — expected ", i0, " got ", i0)') &
            label, expected, got
      n_fail = n_fail + 1
    end if
  end subroutine assert_eq_int_size_t

  subroutine assert_true(cond, label)
    logical, intent(in) :: cond
    character(len=*), intent(in) :: label
    if (cond) then
      write(*, '("  [PASS] ", a)') label
      n_pass = n_pass + 1
    else
      write(*, '("  [FAIL] ", a)') label
      n_fail = n_fail + 1
    end if
  end subroutine assert_true

  subroutine section(name)
    character(len=*), intent(in) :: name
    write(*, '(/, "--- ", a, " ---")') name
  end subroutine section

  ! Tests

  !> Verify all gate enum constants are defined and have expected values.
  !> This ensures the enum values match the Qiskit C API header.
  subroutine test_gate_enum_constants()
    call section("Gate enum constants verification")

    ! Single-qubit gates
    call assert_eq_int(int(QkGate_GlobalPhase), 0,  "QkGate_GlobalPhase == 0")
    call assert_eq_int(int(QkGate_H),           1,  "QkGate_H == 1")
    call assert_eq_int(int(QkGate_I),           2,  "QkGate_I == 2")
    call assert_eq_int(int(QkGate_X),           3,  "QkGate_X == 3")
    call assert_eq_int(int(QkGate_Y),           4,  "QkGate_Y == 4")
    call assert_eq_int(int(QkGate_Z),           5,  "QkGate_Z == 5")
    call assert_eq_int(int(QkGate_Phase),       6,  "QkGate_Phase == 6")
    call assert_eq_int(int(QkGate_R),           7,  "QkGate_R == 7")
    call assert_eq_int(int(QkGate_Rx),          8,  "QkGate_Rx == 8")
    call assert_eq_int(int(QkGate_Ry),          9,  "QkGate_Ry == 9")
    call assert_eq_int(int(QkGate_Rz),          10, "QkGate_Rz == 10")
    call assert_eq_int(int(QkGate_S),           11, "QkGate_S == 11")
    call assert_eq_int(int(QkGate_Sdg),         12, "QkGate_Sdg == 12")
    call assert_eq_int(int(QkGate_SX),          13, "QkGate_SX == 13")
    call assert_eq_int(int(QkGate_SXdg),        14, "QkGate_SXdg == 14")
    call assert_eq_int(int(QkGate_T),           15, "QkGate_T == 15")
    call assert_eq_int(int(QkGate_Tdg),         16, "QkGate_Tdg == 16")
    call assert_eq_int(int(QkGate_U),           17, "QkGate_U == 17")
    call assert_eq_int(int(QkGate_U1),          18, "QkGate_U1 == 18")
    call assert_eq_int(int(QkGate_U2),          19, "QkGate_U2 == 19")
    call assert_eq_int(int(QkGate_U3),          20, "QkGate_U3 == 20")

    ! Two-qubit gates
    call assert_eq_int(int(QkGate_CH),          21, "QkGate_CH == 21")
    call assert_eq_int(int(QkGate_CX),          22, "QkGate_CX == 22")
    call assert_eq_int(int(QkGate_CY),          23, "QkGate_CY == 23")
    call assert_eq_int(int(QkGate_CZ),          24, "QkGate_CZ == 24")
    call assert_eq_int(int(QkGate_DCX),         25, "QkGate_DCX == 25")
    call assert_eq_int(int(QkGate_ECR),         26, "QkGate_ECR == 26")
    call assert_eq_int(int(QkGate_Swap),        27, "QkGate_Swap == 27")
    call assert_eq_int(int(QkGate_ISwap),       28, "QkGate_ISwap == 28")

    ! Three-qubit gates
    call assert_eq_int(int(QkGate_CCX),         45, "QkGate_CCX == 45")
  end subroutine test_gate_enum_constants

  !> A freshly initialised circuit has the correct qubit/clbit counts and
  !> zero instructions.
  subroutine test_construction()
    type(QuantumCircuit) :: qc
    call section("Construction")

    ! 5 qubits, 5 classical bits
    call qc%init(num_qubits=5, num_clbits=5)
    call assert_eq_int(qc%num_qubits(),      5, "num_qubits == 5")
    call assert_eq_int(qc%num_clbits(),      5, "num_clbits == 5")
    call assert_eq_int_size_t(qc%num_instructions(), 0, "empty circuit has 0 instructions")

    ! 3 qubits, no classical bits (optional argument)
    call qc%init(num_qubits=3)
    call assert_eq_int(qc%num_qubits(),      3, "re-init num_qubits == 3")
    call assert_eq_int(qc%num_clbits(),      0, "re-init num_clbits defaults to 0")
    call assert_eq_int_size_t(qc%num_instructions(), 0, "re-init empty")
  end subroutine test_construction

  !> Bell state: H(0) + CX(0,1) + measure_all -> 4 instructions.
  subroutine test_bell_state()
    type(QuantumCircuit) :: qc
    call section("Bell state")

    call qc%init(num_qubits=2, num_clbits=2)
    call qc%h(0)
    call assert_eq_int_size_t(qc%num_instructions(), 1, "after H: 1 instruction")

    call qc%cx(0, 1)
    call assert_eq_int_size_t(qc%num_instructions(), 2, "after CX: 2 instructions")

    call qc%measure(0, 0)
    call qc%measure(1, 1)
    call assert_eq_int_size_t(qc%num_instructions(), 4, "after measures: 4 instructions")
  end subroutine test_bell_state

  !> GHZ state: H(0) + CX(0,1) + CX(0,2) = 3 instructions.
  subroutine test_ghz_state()
    type(QuantumCircuit) :: qc
    call section("GHZ state")

    call qc%init(num_qubits=3)
    call qc%h(0)
    call qc%cx(0, 1)
    call qc%cx(0, 2)
    call assert_eq_int_size_t(qc%num_instructions(), 3, "GHZ has 3 instructions")
    call assert_eq_int(qc%num_qubits(),       3, "GHZ has 3 qubits")
    call assert_eq_int(qc%num_clbits(),       0, "GHZ has 0 clbits")
  end subroutine test_ghz_state

  !> Every zero-parameter single-qubit Clifford gate can be appended
  !> without error, and each adds exactly one instruction.
  subroutine test_single_qubit_clifford_gates()
    type(QuantumCircuit) :: qc
    integer :: expected
    call section("Single-qubit Clifford gates")

    call qc%init(num_qubits=1)
    expected = 0

    call qc%x(0);   expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "X appended")

    call qc%y(0);   expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "Y appended")

    call qc%z(0);   expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "Z appended")

    call qc%h(0);   expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "H appended")

    call qc%s(0);   expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "S appended")

    call qc%sdg(0); expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "Sdg appended")

    call qc%sx(0);  expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "SX appended")

    call qc%t(0);   expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "T appended")

    call qc%tdg(0); expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "Tdg appended")
  end subroutine test_single_qubit_clifford_gates

  !> Parameterised rotation gates Rx, Ry, Rz, P each add one instruction.
  subroutine test_rotation_gates()
    type(QuantumCircuit) :: qc
    real(c_double), parameter :: pi = 3.14159265358979323846_c_double
    call section("Rotation gates")

    call qc%init(num_qubits=1)

    call qc%rx(pi / 2.0_c_double, 0)
    call assert_eq_int_size_t(qc%num_instructions(), 1, "Rx(π/2) appended")

    call qc%ry(pi / 4.0_c_double, 0)
    call assert_eq_int_size_t(qc%num_instructions(), 2, "Ry(π/4) appended")

    call qc%rz(pi,                0)
    call assert_eq_int_size_t(qc%num_instructions(), 3, "Rz(π) appended")

    call qc%p(pi / 8.0_c_double,  0)
    call assert_eq_int_size_t(qc%num_instructions(), 4, "P(π/8) appended")
  end subroutine test_rotation_gates

  !> U gate covers all three parameters in one call.
  subroutine test_u_gate()
    type(QuantumCircuit) :: qc
    real(c_double), parameter :: pi = 3.14159265358979323846_c_double
    call section("U gate (3 parameters)")

    call qc%init(num_qubits=1)
    call qc%u(theta=pi/2.0_c_double, phi=0.0_c_double, lam=pi, qubit=0)
    call assert_eq_int_size_t(qc%num_instructions(), 1, "U(θ,φ,λ) appended")
  end subroutine test_u_gate

  !> CX, CY, CZ, SWAP and ECR each add one instruction.
  subroutine test_two_qubit_gates()
    type(QuantumCircuit) :: qc
    integer :: expected
    call section("Two-qubit gates")

    call qc%init(num_qubits=2)
    expected = 0

    call qc%cx(0, 1);   expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "CX appended")

    call qc%cy(0, 1);   expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "CY appended")

    call qc%cz(0, 1);   expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "CZ appended")

    call qc%swap(0, 1); expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "SWAP appended")

    call qc%ecr(0, 1);  expected = expected + 1
    call assert_eq_int_size_t(qc%num_instructions(), expected, "ECR appended")
  end subroutine test_two_qubit_gates

  !> Measure and Reset add exactly one instruction each.
  subroutine test_measure_and_reset()
    type(QuantumCircuit) :: qc
    call section("Measure and Reset")

    call qc%init(num_qubits=2, num_clbits=2)
    call qc%measure(0, 0)
    call assert_eq_int_size_t(qc%num_instructions(), 1, "measure(0,0) appended")

    call qc%measure(1, 1)
    call assert_eq_int_size_t(qc%num_instructions(), 2, "measure(1,1) appended")

    call qc%reset(0)
    call assert_eq_int_size_t(qc%num_instructions(), 3, "reset(0) appended")
  end subroutine test_measure_and_reset

  !> measure_all adds exactly num_qubits instructions.
  subroutine test_measure_all()
    type(QuantumCircuit) :: qc
    integer, parameter :: nq = 4
    call section("measure_all")

    call qc%init(num_qubits=nq, num_clbits=nq)
    call qc%measure_all()
    call assert_eq_int_size_t(qc%num_instructions(), nq, &
        "measure_all adds 4 instructions for 4-qubit circuit")
  end subroutine test_measure_all

  !> A barrier over an explicit qubit subset counts as one instruction.
  subroutine test_barrier_explicit()
    type(QuantumCircuit) :: qc
    integer :: subset(2)
    call section("Barrier (explicit qubit list)")

    call qc%init(num_qubits=4)
    call qc%h(0)
    call qc%h(1)

    subset = [0, 1]
    call qc%barrier(subset)
    call assert_eq_int_size_t(qc%num_instructions(), 3, &
        "barrier over [0,1] is one instruction")

    call qc%cx(0, 2)
    call assert_eq_int_size_t(qc%num_instructions(), 4, "CX after barrier appended")
  end subroutine test_barrier_explicit

  !> barrier_all produces one barrier instruction spanning all qubits.
  subroutine test_barrier_all()
    type(QuantumCircuit) :: qc
    call section("barrier_all")

    call qc%init(num_qubits=5)
    call qc%barrier_all()
    call assert_eq_int_size_t(qc%num_instructions(), 1, "barrier_all: 1 instruction")
  end subroutine test_barrier_all

  !> Calling init a second time (re-initialisation) resets the circuit.
  subroutine test_reinitialisation()
    type(QuantumCircuit) :: qc
    call section("Re-initialisation")

    call qc%init(num_qubits=5, num_clbits=5)
    call qc%h(0)
    call qc%cx(0, 1)
    call assert_eq_int_size_t(qc%num_instructions(), 2, "before re-init: 2 instructions")

    ! Re-initialise — this must free the old circuit and create a fresh one.
    call qc%init(num_qubits=3)
    call assert_eq_int(qc%num_qubits(),      3, "after re-init: 3 qubits")
    call assert_eq_int(qc%num_clbits(),      0, "after re-init: 0 clbits")
    call assert_eq_int_size_t(qc%num_instructions(), 0, "after re-init: 0 instructions")
  end subroutine test_reinitialisation

  !> Verify the gate metadata API in the FFI layer: H has 1 qubit, 0 params;
  !> CX has 2 qubits, 0 params.
  subroutine test_gate_metadata()
    integer(c_int32_t) :: nq, np
    call section("Gate metadata (qk_gate_num_qubits / qk_gate_num_params)")

    nq = qk_gate_num_qubits(QkGate_H)
    np = qk_gate_num_params(QkGate_H)
    call assert_eq_int(int(nq), 1, "H: num_qubits == 1")
    call assert_eq_int(int(np), 0, "H: num_params == 0")

    nq = qk_gate_num_qubits(QkGate_CX)
    np = qk_gate_num_params(QkGate_CX)
    call assert_eq_int(int(nq), 2, "CX: num_qubits == 2")
    call assert_eq_int(int(np), 0, "CX: num_params == 0")
  end subroutine test_gate_metadata

  !> A 100-qubit circuit with alternating H and CX layers — smoke-tests
  !> performance-sensitive code paths without asserting circuit semantics.
  subroutine test_large_circuit()
    type(QuantumCircuit) :: qc
    integer :: i, expected_instr
    integer, parameter :: nq = 100
    call section("Large circuit (100 qubits)")

    call qc%init(num_qubits=nq, num_clbits=nq)

    ! Layer 1: H on all qubits
    do i = 0, nq - 1
      call qc%h(i)
    end do
    call assert_eq_int_size_t(qc%num_instructions(), nq, &
        "100×H: 100 instructions")

    ! Layer 2: CX on even–odd pairs
    do i = 0, nq - 2, 2
      call qc%cx(i, i + 1)
    end do
    expected_instr = nq + nq / 2     ! 100 H + 50 CX
    call assert_eq_int_size_t(qc%num_instructions(), expected_instr, &
        "100×H + 50×CX: 150 instructions")

    ! Layer 3: Rz on all qubits
    do i = 0, nq - 1
      call qc%rz(0.1_c_double * real(i, c_double), i)
    end do
    expected_instr = expected_instr + nq    ! + 100 Rz
    call assert_eq_int_size_t(qc%num_instructions(), expected_instr, &
        "after 100×Rz: 250 instructions")

    ! measure_all
    call qc%measure_all()
    expected_instr = expected_instr + nq
    call assert_eq_int_size_t(qc%num_instructions(), expected_instr, &
        "after measure_all: 350 instructions")
  end subroutine test_large_circuit

  !> Regression test for optional num_clbits SEGV bug.
  !> Tests the exact sequence that triggered the merge-time crash.
  subroutine test_optional_clbits_regression()
    type(QuantumCircuit) :: qc
    call section("Optional num_clbits regression (merge-SEGV)")

    ! First init with clbits
    call qc%init(num_qubits=2, num_clbits=2)
    call assert_eq_int(qc%num_clbits(), 2, "init with clbits: 2")

    ! Second init WITHOUT clbits — this is what triggered the SEGV
    call qc%init(num_qubits=3)
    call assert_eq_int(qc%num_clbits(), 0, "re-init without clbits: 0")

    ! Third init WITHOUT clbits on a fresh variable
    call qc%init(num_qubits=1)
    call assert_eq_int(qc%num_clbits(), 0, "fresh init without clbits: 0")
  end subroutine test_optional_clbits_regression

  !> Test that num_instructions returns c_size_t without truncation.
  !> Verifies type correctness and that large values aren't silently truncated.
  subroutine test_num_instructions_type()
    use, intrinsic :: iso_c_binding, only : c_size_t
    type(QuantumCircuit) :: qc
    integer(c_size_t) :: n
    call section("num_instructions returns c_size_t (no truncation)")

    call qc%init(4, 0)
    call qc%h(0)
    call qc%h(1)
    call qc%h(2)
    call qc%h(3)

    n = qc%num_instructions()
    call assert_true(kind(n) == kind(1_c_size_t), "num_instructions kind is c_size_t")
    call assert_eq_int_size_t(n, 4, "4 H gates == 4 instructions")
  end subroutine test_num_instructions_type

  !> Test measure_all boundary conditions: nc == nq (exact match) and
  !> nc > nq (extra clbits) must both succeed. nc < nq triggers error stop.
  subroutine test_measure_all_clbit_boundary()
    type(QuantumCircuit) :: qc

    call section("measure_all clbit boundary")

    ! Exact match: nc == nq — must succeed
    call qc%init(num_qubits=3, num_clbits=3)
    call qc%measure_all()
    call assert_eq_int_size_t(qc%num_instructions(), 3, &
        "measure_all with nc==nq succeeds (3 instructions)")

    ! nc > nq — must also succeed (extra clbits are fine)
    call qc%init(num_qubits=2, num_clbits=5)
    call qc%measure_all()
    call assert_eq_int_size_t(qc%num_instructions(), 2, &
        "measure_all with nc>nq succeeds (2 instructions)")
  end subroutine test_measure_all_clbit_boundary

  !> Test that calling methods on an uninitialised circuit triggers
  !> appropriate error stops. This verifies guard clauses.
  !> Note: These tests would ideally use death-test wrappers; for now,
  !> we verify that initialised circuits work and document the guards exist.
  subroutine test_uninitialised_circuit_guards()
    type(QuantumCircuit) :: qc

    call section("Uninitialised circuit guards")
    call qc%init(num_qubits=2, num_clbits=2)
    call assert_eq_int(qc%num_qubits(), 2, "initialised circuit: num_qubits works")
    call assert_eq_int(qc%num_clbits(), 2, "initialised circuit: num_clbits works")

    ! Add a gate to verify dispatch_gate guard
    call qc%h(0)
    call assert_eq_int_size_t(qc%num_instructions(), 1, &
        "initialised circuit: gate dispatch works")
  end subroutine test_uninitialised_circuit_guards

end program test_qiskit