# runtime_bell

Submits a Bell circuit to IBM Quantum through `qiskit_runtime` and prints the
samples it gets back.

Builds the circuit (`H(0)`, `CX(0,1)`, measure), connects, picks the least busy
backend, transpiles the circuit for the target backend, runs a Sampler job,
polls until it's done, reads the samples.

## Needs

- IBM Quantum credentials in the environment (same setup as the
  [qiskit-ibm-runtime-c](https://github.com/Qiskit/qiskit-ibm-runtime-c) samples)
- `libqiskit` and `libqiskit_ibm_runtime`

## Build and run

```bash
cd applications
cmake -B build \
      -DAPP_NAME=runtime_bell \
      -DQISKIT_FORTRAN_ROOT=/path/to/qiskit-fortran/build \
      -DQISKIT_ROOT=/path/to/qiskit \
      -DQISKIT_RUNTIME_ROOT=/path/to/qiskit-ibm-runtime-c
cmake --build build
./build/runtime_bell
```

Backends and counts depend on your account. For a Bell state the samples
cluster on `00` and `11`.

The circuit is now transpiled for the target backend before submission using
the `transpile()` function from the `qiskit` module. This ensures the circuit
is compatible with the backend's gate set and connectivity constraints.
