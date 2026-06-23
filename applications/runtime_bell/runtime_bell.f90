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

! Build a Bell circuit, transpile it for the target backend, submit it to IBM
! Quantum, and read the samples back.
! Needs IBM Quantum credentials in the environment.

program runtime_bell
  use qiskit
  use qiskit_runtime
  use, intrinsic :: iso_c_binding, only : c_int64_t, c_size_t
  implicit none (type, external)

  type(QuantumCircuit)  :: qc, qc_transpiled
  type(RtService)       :: service
  type(RtBackendList)   :: backends
  type(RtBackend)       :: backend
  type(Target)          :: backend_target
  type(RtJob)           :: job
  type(RtSamplerResult) :: res

  integer            :: status
  integer(c_int64_t) :: i, n_backends
  integer(c_size_t)  :: s, n_samples, n_show
  integer, parameter :: shots = 4096

  ! 1. Build a Bell state: H(0), CX(0,1), measure all.
  call qc%init(num_qubits=2, num_clbits=2)
  call qc%h(0)
  call qc%cx(0, 1)
  call qc%measure_all()
  print '(a, i0, a)', "Built Bell circuit with ", qc%num_instructions(), " instructions."
  call flush(6)

  ! 2. Connect to the runtime.
  print '(a)', "Connecting to IBM Quantum Runtime..."
  call flush(6)
  call service%connect()
  print '(a)', "Connected successfully."
  call flush(6)

  ! 3. List backends and select the least busy.
  print '(a)', "Fetching backends..."
  call flush(6)
  call service%backends(backends)
  n_backends = backends%length()
  print '(a, i0, a)', "Found ", n_backends, " backend(s):"
  call flush(6)
  do i = 0, n_backends - 1
    backend = backends%get(int(i))
    print '(a, i0, a, a, a, a, a)', "  [", i, "] ", backend%name(), " (", backend%instance_name(), ")"
  end do

  print '(a)', "Selecting least busy backend..."
  call flush(6)
  backend = backends%least_busy()
  if (.not. backend%is_valid()) error stop "No backends available."
  print '(/, a, a)', "Least busy backend: ", backend%name()
  call flush(6)

  ! 4. Get backend target and transpile the circuit.
  print '(/, a)', "Fetching backend target..."
  call flush(6)
  call backend%get_target(service, backend_target)
  print '(a, i0, a)', "Target has ", backend_target%num_qubits(), " qubits."
  call flush(6)
  
  print '(a)', "Transpiling circuit for backend..."
  call flush(6)
  qc_transpiled = transpile(qc, backend=backend_target)
  print '(a, i0, a)', "Transpiled circuit has ", qc_transpiled%num_instructions(), " instructions."
  call flush(6)

  ! 5. Submit a Sampler job.
  print '(/, a, i0, a)', "Submitting Sampler job (", shots, " shots)..."
  call service%run_sampler(job, backend, qc_transpiled, shots=shots)
  print '(a)', "Job submitted."

  ! 6. Poll until terminal.
  do
    status = service%job_status(job)
    print '(a, a)', "  status: ", job_status_name(status)
    if (job_is_terminal(status)) exit
    call sleep(20)   ! GNU/flang intrinsic; poll interval in seconds
  end do

  if (status /= int(QkrtJobStatus_Completed)) then
    print '(a, a)', "Job did not complete: ", job_status_name(status)
    error stop 1
  end if

  ! 7. Fetch results.
  call service%sampler_results(res, job)
  n_samples = res%num_samples()
  print '(/, a, i0, a)', "Job completed with ", n_samples, " sample(s)."

  n_show = min(n_samples, 5_c_size_t)
  do s = 0_c_size_t, n_show - 1_c_size_t
    print '(a, i0, a, a)', "  sample[", s, "] = ", res%sample(int(s))
  end do

  ! All handles (service, backends, job, res, qc, qc_transpiled, backend_target) free themselves on scope exit.
end program runtime_bell
