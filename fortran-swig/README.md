# Qiskit Fortran Bindings via SWIG

This directory contains a Python-based pipeline that generates clean Fortran bindings from the Qiskit C API. We use SWIG as a parsing tool to extract type information, then generate our own canonical `bind(C)` interfaces that call the C library directly.

## SWIG-Based Generation Tutorial

Here's how to regenerate the bindings from scratch:

**Step 1: Install SWIG-Fortran**

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

**Step 2: Run SWIG to parse the C headers**

```bash
cd fortran-swig
~/.local/bin/swig -fortran -c++ -I../qiskit/dist/c/include qiskit.i
```

This generates `qiskit_swig_api.f90` and `qiskit_wrap.cxx`. We only use the `.f90` file as a schema—the C++ wrapper is discarded.

**Step 3: Generate canonical bindings**

```bash
python generate_bindings.py
```

This reads `qiskit_swig_api.f90`, extracts type information, and writes `qiskit_c_api.f90`—a clean module with proper `bind(C)` interfaces that link directly to `libqiskit_c`. No SWIG runtime needed.

**Step 4: Use the bindings**

The generated `qiskit_c_api.f90` is a drop-in replacement for handwritten interfaces. Your high-level Fortran code (like `qiskit_circuit.f90`) works identically whether you use generated or handwritten bindings.

## Architecture & Design Decisions

We use SWIG as a C header parser, not as a binding generator. SWIG's Fortran output is verbose and includes a C++ wrapper layer we don't need. Instead, we parse the SWIG-generated Fortran module to extract function signatures and type information, then emit our own clean `bind(C)` interfaces.

The trade-off: SWIG gives us comprehensive coverage of the entire C API automatically, but its output isn't production-ready. Our Python scripts (`generate_bindings.py` and `interface_generator.py`) transform that verbose output into idiomatic Fortran that calls the C library directly. Our generated code is clean, idiomatic Fortran that matches the handwritten style. We get SWIG's comprehensive API coverage without its runtime overhead or verbose syntax.

**SWIG's value:** SWIG does the hard work of C-to-Fortran type mapping—handling preprocessor macros, typedefs, and struct layouts. Our Python parses SWIG's Fortran output (not C headers), so we leverage SWIG's type translation.

We commit the pre-generated files (`./qiskit_c_api.f90`) so users don't need SWIG installed. The handwritten bindings in `../src/` remain the default; these generated bindings are an alternative for users who need full API coverage.

This approach lets us maintain a single source of truth (the C headers) while keeping the Fortran bindings readable and efficient. When the C API changes, we regenerate.

## Future Directions

**Modularization**: Right now everything goes into `qiskit_c_api.f90`. We could split this into logical modules (`qiskit_c_api_circuit.f90`, `qiskit_c_api_dag.f90`, etc.) to match the handwritten structure. The routing logic in `generate_bindings.py` already partially supports this, update `_derive_module_name()`.

**Documentation pipeline**: We could auto-generate Fortran documentation from C header comments. The C API has docstrings; we're just not extracting them yet. A simple regex pass during generation would preserve that information.

**Type safety improvements**: The `TypeClassifier` in `interface_generator.py` uses heuristics (parameter names, companion parameters) to infer array vs. scalar types. We could parse C headers directly with `libclang` to get precise type information, though this would require reimplementing SWIG's C->Fortran type mapping.

**CI/CD integration**: Add a GitHub Action that regenerates bindings on C API changes and opens a PR if differences are detected. This would catch API drift early and keep the bindings in sync automatically.

## Maintenance

When the Qiskit C API changes:

1. Regenerate SWIG output: `swig -fortran -c++ qiskit.i`
2. Run generator: `python generate_bindings.py`
3. Commit updated `qiskit_c_api.f90`

The Python scripts handle type inference and interface generation automatically. No manual editing of Fortran code required.

## Resources

- **SWIG-Fortran**: https://github.com/swig-fortran/swig
- **Qiskit C API**: https://qiskit.org/documentation/
- **Fortran ISO C Binding**: https://gcc.gnu.org/onlinedocs/gfortran/ISO_005fC_005fBINDING.html