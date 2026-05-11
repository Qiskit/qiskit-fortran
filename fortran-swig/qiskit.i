// This code is part of Qiskit.
//
// (C) Copyright IBM 2026.
//
// This code is licensed under the Apache License, Version 2.0. You may
// obtain a copy of this license in the LICENSE.txt file in the root directory
// of this source tree or at https://www.apache.org/licenses/LICENSE-2.0.
//
// Any modifications or derivative works of this code must retain this
// copyright notice, and modified files need to carry a notice indicating
// that they have been altered from the originals.

// qiskit.i
%module qiskit_swig_api

%{
#include "qiskit.h"
%}

// Ignore deprecated function attributes
#define Qk_DEPRECATED_FN
#define Qk_DEPRECATED_FN_NOTE(note)

// Include the main header which pulls in types.h and funcs.h
%include "qiskit/attributes.h"
%include "qiskit/complex.h"
%include "qiskit/types.h"
%include "qiskit/funcs.h"