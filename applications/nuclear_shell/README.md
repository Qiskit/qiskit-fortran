# nuclear_shell

> **Status: under active development.** APIs, file formats, and default
> parameters may change. Contributions, bug reports, and feedback are welcome --
> please open an issue or pull request on the repository.

Fortran application for nuclear diagonalization using IBM Qiskit Runtime.
Given a nucleus specified by valence proton and neutron counts, it builds a
magnitude-ranked circuit ensemble with both single and double excitation
operators, samples bitstrings from IBM hardware, filters them by exact nuclear
symmetries, constructs the restricted Hamiltonian, and diagonalizes it to
obtain the subspace ground-state energy.

Changing the nucleus is a single flag change (`--protons P --neutrons N`); all
orbital registry, circuit construction, symmetry filter targets, and oracle
energies adjust automatically at runtime from the loaded `.snt` interaction file.

---

## IBM Quantum Configuration

Required only for `--runtime` mode. Skip if you only want to run in test mode
(see [Test mode  -  no credentials needed](#test-mode--no-credentials-needed) below).

Let Qiskit write the credentials file:

```bash
pip install qiskit-ibm-runtime
python3 -c 'from qiskit_ibm_runtime import QiskitRuntimeService; \
QiskitRuntimeService.save_account(channel="ibm_quantum_platform", \
token="YOUR_API_KEY", instance="YOUR_CRN_OR_INSTANCE", set_as_default=True)'
```

This writes `~/.qiskit/qiskit-ibm.json` with a `default-ibm-quantum-platform`
entry. `qiskit-ibm-runtime-c` reads that file and accepts only the account keys
`default`, `default-ibm-quantum-platform`, and `default-ibm-cloud`. The token is
authenticated against IBM Cloud IAM, so it must be an IBM Quantum Platform API
key from [quantum.cloud.ibm.com](https://quantum.cloud.ibm.com/).

The driver loads credentials automatically via `service%connect()`  -  no token
value ever appears in source code or command-line flags.

---

## Test mode  -  no credentials needed

The driver has two modes:

| Mode | Flag | Requires credentials? |
|---|---|---|
| Test (simulated) | (default, no flag) | No |
| IBM Runtime | `--runtime` | Yes |

Without `--runtime`, each circuit's bitstrings are generated from the
Hartree-Fock reference determinant, and the full classical pipeline
(symmetry filter → Hamiltonian build → diagonalization) runs locally.
This is a complete run  -  all `RESULT` lines are printed, including the
ground-state energy.

**Example test-mode run (20Ne, 3 circuits, 256 shots):**

```bash
cd build/nuclear_shell
./nuclear_shell_driver --protons 2 --neutrons 2 --circuits 3 --shots 256
```

Expected output (abridged):

```
==========================================
Nuclear Shell Model Circuit Ensemble
Mode: Test (simulated bitstrings)
==========================================
  Nucleus        : 2p + 2n
  Circuits       :    3
  Shots/circuit  :   256
  Pairs/circuit  :   16 (ranked partition)

  Singles  -  raw:   40  CG-filtered:   16
  Doubles  -  raw:  490  CG-filtered:   86
  ...
  Pooled bitstrings :    768 (from  3 circuits)
  Filter: kept   768 /    768 pooled shots
  Subspace dim  :     1
  E1            :      -29.360326984 MeV
RESULT  energy_level01      -29.360326984 MeV
RESULT  subspace_dim                  1 states
RESULT  pooled_kept                 768 shots
```

In test mode every shot is the Hartree-Fock reference determinant, so the
subspace collapses to dim=1 and E1 is just the Hartree-Fock diagonal element
(-29.360327 MeV for 20Ne). The full-CI (oracle) ground state for 20Ne in the
USDA sd-shell interaction is **−41.184967 MeV** (dim=640); `--runtime` mode
samples diverse determinants from the circuit ensemble and approaches the oracle
as circuits × shots increases.

---

## Quick start

Build everything with the script in the repository root (see
[BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) for the manual steps):

```bash
./build.sh --help       # options, and the packages to install
./build.sh              # or --no-runtime to skip the IBM Runtime client
```

Then run it  -  binaries live in `applications/build/nuclear_shell/`, with
`USDB.snt` staged alongside:

```bash
cd applications/build/nuclear_shell

./nuclear_shell_driver --protons 2 --neutrons 2

# 20Ne  (2 valence protons + 2 valence neutrons, sd-shell, dim=640, E0=-41.184967 MeV USDA oracle)
# 11 circuits = ceil(86 doubles / 8 per circuit): full doubles-pool coverage at default --subset 16
./nuclear_shell_driver --runtime --protons 2 --neutrons 2 --circuits 11 --shots 4096

# 22Ne  (2 valence protons + 4 valence neutrons, dim=4206)
./nuclear_shell_driver --runtime --protons 2 --neutrons 4 --circuits 11 --shots 4096

# 22Mg  (4 valence protons + 2 valence neutrons, dim=4206 -- isospin mirror of 22Ne)
./nuclear_shell_driver --runtime --protons 4 --neutrons 2 --circuits 11 --shots 4096
```

IBM Runtime credentials come from `~/.qiskit/qiskit-ibm.json` (see
[IBM Quantum Configuration](#ibm-quantum-configuration) above); environment
variables are not consulted.

---

## Post-processing strategies

Two strategies are available for the classical post-processing stage
(filter → Hamiltonian build → diagonalization):

| Strategy | How to invoke | Subspace built from | Variational bound |
|---|---|---|---|
| **Pooled** | `nuclear_shell_driver` (default) | All circuits merged | Tighter  -  more unique determinants |
| **Per-step** | `--bitstrings-dir` or `nuclear_shell_parallel` | One step file at a time | Per-circuit minimum |

**Pooled** is the recommended path. More circuits → more unique Slater
determinants in the combined pool → subspace energy closer to the
full-CI ground state (Rayleigh-Ritz). This is what the driver does by
default after a `--runtime` run or in test mode.

**Per-step** processes each `bitstrings_stepNN.txt` independently and
reports the minimum energy across all steps. The subspace for each step
is smaller, but the work is embarrassingly parallel  -  `nuclear_shell_parallel`
is this exact strategy distributed across coarray images. A single image
gives the same result as the driver's `--bitstrings-dir` mode.

**QPU and classical post-processing are fully decoupled.** The QPU step
(`--runtime`) writes `bitstrings_stepNN.txt` to disk and exits. All classical
work  -  filter, Hamiltonian build, diagonalization  -  happens separately,
either immediately in the same driver process or later via `--bitstrings-dir`
or `nuclear_shell_parallel`. This means parallelism is entirely a
classical-side concern: `nuclear_shell_parallel` reads the saved files
and distributes the post-processing across coarray images with no QPU
involvement. The online path (`--runtime`) is always serial; the parallel
path is always offline.

To make the strategy explicit:

```bash
# Pooled (default  -  no flag needed, but can be stated)
./nuclear_shell_driver --runtime --protons 2 --neutrons 2 --mode pooled

# Per-step, single process
./nuclear_shell_driver --bitstrings-dir /path/to/steps \
    --protons 2 --neutrons 2 --mode per-step

# Per-step, distributed across 4 coarray images
cafrun -n 4 ./nuclear_shell_parallel \
    --steps 11 --protons 2 --neutrons 2 \
    --bitstrings-dir /path/to/steps
```

---

## Classical post-processing on saved bitstrings

After a Runtime run, Fortran dumps `bitstrings_stepNN.txt` beside the binary.
To re-run only classical post-processing on those files (no QPU connection):

```bash
./nuclear_shell_driver --bitstrings-dir /path/to/bitstrings_dir \
    --protons 2 --neutrons 2
```

---

## Driver flags

| Flag | Default | Description |
|------|---------|-------------|
| `-p, --protons NUM` | 2 | valence protons (changes nucleus) |
| `-q, --neutrons NUM` | 2 | valence neutrons (changes nucleus) |
| `-n, --circuits NUM` | 11 | number of circuits in the ensemble (11 = full doubles-pool coverage at default `--subset 16`) |
| `--subset NUM` | 16 | operators per circuit layer (doubles = subset/2); each circuit takes the next ranked slice |
| `--max-depth NUM` | -- | optional gate-count cap per circuit (Givens=6, QEB=28 gates); must be >= 6 and consistent with `--subset` |
| `-s, --shots NUM` | 1024 | shots per circuit |
| `-r, --runtime` | off | submit circuits via IBM Runtime |
| `--bitstrings-dir DIR` | -- | load pre-dumped bitstrings, skip QPU |
| `--mj-target N` | 0 | 2×Mj sector for symmetry filter (0 = Mj=0 ground state; ±1, ±2, ... for excited sectors). Fully supported in both `nuclear_shell_driver` and `nuclear_shell_parallel`. |
| `--snt FILE` | `USDB.snt` | path to any KSHELL-format `.snt` interaction file. j_max and orbital count are read directly from the file - no code changes needed to add a new interaction. |
| `--shell NAME` | `sd` | shorthand: `sd` maps to `USDB.snt` (sd-shell, 24 qubits), `pf` maps to `gxpf1.snt` (pf-shell, 40 qubits). Use `--snt` for any other interaction. |

---

## Algorithm: magnitude-ranked ensemble with simple partition

Each circuit contains two operator layers applied after the HF (Hartree-Fock) reference: a
singles layer (1p1h, one-particle-one-hole, Givens rotations) and a doubles layer (2p2h,
two-particle-two-hole, QEB gates). Both layers take a consecutive slice from the
magnitude-ranked pool: circuit `r` gets positions `[(r-1)*n+1 .. r*n]` (mod pool size),
wrapping as needed. No disjoint-support constraint is applied -- operators acting on
overlapping qubits are accepted and serialise depth-first.

**Pool construction and initial ranking** follow ADAPT-VQE (Adaptive Derivative-Assembled
Pseudo-Trotter VQE, Grimsley et al. 2019): the pool consists of particle-hole excitation
operators, and the initial ranking is by gradient magnitude at the HF reference at theta=0
-- identical to `|F_pq|` (off-diagonal Fock element) for singles and `|V_ms|`
(antisymmetrized m-scheme two-body matrix element, TBME) for doubles when evaluated from
the HF state. Angle seeding follows the methodology of Robledo-Moreno et al. (Science
Advances 2025): frozen, optimization-free parameters from classical pre-computation.

```
PRE-COMPUTE (once):
  1. Singles pool: all (h->v) pairs, CG (Clebsch-Gordan)-filter J=0 -> 16 pairs for 20Ne
     Rank by PT2 (second-order perturbation theory) score:
       F_pq^2 / |Delta_EN|   (coupling squared over EN gap)
       F_pq     = sum_{k in occ, k != h,v} V_ms(h,k;v,k)
         h = hole (occupied orbital), v = virtual (unoccupied orbital),
         occ = occupied orbitals in the HF reference
       Delta_EN = H_hh - H_vv  (EN = Epstein-Nesbet denominator, see Angle seeding section)
     Seed theta_pq = 0.5 * arctan(2 * F_pq / Delta_EN)   [exact 2x2 diag]

  2. Doubles pool: all (h1,h2->v1,v2) quadruples, CG-filter -> 86 quads for 20Ne
     Rank by PT2 score: V_ms^2 / |Delta_EN|   (Slater-Condon element over EN gap)
       V_ms     = <h1 h2|V|v1 v2>_AS  (AS = antisymmetrized)
       Delta_EN = H_ref - H_exc  (EN denominator, see Angle seeding section)
     Seed theta = 0.5 * arctan(2 * V_ms / Delta_EN)       [exact 2x2 diag]

FOR each circuit r = 1 .. N_circuits:
  3. HF reference (X gates on lowest-SPE (single-particle energy) occupied orbitals)
  4. Singles layer: take ranked_pairs[(r-1)*n .. r*n] mod 16 (up to n = subset = 16)
       each pair: 1 Givens rotation  (4 CX + 2 RY = 6 gates)
         CX = CNOT gate, RY = Y-rotation gate
  5. Doubles layer: take ranked_quads[(r-1)*(n/2) .. r*(n/2)] mod 86
       each quad:  1 QEB (qubit-excitation-based) double-excitation gate
                   (14 CX + 6 H + 8 RY = 28 gates)
       n/2 = 8 doubles per circuit at default --subset 16
  6. Submit to IBM Runtime Sampler; accumulate bitstrings into pool

POST-PROCESS (once on the full pool):
  7. filter_bitstrings: keep shots satisfying (N_p, N_n, Mj=0 (magnetic quantum number
       projection), even parity)
  8. build_subspace_hamiltonian: H restricted to unique surviving determinants
  9. diagonalize_exact_complex: LAPACK zheev -> ground-state energy
```

**Ensemble coverage:** the first circuit always uses the strongest operators (ranked by
PT2 score F^2/|Delta_EN|); later circuits work through progressively weaker terms. Full
coverage requires `ceil(pool_size / n)` circuits per pool: for 20Ne at default `--subset 16`,
the singles pool (16 pairs, n=16) needs 1 circuit; the doubles pool (86 quads, n=8) needs
11. The default `--circuits 11` is set to cover the doubles pool exactly. The singles pool
(16 pairs) is exhausted after circuit 1 and then wraps, circuits 2 onward repeat the
same 16 singles operators while continuing to advance through unseen doubles. Using fewer
than 11 circuits means weaker doubles never appear in any circuit, a depth/coverage
trade-off that should be made consciously, not by accident. When `n_circuits` exceeds the
coverage threshold, the pool wraps and the strongest operators reappear.

---

## Angle seeding

Both angle formulas are derived from exact diagonalization of the 2x2 Hamiltonian in the
`{|ref>, |excited>}` subspace. The denominator in both formulas is `H_ref - H_exc`, the
diagonal energy difference between the reference and excited determinant, not a bare SPE
(single-particle energy) gap.

### Singles: exact two-level mixing with Epstein-Nesbet denominator

```
theta_pq = 0.5 * arctan( 2 * F_pq / Delta_EN )

F_pq     = sum_{k in occ, k != h,v}  V_ms(h,k;v,k)
         (off-diagonal Fock element: sum over occupied spectators k,
          excluding h and v themselves)

Delta_EN = (eps_h - eps_v)                                (SPE gap: single-particle
         |                                                 energies of hole h and
         |                                                 virtual v)
         + sum_{k in occ, k != h,v} [V_ms(h,k;h,k)
                                    - V_ms(v,k;v,k)]      (spectator change: how
                                                           each remaining occupied
                                                           orbital k interacts
                                                           differently with h vs v)
         = H_hh - H_vv
```

`H_hh` and `H_vv` are the diagonal Hamiltonian matrix elements for the reference
determinant (h occupied) and the singly-excited determinant (v occupied) respectively.
The EN (Epstein-Nesbet) correction adds the change in spectator two-body interaction
when h is replaced by v. Verified by `verify_angle_formulas` against explicit 2x2
diagonalization.

### Doubles: exact two-body mixing with full Epstein-Nesbet denominator

```
theta = 0.5 * arctan( 2 * V_ms(h1,h2;v1,v2) / Delta_EN )

V_ms     = <h1 h2|V|v1 v2>_AS
         (antisymmetrized m-scheme TBME, two-body matrix element;
          direct Slater-Condon coupling between reference and doubly-excited
          determinant; no spectator sum by Slater-Condon rules)

Delta_EN = (eps_h1 + eps_h2 - eps_v1 - eps_v2)           (sum of SPE gaps for
         |                                                 the two promoted pairs)
         + sum_{k in occ, k != h1,h2} [V_ms(h1,k;h1,k)
                                      + V_ms(h2,k;h2,k)
                                      - V_ms(v1,k;v1,k)
                                      - V_ms(v2,k;v2,k)]  (spectators: how each
                                                           remaining occupied k
                                                           interacts with the
                                                           excited pair vs the
                                                           original pair)
         + [V_ms(h1,h2;h1,h2) - V_ms(v1,v2;v1,v2)]       (pair self-interaction:
                                                           h1-h2 diagonal TBME in
                                                           H_ref minus v1-v2
                                                           diagonal TBME in H_exc)
         = H_ref - H_exc
```

`H_ref` = `<Phi_0|H|Phi_0>`: diagonal Hamiltonian element for the HF reference (h1, h2
occupied; v1, v2 empty). `H_exc` = `<Phi_{h1h2}^{v1v2}|H|Phi_{h1h2}^{v1v2}>`: same for
the doubly-excited determinant (v1, v2 occupied; h1, h2 empty). The pair self-interaction
term `[V_ms(h1,h2;h1,h2) - V_ms(v1,v2;v1,v2)]` is not optional -- it captures the
change in the h1-h2 pairwise interaction that is present in H_ref and absent in H_exc.
Verified by `verify_angle_formulas` against explicit 2x2 diagonalization.

**Numerator (doubles):** by the Slater-Condon rules, two determinants differing in exactly
two orbitals couple as `<Phi|H|Phi'> = V_ms(h1,h2;v1,v2)` -- the direct antisymmetrized
TBME (two-body matrix element), with no spectator sum. This is distinct from singles where
both legs of the two-body operator must be contracted against occupied spectators to give
`F_pq`.

**Note:** singles angles equal `+/-pi/2` when `Delta_EN -> 0` -- i.e. when the
Epstein-Nesbet denominator `H_hh - H_vv` vanishes with `F_pq` finite. This occurs in the
sd-shell when the EN correction to the SPE gap nearly cancels the bare gap, leaving the
two levels near-degenerate in the correlated sense. The mixing is maximal and the angle is
physically meaningful, not a numerical artefact.

Note on entanglement: a Givens rotation does create qubit entanglement in the ordinary
sense (Bell-state-style). What it cannot do is take a single Slater determinant to anything
other than another single Slater determinant (Thouless theorem constraint), regardless of
how many are composed. The resulting state is a superposition only within the one-particle
reduced density matrix; measurement statistics are governed entirely by that one-body
density matrix (Wick's theorem), missing genuine pairwise correlation. The doubles gate
breaks this: `exp(theta * G_pqrs)` generates a genuine superposition of two fermionic
configurations and is the minimal gate for two-body correlations. Full correlation is
recovered by the ensemble: diverse Slater determinants from many circuits are pooled, and
the subsequent diagonalization recovers correlation energy within the sampled subspace.

---

## Gates

### Single-excitation: Givens rotation (6 gates, 4 CNOTs)

Implements `exp(theta * (a+_a * a_b - h.c.))` (h.c. = Hermitian conjugate), mixing `|01> <-> |10>` only:

```
CX(b->a) - RY(+theta/2, b) - CX(a->b) - RY(-theta/2, b) - CX(a->b) - CX(b->a)
```

Particle number is exactly conserved -- `|00>` and `|11>` are unchanged.
Gate set: `{CX, RY}`.

**Depth note:** the minimum-CNOT construction for a single excitation is 2 CNOTs
(Yordanov et al. 2020, qubit-excitation operator). The 4-CNOT count here is correct
but not the floor; halving it is an available future optimization.

### Double-excitation: Barkoutsos gate with Z-strings dropped (28 gates, 14 CNOTs)

Implements `exp(theta * (a+_p a+_q a_r a_s - h.c.))` using the Barkoutsos et al. 2018
construction: the JW (Jordan-Wigner) decomposition of this operator into Pauli strings
(Whitfield, Biamonte & Aspuru-Guzik 2011) yields 8 terms, and the efficient shared-backbone
circuit compiles these into **14 CNOTs + 6 H + 8 RY = 28 gates** by sharing the CNOT
backbone across all 8 terms. The Jordan-Wigner Z-strings are dropped (qubit-excitation
approximation, Yordanov et al. 2020), reducing the circuit to a fixed gate count
independent of orbital distance.

**QEB vs JW:** the QEB (qubit-excitation-based) formulation (Yordanov et al. 2020) drops
the Jordan-Wigner Z-string between non-adjacent orbital indices. For the sd-shell register
layout -- proton block qubits 0-11, neutron block 12-23 -- pp (proton-proton) and nn
(neutron-neutron) doubles always keep all four qubit indices within a single 12-qubit block,
bounding the Z-string to at most 12 qubits. Cross-isospin pn (proton-neutron) doubles span
both blocks and carry a Z-string of up to 24 qubits -- here the QEB approximation (dropping
the string entirely) introduces the largest error.

Gate set: `{CX, H, RY}`.

---

## Design lineage

**What this is:** a nuclear adaptation of the optimization-free SQD (sample-based quantum
diagonalization) methodology (Robledo-Moreno et al., Science Advances 2025). In that work,
CCSD (coupled-cluster singles and doubles) amplitudes are converted directly into circuit
parameters, frozen, and used to sample Slater determinants for classical post-processing.
Here, two-level mixing angles from nuclear perturbation theory (`seed_angles`,
`seed_double_angles`) play exactly that role: seeded once from TBME (two-body matrix
element) physics, frozen, used open-loop.

**Pool construction and ranking** follow ADAPT-VQE (Grimsley et al. 2019): the pool is a
catalogue of particle-hole excitation operators, and at the HF reference with all theta=0 the
ADAPT-VQE gradient for operator O is `|<HF|[H,O]|HF>|`. For singles this evaluates to
`|F_pq|`; for doubles to `|V_ms|` -- identical to the static magnitude ranking computed
here from the loaded `.snt` matrix elements before any circuit run.
The angle seeding and the optimization-free frozen-parameter regime are both from
Robledo-Moreno et al. 2025.

**The top-N knob** (`--subset`) is a user-controlled dial that trades circuit depth for
ensemble diversity. Tighter N means shallower circuits per circuit; later circuits in the
ensemble cover progressively weaker operators, ensuring aggregate coverage of the full pool.

**Extensibility:** `select_ranked_slice` in `nuclear_selection.f90` is the single function
that determines operator ordering. Swapping the consecutive ranked slice for a
gradient-evaluated or norm-weighted stochastic draw would give an adaptive variant behind
the same interface, without touching the gate synthesis or angle seeding code.

---

## Switching nuclei

All per-nucleus quantities are derived at runtime from the loaded `.snt` file and
`--protons`/`--neutrons`. There is no per-nucleus configuration needed:

| What adjusts automatically | How |
|---|---|
| Number of qubits (24 for all sd-shell) | `init_registry_sd_shell(P, N)` |
| HF reference occupation | `create_hf_reference` fills lowest-SPE 0d5/2 first |
| Singles pool (40->16 for 20Ne, 52->16 for 22Ne/22Mg) | `filter_excitations_by_j(J=0)` (CG J=0 filter) |
| Doubles pool (490->86 for 20Ne) | `filter_doubles_by_j` (CG triangle-inequality filter) |
| Symmetry filter targets (N, Z) | passed as `--protons`/`--neutrons` arguments |

Currently supported nuclei (all use the same 24-qubit sd-shell basis):

| Nucleus | `--protons` | `--neutrons` | Full-CI dim |
|---------|-------------|--------------|-------------|
| 20Ne | 2 | 2 | 640 |
| 22Ne | 2 | 4 | 4206 |
| 22Mg | 4 | 2 | 4206 |

### pf-shell extension (structurally supported, untested)

The code is not sd-shell-specific. All physics routines (`reg_mj2`, `reg_parity`,
`build_subspace_hamiltonian`, `v_ms_elem`, the CG tables) are fully general and derive
orbital structure from the `.snt` file at runtime. To run a pf-shell nucleus (e.g. 48Ca):

1. Place `gxpf1.snt` in the working directory -- that is the filename `--shell pf`
   looks for. No pf-shell interaction ships with this repo; obtain one (e.g. from
   KSHELL) and either name it `gxpf1.snt` or pass `--snt <file>.snt` instead.
2. Pass `--shell pf` to the driver. The flag is plumbed through to
   `setup_single_particle_data` and `init_registry_from_file`.
3. Adjust `--protons`/`--neutrons` for the valence particle count above the 40Ca core.
4. Ideally increase `--circuits` and `--shots` -- pf-shell spaces are larger (40 qubits,
   j_max = 7/2, typical Full-CI dim in the thousands to millions).

**What works without modification:** `setup_single_particle_data`, `filter_bitstrings`,
`filter_bitstrings_int`, `build_subspace_hamiltonian`, `diagonalize_exact_complex`,
all CG table computation (GSL recommended for j > 5/2).

**Parity filter (pf-shell safe):** `filter_bitstrings` and `filter_bitstrings_int` use
separate `int32` parity masks for the proton block and neutron block, each with at most 32
bits. The parity is `ieor(poppar(packed_p & mask_p), poppar(packed_n & mask_n))`. This is
correct for any model space with at most 32 orbitals per species (pf-shell has 20), and
avoids the silent truncation bug that would affect a unified 40-bit mask.

**What has not been tested:** the full pipeline end-to-end for any pf-shell nucleus.
Both drivers derive `j_max` dynamically from the loaded `.snt` file via
`maxval(ms%orbitals%j2)`, so no manual adjustment is needed when switching shells.
The `--shell pf` flag is accepted and routes through correctly, but no pf-shell
run has been validated.

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
- **LAPACK** (Linear Algebra PACKage) -- required for `diagonalize_exact_complex`. macOS: Accelerate (automatic).
- **OpenMP** -- for parallel H-build (`COLLAPSE(2) SCHEDULE(DYNAMIC,8)`) and symmetry filter. Detected automatically by CMake.
- **GSL** (GNU Scientific Library, optional) -- `brew install gsl`. Improves CG (Clebsch-Gordan) accuracy for j > 5/2; not needed for sd-shell.
- **qiskit-ibm-runtime-c** -- required for `--runtime` mode.

---

## Modules

### `nuclear_pool.f90`
Stable facade for operator pool management -- the single import point for everything
related to building, filtering, ranking, and seeding an excitation pool. All heavy
lifting is delegated to `exact_solver.f90` (ranking, seeding, angle verification),
`clebsch_gordan.f90` (symmetry filtering), and `nuclear_ansatz.f90` (pool generation).
Callers depend only on the names exposed here; the underlying modules are implementation
detail.

Pool procedures are named explicitly (Fortran generics require type/kind/rank
distinctness; all pool subroutines share identical argument types):

- `rank_singles_pool_pt2(ms, filtered_pairs, n, n_sp, ranked_pairs, weights)` -- rank 1p1h (one-particle-one-hole) pairs by PT2 score F_pq^2/|Delta_EN|.
- `rank_doubles_pool_pt2(ms, filtered_quads, n, n_sp, ranked_quads, weights)` -- rank 2p2h (two-particle-two-hole) quads by PT2 score V_ms^2/|Delta_EN|.
- `filter_singles_by_symmetry(raw, n_raw, j_target_2, filtered, n_filtered)` -- CG (Clebsch-Gordan) J=0 filter for pairs.
- `filter_doubles_by_symmetry(raw, n_raw, j_target_2, filtered, n_filtered)` -- CG triangle-inequality filter for quads.
- `seed_singles_angles(ms, ranked_pairs, n, n_sp, angles)` -- EN (Epstein-Nesbet) two-level mixing angles for singles.
- `seed_doubles_angles(ms, ranked_quads, n, n_sp, angles)` -- EN two-level mixing angles for doubles.
- `build_ranked_pool(ms, n_qubits, n_protons, n_neutrons, excitation_rank, n_sp, j_target_2, ...)` -- convenience: generate -> filter -> rank -> seed in one call. `excitation_rank`: 1=singles, 2=doubles, 3=both.

### `nuclear_selection.f90`
Ranked-partition operator selection -- the designated swap-point for the selection
strategy. A future gradient-driven or stochastic draw would replace the slice logic
here without callers needing any change.

- `select_singles_slice(ranked_pool, n_pool, circuit_index, subset_size, layer_ops, layer_size [, max_depth])` -- returns the consecutive ranked slice for 1p1h pools. Circuit `r` receives pool positions `[(r-1)*n+1 .. r*n]` mod pool size.
- `select_doubles_slice(ranked_pool, n_pool, circuit_index, subset_size, layer_ops, layer_size [, max_depth] [, depth_already_used])`, same for 2p2h pools; `depth_already_used` subtracts gates already placed by the singles layer from the depth budget.
- Note: a single generic `select_ranked_slice` is not provided because Fortran generic resolution requires TKR distinctness; both procedures share identical argument types.

### `nuclear_gates.f90`
Stable re-export facade for users writing custom ansatz circuits outside this application.
Re-exports the four gate primitives from `nuclear_ansatz` under fixed public names so that
callers need not depend on `nuclear_ansatz` internals directly.
**Not used by the built-in driver** (which imports `nuclear_ansatz` directly); intended as
the stable entry point for downstream code.

- `create_hf_reference(circuit, n_qubits, n_protons, n_neutrons)` -- place X gates on HF-occupied orbitals.
- `add_single_excitation(circuit, hole_qubit, virtual_qubit, theta)` -- Givens rotation (4 CX + 2 RY).
- `add_double_excitation(circuit, h1, h2, v1, v2, theta)` -- QEB gate (14 CX + 6 H + 8 RY).
- `finalize_ansatz(circuit)` -- append `measure_all`.

### `nuclear_ansatz.f90`
Builds the Givens-rotation and double-excitation ansatz circuit.

- `create_hf_reference(circuit, n_qubits, n_protons, n_neutrons)` -- X gates on lowest-SPE occupied orbitals.
- `create_ph_excitation_pool` -- enumerates all (h->v) particle-hole pairs.
- `create_2p2h_excitation_pool` -- enumerates all (h1,h2->v1,v2) two-particle two-hole quadruples: pp, nn, and pn doubles.
- `add_givens_layer(circuit, qubit_a, qubit_b, theta)` -- one-body Givens rotation (4 CNOTs + 2 RY = 6 gates). Implements `exp(theta(a+_a a_b - h.c.))` (h.c. = Hermitian conjugate). Gate set: `{CX, RY}`.
- `add_double_excitation_layer(circuit, qp, qq, qr, qs, theta)` -- QEB (qubit-excitation-based) double-excitation gate (14 CNOTs + 6 H + 8 RY = 28 gates). Implements `exp(theta(a+_p a+_q a_s a_r - h.c.))` in the qubit-excitation approximation (Whitfield et al. 2011, Barkoutsos et al. 2018). Gate set: `{CX, H, RY}`.
- `finalize_ansatz(circuit)` -- appends `measure_all`.

### `symmetry_filter.f90`
Post-selects bitstrings to keep only those satisfying exact nuclear quantum numbers.

- `setup_single_particle_data(n_qubits, "sd")` -- initialises per-orbital 2*m_j (twice the magnetic quantum number) and parity tables.
- `convert_bitstrings_to_int` -- character->integer(1) conversion before the timed filter region.
- `filter_bitstrings_int(...)` -- four constraints via `popcnt`/`poppar` hardware intrinsics: proton count N, neutron count Z, Mj=0 (magnetic quantum number projection sum = 0), even parity.

### `exact_solver.f90`
Subspace Hamiltonian construction, diagonalization, and operator pool management.

- `rank_pairs_by_pt2` -- sorts CG-filtered singles by PT2 (second-order perturbation theory) score F_pq^2/|Delta_EN|; weights near-degenerate pairs that bare coupling ranking undervalues.
- `seed_angles` -- theta_pq = 1/2*arctan(2*F_pq / Delta_EN), F_pq = sum_{k in occ, k!=h,v} V_ms(h,k;v,k), denominator = H_hh - H_vv (full EN, Epstein-Nesbet).
- `filter_doubles_by_j` -- CG (Clebsch-Gordan) triangle-inequality filter for (h1,h2;v1,v2) quadruples.
- `rank_doubles_by_pt2` -- sorts CG-filtered doubles by PT2 score V_ms^2/|Delta_EN|.
- `seed_double_angles` -- theta = 1/2*arctan(2*V_ms / Delta_EN), denominator = H_ref - H_exc including spectators and pair self-interaction.
- `verify_angle_formulas` -- sanity-check: for each pair/quadruple builds explicit 2x2 Hamiltonian and verifies seeded angles match exact diagonalization to within tolerance.
- `build_subspace_hamiltonian` -- builds H restricted to pooled QPU (quantum processing unit) bitstrings; OMP (OpenMP) COLLAPSE(2).
- `diagonalize_exact_complex` -- LAPACK zheev (complex Hermitian eigensolver); returns lowest 1-4 eigenvalues.

### `clebsch_gordan.f90`
- `init_cg_tables(j_max_2)` / `cleanup_cg_tables()` -- allocate/free coefficient cache.
- `filter_excitations_by_j(pool_pairs, pool_size, J=0, ...)` -- CG filter for singles.

### `usdb_reader.f90` / `orbital_registry.f90`
- `read_usdb_file("USDB.snt", ms, status)` -- parses the Brown-Richter USDB interaction (6 SPEs (single-particle energies), 158 TBMEs (two-body matrix elements), 16O inert core).
- `init_registry_from_snt(ms, n_protons, n_neutrons)` -- primary initializer; expands all orbitals in the loaded model space into m-substates and fills the HF reference.
- `init_registry_sd_shell(n_protons, n_neutrons)` -- convenience wrapper: loads `USDB.snt` then calls `init_registry_from_snt`. Used by the fallback path in `create_hf_reference` when no `.snt` path is supplied.

---

## Physics reference

### Orbital ordering (24 qubits, sd-shell)

| Orbital | SPE (MeV) | Proton qubits | Neutron qubits |
|---------|-----------|---------------|----------------|
| 0d3/2 | +2.1117 | 0-3   | 12-15 |
| 0d5/2 | -3.9257 | 4-9   | 16-21 |
| 1s1/2 | -3.2079 | 10-11 | 22-23 |

HF reference fills 0d5/2 first (lowest SPE), not file order.

### Variational bound

The subspace energy satisfies E_sub >= E_oracle unconditionally (Rayleigh-Ritz).
More circuits -> more unique Slater determinants in the pool -> subspace closer to
the exact ground state.

---

## References

- **Optimization-free SQD (primary lineage)**: Robledo-Moreno et al., *Science Advances* **11**, eadu9991 (2025). CCSD-amplitude-seeded, optimization-free circuits for subspace diagonalization; direct methodological precedent for frozen-angle ensemble sampling.
- **JW Pauli decomposition**: Whitfield, Biamonte & Aspuru-Guzik, *Mol. Phys.* **109**, 735 (2011). Jordan-Wigner mapping of fermionic operators to Pauli strings; Table 3 gives the 8-string decomposition of double excitations used here.
- **Efficient double-excitation circuit**: Barkoutsos et al., *Phys. Rev. A* **98**, 022322 (2018). Shared-backbone construction compiling 8 JW Pauli-string exponentials into 14 CNOTs + 6 H + 8 RY. This is the circuit implemented here (with Z-strings dropped).
- **Qubit-excitation operators (QEB)**: Yordanov, Arvidsson-Shukur & Barnes, *Phys. Rev. A* **102**, 062612 (2020). Introduces qubit-excitation operators (dropping the JW Z-string); minimum-CNOT constructions give 2 CNOTs for singles and 8 CNOTs for doubles. The Z-string-dropping approximation from this work is applied to the Barkoutsos circuit here.
- **Qubit-excitation VQE**: Yordanov, Armaos, Barnes & Arvidsson-Shukur, *Commun. Phys.* **4**, 228 (2021). Direct QEB operator as VQE ansatz element.
- **ADAPT-VQE**: Grimsley, Economou, Barnes, Mayhall, *Nat. Commun.* **10**, 3007 (2019). Gradient-driven adaptive operator selection from a p-h excitation pool; pool construction and initial ranking by gradient magnitude at the HF reference follow this work. Nuclear applications: Romero et al., *Phys. Rev. C* **105**, 064317 (2022).
- **CIPSI / PT2 selection criterion**: Huron, Malrieu & Rancurel, *J. Chem. Phys.* **58**, 5745 (1973). Introduced the Epstein-Nesbet second-order importance metric `e_a = |<psi|H|a>|^2 / (E0 - H_aa)` for selected CI. This is the basis for the `rank_pairs_by_pt2` / `rank_doubles_by_pt2` ranking used here: score = `F_pq^2 / |Delta_EN|` (singles) or `V_ms^2 / |Delta_EN|` (doubles). Each score is that configuration's individual contribution to the total PT2 energy correction -- greedy selection by score captures the maximum energy recovery per circuit slot.
- **USDB interaction**: Brown & Richter, *Phys. Rev. C* **74**, 034315 (2006). Unified sd-shell Hamiltonian used throughout.
