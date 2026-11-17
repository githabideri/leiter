# Building & running non-Nix software on NixOS

How to compile and run generic (non-Nix) software on a NixOS box:
toolchains, CUDA, linker/loader traps. **Dated knowledge: last verified
2026-11-17 (nixpkgs c8ccf87/26.11: the pin ships the full CUDA 13.0 set as
`pkgs.cudaPackages_13_0`; see "Check first" below), 2026-09-27 (CUDA 12.9 +
driver 580.178.04 on the nixos-unstable pin; llama.cpp upstream main
86a24a1 + GenerelSchwerz moe-cache branch). Re-verify for a new pin.**
Full narrative: see the provisioning report of the session that ran it.

TOC: (1-2) loader/linker traps (stub-ld, ld.so.cache, rpath vs RUNPATH) ·
(4-7) CUDA toolkits (check the pin first, deb assembly, Pascal ceiling,
stubs/libcuda, glibc-2.42 vs CUDA headers, CMake 4.x) · (8-10)
shell/orchestration (pkill self-kill, heredocs over ssh, timeout+env) ·
(11) solved llama-server cublasCreate anomaly + 2026 flag renames ·
(13-18) 2026-11 refinements (driver stub vs real lib, dlopen/RUNPATH, GC,
python, CMake-4 projects, native builds).

## Check first: your nixpkgs pin may already ship the CUDA toolkit (2026-11)

Before assembling a toolkit from `.deb` (item 4), check whether the **pinned**
nixpkgs already packages it. nixpkgs of the 26.11 era (c8ccf87, 2026-09-19;
measured in the 2026-11-17 bd775i session) carries a full **CUDA 13.0** set
under `pkgs.cudaPackages_13_0`:

- **`cudatoolkit`**: a *merged prefix* (`cuda-merged-13.0`): the one
  `/usr/local/cuda`-style tree that `find_package(CUDAToolkit)` expects.
- **components**: `cuda_nvcc` (13.0.88), `cuda_cudart`, `libcublas`,
  `cuda_cccl`, `cuda_crt`, `cuda_nvrtc`, `cuda_nvtx`, `cuda_nvml_dev`,
  `cuda_compat`, …
- **`backendStdenv`**: the stdenv for compiling CUDA; its host cc is the
  era the toolkit was validated against (this pin: gcc 15.3.0; CUDA 13.0
  supports GCC up to 15).
- The glibc-2.42 `noexcept`/`rsqrt` header clash (item 6) is **patched
  upstream already** in `cuda_crt` for CUDA < 13.2; the era-mismatched
  24.05-stdenv workaround was for the hand-assembled toolkit.
- **Unfree license (CUDA EULA)**: forcing a package to a store path fails
  in the `customisation.nix` assert *with the package name in the error*
  (that error is also proof the attribute exists; naive `? a` / `or {}`
  probes can report "missing" when a thunk dies on the unfree gate).
  Permitted by `nixpkgs.config.allowUnfree = true` (declarative; tighten to
  an `allowUnfreePredicate` over `cuda-*`/`nvidia-*` when you can) or
  `NIXPKGS_ALLOW_UNFREE=1`, which flake-mode commands (nix 2.34+) only see
  with `--impure`.

The deb-assembly recipe (item 4) stays valid for pins without the packaging
or versions nixpkgs does not carry (the omen-15 12.9 assembly predates it).
See `nixpkgs-pins.md` for how to be sure you asked the *pinned* nixpkgs,
not the registry's HEAD.

## Loader & linker traps (the "why does any foreign binary fail")

1. **`/lib64/ld-linux-x86-64.so.2` is a *stub* ELF ("stub-ld")** that
   refuses to run generic dynamically-linked binaries. Any non-Nix
   binary (NVIDIA tools, extracted debs, downloaded executables) dies
   at load. **Fix: bind-mount the real glibc loader** onto it:
   `mount --bind <glibc-store-out>/lib/ld-linux-x86-64.so.2
   /lib64/ld-linux-x86-64.so.2`. **Bind mounts do not survive reboot**;
   make it a systemd mount unit in the flake when it matters, and
   re-derive the glibc store path after each reboot (it changes across
   pins).
2. **`/etc/ld.so.cache` is a symlink into the read-only store**, so
   `ldconfig` fails ("Can't create temporary cache file … Read-only file
   system"). Fix: `touch /var/tmp/ld.so.cache && mount --bind
   /var/tmp/ld.so.cache <glibc-store-out>/etc/ld.so.cache`, *then*
   `ldconfig`. Also reboot-fragile: unit-ize it.
3. **rpath vs RUNPATH**: `patchelf --add-rpath` writes **DT_RUNPATH**
   (new style): that is *not* consulted when a loaded *library* does
   `dlopen` (e.g. libcudart dlopen'ing `libcuda.so.1`), so the lookup
   fails. Use `--force-rpath` (old **DT_RPATH**), which *is* consulted
   for process-wide dlopen. And `--set-rpath` **overwrites** the whole
   rpath: CMake already put the build tree's `$ORIGIN` and the gcc
   package's lib dir in there, so a careless overwrite yields
   "cannot open shared object file: libstdc++.so.6" or "lib…-impl.so".
   If you must rewrite, compose the full path yourself:
   `$ORIGIN:<cuda lib64>:<driver lib dir>:<gcc-13.2-lib dir>`; or
   better, don't patch at all: the CMake rpath from a normal build is
   usually already complete (only add `LD_LIBRARY_PATH` with the
   driver's lib dir as belt-and-braces).

## CUDA toolkits

4. **The NVIDIA `.run` installer cannot run on NixOS** (missing
   `/bin/rm` etc. *and* stub-ld). Assemble the toolkit from NVIDIA's
   **`.deb` packages**: download (nvcc, cudart, nvrtc, nvtx, libcublas,
   crt, nvvm, **cccl**), `dpkg -x` each into a prefix,
   `patchelf --set-interpreter` (+ rpath) on the binaries. Don't forget
   the **`cuda-cccl-*`** deb: its `nv/target` headers are needed or
   the flash-attention template instances fail to compile.
5. **CUDA 13 dropped Pascal**: nvcc 13.1 fatals with
   `Unsupported gpu architecture 'compute_61'`. **CUDA 12.9 is the last
   Pascal-capable toolkit** (12.x covers sm_50–sm_90). A 12.x runtime
   works on a 13.x-generation driver (580.x): the driver speaks a
   superset. (Driver 580 + 12.9 runtime verified on GTX 1060 / sm_61.)
   **The deb-assembled toolkit has no `lib64/stubs/` directory** (the
   deb layout puts the driver-API stub elsewhere): code that calls
   the CUDA *driver* API directly (`cuDeviceGet` etc.; e.g.
   GenerelSchwerz's moe-cache fork) fails at link with `undefined
   reference to cuDevice*`. Fix: `mkdir -p lib64/stubs && ln -s
   <nvidia-store>/lib/libcuda.so.1 lib64/stubs/libcuda.so` (linking
   against the real driver lib is fine) and add
   `-L<toolkit>/lib64/stubs -lcuda` to the linker flags.
6. **glibc 2.42 (nixpkgs 26.05) added `noexcept` annotations to math
   headers that collide with CUDA's own headers**: fatal errors deep
   in CMake compiler probes. Sidestep with an era-consistent toolchain:
   **nixpkgs 24.05** (gcc 13.2 + glibc 2.38 + CMake 3.29) is the era
   CUDA was validated against; the resulting binaries run fine on a
   26.05/unstable system. Also: 26.05's `gcc13.cc` is *unwrapped*
   (breaks CMake's link tests: Scrt1.o), 24.05's stdenv cc is wrapped.
7. **CMake 4.x CUDA detection is fragile** with a hand-assembled
   toolkit (empty-arg probes, "identification unknown"); CMake 3.29
   (24.05) identifies nvcc cleanly.

## Shell / orchestration quirks (cost debugging sessions)

8. **`pkill -f "[x]pattern"` self-kill**: if the *same* shell script
   mentions the plain name anywhere else (e.g. a `nohup …/llama-server`
   launch line), the ssh bash's own command line matches and pkill
   kills the script's own shell mid-run. Keep pkill and the launch in
   *separate* ssh calls, or pkill by pidfile.
9. **Heredocs over ssh**: multi-line content with quotes/`$` through
   `ssh "…"` mangles. Pipe a local file instead:
   `ssh host "cat > /tmp/x" < /tmp/x`: always this for scripts.
   Hardened rules (each of these cost a debugging session):
   - **Never nest two heredocs with the same delimiter**: the first
     `EOX` line closes the outer one and the rest of the script is
     garbage. Inner/outer need distinct delimiters.
   - When the *whole* ssh argument sits inside a local `bash -c '…'`
     (single-quoted), a *quoted* remote heredoc `<< "EOX"` means NO
     expansion on either side: `\$VAR` in the script stays a literal
     `\$VAR` at runtime. Either write the script **without variables at
     all** (one explicit command per case: the only method that
     survived every retry this session) or use an unquoted delimiter and
     escape `\$` deliberately.
   - Avoid `(` `)` in `echo` lines inside double-quoted remote commands
     run from a local `bash -c` wrapper: the nested quoting breaks the
     local shell before ssh even runs ("syntax error near unexpected
     token `('" from *your own* machine).
10. **`timeout 300 VAR=x cmd` fails** (`timeout` doesn't take env
    assignments): use `env VAR=x timeout 300 cmd`.

## Solved: the llama-server "first cudaMalloc / CUDA error" anomaly (2026-09-27)

11. **The overnight crash was `cublasCreate_v2` returning 3
    (EXECUTION_FAILED)**: found with `ltrace` (the *only* non-zero
    return in 2168 traced calls; GDB backtrace: `ggml_cuda_mul_mat_cublas`;
    zero Xid/dmesg; GPU showing 11 MiB at the crash). It reproduced in
    **both** the thecodacus fork *and* stock upstream main (fork
    exonerated) and only in the llama process with a **specific config:
    `-ngl 99` + default load mode (mmap)**. Standalone probes (fresh / 
    post-alloc / post-stream / post-graph / spin-flag / workspace-config
    / F16 / F32-cublas) all passed; the driver (580.178.04) was innocent.
    **The fix is Codacus's flag combination (2026 spelling):
    `--load-mode mlock -ngl 999 -ncmoe 36 -t 4`**: on this machine
    (i5-7300HQ 4C/4T no-HT, GTX 1060 6 GB Max-Q, 24 GB RAM, IQ4_XS 17 GB):
    pp512 186 t/s, pp2048 182, pp8192 167, tg ~13 t/s (was ~6 CPU-only).
    `--load-mode mlock` requires `ulimit -l unlimited`; note `-ncmoe 0`
    (all experts on GPU) is **not loadable on a 24 GB box** (17 GB
    model + 4.5 GB VRAM transient): 36 is the static floor here.
    **2026 llama.cpp flag renames** (both upstream and forks): bench
    dropped `-c` entirely (context is server-side only); `-mmp`/
    `--no-mmap`/`--mlock` → `--load-mode <auto|none|mmap|mlock|mmap+mlock|dio>`;
    bench defaults batch 2048 / ubatch 512.
    **MoE placement, 128K KV, the expert-cache fork, and MTP** are in
    `references/llama-moe-placement.md`.
12. **The GC trap for hand-built binaries (bit 2026-09-27):**
    `nixos-rebuild` runs `nix-collect-garbage` after each switch, so any
    store path referenced *only* by rpath/interp (not by the system
    closure) gets **deleted out from under you**: the 24.05-era glibc
    interpreter + gcc lib dir vanished mid-session (units started dying
    127/missing-lib *minutes after* the same binaries worked). Durable
    pattern: re-point the interpreter at the **running system's glibc**
    (the 24.05 builds run fine on 2.42: verified), copy the gcc runtime
    libs to a stable dir (`/var/lib/.../deps` + tmpfiles rule), and give
    every ELF `RPATH = cuda:driver:deps:$ORIGIN` (`patchelf
    --force-rpath --set-rpath`; note `$ORIGIN` must reach the ELF
    literally). Also: the 2026 llama.cpp "binaries" are **~20 KB
    launcher stubs** next to their `lib*-impl` / `libggml-*` shared
    libs: install the *whole bin set*, not the stub.

## 2026-11 refinements (CUDA driver, dlopen, GC, python, CMake)

13. **dlopen and RUNPATH (refines item 3):** glibc resolves a `dlopen()`
    with the *calling object's* RPATH/RUNPATH; the main executable's
    RUNPATH is not necessarily consulted when a *loaded library* dlopens
    (dlopen(3)). "Patch the executable with `--force-rpath`" is therefore a
    one-trick fix. The robust arrangement for *driver* libraries is the
    NixOS-managed **`/run/opengl-driver/lib`** (the live nvidia userspace
    driver) exposed via the service's `LD_LIBRARY_PATH` (or
    `autoAddCudaCompatRunpath` where applicable): that path is kept alive by
    the *system configuration*, so it survives rebuilds and GC, unlike a
    store path you bind-mounted yourself.
14. **Link against the driver *stub*, not the installed driver lib.**
    The toolkit's `stubs/libcuda.so` (in nixpkgs: the driver-dev packaging;
    their `cuda_cudart` packaging includes the driver-link handling and stub
    cleanup) satisfies `-lcuda` / driver-API symbols at link time; at
    runtime the real `libcuda.so.1` out of `/run/opengl-driver/lib` loads.
    Linking straight to the installed driver's lib (item 5's workaround for
    the hand-assembled toolkit) couples the binary to one driver store path; do it only when no stub exists, and make sure the stub's directory
    never lands in the runtime search path (loading a stub at runtime is a
    silent no-GPU failure).
15. **GC and store paths in RPATH (refines item 12):** Nix *does* extract
    store-path references from output contents (including RPATH strings), so
    an RPATH into the store is tracked, *provided the referenced path is
    inside the derivation's closure*. The omen-15 breakage was a
    *different pin's* glibc/gcc path the new system closure no longer
    carried. Rule: keep every runtime lib inside the active system's closure
    (declarative units referencing store outputs); never hand-bind or patch
    to paths outside the closure.
16. **Python serving layers:** `python3.withPackages` (present on
    26.11/c8ccf87, measured) is the robust pattern for a store-built
    service that wraps a C/C++ engine: one derivation, no venv, no
    patchelf, GC-safe. It follows *nixpkgs'* dependency versions, not the
    project's `requirements.txt` wheel pins; usually desirable, but
    document the difference or a runtime regression gets misfiled as an
    engine regression. The venv+patchelf dance (omen-15 `strata.nix`) is
    only for engines that are out-of-store builds whose interpreter the
    stub-ld would otherwise refuse.
17. **CMake-4-era CUDA projects:** if the project uses
    `enable_language(CUDA)` + `find_package(CUDAToolkit REQUIRED)` (the
    modern path), nixpkgs 26.11's CMake 4.4.x is fine; item 7's fragility
    was specific to *hand-assembled* toolkits with empty-arg probes. Give
    CMake the merged toolkit (`CUDAToolkit_ROOT` / `CMAKE_PREFIX_PATH`
    pointing at the `cudatoolkit` output) plus `-DCMAKE_CUDA_COMPILER=<nvcc>`.
    A project with **two independent CMake trees** (an engine plus a
    secondary target, e.g. a vision encoder) wants two clean build
    directories with explicit configure/build phases, not the single-tree
    cmake derivation hook. A `requirements.txt` that pins `cmake`/`ninja`
    *wheels* describes the project's installer environment, not its build
    requirements: use nix's cmake/ninja. A pinned third-party source (a
    vendored llama.cpp commit and friends) is a flake input passed as the
    source-dir argument.
18. **Native vs portable CPU code:** engines that compile their CPU side
    *natively for the build machine* ("build it on the PC it runs on") are
    faithful when the derivation builds on the target box itself, and are
    **not reproducible on other builders** (different CPU features). For a
    dedicated node, choose deliberately (native on the box, or an explicit
    portable baseline) and write the choice into the derivation, instead of
    letting whichever builder nix picks decide.
19. **The automatic cmake hook runs before your buildPhase.** stdenv enables
    its cmake configure/build hooks (triggered by cmake in nativeBuildInputs
    plus project detection and the CUDA setup hooks); its configurePhase
    runs its own `cmake` with only the collected default flags, and dies
    on any project whose CMakeLists needs flags the hook doesn't pass
    (e.g. a FetchContent fallback the sandbox forbids); before your custom
    buildPhase ever executes. When you drive CMake yourself in buildPhase,
    disable the hooks (`dontUseCmakeConfigure = true; dontUseCmakeBuild =
    true;`). Symptom in the log: "Running phase: configurePhase" + "cmake
    flags: …" with none of your -D values, on a build whose buildPhase you
    thought owned the cmake call.
20. **CMake `set(... CACHE <type>)` clobbers UNINITIALIZED entries.**
    `set(FOO "" CACHE PATH "doc")` is a no-op for a *typed* cache variable,
    but it **overwrites an UNINITIALIZED one, which is exactly what a
    `-DFOO=value` command-line flag creates**; so a project with such a
    line silently eats the -D value and falls into its default branch. Fix
    by pre-seeding the build dir's `CMakeCache.txt` with a typed line
    (`printf 'FOO:PATH=<value>\n' > build/CMakeCache.txt`) before the
    configure; typed entries survive the project's set(). Verified both
    ways (repro: -D wins in a bare project only because no such set() is
    present; the real breakage appears the moment the project has the
    line).
21. **Source-pin hygiene for fetchTarball:** the `sha256` field must be the
    value *nix's fetcher* computes; take it from the mismatch report's
    "got:" line, not from `sha256sum` plus a manual base64/hex/
    `nix hash convert` chain (that chain produces a different-looking
    value for the same bytes on current nix; `nix hash convert` takes a
    hash, not a file, and `--to nix32` is 32 chars for sha1, 52 for
    sha256). GitHub **regenerates archive tarballs**: the same commit's
    tarball changed NAR between sessions (different file mtimes), so a pin
    can break without any code change: re-derive the hash from the
    fresh "got:" line and note the drift in the commit message. Verify
    stability with two consecutive `nix flake prefetch <url>` runs (same
    store path both times = stable for now).
