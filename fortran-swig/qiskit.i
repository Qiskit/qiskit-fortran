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