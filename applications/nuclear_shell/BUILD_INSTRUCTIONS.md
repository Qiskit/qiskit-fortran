# Build Instructions

End-to-end guide for building and running the nuclear shell model driver, from a
fresh machine with no prior Qiskit or Fortran setup.

---

## Prerequisites summary

| Requirement | Version | Notes |
|---|---|---|
| Fortran compiler | gfortran 11+ or flang 22+ | Both tested on macOS arm64 |
| CMake | ≥ 3.20 | |
| Rust toolchain | stable | To build the Qiskit C extension |
| Qiskit (Python) | 2.4 | Must be installed so the cext build works |
| LAPACK | any | macOS: Accelerate (automatic); Linux: `liblapack-dev` |

**Optional:**

| Requirement | Purpose | Impact if absent |
|---|---|---|
| OpenMP | Parallel Hamiltonian build | Serial fallback, slower for large subspaces |
| GSL | Clebsch-Gordan coefficients for j > 5/2 | Built-in fallback covers sd-shell (j ≤ 5/2) |
| qiskit-ibm-runtime-c | `--runtime` mode (IBM hardware) | Test mode still works fully without it |

---

## macOS

### 1. Install a Fortran compiler and CMake

Both gfortran and flang work. Pick one:

```bash
# gfortran (via GCC)  -  simpler, recommended
brew install gcc cmake

# or flang (LLVM-based)
brew install flang cmake
```

Verify:
```bash
gfortran --version   # GNU Fortran 11+
flang --version      # LLVM Fortran 20+
cmake --version      # 3.20+
```

### 2. Install the Rust toolchain

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# restart your shell or run: source "$HOME/.cargo/env"
```

### 3. Install Qiskit (Python)

```bash
pip install qiskit
```

### 4. Build the Qiskit C extension

```bash
git clone https://github.com/Qiskit/qiskit.git
cd qiskit
make c
```

After this you should have:
```
qiskit/dist/c/
├── include/
│   └── qiskit.h
└── lib/
    └── libqiskit.dylib
```

### 5. Build qiskit-fortran

The application uses `qiskit_target` and `qiskit_transpiler`, which are only
available through the SWIG-generated bindings. You must pass `-DUSE_SWIG_BINDINGS=ON`.

```bash
git clone https://github.com/Qiskit/qiskit-fortran.git
cd qiskit-fortran

cmake -B build \
      -DQISKIT_ROOT=/absolute/path/to/qiskit \
      -DUSE_SWIG_BINDINGS=ON \
      -DCMAKE_BUILD_TYPE=Release

cmake --build build -j$(sysctl -n hw.ncpu)
```

This produces `build/libqiskit-fortran.a` and `.mod` files under `build/modules/`,
including the SWIG-generated `qiskit_swigf.mod` required by the transpiler and
target modules.

**If you want `--runtime` mode (IBM Quantum Platform):** the `qiskit_runtime` module is
only built when you ask for it, so do step 6 *first*, then configure with two
extra flags:

```bash
cmake -B build \
      -DQISKIT_ROOT=/absolute/path/to/qiskit \
      -DUSE_SWIG_BINDINGS=ON \
      -DQISKIT_FORTRAN_RUNTIME=ON \
      -DQISKIT_RUNTIME_ROOT=/absolute/path/to/qiskit-ibm-runtime-c \
      -DCMAKE_BUILD_TYPE=Release
```

### 6. (Optional) Build qiskit-ibm-runtime-c

Required only for `--runtime` mode (submitting to IBM hardware). Build this
*before* step 5 if you want runtime support, since step 5 needs
`-DQISKIT_RUNTIME_ROOT` to point at the result.

```bash
gh repo clone Qiskit/qiskit-ibm-runtime-c
cd qiskit-ibm-runtime-c
mkdir build && cd build
cmake ..
make
```

This produces `build/cargo/debug/libqiskit_ibm_runtime.dylib`.

### 7. Install optional dependencies

```bash
# OpenMP  -  needed by Homebrew gfortran/flang separately
brew install libomp

# GSL  -  only needed for pf-shell (j > 5/2); skip for sd-shell
brew install gsl
```

### 8. Configure and build nuclear_shell

From the `applications/` directory of this repo:

Configure step 8 to match step 5. If step 5 was built without
`-DQISKIT_FORTRAN_RUNTIME=ON`, use the first form; `--runtime` will be
unavailable but everything else works.

```bash
# Without runtime support:
cmake -B build \
  -DQISKIT_FORTRAN_ROOT=/path/to/qiskit-fortran/build \
  -DQISKIT_ROOT=/path/to/qiskit \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build --target nuclear_shell_driver
```

With IBM Runtime support (`--runtime` mode) — requires that step 5 was
configured with `-DQISKIT_FORTRAN_RUNTIME=ON`:

```bash
cmake -B build \
  -DQISKIT_FORTRAN_ROOT=/path/to/qiskit-fortran/build \
  -DQISKIT_ROOT=/path/to/qiskit \
  -DQISKIT_RUNTIME_ROOT=/path/to/qiskit-ibm-runtime-c \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build --target nuclear_shell_driver
```

The CMake build system detects LAPACK (Accelerate), OpenMP, and GSL automatically
on macOS. No extra flags are needed. Configure prints which optional features
were enabled, e.g.:

```
-- GSL found - version 2.8
-- qiskit_runtime module + library found  -  --runtime mode enabled
```

or, for a build without runtime support:

```
-- libqiskit_ibm_runtime not found (pass -DQISKIT_RUNTIME_ROOT=... to get it)
-- Building nuclear_shell_driver without --runtime support  -  test mode and --bitstrings-dir path are unaffected
```

### 9. Run (test mode  -  no credentials needed)

```bash
cd build/nuclear_shell
./nuclear_shell_driver --protons 2 --neutrons 2 --circuits 3 --shots 256
```

### 10. Run on IBM hardware

Configure credentials first (see [IBM Quantum Configuration](#ibm-quantum-configuration) below), then:

```bash
./nuclear_shell_driver --runtime --protons 2 --neutrons 2 --circuits 11 --shots 4096
```

---

## Linux (Ubuntu/Debian)

### 1. Install compiler, CMake, and LAPACK

```bash
sudo apt update
sudo apt install -y gfortran cmake make git curl liblapack-dev libblas-dev
```

For OpenMP (usually already included with gfortran):
```bash
sudo apt install -y libgomp1
```

For GSL (optional, only needed for pf-shell):
```bash
sudo apt install -y libgsl-dev
```

### 2. Install the Rust toolchain

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

### 3. Install Qiskit (Python)

```bash
pip install qiskit
```

### 4–6. Build Qiskit C extension, qiskit-fortran, qiskit-ibm-runtime-c

Same as macOS steps 4–6 above. Substitute `libqiskit.so` for `.dylib` where noted.
The `-DUSE_SWIG_BINDINGS=ON` flag is required for qiskit-fortran on Linux as well.

### 7. Configure and build nuclear_shell

```bash
cmake -B build \
  -DQISKIT_FORTRAN_ROOT=/path/to/qiskit-fortran/build \
  -DQISKIT_ROOT=/path/to/qiskit \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build --target nuclear_shell_driver
```

With runtime support, add `-DQISKIT_RUNTIME_ROOT=...` as above.

### 8. Run

```bash
cd build/nuclear_shell
./nuclear_shell_driver --protons 2 --neutrons 2 --circuits 3 --shots 256
```

If you see library-not-found errors at runtime:
```bash
export LD_LIBRARY_PATH="/path/to/qiskit/dist/c/lib:$LD_LIBRARY_PATH"
```

---

## IBM Quantum Configuration

Required only for `--runtime` mode.

The simplest way to write a credentials file `qiskit-ibm-runtime-c` can read is
to let Qiskit write it:

```bash
pip install qiskit-ibm-runtime
python3 -c 'from qiskit_ibm_runtime import QiskitRuntimeService; \
QiskitRuntimeService.save_account(channel="ibm_quantum_platform", \
token="YOUR_API_KEY", instance="YOUR_CRN_OR_INSTANCE", set_as_default=True)'
```

That produces `~/.qiskit/qiskit-ibm.json` with a `default-ibm-quantum-platform`
entry, which is one of the three key names the client looks for:

```json
{
  "default-ibm-quantum-platform": {
    "channel": "ibm_quantum_platform",
    "token": "YOUR_API_KEY",
    "instance": "YOUR_CRN_OR_INSTANCE",
    "url": "https://quantum.cloud.ibm.com/api/v1"
  }
}
```

Get an API key from [IBM Quantum Platform](https://quantum.cloud.ibm.com/).

The driver loads credentials automatically via `service%connect()`  -  no token
ever appears in source code or command-line flags.

---

## CMake options reference

| Option | Default | Description |
|---|---|---|
| `QISKIT_FORTRAN_ROOT` | (required) | Path to qiskit-fortran build directory |
| `QISKIT_ROOT` | (required) | Path to Qiskit repo after `make c` |
| `QISKIT_RUNTIME_ROOT` | (optional) | Path to qiskit-ibm-runtime-c for `--runtime` mode |
| `QISKIT_FORTRAN_RUNTIME` | `OFF` | **qiskit-fortran build only** (step 5). Builds the `qiskit_runtime` module that `--runtime` needs. |
| `CMAKE_BUILD_TYPE` | (none) | `Release` for `-O3`, `Debug` for `-g -O0` |

To use a specific compiler explicitly:
```bash
cmake -B build -DCMAKE_Fortran_COMPILER=gfortran ...
# or
cmake -B build -DCMAKE_Fortran_COMPILER=flang ...
```

---

## Build targets

| Target | Description |
|---|---|
| `nuclear_shell_driver` | Main executable |
| `nuclear_shell_parallel` | PGAS coarray variant (built only if coarray support detected) |

---

## Building `nuclear_shell_parallel` (coarray PGAS post-processing)

`nuclear_shell_parallel` is the classical post-processing stage that runs
after the QPU step. It reads the `bitstrings_stepNN.txt` files written by
`--runtime` mode and distributes the filter → Hamiltonian-build →
diagonalisation work across coarray images, one image per partition of step
files. Image 1 gathers the per-image minimum energies and reports the global
variational minimum.

### Compiler requirement

The coarray parallel model requires a compiler that supports
`-fcoarray=lib`. In practice on this platform, that means **gfortran**, not
flang. LLVM flang (22+) does not implement `-fcoarray`  -  CMake detects this
and silently skips the target when flang is the active compiler. The driver
(`nuclear_shell_driver`) continues to build with either compiler; only the
parallel post-processor is affected.

You also need a coarray runtime library to link against:

- **Single-image / development**  -  `libcaf_single` ships with Homebrew GCC
  at no extra install cost.
- **Multi-image production**  -  OpenCoarrays (`libcaf_mpi`) via
  `brew install opencoarrays` on macOS or `apt install opencoarrays-*` on
  Ubuntu; this also installs the `cafrun` launcher.

### Configuring and building

Pass `gfortran` explicitly so CMake detects coarray support and includes the
target:

```bash
# From applications/
cmake -B build \
  -DCMAKE_Fortran_COMPILER=gfortran \
  -DQISKIT_FORTRAN_ROOT=/path/to/qiskit-fortran/build \
  -DQISKIT_ROOT=/path/to/qiskit \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build --target nuclear_shell_parallel
```

Configure prints:

```
-- Performing Test NUCLEAR_SHELL_HAVE_COARRAYS - Success
-- Coarray support detected  -  building nuclear_shell_parallel
```

Under flang the probe fails and the target is skipped, which is expected  -
flang 22 does not implement `-fcoarray`.

### Compiling the parallel source standalone

When the main CMake build used flang (the default on macOS), gfortran cannot
read the resulting `.mod` files  -  they are compiler-specific binary formats.
The correct approach is to compile the physics sources from scratch with
gfortran into a scratch directory, then link:

```bash
# From the repo root (applications/nuclear_shell)
ND=$(pwd)
mkdir -p /tmp/nd_coarray && cd /tmp/nd_coarray

# Step 1  -  compile physics sources with gfortran (-cpp for preprocessor directives)
gfortran -O2 -cpp -fcoarray=lib -J. -c $ND/physics/usdb_reader.f90
gfortran -O2 -cpp -fcoarray=lib -J. -c $ND/physics/orbital_registry.f90
gfortran -O2 -cpp -fcoarray=lib -J. -c $ND/physics/gsl_interface.f90
gfortran -O2 -cpp -fcoarray=lib -J. -c $ND/physics/clebsch_gordan.f90
gfortran -O2 -cpp -fcoarray=lib -J. -c $ND/physics/exact_solver.f90
gfortran -O2 -cpp -fcoarray=lib -J. -c $ND/physics/symmetry_filter.f90

# Step 2  -  compile the parallel program
gfortran -O2 -cpp -fcoarray=lib -J. -I. \
  -c $ND/circuit/nuclear_shell_parallel.f90 \
  -o nuclear_shell_parallel.o

# Step 3  -  link
CAF_DIR=$(dirname $(gfortran -print-file-name=libcaf_single.a))
gfortran -fcoarray=lib \
  nuclear_shell_parallel.o \
  usdb_reader.o orbital_registry.o gsl_interface.o clebsch_gordan.o \
  exact_solver.o symmetry_filter.o \
  -L"$CAF_DIR" -lcaf_single \
  -Wl,-framework,Accelerate \     # macOS; on Linux: -llapack -lblas
  -o nuclear_shell_parallel

cp nuclear_shell_parallel /path/to/applications/build/nuclear_shell/
```

### Running

First generate step files. Use the driver in test mode with `--save-bitstrings`:

```bash
cd build/nuclear_shell
./nuclear_shell_driver --protons 2 --neutrons 2 --circuits 2 --shots 256 \
  --save-bitstrings
# Writes bitstrings_step01.txt and bitstrings_step02.txt in the current directory.
```

Then run the parallel binary in the same directory (it looks for
`bitstrings_stepNN.txt` relative to CWD by default):

```bash
# Single-image (development / verification, no cafrun needed):
./nuclear_shell_parallel --steps 2 --protons 2 --neutrons 2
```

This matches exactly the output of:
```bash
./nuclear_shell_driver --bitstrings-dir . --protons 2 --neutrons 2 --mode per-step
```

confirming the two paths are equivalent.

```bash
# Multi-image with OpenCoarrays cafrun launcher (requires brew install opencoarrays):
cafrun -n 4 ./nuclear_shell_parallel \
  --steps 11 --protons 2 --neutrons 2 \
  --bitstrings-dir /path/to/bitstrings
```

Each image processes steps `me, me+n_images, me+2*n_images, …` (1-based).
With 4 images and 11 steps, image 1 owns steps 1, 5, 9; image 2 owns 2, 6,
10; and so on. Image 1 gathers all per-image results after a `sync all` and
reports the global energy minimum.

---

## Troubleshooting

### `gfortran: command not found`

Install via Homebrew: `brew install gcc`. Confirm with `which gfortran-15` (or
whatever version Homebrew installed). Pass the path explicitly:
```bash
cmake -B build -DCMAKE_Fortran_COMPILER=$(which gfortran-15) ...
```

### Library not found at runtime (macOS)

CMake sets `BUILD_RPATH` automatically. If you still see `dylib not loaded`:
```bash
export DYLD_LIBRARY_PATH="/path/to/qiskit/dist/c/lib:$DYLD_LIBRARY_PATH"
```

### `zheev_` not found at link time

LAPACK is not being found. On macOS, CMake links Accelerate automatically  -  if
this fails, verify the SDK is present (`xcrun --show-sdk-path`). On Linux install
`liblapack-dev` and re-run cmake with `-DLAPACK_ROOT=/usr`.

### OpenMP not detected (macOS + gfortran)

Homebrew GCC ships with its own `libgomp`. If CMake doesn't find it, pass the
library path explicitly:
```bash
cmake -B build -DOpenMP_Fortran_FLAGS="-fopenmp" \
               -DOpenMP_Fortran_LIB_NAMES="gomp" \
               -DOpenMP_gomp_LIBRARY=$(gfortran -print-file-name=libgomp.dylib) ...
```

### `USDB.snt: No such file or directory` at runtime

CMake copies the file to the build directory automatically. Always run the driver
from `build/nuclear_shell/` where `USDB.snt` is placed. If running from
elsewhere:
```bash
ln -sf /path/to/applications/nuclear_shell/data/USDB.snt ./USDB.snt
```

### `Cannot open module file 'qiskit_runtime.mod'`

The qiskit-fortran build in step 5 was configured without
`-DQISKIT_FORTRAN_RUNTIME=ON`, so the module does not exist. Either rebuild
qiskit-fortran with that flag (see step 5) or reconfigure `applications/`
without `-DQISKIT_RUNTIME_ROOT`, which compiles the `--runtime` path out.

### Clean build

```bash
rm -rf applications/build
# then re-run cmake from applications/
```
