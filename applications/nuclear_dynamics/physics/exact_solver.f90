! Module: exact_solver
!
! Purpose: Shell-model Hamiltonian construction and exact diagonalization.
!
! Primary path (nuclear subspace diagonalization):
!   build_subspace_hamiltonian — builds H restricted to the QPU-sampled bitstring
!     subspace (Mj=0, even-parity filtered Slater determinants).
!   diagonalize_exact_complex  — LAPACK zheev; lowest eigenvalue = variational E₀.
!
! Offline oracle path (add a new nucleus):
!   build_sd_hamiltonian — full-CI enumeration of all Mj=0 even-parity sd-shell states.
!   Pair with diagonalize_exact_complex to obtain the exact USDB ground-state energy.
!
! j2 toy-model path (single-shell pairing validation):
!   build_j2_hamiltonian / build_j2_hamiltonian_complex / diagonalize_exact
!   Two identical fermions in one j-shell; dim = C(2j+1, 2).

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

    public :: build_subspace_hamiltonian
    public :: build_sd_hamiltonian
    public :: rank_pairs_by_tbme

    public :: diagonalize_exact
    public :: diagonalize_exact_complex

    ! Basis state type for j2 system
    type, public :: basis_state
        integer :: m1_2  ! 2*m1 (to avoid fractions)
        integer :: m2_2  ! 2*m2
    end type basis_state

    ! Single-particle state descriptor for multi-orbital sd-shell
    type :: sp_state
        integer :: orb_idx  ! 1-based orbital index (matches .snt)
        integer :: j2       ! 2*j
        integer :: mj2      ! 2*mj
        integer :: tz       ! -1 proton, +1 neutron
        integer :: l        ! orbital l
        real(8) :: spe      ! single-particle energy (MeV)
    end type sp_state

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

    ! Subroutine: build_j2_hamiltonian
    !
    ! Description:
    !   Construct full Hamiltonian matrix for j2 system in m-scheme.
    !   H = H_1body + H_2body
    !
    !   One-body: diagonal; both particles share the same SPE for a single-shell system.
    !   Two-body: from J-coupled TBMEs via CG transformation.
    !
    ! Arguments:
    !   j_value    : Angular momentum (2*j)
    !   spe        : Single-particle energy for this j-shell (MeV); looked up by caller from .snt
    !   tbmes      : Two-body matrix elements (J-coupled)
    !   H_matrix   : Output Hamiltonian matrix (dim * dim)
    !   dim        : Dimension of Hilbert space
    !   status     : Error status (0 = success)
    subroutine build_j2_hamiltonian(j_value, spe, tbmes, H_matrix, dim, status)
        integer, intent(in) :: j_value
        real(8), intent(in) :: spe
        type(tbme_element), intent(in) :: tbmes(:)
        real(8), allocatable, intent(out) :: H_matrix(:,:)
        integer, intent(out) :: dim
        integer, intent(out) :: status

        type(basis_state), allocatable :: basis(:)
        integer :: i, j
        real(8) :: h_elem

        status = 0

        call build_basis_states(j_value, basis, dim)

        allocate(H_matrix(dim, dim))
        H_matrix = 0.0d0

        do i = 1, dim
            do j = 1, dim
                call compute_hamiltonian_element(j_value, basis(i), basis(j), &
                                                 spe, tbmes, h_elem)
                H_matrix(i, j) = h_elem
            end do
        end do

        deallocate(basis)

    end subroutine build_j2_hamiltonian

    ! Subroutine: compute_hamiltonian_element
    subroutine compute_hamiltonian_element(j_value, bra, ket, spe, tbmes, h_elem)
        integer, intent(in) :: j_value
        type(basis_state), intent(in) :: bra, ket
        real(8), intent(in) :: spe
        type(tbme_element), intent(in) :: tbmes(:)
        real(8), intent(out) :: h_elem

        real(8) :: h1_elem, h2_elem

        call compute_onebody_element(bra, ket, spe, h1_elem)
        call compute_twobody_element(j_value, bra, ket, tbmes, h2_elem)

        h_elem = h1_elem + h2_elem

    end subroutine compute_hamiltonian_element

    ! Subroutine: compute_onebody_element
    !
    ! Description:
    !   One-body diagonal: <m1,m2|H1|m1,m2> = 2 * spe (same shell, same SPE for both particles).
    !   spe is passed as a scalar by the caller, who reads it from .snt via usdb_reader.
    subroutine compute_onebody_element(bra, ket, spe, h1_elem)
        type(basis_state), intent(in) :: bra, ket
        real(8), intent(in) :: spe
        real(8), intent(out) :: h1_elem

        h1_elem = 0.0d0
        if (bra%m1_2 == ket%m1_2 .and. bra%m2_2 == ket%m2_2) then
            h1_elem = 2.0d0 * spe
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
        
        ! Sum over all J values that couple j+j.
        ! For identical fermions in the same j-shell: only even J are allowed (Pauli).
        ! J is even when J_2 (= 2*J) is a multiple of 4.  Step by 4.
        do J_2 = 0, 2*j_value, 4
            
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

    end subroutine diagonalize_exact


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
    !     phi(m1,m2) = (-1)^(j; m1/2 + j; m2/2)  (real ±1 for half-integer j)
    !   which is absorbed into a real prefactor here; the complex(8) type is kept
    !   so that the calling convention matches zheev and future extensions
    !   (e.g. Coulomb recoil corrections) that genuinely break time-reversal.
    !
    ! Arguments:
    !   j_value   : Angular momentum (2*j)
    !   spe       : Single-particle energy for this j-shell (MeV); caller reads from .snt
    !   tbmes     : Two-body matrix elements (J-coupled, real)
    !   H_matrix  : Output complex Hermitian Hamiltonian (dim * dim)
    !   dim       : Dimension of Hilbert space
    !   status    : Error status (0 = success)
    subroutine build_j2_hamiltonian_complex(j_value, spe, tbmes, H_matrix, dim, status)
        integer, intent(in) :: j_value
        real(8), intent(in) :: spe
        type(tbme_element), intent(in) :: tbmes(:)
        complex(8), allocatable, intent(out) :: H_matrix(:,:)
        integer, intent(out) :: dim
        integer, intent(out) :: status

        type(basis_state), allocatable :: basis(:)
        integer  :: i, j
        real(8)  :: h_elem_real
        ! Time-reversal phase: (-1)^(j; m/2) for each particle.
        ! For the sd-shell (j half-integer) this is always ±1, so the
        ! Hamiltonian remains real. We store it as complex(8) so the
        ! interface is forward-compatible with genuinely complex systems.
        real(8)  :: phase_i, phase_j

        status = 0

        call build_basis_states(j_value, basis, dim)
        allocate(H_matrix(dim, dim))
        H_matrix = cmplx(0.0d0, 0.0d0, kind=8)

        do i = 1, dim
            ! Phase for bra state: (-1)^( (j2-m1_2)/2 + (j2-m2_2)/2 )
            phase_i = (-1.0d0)**( (j_value - basis(i)%m1_2)/2 &
                                + (j_value - basis(i)%m2_2)/2 )
            do j = 1, dim
                phase_j = (-1.0d0)**( (j_value - basis(j)%m1_2)/2 &
                                    + (j_value - basis(j)%m2_2)/2 )

                call compute_hamiltonian_element(j_value, basis(i), basis(j), &
                                                 spe, tbmes, h_elem_real)

                ! For the j2 toy system the phases multiply to +1 on every
                ! element, keeping H real; retained for structural correctness.
                H_matrix(i, j) = cmplx(phase_i * phase_j * h_elem_real, 0.0d0, kind=8)
            end do
        end do

        deallocate(basis)
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
        jobz  = 'V'   ! eigenvalues and eigenvectors — needed for overlap verification
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

        ! zheev (JOBZ='V') writes eigenvectors into H_matrix; copy out
        eigenvectors = H_matrix
        deallocate(work, rwork)

    end subroutine diagonalize_exact_complex

    subroutine build_sd_hamiltonian(ms, n_protons, n_neutrons, H_matrix, dim, status, &
                                     mj2_target)
        type(model_space_data), intent(in)  :: ms
        integer,                intent(in)  :: n_protons, n_neutrons
        complex(8), allocatable, intent(out) :: H_matrix(:,:)
        integer,                intent(out) :: dim
        integer,                intent(out) :: status
        integer,      optional, intent(in)  :: mj2_target  ! 2*Mj target sector; default 0 (Mj=0)

        ! Single-particle basis: all m-substates across all orbitals
        type(sp_state), allocatable :: sp(:)
        integer :: n_sp, n_sp_p, n_sp_n
        integer :: mj2_tgt

        ! Many-body Slater-determinant basis
        ! Each basis state is stored as a bitmask over sp states (1..n_sp).
        ! We use integer arrays of size n_sp per state to keep it general.
        integer, allocatable :: sd_basis(:,:)   ! (n_sp, dim): 0/1 occupation

        integer :: i, j, k, alpha, beta, cnt
        integer :: p, q, r, s_idx   ! orbital indices for TBME
        integer :: n_occ
        real(8) :: h_elem
        integer :: Mj2_tot, par_tot

        mj2_tgt = 0
        if (present(mj2_target)) mj2_tgt = mj2_target
        status = 0

        ! ---------------------------------------------------------------
        ! Build single-particle basis: enumerate all m-substates
        ! Ordering: proton orbitals first (tz=-1), neutron orbitals second
        ! Within each orbital: descending mj
        ! ---------------------------------------------------------------
        n_sp = 0
        do i = 1, ms%n_orbitals
            n_sp = n_sp + ms%orbitals(i)%j2 + 1
        end do

        allocate(sp(n_sp))
        k = 0
        do j = -1, 1, 2   ! tz: protons first (-1), then neutrons (+1)
            do i = 1, ms%n_orbitals
                if (ms%orbitals(i)%tz /= j) cycle
                block
                    integer :: m2
                    do m2 = ms%orbitals(i)%j2, -ms%orbitals(i)%j2, -2
                        k = k + 1
                        sp(k)%orb_idx = ms%orbitals(i)%idx
                        sp(k)%j2      = ms%orbitals(i)%j2
                        sp(k)%mj2     = m2
                        sp(k)%tz      = ms%orbitals(i)%tz
                        sp(k)%l       = ms%orbitals(i)%l
                        sp(k)%spe     = ms%spes(ms%orbitals(i)%idx)
                    end do
                end block
            end do
        end do
        n_sp_p = count(sp(:)%tz == -1)
        n_sp_n = n_sp - n_sp_p

        ! ---------------------------------------------------------------
        ! Count basis states: all N_p proton + N_n neutron Slater dets
        ! with Mj_tot = 0 and parity = 0 (even)
        ! ---------------------------------------------------------------
        dim = 0
        call count_sd_basis(sp, n_sp, n_sp_p, n_protons, n_neutrons, dim, mj2_tgt)
        if (dim == 0) then
            print *, "ERROR: build_sd_hamiltonian: no basis states found"
            status = -1
            deallocate(sp)
            return
        end if

        allocate(sd_basis(n_sp, dim))
        call fill_sd_basis(sp, n_sp, n_sp_p, n_protons, n_neutrons, sd_basis, dim, mj2_tgt)


        ! ---------------------------------------------------------------
        ! Build Hamiltonian: H(alpha,beta) = <alpha|H1+H2|beta>
        ! Each thread owns its alpha row completely — computes both H(alpha,beta)
        ! and H(beta,alpha), avoiding write conflicts without critical sections.
        ! Dynamic scheduling: row work decreases as alpha grows (triangular).
        ! ---------------------------------------------------------------
        allocate(H_matrix(dim, dim))
        H_matrix = cmplx(0.0d0, 0.0d0, kind=8)

        !$OMP PARALLEL DO SCHEDULE(DYNAMIC,4) PRIVATE(i,beta,h_elem)
        do alpha = 1, dim
            ! One-body: diagonal — sum of SPEs + core energy (¹⁶O reference)
            H_matrix(alpha, alpha) = cmplx(ms%core_energy, 0.0d0, kind=8)
            do i = 1, n_sp
                if (sd_basis(i, alpha) == 1) then
                    H_matrix(alpha, alpha) = H_matrix(alpha, alpha) &
                        + cmplx(sp(i)%spe, 0.0d0, kind=8)
                end if
            end do

            ! Two-body: full row (alpha,1..dim).
            ! Each thread owns its alpha row completely — no write conflicts since
            ! thread for alpha writes H(alpha,*) and thread for beta writes H(beta,*).
            ! Off-diagonal elements are computed redundantly (alpha and beta both
            ! evaluate the same V_ms value) to avoid synchronization.
            ! Diagonal two-body term (beta==alpha) is computed separately to add
            ! to the already-set one-body diagonal.
            do beta = 1, dim
                h_elem = 0.0d0
                call compute_sd_twobody(sp, n_sp, sd_basis(:,alpha), sd_basis(:,beta), &
                                         ms%tbmes, ms%n_tbme, h_elem)
                if (beta == alpha) then
                    ! Add two-body diagonal to one-body diagonal already in place
                    H_matrix(alpha, alpha) = H_matrix(alpha, alpha) + cmplx(h_elem, 0.0d0, kind=8)
                else
                    H_matrix(alpha, beta) = cmplx(h_elem, 0.0d0, kind=8)
                end if
            end do
        end do
        !$OMP END PARALLEL DO

        deallocate(sp, sd_basis)

    end subroutine build_sd_hamiltonian


    ! count_sd_basis / fill_sd_basis
    ! Shared combination-iteration logic; split to avoid passing unallocated arrays.

    subroutine count_sd_basis(sp, n_sp, n_sp_p, n_protons, n_neutrons, dim, mj2_target)
        type(sp_state), intent(in)  :: sp(:)
        integer,        intent(in)  :: n_sp, n_sp_p, n_protons, n_neutrons
        integer,        intent(out) :: dim
        integer,        intent(in)  :: mj2_target   ! 2*Mj sector to enumerate
        integer :: n_sp_n, pi(n_protons), ni(n_neutrons), ip, in_, k, Mj2, par
        n_sp_n = n_sp - n_sp_p
        dim = 0
        do k = 1, n_protons; pi(k) = k; end do
        do
            do k = 1, n_neutrons; ni(k) = n_sp_p + k; end do
            do
                Mj2 = 0; par = 0
                do k = 1, n_protons
                    Mj2 = Mj2 + sp(pi(k))%mj2
                    par = ieor(par, sp(pi(k))%l)
                end do
                do k = 1, n_neutrons
                    Mj2 = Mj2 + sp(ni(k))%mj2
                    par = ieor(par, sp(ni(k))%l)
                end do
                if (Mj2 == mj2_target .and. mod(par, 2) == 0) dim = dim + 1
                in_ = n_neutrons
                do while (in_ >= 1 .and. ni(in_) == n_sp_p + n_sp_n - (n_neutrons - in_))
                    in_ = in_ - 1
                end do
                if (in_ < 1) exit
                ni(in_) = ni(in_) + 1
                do k = in_ + 1, n_neutrons; ni(k) = ni(k-1) + 1; end do
            end do
            ip = n_protons
            do while (ip >= 1 .and. pi(ip) == n_sp_p - (n_protons - ip))
                ip = ip - 1
            end do
            if (ip < 1) exit
            pi(ip) = pi(ip) + 1
            do k = ip + 1, n_protons; pi(k) = pi(k-1) + 1; end do
        end do
    end subroutine count_sd_basis


    subroutine fill_sd_basis(sp, n_sp, n_sp_p, n_protons, n_neutrons, sd_basis, dim, mj2_target)
        type(sp_state), intent(in)  :: sp(:)
        integer,        intent(in)  :: n_sp, n_sp_p, n_protons, n_neutrons, dim
        integer,        intent(out) :: sd_basis(n_sp, dim)
        integer,        intent(in)  :: mj2_target   ! 2*Mj sector to enumerate
        integer :: n_sp_n, pi(n_protons), ni(n_neutrons), ip, in_, k, Mj2, par, cnt
        integer :: occ(n_sp)
        n_sp_n = n_sp - n_sp_p
        cnt = 0
        do k = 1, n_protons; pi(k) = k; end do
        do
            do k = 1, n_neutrons; ni(k) = n_sp_p + k; end do
            do
                Mj2 = 0; par = 0
                do k = 1, n_protons
                    Mj2 = Mj2 + sp(pi(k))%mj2
                    par = ieor(par, sp(pi(k))%l)
                end do
                do k = 1, n_neutrons
                    Mj2 = Mj2 + sp(ni(k))%mj2
                    par = ieor(par, sp(ni(k))%l)
                end do
                if (Mj2 == mj2_target .and. mod(par, 2) == 0) then
                    cnt = cnt + 1
                    occ = 0
                    do k = 1, n_protons; occ(pi(k)) = 1; end do
                    do k = 1, n_neutrons; occ(ni(k)) = 1; end do
                    sd_basis(:, cnt) = occ
                end if
                in_ = n_neutrons
                do while (in_ >= 1 .and. ni(in_) == n_sp_p + n_sp_n - (n_neutrons - in_))
                    in_ = in_ - 1
                end do
                if (in_ < 1) exit
                ni(in_) = ni(in_) + 1
                do k = in_ + 1, n_neutrons; ni(k) = ni(k-1) + 1; end do
            end do
            ip = n_protons
            do while (ip >= 1 .and. pi(ip) == n_sp_p - (n_protons - ip))
                ip = ip - 1
            end do
            if (ip < 1) exit
            pi(ip) = pi(ip) + 1
            do k = ip + 1, n_protons; pi(k) = pi(k-1) + 1; end do
        end do
    end subroutine fill_sd_basis


    ! Subroutine: compute_sd_twobody
    !
    ! Compute two-body contribution to <alpha|V|beta> using Slater-Condon rules.
    !
    ! The m-scheme two-body antisymmetric matrix element is:
    !   V_ms(p,q;r,s) = sum_J (2J+1) * CG(jp,jq;J|mp,mq) * CG(jr,js;J|mr,ms) * <pq;J|V|rs;J>
    !
    ! Slater-Condon rules (for a N-body Slater determinant basis):
    !   |alpha> and |beta> differ by 0 sp states (diagonal, alpha==beta):
    !     <alpha|V2|alpha> = sum_{i<j in alpha} V_ms(i,j;i,j)
    !   Differ by 2 sp states (alpha has {p,shared}, beta has {q,shared}; p in alpha not beta,
    !     q in beta not alpha):
    !     <alpha|V2|beta> = phase * sum_{j in both} V_ms(p,j;q,j)
    !   Differ by 4 sp states ({p1,p2} in alpha not beta, {q1,q2} in beta not alpha):
    !     <alpha|V2|beta> = phase * V_ms(p1,p2;q1,q2)
    !   Differ by > 4: zero.
    !
    ! Phase from bringing annihilation/creation operators to normal order: (-1)^(number of
    ! occupied states between the creation/annihilation positions in the ordered list).
    subroutine compute_sd_twobody(sp, n_sp, occ_a, occ_b, tbmes, n_tbme, h_elem)
        type(sp_state), intent(in)  :: sp(:)
        integer,        intent(in)  :: n_sp, n_tbme
        integer,        intent(in)  :: occ_a(:), occ_b(:)
        type(tbme_element), intent(in) :: tbmes(:)
        real(8),        intent(out) :: h_elem

        integer :: n_diff, diff_a(4), diff_b(4), cnt_a, cnt_b
        integer :: i, j, p, q, r, s_idx, t
        integer :: J_2, J2_min, J2_max
        real(8) :: cg_bra, cg_ket, tbme_val, v_ms
        integer :: phase, k

        h_elem = 0.0d0

        ! Find differences: states in alpha not in beta, and vice versa
        cnt_a = 0; cnt_b = 0
        do i = 1, n_sp
            if (occ_a(i) == 1 .and. occ_b(i) == 0) then
                cnt_a = cnt_a + 1
                if (cnt_a <= 4) diff_a(cnt_a) = i
            else if (occ_a(i) == 0 .and. occ_b(i) == 1) then
                cnt_b = cnt_b + 1
                if (cnt_b <= 4) diff_b(cnt_b) = i
            end if
        end do
        n_diff = cnt_a   ! = cnt_b (particle-number conservation enforced at basis level)

        if (n_diff > 2) return   ! zero by Slater-Condon

        select case (n_diff)

        case (0)
            ! Diagonal: <alpha|V2|alpha> = sum_{i<j occ} V_ms(i,j;i,j)
            do i = 1, n_sp
                if (occ_a(i) == 0) cycle
                do j = i + 1, n_sp
                    if (occ_a(j) == 0) cycle
                    call v_ms_elem(sp, tbmes, n_tbme, i, j, i, j, v_ms)
                    h_elem = h_elem + v_ms
                end do
            end do

        case (1)
            ! One excitation: p -> q
            p = diff_a(1)   ! in alpha, not beta
            q = diff_b(1)   ! in beta, not alpha

            ! Phase: (-1)^(number of occupied states between p and q in alpha)
            phase = 1
            do k = min(p,q)+1, max(p,q)-1
                if (occ_a(k) == 1) phase = -phase
            end do

            ! <alpha|V2|beta> = phase * sum_{j in both} V_ms(p,j;q,j)
            do j = 1, n_sp
                if (j == p .or. j == q) cycle
                if (occ_a(j) == 0) cycle   ! j must be in both alpha and beta
                call v_ms_elem(sp, tbmes, n_tbme, p, j, q, j, v_ms)
                h_elem = h_elem + real(phase, 8) * v_ms
            end do

        case (2)
            ! Two excitations: (p1,p2) -> (q1,q2)
            p = diff_a(1); r = diff_a(2)   ! in alpha, not beta (p < r by construction)
            q = diff_b(1); s_idx = diff_b(2)  ! in beta, not alpha (q < s by construction)

            ! Phase: product of occupied states between each creation/annihilation position
            phase = 1
            do k = p+1, r-1
                if (occ_a(k) == 1) phase = -phase
            end do
            do k = q+1, s_idx-1
                if (occ_b(k) == 1) phase = -phase
            end do

            call v_ms_elem(sp, tbmes, n_tbme, p, r, q, s_idx, v_ms)
            h_elem = real(phase, 8) * v_ms

        end select

    end subroutine compute_sd_twobody


    ! v_ms_elem: compute V_ms(p,q;r,s) antisymmetric m-scheme element.
    !
    ! The USDB TBMEs are stored as normalized antisymmetric J-scheme elements
    ! with standard ordering a<=b, c<=d (same-orbital index ordering as in .snt).
    !
    ! The m-scheme conversion (no extra normalization needed because the CG
    ! decomposition of the normalized antisymmetric ket gives the correct factor):
    !   <pq|V|rs>_AS = sum_J CG(jp,jq;J|mp,mq) * CG(jr,js;J|mr,ms) * V_J_USDB(a,b,c,d)
    !
    ! When the bra/ket orbital pairs come in non-standard order (a>b or c>d),
    ! the antisymmetry phase -(-1)^{ja+jb-J} must be applied.
    ! When using Hermitian symmetry (swapping bra and ket), V is real so V_J(ab,cd)=V_J(cd,ab).
    subroutine v_ms_elem(sp, tbmes, n_tbme, p, q, r, s_idx, result)
        type(sp_state),     intent(in)  :: sp(:)
        type(tbme_element), intent(in)  :: tbmes(:)
        integer,            intent(in)  :: n_tbme, p, q, r, s_idx
        real(8),            intent(out) :: result

        integer :: J_2, J2_min, J2_max, t
        real(8) :: cg_bra, cg_ket, tbme_val
        integer :: M_bra, M_ket
        integer :: pa, pb, rc, sd   ! canonical-order sp indices for bra/ket
        real(8) :: phase_bra, phase_ket

        result = 0.0d0
        M_bra = sp(p)%mj2 + sp(q)%mj2
        M_ket = sp(r)%mj2 + sp(s_idx)%mj2
        if (M_bra /= M_ket) return
        if (sp(p)%tz + sp(q)%tz /= sp(r)%tz + sp(s_idx)%tz) return

        ! Canonicalize bra: pa <= pb by sp index (not by orbital index)
        ! The antisymmetry phase from swapping p <-> q in the bra:
        !   CG(jp,jq;J|mp,mq) = (-1)^{jp+jq-J} * CG(jq,jp;J|mq,mp)
        ! Because |pq>_AS = -|qp>_AS, swapping gives a sign.
        ! We keep p < q by sp array index (which sorts by orbital within each species,
        ! so same orbital can appear with different mj), and track whether we swapped.
        if (p <= q) then
            pa = p; pb = q; phase_bra = 1.0d0
        else
            pa = q; pb = p
            ! phase = (-1)^{(j_p + j_q - J)/1} but J-dependent; defer to J loop below
            phase_bra = -1.0d0
        end if

        if (r <= s_idx) then
            rc = r; sd = s_idx; phase_ket = 1.0d0
        else
            rc = s_idx; sd = r
            phase_ket = -1.0d0
        end if

        J2_min = max(abs(sp(pa)%j2 - sp(pb)%j2), abs(sp(rc)%j2 - sp(sd)%j2))
        J2_max = min(sp(pa)%j2 + sp(pb)%j2,      sp(rc)%j2 + sp(sd)%j2)

        do J_2 = J2_min, J2_max, 2
            cg_bra = lookup_cg(sp(pa)%j2, sp(pb)%j2, J_2, sp(pa)%mj2, sp(pb)%mj2, M_bra)
            if (abs(cg_bra) < 1.0d-12) cycle
            cg_ket = lookup_cg(sp(rc)%j2, sp(sd)%j2, J_2, sp(rc)%mj2, sp(sd)%mj2, M_ket)
            if (abs(cg_ket) < 1.0d-12) cycle

            ! Look up USDB TBME by orbital index — try direct and Hermitian-conjugate ordering
            tbme_val = 0.0d0
            do t = 1, n_tbme
                if (tbmes(t)%J /= J_2 / 2) cycle
                if ((tbmes(t)%a == sp(pa)%orb_idx .and. tbmes(t)%b == sp(pb)%orb_idx .and. &
                     tbmes(t)%c == sp(rc)%orb_idx .and. tbmes(t)%d == sp(sd)%orb_idx) .or. &
                    (tbmes(t)%a == sp(rc)%orb_idx .and. tbmes(t)%b == sp(sd)%orb_idx .and. &
                     tbmes(t)%c == sp(pa)%orb_idx .and. tbmes(t)%d == sp(pb)%orb_idx)) then
                    tbme_val = tbmes(t)%matrix_elem
                    exit
                end if
            end do
            if (abs(tbme_val) < 1.0d-15) cycle

            result = result + phase_bra * phase_ket * cg_bra * cg_ket * tbme_val
        end do

    end subroutine v_ms_elem

    ! Subroutine: build_subspace_hamiltonian
    !
    ! Build a Hamiltonian restricted to the subspace spanned by the symmetry-kept
    ! bitstrings from the quantum sampler.  This is the nuclear subspace
    ! diagonalization Hamiltonian: only Slater determinants that actually
    ! appeared in the IBM Runtime output
    ! (after Mj=0 + even-parity filtering) are included in the basis.
    !
    ! Arguments:
    !   ms              : Populated model_space_data (from read_usdb_file)
    !   n_protons       : Number of valence protons
    !   n_neutrons      : Number of valence neutrons
    !   bitstrings      : (n_qubits, n_samples) — '0'/'1' character array
    !   kept_idx        : Indices (1-based) of the n_kept bitstrings that passed the filter
    !   n_kept          : Number of kept bitstrings
    !   n_qubits        : Total qubits (= n_sp proton + neutron substates)
    !   H_matrix        : Output complex Hermitian Hamiltonian (dim × dim)
    !   dim             : Number of unique Slater determinants in the subspace
    !   basis_map       : Maps subspace column i → kept_idx index (for overlap)
    !   status          : 0 = success, -1 = failure
    subroutine build_subspace_hamiltonian(ms, n_protons, n_neutrons, &
        bitstrings, kept_idx, n_kept, n_qubits, &
        H_matrix, dim, basis_map, status)
        use iso_c_binding, only: c_char
        type(model_space_data), intent(in)   :: ms
        integer,                intent(in)   :: n_protons, n_neutrons
        character(kind=c_char), intent(in)   :: bitstrings(:,:)
        integer,                intent(in)   :: kept_idx(:)
        integer,                intent(in)   :: n_kept, n_qubits
        complex(8), allocatable, intent(out) :: H_matrix(:,:)
        integer,                intent(out)  :: dim
        integer, allocatable,   intent(out)  :: basis_map(:)
        integer,                intent(out)  :: status

        type(sp_state), allocatable :: sp(:)
        integer :: n_sp, n_sp_p
        integer, allocatable :: sd_basis(:,:)   ! (n_sp, n_kept) — candidate occupations
        integer, allocatable :: occ_tmp(:)
        integer :: i, j, alpha, beta, idx, b, n_unique
        integer, allocatable :: unique_map(:)   ! unique_map(i) = kept_idx index for basis col i
        real(8) :: h_elem
        logical :: is_dup

        status = 0

        ! Build sp array (same ordering as build_sd_hamiltonian)
        n_sp = 0
        do i = 1, ms%n_orbitals
            n_sp = n_sp + ms%orbitals(i)%j2 + 1
        end do
        allocate(sp(n_sp))
        j = 0
        do alpha = -1, 1, 2
            do i = 1, ms%n_orbitals
                if (ms%orbitals(i)%tz /= alpha) cycle
                block
                    integer :: m2
                    do m2 = ms%orbitals(i)%j2, -ms%orbitals(i)%j2, -2
                        j = j + 1
                        sp(j)%orb_idx = ms%orbitals(i)%idx
                        sp(j)%j2      = ms%orbitals(i)%j2
                        sp(j)%mj2     = m2
                        sp(j)%tz      = ms%orbitals(i)%tz
                        sp(j)%l       = ms%orbitals(i)%l
                        sp(j)%spe     = ms%spes(ms%orbitals(i)%idx)
                    end do
                end block
            end do
        end do
        n_sp_p = count(sp(:)%tz == -1)

        if (n_qubits /= n_sp) then
            print *, "ERROR build_subspace_hamiltonian: n_qubits /= n_sp", n_qubits, n_sp
            status = -1
            deallocate(sp)
            return
        end if

        if (n_kept == 0) then
            print *, "ERROR build_subspace_hamiltonian: no kept bitstrings"
            status = -1
            deallocate(sp)
            return
        end if

        ! Convert each kept bitstring to an occupation vector; deduplicate
        allocate(sd_basis(n_sp, n_kept))
        allocate(unique_map(n_kept))
        allocate(occ_tmp(n_sp))
        n_unique = 0

        do i = 1, n_kept
            idx = kept_idx(i)
            do j = 1, n_sp
                b = ichar(bitstrings(j, idx)) - 48
                occ_tmp(j) = b
            end do
            ! Check for duplicate
            is_dup = .false.
            do alpha = 1, n_unique
                if (all(sd_basis(:, alpha) == occ_tmp)) then
                    is_dup = .true.
                    exit
                end if
            end do
            if (.not. is_dup) then
                n_unique = n_unique + 1
                sd_basis(:, n_unique) = occ_tmp
                unique_map(n_unique) = i
            end if
        end do

        dim = n_unique
        allocate(basis_map(dim))
        basis_map = unique_map(1:dim)


        ! Build H_matrix over the deduplicated subspace.
        ! One-body (diagonal SPE + core) and two-body are separated so the full
        ! (alpha, beta) pair loop is data-independent and can use COLLAPSE(2).
        ! Thread alpha writes H(alpha,beta); thread beta writes H(beta,alpha) for
        ! the same element — but since beta iterates 1..dim for every alpha, each
        ! H(i,j) is written exactly once (by the thread owning alpha=i). No races.
        allocate(H_matrix(dim, dim))
        H_matrix = cmplx(0.0d0, 0.0d0, kind=8)

        ! One-body diagonal: SPE sum + core energy (serial; dim iterations, cheap)
        do alpha = 1, dim
            H_matrix(alpha, alpha) = cmplx(ms%core_energy, 0.0d0, kind=8)
            do i = 1, n_sp
                if (sd_basis(i, alpha) == 1) &
                    H_matrix(alpha, alpha) = H_matrix(alpha, alpha) &
                        + cmplx(sp(i)%spe, 0.0d0, kind=8)
            end do
        end do

        ! Two-body: embarrassingly parallel over all (alpha,beta) pairs.
        ! COLLAPSE(2) exposes dim^2 independent work units to the scheduler.
        !$OMP PARALLEL DO COLLAPSE(2) SCHEDULE(DYNAMIC,8) PRIVATE(h_elem)
        do alpha = 1, dim
            do beta = 1, dim
                h_elem = 0.0d0
                call compute_sd_twobody(sp, n_sp, sd_basis(:,alpha), sd_basis(:,beta), &
                                         ms%tbmes, ms%n_tbme, h_elem)
                if (abs(h_elem) > 0.0d0) then
                    if (beta == alpha) then
                        H_matrix(alpha, alpha) = H_matrix(alpha, alpha) &
                            + cmplx(h_elem, 0.0d0, kind=8)
                    else
                        H_matrix(alpha, beta) = cmplx(h_elem, 0.0d0, kind=8)
                    end if
                end if
            end do
        end do
        !$OMP END PARALLEL DO

        deallocate(sp, sd_basis, unique_map, occ_tmp)

    end subroutine build_subspace_hamiltonian

    ! Subroutine: rank_pairs_by_tbme
    !
    ! Reorders CG-filtered particle-hole pairs by descending |V_ms(h,h;v,v)|
    ! — the diagonal m-scheme TBME that drives the ADAPT gradient at the HF
    ! reference.  Pairs with larger |V_ms| drive the largest first-order energy
    ! correction and should appear first in the Givens-rotation circuit so they
    ! are applied to the freshest state.
    !
    ! Only the ordering is changed; the pair list itself is not pruned further.
    ! Also returns the raw V_ms values so the caller can use them for MP2 angle
    ! initialisation without re-computing them.
    !
    ! Arguments:
    !   ms            : Populated model_space_data
    !   filtered_pairs: (n_pairs, 2) — col1=hole qubit (0-based), col2=virtual qubit
    !   n_pairs       : Number of pairs
    !   ranked_pairs  : Output — same pairs, sorted by |V_ms| descending
    !   tbme_weights  : Output — V_ms(h,h;v,v) for each ranked pair (MeV)
    subroutine rank_pairs_by_tbme(ms, filtered_pairs, n_pairs, ranked_pairs, tbme_weights)
        use iso_c_binding, only: c_int
        type(model_space_data), intent(in)  :: ms
        integer(c_int),         intent(in)  :: filtered_pairs(:,:)
        integer,                intent(in)  :: n_pairs
        integer(c_int), allocatable, intent(out) :: ranked_pairs(:,:)
        real(8),        allocatable, intent(out) :: tbme_weights(:)

        type(sp_state), allocatable :: sp(:)
        integer :: n_sp, k, i, j_orb, m2, sp_idx, h_sp, v_sp
        real(8) :: vms
        real(8), allocatable :: scores(:)
        integer, allocatable :: order(:)
        real(8) :: tmp_score
        integer :: tmp_idx, min_pos
        integer(c_int), allocatable :: tmp_pair(:)

        ! Build sp array (protons tz=-1 first, then neutrons tz=+1, descending mj)
        n_sp = 0
        do i = 1, ms%n_orbitals
            n_sp = n_sp + ms%orbitals(i)%j2 + 1
        end do
        allocate(sp(n_sp))
        k = 0
        do j_orb = -1, 1, 2
            do i = 1, ms%n_orbitals
                if (ms%orbitals(i)%tz /= j_orb) cycle
                do m2 = ms%orbitals(i)%j2, -ms%orbitals(i)%j2, -2
                    k = k + 1
                    sp(k)%orb_idx = ms%orbitals(i)%idx
                    sp(k)%j2      = ms%orbitals(i)%j2
                    sp(k)%mj2     = m2
                    sp(k)%tz      = ms%orbitals(i)%tz
                    sp(k)%l       = ms%orbitals(i)%l
                    sp(k)%spe     = ms%spes(ms%orbitals(i)%idx)
                end do
            end do
        end do

        allocate(scores(n_pairs), order(n_pairs))
        do k = 1, n_pairs
            order(k) = k
            ! filtered_pairs uses 0-based qubit indices; sp array is 1-based
            h_sp = filtered_pairs(k, 1) + 1
            v_sp = filtered_pairs(k, 2) + 1
            ! V_ms(h,v;h,v): antisymmetric TBME with all four distinct indices.
            ! This is the ADAPT gradient numerator at the HF reference for the
            ! 1p1h excitation (h->v): g = 2*V_ms(h,v;h,v).
            call v_ms_elem(sp, ms%tbmes, ms%n_tbme, h_sp, v_sp, h_sp, v_sp, vms)
            scores(k) = abs(vms)
        end do

        ! Selection sort descending (n_pairs typically ≤ 16 — no need for qsort)
        do i = 1, n_pairs - 1
            min_pos = i
            do j_orb = i + 1, n_pairs
                if (scores(order(j_orb)) > scores(order(min_pos))) min_pos = j_orb
            end do
            if (min_pos /= i) then
                tmp_idx        = order(i)
                order(i)       = order(min_pos)
                order(min_pos) = tmp_idx
            end if
        end do

        allocate(ranked_pairs(n_pairs, 2))
        allocate(tbme_weights(n_pairs))
        allocate(tmp_pair(2))
        do k = 1, n_pairs
            sp_idx = order(k)
            ranked_pairs(k, 1) = filtered_pairs(sp_idx, 1)
            ranked_pairs(k, 2) = filtered_pairs(sp_idx, 2)
            h_sp = filtered_pairs(sp_idx, 1) + 1
            v_sp = filtered_pairs(sp_idx, 2) + 1
            call v_ms_elem(sp, ms%tbmes, ms%n_tbme, h_sp, v_sp, h_sp, v_sp, vms)
            tbme_weights(k) = vms
        end do

        deallocate(sp, scores, order, tmp_pair)

    end subroutine rank_pairs_by_tbme


end module exact_solver