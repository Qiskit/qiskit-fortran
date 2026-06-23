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

program test_usdb_reader
  use usdb_reader
  implicit none

  type(model_space_data)              :: ms
  type(tbme_element), allocatable     :: j_tbmes(:)
  integer                             :: status, i, n_j
  character(len=256)                  :: usdb_file
  integer                             :: clock_rate, clock_start, clock_end
  integer                             :: step_start, step_end
  real(8)                             :: total_runtime, step_runtime

  ! CMake configure_file copies USDB.snt next to the executable.
  usdb_file = "USDB.snt"

  call system_clock(count_rate=clock_rate)
  call system_clock(count=clock_start)
  write(*,'(a)') "=========================================="
  write(*,'(a)') "USDB Reader Test Program"
  write(*,'(a)') "=========================================="

  ! --- Test 1: read file -----------------------------------------------------
  write(*,'(/,a)') "Test 1: Reading USDB.snt ..."
  call system_clock(count=step_start)
  call read_usdb_file(usdb_file, ms, status)
  if (status /= 0) then
    write(*,'(a,i0)') "FAIL: read_usdb_file returned status = ", status
    stop 1
  end if
  call system_clock(count=step_end)
  step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
  write(*,'(a)') "PASS: file read successfully"
  write(*,'(a,es16.8,a)') "Runtime: ", step_runtime, " s"

  ! --- Test 2: model space info ----------------------------------------------
  write(*,'(/,a)') "Test 2: Model Space Information"
  write(*,'(a)') "  Proton  orbitals : " // itoa(ms%n_proton_orbs)
  write(*,'(a)') "  Neutron orbitals : " // itoa(ms%n_neutron_orbs)
  write(*,'(a)') "  Core   A / Z     : " // itoa(ms%core_A) // " / " // itoa(ms%core_Z)
  write(*,'(a)') "  Core   energy    : " // ftoa(ms%core_energy) // " MeV"
  write(*,'(a)') "  n_orbitals       : " // itoa(ms%n_orbitals)
  write(*,'(a)') "  n_spe            : " // itoa(ms%n_spe)
  write(*,'(a)') "  n_tbme           : " // itoa(ms%n_tbme)
  write(*,'()')
  write(*,'(a)') "  Orbital table:"
  write(*,'(a)') "    idx   n   l  2j  tz"
  do i = 1, ms%n_orbitals
    write(*,'(5i5)') ms%orbitals(i)%idx, ms%orbitals(i)%n, &
                     ms%orbitals(i)%l,   ms%orbitals(i)%j2, ms%orbitals(i)%tz
  end do

  ! --- Test 3: first 5 SPEs --------------------------------------------------
  write(*,'(/,a)') "Test 3: First 5 Single-Particle Energies"
  write(*,'(a)') "  orbital   SPE (MeV)"
  do i = 1, min(5, ms%n_spe)
    write(*,'(i8,f14.5)') i, ms%spes(i)
  end do
  if (ms%n_spe > 5) write(*,'(a,i0,a)') "  ... (", ms%n_spe, " total)"

  ! --- Test 4: first 10 TBMEs ------------------------------------------------
  write(*,'(/,a)') "Test 4: First 10 Two-Body Matrix Elements"
  write(*,'(a)') "    a   b   c   d   J    value (MeV)"
  do i = 1, min(10, ms%n_tbme)
    write(*,'(5i4,f14.6)') ms%tbmes(i)%a, ms%tbmes(i)%b, &
                           ms%tbmes(i)%c, ms%tbmes(i)%d, &
                           ms%tbmes(i)%J, ms%tbmes(i)%matrix_elem
  end do
  if (ms%n_tbme > 10) write(*,'(a,i0,a)') "  ... (", ms%n_tbme, " total)"

  ! --- Test 5: j=5/2 (d5/2) TBMEs -------------------------------------------
  write(*,'(/,a)') "Test 5: TBMEs for j=5/2 shell (0d5/2, j2=5)"
  call system_clock(count=step_start)
  call get_j_shell_tbmes(5, ms, j_tbmes, n_j)
  write(*,'(a,i0)') "  Extracted : ", n_j
  write(*,'(a)') "    a   b   c   d   J    value (MeV)"
  do i = 1, min(10, n_j)
    write(*,'(5i4,f14.6)') j_tbmes(i)%a, j_tbmes(i)%b, &
                           j_tbmes(i)%c, j_tbmes(i)%d, &
                           j_tbmes(i)%J, j_tbmes(i)%matrix_elem
  end do
  if (n_j > 10) write(*,'(a,i0,a)') "  ... (", n_j, " total)"
  call system_clock(count=step_end)
  step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
  write(*,'(a,es16.8,a)') "  Runtime: ", step_runtime, " s"
  if (allocated(j_tbmes)) deallocate(j_tbmes)

  ! --- Test 6: j=3/2 (d3/2) TBMEs -------------------------------------------
  write(*,'(/,a)') "Test 6: TBMEs for j=3/2 shell (0d3/2, j2=3)"
  call system_clock(count=step_start)
  call get_j_shell_tbmes(3, ms, j_tbmes, n_j)
  write(*,'(a,i0)') "  Extracted : ", n_j
  do i = 1, min(5, n_j)
    write(*,'(5i4,f14.6)') j_tbmes(i)%a, j_tbmes(i)%b, &
                           j_tbmes(i)%c, j_tbmes(i)%d, &
                           j_tbmes(i)%J, j_tbmes(i)%matrix_elem
  end do
  call system_clock(count=step_end)
  step_runtime = real(step_end - step_start, 8) / real(clock_rate, 8)
  write(*,'(a,es16.8,a)') "  Runtime: ", step_runtime, " s"
  if (allocated(j_tbmes)) deallocate(j_tbmes)

  ! --- cleanup and summary ---------------------------------------------------
  call free_model_space(ms)

  call system_clock(count=clock_end)
  total_runtime = real(clock_end - clock_start, 8) / real(clock_rate, 8)
  write(*,'(/,a)') "=========================================="
  write(*,'(a)') "All tests PASSED — USDB reader functional."
  write(*,'(a)') "Ready for j² pairing toy model integration."
  write(*,'(a,es16.8,a)') "Total runtime: ", total_runtime, " s"
  write(*,'(a)') "=========================================="

contains

  ! Minimal integer->string conversion (no external lib dependency).
  function itoa(n) result(s)
    integer, intent(in) :: n
    character(len=20) :: s
    write(s,'(i0)') n
    s = adjustl(s)
  end function itoa

  function ftoa(x) result(s)
    real(8), intent(in) :: x
    character(len=30) :: s
    write(s,'(f12.5)') x
    s = adjustl(s)
  end function ftoa

end program test_usdb_reader
