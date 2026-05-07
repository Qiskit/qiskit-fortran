# qiskit-f90

Fortran ISO_C_BINDING interface to the [Qiskit C API](https://docs.quantum.ibm.com/api/qiskit-c).

Provides a two-layer binding that mirrors the architecture of
[Qiskit.jl](https://github.com/Qiskit/Qiskit.jl) and
[qiskit-cpp](https://github.com/Qiskit/qiskit-cpp):

qiskit.f90 -> qiskit_circuit.f90 -> qiskit_c_api_circuit.f90 -> libqiskit (C/Rust)

---

## Prerequisites

| Requirement | Minimum version | Notes |
|---|---|---|
| Platform | macOS 13+ | Tested; Linux (glibc) should work but untested; Windows not supported |
| Fortran compiler | gfortran 9+ | Needs Fortran 2018 (`FINAL`, `ERROR STOP` with message, `C_LOC`); ifort/ifx and Cray untested, contributions welcome |
| CMake | 3.20 | |
| Qiskit (Python) | 2.2 | Must be installed so the cext build works |
| Rust toolchain | stable | Needed only to build the C extension |

---

## Step 1 — Build the Qiskit C extension

The shared library is generated from the Rust crate at `qiskit/crates/cext`.
CMake automatically resolves `libqiskit.so` (Linux) or `libqiskit.dylib` (macOS).

```bash
git clone https://github.com/Qiskit/qiskit.git
cd qiskit
pip install -e .

# Build the C extension
make c
```

After this you should have:
```
qiskit/dist/c/
├── include/
│   └── qiskit.h
└── lib/
    └── libqiskit.so  # or libqiskit.dylib
```

---

## Step 2 — Configure and build qiskit-f90

```bash
git clone <this-repo>
cd qiskit-f90

cmake -B build \
      -DQISKIT_ROOT=/absolute/path/to/qiskit \
      -DCMAKE_BUILD_TYPE=Release

cmake --build build -j$(nproc)
```

### CMakeLists.txt Features

The build system includes several intelligent features:

- **RPATH configuration**: embeds runtime library search paths directly into the test binary so no environment variables are needed at runtime
- **Automatic Python detection**: locates the active conda environment or system Python to resolve the `libpython` transitive dependency of `libqiskit`
- **Multi-compiler support**: gfortran validated; other compilers untested

### Build Variants

For a Debug build with runtime bounds checking:
```bash
cmake -B build-debug \
      -DQISKIT_ROOT=/absolute/path/to/qiskit \
      -DCMAKE_BUILD_TYPE=Debug
cmake --build build-debug -j$(nproc)
```

### Build Options: Manual vs SWIG Bindings

The project supports two C API binding methods:

**Manual bindings (default)**: Hand-written interfaces covering essential circuit operations. Minimal dependencies, readable code, fast builds.

**SWIG bindings**: Auto-generated, directly from C headers providing complete API coverage. Pre-generated bindings are included; SWIG is only needed to regenerate them.

```bash
# Build with SWIG bindings (uses pre-generated files)
cmake -B build-swig \
      -DQISKIT_ROOT=/path/to/qiskit \
      -DUSE_SWIG_BINDINGS=ON
cmake --build build-swig

# Test (same test suite works for both modes)
cd build-swig && ./test_qiskit
```

To regenerate bindings (requires [SWIG-Fortran](https://github.com/swig-fortran/swig)):
```bash
cd fortran-swig
swig -fortran -c++ qiskit.i
python generate_bindings.py
```

The high-level API (`QuantumCircuit` type, etc.) works identically with both backends.

---

## Step 3 — Run the tests

### Using CTest (recommended)

Runtime library paths are embedded via RPATH at build time. No environment variable setup is required.

```bash
# Run tests
cd build && make test
# or
make run_test
```

**Linux note:** The same RPATH mechanism applies (`DT_RUNPATH` in the ELF binary). If you build outside CMake or need to override, `export LD_LIBRARY_PATH=/path/to/dist/c/lib` is sufficient, matching Qiskit's own install guide.

Expected output (all passing):
```
--- Gate enum constants verification ---
  [PASS] QkGate_GlobalPhase == 0
  [PASS] QkGate_H == 1
  ...
  [PASS] QkGate_CCX == 45

--- Construction ---
  [PASS] num_qubits == 5
  [PASS] num_clbits == 5
  [PASS] empty circuit has 0 instructions
  ...

--- Bell state ---
  [PASS] after H: 1 instruction
  [PASS] after CX: 2 instructions
  ...

--- Large circuit (100 qubits) ---
  [PASS] 100×H: 100 instructions
  [PASS] 100×H + 50×CX: 150 instructions
  [PASS] after 100×Rz: 250 instructions
  [PASS] after measure_all: 350 instructions

========================================
  PASS : 90
  FAIL : 0
========================================
```

The test binary exits 0 on all-pass, non-zero (via `error stop`) on any
failure, so it integrates cleanly with CTest and CI pipelines.

---

## Step 4 — Use in your own program

Link against the static library and add the module directory to your include
path:

### CMake (recommended)

```cmake
find_package(qiskit-f90 REQUIRED
  HINTS /path/to/qiskit-f90/build)

add_executable(my_hpc_code main.f90)
target_link_libraries(my_hpc_code PRIVATE qiskit-f90::qiskit-f90)
```

### Manual compilation (gfortran)

```bash
QISKIT_ROOT=/path/to/qiskit
BUILD=/path/to/qiskit-f90/build

gfortran -std=f2018 -O3 \
  -I${BUILD}/modules \
  main.f90 \
  -L${BUILD} -lqiskit_fortran \
  -L${QISKIT_ROOT}/dist/c/lib -lqiskit \
  -Wl,-rpath,${QISKIT_ROOT}/dist/c/lib \
  -o my_program
```

---

## Usage guide

### Qubit indexing

All qubit and classical bit indices are **0-based**, matching the C API and
Python API.

### Object lifecycle

`QuantumCircuit` uses a `FINAL` destructor — there is **no** `free()` call to
remember.  The circuit is released automatically when the variable goes out of
scope.
Re-initialisation is safe.

### Direct C dispatch

Gate operations use direct C pointer dispatch without intermediate array allocations. Qubit indices and parameters are passed as stack-allocated arrays directly to the C API via `c_loc()`.

---

## Memory Safety checklist

| Concern | How it is addressed |
|---|---|
| Double-free | `FINAL` sets `ptr = c_null_ptr` after free; `c_associated` guard in `init` |
| Leak on re-init | `init` calls `qk_circuit_free` before allocating a new circuit |
| Leak on scope exit | `FINAL` destructor fires unconditionally |
| Error Handling | Every gate method calls `check_rc`; a method to check for relevant C-API exit code and raise a fortran native error accordingly |

---

## Documentation

API documentation is generated using [Doxygen](https://www.doxygen.nl/), following the same approach as [qiskit-cpp](https://github.com/Qiskit/qiskit-cpp).

### Setup

Generate a default configuration:
```bash
doxygen -g Doxyfile
```

Edit `Doxyfile` to set:
```
PROJECT_NAME           = "qiskit-f90"
INPUT                  = src/
RECURSIVE              = YES
OPTIMIZE_FOR_FORTRAN   = YES
EXTENSION_MAPPING      = f90=FortranFree F90=FortranFree
EXTRACT_ALL            = NO
EXTRACT_PRIVATE        = NO
GENERATE_HTML          = YES
OUTPUT_DIRECTORY       = docs/
```

Build documentation:
```bash
doxygen
```

Output is in `docs/html/index.html`. The high-level API is documented with Fortran-specific usage patterns. The FFI layer (`qiskit_c_api*.f90`) defers to the [Qiskit C API reference](https://docs.quantum.ibm.com/api/qiskit-c).

---
