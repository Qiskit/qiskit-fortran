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

!> @brief Single source of truth for qubit ↔ orbital quantum-number mapping.
!>
!> Every module that needs to know a qubit's j, mj, parity, or isospin reads
!> from here. The registry is populated once from a USDB.snt file via
!> init_registry_from_snt() or init_registry_sd_shell() (which reads USDB.snt
!> internally), and then queried by all consumers.
!>
!> The orbital layout is determined by the USDB.snt file structure:
!>   - Proton orbitals listed first (tz=-1), expanded into m-substates
!>   - Neutron orbitals listed second (tz=+1), expanded into m-substates
!>   - Each j-shell expanded in descending mj order: +j, +j-1, ..., -j
module orbital_registry
  use iso_c_binding
  use usdb_reader, only: model_space_data, orbital_info, read_usdb_file, free_model_space
  implicit none
  private

  public :: init_registry_from_snt
  public :: init_registry_sd_shell
  public :: reg_n_qubits
  public :: reg_j2
  public :: reg_mj2
  public :: reg_parity
  public :: reg_tz
  public :: reg_is_proton
  public :: reg_is_occupied
  public :: reg_proton_holes
  public :: reg_proton_virtuals
  public :: reg_neutron_holes
  public :: reg_neutron_virtuals

  ! Per-qubit tables (1-based internally, 0-based public API)
  integer :: n_reg = 0
  integer, allocatable :: tbl_j2(:)       ! 2*j
  integer, allocatable :: tbl_mj2(:)      ! 2*mj
  integer, allocatable :: tbl_parity(:)   ! 0=even, 1=odd
  integer, allocatable :: tbl_tz(:)       ! -1=proton, +1=neutron
  logical, allocatable :: tbl_occupied(:) ! .true. for HF-occupied orbitals

contains

  !> Populate registry from a USDB model_space_data and particle counts.
  !>
  !> The .snt file gives (n, l, j, tz) per orbital but lists only one entry
  !> per j-shell, not per magnetic substate.  We expand each orbital into its
  !> 2j+1 m-substates in descending mj order (matches the sd-shell convention
  !> in symmetry_filter).  Proton orbitals come first (tz=-1), neutron orbitals
  !> second (tz=+1), in the order they appear in the .snt header.
  !>
  !> @param ms         Populated model_space_data from read_usdb_file
  !> @param n_protons  Number of occupied proton orbitals (HF configuration)
  !> @param n_neutrons Number of occupied neutron orbitals
  subroutine init_registry_from_snt(ms, n_protons, n_neutrons)
    type(model_space_data), intent(in) :: ms
    integer(c_int),         intent(in) :: n_protons, n_neutrons

    integer :: orb, m2, qubit, n_proton_qubits
    integer :: p_filled, n_filled   ! counters for HF-occupied qubits

    ! Total qubits = sum over all orbitals of (2j+1) m-substates
    n_reg = 0
    do orb = 1, ms%n_orbitals
      n_reg = n_reg + ms%orbitals(orb)%j2 + 1
    end do

    call alloc_tables(n_reg)

    qubit = 1
    n_proton_qubits = 0
    do orb = 1, ms%n_orbitals
      if (ms%orbitals(orb)%tz == -1) &
        n_proton_qubits = n_proton_qubits + ms%orbitals(orb)%j2 + 1
    end do

    ! Proton orbitals first (tz=-1 entries in the .snt header)
    do orb = 1, ms%n_orbitals
      if (ms%orbitals(orb)%tz /= -1) cycle
      do m2 = ms%orbitals(orb)%j2, -ms%orbitals(orb)%j2, -2
        tbl_j2(qubit)     = ms%orbitals(orb)%j2
        tbl_mj2(qubit)    = m2
        tbl_parity(qubit) = mod(ms%orbitals(orb)%l, 2)
        tbl_tz(qubit)     = -1
        qubit = qubit + 1
      end do
    end do

    ! Neutron orbitals second (tz=+1)
    do orb = 1, ms%n_orbitals
      if (ms%orbitals(orb)%tz /= 1) cycle
      do m2 = ms%orbitals(orb)%j2, -ms%orbitals(orb)%j2, -2
        tbl_j2(qubit)     = ms%orbitals(orb)%j2
        tbl_mj2(qubit)    = m2
        tbl_parity(qubit) = mod(ms%orbitals(orb)%l, 2)
        tbl_tz(qubit)     = 1
        qubit = qubit + 1
      end do
    end do

    ! Mark HF-occupied qubits: first n_protons proton qubits, first n_neutrons
    ! neutron qubits (lowest-energy = first in each sector as ordered by .snt)
    tbl_occupied = .false.
    p_filled = 0
    do qubit = 1, n_reg
      if (tbl_tz(qubit) == -1 .and. p_filled < n_protons) then
        tbl_occupied(qubit) = .true.
        p_filled = p_filled + 1
      end if
    end do
    n_filled = 0
    do qubit = 1, n_reg
      if (tbl_tz(qubit) == 1 .and. n_filled < n_neutrons) then
        tbl_occupied(qubit) = .true.
        n_filled = n_filled + 1
      end if
    end do

  end subroutine init_registry_from_snt

  !> Populate registry with the built-in sd-shell 24-qubit layout.
  !> Canonical ordering matches symmetry_filter's setup_single_particle_data.
  !>
  !> @param n_protons  Number of HF-occupied proton qubits  (0–11)
  !> @param n_neutrons Number of HF-occupied neutron qubits (12–23)
  subroutine init_registry_sd_shell(n_protons, n_neutrons)
    integer(c_int), intent(in) :: n_protons, n_neutrons

    type(model_space_data) :: ms
    integer :: status

    ! Read sd-shell configuration from USDB.snt instead of hardcoding
    call read_usdb_file("USDB.snt", ms, status)

    ! Use the USDB data to populate the registry
    call init_registry_from_snt(ms, n_protons, n_neutrons)
    call free_model_space(ms)

  end subroutine init_registry_sd_shell

  ! Public query functions (all use 0-based qubit index externally)

  integer function reg_n_qubits()
    reg_n_qubits = n_reg
  end function reg_n_qubits

  integer function reg_j2(qubit_0)
    integer, intent(in) :: qubit_0
    reg_j2 = tbl_j2(qubit_0 + 1)
  end function reg_j2

  integer function reg_mj2(qubit_0)
    integer, intent(in) :: qubit_0
    reg_mj2 = tbl_mj2(qubit_0 + 1)
  end function reg_mj2

  integer function reg_parity(qubit_0)
    integer, intent(in) :: qubit_0
    reg_parity = tbl_parity(qubit_0 + 1)
  end function reg_parity

  integer function reg_tz(qubit_0)
    integer, intent(in) :: qubit_0
    reg_tz = tbl_tz(qubit_0 + 1)
  end function reg_tz

  logical function reg_is_proton(qubit_0)
    integer, intent(in) :: qubit_0
    reg_is_proton = (tbl_tz(qubit_0 + 1) == -1)
  end function reg_is_proton

  logical function reg_is_occupied(qubit_0)
    integer, intent(in) :: qubit_0
    reg_is_occupied = tbl_occupied(qubit_0 + 1)
  end function reg_is_occupied

  !> Return 0-based indices of occupied proton hole qubits.
  subroutine reg_proton_holes(holes, n)
    integer, allocatable, intent(out) :: holes(:)
    integer,              intent(out) :: n
    integer :: q, cnt
    cnt = 0
    do q = 1, n_reg
      if (tbl_tz(q) == -1 .and. tbl_occupied(q)) cnt = cnt + 1
    end do
    n = cnt
    allocate(holes(n))
    cnt = 0
    do q = 1, n_reg
      if (tbl_tz(q) == -1 .and. tbl_occupied(q)) then
        cnt = cnt + 1
        holes(cnt) = q - 1
      end if
    end do
  end subroutine reg_proton_holes

  !> Return 0-based indices of unoccupied proton virtual qubits.
  subroutine reg_proton_virtuals(virts, n)
    integer, allocatable, intent(out) :: virts(:)
    integer,              intent(out) :: n
    integer :: q, cnt
    cnt = 0
    do q = 1, n_reg
      if (tbl_tz(q) == -1 .and. .not. tbl_occupied(q)) cnt = cnt + 1
    end do
    n = cnt
    allocate(virts(n))
    cnt = 0
    do q = 1, n_reg
      if (tbl_tz(q) == -1 .and. .not. tbl_occupied(q)) then
        cnt = cnt + 1
        virts(cnt) = q - 1
      end if
    end do
  end subroutine reg_proton_virtuals

  !> Return 0-based indices of occupied neutron hole qubits.
  subroutine reg_neutron_holes(holes, n)
    integer, allocatable, intent(out) :: holes(:)
    integer,              intent(out) :: n
    integer :: q, cnt
    cnt = 0
    do q = 1, n_reg
      if (tbl_tz(q) == 1 .and. tbl_occupied(q)) cnt = cnt + 1
    end do
    n = cnt
    allocate(holes(n))
    cnt = 0
    do q = 1, n_reg
      if (tbl_tz(q) == 1 .and. tbl_occupied(q)) then
        cnt = cnt + 1
        holes(cnt) = q - 1
      end if
    end do
  end subroutine reg_neutron_holes

  !> Return 0-based indices of unoccupied neutron virtual qubits.
  subroutine reg_neutron_virtuals(virts, n)
    integer, allocatable, intent(out) :: virts(:)
    integer,              intent(out) :: n
    integer :: q, cnt
    cnt = 0
    do q = 1, n_reg
      if (tbl_tz(q) == 1 .and. .not. tbl_occupied(q)) cnt = cnt + 1
    end do
    n = cnt
    allocate(virts(n))
    cnt = 0
    do q = 1, n_reg
      if (tbl_tz(q) == 1 .and. .not. tbl_occupied(q)) then
        cnt = cnt + 1
        virts(cnt) = q - 1
      end if
    end do
  end subroutine reg_neutron_virtuals

  ! ===========================================================================
  ! Private helpers
  ! ===========================================================================

  subroutine alloc_tables(n)
    integer, intent(in) :: n
    if (allocated(tbl_j2))       deallocate(tbl_j2)
    if (allocated(tbl_mj2))      deallocate(tbl_mj2)
    if (allocated(tbl_parity))   deallocate(tbl_parity)
    if (allocated(tbl_tz))       deallocate(tbl_tz)
    if (allocated(tbl_occupied)) deallocate(tbl_occupied)
    allocate(tbl_j2(n), tbl_mj2(n), tbl_parity(n), tbl_tz(n), tbl_occupied(n))
    tbl_occupied = .false.
  end subroutine alloc_tables

  !> Fill n consecutive qubit entries starting at q (1-based, updated on exit).
  subroutine fill_subshell(q, j2, l, tz, n)
    integer, intent(inout) :: q
    integer, intent(in)    :: j2, l, tz, n
    integer :: k, m2
    m2 = j2
    do k = 1, n
      tbl_j2(q)     = j2
      tbl_mj2(q)    = m2
      tbl_parity(q) = mod(l, 2)
      tbl_tz(q)     = tz
      q  = q  + 1
      m2 = m2 - 2
    end do
  end subroutine fill_subshell

  subroutine mark_hf_occupied(n_protons, n_neutrons)
    integer, intent(in) :: n_protons, n_neutrons
    integer :: q, filled
    tbl_occupied = .false.
    filled = 0
    do q = 1, n_reg
      if (tbl_tz(q) == -1 .and. filled < n_protons) then
        tbl_occupied(q) = .true.; filled = filled + 1
      end if
    end do
    filled = 0
    do q = 1, n_reg
      if (tbl_tz(q) == 1 .and. filled < n_neutrons) then
        tbl_occupied(q) = .true.; filled = filled + 1
      end if
    end do
  end subroutine mark_hf_occupied

end module orbital_registry
