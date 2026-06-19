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

! High-level wrapper over qiskit_c_api_runtime: submit a QuantumCircuit to IBM
! Quantum and read results back as Fortran strings and arrays. Owning handles
! free themselves via FINAL. Owning results come back through intent(out)
! subroutine args (a returned-then-finalised value would double-free the handle).
! Types carry an Rt prefix so a variable can keep the obvious name (job, backend).
! An RtBackend is non-owning: do not use one after its RtBackendList is gone.
! See applications/runtime_bell for a full run.
module qiskit_runtime
  use, intrinsic :: iso_c_binding, only : &
      c_ptr, c_null_ptr, c_null_char, c_char, c_associated, c_loc, c_f_pointer, &
      c_int32_t, c_int64_t, c_size_t, c_double
  use qiskit_circuit,        only : QuantumCircuit
  use qiskit_c_api_runtime

  implicit none (type, external)
  private

  public :: RtService, RtBackendList, RtBackend, RtJob, RtSamplerResult, RtEstimatorResult
  public :: job_is_terminal, job_status_name
  public :: QkrtJobStatus_Queued, QkrtJobStatus_Running, QkrtJobStatus_Completed
  public :: QkrtJobStatus_Cancelled, QkrtJobStatus_CancelledRanTooLong, QkrtJobStatus_Failed

  type :: RtService
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public :: connect           => svc_connect
    procedure, public :: is_connected      => svc_is_connected
    procedure, public :: backends          => svc_backends
    procedure, public :: run_sampler       => svc_run_sampler
    procedure, public :: run_estimator     => svc_run_estimator
    procedure, public :: job_status        => svc_job_status
    procedure, public :: sampler_results   => svc_sampler_results
    procedure, public :: estimator_results => svc_estimator_results
    final :: svc_destroy
  end type

  type :: RtBackendList
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public :: length     => bl_length
    procedure, public :: get        => bl_get
    procedure, public :: least_busy => bl_least_busy
    final :: bl_destroy
  end type

  ! non-owning; owned by the RtBackendList it came from
  type :: RtBackend
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public :: name          => be_name
    procedure, public :: instance_crn  => be_instance_crn
    procedure, public :: instance_name => be_instance_name
    procedure, public :: is_valid      => be_is_valid
    procedure, public :: get_target    => be_get_target_sub
  end type

  type :: RtJob
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    final :: job_destroy
  end type

  type :: RtSamplerResult
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public :: num_samples => sr_num_samples
    procedure, public :: sample      => sr_sample
    final :: sr_destroy
  end type

  type :: RtEstimatorResult
    private
    type(c_ptr) :: ptr = c_null_ptr
  contains
    procedure, public :: num_values => er_num_values
    procedure, public :: value      => er_value
    procedure, public :: values     => er_values
    final :: er_destroy
  end type

  interface
    function c_strlen(s) result(n) bind(C, name="strlen")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: s
      integer(c_size_t) :: n
    end function
  end interface

contains

  ! --- RtService ------------------------------------------------------------

  ! credentials come from the environment, as in the C library
  subroutine svc_connect(self)
    class(RtService), intent(inout) :: self
    integer(c_int32_t) :: rc
    if (c_associated(self%ptr)) then
      call qkrt_service_free(self%ptr)
      self%ptr = c_null_ptr
    end if
    rc = qkrt_service_new(self%ptr)
    call check_rt(rc, "connect")
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] connect: null service"
  end subroutine

  function svc_is_connected(self) result(ok)
    class(RtService), intent(in) :: self
    logical :: ok
    ok = c_associated(self%ptr)
  end function

  subroutine svc_destroy(self)
    type(RtService), intent(inout) :: self
    if (c_associated(self%ptr)) call qkrt_service_free(self%ptr)
    self%ptr = c_null_ptr
  end subroutine

  subroutine svc_backends(self, list)
    class(RtService),    intent(in)  :: self
    type(RtBackendList), intent(out) :: list
    integer(c_int32_t) :: rc
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] backends: not connected"
    rc = qkrt_backend_search(list%ptr, self%ptr)
    call check_rt(rc, "backends")
  end subroutine

  ! circuit is submitted as built; transpile for hardware first.
  ! runtime is the primitive name; omit it for the library default.
  subroutine svc_run_sampler(self, job, backend, circuit, shots, runtime)
    class(RtService),     intent(in)  :: self
    type(RtJob),          intent(out) :: job
    type(RtBackend),      intent(in)  :: backend
    type(QuantumCircuit), intent(in)  :: circuit
    integer,              intent(in)  :: shots
    character(len=*),     intent(in), optional :: runtime
    integer(c_int32_t) :: rc
    character(kind=c_char), allocatable, target :: rt(:)
    type(c_ptr) :: rt_ptr
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] run_sampler: not connected"
    rt_ptr = c_null_ptr
    if (present(runtime)) then
      rt = f_c_string(runtime)
      rt_ptr = c_loc(rt(1))
    end if
    rc = qkrt_sampler_job_run(job%ptr, self%ptr, backend%ptr, circuit%c_handle(), &
                              int(shots, c_int32_t), rt_ptr)
    call check_rt(rc, "run_sampler")
  end subroutine

  ! observable is a QkObs* from the core C API (no idiomatic type bound yet)
  subroutine svc_run_estimator(self, job, backend, circuit, observable, runtime)
    class(RtService),     intent(in)  :: self
    type(RtJob),          intent(out) :: job
    type(RtBackend),      intent(in)  :: backend
    type(QuantumCircuit), intent(in)  :: circuit
    type(c_ptr),          intent(in)  :: observable
    character(len=*),     intent(in), optional :: runtime
    integer(c_int32_t) :: rc
    character(kind=c_char), allocatable, target :: rt(:)
    type(c_ptr) :: rt_ptr
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] run_estimator: not connected"
    rt_ptr = c_null_ptr
    if (present(runtime)) then
      rt = f_c_string(runtime)
      rt_ptr = c_loc(rt(1))
    end if
    rc = qkrt_estimator_job_run(job%ptr, self%ptr, backend%ptr, circuit%c_handle(), &
                                observable, rt_ptr)
    call check_rt(rc, "run_estimator")
  end subroutine

  function svc_job_status(self, job) result(status)
    class(RtService), intent(in) :: self
    type(RtJob),      intent(in) :: job
    integer :: status
    integer(c_int32_t) :: rc, st
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] job_status: not connected"
    rc = qkrt_job_status(st, self%ptr, job%ptr)
    call check_rt(rc, "job_status")
    status = int(st)
  end function

  subroutine svc_sampler_results(self, result, job)
    class(RtService),      intent(in)  :: self
    type(RtSamplerResult), intent(out) :: result
    type(RtJob),           intent(in)  :: job
    integer(c_int32_t) :: rc
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] sampler_results: not connected"
    rc = qkrt_sampler_job_results(result%ptr, self%ptr, job%ptr)
    call check_rt(rc, "sampler_results")
  end subroutine

  subroutine svc_estimator_results(self, result, job)
    class(RtService),        intent(in)  :: self
    type(RtEstimatorResult), intent(out) :: result
    type(RtJob),             intent(in)  :: job
    integer(c_int32_t) :: rc
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] estimator_results: not connected"
    rc = qkrt_estimator_job_results(result%ptr, self%ptr, job%ptr)
    call check_rt(rc, "estimator_results")
  end subroutine

  ! --- RtBackendList --------------------------------------------------------

  function bl_length(self) result(n)
    class(RtBackendList), intent(in) :: self
    integer(c_int64_t) :: n
    n = 0
    if (c_associated(self%ptr)) n = qkrt_backend_search_results_length(self%ptr)
  end function

  ! index is 0-based, matching the C API
  function bl_get(self, index) result(be)
    class(RtBackendList), intent(in) :: self
    integer,              intent(in) :: index
    type(RtBackend) :: be
    type(c_ptr)          :: data_ptr
    type(c_ptr), pointer :: arr(:)
    integer(c_int64_t)   :: n
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] get: empty listing"
    n = qkrt_backend_search_results_length(self%ptr)
    if (index < 0 .or. int(index, c_int64_t) >= n) &
        error stop "[qiskit_runtime] get: index out of range"
    data_ptr = qkrt_backend_search_results_data(self%ptr)
    call c_f_pointer(data_ptr, arr, [n])
    be%ptr = arr(index + 1)
  end function

  ! check %is_valid() in case the listing was empty
  function bl_least_busy(self) result(be)
    class(RtBackendList), intent(in) :: self
    type(RtBackend) :: be
    be%ptr = c_null_ptr
    if (c_associated(self%ptr)) be%ptr = qkrt_backend_search_results_least_busy(self%ptr)
  end function

  subroutine bl_destroy(self)
    type(RtBackendList), intent(inout) :: self
    if (c_associated(self%ptr)) call qkrt_backend_search_results_free(self%ptr)
    self%ptr = c_null_ptr
  end subroutine

  ! --- RtBackend ------------------------------------------------------------

  function be_name(self) result(s)
    class(RtBackend), intent(in) :: self
    character(len=:), allocatable :: s
    s = c_str(qkrt_backend_name(self%ptr))
  end function

  function be_instance_crn(self) result(s)
    class(RtBackend), intent(in) :: self
    character(len=:), allocatable :: s
    s = c_str(qkrt_backend_instance_crn(self%ptr))
  end function

  function be_instance_name(self) result(s)
    class(RtBackend), intent(in) :: self
    character(len=:), allocatable :: s
    s = c_str(qkrt_backend_instance_name(self%ptr))
  end function

  pure function be_is_valid(self) result(ok)
    class(RtBackend), intent(in) :: self
    logical :: ok
    ok = c_associated(self%ptr)
  end function

  !> @brief Get the Target for this backend
  !> @param service the runtime service (needed to fetch backend configuration)
  !> @param backend_target [out] Target object representing backend constraints
  subroutine be_get_target_sub(self, service, backend_target)
    use qiskit_target, only : Target
    class(RtBackend), intent(in) :: self
    type(RtService), intent(in) :: service
    type(Target), intent(out) :: backend_target
    type(c_ptr) :: target_ptr
    
    if (.not. c_associated(self%ptr)) &
        error stop "[qiskit_runtime] get_target: invalid backend"
    if (.not. c_associated(service%ptr)) &
        error stop "[qiskit_runtime] get_target: service not connected"
    
    target_ptr = qkrt_get_backend_target(service%ptr, self%ptr)
    
    if (.not. c_associated(target_ptr)) &
        error stop "[qiskit_runtime] get_target: failed to retrieve target"
    
    call backend_target%from_ptr(target_ptr)
  end subroutine be_get_target_sub

  ! --- RtJob ----------------------------------------------------------------

  subroutine job_destroy(self)
    type(RtJob), intent(inout) :: self
    if (c_associated(self%ptr)) call qkrt_job_free(self%ptr)
    self%ptr = c_null_ptr
  end subroutine

  ! --- RtSamplerResult ------------------------------------------------------

  function sr_num_samples(self) result(n)
    class(RtSamplerResult), intent(in) :: self
    integer(c_size_t) :: n
    n = 0
    if (c_associated(self%ptr)) n = qkrt_samples_num_samples(self%ptr)
  end function

  ! 0-based
  function sr_sample(self, index) result(s)
    class(RtSamplerResult), intent(in) :: self
    integer,                intent(in) :: index
    character(len=:), allocatable :: s
    type(c_ptr) :: cstr
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] sample: no results"
    cstr = qkrt_samples_get_sample(self%ptr, int(index, c_size_t))
    s = c_str(cstr)
    call qkrt_str_free(cstr)
  end function

  subroutine sr_destroy(self)
    type(RtSamplerResult), intent(inout) :: self
    if (c_associated(self%ptr)) call qkrt_samples_free(self%ptr)
    self%ptr = c_null_ptr
  end subroutine

  ! --- RtEstimatorResult ----------------------------------------------------

  function er_num_values(self) result(n)
    class(RtEstimatorResult), intent(in) :: self
    integer(c_size_t) :: n
    n = 0
    if (c_associated(self%ptr)) n = qkrt_expectation_values_num_evs(self%ptr)
  end function

  ! 0-based
  function er_value(self, index) result(v)
    class(RtEstimatorResult), intent(in) :: self
    integer,                  intent(in) :: index
    real(c_double) :: v
    if (.not. c_associated(self%ptr)) error stop "[qiskit_runtime] value: no results"
    v = qkrt_expectation_values_get_ev(self%ptr, int(index, c_size_t))
  end function

  function er_values(self) result(arr)
    class(RtEstimatorResult), intent(in) :: self
    real(c_double), allocatable :: arr(:)
    integer(c_size_t) :: n, i
    n = self%num_values()
    allocate(arr(n))
    do i = 1_c_size_t, n
      arr(i) = qkrt_expectation_values_get_ev(self%ptr, i - 1_c_size_t)
    end do
  end function

  subroutine er_destroy(self)
    type(RtEstimatorResult), intent(inout) :: self
    if (c_associated(self%ptr)) call qkrt_expectation_values_free(self%ptr)
    self%ptr = c_null_ptr
  end subroutine

  ! --- status helpers -------------------------------------------------------

  pure function job_is_terminal(status) result(done)
    integer, intent(in) :: status
    logical :: done
    done = .not. (status == int(QkrtJobStatus_Queued) .or. &
                  status == int(QkrtJobStatus_Running))
  end function

  pure function job_status_name(status) result(name)
    integer, intent(in) :: status
    character(len=:), allocatable :: name
    select case (status)
    case (int(QkrtJobStatus_Queued));              name = "Queued"
    case (int(QkrtJobStatus_Running));             name = "Running"
    case (int(QkrtJobStatus_Completed));           name = "Completed"
    case (int(QkrtJobStatus_Cancelled));           name = "Cancelled"
    case (int(QkrtJobStatus_CancelledRanTooLong)); name = "CancelledRanTooLong"
    case (int(QkrtJobStatus_Failed));              name = "Failed"
    case default;                                  name = "Unknown"
    end select
  end function

  ! --- internal -------------------------------------------------------------

  subroutine check_rt(rc, context)
    integer(c_int32_t), intent(in) :: rc
    character(len=*),   intent(in) :: context
    if (rc == QkrtExitCode_Success) return
    select case (rc)
    case (QkrtExitCode_NullPointerError)
      error stop "[qiskit_runtime] " // context // ": null pointer"
    case (QkrtExitCode_AlignmentError)
      error stop "[qiskit_runtime] " // context // ": pointer not aligned"
    case (QkrtExitCode_BadArgumentError)
      error stop "[qiskit_runtime] " // context // ": invalid argument"
    case (QkrtExitCode_QuantumAPIBadRequest)
      error stop "[qiskit_runtime] " // context // ": IBM Quantum rejected the request"
    case (QkrtExitCode_QuantumAPIUnauthenticated)
      error stop "[qiskit_runtime] " // context // ": IBM Quantum auth required (check credentials)"
    case (QkrtExitCode_QuantumAPIForbidden)
      error stop "[qiskit_runtime] " // context // ": IBM Quantum permission denied"
    case (QkrtExitCode_QuantumAPINotFound)
      error stop "[qiskit_runtime] " // context // ": IBM Quantum resource not found"
    case (QkrtExitCode_QuantumAPIConflict)
      error stop "[qiskit_runtime] " // context // ": IBM Quantum conflict"
    case (QkrtExitCode_QuantumAPIUnhandledError)
      error stop "[qiskit_runtime] " // context // ": IBM Quantum platform error"
    case (QkrtExitCode_GlobalSearchAPIUnhandledError)
      error stop "[qiskit_runtime] " // context // ": IBM Global Search error"
    case (QkrtExitCode_IAMAPIUnhandledError)
      error stop "[qiskit_runtime] " // context // ": IBM IAM error"
    case default
      error stop "[qiskit_runtime] " // context // ": runtime error"
    end select
  end subroutine

  ! NUL-terminated C string -> allocatable Fortran string
  function c_str(cptr) result(s)
    type(c_ptr), intent(in) :: cptr
    character(len=:), allocatable :: s
    character(kind=c_char), pointer :: chars(:)
    integer(c_size_t) :: n
    integer :: i
    if (.not. c_associated(cptr)) then
      s = ""
      return
    end if
    n = c_strlen(cptr)
    call c_f_pointer(cptr, chars, [n])
    allocate(character(len=int(n)) :: s)
    do i = 1, int(n)
      s(i:i) = chars(i)
    end do
  end function

  ! Fortran string -> NUL-terminated c_char buffer
  function f_c_string(s) result(buf)
    character(len=*), intent(in) :: s
    character(kind=c_char), allocatable :: buf(:)
    integer :: i, n
    n = len_trim(s)
    allocate(buf(n + 1))
    do i = 1, n
      buf(i) = s(i:i)
    end do
    buf(n + 1) = c_null_char
  end function

end module qiskit_runtime
