# Nixpkgs / nixOS pins: per-generation quirks

Which pin to use and the module-system / option quirks that come with it.
**Dated knowledge: last verified 2026-11-17 against the bd775i's nixpkgs
c8ccf87 (2026-09-19, the rev the nixos-unstable input actually follows),
2026-09-27 against nixos-unstable e158d9ed ("26.11.20260926") and nixpkgs
26.05 (c508844). Re-verify before relying on a claim for a *new* pin; pins
move.** Full narrative: see the provisioning report of the session that ran
it.

## Pin policy (the settings repo)

- The repo pins **nixos-26.05**. the node runs a **machine-local
  nixos-unstable (e94cb152)** copy at `/root/nixos-flake` because of the
  crash below. Re-test each 26.05 point release; flip the pin back when
  the crash is fixed upstream (candidate nixpkgs bug report).

## Quirks by generation

1. **nvidia `branch = "legacy_580"` + nixpkgs 26.05 (c508844) =
   module-system internal crash**: opaque `head` in `zipAttrsWith`
   (attrsets.nix:1717 / `seq` at modules.nix:402), *empty* error message,
   triggered the moment the nvidia module joins a full host tree; even a
   minimal host with only `hardware.nvidia = { open = false;
   branch = "legacy_580"; }`. Upstream nixpkgs bug, **fixed on
   nixos-unstable e94cb152 (2026-09-25)**; full tree evals and builds
   clean. (Distinct from the March #503740 variant, which was a clean
   attribute-missing and was fixed in April.)
2. **sops-nix March 2026 pin = stub `nixosModules.default` on 26.05**
   (the `sops` option is absent). Keep the input; comment out the module
   import until `nix flake update sops-nix`; `modules/secrets.nix` stays
   inert until then.
3. **`systemd.tmpfiles.settings` is the structured format now**:
   `settings."<name>"."<path>".d = { user; group; mode; }`: the old
   `"<path>" = [ "d" ... ]` list form is gone.
4. **`openInFirewall` (26.05) → `openFirewall` (unstable)**: check the
   name when crossing pins. A pin-agnostic module: discriminate on
   `pkgs.lib.versions.nixpkgs` (version string) + `lib.optionalAttrs`
   (emits *no attribute* for the absent name: a plain `= false` is
   itself a hard error); `options.<path>` suboption introspection is NOT
   portable ("attribute 'node' missing" on the newer module system).
   See `the settings repo's telemetry module` (c6177ac) as the working
   example. Related Nix-parser fact: the `a.?b` / `a.?"b"` *suffix*
   optional-access syntax does not parse in Nix 2.34: use the *function
   form* `a ? b` inside `if/then/else`.
5. **NVIDIA unfree gate**: ad-hoc `nix build --expr "(import
   <nixpkgs-src> { allowUnfree = true; }) …"` is *not* enough: the gate
   reads nixpkgs config. Use `NIXPKGS_ALLOW_UNFREE=1` (env) or
   `nixpkgs.config.allowUnfree = true` in the nixos config.
6. **`builtins.getFlake` on nix 2.34**: takes a **string** (not a path)
   and returns the outputs directly (no `.flake` wrapper).
7. **26.05 renames vs older muscle memory**: `console.keyMap` (not
   `console.keys`); `pkgs."linux-firmware"` (was `linuxFirmware`);
   `zramSwap.memoryPercent` (no fixed `size`);
   `services.logind.settings.Login.lidSwitch` (friendly name).
8. **Branch-based pins move silently between sessions** (2026-09-27:
   the node's `nixos-unstable` branch pin advanced e94cb152 → e158d9ed
   overnight; the system name revealed it: `26.11.20260926.e158d9e`).
   If a config must be reproducible, pin by **rev**, not branch, or at
   least record the resolved rev (system name / `nix flake metadata`) in
   the report when you build.

9. **26.11 (post-26.05 unstable) systemd units behave differently** (hit
   2026-09-27 on the node): units get **no store-PATH injection** and
   **`/usr/bin` is not the standard symlink** → ExecStart must be a
   **flake-interpolated absolute path** (e.g. `${pkgs.python3}/bin/python3`)
   with `path = [ … ]` for helper binaries (nvidia-smi lives in the
   driver package, not the system PATH); **multi-line triple-quoted
   ExecStart fails at eval** ("attempt to call … string: ''" inside
   `zipAttrsWith`: one line only; fine while no argument carries a
   space); **`networking.firewall.allowedTCPPortsInterfaces` is gone**
   (nftables redesign): use plain `allowedTCPPorts`. The *old* unit
   style (oneshot `script =`, `path =`, `serviceConfig` basics) still
   works on the same pin, so discriminate per-quirk, not per-generation.

10. **The `/bin` symlink farm can lose `bash` between 26.11 switches**
    (2026-09-27/28, on a headless laptop node): after a switch-to-configuration, `/bin` on
    this pin contained **only `sh`**: every script with a
    `#!/bin/bash` shebang died with ENOENT ("No such file or directory",
    no log content). bash lives at `/run/current-system/sw/bin/bash`. Use
    that absolute shebang (or a `#!/usr/bin/env -S` variant) for scripts
    that survive switches, and check `/bin` after a switch before blaming
    your script.

11. **Long jobs must not ride the ssh session** (2026-09-28, on a headless laptop node):
    `cmd && nohup X &` over ssh backgrounds the *entire chain*; when the
    session closes, systemd-logind kills the session's cgroup: taking the
    chain down before nohup ever detaches (symptom: "bash: line 1:
    85236: Terminated …"). Use a **systemd transient unit**:
    `systemd-run -u name --collect /run/current-system/sw/bin/sh -c "…"),
    session-independent by construction.

12. **`systemd-run` units get a minimal PATH** (no `seq`, no `curl`):
    `export PATH=/run/current-system/sw/bin:/run/current-system/bin:/bin:/run/current-system/sw/sbin`
    at the top of every campaign script (systemctl is in the sbin dir).

13. **Store gcc drivers need their wrapper** (2026-09-28, on a headless laptop node):
    running a bare `/nix/store/…-gcc-*/bin/gcc` fails with
    "cannot execute 'as'" (the driver can't find the sibling binutils).
    Use the **gcc-wrapper** path (`…-gcc-wrapper-*/bin/cc`), or add the
    matching binutils store dir to PATH. (glibc-2.42-era gcc is fine for
    scratch C; production binaries keep the 24.05 toolchain.)

## Which nixpkgs does your flake actually use (forensics, 2026-11)

"nixpkgs has no X" is only true for the nixpkgs you actually asked.
2026-11-17 (bd775i session): `nixpkgs#cuda` → "attribute missing" was checked
against the *registry's* HEAD, while the system was built from a different
rev, and the pinned rev **did** carry the CUDA 13.0 packaging
(`pkgs.cudaPackages_13_0`, verified by forcing the attributes to store
paths). The recipe to never chase a false negative again:

1. **`nixpkgs#` (nix 2.34+) is the flake registry's HEAD, not your pin.**
   Always evaluate the rev in your project's flake.lock.
2. **A flake.lock can carry several `nixpkgs` nodes** (the repo's own
   input; `nixpkgs_2`-style disambiguation; inputs of inputs). Which one
   feeds the *system* is decided by input-following: in the nixos-settings
   flake the `nixos-unstable` input **follows** `nixos-anywhere/nixpkgs`
   (c8ccf87); that is the pkgs the `nixos-rebuild --flake` system is built
   from, while the repo's own `nixpkgs` input (e158d9e) and the
   `nixos-stable` input (cf9d2fb3) serve other things. `nix flake
   metadata .` prints the follow graph; trust it over node names.
3. **nix3 short hashes are not fetchurl hashes.** Lock-file narHashes in
   the nix3 era are *short* base32 (43 chars for sha256, trailing `=`);
   `builtins.fetchurl` (nix2 style) wants the classic 52-char form and
   rejects the short one ("wrong length for hash algorithm"). Don't
   transcribe by hand; fetch via the flake fetcher, which validates the
   short form:
   `nix path-info 'github:NixOS/nixpkgs/<rev>?narHash=sha256-<short>='`
   (one-time git clone into the flake cache, minutes).
4. **Flake URL outputs:** `#legacyPackages.x86_64-linux.<attr>` works with
   `nix eval` (`--raw` for store paths, `--apply` for filtering). Bare
   top-level names like `#cudaPackages_13_0` are *not* flake outputs; and
   `nix path-info` only accepts outputs that are paths or derivations (the
   pkgs *set* is rejected with "found a set"). To find a source's store
   path: match the lock's narHash against `nix path-info --json --all`
   (field `narHash` per path); expect the source to have been GC'd
   (`nixos-rebuild` runs `nix-collect-garbage` after every switch; a
   source that only fed evaluation is not necessarily a GC root).
5. **Env vars need `--impure` in flake mode** (e.g.
   `NIXPKGS_ALLOW_UNFREE=1 nix eval --impure …`); and forcing an
   *unfree-licensed* package to a store path dies in the
   `customisation.nix` assert **with the package name in the error**, which is itself proof the attribute exists (naive `? a` / `or {}`
   probes can report "missing" for a thunk that died on the unfree gate).
