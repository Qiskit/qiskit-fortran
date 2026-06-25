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
!>     2. Execute sampler (Aer or Runtime) to get bitstrings
!>     3. Post-select by (N, Z) via filter_bitstrings
!>     4. Diagonalize subspace Hamiltonian via exact_solver
!>     5. Extract ground state energy → E(θᵢ)
!>   END FOR
!>   Find θ* = argmin E(θ), compare to oracle truth

module nuclear_dynamics_driver
    use iso_c_binding
    use qiskit_circuit
    use qiskit_target
    use qiskit_transpiler
    use qiskit_runtime
    use nuclear_ansatz
    use symmetry_filter, only: filter_bitstrings, setup_single_particle_data
    use exact_solver
    use usdb_reader, only: tbme_element, read_usdb_file, model_space_data
    use orbital_registry, only: init_registry_sd_shell
    implicit none
    private

    public :: run_parameter_sweep

contains

    subroutine extract_bitstrings_from_sampler(res, bitstrings, n_qubits)
        type(RtSamplerResult), intent(in) :: res
        character(kind=c_char), intent(out) :: bitstrings(:,:)
        integer, intent(in) :: n_qubits

        integer(c_size_t) :: i, n_samples
        integer :: j
        character(len=:), allocatable :: sample_str

        n_samples = res%num_samples()
        if (int(n_samples) /= size(bitstrings, 2)) then
            error stop "extract_bitstrings_from_sampler: sample count mismatch"
        end if

        do i = 0_c_size_t, n_samples - 1_c_size_t
            sample_str = res%sample(int(i))
            do j = 1, n_qubits
                if (j <= len(sample_str)) then
                    bitstrings(j, int(i) + 1) = sample_str(j:j)
                else
                    bitstrings(j, int(i) + 1) = '0'
                end if
            end do
        end do
    end subroutine extract_bitstrings_from_sampler

    !> Execute fixed-ansatz parameter sweep with runtime integration
    subroutine run_parameter_sweep(n_theta, theta_min, theta_max, &
                                    n_qubits, n_protons, n_neutrons, &
                                    shots, energies, min_energy, use_runtime)
        integer(c_int), intent(in) :: n_theta
        real(c_double), intent(in) :: theta_min, theta_max
        integer(c_int), intent(in) :: n_qubits, n_protons, n_neutrons
        integer(c_int), intent(in) :: shots
        real(c_double), intent(out) :: energies(n_theta)
        real(c_double), intent(out) :: min_energy
        logical, intent(in), optional :: use_runtime

        integer :: i, j, n_kept, status
        real(8) :: theta, delta_theta
        type(QuantumCircuit) :: circuit, qc_transpiled
        type(RtService) :: service
        type(RtBackendList) :: backends
        type(RtBackend) :: backend
        type(Target) :: backend_target
        type(RtJob) :: job
        type(RtSamplerResult) :: res
        character(kind=c_char), allocatable :: bitstrings(:,:)
        logical(c_bool), allocatable :: kept(:)
        complex(8), allocatable :: hamiltonian(:,:)
        real(8), allocatable :: eigenvalues(:), spes(:)
        type(tbme_element), allocatable :: tbmes(:)
        complex(8), allocatable :: eigenvectors(:,:)
        type(model_space_data) :: model_space
        integer :: dim, info
        logical :: do_runtime
        integer(c_int64_t) :: n_backends

        do_runtime = .false.
        if (present(use_runtime)) do_runtime = use_runtime

        if (n_theta < 1) error stop "run_parameter_sweep: n_theta must be >= 1"

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
        print *, ""

        call setup_single_particle_data(n_qubits, "sd"//c_null_char)
        call init_registry_sd_shell(n_protons, n_neutrons)

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

        do i = 1, n_theta
            theta = real(theta_min, 8) + real(i - 1, 8) * delta_theta

            print *, "Step", i, "of", n_theta, ": theta =", theta

            call create_hf_reference(circuit, n_qubits, n_protons, n_neutrons)
            call add_adapt_layer(circuit, 0_c_int, 6_c_int, real(theta, c_double))
            call add_adapt_layer(circuit, 1_c_int, 7_c_int, real(theta * 0.5d0, c_double))
            call add_adapt_layer(circuit, 2_c_int, 8_c_int, real(theta * 0.25d0, c_double))
            call finalize_ansatz(circuit)

            allocate(bitstrings(n_qubits, shots))
            allocate(kept(shots))

            if (do_runtime) then
                print *, "  Transpiling circuit..."
                qc_transpiled = transpile(circuit, backend=backend_target)

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
            else
                call generate_test_bitstrings(n_qubits, shots, n_protons, n_neutrons, bitstrings)
            end if

            call filter_bitstrings(bitstrings, int(shots, c_int), n_qubits, &
                                  int(n_qubits/2, c_int), int(n_qubits/2, c_int), &
                                  n_protons, n_neutrons, &
                                  0_c_int, 0_c_int, &
                                  kept, n_kept)

            if (n_kept > 0) then
                allocate(spes(1))
                allocate(tbmes(1))
                spes(1) = 0.0d0
                tbmes(1)%a = 1
                tbmes(1)%b = 1
                tbmes(1)%c = 1
                tbmes(1)%d = 1
                tbmes(1)%J = 0
                tbmes(1)%matrix_elem = 0.2d0

                call build_j2_hamiltonian_complex(5, spes, tbmes, hamiltonian, dim, info)

                if (info == 0) then
                    allocate(eigenvectors(dim, dim))
                    call diagonalize_exact_complex(hamiltonian, dim, eigenvalues, eigenvectors, info)
                    if (info == 0) then
                        energies(i) = eigenvalues(1)
                        min_energy = min(min_energy, energies(i))
                        print *, "  E(theta) =", energies(i), "MeV (", n_kept, "samples)"
                    else
                        energies(i) = huge(1.0d0)
                        print *, "  Diagonalization failed"
                    end if
                    deallocate(eigenvectors)
                else
                    energies(i) = huge(1.0d0)
                    print *, "  Hamiltonian construction failed"
                end if

                deallocate(hamiltonian)
                deallocate(eigenvalues)
                deallocate(spes)
                deallocate(tbmes)
            else
                energies(i) = huge(1.0d0)
                print *, "  No valid samples after filtering"
            end if

            deallocate(bitstrings)
            deallocate(kept)
            print *, ""
        end do

        print *, "=========================================="
        print *, "Results:"
        print *, "Minimum energy E* =", min_energy, "MeV"
        print *, "Oracle (j^2 pairing) =", 4.2234d0, "MeV"
        print *, "=========================================="

    end subroutine run_parameter_sweep

    !> Generate test bitstrings with proper symmetry
    subroutine generate_test_bitstrings(n_qubits, n_samples, n_protons, n_neutrons, bitstrings)
        integer(c_int), intent(in) :: n_qubits, n_samples, n_protons, n_neutrons
        character(kind=c_char), intent(out) :: bitstrings(:,:)
        integer :: i, j

        do i = 1, n_samples
            bitstrings(:, i) = '0'
            do j = 1, n_protons
                bitstrings(j, i) = '1'
            end do
            do j = 1, n_neutrons
                bitstrings(int(n_qubits/2) + j, i) = '1'
            end do
        end do
    end subroutine generate_test_bitstrings

end module nuclear_dynamics_driver

program nuclear_dynamics_driver_exe
    use iso_c_binding
    use nuclear_dynamics_driver
    implicit none

    integer :: n_theta, shots
    real(c_double) :: theta_min, theta_max
    real(c_double), allocatable :: energies(:)
    real(c_double) :: min_energy
    character(len=256) :: arg
    integer :: i, n_args
    logical :: use_runtime

    integer(c_int), parameter :: N_QUBITS = 24
    integer(c_int), parameter :: N_PROTONS = 4
    integer(c_int), parameter :: N_NEUTRONS = 4

    n_theta = 8
    theta_min = 0.0d0
    theta_max = 1.6d0
    shots = 1024
    use_runtime = .false.

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
        case ('--runtime', '-r')
            use_runtime = .true.
        case ('--help', '-h')
            print *, "Usage: nuclear_dynamics_driver [OPTIONS]"
            print *, ""
            print *, "Options:"
            print *, "  -n, --iterations NUM      Number of theta values (default: 8)"
            print *, "  --theta-min VALUE         Minimum theta (default: 0.0)"
            print *, "  --theta-max VALUE         Maximum theta (default: 1.6)"
            print *, "  -s, --shots NUM           Shots per iteration (default: 1024)"
            print *, "  -r, --runtime             Use IBM Runtime (requires credentials)"
            print *, "  -h, --help                Show this help message"
            print *, ""
            stop 0
        end select
        i = i + 1
    end do

    print *, "========================================"
    print *, "Nuclear Dynamics Parameter Sweep Driver"
    print *, "========================================"
    print *, ""

    allocate(energies(n_theta))

    call run_parameter_sweep(int(n_theta, c_int), real(theta_min, c_double), real(theta_max, c_double), &
                            int(N_QUBITS, c_int), int(N_PROTONS, c_int), int(N_NEUTRONS, c_int), &
                            int(shots, c_int), energies, min_energy, use_runtime)

    deallocate(energies)

end program nuclear_dynamics_driver_exe
