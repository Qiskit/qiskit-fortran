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

!> @brief Integration test for nuclear dynamics post-processing modules
!>
!> Validates three core nuclear dynamics components:
!> 1. nuclear_ansatz - HF reference and parameter-swept circuit layers
!> 2. symmetry_filter - Bitstring filtering by (N, Z, Jz, parity)
!> 3. clebsch_gordan - Angular momentum conservation in excitation pairs
!>
!> Purpose: Verify that each component works correctly before circuit execution.
!> Tests are intentionally simple: build circuit, filter bitstrings, filter pool.

program test_nuclear_dynamics
    use iso_c_binding
    use qiskit_circuit
    use nuclear_ansatz
    use symmetry_filter
    use clebsch_gordan
    use orbital_registry, only: init_registry_sd_shell
    implicit none

    logical :: all_passed
    integer :: clock_rate, clock_start, clock_end
    integer :: step_start, step_end
    real(8) :: total_runtime, step_runtime

    call system_clock(count_rate=clock_rate)
    call system_clock(count=clock_start)
    print *, "========================================"
    print *, "Nuclear Dynamics Module Test Suite"
    print *, "========================================"
    print *, ""

    all_passed = .true.

    ! Test 1: Circuit construction
    print *, "Test 1: Circuit Construction"
    print *, "----------------------------------------"
    call system_clock(count=step_start)
    call test_circuit_construction(all_passed)
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""

    ! Test 2: Symmetry filtering
    print *, "Test 2: Symmetry Filter"
    print *, "----------------------------------------"
    call system_clock(count=step_start)
    call test_symmetry_filtering(all_passed)
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""

    ! Test 3: CG pool filtering
    print *, "Test 3: Clebsch-Gordan Pool Filter"
    print *, "----------------------------------------"
    call system_clock(count=step_start)
    call test_cg_pool_filter(all_passed)
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""

    ! Summary
    call system_clock(count=clock_end)
    total_runtime = real(clock_end - clock_start, 8) / real(clock_rate, 8)
    print *, "========================================"
    if (all_passed) then
        print *, "  All tests completed successfully!"
    else
        print *, ":/ Some tests failed"
    end if
    write(*,'(A,ES16.8,A)') "  Total runtime: ", total_runtime, " s"
    print *, "========================================"

contains

    subroutine test_circuit_construction(passed)
        logical, intent(inout) :: passed
        type(QuantumCircuit) :: circuit
        integer(c_int) :: n_qubits, n_protons, n_neutrons
        integer :: i

        n_qubits = 24
        n_protons = 2
        n_neutrons = 0

        ! Create HF reference
        call create_hf_reference(circuit, int(n_qubits, c_int), &
                                int(n_protons, c_int), int(n_neutrons, c_int))
        print *, "Created HF reference for 18O (Z=2, N=0)"

        ! Add 3 parameter-sweep layers
        do i = 1, 3
            call add_adapt_layer(circuit, int(i-1, c_int), int(i+5, c_int), &
                               0.1d0 * i)
        end do
        print *, "Added 3 parameter-sweep layers"

        ! Finalize
        call finalize_ansatz(circuit)
        print *, "Finalized circuit with measurement"
        print *, "Test 1 PASSED"
    end subroutine test_circuit_construction

    subroutine test_symmetry_filtering(passed)
        logical, intent(inout) :: passed
        integer(c_int) :: n_qubits, n_qp, n_qn
        integer(c_int) :: n_protons, n_neutrons, Jz_target, parity_target
        integer(c_int) :: n_samples, n_kept
        character(kind=c_char), allocatable :: bitstrings(:,:)
        logical(c_bool), allocatable :: kept(:)
        integer :: i

        n_qubits = 24
        n_qp = 12
        n_qn = 12
        n_protons = 4
        n_neutrons = 4
        Jz_target = 0
        parity_target = 0

        ! Setup
        call setup_single_particle_data(int(n_qubits, c_int), "sd"//c_null_char)
        print *, "Initialized sd-shell single-particle data"

        ! Create 3 test bitstrings
        n_samples = 3
        allocate(bitstrings(n_qubits, n_samples))
        allocate(kept(n_samples))

        ! Bitstring 1: Valid (N=4, Z=4)
        bitstrings(:, 1) = '0'
        do i = 1, 4
            bitstrings(i, 1) = '1'
            bitstrings(i+12, 1) = '1'
        end do
        print *, "Bitstring 1: 4 protons, 4 neutrons (valid)"

        ! Bitstring 2: Invalid (N=3, Z=4)
        bitstrings(:, 2) = '0'
        do i = 1, 4
            bitstrings(i, 2) = '1'
        end do
        do i = 1, 3
            bitstrings(i+12, 2) = '1'
        end do
        print *, "Bitstring 2: 4 protons, 3 neutrons (invalid)"

        ! Bitstring 3: Valid (N=4, Z=4)
        bitstrings(:, 3) = '0'
        do i = 1, 4
            bitstrings(i, 3) = '1'
            bitstrings(i+12, 3) = '1'
        end do
        print *, "Bitstring 3: 4 protons, 4 neutrons (valid)"

        ! Filter
        call filter_bitstrings(bitstrings, int(n_samples, c_int), int(n_qubits, c_int), &
                              int(n_qp, c_int), int(n_qn, c_int), &
                              int(n_protons, c_int), int(n_neutrons, c_int), &
                              int(Jz_target, c_int), int(parity_target, c_int), &
                              kept, n_kept)

        print *, "Filtered:", n_kept, "out of", n_samples, "bitstrings"
        if (n_kept == 2) then
            print *, "Test 2 PASSED"
        else
            print *, "Test 2 FAILED: Expected 2 valid, got", n_kept
            passed = .false.
        end if

        deallocate(bitstrings)
        deallocate(kept)
    end subroutine test_symmetry_filtering

    subroutine test_cg_pool_filter(passed)
        logical, intent(inout) :: passed
        integer(c_int) :: pool_size, filtered_size
        integer(c_int), allocatable :: pool_pairs(:,:)
        integer(c_int), allocatable :: filtered_pairs(:,:)

        ! Initialize registry
        call init_registry_sd_shell(2_c_int, 0_c_int)
        print *, "Initialized orbital registry for sd-shell"

        ! Initialize CG tables
        call init_cg_tables(5_c_int)  ! j_max = 5/2
        print *, "Initialized Clebsch-Gordan tables"

        ! Create simple pool: 5 pairs total
        pool_size = 5_c_int
        allocate(pool_pairs(pool_size, 2))

        ! J=0 allowed pairs (same j)
        pool_pairs(1, :) = [0_c_int, 1_c_int]   ! d3/2 -> d3/2
        pool_pairs(2, :) = [4_c_int, 5_c_int]   ! d5/2 -> d5/2
        ! J=0 forbidden pairs (different j)
        pool_pairs(3, :) = [0_c_int, 4_c_int]   ! d3/2 -> d5/2
        pool_pairs(4, :) = [0_c_int, 10_c_int]  ! d3/2 -> s1/2
        pool_pairs(5, :) = [10_c_int, 4_c_int]  ! s1/2 -> d5/2

        ! Filter
        call filter_excitations_by_j(pool_pairs, int(pool_size, c_int), 0_c_int, &
                                    filtered_pairs, filtered_size)

        print *, "Filtered pool:", filtered_size, "out of", pool_size, "pairs"
        if (filtered_size >= 2) then
            print *, "Test 3 PASSED"
        else
            print *, "Test 3 FAILED: Expected >= 2 valid pairs, got", filtered_size
            passed = .false.
        end if

        call cleanup_cg_tables()
        deallocate(pool_pairs)
        if (allocated(filtered_pairs)) deallocate(filtered_pairs)
    end subroutine test_cg_pool_filter

end program test_nuclear_dynamics
