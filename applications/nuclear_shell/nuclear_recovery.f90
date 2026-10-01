! This code is part of Qiskit.
!
! (C) Copyright IBM 2026.
!
! This code is licensed under the Apache License, Version 2.0. You may
! obtain a copy of this license in the LICENSE.txt file in the root directory
! of this source tree or at https://www.apache.org/licenses/LICENSE-2.0.
!
! nuclear_recovery  -  self-consistent configuration recovery.
!
! Public API:
!
!   recover_configurations(bits, n_rows, n_qubits, occ, n_protons, n_neutrons, seed)
!
!     Port of qiskit_addon_sqd.configuration_recovery.recover_configurations.  Each
!     shot whose proton or neutron half has the wrong nucleon number has exactly the
!     excess bits of that half flipped, drawn without replacement with the addon's
!     occupancy-dependent weights, so bits least consistent with occ go first.
!     bits(q+1, r) is qubit q of shot r, protons in the low half as everywhere in this
!     application, and occ(q+1) is the occupancy estimate of qubit q.  Shots are
!     repaired in place.  The random stream is a seeded xorshift64: reproducible, but
!     not numpy's.  Where the addon would raise (every candidate has zero weight) the
!     draw falls back to uniform.
!
!   recovery_loop(ms, occ_int, n_protons, n_neutrons, mj2_target, max_iterations,
!                 eigenvalues, dim, n_kept, status)
!
!     Repair every pooled shot against the current occupancy estimate, symmetry-filter
!     the result, add the survivors to the subspace, diagonalize, and take the next
!     estimate from the ground state (Robledo-Moreno et al. 2025).  The subspace only
!     grows, so the energy is monotone non-increasing; the loop stops after
!     max_iterations or once an iteration adds no determinant or moves E1 by less
!     than ENERGY_TOL.  The first estimate is the mean occupancy of the shots already
!     on the right nucleon numbers, or the HF reference when there are none.  The HF
!     reference (read from orbital_registry, which must hold n_protons/n_neutrons) also
!     seeds the subspace; status /= 0 if no repaired shot ever passes the filter.

module nuclear_recovery
    use iso_c_binding
    use symmetry_filter,  only: filter_bitstrings_int
    use exact_solver,     only: build_subspace_hamiltonian, diagonalize_exact_complex
    use usdb_reader,      only: model_space_data
    use orbital_registry, only: reg_is_occupied
    implicit none
    private

    public :: recover_configurations, recovery_loop

    real(c_double),     parameter :: EPS        = 0.01_c_double   ! the addon's flip floor
    real(c_double),     parameter :: OCC_CLIP   = 1.0e-4_c_double ! keep occ inside (0,1)
    real(c_double),     parameter :: ENERGY_TOL = 1.0e-4_c_double ! MeV
    integer(c_int64_t), parameter :: SEED       = 42_c_int64_t
    integer(c_int64_t), parameter :: GOLDEN     = -7046029254386353131_c_int64_t ! 0x9E3779B97F4A7C15

contains

    subroutine recover_configurations(bits, n_rows, n_qubits, occ, n_protons, n_neutrons, seed)
        integer(c_int),     value         :: n_rows, n_qubits, n_protons, n_neutrons
        integer(c_int64_t), value         :: seed
        integer(c_int8_t),  intent(inout) :: bits(n_qubits, n_rows)
        real(c_double),     intent(in)    :: occ(n_qubits)

        ! Flip weights depend only on the qubit and its current bit, so tabulate them once.
        real(c_double) :: w_on(n_qubits), w_off(n_qubits)   ! weight to flip a 0 on, a 1 off
        real(c_double) :: ratio, u
        integer        :: half, q, r
        integer(c_int64_t) :: state

        half = n_qubits / 2
        if (min(n_protons, n_neutrons) < 0 .or. max(n_protons, n_neutrons) > half) &
            error stop "recover_configurations: nucleon number outside [0, n_qubits/2]"

        do q = 1, n_qubits
            ratio = real(merge(n_protons, n_neutrons, q <= half), c_double) / half
            w_on(q)  = min(1.0_c_double, max(0.0_c_double, p_flip_on(ratio, occ(q))))
            w_off(q) = min(1.0_c_double, max(0.0_c_double, p_flip_on(1 - ratio, 1 - occ(q))))
        end do

        state = ieor(seed, GOLDEN)
        if (state == 0) state = GOLDEN
        do q = 1, 8                             ! decorrelate nearby seeds
            u = uniform(state)
        end do

        do r = 1, n_rows
            call repair(bits(1:half, r), w_on(1:half), w_off(1:half), n_protons, state)
            call repair(bits(half+1:n_qubits, r), w_on(half+1:n_qubits), &
                        w_off(half+1:n_qubits), n_neutrons, state)
        end do
    end subroutine recover_configurations

    ! Probability weight for flipping a 0 to 1, from the addon's _p_flip_0_to_1.
    pure real(c_double) function p_flip_on(ratio, o)
        real(c_double), intent(in) :: ratio, o
        real(c_double) :: slope

        if (o < ratio) then
            p_flip_on = o * EPS / ratio
        else if (ratio == 1) then
            p_flip_on = EPS
        else
            slope = (1 - EPS) / (1 - ratio)
            p_flip_on = o * slope + 1 - slope
        end if
    end function p_flip_on

    ! Bring one half to its target weight by weighted sampling without replacement.
    subroutine repair(b, w_on, w_off, target, state)
        integer(c_int8_t),  intent(inout) :: b(:)
        real(c_double),     intent(in)    :: w_on(:), w_off(:)
        integer(c_int),     intent(in)    :: target
        integer(c_int64_t), intent(inout) :: state

        real(c_double)    :: w(size(b)), total, u
        integer           :: excess, k, i, pick
        integer(c_int8_t) :: from

        excess = count(b /= 0) - target
        if (excess == 0) return
        w = merge(w_off, w_on, b /= 0)
        if (all(w == 0)) return                 ! the addon leaves such a half untouched

        ! Candidates are the 1s when there are too many, the 0s when there are too few.
        from = merge(1_c_int8_t, 0_c_int8_t, excess > 0)
        where (b /= from) w = 0

        do k = 1, abs(excess)
            total = sum(w)                      ! re-summed, so no drift across picks
            if (total <= 0) then                ! weights exhausted: uniform over the rest
                w = merge(1.0_c_double, 0.0_c_double, b == from)
                total = sum(w)
            end if
            u = uniform(state) * total
            pick = 0
            do i = 1, size(b)
                if (w(i) <= 0) cycle
                pick = i
                u = u - w(i)
                if (u < 0) exit
            end do
            b(pick) = 1_c_int8_t - from
            w(pick) = 0
        end do
    end subroutine repair

    ! xorshift64: shifts and xors only, so no reliance on integer overflow.
    real(c_double) function uniform(state)
        integer(c_int64_t), intent(inout) :: state

        state = ieor(state, ishft(state, 13))
        state = ieor(state, ishft(state, -7))
        state = ieor(state, ishft(state, 17))
        uniform = real(ishft(state, -11), c_double) * 2.0_c_double**(-53)
    end function uniform

    subroutine recovery_loop(ms, occ_int, n_protons, n_neutrons, mj2_target, max_iterations, &
                             eigenvalues, dim, n_kept, status)
        type(model_space_data), intent(in)  :: ms
        integer(1),             intent(in)  :: occ_int(:,:)   ! (n_qubits, n_shots)
        integer(c_int),         intent(in)  :: n_protons, n_neutrons, mj2_target
        integer,                intent(in)  :: max_iterations
        real(8), allocatable,   intent(out) :: eigenvalues(:)
        integer,                intent(out) :: dim, n_kept, status

        integer(1),             allocatable :: work(:,:)
        logical(c_bool),        allocatable :: kept(:)
        logical,                allocatable :: on_shell(:)
        integer(8),             allocatable :: basis(:), grown(:)
        character(kind=c_char), allocatable :: basis_bs(:,:)
        integer,                allocatable :: kept_idx(:), basis_map(:)
        complex(8),             allocatable :: hamiltonian(:,:), eigenvectors(:,:)
        real(c_double) :: occ(size(occ_int, 1)), e_prev
        integer(c_int) :: n_pass
        integer        :: n_qubits, n_shots, half, it, i, q
        logical        :: sampled

        n_qubits = size(occ_int, 1)
        n_shots  = size(occ_int, 2)
        half     = n_qubits / 2
        dim = 0; n_kept = 0; status = -1

        on_shell = count(occ_int(1:half, :) /= 0, dim=1) == n_protons .and. &
                   count(occ_int(half+1:, :) /= 0, dim=1) == n_neutrons
        if (any(on_shell)) then
            do q = 1, n_qubits
                occ(q) = real(count(on_shell .and. occ_int(q, :) /= 0), c_double) / count(on_shell)
            end do
        else
            occ = [(merge(1.0_c_double, 0.0_c_double, reg_is_occupied(q - 1)), q = 1, n_qubits)]
        end if

        ! Seed the subspace with the HF reference when it lies in the target sector.
        allocate(work(n_qubits, 1), kept(1))
        work(:, 1) = [(merge(1_1, 0_1, reg_is_occupied(q - 1)), q = 1, n_qubits)]
        call filter_bitstrings_int(work, 1, n_qubits, half, n_protons, n_neutrons, &
                                   mj2_target, 0_c_int, kept, n_pass)
        basis = pack(pack_keys(work), kept)
        deallocate(work, kept)

        allocate(work(n_qubits, n_shots), kept(n_shots))
        e_prev = huge(e_prev)
        sampled = .false.
        do it = 1, max_iterations
            work = occ_int
            call recover_configurations(work, n_shots, n_qubits, &
                                        min(1 - OCC_CLIP, max(OCC_CLIP, occ)), &
                                        n_protons, n_neutrons, SEED + it)
            call filter_bitstrings_int(work, n_shots, n_qubits, half, n_protons, n_neutrons, &
                                       mj2_target, 0_c_int, kept, n_pass)
            grown = [basis, pack(pack_keys(work), kept)]
            call sort_unique(grown)
            sampled = sampled .or. n_pass > 0
            if (size(grown) == 0) cycle
            if (e_prev < huge(e_prev) .and. size(grown) == size(basis)) exit   ! nothing new
            call move_alloc(grown, basis)
            n_kept = int(n_pass)

            ! Sorted, unique keys: the builder's own dedup pass is then linear.
            if (allocated(basis_bs)) deallocate(basis_bs)
            allocate(basis_bs(n_qubits, size(basis)))
            do i = 1, size(basis)
                do q = 1, n_qubits
                    basis_bs(q, i) = merge('1', '0', btest(basis(i), q - 1))
                end do
            end do
            kept_idx = [(i, i = 1, size(basis))]
            call build_subspace_hamiltonian(ms, n_protons, n_neutrons, basis_bs, kept_idx, &
                                            size(basis), n_qubits, hamiltonian, dim, &
                                            basis_map, status)
            if (status /= 0) return
            call diagonalize_exact_complex(hamiltonian, dim, eigenvalues, eigenvectors, status)
            if (status /= 0) return
            print '("  Recovery ",I2,": kept ",I7," / ",I7," repaired shots  dim ",I6, &
                    &"  E1 = ",F16.9," MeV")', it, n_pass, n_shots, dim, eigenvalues(1)

            ! Self-consistent update: the ground state's occupancy of each qubit.
            occ = 0
            do i = 1, dim
                occ = occ + abs(eigenvectors(i, 1))**2 * (ichar(basis_bs(:, basis_map(i))) - 48)
            end do
            if (abs(e_prev - eigenvalues(1)) < ENERGY_TOL) exit
            e_prev = eigenvalues(1)
        end do
        if (.not. sampled) status = -1          ! the HF seed alone is not a result
    end subroutine recovery_loop

    ! One 64-bit key per shot, bit q-1 set for qubit q (the Hamiltonian builder's packing).
    pure function pack_keys(bits) result(keys)
        integer(1), intent(in) :: bits(:,:)
        integer(8) :: keys(size(bits, 2))
        integer :: r, q

        keys = 0
        do r = 1, size(bits, 2)
            do q = 1, size(bits, 1)
                if (bits(q, r) /= 0) keys(r) = ibset(keys(r), q - 1)
            end do
        end do
    end function pack_keys

    ! Heapsort, then drop repeats.
    subroutine sort_unique(keys)
        integer(8), allocatable, intent(inout) :: keys(:)
        integer    :: n, i, last
        integer(8) :: t

        n = size(keys)
        do i = n / 2, 1, -1
            call sift_down(keys, i, n)
        end do
        do last = n, 2, -1
            t = keys(1); keys(1) = keys(last); keys(last) = t
            call sift_down(keys, 1, last - 1)
        end do

        if (n == 0) return
        last = 1
        do i = 2, n
            if (keys(i) /= keys(last)) then
                last = last + 1
                keys(last) = keys(i)
            end if
        end do
        keys = keys(1:last)
    end subroutine sort_unique

    pure subroutine sift_down(a, root_in, n)
        integer(8), intent(inout) :: a(:)
        integer,    intent(in)    :: root_in, n
        integer    :: root, child
        integer(8) :: t

        root = root_in
        do
            child = 2 * root
            if (child > n) exit
            if (child < n) then
                if (a(child + 1) > a(child)) child = child + 1
            end if
            if (a(root) >= a(child)) exit
            t = a(root); a(root) = a(child); a(child) = t
            root = child
        end do
    end subroutine sift_down

end module nuclear_recovery
