# Building & running non-Nix software on NixOS

How to compile and run generic (non-Nix) software on a NixOS box:
toolchains, CUDA, linker/loader traps. **Dated knowledge: last verified
2026-09-27 (CUDA 12.9 + driver 580.178.04 on the nixos-unstable pin;
llama.cpp upstream main 86a24a1 + GenerelSchwerz moe-cache branch).
Re-verify for a new pin.** Full narrative: see the provisioning report of the session that ran it.

TOC: (1-2) loader/linker traps (stub-ld, ld.so.cache, rpath vs RUNPATH) ·
(4-7) CUDA toolkits (deb assembly, Pascal ceiling, stubs/libcuda, glibc-2.42
vs CUDA headers, CMake 4.x) · (8-10) shell/orchestration (pkill self-kill,
heredocs over ssh, timeout+env) · (11) solved llama-server cublasCreate
anomaly + 2026 flag renames.

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
