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

! FFI bindings to qiskit-ibm-runtime-c. Signatures track
! include/qiskit_ibm_runtime/qiskit_ibm_runtime.h. Opaque handles are c_ptr.
! Runtime exit codes are their own namespace, not the core qiskit ones.
module qiskit_c_api_runtime
  use, intrinsic :: iso_c_binding, only : &
      c_ptr, c_char, c_int32_t, c_int64_t, c_size_t, c_double

  implicit none (type, external)
  private

  ! ExitCode enum (crates/client/src/lib.rs)
  public :: QkrtExitCode_Success, QkrtExitCode_NullPointerError
  public :: QkrtExitCode_AlignmentError, QkrtExitCode_BadArgumentError
  public :: QkrtExitCode_QuantumAPIUnhandledError, QkrtExitCode_QuantumAPIBadRequest
  public :: QkrtExitCode_QuantumAPIUnauthenticated, QkrtExitCode_QuantumAPIForbidden
  public :: QkrtExitCode_QuantumAPINotFound, QkrtExitCode_QuantumAPIConflict
  public :: QkrtExitCode_GlobalSearchAPIUnhandledError, QkrtExitCode_IAMAPIUnhandledError

  ! JobStatus enum (crates/client/src/service.rs)
  public :: QkrtJobStatus_Queued, QkrtJobStatus_Running, QkrtJobStatus_Completed
  public :: QkrtJobStatus_Cancelled, QkrtJobStatus_CancelledRanTooLong, QkrtJobStatus_Failed

  public :: qkrt_service_new, qkrt_service_free
  public :: qkrt_backend_search, qkrt_backend_search_results_free
  public :: qkrt_backend_search_results_length, qkrt_backend_search_results_data
  public :: qkrt_backend_search_results_least_busy, qkrt_get_backend_target
  public :: qkrt_backend_name, qkrt_backend_instance_crn, qkrt_backend_instance_name
  public :: qkrt_sampler_job_run, qkrt_estimator_job_run
  public :: qkrt_job_status, qkrt_job_free, generate_qpy
  public :: qkrt_sampler_job_results, qkrt_estimator_job_results
  public :: qkrt_samples_num_samples, qkrt_samples_get_sample, qkrt_samples_free
  public :: qkrt_expectation_values_num_evs, qkrt_expectation_values_get_ev
  public :: qkrt_expectation_values_free, qkrt_str_free

  integer(c_int32_t), parameter :: QkrtExitCode_Success                       = 0
  integer(c_int32_t), parameter :: QkrtExitCode_NullPointerError              = 1
  integer(c_int32_t), parameter :: QkrtExitCode_AlignmentError                = 2
  integer(c_int32_t), parameter :: QkrtExitCode_BadArgumentError              = 3
  integer(c_int32_t), parameter :: QkrtExitCode_QuantumAPIUnhandledError      = 100
  integer(c_int32_t), parameter :: QkrtExitCode_QuantumAPIBadRequest          = 101
  integer(c_int32_t), parameter :: QkrtExitCode_QuantumAPIUnauthenticated     = 102
  integer(c_int32_t), parameter :: QkrtExitCode_QuantumAPIForbidden           = 103
  integer(c_int32_t), parameter :: QkrtExitCode_QuantumAPINotFound            = 104
  integer(c_int32_t), parameter :: QkrtExitCode_QuantumAPIConflict            = 105
  integer(c_int32_t), parameter :: QkrtExitCode_GlobalSearchAPIUnhandledError = 200
  integer(c_int32_t), parameter :: QkrtExitCode_IAMAPIUnhandledError          = 300

  integer(c_int32_t), parameter :: QkrtJobStatus_Queued              = 0
  integer(c_int32_t), parameter :: QkrtJobStatus_Running             = 1
  integer(c_int32_t), parameter :: QkrtJobStatus_Completed           = 2
  integer(c_int32_t), parameter :: QkrtJobStatus_Cancelled           = 3
  integer(c_int32_t), parameter :: QkrtJobStatus_CancelledRanTooLong = 4
  integer(c_int32_t), parameter :: QkrtJobStatus_Failed              = 5

  interface

    function qkrt_service_new(out) result(rc) bind(C, name="qkrt_service_new")
      import :: c_ptr, c_int32_t
      type(c_ptr), intent(out) :: out
      integer(c_int32_t) :: rc
    end function

    subroutine qkrt_service_free(service) bind(C, name="qkrt_service_free")
      import :: c_ptr
      type(c_ptr), value :: service
    end subroutine

    function qkrt_backend_search(out, service) result(rc) &
        bind(C, name="qkrt_backend_search")
      import :: c_ptr, c_int32_t
      type(c_ptr), intent(out) :: out
      type(c_ptr), value       :: service
      integer(c_int32_t) :: rc
    end function

    subroutine qkrt_backend_search_results_free(results) &
        bind(C, name="qkrt_backend_search_results_free")
      import :: c_ptr
      type(c_ptr), value :: results
    end subroutine

    function qkrt_backend_search_results_length(results) result(n) &
        bind(C, name="qkrt_backend_search_results_length")
      import :: c_ptr, c_int64_t
      type(c_ptr), value :: results
      integer(c_int64_t) :: n
    end function

    function qkrt_backend_search_results_data(results) result(data) &
        bind(C, name="qkrt_backend_search_results_data")
      import :: c_ptr
      type(c_ptr), value :: results
      type(c_ptr) :: data
    end function

    function qkrt_backend_search_results_least_busy(results) result(backend) &
        bind(C, name="qkrt_backend_search_results_least_busy")
      import :: c_ptr
      type(c_ptr), value :: results
      type(c_ptr) :: backend
    end function

    function qkrt_get_backend_target(service, backend) result(target) &
        bind(C, name="qkrt_get_backend_target")
      import :: c_ptr
      type(c_ptr), value :: service, backend
      type(c_ptr) :: target
    end function

    function qkrt_backend_name(backend) result(s) bind(C, name="qkrt_backend_name")
      import :: c_ptr
      type(c_ptr), value :: backend
      type(c_ptr) :: s
    end function

    function qkrt_backend_instance_crn(backend) result(s) &
        bind(C, name="qkrt_backend_instance_crn")
      import :: c_ptr
      type(c_ptr), value :: backend
      type(c_ptr) :: s
    end function

    function qkrt_backend_instance_name(backend) result(s) &
        bind(C, name="qkrt_backend_instance_name")
      import :: c_ptr
      type(c_ptr), value :: backend
      type(c_ptr) :: s
    end function

    ! runtime may be a null c_ptr (library default)
    function qkrt_sampler_job_run(out, service, backend, circuit, shots, runtime) &
        result(rc) bind(C, name="qkrt_sampler_job_run")
      import :: c_ptr, c_int32_t
      type(c_ptr), intent(out)  :: out
      type(c_ptr), value        :: service, backend, circuit
      integer(c_int32_t), value :: shots
      type(c_ptr), value        :: runtime
      integer(c_int32_t) :: rc
    end function

    function qkrt_estimator_job_run(out, service, backend, circuit, observable, runtime) &
        result(rc) bind(C, name="qkrt_estimator_job_run")
      import :: c_ptr, c_int32_t
      type(c_ptr), intent(out) :: out
      type(c_ptr), value       :: service, backend, circuit, observable, runtime
      integer(c_int32_t) :: rc
    end function

    function qkrt_job_status(out, service, job) result(rc) &
        bind(C, name="qkrt_job_status")
      import :: c_ptr, c_int32_t
      integer(c_int32_t), intent(out) :: out
      type(c_ptr), value              :: service, job
      integer(c_int32_t) :: rc
    end function

    subroutine qkrt_job_free(job) bind(C, name="qkrt_job_free")
      import :: c_ptr
      type(c_ptr), value :: job
    end subroutine

    subroutine generate_qpy(circuit, filename) bind(C, name="generate_qpy")
      import :: c_ptr, c_char
      type(c_ptr), value                 :: circuit
      character(kind=c_char), intent(in) :: filename(*)
    end subroutine

    function qkrt_sampler_job_results(out, service, job) result(rc) &
        bind(C, name="qkrt_sampler_job_results")
      import :: c_ptr, c_int32_t
      type(c_ptr), intent(out) :: out
      type(c_ptr), value       :: service, job
      integer(c_int32_t) :: rc
    end function

    function qkrt_estimator_job_results(out, service, job) result(rc) &
        bind(C, name="qkrt_estimator_job_results")
      import :: c_ptr, c_int32_t
      type(c_ptr), intent(out) :: out
      type(c_ptr), value       :: service, job
      integer(c_int32_t) :: rc
    end function

    function qkrt_samples_num_samples(samples) result(n) &
        bind(C, name="qkrt_samples_num_samples")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: samples
      integer(c_size_t) :: n
    end function

    function qkrt_samples_get_sample(samples, index) result(s) &
        bind(C, name="qkrt_samples_get_sample")
      import :: c_ptr, c_size_t
      type(c_ptr), value       :: samples
      integer(c_size_t), value :: index
      type(c_ptr) :: s
    end function

    subroutine qkrt_samples_free(samples) bind(C, name="qkrt_samples_free")
      import :: c_ptr
      type(c_ptr), value :: samples
    end subroutine

    function qkrt_expectation_values_num_evs(evs) result(n) &
        bind(C, name="qkrt_expectation_values_num_evs")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: evs
      integer(c_size_t) :: n
    end function

    function qkrt_expectation_values_get_ev(evs, index) result(ev) &
        bind(C, name="qkrt_expectation_values_get_ev")
      import :: c_ptr, c_size_t, c_double
      type(c_ptr), value       :: evs
      integer(c_size_t), value :: index
      real(c_double) :: ev
    end function

    subroutine qkrt_expectation_values_free(evs) &
        bind(C, name="qkrt_expectation_values_free")
      import :: c_ptr
      type(c_ptr), value :: evs
    end subroutine

    subroutine qkrt_str_free(string) bind(C, name="qkrt_str_free")
      import :: c_ptr
      type(c_ptr), value :: string
    end subroutine

  end interface

end module qiskit_c_api_runtime
