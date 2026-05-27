# Application Areas

`qiskit-fortran` exposes Qiskit's circuit construction and transpilation layer
as a native Fortran interface. This document outlines the research domains
where that capability has a well-motivated landing zone, grounded in active
literature and existing Fortran codebases.

Circuit execution is not yet natively supported from Fortran — tracked in [#12](https://github.com/Qiskit/qiskit-fortran/issues/12).

## Quantum Chemistry

Qiskit's [`qiskit-addon-sqd`](https://github.com/Qiskit/qiskit-addon-sqd) implements
Sample-based Quantum Diagonalization (SQD), an active research direction in
near-term quantum chemistry. The classical preprocessing and post-processing
stages of an SQD workflow map naturally to Fortran.

The dominant quantum chemistry codes:
[GAMESS](https://www.msg.chem.iastate.edu/gamess/),
[NWChem](https://nwchemgit.github.io/),
[OpenMolcas](https://gitlab.com/Molcas/OpenMolcas),
[CFOUR](https://cfour.uni-mainz.de/),
[CP2K](https://www.cp2k.org/), are written in Fortran and export Hamiltonians
in FCIDUMP format, which is the natural input to a quantum diagonalization
step. The connection is direct: a Fortran subroutine accepting an active-space
Hamiltonian and returning a selected configuration expansion could be embedded
in these codes. The [`qiskit-community/qiskit-c-api-demo`](https://github.com/qiskit-community/qiskit-c-api-demo)
demonstrates the same workflow in C++/MPI as a concrete point of reference.

## Nuclear Structure

Nuclear shell model codes: [ANTOINE](https://www.iphc.cnrs.fr/nutheo/code_antoine/menu.html),
[KSHELL](https://github.com/hamad-almasri/kshell),
[NuShellX](http://www.garsington.eclipse.co.uk/), solve configuration
interaction problems in many-body Hilbert spaces that scale exponentially with
valence nucleon count. There is active peer-reviewed work (2023–2025, Physical
Review C, Scientific Reports) applying VQE and ADAPT-VQE to nuclear shell
model Hamiltonians on IBM hardware using Qiskit directly. The classical
benchmark codes in that research are Fortran. A Fortran binding means the
quantum and classical phases of a hybrid calculation can live in the same
language and eventually in the same build.

## Lattice Gauge Theory

Classical lattice QCD codes use Fortran for their most computationally
intensive components. The quantum simulation of lattice gauge theories: U(1),
SU(2), and toward SU(3), is an active research program and regular representation 
at the Lattice conference series. The Hamiltonian formulations that quantum computers 
target require Hilbert space machinery that overlaps significantly with what existing 
Fortran diagonalization and Monte Carlo codes already handle. 
A Fortran-native circuit interface lowers the barrier for lattice theorists to prototype 
quantum circuit constructions within an existing workflow.

## Plasma Physics and Magnetohydrodynamics

Gyrokinetic codes ([GENE](https://www.ipp.mpg.de/GENE),
[GS2](https://gyrokinetics.gitlab.io/gs2/),
[CGYRO](https://gacode.io/CGYRO)) and MHD codes
([M3D-C1](https://m3dc1.pppl.gov/), [NIMROD](https://nimrodteam.org/)) are
predominantly Fortran and run at scale on HPC clusters. Quantum algorithms
for plasma simulation; Koopman–von Neumann linearization, Hamiltonian
simulation of MHD equations, appear in 2024–2025 literature. The common
thread is that these codes contain linear-algebraic subproblems (eigenvalue
problems, linear systems) where a quantum subroutine is a coherent if
speculative drop-in. A Fortran binding positions that quantum call within the
existing workflow rather than requiring a separate stack.

## Quantum Monte Carlo

Fortran QMC codes: [CASINO](https://vallico.net/casinoqmc/),
[QMCPACK](https://qmcpack.org/), [TurboRVB](https://turborvb.sissa.it/), use
trial wavefunctions to guide Monte Carlo sampling. There is conceptual interest
in using quantum hardware to prepare trial wavefunctions richer than classical
ansätze can efficiently express, with the resulting bitstring samples feeding
back into the QMC walker distribution. The physics of integrating
quantum-sampled trial states into QMC is an open research question, but the
domain is Fortran-native and the application is coherent with the binding
layer's design.

## Condensed Matter: DFT and Quantum Embedding

Electronic structure codes for periodic systems: [Quantum ESPRESSO](https://www.quantum-espresso.org/),
[ABINIT](https://www.abinit.org/), [Wien2k](http://www.wien2k.at/), are
written in Fortran and deployed at HPC facilities globally. Quantum embedding
methods (DMET, QDET), where a strongly correlated cluster is treated with a
quantum algorithm while the bath is handled classically, produce active-space
Hamiltonians small enough for near-term devices. These map onto an SQD-style
workflow, and since the host codes are Fortran, a native binding is a more natural
integration path.

## See also

- [`applications/`](applications/) — working programs built on the current binding surface
- [Open issues](https://github.com/Qiskit/qiskit-fortran/issues) — contributions currently looking for owners
- [Qiskit C API reference](https://docs.quantum.ibm.com/api/qiskit-c)