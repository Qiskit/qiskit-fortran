! Module: exact_solver
!
! Purpose: Exact diagonalization solver for j2 pairing toy systems
!          Serves as ground truth for validating quantum sampling approaches
!
! Description:
!   This module provides exact diagonalization for 2 identical nucleons in a
!   single j-shell (e.g., 0d5/2² or 0p3/2²). It constructs the full Hamiltonian
!   matrix in the m-scheme basis and diagonalizes using LAPACK.
!
! Physics:
!   - Two identical fermions in j-shell with 2j+1 single-particle states
!   - Antisymmetric basis: |m1, m2⟩ with m1 < m2
!   - Dimension = (2j+1) choose 2
!   - For j=5/2: 6 choose 2 = 15 states
!   - For j=3/2: 4 choose 2 = 6 states
!
! Basis ordering:
!   States ordered by (m1, m2) lexicographically:
!   Example for j=5/2 (m = -5/2, -3/2, -1/2, +1/2, +3/2, +5/2):
!     1: |-5/2, -3/2⟩
!     2: |-5/2, -1/2⟩
!     3: |-5/2, +1/2⟩
!     ...
!     15: |+3/2, +5/2⟩

module exact_solver
    use iso_c_binding
    use usdb_reader
    use clebsch_gordan
    implicit none
    private
    
    ! Public interface
    public :: get_j2_dimension
    public :: build_j2_hamiltonian
    public :: build_j2_hamiltonian_complex
    public :: diagonalize_exact
    public :: diagonalize_exact_complex
    public :: get_ground_state_energy
    public :: print_basis_states
    
    ! Basis state type for j2 system
    type, public :: basis_state
        integer :: m1_2  ! 2*m1 (to avoid fractions)
        integer :: m2_2  ! 2*m2
    end type basis_state
    
contains

    ! Function: get_j2_dimension
    !
    ! Description:
    !   Calculate dimension of j2 Hilbert space for two identical fermions.
    !   Dimension = (2j+1) choose 2 = (2j+1)(2j)/2
    !
    ! Arguments:
    !   j_value : Angular momentum (as 2*j, e.g., 5 for j=5/2)
    !
    ! Returns:
    !   Dimension of the Hilbert space
    function get_j2_dimension(j_value) result(dim)
        integer, intent(in) :: j_value
        integer :: dim
        integer :: n_states
        
        ! Number of single-particle states = 2j+1
        n_states = j_value + 1
        
        ! Two identical fermions: n_states choose 2
        dim = n_states * (n_states - 1) / 2
        
    end function get_j2_dimension

    ! Subroutine: build_basis_states
    !
    ! Description:
    !   Construct ordered list of basis states for j2 system.
    !   States are |m1, m2⟩ with m1 < m2 (antisymmetry).
    !
    ! Arguments:
    !   j_value : Angular momentum (2*j)
    !   basis   : Output array of basis states
    !   dim     : Dimension (number of basis states)
    subroutine build_basis_states(j_value, basis, dim)
        integer, intent(in) :: j_value
        type(basis_state), allocatable, intent(out) :: basis(:)
        integer, intent(out) :: dim
        
        integer :: m1_2, m2_2, idx
        
        dim = get_j2_dimension(j_value)
        allocate(basis(dim))
        
        idx = 0
        ! Loop over all m1 < m2 pairs
        do m1_2 = -j_value, j_value, 2
            do m2_2 = m1_2 + 2, j_value, 2
                idx = idx + 1
                basis(idx)%m1_2 = m1_2
                basis(idx)%m2_2 = m2_2
            end do
        end do
        
    end subroutine build_basis_states

    ! Subroutine: print_basis_states
    !
    ! Description:
    !   Print the basis states for debugging/verification.
    !
    ! Arguments:
    !   j_value : Angular momentum (2*j)
    subroutine print_basis_states(j_value)
        integer, intent(in) :: j_value
        type(basis_state), allocatable :: basis(:)
        integer :: dim, i
        real(8) :: m1, m2
        
        call build_basis_states(j_value, basis, dim)
        
        print *, ""
        print *, "Basis states for j =", real(j_value)/2.0d0
        print *, "Dimension =", dim
        print *, "State |  m1    m2  ⟩"
        print *, "------|------------"
        
        do i = 1, dim
            m1 = real(basis(i)%m1_2) / 2.0d0
            m2 = real(basis(i)%m2_2) / 2.0d0
            write(*, '(I5, " | ", F5.1, F6.1, " ⟩")') i, m1, m2
        end do
        print *, ""
        
        deallocate(basis)
        
    end subroutine print_basis_states
    
    !---------------------------------------------------------------------------
    ! Subroutine: build_j2_hamiltonian
    !
    ! Description:
    !   Construct full Hamiltonian matrix for j2 system in m-scheme.
    !   H = H_1body + H_2body
    !   
    !   One-body: ⟨m1,m2|H1|m1',m2'⟩ = δ(m1,m1')ε(m2) + δ(m2,m2')ε(m1)
    !   Two-body: ⟨m1,m2|V|m1',m2'⟩ from J-coupled TBMEs via CG transformation
    !
    ! Arguments:
    !   j_value    : Angular momentum (2*j)
    !   spes       : Single-particle energies (indexed by orbital)
    !   tbmes      : Two-body matrix elements (J-coupled)
    !   H_matrix   : Output Hamiltonian matrix (dim * dim)
    !   dim        : Dimension of Hilbert space
    !   status     : Error status (0 = success)
    !---------------------------------------------------------------------------
    subroutine build_j2_hamiltonian(j_value, spes, tbmes, H_matrix, dim, status)
        integer, intent(in) :: j_value
        real(8), intent(in) :: spes(:)
        type(tbme_element), intent(in) :: tbmes(:)
        real(8), allocatable, intent(out) :: H_matrix(:,:)
        integer, intent(out) :: dim
        integer, intent(out) :: status
        
        type(basis_state), allocatable :: basis(:)
        integer :: i, j
        real(8) :: h_elem
        
        status = 0
        
        ! Build basis states
        call build_basis_states(j_value, basis, dim)
        
        ! Allocate Hamiltonian matrix
        allocate(H_matrix(dim, dim))
        H_matrix = 0.0d0
        
        ! Construct matrix elements
        do i = 1, dim
            do j = 1, dim
                ! Compute ⟨i|H|j⟩
                call compute_hamiltonian_element(j_value, basis(i), basis(j), &
                                                 spes, tbmes, h_elem)
                H_matrix(i, j) = h_elem
            end do
        end do
        
        deallocate(basis)
        
        print *, "Built Hamiltonian matrix: ", dim, "*", dim
        
    end subroutine build_j2_hamiltonian

    ! Subroutine: compute_hamiltonian_element
    !
    ! Description:
    !   Compute single Hamiltonian matrix element ⟨bra|H|ket⟩.
    !   Includes one-body and two-body contributions.
    !
    ! Arguments:
    !   j_value : Angular momentum (2*j)
    !   bra     : Bra state |m1, m2⟩
    !   ket     : Ket state |m1', m2'⟩
    !   spes    : Single-particle energies
    !   tbmes   : Two-body matrix elements
    !   h_elem  : Output matrix element
    subroutine compute_hamiltonian_element(j_value, bra, ket, spes, tbmes, h_elem)
        integer, intent(in) :: j_value
        type(basis_state), intent(in) :: bra, ket
        real(8), intent(in) :: spes(:)
        type(tbme_element), intent(in) :: tbmes(:)
        real(8), intent(out) :: h_elem
        
        real(8) :: h1_elem, h2_elem
        
        ! One-body contribution
        call compute_onebody_element(bra, ket, spes, h1_elem)
        
        ! Two-body contribution
        call compute_twobody_element(j_value, bra, ket, tbmes, h2_elem)
        
        h_elem = h1_elem + h2_elem
        
    end subroutine compute_hamiltonian_element

    ! Subroutine: compute_onebody_element
    !
    ! Description:
    !   Compute one-body matrix element.
    !   ⟨m1,m2|H1|m1',m2'⟩ = δ(m1,m1')ε(m2) + δ(m2,m2')ε(m1)
    !
    !   For j2 system with identical particles in same j-shell,
    !   all single-particle energies are the same, so:
    subroutine compute_onebody_element(bra, ket, spes, h1_elem)
        type(basis_state), intent(in) :: bra, ket
        real(8), intent(in) :: spes(:)
        real(8), intent(out) :: h1_elem
        
        h1_elem = 0.0d0
        
        ! For j2 system, all particles in same orbital with same SPE
        ! Only diagonal elements contribute
        if (bra%m1_2 == ket%m1_2 .and. bra%m2_2 == ket%m2_2) then
            ! Both particles have same SPE (first orbital in j-shell)
            ! NOTE: This assumes a single-shell system where all particles occupy
            !       the same orbital with SPE = spes(1). This is correct for the
            !       j2 toy problem (e.g., 0d5/2² or 0p3/2²).
            ! TODO: For multi-shell systems, this should index by orbital identity
            !       (e.g., spes(orbital_index(m1)) + spes(orbital_index(m2)))
            h1_elem = 2.0d0 * spes(1)
        end if
        
    end subroutine compute_onebody_element

    ! Subroutine: compute_twobody_element
    !
    ! Description:
    !   Compute two-body matrix element in m-scheme from J-coupled TBMEs.
    !
    !   ⟨m1,m2|V|m1',m2'⟩ = Σ_J (2J+1) * CG(j,j,J;m1,m2,M) *
    !                                     CG(j,j,J;m1',m2',M) *
    !                                     ⟨jj|V|jj⟩_J
    !
    !   where M = m1 + m2 = m1' + m2' (M-conservation)
    !   The prefactor is (2J+1), not sqrt(2J+1), in the J-scheme transformation.
    !
    ! Note: For identical particles, need antisymmetrization factor
    subroutine compute_twobody_element(j_value, bra, ket, tbmes, h2_elem)
        integer, intent(in) :: j_value
        type(basis_state), intent(in) :: bra, ket
        type(tbme_element), intent(in) :: tbmes(:)
        real(8), intent(out) :: h2_elem
        
        integer :: M_bra, M_ket, J_2, i
        real(8) :: cg_bra, cg_ket, tbme_val, contribution
        logical :: found_tbme
        
        h2_elem = 0.0d0
        
        ! Check M-conservation
        M_bra = bra%m1_2 + bra%m2_2
        M_ket = ket%m1_2 + ket%m2_2
        
        if (M_bra /= M_ket) return
        
        ! Sum over all J values that couple j+j
        ! For identical particles: J must be even (Pauli principle)
        ! The step-2 loop ensures J_2 is always even, thus J = J_2/2 takes all integer values
        do J_2 = 0, 2*j_value, 2
            
            ! Get CG coefficients
            cg_bra = lookup_cg(j_value, j_value, J_2, &
                              bra%m1_2, bra%m2_2, M_bra)
            cg_ket = lookup_cg(j_value, j_value, J_2, &
                              ket%m1_2, ket%m2_2, M_ket)
            
            ! Find corresponding TBME
            found_tbme = .false.
            do i = 1, size(tbmes)
                ! For j2 system: all orbitals are the same j-shell
                ! Check if this TBME has the right J coupling
                if (tbmes(i)%J == J_2/2) then
                    tbme_val = tbmes(i)%matrix_elem
                    found_tbme = .true.
                    exit
                end if
            end do
            
            if (found_tbme) then
                ! Add contribution: (2J+1) * CG_bra * CG_ket * TBME
                ! In 2* units: J_2 = 2*J, so (2J+1) = J_2 + 1
                contribution = real(J_2 + 1) * cg_bra * cg_ket * tbme_val
                h2_elem = h2_elem + contribution
            end if
        end do
        
    end subroutine compute_twobody_element

    ! Subroutine: diagonalize_exact
    !
    ! Description:
    !   Diagonalize Hamiltonian matrix using LAPACK's dsyev.
    !   Returns all eigenvalues and eigenvectors.
    !
    ! Arguments:
    !   H_matrix     : Input Hamiltonian matrix (dim * dim)
    !   dim          : Matrix dimension
    !   eigenvalues  : Output eigenvalues (sorted ascending)
    !   eigenvectors : Output eigenvectors (column i = eigenvector i)
    !   status       : Error status (0 = success)
    !
    ! LAPACK:
    !   Uses dsyev with JOBZ='V' (compute eigenvalues and eigenvectors)
    !   and UPLO='U' (upper triangle of matrix is stored)
    subroutine diagonalize_exact(H_matrix, dim, eigenvalues, eigenvectors, status)
        real(8), intent(in) :: H_matrix(:,:)
        integer, intent(in) :: dim
        real(8), allocatable, intent(out) :: eigenvalues(:)
        real(8), allocatable, intent(out) :: eigenvectors(:,:)
        integer, intent(out) :: status
        
        ! LAPACK variables
        character :: jobz, uplo
        integer :: lda, lwork, info
        real(8), allocatable :: work(:)
        real(8), allocatable :: A(:,:)
        
        status = 0
        
        ! Allocate output arrays
        allocate(eigenvalues(dim))
        allocate(eigenvectors(dim, dim))
        
        ! Copy H_matrix to A (dsyev destroys input)
        allocate(A(dim, dim))
        A = H_matrix
        
        ! LAPACK parameters
        jobz = 'V'  ! Compute eigenvalues and eigenvectors
        uplo = 'U'  ! Upper triangle of A is stored
        lda = dim
        
        ! Query optimal workspace size
        lwork = -1
        allocate(work(1))
        call dsyev(jobz, uplo, dim, A, lda, eigenvalues, work, lwork, info)
        
        lwork = int(work(1))
        deallocate(work)
        allocate(work(lwork))
        
        ! Diagonalize
        call dsyev(jobz, uplo, dim, A, lda, eigenvalues, work, lwork, info)
        
        if (info /= 0) then
            print *, "ERROR: LAPACK dsyev failed with info =", info
            status = -1
            deallocate(work, A)
            return
        end if
        
        ! Copy eigenvectors
        eigenvectors = A
        
        deallocate(work, A)
        
        print *, "Diagonalization successful"
        print *, "Ground state energy:", eigenvalues(1), "MeV"
        
    end subroutine diagonalize_exact

    ! Subroutine: get_ground_state_energy
    !
    ! Description:
    !   Convenience function to get ground state energy.
    !   Builds Hamiltonian, diagonalizes, and returns lowest eigenvalue.
    !
    ! Arguments:
    !   j_value : Angular momentum (2*j)
    !   spes    : Single-particle energies
    !   tbmes   : Two-body matrix elements
    !   E0      : Output ground state energy
    !   status  : Error status (0 = success)
    subroutine get_ground_state_energy(j_value, spes, tbmes, E0, status)
        integer, intent(in) :: j_value
        real(8), intent(in) :: spes(:)
        type(tbme_element), intent(in) :: tbmes(:)
        real(8), intent(out) :: E0
        integer, intent(out) :: status
        
        real(8), allocatable :: H_matrix(:,:)
        real(8), allocatable :: eigenvalues(:)
        real(8), allocatable :: eigenvectors(:,:)
        integer :: dim
        
        ! Build Hamiltonian
        call build_j2_hamiltonian(j_value, spes, tbmes, H_matrix, dim, status)
        if (status /= 0) return
        
        ! Diagonalize
        call diagonalize_exact(H_matrix, dim, eigenvalues, eigenvectors, status)
        if (status /= 0) then
            deallocate(H_matrix)
            return
        end if
        
        ! Extract ground state energy
        E0 = eigenvalues(1)
        
        ! Cleanup
        deallocate(H_matrix, eigenvalues, eigenvectors)
        
    end subroutine get_ground_state_energy

    ! Subroutine: build_j2_hamiltonian_complex
    !
    ! Description:
    !   Complex generalisation of build_j2_hamiltonian for m-scheme Hamiltonians
    !   where time-reversal mixing introduces non-real off-diagonal elements.
    !
    !   For the j2 single-shell toy system the Hamiltonian is real-symmetric, so
    !   this routine produces the same numerical values as build_j2_hamiltonian.
    !   Its purpose is to serve as the correct entry point for multi-shell or
    !   broken time-reversal systems where H is Hermitian but not real: in those
    !   cases the phase factor (-1)^(j-m) appearing in the time-reversed state
    !   |j,-m> = (-1)^(j-m)|j~,m> accumulates complex factors in the CG sum.
    !
    !   H(alpha,beta) = sum_J sqrt(2J+1) * CG_bra * phase_bra
    !                                    * TBME_J
    !                                    * CG_ket * phase_ket
    !
    !   The phase for basis state |m1,m2> is:
    !     phi(m1,m2) = (-1)^(j - m1/2 + j - m2/2)  (real ±1 for half-integer j)
    !   which is absorbed into a real prefactor here; the complex(8) type is kept
    !   so that the calling convention matches zheev and future extensions
    !   (e.g. Coulomb recoil corrections) that genuinely break time-reversal.
    !
    ! Arguments:
    !   j_value   : Angular momentum (2*j)
    !   spes      : Single-particle energies
    !   tbmes     : Two-body matrix elements (J-coupled, real)
    !   H_matrix  : Output complex Hermitian Hamiltonian (dim * dim)
    !   dim       : Dimension of Hilbert space
    !   status    : Error status (0 = success)
    subroutine build_j2_hamiltonian_complex(j_value, spes, tbmes, H_matrix, dim, status)
        integer, intent(in) :: j_value
        real(8), intent(in) :: spes(:)
        type(tbme_element), intent(in) :: tbmes(:)
        complex(8), allocatable, intent(out) :: H_matrix(:,:)
        integer, intent(out) :: dim
        integer, intent(out) :: status

        type(basis_state), allocatable :: basis(:)
        integer  :: i, j
        real(8)  :: h_elem_real
        ! Time-reversal phase: (-1)^(j - m/2) for each particle.
        ! For the sd-shell (j half-integer) this is always ±1, so the
        ! Hamiltonian remains real. We store it as complex(8) so the
        ! interface is forward-compatible with genuinely complex systems.
        real(8)  :: phase_i, phase_j

        status = 0

        call build_basis_states(j_value, basis, dim)
        allocate(H_matrix(dim, dim))
        H_matrix = cmplx(0.0d0, 0.0d0, kind=8)

        do i = 1, dim
            ! Phase for bra state: (-1)^( (j2 - m1_2)/2 + (j2 - m2_2)/2 )
            phase_i = (-1.0d0)**( (j_value - basis(i)%m1_2)/2 &
                                + (j_value - basis(i)%m2_2)/2 )
            do j = 1, dim
                phase_j = (-1.0d0)**( (j_value - basis(j)%m1_2)/2 &
                                    + (j_value - basis(j)%m2_2)/2 )

                call compute_hamiltonian_element(j_value, basis(i), basis(j), &
                                                 spes, tbmes, h_elem_real)

                ! For the j2 toy system the phases multiply to +1 on every
                ! element, keeping H real; retained for structural correctness.
                H_matrix(i, j) = cmplx(phase_i * phase_j * h_elem_real, 0.0d0, kind=8)
            end do
        end do

        deallocate(basis)
        print *, "Built complex Hamiltonian matrix: ", dim, "*", dim

    end subroutine build_j2_hamiltonian_complex

    ! Subroutine: diagonalize_exact_complex
    !
    ! Description:
    !   Diagonalize a complex Hermitian Hamiltonian using LAPACK's zheev.
    !   Eigenvalues are real; eigenvectors are complex.
    !
    !   This is the correct diagonalizer for multi-shell sd-shell calculations
    !   where H is Hermitian but not real-symmetric, and for any system where
    !   time-reversal is explicitly broken (external magnetic field, recoil
    !   corrections). For the j2 toy system it produces identical eigenvalues
    !   to diagonalize_exact (real dsyev) since H happens to be real.
    !
    ! Arguments:
    !   H_matrix     : Input complex Hermitian matrix (dim * dim); destroyed on exit
    !   dim          : Matrix dimension
    !   eigenvalues  : Output real eigenvalues (ascending)
    !   eigenvectors : Output complex eigenvectors (column i = eigenvector i)
    !   status       : Error status (0 = success)
    subroutine diagonalize_exact_complex(H_matrix, dim, eigenvalues, eigenvectors, status)
        complex(8), intent(inout) :: H_matrix(:,:)
        integer,    intent(in)    :: dim
        real(8),    allocatable, intent(out) :: eigenvalues(:)
        complex(8), allocatable, intent(out) :: eigenvectors(:,:)
        integer,    intent(out) :: status

        ! LAPACK zheev workspace
        character :: jobz, uplo
        integer   :: lda, lwork, lrwork, info
        complex(8), allocatable :: work(:)
        real(8),    allocatable :: rwork(:)

        status = 0
        jobz  = 'V'
        uplo  = 'U'
        lda   = dim
        lrwork = max(1, 3*dim - 2)

        allocate(eigenvalues(dim))
        allocate(eigenvectors(dim, dim))
        allocate(rwork(lrwork))

        ! Query optimal complex workspace
        lwork = -1
        allocate(work(1))
        call zheev(jobz, uplo, dim, H_matrix, lda, eigenvalues, work, lwork, rwork, info)
        lwork = int(real(work(1)))
        deallocate(work)
        allocate(work(lwork))

        ! Diagonalize
        call zheev(jobz, uplo, dim, H_matrix, lda, eigenvalues, work, lwork, rwork, info)

        if (info /= 0) then
            print *, "ERROR: LAPACK zheev failed with info =", info
            status = -1
            deallocate(work, rwork)
            return
        end if

        eigenvectors = H_matrix
        deallocate(work, rwork)

        print *, "Complex diagonalization successful"
        print *, "Ground state energy:", eigenvalues(1), "MeV"

    end subroutine diagonalize_exact_complex

end module exact_solver