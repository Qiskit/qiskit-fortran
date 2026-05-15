// This code is part of Qiskit.
//
// (C) Copyright IBM 2026
//
// This code is licensed under the Apache License, Version 2.0. You may
// obtain a copy of this license in the LICENSE.txt file in the root directory
// of this source tree or at https://www.apache.org/licenses/LICENSE-2.0.
//
// Any modifications or derivative works of this code must retain this
// copyright notice, and modified files need to carry a notice indicating
// that they have been altered from the originals.

/**
 * @file qiskit_direct.i
 * @brief SWIG interface for direct Fortran bindings to Qiskit C API
 *
 * Uses %fortranbindc for direct C-to-Fortran binding generation via ISO_C_BINDING.
 * See README.md for detailed documentation on usage and rationale.
 */

%module qiskit_swigf

// ============================================================================
// FORTRAN BINDING DIRECTIVES
// ============================================================================

%fortranbindc;

// ============================================================================
// STANDARD TYPE DEFINITIONS
// ============================================================================

// Include standard signed integer types
%include <fortran/stdint.i>

// Map unsigned integer types to their signed equivalents
// (Fortran doesn't distinguish signed/unsigned)
%fortran_unsigned(int8_t,  uint8_t)
%fortran_unsigned(int16_t, uint16_t)
%fortran_unsigned(int32_t, uint32_t)
%fortran_unsigned(int64_t, uint64_t)

// ============================================================================
// PREPROCESSOR CONFIGURATION
// ============================================================================

// Exclude Python-specific interface functions
#define QISKIT_C_PYTHON_INTERFACE 0

%{
#define QISKIT_C_PYTHON_INTERFACE 0
%}

// ============================================================================
// HEADER INCLUDES
// ============================================================================

%{
// Define PyObject as an opaque struct to satisfy the compiler
// We won't actually use these Python-specific functions
typedef struct _object PyObject;

#include "qiskit/complex.h"
#include "qiskit/types.h"
#include "qiskit/funcs.h"
#include "qiskit/attributes.h"
%}

// Ignore helper functions (header-only, not part of C API)
%ignore qk_complex64_to_native;
%ignore qk_complex64_from_native;

// Ignore all Python-specific functions (require PyObject which isn't available in pure C)
%rename("$ignore", regextarget=1, fullname=1) ".*python.*";

%include "qiskit/complex.h"
%include "qiskit/attributes.h"

// ============================================================================
// STRUCT TYPE MAPPINGS
// ============================================================================

// Enable native Fortran bind(C) derived types for ISO C compatible structs
%fortran_struct(QkComplex64);
%fortran_struct(QkOpCount);
%fortran_struct(QkOpCounts);
%fortran_struct(QkCircuitInstruction);
%fortran_struct(QkPauliProductRotation);
%fortran_struct(QkPauliProductMeasurement);
%fortran_struct(QkCircuitDrawerConfig);
%fortran_struct(QkDagNeighbors);
%fortran_struct(QkObsTerm);
%fortran_struct(QkNeighbors);
%fortran_struct(QkSabreLayoutOptions);
%fortran_struct(QkInstructionProperties);
%fortran_struct(QkTargetOp);
%fortran_struct(QkTranspileOptions);
%fortran_struct(QkTranspileResult);

// ============================================================================
// TYPE DEFINITIONS AND FUNCTION DECLARATIONS
// ============================================================================

%include "qiskit/types.h"
%include "qiskit/funcs.h"

// ============================================================================
// FORTRAN TYPE CONFIGURATION
// ============================================================================

%fortranconst;

%apply size_t { size_t };
%apply uint32_t { uint32_t };
%apply uint8_t { uint8_t };
%apply int64_t { int64_t };
%apply double { double };
%apply bool { bool };
