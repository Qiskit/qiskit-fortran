#!/usr/bin/env bash
# Build the nuclear_shell application and its dependencies.  Every step is
# skipped when its output already exists, so re-running is cheap.
# Manual equivalent: applications/nuclear_shell/BUILD_INSTRUCTIONS.md
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

WORK_DIR="${WORK_DIR:-$HOME/qf-work}"   # where dependencies are cloned
QISKIT_TAG="${QISKIT_TAG:-2.4.2}"       # oldest series with qk_obs_add_inplace,
BUILD_TYPE="${BUILD_TYPE:-Release}"     #   newest qiskit-ibm-runtime-c supports
QISKIT_ROOT="" RUNTIME_ROOT="" FC="" JOBS="" RUNTIME=1 TESTS=1 CLEAN=0

usage() {
    cat <<EOF
Usage: ./build.sh [options]

  --no-runtime        skip qiskit-ibm-runtime-c; the driver still runs in test
                      mode and via --bitstrings-dir, only --runtime is lost
  --qiskit-root DIR   use an existing Qiskit checkout instead of cloning
  --runtime-root DIR  use an existing qiskit-ibm-runtime-c checkout
  --compiler NAME     Fortran compiler (default: gfortran, else flang)
  --jobs N            parallel jobs (default: all cores)
  --skip-tests        do not run the qiskit-fortran test suite
  --clean             delete build/ and applications/build/ first
  -h, --help

Env: WORK_DIR (default ~/qf-work), QISKIT_TAG ($QISKIT_TAG), BUILD_TYPE ($BUILD_TYPE)

Needs git, cmake >= 3.20, make, cargo and a Fortran compiler:
  macOS   brew install gcc cmake gsl libomp rust
  Debian  sudo apt install gfortran cmake make cargo libgsl-dev liblapack-dev
GSL and OpenMP are optional (Racah fallback / serial Hamiltonian build).
Python Qiskit is not needed -- \`make c\` is pure cargo.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-runtime)   RUNTIME=0;         shift ;;
        --qiskit-root)  QISKIT_ROOT="$2";  shift 2 ;;
        --runtime-root) RUNTIME_ROOT="$2"; shift 2 ;;
        --compiler)     FC="$2";           shift 2 ;;
        --jobs|-j)      JOBS="$2";         shift 2 ;;
        --skip-tests)   TESTS=0;           shift ;;
        --clean)        CLEAN=1;           shift ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "unknown option '$1'" >&2; usage >&2; exit 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$1"; }
say()  { printf '    %s\n' "$*"; }
run()  { printf '    $ %s\n' "$*"; "$@"; }
die()  { printf '\nbuild.sh: %s\n' "$1" >&2; exit 1; }

# --- prerequisites ---------------------------------------------------------
step "Prerequisites"
if [[ "$(uname -s)" == Darwin ]]; then NCPU="$(sysctl -n hw.ncpu)"
else NCPU="$(nproc 2>/dev/null || echo 4)"; fi
JOBS="${JOBS:-$NCPU}"

for tool in git cmake make cargo; do
    command -v "$tool" >/dev/null || die "'$tool' not found.  See ./build.sh --help"
done
if [[ -z "$FC" ]]; then
    for c in gfortran gfortran-15 gfortran-14 gfortran-13 gfortran-12 gfortran-11 flang; do
        if command -v "$c" >/dev/null; then FC="$c"; break; fi
    done
    [[ -n "$FC" ]] || die "no Fortran compiler found.  See ./build.sh --help"
fi
FC="$(command -v "$FC")" || die "compiler '$FC' not found"

say "compiler $FC, $JOBS jobs, $BUILD_TYPE"

# --- Qiskit C extension, and the runtime client when requested -------------
if ((RUNTIME)); then step "Qiskit C extension and IBM Runtime client"; else step "Qiskit C extension"; fi

make_c() {  # $1 = Qiskit checkout
    if [[ -f "$1/dist/c/include/qiskit.h" ]] && compgen -G "$1/dist/c/lib/libqiskit.*" >/dev/null; then
        say "already built: $1/dist/c"
    else
        run make -C "$1" c          # cargo build, several minutes
    fi
}

if [[ -n "$QISKIT_ROOT" ]]; then
    [[ -d "$QISKIT_ROOT" ]] || die "--qiskit-root '$QISKIT_ROOT' does not exist"
    QISKIT_ROOT="$(cd -- "$QISKIT_ROOT" && pwd)"
    [[ -f "$QISKIT_ROOT/Makefile" ]] || die "$QISKIT_ROOT is not a Qiskit checkout"
    make_c "$QISKIT_ROOT"
fi

if ((RUNTIME)); then
    if [[ -n "$RUNTIME_ROOT" ]]; then
        [[ -d "$RUNTIME_ROOT" ]] || die "--runtime-root '$RUNTIME_ROOT' does not exist"
        RUNTIME_ROOT="$(cd -- "$RUNTIME_ROOT" && pwd)"
    else
        RUNTIME_ROOT="$WORK_DIR/qiskit-ibm-runtime-c"
        [[ -d "$RUNTIME_ROOT/.git" ]] ||
            run git clone --depth 1 https://github.com/Qiskit/qiskit-ibm-runtime-c.git "$RUNTIME_ROOT"
    fi
    # release and debug are the two locations the root CMakeLists searches
    if compgen -G "$RUNTIME_ROOT/build/cargo/release/libqiskit_ibm_runtime.*" >/dev/null ||
       compgen -G "$RUNTIME_ROOT/build/cargo/debug/libqiskit_ibm_runtime.*" >/dev/null; then
        say "already built: libqiskit_ibm_runtime"
    else
        run cmake -S "$RUNTIME_ROOT" -B "$RUNTIME_ROOT/build" -DCMAKE_BUILD_TYPE=Release
        run cmake --build "$RUNTIME_ROOT/build" --parallel "$JOBS"
    fi
    # It builds its own Qiskit (GIT_TAG main); reuse that rather than build twice.
    if [[ -z "$QISKIT_ROOT" ]]; then QISKIT_ROOT="$RUNTIME_ROOT/build/qiskit_srcdir"; fi
elif [[ -z "$QISKIT_ROOT" ]]; then
    QISKIT_ROOT="$WORK_DIR/qiskit"
    [[ -d "$QISKIT_ROOT/.git" ]] ||
        run git clone --depth 1 --branch "$QISKIT_TAG" https://github.com/Qiskit/qiskit.git "$QISKIT_ROOT"
    make_c "$QISKIT_ROOT"
fi
say "Qiskit: $QISKIT_ROOT"

# qiskit_observable.f90 needs the in-place QkObs arithmetic added in 2.4.0.
ver="$(cat "$QISKIT_ROOT/qiskit/VERSION.txt" 2>/dev/null || echo "")"
base="${ver%%.dev*}"; base="${base%%rc*}"
if [[ -n "$base" ]]; then
    say "version $ver"
    [[ "$(printf '%s\n2.4.0\n' "$base" | sort -V | head -1)" == "2.4.0" ]] ||
        die "Qiskit $ver is too old: src/qiskit_observable.f90 calls qk_obs_add_inplace and
       friends, added in 2.4.0.  Re-run with QISKIT_TAG=$QISKIT_TAG and no --qiskit-root."
    minor="$(cut -d. -f2 <<<"$base")"
    if ((RUNTIME)) && [[ "$minor" =~ ^[0-9]+$ ]] && ((minor > 4)); then
        say "! Qiskit $ver is newer than the 2.4 ceiling qiskit-ibm-runtime-c declares;"
        say "! if --runtime misbehaves, point --qiskit-root at a 2.4.x checkout"
    fi
fi

# --- qiskit-fortran -------------------------------------------------------
step "qiskit-fortran"
FBUILD="$REPO/build" ABUILD="$REPO/applications/build"
if ((CLEAN)); then run rm -rf "$FBUILD" "$ABUILD"; fi

# gfortran and flang cannot read each other's .mod files, and a build tree
# cannot switch compilers in place, so wipe on mismatch.
for tree in "$FBUILD" "$ABUILD"; do
    # `|| true`: no cache yet (fresh or --clean tree) must not trip `set -e`
    had="$(sed -n 's/^CMAKE_Fortran_COMPILER:[^=]*=//p' "$tree/CMakeCache.txt" 2>/dev/null || true)"
    if [[ -n "$had" && "$had" != "$FC" ]]; then say "wiping $tree (was $had)"; run rm -rf "$tree"; fi
done

rt_flags=()
if ((RUNTIME)); then rt_flags=(-DQISKIT_FORTRAN_RUNTIME=ON -DQISKIT_RUNTIME_ROOT="$RUNTIME_ROOT"); fi

run cmake -S "$REPO" -B "$FBUILD" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_Fortran_COMPILER="$FC" -DQISKIT_ROOT="$QISKIT_ROOT" \
    -DUSE_SWIG_BINDINGS=ON ${rt_flags[@]+"${rt_flags[@]}"}
run cmake --build "$FBUILD" --parallel "$JOBS"

if ((TESTS)) && [[ -x "$FBUILD/test_qiskit" ]]; then
    "$FBUILD/test_qiskit" > "$FBUILD/test_qiskit.log" 2>&1 ||
        { tail -20 "$FBUILD/test_qiskit.log"; die "test_qiskit failed, log in $FBUILD/test_qiskit.log"; }
    tail -4 "$FBUILD/test_qiskit.log" | sed 's/^/    /'
fi

# --- the application ------------------------------------------------------
step "nuclear_shell"
app_flags=()
if [[ -n "$RUNTIME_ROOT" ]]; then app_flags=(-DQISKIT_RUNTIME_ROOT="$RUNTIME_ROOT"); fi

run cmake -S "$REPO/applications" -B "$ABUILD" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_Fortran_COMPILER="$FC" -DQISKIT_FORTRAN_ROOT="$FBUILD" \
    -DQISKIT_ROOT="$QISKIT_ROOT" ${app_flags[@]+"${app_flags[@]}"}
run cmake --build "$ABUILD" --parallel "$JOBS"

step "Done  -  USDB.snt is staged beside the binaries"
cat <<EOF
    cd $ABUILD/nuclear_shell
    ./nuclear_shell_driver --protons 2 --neutrons 2      # test mode, no credentials
EOF
if [[ -x "$ABUILD/nuclear_shell/nuclear_shell_parallel" ]]; then
    say "./nuclear_shell_driver --steps 3 --protons 2 --neutrons 2 --save-bitstrings"
    say "./nuclear_shell_parallel --steps 3 --protons 2 --neutrons 2   # needs those files"
fi
if ((RUNTIME)); then say "./nuclear_shell_driver --runtime ...  (credentials: ~/.qiskit/qiskit-ibm.json)"; fi
echo
