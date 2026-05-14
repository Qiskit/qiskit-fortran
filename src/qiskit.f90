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
! qiskit.f90  —  High-level Fortran API for the Qiskit C extension
!
! Provides a Fortran-idiomatic QuantumCircuit derived type whose interface
! mirrors the Python qiskit.QuantumCircuit API as closely as the language
! allows.  Every method delegates to qiskit_c_api (the raw FFI layer) while
! hiding pointer arithmetic, kind conversions, and NULL handling.
!
! Design principles (mirroring qiskit-cpp and Qiskit.jl):
!   • Two clear layers: FFI (qiskit_c_api) and API (this module).
!   • RAII via Fortran FINAL procedure: no manual free() calls needed.
!   • All qubit/clbit indices are 0-based, matching the C API and Python.
!   • Every C call checks the exit code; failures call error stop.
!   • No module-level mutable state: circuits are independent objects.
!
! Typical usage:
!
!   use qiskit
!   type(QuantumCircuit) :: qc
!   call qc%init(num_qubits=2, num_clbits=2)
!   call qc%h(0)
!   call qc%cx(0, 1)
!   call qc%measure_all()
!   print *, "instructions:", qc%num_instructions()
!   ! qc is freed automatically when it leaves scope
! =============================================================================

module qiskit
  use qiskit_circuit

  implicit none (type, external)
  private

  public :: QuantumCircuit

end module qiskit
