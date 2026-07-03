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

! Hardware-free tests for qiskit_runtime: constants, the status helpers, and the
! null-handle guard paths. Live submission needs credentials and lives in
! applications/runtime_bell.

program test_runtime
  use qiskit_runtime
  use qiskit_c_api_runtime
  use, intrinsic :: iso_c_binding, only : c_size_t, c_int64_t, c_double
  implicit none (type, external)

  integer :: n_pass = 0
  integer :: n_fail = 0

  call test_exit_code_constants()
  call test_job_status_constants()
  call test_job_is_terminal()
  call test_job_status_name()
  call test_unconnected_service()
  call test_empty_backend_list()
  call test_invalid_backend()
  call test_empty_results()

  write(*, '(/, a)') "========================================"
  write(*, '(a, i0)') "  PASS : ", n_pass
  write(*, '(a, i0)') "  FAIL : ", n_fail
  write(*, '(a)')    "========================================"

  if (n_fail > 0) error stop "One or more tests failed."

contains

  ! Harness helpers

  subroutine assert_eq_int(got, expected, label)
    integer, intent(in) :: got, expected
    character(len=*), intent(in) :: label
    if (got == expected) then
      write(*, '("  [PASS] ", a)') label
      n_pass = n_pass + 1
    else
      write(*, '("  [FAIL] ", a, ": expected ", i0, " got ", i0)') label, expected, got
      n_fail = n_fail + 1
    end if
  end subroutine assert_eq_int

  subroutine assert_true(cond, label)
    logical, intent(in) :: cond
    character(len=*), intent(in) :: label
    if (cond) then
      write(*, '("  [PASS] ", a)') label
      n_pass = n_pass + 1
    else
      write(*, '("  [FAIL] ", a)') label
      n_fail = n_fail + 1
    end if
  end subroutine assert_true

  subroutine assert_str_eq(got, expected, label)
    character(len=*), intent(in) :: got, expected, label
    if (got == expected) then
      write(*, '("  [PASS] ", a)') label
      n_pass = n_pass + 1
    else
      write(*, '("  [FAIL] ", a, ": expected ", a, " got ", a)') label, expected, got
      n_fail = n_fail + 1
    end if
  end subroutine assert_str_eq

  subroutine section(name)
    character(len=*), intent(in) :: name
    write(*, '(/, "--- ", a, " ---")') name
  end subroutine section

  ! Tests

  ! Runtime exit codes match the ExitCode enum (crates/client/src/lib.rs).
  subroutine test_exit_code_constants()
    call section("Runtime exit-code constants")
    call assert_eq_int(int(QkrtExitCode_Success),                   0,   "Success == 0")
    call assert_eq_int(int(QkrtExitCode_NullPointerError),          1,   "NullPointerError == 1")
    call assert_eq_int(int(QkrtExitCode_AlignmentError),            2,   "AlignmentError == 2")
    call assert_eq_int(int(QkrtExitCode_BadArgumentError),          3,   "BadArgumentError == 3")
    call assert_eq_int(int(QkrtExitCode_QuantumAPIUnhandledError),  100, "QuantumAPIUnhandledError == 100")
    call assert_eq_int(int(QkrtExitCode_QuantumAPIBadRequest),      101, "QuantumAPIBadRequest == 101")
    call assert_eq_int(int(QkrtExitCode_QuantumAPIUnauthenticated), 102, "QuantumAPIUnauthenticated == 102")
    call assert_eq_int(int(QkrtExitCode_QuantumAPIForbidden),       103, "QuantumAPIForbidden == 103")
    call assert_eq_int(int(QkrtExitCode_QuantumAPINotFound),        104, "QuantumAPINotFound == 104")
    call assert_eq_int(int(QkrtExitCode_QuantumAPIConflict),        105, "QuantumAPIConflict == 105")
    call assert_eq_int(int(QkrtExitCode_GlobalSearchAPIUnhandledError), 200, "GlobalSearchAPIUnhandledError == 200")
    call assert_eq_int(int(QkrtExitCode_IAMAPIUnhandledError),      300, "IAMAPIUnhandledError == 300")
  end subroutine test_exit_code_constants

  ! Job status codes match the JobStatus enum (crates/client/src/service.rs).
  subroutine test_job_status_constants()
    call section("Job status constants")
    call assert_eq_int(int(QkrtJobStatus_Queued),              0, "Queued == 0")
    call assert_eq_int(int(QkrtJobStatus_Running),             1, "Running == 1")
    call assert_eq_int(int(QkrtJobStatus_Completed),           2, "Completed == 2")
    call assert_eq_int(int(QkrtJobStatus_Cancelled),           3, "Cancelled == 3")
    call assert_eq_int(int(QkrtJobStatus_CancelledRanTooLong), 4, "CancelledRanTooLong == 4")
    call assert_eq_int(int(QkrtJobStatus_Failed),              5, "Failed == 5")
  end subroutine test_job_status_constants

  ! Only Queued and Running are non-terminal.
  subroutine test_job_is_terminal()
    call section("job_is_terminal")
    call assert_true(.not. job_is_terminal(int(QkrtJobStatus_Queued)),  "Queued is not terminal")
    call assert_true(.not. job_is_terminal(int(QkrtJobStatus_Running)), "Running is not terminal")
    call assert_true(job_is_terminal(int(QkrtJobStatus_Completed)),           "Completed is terminal")
    call assert_true(job_is_terminal(int(QkrtJobStatus_Cancelled)),           "Cancelled is terminal")
    call assert_true(job_is_terminal(int(QkrtJobStatus_CancelledRanTooLong)), "CancelledRanTooLong is terminal")
    call assert_true(job_is_terminal(int(QkrtJobStatus_Failed)),              "Failed is terminal")
  end subroutine test_job_is_terminal

  ! Status names round-trip, and unknown codes degrade gracefully.
  subroutine test_job_status_name()
    call section("job_status_name")
    call assert_str_eq(job_status_name(int(QkrtJobStatus_Queued)),    "Queued",    "name(Queued)")
    call assert_str_eq(job_status_name(int(QkrtJobStatus_Running)),   "Running",   "name(Running)")
    call assert_str_eq(job_status_name(int(QkrtJobStatus_Completed)), "Completed", "name(Completed)")
    call assert_str_eq(job_status_name(int(QkrtJobStatus_Failed)),    "Failed",    "name(Failed)")
    call assert_str_eq(job_status_name(999),                          "Unknown",   "name(999) is Unknown")
  end subroutine test_job_status_name

  ! A default-constructed service reports no connection.
  subroutine test_unconnected_service()
    type(RtService) :: service
    call section("Unconnected service")
    call assert_true(.not. service%is_connected(), "fresh service is not connected")
  end subroutine test_unconnected_service

  ! An empty backend listing has length 0.
  subroutine test_empty_backend_list()
    type(RtBackendList) :: backends
    call section("Empty backend listing")
    call assert_true(backends%length() == 0_c_int64_t, "empty listing length == 0")
  end subroutine test_empty_backend_list

  ! A default-constructed backend handle is invalid.
  subroutine test_invalid_backend()
    type(RtBackend) :: backend
    call section("Invalid backend handle")
    call assert_true(.not. backend%is_valid(), "fresh backend is not valid")
  end subroutine test_invalid_backend

  ! Result objects with no data report zero entries.
  subroutine test_empty_results()
    type(RtSamplerResult)   :: sres
    type(RtEstimatorResult) :: eres
    real(c_double), allocatable :: vals(:)
    call section("Empty results")
    call assert_true(sres%num_samples() == 0_c_size_t, "empty SamplerResult has 0 samples")
    call assert_true(eres%num_values()  == 0_c_size_t, "empty EstimatorResult has 0 values")
    vals = eres%values()
    call assert_eq_int(size(vals), 0, "empty EstimatorResult values() is size 0")
  end subroutine test_empty_results

end program test_runtime
