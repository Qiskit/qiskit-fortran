! =============================================================================
! qiskit_c_api.f90  —  Raw ISO_C_BINDING interface to the Qiskit C API
!
! This module is the FFI layer.  It declares every C symbol verbatim: names,
! argument order, and types all follow qiskit.h so that diffs against the
! upstream header stay trivial.  No abstraction lives here; this module is
! intentionally "ugly" so that qiskit.f90 (the API layer) can be "pretty".
!
! Usage:
!   use qiskit_c_api   ! for low-level access
!   use qiskit         ! for the high-level QuantumCircuit type (preferred)
!
! Gate enum constants
! -------------------
! The QkGate integer values are generated from Rust's StandardGate enum and
! compiled into qiskit.h by `make c` inside the Qiskit repo.
!
! re-verify with:
!   grep -E 'QkGate_[A-Za-z]+ =' $(QISKIT_ROOT)/dist/c/include/qiskit.h
! =============================================================================

module qiskit_c_api
  use, intrinsic :: iso_c_binding, only : &
      c_ptr, c_null_ptr, c_associated,    &
      c_int, c_int32_t,                   &
      c_size_t, c_double
  use qiskit_c_api_types
  use qiskit_c_api_circuit

  implicit none (type, external)
  private

  public :: QkGate_GlobalPhase
  public :: QkGate_H,   QkGate_I,   QkGate_X,    QkGate_Y,    QkGate_Z
  public :: QkGate_Phase
  public :: QkGate_R,   QkGate_Rx,  QkGate_Ry,   QkGate_Rz
  public :: QkGate_S,   QkGate_Sdg, QkGate_SX,   QkGate_SXdg
  public :: QkGate_T,   QkGate_Tdg
  public :: QkGate_U,   QkGate_U1,  QkGate_U2,   QkGate_U3
  public :: QkGate_CH,  QkGate_CX,  QkGate_CY,   QkGate_CZ
  public :: QkGate_DCX, QkGate_ECR, QkGate_Swap, QkGate_ISwap
  public :: QkGate_CCX

  public :: QkExitCode_Success
  public :: QkExitCode_CInputError
  public :: QkExitCode_NullPointerError
  public :: QkExitCode_AlignmentError
  public :: QkExitCode_IndexError
  public :: QkExitCode_ArithmeticError
  public :: QkExitCode_MismatchedQubits

  public :: qk_circuit_new, qk_circuit_free
  public :: qk_circuit_num_qubits, qk_circuit_num_clbits
  public :: qk_circuit_num_instructions
  public :: qk_circuit_gate
  public :: qk_gate_num_qubits, qk_gate_num_params
  public :: qk_circuit_measure
  public :: qk_circuit_reset
  public :: qk_circuit_barrier

end module qiskit_c_api
