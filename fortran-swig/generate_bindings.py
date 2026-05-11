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

"""
generate_bindings.py: Canonical Fortran FFI module generator

Pipeline
--------
  qiskit.h  ->  [SWIG -fortran]  -> qiskit_swig_api.f90 -> [this script] -> ergonomic API

The generator reads qiskit_swig_api.f90 purely as a parsed schema, extracting
type shapes, argument names, and enum values. It then emits canonical bind(C)
interface modules that call libqiskit directly.  qiskit_wrap.cxx is NOT used
or linked.  The generated modules are drop-in replacements for the handwritten
interfaces (such as qiskit_c_api_types.f90 and qiskit_c_api_circuit.f90,).
So API modules (such as qiskit_utils.f90, qiskit_circuit.f90, and qiskit.f90) 
compile identically on both build paths.

Usage
-----
  python fortran-swig/generate_bindings.py               # defaults
  python fortran-swig/generate_bindings.py \\
      --input  fortran-swig/qiskit_swig_api.f90 \\
      --output-dir fortran-swig/
"""

from __future__ import annotations

import argparse
import re
import sys
import textwrap
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from interface_generator import TypeClassifier, SwigParam, SwigProc

# ---------------------------------------------------------------------------
# Module routing
# ---------------------------------------------------------------------------

UNIFIED_MODULE_NAME = "qiskit_c_api"


def _derive_module_name(func_name: str) -> str:
    """Route function to unified module."""
    return UNIFIED_MODULE_NAME


def _derive_enum_module(enum_name: str) -> str:
    """Route enum to unified module."""
    return UNIFIED_MODULE_NAME


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------

@dataclass
class EnumDef:
    """Enum definition with alias name and values."""
    name:   str
    values: List[Tuple[str, str]]


@dataclass
class Param:
    """Procedure parameter."""
    name:           str
    swig_type:      str
    canonical_type: Optional[str] = None


@dataclass
class ProcDef:
    """Procedure definition."""
    name:              str
    kind:              str
    params:            List[Param]
    result_swig_type:  Optional[str] = None
    canonical_result:  Optional[str] = None
    output_module:     Optional[str] = None


@dataclass
class CanonicalModule:
    """Generated Fortran module."""
    name:       str
    constants:  List[Tuple[str, str]] = field(default_factory=list)
    procedures: List[ProcDef]         = field(default_factory=list)
    extra_uses: List[str]             = field(default_factory=list)

# ---------------------------------------------------------------------------
# Compiled regexes
# ---------------------------------------------------------------------------

_ENUM_OPEN_RE  = re.compile(r"^\s*enum,\s*bind\(c\)\s*$", re.I)
_ENUM_CLOSE_RE = re.compile(r"^\s*end\s+enum\s*$", re.I)
_ENUMERATOR_RE = re.compile(r"^\s*enumerator\s*::\s*(\w+)\s*=\s*(.+?)\s*$", re.I)
_ENUM_ALIAS_RE = re.compile(
    r"^\s*integer,\s*parameter,\s*public\s*::\s*(\w+)\s*=\s*kind\((\w+)\)\s*$", re.I
)
_TYPE_DECL_RE  = re.compile(r"^\s*type,\s*public\s*::\s*(SWIGTYPE_p_[A-Za-z0-9_]+)\s*$", re.I)
_PUBLIC_RE     = re.compile(r"^\s*public\s*::\s*(.+)$", re.I)
_PROC_START_RE = re.compile(
    r"^\s*(function|subroutine)\s+(qk_[A-Za-z0-9_]+)\s*\(([^)]*)\)\s*(?:&)?\s*$",
    re.I,
)
_RESULT_RE = re.compile(r"\bresult\s*\(\s*(\w+)\s*\)", re.I)
_DECL_RE = re.compile(
    r"^\s*((?:type|class)\s*\(\s*\w+\s*\)|integer(?:\s*\(\s*\w+\s*\))?|"
    r"real\s*\(\s*\w+\s*\)|logical(?:\s*\(\s*\w+\s*\))?|"
    r"character\s*\(\s*len\s*=\s*\*\s*\))\s*(?:,\s*[^:]*)?\s*::\s*(.+)$",
    re.I,
)


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def _normalize_lines(text: str) -> List[str]:
    return text.splitlines()


def _normalize_decl_type(raw: str) -> str:
    """Extract SWIG type name from Fortran declaration."""
    lowered = raw.lower().replace(" ", "")
    for prefix in ("type(", "class("):
        if lowered.startswith(prefix):
            inner = raw[raw.find("(") + 1 : raw.rfind(")")].strip()
            return inner
    if lowered.startswith("integer("):
        inner = raw[raw.find("(") + 1 : raw.rfind(")")].strip()
        return inner
    if lowered in ("integer",):
        return "integer"
    if lowered.startswith("real("):
        inner = raw[raw.find("(") + 1 : raw.rfind(")")].strip()
        return inner
    if lowered.startswith("logical("):
        inner = raw[raw.find("(") + 1 : raw.rfind(")")].strip()
        return inner
    return raw.strip()


def parse_enums(lines: List[str]) -> List[EnumDef]:
    """Parse enum blocks and alias names."""
    enums: List[EnumDef] = []
    i = 0
    while i < len(lines):
        if _ENUM_OPEN_RE.match(lines[i]):
            values: List[Tuple[str, str]] = []
            i += 1
            while i < len(lines) and not _ENUM_CLOSE_RE.match(lines[i]):
                m = _ENUMERATOR_RE.match(lines[i])
                if m:
                    values.append((m.group(1), m.group(2).strip()))
                i += 1
            alias_name: Optional[str] = None
            if i + 1 < len(lines):
                am = _ENUM_ALIAS_RE.match(lines[i + 1])
                if am:
                    alias_name = am.group(1)
            if alias_name and values:
                enums.append(EnumDef(alias_name, values))
        i += 1
    return enums


def parse_public_procedures(lines: List[str]) -> Set[str]:
    """Collect public qk_* procedure names."""
    names: Set[str] = set()
    for line in lines:
        m = _PUBLIC_RE.match(line)
        if not m:
            continue
        for part in m.group(1).replace("&", "").split(","):
            name = part.strip()
            if name.startswith("qk_"):
                names.add(name)
    return names


def parse_procedures(lines: List[str], public_procs: Set[str]) -> List[ProcDef]:
    """Parse procedure signatures from SWIG-generated module."""
    procedures: List[ProcDef] = []
    i = 0
    while i < len(lines):
        m = _PROC_START_RE.match(lines[i])
        if not m:
            i += 1
            continue
        kind = m.group(1).lower()
        name = m.group(2)
        if name not in public_procs:
            i += 1
            continue

        raw_args = m.group(3)
        params = [a.strip() for a in raw_args.split(",") if a.strip()]

        result_name: Optional[str] = None
        header_extra = ""
        if i + 1 < len(lines) and _RESULT_RE.search(lines[i + 1]):
            header_extra = lines[i + 1]
        combined = lines[i] + " " + header_extra
        rm = _RESULT_RE.search(combined)
        if rm:
            result_name = rm.group(1)

        end_pat = re.compile(rf"^\s*end\s+{kind}(?:\s+{re.escape(name)})?\s*$", re.I)
        j = i + 1
        decl_map: Dict[str, str] = {}
        result_type: Optional[str] = None

        while j < len(lines) and not end_pat.match(lines[j]):
            dm = _DECL_RE.match(lines[j])
            if dm:
                dtype = _normalize_decl_type(dm.group(1))
                for vname in dm.group(2).split(","):
                    vname = vname.strip()
                    if vname == result_name:
                        result_type = dtype
                    else:
                        decl_map[vname] = dtype
            j += 1

        proc_params = [
            Param(name=p, swig_type=decl_map.get(p, "unknown"))
            for p in params
        ]
        procedures.append(ProcDef(
            name=name,
            kind=kind,
            params=proc_params,
            result_swig_type=result_type,
        ))
        i = j + 1
    return procedures


# ---------------------------------------------------------------------------
# Type classification
# ---------------------------------------------------------------------------

_type_classifier = TypeClassifier()


def classify_param(proc: ProcDef, param: Param) -> str:
    """Classify parameter type using TypeClassifier."""
    swig_params = [SwigParam(name=p.name, swig_type=p.swig_type) for p in proc.params]
    swig_proc = SwigProc(
        name=proc.name,
        kind=proc.kind,
        params=swig_params,
        result_swig_type=proc.result_swig_type
    )
    swig_param = SwigParam(name=param.name, swig_type=param.swig_type)
    
    return _type_classifier.classify_param(swig_proc, swig_param)


def classify_result(proc: ProcDef) -> Optional[str]:
    """Classify result type using TypeClassifier."""
    swig_params = [SwigParam(name=p.name, swig_type=p.swig_type) for p in proc.params]
    swig_proc = SwigProc(
        name=proc.name,
        kind=proc.kind,
        params=swig_params,
        result_swig_type=proc.result_swig_type
    )
    
    return _type_classifier.classify_result(swig_proc)


# ---------------------------------------------------------------------------
# Routing and inference
# ---------------------------------------------------------------------------

def _target_module(func_name: str) -> str:
    """Get target module for function."""
    return _derive_module_name(func_name)


def build_modules(
    enums: List[EnumDef],
    procs: List[ProcDef],
) -> Dict[str, CanonicalModule]:
    """Route enums and procedures to target modules."""
    modules: Dict[str, CanonicalModule] = {}

    def get_mod(name: str) -> CanonicalModule:
        if name not in modules:
            modules[name] = CanonicalModule(name=name)
        return modules[name]

    # Route enum constants
    for enum in enums:
        target = _derive_enum_module(enum.name)
        get_mod(target).constants.extend(enum.values)

    # Route and infer procedures
    for proc in procs:
        target = _target_module(proc.name)
        proc.output_module = target
        for param in proc.params:
            param.canonical_type = classify_param(proc, param)
        proc.canonical_result = classify_result(proc)
        get_mod(target).procedures.append(proc)

    return modules


# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------

_FORTRAN_MAX_LINE = 128

def _public_list(names: List[str], indent: int = 2) -> List[str]:
    """Render public statements with proper continuation lines."""
    prefix = " " * indent + "public :: "
    cont_prefix = " " * (indent + 4)  # Indent continuation lines
    lines: List[str] = []
    current: List[str] = []
    current_len = len(prefix)
    
    for i, name in enumerate(names):
        test_len = current_len + len(name) + (2 if current else 0)
        
        if current and test_len > _FORTRAN_MAX_LINE:
            lines.append(prefix + ", ".join(current) + ", &")
            current = [name]
            current_len = len(cont_prefix) + len(name)
            prefix = cont_prefix
        else:
            current.append(name)
            current_len = test_len
    
    if current:
        lines.append(prefix + ", ".join(current))
    
    return lines


def _required_imports(types: Set[str]) -> List[str]:
    """Return required iso_c_binding names in stable order."""
    order = ["c_ptr", "c_null_ptr", "c_int", "c_int32_t",
             "c_size_t", "c_double", "c_bool", "c_int64_t"]
    return [n for n in order if n in types]


def _collect_types_for_decl(decl: str) -> Set[str]:
    found: Set[str] = set()
    for name in ("c_ptr", "c_null_ptr", "c_int32_t", "c_size_t",
                 "c_double", "c_bool", "c_int64_t"):
        if name in decl:
            found.add(name)
    if "c_int" in decl and not any(v in decl for v in ("c_int32_t", "c_int64_t")):
        found.add("c_int")
    return found


def _module_level_imports(mod: CanonicalModule) -> List[str]:
    types: Set[str] = set()
    if mod.constants:
        types.add("c_int")
    for proc in mod.procedures:
        for p in proc.params:
            types |= _collect_types_for_decl(p.canonical_type or "")
        if proc.canonical_result:
            types |= _collect_types_for_decl(proc.canonical_result)
    return _required_imports(types)


def _proc_imports(proc: ProcDef) -> List[str]:
    types: Set[str] = set()
    for p in proc.params:
        types |= _collect_types_for_decl(p.canonical_type or "")
    if proc.canonical_result:
        types |= _collect_types_for_decl(proc.canonical_result)
    return _required_imports(types)


def _result_var_name(proc: ProcDef) -> str:
    cr = proc.canonical_result or ""
    if cr == "type(c_ptr)":
        return "ptr"
    if "size_t" in cr:
        return "n"
    if "int32" in cr:
        return "n"
    if "c_int" in cr:
        return "code"
    return "result"


def _render_param(p: Param) -> str:
    ct = p.canonical_type or "type(c_ptr)"
    return f"      {ct}, value, intent(in) :: {p.name}"


def _render_proc(proc: ProcDef) -> List[str]:
    """Render procedure interface."""
    imports = ", ".join(_proc_imports(proc))
    out: List[str] = []

    if proc.kind == "function":
        rname = _result_var_name(proc)
        sig_line = f"    function {proc.name}("
        args = ", ".join(p.name for p in proc.params)
        full_sig = f"{sig_line}{args}) result({rname}) &"
        
        if len(full_sig) <= _FORTRAN_MAX_LINE:
            out.append(full_sig)
        else:
            out.append(sig_line + "&")
            for i, p in enumerate(proc.params):
                is_last = (i == len(proc.params) - 1)
                if is_last:
                    out.append(f"        {p.name}) result({rname}) &")
                else:
                    out.append(f"        {p.name}, &")
        
        out.append(f'        bind(C, name="{proc.name}")')
        if imports:
            out.append(f"      import :: {imports}")
        for p in proc.params:
            out.append(_render_param(p))
        result_decl = proc.canonical_result or "type(c_ptr)"
        out.append(f"      {result_decl} :: {rname}")
        out.append(f"    end function {proc.name}")
    else:
        sig_line = f"    subroutine {proc.name}("
        args = ", ".join(p.name for p in proc.params)
        full_sig = f"{sig_line}{args}) &"
        
        if len(full_sig) <= _FORTRAN_MAX_LINE:
            out.append(full_sig)
        else:
            out.append(sig_line + "&")
            for i, p in enumerate(proc.params):
                is_last = (i == len(proc.params) - 1)
                if is_last:
                    out.append(f"        {p.name}) &")
                else:
                    out.append(f"        {p.name}, &")
        
        out.append(f'        bind(C, name="{proc.name}")')
        if imports:
            out.append(f"      import :: {imports}")
        for p in proc.params:
            out.append(_render_param(p))
        out.append(f"    end subroutine {proc.name}")

    return out


def _render_module(mod: CanonicalModule) -> str:
    """Render module to Fortran source."""
    use_names = _module_level_imports(mod)

    lines: List[str] = []

    lines += [
        "! =============================================================================",
        f"! {mod.name}.f90  —  generated by generate_bindings.py",
        "!",
        "! DO NOT EDIT — regenerate with:",
        "!   python fortran-swig/generate_bindings.py",
        "! =============================================================================",
        "",
        f"module {mod.name}",
    ]

    if use_names:
        names_str = ", ".join(use_names)
        if len(f"  use, intrinsic :: iso_c_binding, only : {names_str}") <= _FORTRAN_MAX_LINE:
            lines.append(f"  use, intrinsic :: iso_c_binding, only : {names_str}")
        else:
            lines.append("  use, intrinsic :: iso_c_binding, only : &")
            chunks = textwrap.wrap(names_str, width=72)
            for i, chunk in enumerate(chunks):
                suffix = " &" if i < len(chunks) - 1 else ""
                lines.append(f"      {chunk}{suffix}")

    for extra in mod.extra_uses:
        lines.append(extra)

    lines += ["", "  implicit none (type, external)", "  private", ""]

    all_names = [name for name, _ in mod.constants] + [p.name for p in mod.procedures]
    if mod.name in ("qiskit_c_api_types", "qiskit_c_api"):
        all_names.append("QK_QUBIT_KIND")
    if all_names:
        lines += _public_list(all_names)
        lines.append("")

    seen: Set[str] = set()
    for name, value in mod.constants:
        if name in seen:
            continue
        seen.add(name)
        try:
            int(value)
            lines.append(f"  integer(c_int), parameter :: {name} = {value}_c_int")
        except ValueError:
            lines.append(f"  integer(c_int), parameter :: {name} = {value}")
    if mod.constants:
        lines.append("")

    if mod.name in ("qiskit_c_api_types", "qiskit_c_api"):
        lines.append("  ! C-interoperable kind for uint32_t qubit/clbit indices")
        lines.append("  integer, parameter :: QK_QUBIT_KIND = c_int32_t")
        lines.append("")

    if mod.procedures:
        lines.append("  interface")
        lines.append("")
        for i, proc in enumerate(mod.procedures):
            lines += _render_proc(proc)
            if i < len(mod.procedures) - 1:
                lines.append("")
        lines += ["", "  end interface", ""]

    lines.append(f"end module {mod.name}")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument(
        "--input",
        default="fortran-swig/qiskit_swig_api.f90",
        help="Path to the SWIG-generated Fortran API file.",
    )
    p.add_argument(
        "--output-dir",
        default="fortran-swig",
        help="Directory where the generated .f90 files are written.",
    )
    return p.parse_args()


def main() -> int:
    args   = parse_args()
    inp    = Path(args.input)
    outdir = Path(args.output_dir)

    if not inp.exists():
        print(f"ERROR: input not found: {inp}", file=sys.stderr)
        return 1

    print(f"Reading: {inp}")
    lines = _normalize_lines(inp.read_text(encoding="utf-8"))

    enums        = parse_enums(lines)
    public_procs = parse_public_procedures(lines)
    procs        = parse_procedures(lines, public_procs)

    print(f"  Parsed  {len(enums)} enum groups")
    print(f"  Parsed  {len(public_procs)} public procedure names")
    print(f"  Parsed  {len(procs)} procedure signatures")

    modules = build_modules(enums, procs)
    outdir.mkdir(parents=True, exist_ok=True)

    if UNIFIED_MODULE_NAME in modules:
        mod = modules[UNIFIED_MODULE_NAME]
        source = _render_module(mod)
        target = outdir / f"{UNIFIED_MODULE_NAME}.f90"
        target.write_text(source, encoding="utf-8")
        n_procs = len(mod.procedures)
        n_consts = len(mod.constants)
        print(f"\n  Wrote   {target}")
        print(f"          {n_consts} constants, {n_procs} procedures")
        print("\nSuccess.")
        print(f"  Unified C API interface → {target}")
        print()
        print("This module provides bind(C) interfaces for ALL Qiskit C API functions.")
        print("Handwritten high-level APIs can selectively use functions from this module.")
    else:
        print("ERROR: No functions were routed to the unified module", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())