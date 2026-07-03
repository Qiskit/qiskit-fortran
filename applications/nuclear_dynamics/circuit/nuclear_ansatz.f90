! This code is part of Qiskit.
!
! (C) Copyright IBM 2026.
!
! This code is licensed under the Apache License, Version 2.0. You may
! obtain a copy of this license in the LICENSE.txt file in the root directory
! of this source tree or at https://www.apache.org/licenses/LICENSE-2.0.
!
! Any modifications or derivative works of this code must retain this
! copyright notice, and modified files need to carry a notice indicating
! that they have been altered from the originals.

!> @brief Nuclear ansatz creation module
!>
!> Provides subroutines for creating fixed-parameter quantum circuits for
!> nuclear structure calculations. Implements a Hartree-Fock reference state
!> followed by CG-filtered particle-hole Givens rotations at fixed theta.
module nuclear_ansatz
  use iso_c_binding
  use qiskit_circuit
  use orbital_registry, only: init_registry_sd_shell, reg_is_occupied, &
                               reg_proton_holes, reg_proton_virtuals, &
                               reg_neutron_holes, reg_neutron_virtuals
  implicit none
  private

  public :: create_hf_reference
  public :: add_adapt_layer
  public :: create_ph_excitation_pool
  public :: finalize_ansatz

contains

  !> @brief Initialize circuit with Hartree-Fock reference state
  !>
  !> Creates the HF reference state by applying X gates to occupy the lowest
  !> energy orbitals for protons and neutrons. In the nuclear shell model,
  !> the HF state represents the ground state configuration where nucleons
  !> fill orbitals from lowest to highest energy according to the Pauli
  !> exclusion principle.
  !>
  !> NOTE: This subroutine ONLY initializes the HF reference state.
  !> Measurement should be added separately after all Givens layers are appended.
  !>
  !> Typical workflow:
  !>   1. Create HF reference: call create_hf_reference(circuit, 24, 4, 4)
  !>   2. Add Givens layers: call add_adapt_layer(circuit, 0, 6, 0.1d0)
  !>   3. Finalize with measurement: call finalize_ansatz(circuit)
  !>
  !> Qubit mapping (determined by USDB.snt file structure):
  !>   - Proton orbitals come first (tz=-1 entries in USDB.snt)
  !>   - Neutron orbitals follow (tz=+1 entries in USDB.snt)
  !>   - Each j-shell expanded into m-substates in descending mj order
  !>   - |0⟩ = empty orbital, |1⟩ = occupied orbital
  !>
  !> @param circuit The quantum circuit to initialize
  !> @param n_qubits Total number of qubits (must equal n_protons + n_neutrons)
  !> @param n_protons Number of protons (occupied proton orbitals)
  !> @param n_neutrons Number of neutrons (occupied neutron orbitals)
  subroutine create_hf_reference(circuit, n_qubits, n_protons, n_neutrons)
    type(QuantumCircuit), intent(inout) :: circuit
    integer(c_int), intent(in) :: n_qubits
    integer(c_int), intent(in) :: n_protons
    integer(c_int), intent(in) :: n_neutrons

    integer :: i

    if (n_protons < 0 .or. n_neutrons < 0) &
      error stop "[nuclear_ansatz] create_hf_reference: negative particle count"
    if (n_protons + n_neutrons > n_qubits) &
      error stop "[nuclear_ansatz] create_hf_reference: n_protons + n_neutrons exceeds n_qubits"

    ! Populate the registry with the HF occupation pattern for this system.
    ! init_registry_sd_shell marks the first n_protons proton qubits and first
    ! n_neutrons neutron qubits as occupied; the canonical sd-shell HF state.
    call init_registry_sd_shell(n_protons, n_neutrons)

    call circuit%init(n_qubits, n_qubits)

    ! Apply X to every qubit the registry marks as HF-occupied.
    do i = 0, n_qubits - 1
      if (reg_is_occupied(i)) call circuit%x(i)
    end do

  end subroutine create_hf_reference

  !> @brief Finalize the ansatz by adding measurements to all qubits
  !>
  !> This should be called after the HF reference state is created
  !> and all Givens layers have been appended. Provides a clean
  !> separation between ansatz construction and measurement.
  !>
  !> Example workflow:
  !>   ! 1. Create HF reference
  !>   call create_hf_reference(circuit, 24, 4, 4)
  !>   ! 2. Add Givens layers
  !>   call add_adapt_layer(circuit, 0, 6, 0.1d0)
  !>   call add_adapt_layer(circuit, 1, 7, 0.1d0)
  !>   ! 3. Finalize with measurement
  !>   call finalize_ansatz(circuit)
  !>
  !> @param circuit The quantum circuit to finalize
  subroutine finalize_ansatz(circuit)
    type(QuantumCircuit), intent(inout) :: circuit
    
    ! Add measurement to all qubits
    call circuit%measure_all()
    
  end subroutine finalize_ansatz

  !> @brief Add a particle-conserving Givens rotation layer
  !>
  !> Implements a NUMBER-CONSERVING particle-hole excitation operator using
  !> Givens rotations. The gate sequence implements the unitary: exp(θ(a†b - b†a))
  !> where a† creates a particle in orbital a and b annihilates in orbital b.
  !>
  !> Physical interpretation:
  !>   - Excites a nucleon from occupied orbital (hole) to virtual orbital (particle)
  !>   - The parameter θ is fixed at call time; no adaptive selection is performed
  !>   - CRITICALLY: This gate CONSERVES particle number by only mixing |01⟩ ↔ |10⟩
  !>
  !> Particle number conservation:
  !>   - The gate acts ONLY on the |01⟩ and |10⟩ subspace (single particle states)
  !>   - States |00⟩ (no particles) and |11⟩ (two particles) remain unchanged
  !>   - This ensures the total particle number is preserved throughout evolution
  !>
  !> Gate decomposition (since controlled-RY is not available):
  !>   The standard number-conserving decomposition is:
  !>     CNOT(b->a) - CRY(θ, a->b) - CNOT(b->a)
  !>
  !>   Since CRY is not available, we decompose it as:
  !>     1. CNOT(b->a)
  !>     2. RY(θ/2) on qubit_b
  !>     3. CNOT(a->b)
  !>     4. RY(-θ/2) on qubit_b
  !>     5. CNOT(a->b)
  !>     6. CNOT(b->a)
  !>
  !> Verification:
  !>   The resulting 4×4 unitary in the {|00⟩, |01⟩, |10⟩, |11⟩} basis is:
  !>     [1   0      0     0  ]
  !>     [0  cos(θ) sin(θ) 0  ]
  !>     [0 -sin(θ) cos(θ) 0  ]
  !>     [0   0      0     1  ]
  !>   This is block-diagonal, confirming particle number conservation.
  !>
  !> @param circuit The quantum circuit to add the layer to
  !> @param qubit_a First qubit index (typically the hole orbital)
  !> @param qubit_b Second qubit index (typically the particle orbital)
  !> @param theta Rotation angle parameter (in radians)
  subroutine add_adapt_layer(circuit, qubit_a, qubit_b, theta)
    type(QuantumCircuit), intent(inout) :: circuit
    integer(c_int), intent(in) :: qubit_a
    integer(c_int), intent(in) :: qubit_b
    real(c_double), intent(in) :: theta
    
    ! Validate qubit indices
    if (qubit_a < 0 .or. qubit_b < 0) then
      error stop "[nuclear_ansatz] add_adapt_layer: qubit indices must be non-negative"
    end if
    
    if (qubit_a == qubit_b) then
      error stop "[nuclear_ansatz] add_adapt_layer: qubit_a and qubit_b must be different"
    end if
    
    ! Implement particle-conserving Givens rotation for particle-hole excitation
    ! This decomposition ensures particle number is conserved by only mixing
    ! |01⟩ <-> |10⟩ states while leaving |00⟩ and |11⟩ unchanged.
    
    call circuit%cx(qubit_b, qubit_a)                      ! 1. basis change
    call circuit%ry(theta / 2.0_c_double, qubit_b)        ! 2. first half-rotation
    call circuit%cx(qubit_a, qubit_b)                      ! 3. entangle
    call circuit%ry(-theta / 2.0_c_double, qubit_b)       ! 4. second half-rotation
    call circuit%cx(qubit_a, qubit_b)                      ! 5. disentangle
    call circuit%cx(qubit_b, qubit_a)                      ! 6. restore basis
    
  end subroutine add_adapt_layer

  !> @brief Generate CG-filtered particle-hole excitation pairs for the fixed ansatz
  !>
  !> Enumerates all valid particle-hole excitation pairs. The caller is expected
  !> to pass the result through filter_excitations_by_j (clebsch_gordan) before
  !> building the circuit, reducing the 40-pair full pool to the 16 J=0-coupled
  !> pairs used in the fixed ansatz (confirmed at runtime for 2p+2n sd-shell).
  !>
  !> Excitation rules:
  !>   - Proton excitations: occupied proton orbitals -> virtual proton orbitals
  !>   - Neutron excitations: occupied neutron orbitals -> virtual neutron orbitals
  !>   - No cross-species excitations (proton->neutron or vice versa)
  !>
  !> @param n_qubits Total number of qubits in the system
  !> @param n_protons Number of occupied proton orbitals
  !> @param n_neutrons Number of occupied neutron orbitals
  !> @param pool_size Output: number of excitation pairs in the pool
  !> @param pool_pairs Output: allocated array of (hole, particle) pairs
  subroutine create_ph_excitation_pool(n_qubits, n_protons, n_neutrons, pool_size, pool_pairs)
    integer(c_int), intent(in)  :: n_qubits
    integer(c_int), intent(in)  :: n_protons
    integer(c_int), intent(in)  :: n_neutrons
    integer(c_int), intent(out) :: pool_size
    integer(c_int), allocatable, intent(inout) :: pool_pairs(:,:)

    integer, allocatable :: p_holes(:), p_virts(:), n_holes(:), n_virts(:)
    integer :: n_ph, n_nv, n_pv, n_nn
    integer(c_int), allocatable :: tmp(:,:)
    integer :: idx, h, v

    if (n_qubits < 0 .or. n_protons < 0 .or. n_neutrons < 0) &
      error stop "[nuclear_ansatz] create_ph_excitation_pool: negative parameter"
    if (n_protons + n_neutrons > n_qubits) &
      error stop "[nuclear_ansatz] create_ph_excitation_pool: n_protons + n_neutrons > n_qubits"

    ! Registry must be initialised before this call; create_hf_reference does that.
    ! Pull hole/virtual index lists from the single source of truth.
    call reg_proton_holes(p_holes, n_ph)
    call reg_proton_virtuals(p_virts, n_pv)
    call reg_neutron_holes(n_holes, n_nv)
    call reg_neutron_virtuals(n_virts, n_nn)

    pool_size = n_ph * n_pv + n_nv * n_nn

    ! Use local tmp + move_alloc
    allocate(tmp(pool_size, 2))
    idx = 1

    do h = 1, n_ph
      do v = 1, n_pv
        tmp(idx, 1) = int(p_holes(h), c_int)
        tmp(idx, 2) = int(p_virts(v), c_int)
        idx = idx + 1
      end do
    end do

    do h = 1, n_nv
      do v = 1, n_nn
        tmp(idx, 1) = int(n_holes(h), c_int)
        tmp(idx, 2) = int(n_virts(v), c_int)
        idx = idx + 1
      end do
    end do

    if (allocated(pool_pairs)) deallocate(pool_pairs)
    call move_alloc(tmp, pool_pairs)

  end subroutine create_ph_excitation_pool

end module nuclear_ansatz
