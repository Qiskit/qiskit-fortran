#!/usr/bin/env python3
# This code is part of Qiskit.
#
# (C) Copyright IBM 2026.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at https://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

"""Type classification for SWIG-generated Fortran bindings.

Maps SWIG wrapper types to canonical Fortran bind(C) types using systematic
pattern matching and naming conventions.
"""

from __future__ import annotations

from typing import Optional, Set
from dataclasses import dataclass


@dataclass
class SwigParam:
    """SWIG-generated parameter."""
    name: str
    swig_type: str


@dataclass
class SwigProc:
    """SWIG-generated procedure."""
    name: str
    kind: str
    params: list[SwigParam]
    result_swig_type: Optional[str] = None


class TypeClassifier:
    """Classify SWIG wrapper types to canonical Fortran types."""
    
    OPAQUE_PREFIXES = ("SWIGTYPE_p_Qk", "SWIGTYPE_p_p_")
    SCALAR_INDEX_NAMES = {
        "num_qubits", "num_clbits", "qubit", "clbit",
        "seed", "fold", "num_qubits_out",
    }
    SCALAR_SIZE_NAMES = {"len", "count", "num_instructions", "size"}
    ARRAY_POINTER_NAMES = {
        "qubits", "clbits", "params", "indices",
        "neighbors", "data", "matrix",
    }
    ENUM_TYPES = {"QkGate", "QkExitCode", "QkOperationKind", "QkDelayUnit"}
    
    def classify_param(self, proc: SwigProc, param: SwigParam) -> str:
        """Classify parameter SWIG type to canonical Fortran type."""
        swig_type = param.swig_type
        param_name = param.name
        
        if self._is_opaque_handle(swig_type):
            return "type(c_ptr)"
        
        if swig_type.startswith("SWIGTYPE_p_p_"):
            return "type(c_ptr)"
        
        if swig_type in self.ENUM_TYPES or param_name == "gate":
            return "integer(c_int)"
        
        if param_name in self.ARRAY_POINTER_NAMES:
            return "type(c_ptr)"
        
        if param_name in self.SCALAR_INDEX_NAMES:
            return "integer(c_int32_t)"
        
        if param_name in self.SCALAR_SIZE_NAMES:
            return "integer(c_size_t)"
        
        if swig_type == "SWIGTYPE_p_uint32_t":
            if self._has_size_companion(proc, param_name):
                return "type(c_ptr)"
            return "integer(c_int32_t)"
        
        if swig_type == "SWIGTYPE_p_size_t":
            if self._has_size_companion(proc, param_name):
                return "type(c_ptr)"
            return "integer(c_size_t)"
        
        if swig_type == "SWIGTYPE_p_double":
            return "type(c_ptr)"  # Usually array of doubles
        
        if swig_type == "SWIGTYPE_p_bool":
            return "integer(c_int)"  # C bool as int
        
        return "type(c_ptr)"
    
    def classify_result(self, proc: SwigProc) -> Optional[str]:
        """Classify function return type to canonical Fortran (None for void)."""
        swig_type = proc.result_swig_type
        if not swig_type:
            return None
        
        if self._is_opaque_handle(swig_type):
            return "type(c_ptr)"
        
        if swig_type in self.ENUM_TYPES:
            return "integer(c_int)"
        
        if swig_type == "SWIGTYPE_p_uint32_t":
            return "integer(c_int32_t)"
        
        if swig_type == "SWIGTYPE_p_size_t":
            return "integer(c_size_t)"
        
        if "C_SIZE_T" in swig_type.upper():
            return "integer(c_size_t)"
        
        if proc.name.endswith("_new") or proc.name.endswith("_copy"):
            return "type(c_ptr)"
        
        if "_num_" in proc.name or proc.name.startswith("qk_gate_num_"):
            return "integer(c_int32_t)"
        
        return "type(c_ptr)"
    
    def _is_opaque_handle(self, swig_type: str) -> bool:
        """Check if SWIG type is an opaque handle."""
        return any(swig_type.startswith(prefix) for prefix in self.OPAQUE_PREFIXES)
    
    def _has_size_companion(self, proc: SwigProc, param_name: str) -> bool:
        """Check if parameter has companion size parameter (array heuristic)."""
        if not param_name.endswith("s"):
            return False
        
        for p in proc.params:
            if p.name.startswith("num_") or p.name in self.SCALAR_SIZE_NAMES:
                return True
        
        return False


def classify_param(proc: SwigProc, param: SwigParam) -> str:
    """Classify parameter type."""
    classifier = TypeClassifier()
    return classifier.classify_param(proc, param)


def classify_result(proc: SwigProc) -> Optional[str]:
    """Classify result type."""
    classifier = TypeClassifier()
    return classifier.classify_result(proc)