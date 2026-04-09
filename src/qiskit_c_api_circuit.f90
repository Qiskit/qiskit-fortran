!> @brief C API bindings for quantum circuit operations
!>
!> ISO_C_BINDING interfaces to Qiskit C extension. Gate constants match
!> Rust's StandardGate enum. Function signatures match qiskit.h exactly.
!> Prefer using the high-level qiskit module instead of this FFI layer.
module qiskit_c_api_circuit
  use, intrinsic :: iso_c_binding, only : &
      c_ptr, c_int, c_int32_t, c_size_t

  implicit none
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

  public :: qk_circuit_new, qk_circuit_free
  public :: qk_circuit_num_qubits, qk_circuit_num_clbits
  public :: qk_circuit_num_instructions
  public :: qk_circuit_gate
  public :: qk_gate_num_qubits, qk_gate_num_params
  public :: qk_circuit_measure
  public :: qk_circuit_reset
  public :: qk_circuit_barrier

  ! Gate enum constants from qiskit.h (StandardGate in Rust)
  integer(c_int), parameter :: QkGate_GlobalPhase = 0_c_int
  integer(c_int), parameter :: QkGate_H           = 1_c_int
  integer(c_int), parameter :: QkGate_I           = 2_c_int
  integer(c_int), parameter :: QkGate_X           = 3_c_int
  integer(c_int), parameter :: QkGate_Y           = 4_c_int
  integer(c_int), parameter :: QkGate_Z           = 5_c_int
  integer(c_int), parameter :: QkGate_Phase       = 6_c_int
  integer(c_int), parameter :: QkGate_R           = 7_c_int
  integer(c_int), parameter :: QkGate_Rx          = 8_c_int
  integer(c_int), parameter :: QkGate_Ry          = 9_c_int
  integer(c_int), parameter :: QkGate_Rz          = 10_c_int
  integer(c_int), parameter :: QkGate_S           = 11_c_int
  integer(c_int), parameter :: QkGate_Sdg         = 12_c_int
  integer(c_int), parameter :: QkGate_SX          = 13_c_int
  integer(c_int), parameter :: QkGate_SXdg        = 14_c_int
  integer(c_int), parameter :: QkGate_T           = 15_c_int
  integer(c_int), parameter :: QkGate_Tdg         = 16_c_int
  integer(c_int), parameter :: QkGate_U           = 17_c_int
  integer(c_int), parameter :: QkGate_U1          = 18_c_int
  integer(c_int), parameter :: QkGate_U2          = 19_c_int
  integer(c_int), parameter :: QkGate_U3          = 20_c_int
  integer(c_int), parameter :: QkGate_CH          = 21_c_int
  integer(c_int), parameter :: QkGate_CX          = 22_c_int
  integer(c_int), parameter :: QkGate_CY          = 23_c_int
  integer(c_int), parameter :: QkGate_CZ          = 24_c_int
  integer(c_int), parameter :: QkGate_DCX         = 25_c_int
  integer(c_int), parameter :: QkGate_ECR         = 26_c_int
  integer(c_int), parameter :: QkGate_Swap        = 27_c_int
  integer(c_int), parameter :: QkGate_ISwap       = 28_c_int
  integer(c_int), parameter :: QkGate_CCX         = 45_c_int

  interface

    function qk_circuit_new(num_qubits, num_clbits) result(ptr) &
        bind(C, name="qk_circuit_new")
      import :: c_ptr, c_int32_t
      integer(c_int32_t), value, intent(in) :: num_qubits
      integer(c_int32_t), value, intent(in) :: num_clbits
      type(c_ptr)                            :: ptr
    end function qk_circuit_new

    subroutine qk_circuit_free(circuit) &
        bind(C, name="qk_circuit_free")
      import :: c_ptr
      type(c_ptr), value, intent(in) :: circuit
    end subroutine qk_circuit_free

    function qk_circuit_num_qubits(circuit) result(n) &
        bind(C, name="qk_circuit_num_qubits")
      import :: c_ptr, c_int32_t
      type(c_ptr), value, intent(in) :: circuit
      integer(c_int32_t)            :: n
    end function qk_circuit_num_qubits

    function qk_circuit_num_clbits(circuit) result(n) &
        bind(C, name="qk_circuit_num_clbits")
      import :: c_ptr, c_int32_t
      type(c_ptr), value, intent(in) :: circuit
      integer(c_int32_t)            :: n
    end function qk_circuit_num_clbits

    function qk_circuit_num_instructions(circuit) result(n) &
        bind(C, name="qk_circuit_num_instructions")
      import :: c_ptr, c_size_t
      type(c_ptr), value, intent(in) :: circuit
      integer(c_size_t)              :: n
    end function qk_circuit_num_instructions

    function qk_circuit_gate(circuit, gate, qubits, params) result(code) &
        bind(C, name="qk_circuit_gate")
      import :: c_ptr, c_int
      type(c_ptr), value, intent(in) :: circuit
      integer(c_int), value, intent(in) :: gate
      type(c_ptr), value, intent(in) :: qubits
      type(c_ptr), value, intent(in) :: params
      integer(c_int)                 :: code
    end function qk_circuit_gate

    function qk_gate_num_qubits(gate) result(n) &
        bind(C, name="qk_gate_num_qubits")
      import :: c_int, c_int32_t
      integer(c_int), value, intent(in) :: gate
      integer(c_int32_t)               :: n
    end function qk_gate_num_qubits

    function qk_gate_num_params(gate) result(n) &
        bind(C, name="qk_gate_num_params")
      import :: c_int, c_int32_t
      integer(c_int), value, intent(in) :: gate
      integer(c_int32_t)               :: n
    end function qk_gate_num_params

    function qk_circuit_measure(circuit, qubit, clbit) result(code) &
        bind(C, name="qk_circuit_measure")
      import :: c_ptr, c_int, c_int32_t
      type(c_ptr),         value, intent(in) :: circuit
      integer(c_int32_t), value, intent(in) :: qubit
      integer(c_int32_t), value, intent(in) :: clbit
      integer(c_int)                         :: code
    end function qk_circuit_measure

    function qk_circuit_reset(circuit, qubit) result(code) &
        bind(C, name="qk_circuit_reset")
      import :: c_ptr, c_int, c_int32_t
      type(c_ptr),         value, intent(in) :: circuit
      integer(c_int32_t), value, intent(in) :: qubit
      integer(c_int)                         :: code
    end function qk_circuit_reset

    function qk_circuit_barrier(circuit, qubits, num_qubits) result(code) &
        bind(C, name="qk_circuit_barrier")
      import :: c_ptr, c_int, c_int32_t
      type(c_ptr),         value, intent(in) :: circuit
      type(c_ptr),         value, intent(in) :: qubits
      integer(c_int32_t), value, intent(in) :: num_qubits
      integer(c_int)                         :: code
    end function qk_circuit_barrier

  end interface

end module qiskit_c_api_circuit
