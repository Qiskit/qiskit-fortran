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

!> @brief Transpiler module for quantum circuit optimization
!>
!> Provides types and functions for transpiling quantum circuits to target
!> hardware architectures with various optimization levels and constraints.
module qiskit_transpiler
  use, intrinsic :: iso_c_binding, only : &
      c_ptr, c_null_ptr, c_associated, c_int, c_int32_t, c_int64_t, &
      c_double, c_bool

#ifdef USE_SWIG_BINDINGS
  use qiskit_swigf, only : &
      QkTranspileResult, &
      QkTranspileOptions, qk_transpiler_default_options, &
      qk_transpile_layout_free, qk_transpile_layout_num_input_qubits, &
      qk_transpile_layout_num_output_qubits, qk_transpile_layout_initial_layout, &
      qk_transpile_layout_final_layout
  ! qk_transpile has a dummy arg named 'target'; module-level import would embed
  ! that name in the .mod file and break consumers declaring type(Target).
  ! It is imported at local scope inside transpile() only.
#else
  use qiskit_c_api_types
  use qiskit_c_api_transpiler
#endif

  use qiskit_utils, only : check_rc
  use qiskit_circuit, only : QuantumCircuit
  use qiskit_target, only : Target

  implicit none (type, external)
  private

  public :: TranspileOptions
  public :: TranspileLayout
  public :: transpile

  !> @brief Transpilation options
  !>
  !> Configures the transpilation process including optimization level,
  !> random seed, and approximation degree for gate synthesis.
  type :: TranspileOptions
    integer :: optimization_level = 1
    integer(c_int64_t) :: seed_transpiler = -1_c_int64_t
    real(c_double) :: approximation_degree = 1.0_c_double
  contains
    procedure, public :: init => transpile_options_init
  end type TranspileOptions

  !> @brief Transpilation layout information
  !>
  !> Encapsulates the qubit layout mapping from logical to physical qubits
  !> after transpilation. Provides methods to query layout properties and
  !> retrieve initial/final qubit mappings.
  type :: TranspileLayout
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public :: num_input_qubits => layout_num_input_qubits
    procedure, public :: num_output_qubits => layout_num_output_qubits
    procedure, public :: get_initial_layout => layout_get_initial_layout
    procedure, public :: get_final_layout => layout_get_final_layout
    final :: layout_destroy
  end type TranspileLayout

contains

  !> @brief Set options fields; validates ranges.
  !> @param optimization_level 0-3 (default 1)
  !> @param seed_transpiler RNG seed; negative = system entropy (default -1)
  !> @param approximation_degree 0.0-1.0; 1.0 = exact (default 1.0)
  subroutine transpile_options_init(self, optimization_level, seed_transpiler, approximation_degree)
    class(TranspileOptions), intent(inout) :: self
    integer, intent(in), optional :: optimization_level
    integer(c_int64_t), intent(in), optional :: seed_transpiler
    real(c_double), intent(in), optional :: approximation_degree

    self%optimization_level = 1
    self%seed_transpiler = -1_c_int64_t
    self%approximation_degree = 1.0_c_double

    if (present(optimization_level)) then
      if (optimization_level < 0 .or. optimization_level > 3) &
          error stop "[qiskit_transpiler] init: optimization_level must be 0-3"
      self%optimization_level = optimization_level
    end if

    if (present(seed_transpiler)) self%seed_transpiler = seed_transpiler

    if (present(approximation_degree)) then
      if (approximation_degree < 0.0_c_double .or. approximation_degree > 1.0_c_double) &
          error stop "[qiskit_transpiler] init: approximation_degree must be 0.0-1.0"
      self%approximation_degree = approximation_degree
    end if
  end subroutine transpile_options_init

  subroutine layout_destroy(self)
    type(TranspileLayout), intent(inout) :: self
    if (c_associated(self%ptr)) then
      call qk_transpile_layout_free(self%ptr)
      self%ptr = c_null_ptr
    end if
  end subroutine layout_destroy

  !> @brief Get number of input (logical) qubits in layout
  !> @return number of input qubits
  function layout_num_input_qubits(self) result(n)
    class(TranspileLayout), intent(in) :: self
    integer :: n

    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_transpiler] num_input_qubits: uninitialised layout"

    n = int(qk_transpile_layout_num_input_qubits(self%ptr))
  end function layout_num_input_qubits

  !> @brief Get number of output (physical) qubits in layout
  !> @return number of output qubits
  function layout_num_output_qubits(self) result(n)
    class(TranspileLayout), intent(in) :: self
    integer :: n

    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_transpiler] num_output_qubits: uninitialised layout"

    n = int(qk_transpile_layout_num_output_qubits(self%ptr))
  end function layout_num_output_qubits

  !> @brief Get initial layout mapping (logical to physical qubits)
  !> @param filter_ancillas optional flag to filter out ancilla qubits (default: false)
  !> @return allocatable array of physical qubit indices (-1 for unmapped)
  !> @note Array is indexed from 1 (Fortran convention), but values are 0-indexed qubit indices
  function layout_get_initial_layout(self, filter_ancillas) result(layout_array)
    class(TranspileLayout), intent(in) :: self
    logical, intent(in), optional :: filter_ancillas
    integer, allocatable :: layout_array(:)

    integer :: n_input, i
    integer(c_int32_t) :: output_qubit
    logical(c_bool) :: found, filter_flag
    logical :: filter

    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_transpiler] get_initial_layout: uninitialised layout"

    filter = .false.
    if (present(filter_ancillas)) filter = filter_ancillas
    filter_flag = logical(filter, c_bool)

    n_input = self%num_input_qubits()
    allocate(layout_array(n_input))

    do i = 1, n_input
      found = qk_transpile_layout_initial_layout(self%ptr, filter_flag, output_qubit)
      if (found) then
        layout_array(i) = int(output_qubit)
      else
        layout_array(i) = -1
      end if
    end do
  end function layout_get_initial_layout

  !> @brief Get final layout mapping (physical to logical qubits)
  !> @param filter_ancillas optional flag to filter out ancilla qubits (default: false)
  !> @return allocatable array of logical qubit indices (-1 for unmapped)
  !> @note Array is indexed from 1 (Fortran convention), but values are 0-indexed qubit indices
  function layout_get_final_layout(self, filter_ancillas) result(layout_array)
    class(TranspileLayout), intent(in) :: self
    logical, intent(in), optional :: filter_ancillas
    integer, allocatable :: layout_array(:)

    integer :: n_output, i
    integer(c_int32_t) :: input_qubit
    logical(c_bool) :: filter_flag
    logical :: filter

    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_transpiler] get_final_layout: uninitialised layout"

    filter = .false.
    if (present(filter_ancillas)) filter = filter_ancillas
    filter_flag = logical(filter, c_bool)

    n_output = self%num_output_qubits()
    allocate(layout_array(n_output))

    do i = 1, n_output
      call qk_transpile_layout_final_layout(self%ptr, filter_flag, input_qubit)
      layout_array(i) = int(input_qubit)
    end do
  end function layout_get_final_layout

  !> @brief Transpile a quantum circuit for target hardware
  !> @param circuit input quantum circuit to transpile
  !> @param backend target hardware (required; C API does not accept a null target)
  !> @param options optional transpilation options
  !> @param layout optional output: qubit layout after transpilation (freed automatically via `final`)
  !> @return new transpiled circuit; input is unchanged
  function transpile(circuit, backend, options, layout) result(transpiled_circuit)
    use qiskit_swigf, only : qk_transpile
    type(QuantumCircuit), intent(in) :: circuit
    type(Target), intent(in), optional :: backend
    type(TranspileOptions), intent(in), optional :: options
    type(TranspileLayout), intent(out), optional :: layout
    type(QuantumCircuit) :: transpiled_circuit

    type(QkTranspileResult) :: result
    type(QkTranspileOptions) :: c_opts
    type(TranspileLayout) :: temp_layout
    type(c_ptr) :: target_ptr
    integer(c_int) :: rc

    result%circuit = c_null_ptr
    result%layout  = c_null_ptr

    if (.not. present(backend)) &
        error stop "[qiskit_transpiler] transpile: backend is required"
    target_ptr = backend%get_c_ptr()

    if (present(options)) then
      c_opts%optimization_level = int(options%optimization_level, kind(c_opts%optimization_level))
      c_opts%seed               = options%seed_transpiler
      c_opts%approximation_degree = options%approximation_degree
    else
      c_opts = qk_transpiler_default_options()
    end if

    rc = qk_transpile(circuit%get_c_ptr(), target_ptr, c_opts, result, c_null_ptr)

    call check_rc(rc, "transpile")
    if (.not. c_associated(result%circuit)) &
        error stop "[qiskit_transpiler] transpile: transpilation failed"

    call transpiled_circuit%from_ptr(result%circuit)

    if (present(layout)) then
      layout%ptr = result%layout
    else
      temp_layout%ptr = result%layout
    end if
  end function transpile

end module qiskit_transpiler
