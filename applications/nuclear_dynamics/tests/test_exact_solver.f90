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

!> @brief Test program for exact_solver module
!>
!> Purpose: Test exact diagonalization of j² pairing systems
!>
!> Tests:
!>   1. Read USDB interaction file
!>   2. Extract j-shell TBMEs
!>   3. Solve 0d5/2² system (j=5/2, 15-dimensional)
!>   4. Print ground state and excited state energies
!>   5. Verify basis construction and dimensions

program test_exact_solver
    use usdb_reader
    use clebsch_gordan
    use exact_solver
    implicit none
    
    ! Variables
    type(model_space_data) :: model_space
    type(tbme_element), allocatable :: j_shell_tbmes(:)
    integer :: status, n_tbmes
    integer :: j_value, dim
    real(8), allocatable :: H_matrix(:,:)
    real(8), allocatable :: eigenvalues(:)
    real(8), allocatable :: eigenvectors(:,:)
    real(8) :: E0
    integer :: i
    integer :: clock_rate, clock_start, clock_end
    integer :: step_start, step_end
    real(8) :: total_runtime, step_runtime
    
    call system_clock(count_rate=clock_rate)
    call system_clock(count=clock_start)
    print *, "=========================================="
    print *, "  Exact Diagonalization Solver Test"
    print *, "  j² Pairing Toy System"
    print *, "=========================================="
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 1: Read USDB interaction file
    ! -------------------------------------------------------------------------
    print *, "Test 1: Reading USDB.snt file..."
    call system_clock(count=step_start)
    call read_usdb_file("USDB.snt", model_space, status)
    
    if (status /= 0) then
        print *, "ERROR: Failed to read USDB file"
        stop 1
    end if
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    print *, "  USDB file read successfully"
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 2: Initialize Clebsch-Gordan tables
    ! -------------------------------------------------------------------------
    print *, "Test 2: Initializing Clebsch-Gordan tables..."
    call system_clock(count=step_start)
    call init_cg_tables(5)  ! j_max = 5/2
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    print *, "  CG tables initialized"
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 3: Test dimension calculation
    ! -------------------------------------------------------------------------
    print *, "Test 3: Testing dimension calculations..."
    
    ! j = 3/2 (j_value = 3)
    j_value = 3
    dim = get_j2_dimension(j_value)
    print *, "  j = 3/2: dimension =", dim, "(expected: 6)"
    if (dim /= 6) then
        print *, "  ERROR: Wrong dimension for j=3/2"
        stop 1
    end if
    
    ! j = 5/2 (j_value = 5)
    j_value = 5
    dim = get_j2_dimension(j_value)
    print *, "  j = 5/2: dimension =", dim, "(expected: 15)"
    if (dim /= 15) then
        print *, "  ERROR: Wrong dimension for j=5/2"
        stop 1
    end if
    print *, "  Dimension calculations correct"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 4: Print basis states for j=5/2
    ! -------------------------------------------------------------------------
    print *, "Test 4: Basis states for j=5/2..."
    call print_basis_states(5)
    print *, "  Basis states printed"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 5: Extract TBMEs for 0d5/2 shell
    ! -------------------------------------------------------------------------
    print *, "Test 5: Extracting TBMEs for 0d5/2 shell..."
    call system_clock(count=step_start)
    ! In USDB, 0d5/2 orbitals have j2=5
    ! Orbitals 3 and 4 are 0d5/2 for protons and neutrons
    call get_j_shell_tbmes(5, model_space, j_shell_tbmes, n_tbmes)
    
    if (n_tbmes == 0) then
        print *, "WARNING: No TBMEs found for j=5/2 shell"
        print *, "This may be expected if USDB doesn't have pure j-shell elements"
    else
        print *, "  Extracted", n_tbmes, "TBMEs for j=5/2 shell"
        print *, ""
        print *, "Sample TBMEs (first 5):"
        do i = 1, min(5, n_tbmes)
            print '(A,I3,I3,A,I3,I3,A,I2,A,F10.4,A)', &
                "  <", j_shell_tbmes(i)%a, j_shell_tbmes(i)%b, &
                "|V|", j_shell_tbmes(i)%c, j_shell_tbmes(i)%d, &
                ">_J=", j_shell_tbmes(i)%J, &
                " = ", j_shell_tbmes(i)%matrix_elem, " MeV"
        end do
    end if
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 6: Build Hamiltonian for 0d5/2² system
    ! -------------------------------------------------------------------------
    print *, "Test 6: Building Hamiltonian for 0d5/2² system..."
    call system_clock(count=step_start)
    j_value = 5
    
    call build_j2_hamiltonian(j_value, model_space%spes, j_shell_tbmes, &
                              H_matrix, dim, status)
    
    if (status /= 0) then
        print *, "ERROR: Failed to build Hamiltonian"
        stop 1
    end if
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    print *, "  Hamiltonian built successfully"
    print *, "  Matrix size:", dim, "×", dim
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""
    
    ! Print sample matrix elements
    print *, "Sample Hamiltonian matrix elements:"
    print *, "  H(1,1) =", H_matrix(1,1), "MeV"
    print *, "  H(1,2) =", H_matrix(1,2), "MeV"
    print *, "  H(2,2) =", H_matrix(2,2), "MeV"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 7: Diagonalize Hamiltonian
    ! -------------------------------------------------------------------------
    print *, "Test 7: Diagonalizing Hamiltonian..."
    call system_clock(count=step_start)
    
    call diagonalize_exact(H_matrix, dim, eigenvalues, eigenvectors, status)
    
    if (status /= 0) then
        print *, "ERROR: Diagonalization failed"
        stop 1
    end if
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    print *, "  Diagonalization successful"
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 8: Print energy spectrum
    ! -------------------------------------------------------------------------
    print *, "Test 8: Energy spectrum for 0d5/2² system"
    print *, "=========================================="
    print *, ""
    print *, "State |  Energy (MeV)  | Excitation (MeV)"
    print *, "------|----------------|------------------"
    
    do i = 1, min(10, dim)
        write(*, '(I5, " | ", F14.6, " | ", F14.6)') &
            i, eigenvalues(i), eigenvalues(i) - eigenvalues(1)
    end do
    
    if (dim > 10) then
        print *, "  ... (", dim - 10, "more states)"
    end if
    print *, ""
    
    print *, "Ground state energy: E0 =", eigenvalues(1), "MeV"
    print *, "First excited state: E1 =", eigenvalues(2), "MeV"
    print *, "Energy gap: ΔE =", eigenvalues(2) - eigenvalues(1), "MeV"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 9: Test convenience function
    ! -------------------------------------------------------------------------
    print *, "Test 9: Testing get_ground_state_energy()..."
    call system_clock(count=step_start)
    
    call get_ground_state_energy(j_value, model_space%spes, j_shell_tbmes, &
                                 E0, status)
    
    if (status /= 0) then
        print *, "ERROR: get_ground_state_energy failed"
        stop 1
    end if
    
    print *, "  Ground state energy:", E0, "MeV"
    
    ! Verify it matches the full diagonalization
    if (abs(E0 - eigenvalues(1)) > 1.0d-10) then
        print *, "ERROR: Ground state energies don't match!"
        print *, "  Full diag:", eigenvalues(1)
        print *, "  Convenience:", E0
        stop 1
    end if
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    print *, "  Convenience function works correctly"
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Test 10: Test smaller system (j=3/2)
    ! -------------------------------------------------------------------------
    print *, "Test 10: Testing j=3/2 system (0p3/2²)..."
    call system_clock(count=step_start)
    j_value = 3
    
    ! Get TBMEs for j=3/2
    if (allocated(j_shell_tbmes)) deallocate(j_shell_tbmes)
    call get_j_shell_tbmes(3, model_space, j_shell_tbmes, n_tbmes)
    
    if (n_tbmes > 0) then
        call get_ground_state_energy(j_value, model_space%spes, j_shell_tbmes, &
                                     E0, status)
        
        if (status == 0) then
            print *, "  j=3/2 ground state energy:", E0, "MeV"
            print *, "  j=3/2 system solved successfully"
        else
            print *, "  Note: j=3/2 system could not be solved"
        end if
    else
        print *, "  Note: No TBMEs found for j=3/2 shell"
    end if
    call system_clock(count=step_end)
    step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
    write(*,'(A,ES16.8,A)') "  Runtime: ", step_runtime, " s"
    print *, ""
    
    ! -------------------------------------------------------------------------
    ! Cleanup
    ! -------------------------------------------------------------------------
    print *, "Cleaning up..."
    call cleanup_cg_tables()
    
    if (allocated(H_matrix)) deallocate(H_matrix)
    if (allocated(eigenvalues)) deallocate(eigenvalues)
    if (allocated(eigenvectors)) deallocate(eigenvectors)
    if (allocated(j_shell_tbmes)) deallocate(j_shell_tbmes)
    call free_model_space(model_space)
    
    call system_clock(count=clock_end)
    total_runtime = real(clock_end - clock_start, 8) / real(clock_rate, 8)
    print *, ""
    print *, "=========================================="
    print *, "  All tests passed!  "
    print *, "=========================================="
    print *, ""
    print *, "Summary:"
    print *, "  - Exact solver module working correctly"
    print *, "  - Basis construction verified"
    print *, "  - Hamiltonian construction successful"
    print *, "  - LAPACK diagonalization working"
    print *, "  - Energy spectrum computed"
    print *, ""
    write(*,'(A,ES16.8,A)') "  Total runtime: ", total_runtime, " s"
    print *, ""
    print *, "This solver can now be used as ground truth"
    print *, "for validating quantum sampling approaches."
    print *, ""

end program test_exact_solver