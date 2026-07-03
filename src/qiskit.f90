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
! qiskit.f90  —  Top-level re-export module
!
! Aggregates the public API: QuantumCircuit (always), and Target/transpile
! (SWIG path only — no manual C API equivalents yet).
! =============================================================================

module qiskit
  use qiskit_circuit

#ifdef USE_SWIG_BINDINGS
  use qiskit_target
  use qiskit_transpiler
#endif

  implicit none (type, external)
  private

  public :: QuantumCircuit

#ifdef USE_SWIG_BINDINGS
  public :: Target, InstructionProperties
  public :: TranspileOptions, TranspileLayout
  public :: transpile
#endif

end module qiskit
