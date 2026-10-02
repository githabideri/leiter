---
name: nix
description: >-
  Provision and operate NixOS machines. The proven 2-phase flow (bare
  metal → headless fleet node: dd'd ISO + hidden payload on one stick,
  one-time Tailscale authkey, minimal keyboard input, machine-local flake
  with real secrets), the layout invariants (initial vs full host,
  host-dir-first import, atomic rebuilds), and building/running non-Nix
  software on NixOS (CUDA from debs, the stub-ld / ld.so.cache / rpath
  traps, Pascal legacy_580, the 26.05 module-system crash, branch pins
  that move on their own). Use for "install NixOS", "provision a node",
  "nixos-anywhere", "why did my nixos eval crash", "build CUDA or
  llama.cpp on NixOS", "why does this binary fail on NixOS". Details in
  references/. Not for: non-NixOS nodes.
---

# Nix Skill

Provisioning and operating NixOS, distilled from a fleet of headless
nodes (mini PCs, old laptops) running inference.

## When to read which reference

| Task | Read |
|------|------|
| Preparing the install stick (hidden payload, iwd network file, PSK extraction, human-input budget) | `references/install-stick.md` |
| Which nixpkgs/nixOS pin to use; module-system / option-name quirks per generation (the 26.05 nvidia crash, sops stub, tmpfiles format, 26.11 unit changes, the /bin bash trap) | `references/nixpkgs-pins.md` |
| Building/running non-Nix software (CUDA, llama.cpp, any generic binary), or any "why does X fail on NixOS" (stub-ld, ld.so.cache, rpath) | `references/building.md` |
| The provisioning flow itself | this file |

The dated references are snapshots — re-verify a specific claim before
relying on it for a *new* pin; pins move (see the last one in the
reference itself).

## The two-phase flow

```
control station (Nix box)              target machine
nix build .#<host>-initial             dd'd ISO boots (F9/ESC)
agent SSHs in (payload brings sshd     human types 1-2 short lines max
+ keys up; or nixos-anywhere)          (wired: zero) -> agent over LAN
tailscale up --authkey=one-time        -> agent: hwclock, tailscale,
                                         nixos-rebuild switch (full)
```

Layout invariants of the settings repo (a flake with a host directory per
machine):

- **`<host>-initial`** = hardware configuration + first-contact only.
  Pure nixos.org-cache: no kernel-module builds, no GPU stack — it
  cannot plausibly fail. First-contact = iwd (the network file
  *inlined into the activation script*, never a `deps:` —
  strings-with-deps with store-path strings crashes), timesyncd (dead
  RTCs), sshd + agent keys, tailscale, firewall, lidSwitch=ignore.
- **`<host>` (full)** = the normal host module — **the host directory is
  imported FIRST** (`[ ./hosts/<name> ] ++ commonModules ++ modules`) so
  machine facts override shared modules. Reversed order once let a shared
  `hardware.nvidia.open = true` silently clobber a Pascal host's
  `open = false` and produced an opaque module-system crash.
- **Machine-local working copy** at `/root/nixos-flake` (writable — `/etc`
  is read-only) with *real* secrets injected; the repo keeps `REPLACE-*`
  placeholders. Rebuild:
  `nixos-rebuild switch --flake /root/nixos-flake#<host>` (atomic — a
  broken build never bricks the node).
- **Pascal/Maxwell hosts**: `hardware.nvidia = { open = false;
  branch = "legacy_580"; modesetting.enable = true; nvidiaPersistenced =
  true; }` — use `branch`, not the drv-form `package =` attr. Shared GPU
  modules deliberately do **not** set `open` (it's a host fact). Low TGP
  caps for thin-laptop cards: an oneshot after persistenced
  (`nvidia-smi -pm 1; nvidia-smi -pl <watts> || true`; the unit needs the
  nvidia package on its `path`).
- **Pin policy**: pin a stable nixOS branch in the repo; a machine-local
  copy may run a newer (unstable) rev while a known crash is unfixed.
  Re-test each point release; flip back when fixed.

## After first boot (agent, unattended)

1. Find the node (LAN ARP by MAC, or `tailscale status` after the authkey).
2. `hwclock --systohc` — persist the NTP-corrected clock (dead RTCs are
   common in old laptops; see the CR2032 trap below).
3. `tailscale up --authkey=<one-time> --hostname=<host>` (self-consuming
   key; no revocation needed).
4. `nixos-rebuild switch --flake /root/nixos-flake#<host>` — the full
   config; 10-30+ min (kernel module builds happen here).
5. Verify: `nvidia-smi` (if GPU), `smartctl -a` on any pre-existing NVMe
   (old drives!), a metrics exporter, tailscale on the tailnet.
6. **The host config ships a dev/debug kit** (git, jq, patchelf, gdb,
   strace, ltrace, less, unzip). Headless nodes must be debuggable over
   plain SSH; if a node is missing one of these, it ran an older config —
   rebuild.

**CR2032/CMOS trap**: a dead coin cell means BIOS settings (including
Secure Boot = Disabled) only survive while AC is connected — total power
loss re-enables Secure Boot and the unsigned bootloader dies. Never
unplug AC on such a machine until the cell is replaced. Rebooting is
fine. (Some chassis ship with no cell at all — for those the AC
constraint is permanent, not interim.)

## Related

- The companion `component-graph` practice tracks which hosts exist;
  this skill makes new ones.
