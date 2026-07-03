# nuclear_dynamics

Fortran application for nuclear subspace diagonalization using IBM Qiskit Runtime.
Given a nucleus specified by valence proton and neutron counts, it builds a
Givens-rotation ansatz circuit, samples bitstrings from IBM hardware, filters
them by exact nuclear symmetries, constructs the restricted Hamiltonian, and
diagonalizes it to obtain the subspace ground-state energy.

Changing the nucleus is a single flag change (`--protons P --neutrons N`); all
orbital registry, circuit construction, symmetry filter targets, and oracle
energies adjust automatically at runtime from `USDB.snt`.

---

## Quick start

```bash
cd build/nuclear_dynamics

# 20Ne  (2 valence protons + 2 valence neutrons, sd-shell, dim=640 oracle)
./nuclear_dynamics_driver --runtime --protons 2 --neutrons 2 --iterations 12 --shots 4096

# 22Ne  (2 valence protons + 4 valence neutrons, dim=4206 oracle)
./nuclear_dynamics_driver --runtime --protons 2 --neutrons 4 --iterations 12 --shots 4096

# 22Mg  (4 valence protons + 2 valence neutrons, dim=4206 oracle — isospin mirror of 22Ne)
./nuclear_dynamics_driver --runtime --protons 4 --neutrons 2 --iterations 12 --shots 4096
```

IBM Runtime credentials must be set as environment variables
`QISKIT_IBM_TOKEN` and `QISKIT_IBM_CHANNEL`.

---

## Classical post-processing on saved bitstrings

After a Runtime run, Fortran dumps `bitstrings_stepNN.txt` beside the binary.
To re-run only classical post-processing on those files (no QPU connection):

```bash
./nuclear_dynamics_driver --bitstrings-dir /path/to/bitstrings_dir \
    --protons 2 --neutrons 2
```

The Python baseline (in `build/benchmark/`) mirrors the same pipeline and
processes the identical saved files, enabling apples-to-apples timing comparison:

```bash
python3 build/benchmark/nuclear_dynamics_baseline.py \
    --bitstrings-dir /path/to/bitstrings_dir \
    --protons 2 --neutrons 2 --ham-workers -1
```

---

## Driver flags

| Flag | Default | Description |
|------|---------|-------------|
| `-p, --protons NUM` | 2 | valence protons (changes nucleus) |
| `-q, --neutrons NUM` | 2 | valence neutrons (changes nucleus) |
| `-n, --iterations NUM` | 15 | theta steps; stops early on convergence |
| `-s, --shots NUM` | 1024 | shots per step |
| `--theta-min/max VALUE` | 0 / π | ansatz parameter sweep range |
| `-r, --runtime` | off | submit circuits via IBM Runtime |
| `--bitstrings-dir DIR` | — | load pre-dumped bitstrings, skip QPU |
| `--start-step N` | 1 | resume sweep from step N (skip earlier steps) |

---

## Algorithm: nuclear subspace diagonalization

```
FOR each theta_i in [theta_min, theta_max]:
  1. Build ansatz: HF reference + CG-filtered Givens rotation layers (16 pairs)
  2. Submit to IBM Runtime Sampler (shots per step)
  3. filter_bitstrings: keep shots satisfying (N, Z, Mj=0, even parity)
  4. build_subspace_hamiltonian: H restricted to unique surviving Slater determinants
  5. diagonalize_exact_complex: LAPACK zheev on subspace H
  6. E_sub(theta_i) = lowest eigenvalue  [variational upper bound: E_sub >= E_oracle]
END FOR
```

The subspace dimension is typically 16–28 at 4096 shots (1–5% filter pass rate).
The subspace energy is a strict variational upper bound unconditionally.

---

## Switching nuclei

All per-nucleus quantities are derived at runtime from `USDB.snt` and
`--protons`/`--neutrons`. There is no per-nucleus configuration needed:

| What adjusts automatically | How |
|---|---|
| Number of qubits (24 for all sd-shell) | `init_registry_sd_shell(P, N)` |
| HF reference occupation | `create_hf_reference` fills lowest-SPE 0d5/2 first |
| Excitation pool size (40→16 or 52→16) | `filter_excitations_by_j(J=0)` |
| Symmetry filter targets (N, Z) | passed as `--protons`/`--neutrons` arguments |
| Oracle energy for convergence reporting | hard-coded per (P,N) in the driver |

Currently supported nuclei (all use the same 24-qubit sd-shell basis):

| Nucleus | `--protons` | `--neutrons` | Oracle E₀ (MeV) | Full-CI dim |
|---------|-------------|--------------|-----------------|-------------|
| ²⁰Ne | 2 | 2 | −39.145050266 | 640 |
| ²²Ne | 2 | 4 | −55.273041038 | 4206 |
| ²²Mg | 4 | 2 | −55.273041038 | 4206 |

Adding a new sd-shell nucleus (e.g. ²⁴Mg, 4p+4n) requires only adding its oracle
energy to the driver's lookup table and verifying the USDB.snt covers its TBMEs.
To compute the oracle energy offline, call `build_sd_hamiltonian` + `diagonalize_exact_complex`
from `exact_solver.f90` with the desired proton/neutron counts — the lowest eigenvalue is E₀.

---

## Build

```bash
cmake -B build \
  -DQISKIT_FORTRAN_ROOT=/path/to/fortran-trials/build \
  -DQISKIT_ROOT=/path/to/qiskit \
  -DQISKIT_RUNTIME_ROOT=/path/to/qiskit-ibm-runtime-c
cmake --build build
```

**Dependencies:**
- **LAPACK** — required for `diagonalize_exact_complex`. macOS: Accelerate (automatic). Linux: system LAPACK.
- **OpenMP** — for parallel H-build (`COLLAPSE(2)`) and symmetry filter. Detected automatically by CMake.
- **GSL** (optional) — `brew install gsl`. Improves CG accuracy for j > 5/2; not needed for sd-shell.
- **qiskit-ibm-runtime-c** — required for `--runtime` mode.

---

## Modules

### `nuclear_ansatz.f90`
Builds the Givens-rotation ansatz circuit.

- `create_hf_reference(circuit, n_qubits, n_protons, n_neutrons)` — X gates on lowest-SPE occupied orbitals.
- `create_ph_excitation_pool` + `filter_excitations_by_j(J=0)` — enumerates all particle-hole pairs, reduces pool to J=0-coupled pairs (40→16 for ²⁰Ne, 52→16 for ²²Ne/²²Mg).
- `add_adapt_layer(circuit, qubit_a, qubit_b, theta)` — one Givens rotation (6 gates: CX, RY, CX, RY, CX, CX).
- `finalize_ansatz(circuit)` — appends `measure_all`.

### `symmetry_filter.f90`
Post-selects bitstrings to keep only those satisfying exact nuclear quantum numbers.

- `setup_single_particle_data(n_qubits, "sd")` — initialises per-orbital 2×m_j and parity tables.
- `convert_bitstrings_to_int` — character→integer(1) conversion before the timed filter region.
- `filter_bitstrings_int(...)` — four constraints via `popcnt`/`poppar` hardware intrinsics:
  proton count N, neutron count Z, Mj=0 (weighted sum), even parity.

### `exact_solver.f90`
Subspace Hamiltonian construction and diagonalization.

- `build_subspace_hamiltonian(ms, n_p, n_n, bitstrings, kept_idx, n_kept, n_qubits, H, dim, basis_map, info)` —
  builds H restricted to the subspace spanned by symmetry-valid QPU bitstrings.
  Deduplicates first (dim ≤ n_kept). Two-body loops use `OMP COLLAPSE(2) SCHEDULE(DYNAMIC,8)`.
- `build_sd_hamiltonian(ms, n_p, n_n, H, dim, info)` —
  full Mj=0 even-parity Hamiltonian across all sd-shell states. Not called by the driver; used offline
  to compute oracle energies when adding a new nucleus (see Switching nuclei above).
- `diagonalize_exact_complex(H, dim, eigenvalues, eigenvectors, info)` —
  LAPACK zheev, JOBZ='V'. Lowest eigenvalue = variational ground-state energy.

### `clebsch_gordan.f90`
CG coefficients for angular momentum coupling.

- `init_cg_tables(j_max_2)` / `cleanup_cg_tables()` — allocate/free coefficient cache.
- `filter_excitations_by_j(pool_pairs, pool_size, J=0, ...)` — removes pairs that cannot couple to J=0; reduces circuit size.
- With GSL: uses `gsl_sf_coupling_3j` for higher accuracy.

### `usdb_reader.f90` / `orbital_registry.f90`
- `read_usdb_file("USDB.snt", ms, status)` — parses the Brown–Richter USDB interaction (6 SPEs, 158 TBMEs, ¹⁶O core).
- `init_registry_sd_shell(n_protons, n_neutrons)` — expands 3 sd-shell j-shells into 24 m-substates (12 proton + 12 neutron qubits); the qubit-to-orbital mapping is fixed by this call.

---

## Physics reference

### Orbital ordering (24 qubits, sd-shell)

| Orbital | SPE (MeV) | Proton qubits | Neutron qubits |
|---------|-----------|---------------|----------------|
| 0d3/2 | +2.1117 | 0–3   | 12–15 |
| 0d5/2 | −3.9257 | 4–9   | 16–21 |
| 1s1/2 | −3.2079 | 10–11 | 22–23 |

HF reference fills 0d5/2 first (lowest SPE), not file order.

### Variational bound

The subspace energy satisfies E_sub ≥ E_oracle unconditionally (Rayleigh-Ritz).
It is not shot-count-dependent — a single surviving bitstring gives a valid (loose) bound.
More shots → more unique Slater determinants → subspace closer to the exact ground state.
