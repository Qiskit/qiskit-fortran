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

!> @brief Driver for nuclear dynamics parameter-sweep sampling pipeline with IBM Runtime
!>
!> Classical post-processing loop for fixed-ansatz parameter sweeps:
!>
!>   FOR each parameter θᵢ ∈ [θ_min, θ_max]:
!>     1. Build fixed ansatz (HF reference + θᵢ-parametrized layers)
!>     2. Execute sampler (Runtime) to get bitstrings
!>     3. Post-select by (N, Z) via filter_bitstrings
!>     4. Diagonalize subspace Hamiltonian via exact_solver
!>     5. Extract ground state energy → E(θᵢ)
!>   END FOR
!>   Find θ* = argmin E(θ), compare to oracle truth

module nuclear_dynamics_driver
    use iso_c_binding
    !$ use omp_lib
    use qiskit_circuit
    use qiskit_target
    use qiskit_transpiler
    use qiskit_runtime
    use nuclear_ansatz
    use symmetry_filter, only: filter_bitstrings, setup_single_particle_data, &
                                 convert_bitstrings_to_int, filter_bitstrings_int
    use exact_solver
    use usdb_reader, only: tbme_element, read_usdb_file, model_space_data
    use orbital_registry, only: init_registry_sd_shell, reg_proton_holes, reg_proton_virtuals, &
                                 reg_n_qubits, reg_is_occupied
    use clebsch_gordan, only: init_cg_tables, cleanup_cg_tables, filter_excitations_by_j
    implicit none
    private

    public :: run_parameter_sweep, run_bitstrings_dir

contains

    subroutine extract_bitstrings_from_sampler(res, bitstrings, n_qubits)
        type(RtSamplerResult), intent(in) :: res
        character(kind=c_char), intent(out) :: bitstrings(:,:)
        integer, intent(in) :: n_qubits

        integer(c_size_t) :: i, n_samples
        integer :: j
        character(len=:), allocatable :: sample_str
        integer(8) :: hex_val
        integer :: bit_pos, ios

        n_samples = res%num_samples()
        if (int(n_samples) /= size(bitstrings, 2)) then
            error stop "extract_bitstrings_from_sampler: sample count mismatch"
        end if

        do i = 0_c_size_t, n_samples - 1_c_size_t
            sample_str = res%sample(int(i))
            if (len(sample_str) >= 2 .and. sample_str(1:2) == '0x') then
                read(sample_str(3:), '(z20)', iostat=ios) hex_val
                if (ios /= 0) then
                    write(*, '(a, i0, a, a, a)') &
                        "WARNING: Failed to parse hex sample at index ", i, ": ", trim(sample_str), &
                        " - skipping this sample"
                    cycle  ! Skip the sample entirely, without breaking the workflow
                end if
                do j = 1, n_qubits
                    bit_pos = j - 1
                    if (btest(hex_val, bit_pos)) then
                        bitstrings(j, int(i) + 1) = '1'
                    else
                        bitstrings(j, int(i) + 1) = '0'
                    end if
                end do
            else
                do j = 1, n_qubits
                    if (j <= len(sample_str)) then
                        bitstrings(j, int(i) + 1) = sample_str(j:j)
                    else
                        bitstrings(j, int(i) + 1) = '0'
                    end if
                end do
            end if
        end do
    end subroutine extract_bitstrings_from_sampler

    !> Execute fixed-ansatz parameter sweep with runtime integration
    subroutine run_parameter_sweep(n_theta, theta_min, theta_max, &
                                    n_protons, n_neutrons, &
                                    shots, energies, min_energy, use_runtime, &
                                    start_step, mj2_target, j_target_2)
        integer(c_int), intent(in) :: n_theta
        real(c_double), intent(in) :: theta_min, theta_max
        integer(c_int), intent(in) :: n_protons, n_neutrons
        integer(c_int), intent(in) :: shots
        real(c_double), intent(out) :: energies(n_theta)
        real(c_double), intent(out) :: min_energy
        logical, intent(in), optional :: use_runtime
        integer, intent(in), optional :: start_step     ! resume from this step (1-based, skip prior)
        integer(c_int), intent(in), optional :: mj2_target  ! 2*Mj target sector (0=even-even; ±1=odd-mass)
        integer(c_int), intent(in), optional :: j_target_2  ! 2*J for CG pool filter (0=J=0 ground state)

        integer :: i, j, n_kept, status, i_start
        integer(c_int) :: n_qubits   ! derived from USDB orbital registry
        integer(c_int) :: mj2_tgt, j_tgt_2   ! resolved from optional args
        real(8) :: theta, delta_theta
        real(8) :: tol_oracle, oracle_e0
        logical :: gs_found
        integer(8) :: t0_step, t1_step, tick_rate
        integer(8) :: tc0, tc1     ! per-step classical timing checkpoints
        ! Per-step timing accumulators (ns)
        integer(8) :: t_filter_ns, t_ham_ns, t_diag_ns, t_classical_ns
        ! Sweep aggregates
        integer(8) :: total_filter_ns, total_ham_ns, total_diag_ns, total_classical_ns
        integer :: n_valid_steps
        real(8) :: sweep_e_min
        type(QuantumCircuit) :: circuit, qc_transpiled
        type(RtService) :: service
        type(RtBackendList) :: backends
        type(RtBackend) :: backend
        type(Target) :: backend_target
        type(RtJob) :: job
        type(RtSamplerResult) :: res
        character(kind=c_char), allocatable :: bitstrings(:,:)
        logical(c_bool), allocatable :: kept(:)
        integer, allocatable :: kept_idx(:), basis_map(:)
        integer(1), allocatable :: occ_int(:,:)   ! pre-converted occupation matrix
        complex(8), allocatable :: hamiltonian(:,:)
        real(8), allocatable :: eigenvalues(:)
        complex(8), allocatable :: eigenvectors(:,:)
        type(model_space_data) :: model_space
        integer :: dim, info, ik, n_kept_int
        logical :: do_runtime
        integer(c_int64_t) :: n_backends

        mj2_tgt = 0_c_int
        j_tgt_2 = 0_c_int
        if (present(mj2_target)) mj2_tgt = mj2_target
        if (present(j_target_2)) j_tgt_2 = j_target_2

        do_runtime = .false.
        if (present(use_runtime)) do_runtime = use_runtime

        ! Oracle energies from build_sd_hamiltonian + zheev on the same USDB.snt.
        ! 22Ne == 22Mg by isospin symmetry of USDB (approximately isospin-invariant).
        ! Used only for convergence reporting; the subspace solver is a variational
        ! upper bound: E_sub >= E_oracle unconditionally.
        if (n_protons == 2 .and. n_neutrons == 2) then
            oracle_e0 = -39.145050266d0   ! 20Ne
        else if (n_protons == 2 .and. n_neutrons == 4) then
            oracle_e0 = -55.273041038d0   ! 22Ne
        else if (n_protons == 4 .and. n_neutrons == 2) then
            oracle_e0 = -55.273041038d0   ! 22Mg (isospin mirror)
        else if (n_protons == 4 .and. n_neutrons == 4) then
            oracle_e0 = -75.548900000d0   ! 24Mg (approximate; run build_sd_hamiltonian offline for exact value)
        else
            oracle_e0 = -huge(1.0d0)      ! unknown nucleus — disable oracle stop
        end if

        tol_oracle = 0.1d0   ! |E - oracle| threshold: within 0.1 MeV = ground state found
        gs_found   = .false.
        i_start = 1
        if (present(start_step)) i_start = max(1, min(start_step, int(n_theta)))

        if (n_theta < 1) error stop "run_parameter_sweep: n_theta must be >= 1"

        ! Initialise timing aggregates
        total_filter_ns   = 0_8; total_ham_ns = 0_8; total_diag_ns = 0_8
        total_classical_ns = 0_8
        n_valid_steps = 0
        sweep_e_min = huge(1.0d0)

        delta_theta = 0.0d0
        if (n_theta > 1) delta_theta = real(theta_max - theta_min, 8) / real(n_theta - 1, 8)

        print *, "=========================================="
        print *, "Nuclear Dynamics Parameter Sweep"
        if (do_runtime) then
            print *, "Mode: IBM Runtime"
        else
            print *, "Mode: Test (simulated bitstrings)"
        end if
        print *, "=========================================="
        print *, "Parameter sweep: theta in [", theta_min, ",", theta_max, "]"
        print *, "Number of steps:", n_theta
        print *, "Step size:", delta_theta
        print *, "Shots per step:", shots
        write(*,'("  Oracle (full sd-shell): ",F18.9," MeV  [stop if |E-oracle| < ",F5.2," MeV]")') &
            oracle_e0, tol_oracle
        write(*,'("RESULT  oracle_e0   ",F16.9," MeV")') oracle_e0
        block
            integer :: n_omp_threads
            !$ n_omp_threads = omp_get_max_threads()
            !$ print '("  OMP threads (max): ",I4)', n_omp_threads
            !$ write(*,'("RESULT  omp_threads   ",I16," threads")') int(n_omp_threads, 8)
        end block
        if (i_start > 1) then
            print '("  *** Resuming from step ",I2," (steps 1–",I2," skipped) ***")', i_start, i_start-1
        end if
        print *, ""

        ! Init registry first so we can derive n_qubits from USDB orbital table.
        call init_registry_sd_shell(n_protons, n_neutrons)
        n_qubits = int(reg_n_qubits(), c_int)
        call setup_single_particle_data(n_qubits, "sd"//c_null_char)
        call init_cg_tables(5_c_int)   ! j_max = 5/2 for sd-shell

        ! Load USDB model space once (read_usdb_file searches cwd for USDB.snt)
        block
            integer :: snt_status
            call read_usdb_file("USDB.snt", model_space, snt_status)
            if (snt_status /= 0) error stop "run_parameter_sweep: could not load USDB.snt"
        end block

        if (do_runtime) then
            print *, "Connecting to IBM Quantum Runtime..."
            call service%connect()
            print *, "Connected successfully."
            print *, ""

            print *, "Fetching backends..."
            call service%backends(backends)
            n_backends = backends%length()
            print *, "Found", n_backends, "backend(s)."

            print *, "Selecting least busy backend..."
            backend = backends%least_busy()
            if (.not. backend%is_valid()) error stop "No backends available."
            print *, "Backend:", backend%name()
            print *, ""

            print *, "Fetching backend target..."
            call backend%get_target(service, backend_target)
            print *, ""
        end if

        min_energy = huge(1.0d0)
        call system_clock(count_rate=tick_rate)

        do i = 1, n_theta
            ! Resume: skip steps before start_step (no QPU call, no energy recorded)
            if (i < i_start) then
                print '("  Step ",I2," skipped — resuming from step ",I2)', i, i_start
                energies(i) = huge(1.0d0)
                cycle
            end if

            if (gs_found) then
                print '("  Step ",I2," skipped — ground state found at step ",I2," (|E-oracle| < ",F5.2," MeV)")', &
                    i, i-1, tol_oracle
                energies(i) = energies(i-1)
                cycle
            end if

            theta = real(theta_min, 8) + real(i - 1, 8) * delta_theta

            print *, "Step", i, "of", n_theta, ": theta =", theta

            call create_hf_reference(circuit, n_qubits, n_protons, n_neutrons)
            ! Build full p-h pool then apply CG J=0 filter — use all physics-valid pairs.
            ! No arbitrary cap: the pool size is determined entirely by the triangle
            ! inequality and parity condition for J_target=0.
            block
                integer(c_int), allocatable :: raw_pairs(:,:), filtered_pairs(:,:)
                integer(c_int), allocatable :: ranked_pairs(:,:)
                real(8),        allocatable :: tbme_weights(:)
                integer(c_int) :: raw_size, filtered_size
                integer :: k
                call create_ph_excitation_pool(n_qubits, n_protons, n_neutrons, &
                                               raw_size, raw_pairs)
                call filter_excitations_by_j(raw_pairs, raw_size, j_tgt_2, &
                                             filtered_pairs, filtered_size)
                ! Rank pairs by |V_ms(h,h;v,v)| descending so largest TBMEs go first
                call rank_pairs_by_tbme(model_space, filtered_pairs, int(filtered_size), &
                                        ranked_pairs, tbme_weights)
                if (i == 1) then
                    print '("  Raw pool size     :", I4)', raw_size
                    print '("  CG-filtered (J=0) :", I4)', filtered_size
                    print '("  TBME ranking (top-3 |V_ms| MeV):")'
                    do k = 1, min(3, int(filtered_size))
                        write(*,'("    pair (",I2,"->",I2,"): V_ms=",F8.4," MeV")') &
                            ranked_pairs(k,1), ranked_pairs(k,2), tbme_weights(k)
                    end do
                end if
                do k = 1, filtered_size
                    call add_adapt_layer(circuit, ranked_pairs(k, 1), ranked_pairs(k, 2), &
                                         real(theta / real(k, 8), c_double))
                end do
            end block
            call finalize_ansatz(circuit)
            print '("  Circuit instructions (pre-transpile):", I5)', circuit%num_instructions()

            allocate(bitstrings(n_qubits, shots))
            allocate(kept(shots))

            if (do_runtime) then
                print *, "  Transpiling circuit..."
                block
                    type(TranspileOptions) :: topts
                    call topts%init(optimization_level=0)
                    call transpile(circuit, qc_transpiled, backend=backend_target, options=topts)
                end block

                print *, "  Submitting sampler job..."
                call service%run_sampler(job, backend, qc_transpiled, shots=shots)

                print *, "  Polling for completion..."
                do
                    status = service%job_status(job)
                    if (job_is_terminal(status)) exit
                    call sleep(5)
                end do

                if (status /= int(QkrtJobStatus_Completed)) then
                    print *, "  Job did not complete: ", job_status_name(status)
                    energies(i) = huge(1.0d0)
                    deallocate(bitstrings, kept)
                    cycle
                end if

                call service%sampler_results(res, job)
                call extract_bitstrings_from_sampler(res, bitstrings, n_qubits)
                print *, "  Extracted", res%num_samples(), "samples"
                ! Dump bitstrings to file for Python classical reuse
                block
                    integer :: funit, bs, bq
                    character(len=64) :: bsfname
                    write(bsfname,'("bitstrings_step",I2.2,".txt")') i
                    open(newunit=funit, file=trim(bsfname), status='replace', action='write')
                    do bs = 1, shots
                        do bq = 1, n_qubits
                            write(funit,'(A1)',advance='no') bitstrings(bq, bs)
                        end do
                        write(funit,*)
                    end do
                    close(funit)
                    print '("  Bitstrings written to ",A)', trim(bsfname)
                end block
                ! Diagnostic: print first 3 raw strings and decoded proton/neutron counts
                block
                    integer :: di, dj, dp, dn
                    character(len=:), allocatable :: raw
                    do di = 1, min(3, int(res%num_samples()))
                        raw = res%sample(di - 1)
                        dp = 0; dn = 0
                        do dj = 1, n_qubits
                            if (bitstrings(dj, di) == '1') then
                                if (dj <= n_qubits/2) then
                                    dp = dp + 1
                                else
                                    dn = dn + 1
                                end if
                            end if
                        end do
                        print '("  sample ",I2,": raw=",A," -> protons=",I2," neutrons=",I2)', &
                            di, raw, dp, dn
                    end do
                end block
            else
                call generate_test_bitstrings(n_qubits, shots, n_protons, n_neutrons, bitstrings)
            end if

            ! --- char→integer conversion (untimed pre-processing) ---
            allocate(occ_int(n_qubits, shots))
            call convert_bitstrings_to_int(bitstrings, int(n_qubits), shots, occ_int)

            ! --- symmetry filter on integer array (timed) ---
            call system_clock(tc0)
            call filter_bitstrings_int(occ_int, shots, int(n_qubits), &
                                       int(n_qubits/2), &
                                       n_protons, n_neutrons, &
                                       mj2_tgt, 0_c_int, &
                                       kept, n_kept)
            call system_clock(tc1)
            t_filter_ns = (tc1 - tc0) * (1000000000_8 / tick_rate)
            deallocate(occ_int)
            print *, "  Samples passing filter:", n_kept, "/", shots

            t_ham_ns  = 0_8
            t_diag_ns = 0_8

            if (n_kept > 0) then
                ! Extract integer indices of kept bitstrings from boolean mask
                n_kept_int = int(n_kept)
                allocate(kept_idx(n_kept_int))
                ik = 0
                do j = 1, shots
                    if (kept(j)) then
                        ik = ik + 1
                        kept_idx(ik) = j
                    end if
                end do

                ! --- Hamiltonian build (nuclear subspace diagonalization) ---
                call system_clock(tc0)
                allocate(basis_map(n_kept_int))
                call build_subspace_hamiltonian(model_space, n_protons, n_neutrons, &
                    bitstrings, kept_idx, n_kept_int, int(n_qubits), &
                    hamiltonian, dim, basis_map, info)
                call system_clock(tc1)
                t_ham_ns = (tc1 - tc0) * (1000000000_8 / tick_rate)

                if (info == 0) then
                    ! --- diagonalise ---
                    call system_clock(tc0)
                    call diagonalize_exact_complex(hamiltonian, dim, eigenvalues, eigenvectors, info)
                    call system_clock(tc1)
                    t_diag_ns = (tc1 - tc0) * (1000000000_8 / tick_rate)

                    if (info == 0) then
                        energies(i) = eigenvalues(1)
                        min_energy = min(min_energy, energies(i))
                        sweep_e_min = min_energy
                        n_valid_steps = n_valid_steps + 1
                        print *, "  E(theta) =", energies(i), "MeV  subspace_dim =", dim, &
                            "  kept =", n_kept_int
                        write(*,'("RESULT  energy_step",I2.2,"   ",F16.9," MeV")') i, energies(i)
                        write(*,'("RESULT  kept_step",I2.2,"     ",I16," shots")') i, n_kept
                        write(*,'("RESULT  dim_step",I2.2,"      ",I16," states")') i, dim

                        ! Oracle-proximity stop: |E - E_oracle| < 0.1 MeV
                        if (oracle_e0 > -huge(1.0d0)/2.0d0) then
                            if (abs(energies(i) - oracle_e0) < tol_oracle) then
                                gs_found = .true.
                                print '("  *** Ground state found at step ",I2,": E=",F12.6," MeV, |E-oracle|=",ES9.2," MeV ***")', &
                                    i, energies(i), abs(energies(i) - oracle_e0)
                            end if
                        end if
                    else
                        energies(i) = huge(1.0d0)
                        print *, "  Diagonalization failed"
                    end if
                    deallocate(eigenvectors)
                else
                    energies(i) = huge(1.0d0)
                    print *, "  Hamiltonian construction failed"
                end if

                if (allocated(hamiltonian))  deallocate(hamiltonian)
                if (allocated(eigenvalues))  deallocate(eigenvalues)
                if (allocated(kept_idx))     deallocate(kept_idx)
                if (allocated(basis_map))    deallocate(basis_map)
            else
                energies(i) = huge(1.0d0)
                print *, "  No valid samples after filtering"
            end if

            t_classical_ns = t_filter_ns + t_ham_ns + t_diag_ns
            total_filter_ns    = total_filter_ns    + t_filter_ns
            total_ham_ns       = total_ham_ns       + t_ham_ns
            total_diag_ns      = total_diag_ns      + t_diag_ns
            total_classical_ns = total_classical_ns + t_classical_ns

            deallocate(bitstrings)
            deallocate(kept)
            print '("  Classical post-processing: ",F12.3," ms (filter+ham+diag)")', &
                real(t_classical_ns, 8) / 1.0d6
            print *, ""
        end do

        print *, "=========================================="
        print *, "Results:"
        print *, "Minimum energy E* =", min_energy, "MeV"
        write(*,'("Oracle (full sd-shell USDB/LAPACK): ",F18.9," MeV")') oracle_e0
        print *, "=========================================="
        print *, ""

        ! Machine-readable result block
        if (n_valid_steps > 0) then
            write(*,'("RESULT  filter_mean    ",I16," ns")') total_filter_ns / int(n_valid_steps,8)
            write(*,'("RESULT  filter_total   ",I16," ns")') total_filter_ns
            write(*,'("RESULT  ham_mean       ",I16," ns")') total_ham_ns / int(n_valid_steps,8)
            write(*,'("RESULT  ham_total      ",I16," ns")') total_ham_ns
            write(*,'("RESULT  diag_mean      ",I16," ns")') total_diag_ns / int(n_valid_steps,8)
            write(*,'("RESULT  diag_total     ",I16," ns")') total_diag_ns
            write(*,'("RESULT  classical_total",I16," ns")') total_classical_ns
            write(*,'("RESULT  energy_min     ",F16.9," MeV")') sweep_e_min
            if (oracle_e0 > -huge(1.0d0)/2.0d0) &
                write(*,'("RESULT  energy_error   ",F16.9," MeV")') abs(sweep_e_min - oracle_e0)
        end if

    end subroutine run_parameter_sweep

    !> Generate test bitstrings using HF reference from orbital registry (Mj=0 by construction).
    subroutine generate_test_bitstrings(n_qubits, n_samples, n_protons, n_neutrons, bitstrings)
        integer(c_int), intent(in) :: n_qubits, n_samples, n_protons, n_neutrons
        character(kind=c_char), intent(out) :: bitstrings(:,:)
        integer :: i, q

        do i = 1, n_samples
            bitstrings(:, i) = '0'
            do q = 0, n_qubits - 1
                if (reg_is_occupied(q)) bitstrings(q + 1, i) = '1'
            end do
        end do
    end subroutine generate_test_bitstrings

    !> Load per-step bitstring files and run the classical post-processing pipeline.
    !> Mirrors the --bitstrings-dir mode of the Python baseline.
    !> Reads bitstrings_step01.txt .. bitstrings_stepNN.txt from bits_dir,
    !> runs symmetry filter → subspace Hamiltonian → diagonalisation for each,
    !> and emits RESULT lines identical to run_parameter_sweep.
    subroutine run_bitstrings_dir(bits_dir, n_protons, n_neutrons, max_steps, &
                                   mj2_target, j_target_2)
        character(len=*), intent(in) :: bits_dir
        integer(c_int),   intent(in) :: n_protons, n_neutrons
        integer,          intent(in) :: max_steps   ! maximum steps to look for
        integer(c_int), intent(in), optional :: mj2_target  ! 2*Mj target sector (0=even-even; ±1=odd-mass)
        integer(c_int), intent(in), optional :: j_target_2  ! 2*J for CG pool filter (0=J=0 ground state)

        type(model_space_data) :: ms
        character(kind=c_char), allocatable :: bitstrings(:,:)
        integer(1),             allocatable :: occ_int(:,:)
        logical(c_bool),        allocatable :: kept(:)
        integer,                allocatable :: kept_idx(:), basis_map(:)
        real(8),                allocatable :: eigenvalues(:)
        complex(8),             allocatable :: hamiltonian(:,:), eigenvectors(:,:)
        integer(c_int) :: n_qubits, n_kept_ci
        integer(c_int) :: n_shots_file
        integer(c_int) :: mj2_tgt   ! resolved from optional arg
        integer        :: i, j, ik, n_kept, dim, info, snt_st, n_valid_steps
        integer        :: funit, ios, q
        integer(8)     :: tc0, tc1, tick
        integer(8)     :: t_filter_ns, t_ham_ns, t_diag_ns, t_classical_ns
        integer(8)     :: total_filter_ns, total_ham_ns, total_diag_ns, total_classical_ns
        real(8)        :: oracle_e0, e_min
        character(len=256) :: bsfile
        character(len=24)  :: linebuf

        mj2_tgt = 0_c_int
        if (present(mj2_target)) mj2_tgt = mj2_target

        print *, "=========================================="
        print *, "Fortran classical pipeline (--bitstrings-dir)"
        print '("  Source : ",A)', trim(bits_dir)
        print '("  Nucleus: ",I1,"p+",I1,"n")', n_protons, n_neutrons
        print *, "=========================================="

        if (n_protons == 2 .and. n_neutrons == 2) then
            oracle_e0 = -39.145050266d0
        else if (n_protons == 2 .and. n_neutrons == 4) then
            oracle_e0 = -55.273041038d0
        else if (n_protons == 4 .and. n_neutrons == 2) then
            oracle_e0 = -55.273041038d0
        else
            oracle_e0 = -huge(1.0d0)
        end if
        write(*,'("RESULT  oracle_e0   ",F16.9," MeV")') oracle_e0

        call init_registry_sd_shell(n_protons, n_neutrons)
        n_qubits = int(reg_n_qubits(), c_int)
        call setup_single_particle_data(n_qubits, "sd"//c_null_char)
        call init_cg_tables(5_c_int)
        call read_usdb_file("USDB.snt", ms, snt_st)
        if (snt_st /= 0) error stop "run_bitstrings_dir: USDB.snt not found"

        block
            integer :: n_omp_threads
            !$ n_omp_threads = omp_get_max_threads()
            !$ write(*,'("RESULT  omp_threads   ",I16," threads")') int(n_omp_threads, 8)
        end block

        call system_clock(count_rate=tick)
        total_filter_ns = 0_8; total_ham_ns = 0_8; total_diag_ns = 0_8; total_classical_ns = 0_8
        n_valid_steps = 0
        e_min = huge(1.0d0)

        do i = 1, max_steps
            ! Build filename
            if (len_trim(bits_dir) > 0) then
                write(bsfile,'(A,"/bitstrings_step",I2.2,".txt")') trim(bits_dir), i
            else
                write(bsfile,'("bitstrings_step",I2.2,".txt")') i
            end if

            ! Try to open the file
            open(newunit=funit, file=trim(bsfile), status='old', action='read', iostat=ios)
            if (ios /= 0) exit   ! no more step files

            ! Count lines (shots) and detect n_qubits from line length
            n_shots_file = 0_c_int
            do
                read(funit, '(A)', iostat=ios) linebuf
                if (ios /= 0) exit
                if (len_trim(linebuf) > 0) n_shots_file = n_shots_file + 1_c_int
            end do
            rewind(funit)

            allocate(bitstrings(n_qubits, n_shots_file))
            allocate(kept(n_shots_file))

            do j = 1, int(n_shots_file)
                read(funit, '(A)', iostat=ios) linebuf
                if (ios /= 0) exit
                do q = 1, int(n_qubits)
                    bitstrings(q, j) = linebuf(q:q)
                end do
            end do
            close(funit)

            print '("  Step ",I2,": ",I4," shots from ",A)', i, n_shots_file, trim(bsfile)

            ! Convert to integer array
            allocate(occ_int(n_qubits, n_shots_file))
            call convert_bitstrings_to_int(bitstrings, int(n_qubits), int(n_shots_file), occ_int)

            ! Symmetry filter (timed)
            call system_clock(tc0)
            n_kept_ci = 0_c_int
            call filter_bitstrings_int(occ_int, int(n_shots_file), int(n_qubits), int(n_qubits/2), &
                                       n_protons, n_neutrons, mj2_tgt, 0_c_int, kept, n_kept_ci)
            call system_clock(tc1)
            t_filter_ns = (tc1 - tc0) * (1000000000_8 / tick)
            n_kept = int(n_kept_ci)
            deallocate(occ_int)
            print '("    kept=",I4,"/",I4)', n_kept, n_shots_file

            t_ham_ns  = 0_8
            t_diag_ns = 0_8

            if (n_kept > 0) then
                allocate(kept_idx(n_kept))
                ik = 0
                do j = 1, int(n_shots_file)
                    if (kept(j)) then
                        ik = ik + 1
                        kept_idx(ik) = j
                    end if
                end do

                ! Hamiltonian build (timed)
                allocate(basis_map(n_kept))
                call system_clock(tc0)
                call build_subspace_hamiltonian(ms, n_protons, n_neutrons, &
                    bitstrings, kept_idx, n_kept, int(n_qubits), &
                    hamiltonian, dim, basis_map, info)
                call system_clock(tc1)
                t_ham_ns = (tc1 - tc0) * (1000000000_8 / tick)

                if (info == 0) then
                    ! Diagonalisation (timed)
                    call system_clock(tc0)
                    call diagonalize_exact_complex(hamiltonian, dim, eigenvalues, eigenvectors, info)
                    call system_clock(tc1)
                    t_diag_ns = (tc1 - tc0) * (1000000000_8 / tick)

                    if (info == 0) then
                        n_valid_steps = n_valid_steps + 1
                        e_min = min(e_min, eigenvalues(1))
                        print '("    E=",F18.9," MeV  dim=",I5)', eigenvalues(1), dim
                        write(*,'("RESULT  energy_step",I2.2,"   ",F16.9," MeV")') i, eigenvalues(1)
                        write(*,'("RESULT  kept_step",I2.2,"     ",I16," shots")') i, n_kept
                        write(*,'("RESULT  dim_step",I2.2,"      ",I16," states")') i, dim

                    end if
                    deallocate(eigenvectors)
                end if
                if (allocated(hamiltonian))  deallocate(hamiltonian)
                if (allocated(eigenvalues))  deallocate(eigenvalues)
                if (allocated(kept_idx))     deallocate(kept_idx)
                if (allocated(basis_map))    deallocate(basis_map)
            end if

            t_classical_ns = t_filter_ns + t_ham_ns + t_diag_ns
            total_filter_ns    = total_filter_ns    + t_filter_ns
            total_ham_ns       = total_ham_ns       + t_ham_ns
            total_diag_ns      = total_diag_ns      + t_diag_ns
            total_classical_ns = total_classical_ns + t_classical_ns

            deallocate(bitstrings, kept)
        end do

        ! Aggregate result output
        if (n_valid_steps > 0) then
            write(*,'("RESULT  filter_mean    ",I16," ns")') total_filter_ns / int(n_valid_steps,8)
            write(*,'("RESULT  filter_total   ",I16," ns")') total_filter_ns
            write(*,'("RESULT  ham_mean       ",I16," ns")') total_ham_ns / int(n_valid_steps,8)
            write(*,'("RESULT  ham_total      ",I16," ns")') total_ham_ns
            write(*,'("RESULT  diag_mean      ",I16," ns")') total_diag_ns / int(n_valid_steps,8)
            write(*,'("RESULT  diag_total     ",I16," ns")') total_diag_ns
            write(*,'("RESULT  classical_total",I16," ns")') total_classical_ns
            write(*,'("RESULT  energy_min     ",F16.9," MeV")') e_min
            if (oracle_e0 > -huge(1.0d0)/2.0d0) &
                write(*,'("RESULT  energy_error   ",F16.9," MeV")') abs(e_min - oracle_e0)
        end if

        call cleanup_cg_tables()
    end subroutine run_bitstrings_dir

end module nuclear_dynamics_driver

program nuclear_dynamics_driver_exe
    use iso_c_binding
    use nuclear_dynamics_driver
    use exact_solver,    only: diagonalize_exact_complex
    use usdb_reader,     only: read_usdb_file, model_space_data
    use orbital_registry,only: init_registry_sd_shell, reg_n_qubits
    use clebsch_gordan,  only: init_cg_tables, cleanup_cg_tables
    implicit none

    integer :: n_theta, shots, start_step_arg
    real(c_double) :: theta_min, theta_max
    real(c_double), allocatable :: energies(:)
    real(c_double) :: min_energy
    character(len=256) :: arg
    character(len=256) :: bitstrings_dir    ! directory for --bitstrings-dir mode
    integer :: i, n_args
    logical :: use_runtime, bitstrings_mode

    integer(c_int) :: N_PROTONS = 2
    integer(c_int) :: N_NEUTRONS = 2
    integer(c_int) :: MJ2_TARGET = 0_c_int  ! 2*Mj sector (0=even-even; ±1=odd-mass)
    integer(c_int) :: J_TARGET_2 = 0_c_int  ! 2*J for CG pool filter (0=J=0)

    ! sweep wall-clock (start/stop around the full run_parameter_sweep call)
    integer(8) :: t_wall_0, t_wall_1, tick_rate_wall

    n_theta        = 15
    theta_min      = 0.0d0
    theta_max      = 3.141592653589793d0   ! pi
    shots          = 1024
    start_step_arg = 1
    bitstrings_dir  = ""
    use_runtime     = .false.
    bitstrings_mode = .false.
    n_args = command_argument_count()
    i = 1
    do while (i <= n_args)
        call get_command_argument(i, arg)
        select case (trim(arg))
        case ('--iterations', '-n')
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, arg)
                read(arg, *) n_theta
            end if
        case ('--theta-min')
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, arg)
                read(arg, *) theta_min
            end if
        case ('--theta-max')
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, arg)
                read(arg, *) theta_max
            end if
        case ('--shots', '-s')
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, arg)
                read(arg, *) shots
            end if
        case ('--protons', '-p')
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, arg)
                read(arg, *) N_PROTONS
            end if
        case ('--neutrons', '-q')
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, arg)
                read(arg, *) N_NEUTRONS
            end if
        case ('--runtime', '-r')
            use_runtime = .true.
        case ('--start-step')
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, arg)
                read(arg, *) start_step_arg
            end if
        case ('--bitstrings-dir')
            bitstrings_mode = .true.
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, bitstrings_dir)
            end if
        case ('--mj-target')
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, arg)
                read(arg, *) MJ2_TARGET
            end if
        case ('--j-target')
            i = i + 1
            if (i <= n_args) then
                call get_command_argument(i, arg)
                read(arg, *) J_TARGET_2
            end if
        case ('--help', '-h')
            print *, "Usage: nuclear_dynamics_driver [OPTIONS]"
            print *, "  -n, --iterations NUM   theta steps (default 15, stops early on convergence)"
            print *, "  --theta-min VALUE      sweep start (default 0)"
            print *, "  --theta-max VALUE      sweep end (default pi)"
            print *, "  -s, --shots NUM        shots/step (default 1024)"
            print *, "  -p, --protons NUM      valence protons (default 2)"
            print *, "  -q, --neutrons NUM     valence neutrons (default 2)"
            print *, "  -r, --runtime          use IBM Runtime"
            print *, "  --bitstrings-dir DIR   load bitstrings_stepNN.txt from DIR, skip QPU"
            print *, "  --start-step N         resume sweep from step N (skip steps 1..N-1)"
            print *, "  --mj-target N          2*Mj target sector: 0=even-even (default), ±1=odd-mass"
            print *, "  --j-target N           2*J for CG pool filter: 0=J=0 (default), 2=J=1, etc."
            stop 0
        end select
        i = i + 1
    end do

    ! ── Mode: classical pipeline on pre-dumped bitstrings ────────────────────
    if (bitstrings_mode) then
        call run_bitstrings_dir(trim(bitstrings_dir), N_PROTONS, N_NEUTRONS, n_theta, &
                                mj2_target=MJ2_TARGET, j_target_2=J_TARGET_2)
        stop 0
    end if

    ! ── Normal sweep mode ─────────────────────────────────────────────────────
    print *, "========================================"
    print *, "Nuclear Dynamics Parameter Sweep Driver"
    print *, "========================================"
    print *, ""

    allocate(energies(n_theta))

    call system_clock(t_wall_0, tick_rate_wall)
    call run_parameter_sweep(int(n_theta, c_int), real(theta_min, c_double), real(theta_max, c_double), &
                            int(N_PROTONS, c_int), int(N_NEUTRONS, c_int), &
                            int(shots, c_int), energies, min_energy, use_runtime, &
                            start_step=start_step_arg, &
                            mj2_target=MJ2_TARGET, j_target_2=J_TARGET_2)
    call system_clock(t_wall_1)

    write(*,'("RESULT  sweep_wall     ",I16," ns")') &
        (t_wall_1 - t_wall_0) * (1000000000_8 / tick_rate_wall)

    deallocate(energies)

end program nuclear_dynamics_driver_exe
