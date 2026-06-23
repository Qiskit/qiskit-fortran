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

!> @brief USDB.snt interaction file reader for nuclear shell-model calculations.
!>
!> File format (.snt):
!>   First non-comment line: n_proton_orbs  n_neutron_orbs  core_A  core_Z
!>   Next n_orb lines: orbital definitions — idx  n  l  2j  tz
!>     (tz = -1 proton, +1 neutron)
!>   SPE header line: n_spe  method
!>   Next n_spe lines: i  i  energy(MeV)   (diagonal only)
!>   TBME header line: n_tbme  method  hbar_omega  core_energy
!>   Next n_tbme lines: a  b  c  d  J  value(MeV)
!>     a,b = bra orbital indices (1-based), c,d = ket orbital indices
!>     J = total angular momentum coupling
!>
!> Note on J-coupled vs m-scheme:
!>   TBMEs <ab;J|V|cd;J> are in the J-coupled basis. Mapping to qubit
!>   bitstrings requires a Pandya transform into the m-scheme basis where each
!>   qubit is a single (n,l,j,m_j,tz) orbital, this is done in a separate
!>   module (future: sqd_transform.f90).
module usdb_reader
  implicit none
  private

  public :: orbital_info, tbme_element, model_space_data
  public :: read_usdb_file, get_j_shell_tbmes, free_model_space

  ! derived types

  type :: orbital_info
    integer :: idx  ! 1-based index as in .snt
    integer :: n    ! principal quantum number
    integer :: l    ! orbital angular momentum
    integer :: j2   ! 2*j (e.g. 5 for d5/2, 3 for d3/2, 1 for s1/2)
    integer :: tz   ! -1 = proton, +1 = neutron
  end type orbital_info

  !> Two-body matrix element in MeV (J-coupled, no T column).
  type :: tbme_element
    integer :: a, b      ! bra orbital indices (1-based)
    integer :: c, d      ! ket orbital indices (1-based)
    integer :: J         ! total angular momentum coupling
    real(8) :: matrix_elem
  end type tbme_element

  type :: model_space_data
    integer :: n_proton_orbs   ! proton  orbital count from header
    integer :: n_neutron_orbs  ! neutron orbital count from header
    integer :: core_A          ! core mass number
    integer :: core_Z          ! core proton number
    integer :: n_orbitals      ! = n_proton_orbs + n_neutron_orbs
    integer :: n_spe
    integer :: n_tbme
    real(8) :: core_energy     ! MeV, from TBME header
    type(orbital_info), allocatable :: orbitals(:)
    real(8),            allocatable :: spes(:)
    type(tbme_element), allocatable :: tbmes(:)
  end type model_space_data

contains

  !> Read a USDB-format .snt file
  !>
  !> @param[in]  filename   Path to the .snt file
  !> @param[out] ms         Populated model_space_data on success
  !> @param[out] status     0 = ok; negative = I/O error; positive = parse error
  subroutine read_usdb_file(filename, ms, status)
    character(len=*),       intent(in)  :: filename
    type(model_space_data), intent(out) :: ms
    integer,                intent(out) :: status

    integer, parameter :: U = 42
    character(len=512) :: line
    integer            :: ios, i
    integer            :: n_spe_hdr, spe_method
    integer            :: n_tbme_hdr, tbme_method
    real(8)            :: hbar_omega
    integer            :: orb_i, orb_j

    status = 0
    open(unit=U, file=filename, status='old', action='read', iostat=ios)
    if (ios /= 0) then
      write(*,'(a,a)') "usdb_reader: cannot open ", trim(filename)
      status = -1; return
    end if

    ! model space header
    call next_noncomment(U, line, ios)
    if (ios /= 0) then; status = -2; close(U); return; end if
    read(line, *, iostat=ios) ms%n_proton_orbs, ms%n_neutron_orbs, ms%core_A, ms%core_Z
    if (ios /= 0) then
      write(*,'(a,a)') "usdb_reader: bad model-space line: ", trim(line)
      status = 1; close(U); return
    end if
    ms%n_orbitals = ms%n_proton_orbs + ms%n_neutron_orbs

    ! orbital definitions
    allocate(ms%orbitals(ms%n_orbitals))
    do i = 1, ms%n_orbitals
      call next_noncomment(U, line, ios)
      if (ios /= 0) then; status = -3; close(U); return; end if
      call strip_inline_comment(line)
      read(line, *, iostat=ios) ms%orbitals(i)%idx, ms%orbitals(i)%n, &
                                ms%orbitals(i)%l,   ms%orbitals(i)%j2, &
                                ms%orbitals(i)%tz
      if (ios /= 0) then
        write(*,'(a,i0,a,a)') "usdb_reader: bad orbital line ", i, ": ", trim(line)
        status = 2; close(U); return
      end if
    end do

    ! SPE header  (e.g. "6  0")
    call next_noncomment(U, line, ios)
    if (ios /= 0) then; status = -4; close(U); return; end if
    read(line, *, iostat=ios) n_spe_hdr, spe_method
    if (ios /= 0) then
      write(*,'(a,a)') "usdb_reader: bad SPE header: ", trim(line)
      status = 3; close(U); return
    end if

    ! SPE values  ("i  i  energy")
    ms%n_spe = n_spe_hdr
    allocate(ms%spes(ms%n_spe))
    do i = 1, ms%n_spe
      call next_noncomment(U, line, ios)
      if (ios /= 0) then; status = -5; close(U); return; end if
      read(line, *, iostat=ios) orb_i, orb_j, ms%spes(i)
      if (ios /= 0) then
        write(*,'(a,i0,a,a)') "usdb_reader: bad SPE line ", i, ": ", trim(line)
        status = 4; close(U); return
      end if
    end do

    ! TBME header  ("n  method  hbar_omega  core_energy")
    call next_noncomment(U, line, ios)
    if (ios /= 0) then; status = -6; close(U); return; end if
    read(line, *, iostat=ios) n_tbme_hdr, tbme_method, hbar_omega, ms%core_energy
    if (ios /= 0) then
      write(*,'(a,a)') "usdb_reader: bad TBME header: ", trim(line)
      status = 5; close(U); return
    end if

    ! TBME values  ("a  b  c  d  J  value")
    allocate(ms%tbmes(ms%n_tbme))
    do i = 1, ms%n_tbme
      call next_noncomment(U, line, ios)
      if (ios /= 0) then; status = -7; close(U); return; end if
      read(line, *, iostat=ios) ms%tbmes(i)%a, ms%tbmes(i)%b, &
                                ms%tbmes(i)%c, ms%tbmes(i)%d, &
                                ms%tbmes(i)%J, ms%tbmes(i)%matrix_elem
      if (ios /= 0) then
        write(*,'(a,i0,a,a)') "usdb_reader: bad TBME line ", i, ": ", trim(line)
        status = 6; close(U); return
      end if
    end do

    close(U)
  end subroutine read_usdb_file

  !> Extract TBMEs where all four orbital indices have 2j = j2_target.
  !>
  !> For the j2 pairing toy model (two nucleons in a single j-shell) we only
  !> need <jj;J|V|jj;J>.  In the sd-shell j2=5 selects 0d5/2, j2=3 selects
  !> 0d3/2, j2=1 selects 1s1/2.
  !>
  !> **Model space simplification**: This function filters to single-j-shell
  !> interactions (12 of 158 TBMEs for d5/2). Full sd-shell calculations require
  !> cross-shell matrix elements like <d5/2,s1/2|V|d3/2,d5/2>, increasing both
  !> classical diagonalization cost (hours vs milliseconds) and quantum circuit
  !> depth (~2000 vs ~200 gates). The USDB interaction is complete; this is a
  !> model space truncation for algorithm validation, not an interaction limitation.
  !>
  !> @param[in]  j2_target    2*j for the shell of interest
  !> @param[in]  ms           Populated model_space_data
  !> @param[out] tbmes_out    Extracted TBMEs (allocated here)
  !> @param[out] n_out        Number extracted
  subroutine get_j_shell_tbmes(j2_target, ms, tbmes_out, n_out)
    integer,                intent(in)  :: j2_target
    type(model_space_data), intent(in)  :: ms
    type(tbme_element), allocatable, intent(out) :: tbmes_out(:)
    integer,                intent(out) :: n_out

    integer :: i, cnt

    ! Two-pass: count then collect
    cnt = 0
    do i = 1, ms%n_tbme
      if (orb_j2(ms, ms%tbmes(i)%a) == j2_target .and. &
          orb_j2(ms, ms%tbmes(i)%b) == j2_target .and. &
          orb_j2(ms, ms%tbmes(i)%c) == j2_target .and. &
          orb_j2(ms, ms%tbmes(i)%d) == j2_target) cnt = cnt + 1
    end do

    n_out = cnt
    allocate(tbmes_out(n_out))
    cnt = 0
    do i = 1, ms%n_tbme
      if (orb_j2(ms, ms%tbmes(i)%a) == j2_target .and. &
          orb_j2(ms, ms%tbmes(i)%b) == j2_target .and. &
          orb_j2(ms, ms%tbmes(i)%c) == j2_target .and. &
          orb_j2(ms, ms%tbmes(i)%d) == j2_target) then
        cnt = cnt + 1
        tbmes_out(cnt) = ms%tbmes(i)
      end if
    end do
  end subroutine get_j_shell_tbmes

  !> Deallocate all allocatable components of a model_space_data.
  subroutine free_model_space(ms)
    type(model_space_data), intent(inout) :: ms
    if (allocated(ms%orbitals)) deallocate(ms%orbitals)
    if (allocated(ms%spes))     deallocate(ms%spes)
    if (allocated(ms%tbmes))    deallocate(ms%tbmes)
    ms%n_orbitals = 0; ms%n_spe = 0; ms%n_tbme = 0
  end subroutine free_model_space

  ! ===========================================================================
  ! Private helpers
  ! ===========================================================================

  !> Return j2 of orbital index orb_idx (0 if not found).
  integer function orb_j2(ms, orb_idx) result(j2)
    type(model_space_data), intent(in) :: ms
    integer,                intent(in) :: orb_idx
    integer :: k
    j2 = 0
    do k = 1, ms%n_orbitals
      if (ms%orbitals(k)%idx == orb_idx) then
        j2 = ms%orbitals(k)%j2; return
      end if
    end do
  end function orb_j2

  !> Return the next non-blank, non-comment line from unit U.
  subroutine next_noncomment(U, line, ios)
    integer,            intent(in)  :: U
    character(len=512), intent(out) :: line
    integer,            intent(out) :: ios
    do
      read(U, '(a)', iostat=ios) line
      if (ios /= 0) return
      line = adjustl(line)
      if (len_trim(line) == 0) cycle
      if (line(1:1) == '!')    cycle
      return
    end do
  end subroutine next_noncomment

  !> Blank everything from the first '!' onward (strip inline comments).
  subroutine strip_inline_comment(line)
    character(len=*), intent(inout) :: line
    integer :: p
    p = index(line, '!')
    if (p > 0) line(p:) = ' '
  end subroutine strip_inline_comment

end module usdb_reader
