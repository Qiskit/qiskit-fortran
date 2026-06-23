# nuclear_dynamics

Fortran oracle pipeline for post-processing quantum samples in nuclear structure.
Designed as a **supporting backend** for variational algorithms (VQE, SQD, ADAPT):
given bitstrings from any quantum sampler, filters by nuclear symmetries and
evaluates ground state energy via exact diagonalization. Can be appended to any
sampling loop that produces bitstrings.

---

## Purpose: Oracle Backend for Variational Pipelines

This is **not** a standalone algorithm. Rather, it's a **classical post-processing backend**
that any quantum sampling algorithm (VQE, SQD, ADAPT) can call after generating bitstrings:

```
Quantum Sampler (VQE/SQD/ADAPT/etc)
         | (bitstrings)
   nuclear_dynamics oracle:
     1. filter_bitstrings(N, Z, Jz, parity) — symmetry post-selection
     2. build_j2_hamiltonian_complex() — classical matrix from USDB
     3. diagonalize_exact_complex() — LAPACK zheev
         | (subspace ground state energy)
   Back to variational loop
```

This pipeline differs from existing work in three ways:

**1. Fortran-native backend with standard nuclear data.**
All classical components (symmetry filter, exact solver) are `bind(C)` Fortran. `usdb_reader` parses `.snt` format directly;
no transcription of two-body matrix elements. Reuses established Fortran nuclear physics
infrastructure.

**2. Symmetry-aware subspace diagonalization.**
`filter_bitstrings` enforces exact (N, Z, Jz, parity) constraints on each shot before
classical diagonalization. This reduces classical CPU cost and eliminates symmetry noise
from quantum samples. Applicable to any variational loop.

**3. j² oracle for validation.**
The j² pairing toy model (0d5/2², dim=15) serves as built-in ground truth. Sampled
energies from any variational algorithm can be compared against exact oracle before
scaling to full sd-shell (24 qubits). Demonstrates proof-of-concept at a controlled scale.

---

**Integration pattern:** Any quantum sampling algorithm can call this oracle in its
classical update loop. Given a batch of bitstrings, the oracle returns a symmetry-filtered,
classically-diagonalized ground state energy. This is pluggable into VQE energy evaluators,
SQD gradient computations, ADAPT operator selection, or any hybrid loop that needs subspace
ground states from noisy quantum samples.

---

## Oracle Interface

Any variational algorithm (VQE, SQD, ADAPT) calls this two-step interface:

```fortran
! Step 1: Your algorithm generates bitstrings (via Aer/Runtime)
character(c_char), allocatable :: bitstrings(:,:)

! Step 2: Call nuclear_dynamics oracle
call evaluate_subspace_energy(bitstrings, n_qubits, n_protons, n_neutrons, &
                             E_subspace, eigenvalues, ierr)

! Use E_subspace in your variational loop
```

The oracle handles:
- Symmetry post-selection by (N, Z, Jz, parity)
- Hamiltonian matrix construction from USDB
- Exact diagonalization via LAPACK
- Returns ground state energy and full spectrum

---

## Modules

### `nuclear_ansatz.f90`
Builds the quantum circuit ansatz for nuclear structure calculations.

- `create_hf_reference(circuit, n_qubits, n_protons, n_neutrons)` — initialises
  the Hartree–Fock reference state by applying X gates to the lowest occupied
  proton and neutron orbitals.
- `add_adapt_layer(circuit, qubit_a, qubit_b, theta)` — appends one
  particle-number-conserving Givens rotation between a hole and a particle orbital.
- `create_ph_excitation_pool(n_qubits, n_protons, n_neutrons, pool_size, pool_pairs)` — enumerates all valid particle-hole excitation pairs; pass the result through `filter_excitations_by_j` before circuit construction.
- `finalize_ansatz(circuit)` — adds `measure_all` after all Givens layers have
  been appended.

### `symmetry_filter.f90`
Post-selects sampled bitstrings to keep only those satisfying exact nuclear
quantum number constraints, eliminating wrong-symmetry shots before
subspace construction.

- `setup_single_particle_data(n_qubits, shell_name)` — initialises the
  per-orbital 2×m_j and parity tables for the specified shell model space
  (currently `"sd"`).
- `filter_bitstrings(bitstrings, n_samples, n_qubits, n_qp, n_qn, n_protons, n_neutrons, Mj_2target, parity_target, kept, n_kept)` — filters on proton number, neutron number, J_z projection, and parity. Expected to reduce shot waste by 5–10× compared to unfiltered SQD.
- `filter_bitstrings_parallel(...)` — same interface but distributes work across
  Fortran coarray images when compiled with `-fcoarray=lib`; falls back to
  serial if only one image.
- `init_parallel_filter()` — checks coarray availability and prints a diagnostic.

### `clebsch_gordan.f90`
Computes and caches Clebsch–Gordan coefficients for angular momentum coupling,
used to pre-screen the excitation pool to J=0-coupled pairs before circuit construction.

- `init_cg_tables(j_max_2)` — Initialize CG coefficient tables up to j = j_max_2/2
- `filter_excitations_by_j(pool_pairs, pool_size, j_target_2, filtered_pairs, filtered_size)` — Filter excitations by angular momentum coupling
- `lookup_cg(j1_2, j2_2, j_2, m1_2, m2_2, m_2)` — Look up a specific CG coefficient from the table
- `cleanup_cg_tables()` — Free the CG table memory

**Optional GSL Support**: When compiled with GSL (GNU Scientific Library),
`clebsch_gordan` uses GSL's `gsl_sf_coupling_3j` function for computing Wigner 3-j
symbols, which are then converted to CG coefficients. This provides more accurate
results for high angular momentum couplings (j > 5/2). Without GSL, the module
falls back to a built-in Racah formula implementation that works correctly for
all sd-shell cases.

### `gsl_interface.f90`
Fortran interface to GSL (GNU Scientific Library) special functions for computing
Wigner 3-j symbols and Clebsch-Gordan coefficients. This module is always compiled
but only uses GSL functions when the library is available at build time.

- `gsl_is_available()` — returns `.true.` if compiled with GSL support
- `gsl_compute_3j(...)` — computes Wigner 3-j symbol using GSL
- `gsl_compute_cg_from_3j(...)` — computes CG coefficient from 3-j symbol

---

## Test programs

The `nuclear_dynamics` directory builds four executables:

### Standalone tests (qiskit-free)
- `test_usdb_reader` — validates `USDB.snt` parser; prints model-space, SPE, TBME
- `test_exact_solver` — validates j² oracle (0d5/2²) exact diagonalization; ground state E₀ = 4.2234 MeV

### Integration tests (qiskit-dependent)
- `nuclear_dynamics` — integration test suite: HF reference + Givens layers, bitstring filtering, CG pool reduction
- `nuclear_dynamics_driver` — parameter-sweep driver: builds fixed ansatz for θ ∈ [θ_min, θ_max], filters, diagonalizes, returns E(θ)

---

## Build

The application is built from the `applications/` directory as part of the larger
Qiskit Fortran build system. From `/Users/aaryav/Documents/Qiskit/fortran-trials/applications`:

```bash
cmake -B build \
  -DQISKIT_FORTRAN_ROOT=/Users/aaryav/Documents/Qiskit/fortran-trials/build \
  -DQISKIT_ROOT=/Users/aaryav/Documents/Qiskit/fortran-trials/qiskit
cmake --build build
```

The executables are written to `build/nuclear_dynamics/`. No IBM Quantum credentials
are required — this application runs entirely on the classical host.

**Required paths:**
- `QISKIT_FORTRAN_ROOT`: path to the qiskit-fortran build directory containing
  `libqiskit-fortran.a` and the `modules/` subdirectory.
- `QISKIT_ROOT`: path to the qiskit repository after running `make c` (contains
  `dist/c/lib/libqiskit.dylib` or equivalent).

### Dependencies

**LAPACK**: Required for exact diagonalization (`exact_solver.f90`).
- On macOS: uses the Accelerate framework automatically.
- On Linux: CMake searches for and links the system LAPACK.

**GSL (GNU Scientific Library)**: Optional but recommended for improved accuracy
in Clebsch-Gordan coefficient calculations for high angular momentum couplings.

- **With GSL** (macOS):
  ```bash
  brew install gsl
  ```
  CMake automatically detects GSL during configuration.

- **With GSL** (Linux):
  ```bash
  # Debian/Ubuntu
  sudo apt-get install libgsl-dev
  
  # Fedora/RHEL
  sudo dnf install gsl-devel
  ```

- **Without GSL**: The build continues normally using built-in Racah formulas.
  All sd-shell calculations work correctly without GSL; it provides higher
  accuracy only for j > 5/2 couplings.

- **Verify GSL support**: Check the CMake output after configuration. Both
  configurations pass all tests:
  ```
  -- GSL found - version 2.8
  -- GSL libraries: /opt/homebrew/lib/libgsl.dylib;/opt/homebrew/lib/libgslcblas.dylib
  ```
  or
  ```
  -- GSL not found - building without GSL support (optional)
  ```

## Testing

Build all targets (libraries and test executables):

```bash
cmake --build build
```

Run the tests from the expected runtime directory (tests require `USDB.snt`):

```bash
cd build/nuclear_dynamics
./test_usdb_reader       # validates USDB.snt parser
./test_exact_solver      # validates j² exact diagonalization
./nuclear_dynamics       # integration test of ansatz, symmetry filter, and CG pool
```

All three tests should complete in ~3ms total and print a summary of passing assertions.

**Notes:**
- `USDB.snt` is copied into the build directory by `configure_file` in the CMakeLists.
- Test executables print per-step runtime data in scientific notation (e.g., `1.00E-03 s`).
- On platforms with coarse `system_clock` resolution, fast steps may show `0.00E+00 s`.

### Optional: Coarray parallelism

To enable distributed bitstring filtering across multiple images (requires OpenCoarrays):

```bash
# Rebuild with coarray support
cmake -B build -DCMAKE_Fortran_FLAGS="-fcoarray=lib" \
  -DQISKIT_FORTRAN_ROOT=... -DQISKIT_ROOT=...
cmake --build build
# Run with multiple images
cafrun -n 4 ./build/nuclear_dynamics/nuclear_dynamics
```

---

---

## Fortran integration points for variational loops

### Step 1: Parameter-sweep driver (`nuclear_dynamics_driver.f90`)

Demonstrates oracle integration for fixed-ansatz VQE-style sweeps:

```fortran
use nuclear_dynamics_driver, only: run_parameter_sweep

call run_parameter_sweep(n_theta, theta_min, theta_max, &
                        n_qubits, n_protons, n_neutrons, shots, &
                        energies, min_energy)
```

- Builds HF reference + parametrized Givens layers per theta
- Generates/receives bitstrings from sampler
- Filters by (N, Z) symmetry
- Constructs and diagonalizes j² Hamiltonian (LAPACK zheev)
- Returns ground state energy for each theta value

**Integration with samplers**: Replace test bitstring generation with real sampler calls:
```fortran
call sampler%run(circuit, bitstrings, shots)  ! Aer or Runtime
call filter_bitstrings(bitstrings, ...)       ! Symmetry post-selection
call diagonalize_exact_complex(H, eigenvalues, eigenvectors, info)
```

### Step 2: Coarray parallel executor (`nuclear_dynamics_parallel.f90`)

Demonstrates PGAS parallelism for parameter sweep distribution:

```fortran
! Each image evaluates one theta independently
theta_local = theta_min + (this_image() - 1) * step
energy = evaluate_oracle_at_theta(theta_local)
sync all
! Image 1 reduces and prints
```

- Requires compilation with `-fcoarray=lib` and CAF runtime (e.g., OpenCoarrays)
- Uses coarrays for inter-image communication (no explicit MPI)
- Run: `cafrun -n 8 ./nuclear_dynamics_parallel`

### Step 3: Python multiprocessing baseline (`benchmark/nuclear_dynamics_baseline.py`)

Python reference for comparative benchmarking (Fortran PGAS vs Python Process overhead):

- Serial sweep: sequential theta evaluation
- Parallel sweep: `multiprocessing.Pool(n)` for distribution
- Oracle interface: equivalent filter + diagonalize
- Timing comparison on same problem scale (8 theta values, 1024 shots)

### Bitstring extraction pattern

Generic extraction for any sampler backend:

```fortran
allocate(bitstrings(n_qubits, n_shots))
do i = 1, n_shots
  string_i = sampler_result%sample(i)  ! Fortran string from sampler
  ! Copy into c_char array for FFI
  do j = 1, n_qubits
    bitstrings(j, i) = string_i(j:j)
  end do
end do
! Pass to oracle
call filter_bitstrings(bitstrings, n_shots, n_qubits, ...)
```

This pattern works with any quantum sampler (Aer, Runtime, custom).
