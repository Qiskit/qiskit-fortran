# qiskit-fortran

Fortran ISO_C_BINDING interface to the [Qiskit C API](https://docs.quantum.ibm.com/api/qiskit-c).

Provides a two-layer binding that mirrors the architecture of
[Qiskit.jl](https://github.com/Qiskit/Qiskit.jl) and
[qiskit-cpp](https://github.com/Qiskit/qiskit-cpp):

Fortran -> API (qiskit.f90) -> FFI (qiskit_c_api.f90) -> libqiskit (C/Rust)

---

## Prerequisites

| Requirement | Minimum version | Notes |
|---|---|---|
| Fortran compiler | gfortran 9 / ifort 18 / ifx 2023 | Needs Fortran 2018 (`FINAL`, `ERROR STOP` with message, `C_LOC`) |
| CMake | 3.20 | |
| Qiskit (Python) | 2.2 | Must be installed so the cext build works |
| Rust toolchain | stable | Needed only to build the C extension |

---

## Step 1 — Build the Qiskit C extension

The shared library `libqiskit.so` (Linux) or `qiskit_cext.dll` (Windows) is
generated from the Rust crate at `qiskit/crates/cext`.

```bash
git clone https://github.com/Qiskit/qiskit.git
cd qiskit
pip install -e ".[dev]"

# Build the C extension
make c
```

After this you should have:
```
qiskit/dist/c/
├── include/
│   └── qiskit.h
└── lib/
    └── libqiskit.so
```

---

## Step 2 — Configure and build qiskit-fortran

```bash
git clone <this-repo>
cd qiskit-fortran

cmake -B build \
      -DQISKIT_ROOT=/absolute/path/to/qiskit \
      -DCMAKE_BUILD_TYPE=Release

cmake --build build -j$(nproc)
```

### CMakeLists.txt Features

The build system includes several intelligent features:

- **Automatic Python detection**: Detects the active conda environment and configures library paths
- **macOS library path handling**: Automatically resolves `libc++.1.dylib` and `libpython3.12.dylib` dependencies
- **Rpath configuration**: Sets proper runtime library search paths for the test executable
- **CTest integration**: Configures test environment with correct `DYLD_LIBRARY_PATH` on macOS
- **Multi-compiler support**: Works with gfortran, Intel ifx, and Cray compilers

### Build Variants

For a Debug build with runtime bounds checking (gfortran):
```bash
cmake -B build-debug \
      -DQISKIT_ROOT=/absolute/path/to/qiskit \
      -DCMAKE_BUILD_TYPE=Debug
cmake --build build-debug -j$(nproc)
```

For Intel oneAPI (ifx):
```bash
FC=ifx cmake -B build-intel \
             -DQISKIT_ROOT=/absolute/path/to/qiskit \
             -DCMAKE_BUILD_TYPE=Release
cmake --build build-intel -j$(nproc)
```

---

## Step 3 — Run the tests

### Using CTest (recommended)

The CMakeLists.txt automatically configures the test environment with proper library paths:

```bash
# Run tests
cd build && make test
# or
make run_test
```

### Cross-Platform Library Path Configuration

The CMakeLists.txt includes automatic, cross-platform library path detection:
- **Detects Python library path** dynamically from conda environment (`$CONDA_PREFIX`) or system Python
- **Platform-aware environment variables**: `DYLD_LIBRARY_PATH` (macOS) or `LD_LIBRARY_PATH` (Linux)
- **Dynamic path resolution**: Automatically includes system libraries and Python libraries
- **No hardcoded paths**: All library paths are detected at configure time
- **Resolves dependencies** for `libc++.1.dylib` and `libpython3.12.dylib` required by the Rust-built Qiskit library

Both `make test` and `make run_test` automatically set the correct library paths for your platform.

Expected output (all passing):
```
--- Construction ---
  [PASS] num_qubits == 5
  [PASS] num_clbits == 5
  [PASS] empty circuit has 0 instructions
  [PASS] re-init num_qubits == 3
  ...

--- Large circuit (100 qubits) ---
  [PASS] 100×H: 100 instructions
  [PASS] 100×H + 50×CX: 150 instructions
  [PASS] after 100×Rz: 250 instructions
  [PASS] after measure_all: 350 instructions

========================================
  PASS : 80
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
find_package(qiskit_fortran REQUIRED
  HINTS /path/to/qiskit-fortran/build)

add_executable(my_hpc_code main.f90)
target_link_libraries(my_hpc_code PRIVATE qiskit_fortran::qiskit_fortran)
```

### Manual compilation (gfortran)

```bash
QISKIT_ROOT=/path/to/qiskit
BUILD=/path/to/qiskit-fortran/build

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

### Array handling for parallelization

The `qiskit_arrays` module provides `QubitArray` and `ParamArray` types with contiguous allocatable components. These arrays are used internally by all gate operations and can be used directly in HPC workflows.

**Key properties:**
- **Contiguous memory**: `ALLOCATABLE` guarantees stride-1 layout — enables SIMD vectorization and direct `MPI_Send` without `MPI_Pack`
- **No aliasing**: Lack of `POINTER` attribute allows compiler to assume independence between arrays: permits loop hoisting and instruction reordering
- **Single ABI boundary**: All Fortran→C conversions (`c_loc`) happen in one place (`to_c` functions), making the codebase auditable

**Example — MPI circuit distribution:**
```fortran
use qiskit
type(QubitArray) :: qa
qa = q(0, 1, 2)  ! Contiguous allocatable
call MPI_Send(qa%v, size(qa%v), MPI_INT32_T, dest, tag, comm, ierr)
```

The `q()` and `p()` constructors are exported by `use qiskit` for advanced use cases. Typical gate calls use them internally and require no explicit array handling.

---

## Memory safety checklist

| Concern | How it is addressed |
|---|---|
| Double-free | `FINAL` sets `ptr = c_null_ptr` after free; `c_associated` guard in `init` |
| Leak on re-init | `init` calls `qk_circuit_free` before allocating a new circuit |
| Leak on scope exit | `FINAL` destructor fires unconditionally |
| NULL dereference | Every gate method calls `check_rc`; a null circuit pointer produces `QkExitCode_NullPointerError` from the C side |
| Array out-of-bounds | Qubit index validation is delegated to the C API (`QkExitCode_IndexError`) |

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
PROJECT_NAME           = "qiskit-fortran"
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
