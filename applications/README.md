# Applications

This directory contains self-contained Fortran programs built on top of `qiskit-fortran`. They are separate from the unit tests in `test/` the tests verify binding correctness; the applications show what you can do with a correct binding.

Each application lives in its own subdirectory with its own `README.md` and compiles independently against the `qiskit-fortran` library.

---

## Building an application

All applications use the same build pattern. From the repo root, after building `qiskit-fortran`:

```bash
cd applications
cmake -B build \
      -DAPP_NAME=bell_state \
      -DQISKIT_FORTRAN_ROOT=/path/to/qiskit-fortran/build \
      -DQISKIT_ROOT=/path/to/qiskit
cmake --build build
./build/bell_state
```

---

## Contributing an application

An application belongs here if it:

- compiles and runs correctly against the current `main` of `qiskit-fortran`
- demonstrates a use of the binding that is not already covered by the unit tests

The structure for a new application:

```
applications/
└── your_application/
    ├── README.md          # what it does, how to build, how to run, expected output
    └── your_application.f90
```

The `README.md` should state what the program demonstrates in terms of the Fortran API, just which modules and derived types it exercises. If it produces numerical output, include the expected values so a reader can verify correctness.

Open an issue before starting on a larger application so it can be discussed before implementation. The [open issues](https://github.com/Qiskit/qiskit-fortran/issues) list applications that are explicitly looking for contributors.

See [`APPLICATIONS.md`](../docs/APPLICATIONS.md) for the broader context on where these applications point.