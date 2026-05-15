# Qiskit Fortran Bindings via SWIG

This directory contains SWIG interface files for generating direct Fortran bindings to the Qiskit C API. We use SWIG's `%fortranbindc` feature to generate zero-overhead `bind(C)` interfaces that call the C library directly.

## SWIG-Based Generation Tutorial

Here's how to generate the bindings from scratch:

**Install SWIG-Fortran**

```bash
# Clone and build SWIG-Fortran
git clone https://github.com/swig-fortran/swig.git
cd swig
./autogen.sh
./configure --prefix=$HOME/.local
make -j$(nproc) && make install

# On macOS, you may need to set library path
export DYLD_LIBRARY_PATH=$HOME/miniconda3/lib:$DYLD_LIBRARY_PATH
```

**Note**: This is a template installation process. For detailed instructions, platform-specific requirements, and troubleshooting, refer to the official repository: https://github.com/swig-fortran/swig

**Generate bindings with SWIG**

```bash
cd fortran-swig
~/.local/bin/swig -fortran -I/path/to/qiskit/qiskit/capi/include qiskit_swigf.i
```

Replace `/path/to/qiskit` with your actual Qiskit installation path.

This generates:
- `qiskit_swigf.f90` - Fortran module with `bind(C)` interfaces
- `qiskit_swigf_wrap.c` - Minimal C wrapper (mostly empty with `fortranbindc`)

Note: `qiskit_swigf.i` declares `typedef struct _object PyObject;` as an opaque placeholder because `qiskit/funcs.h` still contains Python-bridge declarations guarded by `QISKIT_C_PYTHON_INTERFACE`.
Even when those functions are ignored for Fortran generation, SWIG still compiles the raw `%{ ... %}` include block, so removing the typedef causes an unknown-type `PyObject` compile failure.

## Architecture & Design Decisions

We use SWIG's `%fortranbindc` feature to generate direct C-to-Fortran bindings via ISO_C_BINDING. This approach provides zero-overhead interop—no wrapper layer, no runtime dependencies, just native Fortran calling C functions directly.

The key directive `%fortran_struct` tells SWIG to wrap C structs as native Fortran `bind(C)` derived types. Without this, structs would be opaque pointers requiring wrapper functions for field access. With it, we get direct field access (`mystruct%field`) with zero overhead.

**SWIG's value:** SWIG handles the complex C-to-Fortran type mapping automatically (preprocessor macros, typedefs, struct layouts, and function signatures). The `%fortranbindc` mode generates clean, idiomatic Fortran that matches handwritten `bind(C)` interfaces.

**Type mapping:** Opaque pointers (QkCircuit*, QkDag*, etc.) map to `type(c_ptr)`. ISO C compatible structs (QkComplex64, QkCircuitInstruction, etc.) become native Fortran types with direct field access. Enums become integer parameters. All mappings follow ISO_C_BINDING standards.

This approach maintains a single source of truth (the C headers) while generating readable, efficient Fortran bindings. When the C API changes, we regenerate.

## Future Directions

**Modularization**: Currently everything goes into one Fortran module. We could split into logical modules (`qiskit_circuit`, `qiskit_dag`, etc.) using SWIG's `%module` directive with submodules.

**Documentation pipeline**: SWIG can extract C header comments and generate Fortran documentation. We could explore enabling this with `%feature("docstring")` directives to preserve API documentation in the Fortran interfaces.

**Custom typemaps**: For advanced use cases, we could add custom SWIG typemaps to handle specific C patterns more idiomatically in Fortran. The current setup uses SWIG's default typemaps which work well for the Qiskit C API.

**CI/CD integration**: Add a GitHub Action that regenerates bindings on C API changes and opens a PR if differences are detected. This would catch API drift early and keep the bindings in sync automatically.

## Maintenance

When the Qiskit C API changes:

1. If new structs are added: Add `%fortran_struct(NewStruct);` to `qiskit_swigf.i`, then regenerate
2. If struct definitions/function signatures change: Just regenerating using SWIG picks up changes automatically

The SWIG interface file handles type mapping and code generation automatically. No manual editing of Fortran code required.

## Resources

- **SWIG-Fortran**: https://github.com/swig-fortran/swig
- **SWIG Fortran User Manual**: https://www.osti.gov/biblio/1833959
- **Qiskit C API**: https://qiskit.org/documentation/
- **Fortran ISO C Binding**: https://gcc.gnu.org/onlinedocs/gfortran/ISO_005fC_005fBINDING.html

## License
[Apache License 2.0](https://github.com/Qiskit/qiskit-cpp/blob/main/LICENSE.txt)