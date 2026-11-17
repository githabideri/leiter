# UEFI firmware that owns its boot entries: fixing "rebuild boot" that does not boot

Some consumer firmwares (AMI on compact boards is the observed case) keep the
UEFI boot entries **in their own store**: on every POST they rebuild the NVRAM
boot list from that store and discard anything written by the OS
(`efibootmgr --create` entries appear once, then vanish; the firmware even
keeps its own `OldBootOrder`/`DefaultBootOrder` variables alongside the
standard ones, which is a tell that it is managing the list itself).

Symptom in NixOS: `nixos-rebuild boot` finishes successfully ("Done. The new
configuration is ..."), but the next reboot boots the **old** generation —
`/run/booted-system` keeps pointing at the old store path, no matter what
`/boot/loader/` says.

## Diagnose without touching NVRAM

1. **Do not read the firmware's vendor efivars from userspace.** On the
   observed firmware, a userspace process that opens one of its vendor
   variables (the boot variables live under a vendor GUID, e.g.
   `8be4df61-93ca-11d2-aa0d-00e098032b8c`, not the standard
   `8a845d20-...` GUID) **hangs in the kernel and never returns**; the box
   stays "up" (network answers) but the reading session is gone. Standard-GUID
   variables are fine; vendor ones are not. `loaderctl`/`efibootmgr` on such a
   box is a trap for the same reason.
2. The reliable oracle is **what actually booted**: after a reboot,
   `readlink /run/booted-system` tells you which generation the firmware chose.
3. Map what the firmware can reach: the ESP (`/boot`) holds the raw boot
   files. NixOS/systemd-boot layout: `/EFI/nixos/` with one `*-bzImage.efi`
   per kernel build and one `*-initrd-*.efi` per initrd build (filenames
   derived from the store hash), plus `/loader/entries/nixos-<hash>.conf`
   entries and `/loader/loader.conf` for the systemd-boot fallback path.
   File mtimes tell you which generation each ESP file was written by.
4. Reconcile: if the firmware booted generation X, its (uninspectable) boot
   entry must reference X's files on the ESP. The kernel is
   content-addressed across generations: same nixpkgs pin + same
   `hardware-configuration` = same kernel build = one shared bzImage. The
   **initrd differs per generation** (it embeds the activation and the system
   closure) — that is the lever.

## The fix: content swap at the stable path

The firmware's entry is a path on the ESP. You cannot rewrite the NVRAM
(the firmware reverts it at next POST), but you can **rewrite the file the
path points at**: copy the current generation's initrd over the old
generation's initrd file, keeping the old filename. Back up the old bytes
first (e.g. into `/root/`). The next POST, the firmware boots "the old path"
and gets the new system. No NVRAM is written, so there is nothing for the
firmware to revert; and because the NixOS activation only ever copies fresh
files under fresh names (it does not delete or rewrite old paths on the
ESP), the swap survives further rebuilds.

Practical notes:

- The ESP is vfat: no symlinks (UEFI cannot follow them), so copy bytes into
  the existing filename (`cat new > old`), do not rename.
- As a second boot path (in case the firmware ever falls through to the
  default loader), prune `/loader/entries/` to the current generation's
  `.conf` and keep `loader.conf`'s `default` on it. This alone is **not**
  the fix on such a box — the vendor entry wins — but it keeps the fallback
  path honest. Back up the removed `.conf` files.
- If a future rebuild changes the kernel build (new nixpkgs pin, changed
  hardware config), the ESP gains a new bzImage and the old one stays
  referenced; redo the initrd swap if the boot target regresses.
- Verify after the reboot with `/run/booted-system` and one generation-specific
  fact (e.g. a module or service only the new generation carries).

## What not to do

- `efibootmgr` / `loaderctl` against vendor-GUID variables (kernel hang).
- Repeatedly re-running `nixos-rebuild boot` in a retry loop: every run
  reports success while the NVRAM write is silently discarded, which reads as
  "the fix is flaky" when the firmware is simply ignoring it.
- BIOS-setup-menu surgery over a remote console to re-pick the boot entry:
  it works (that store is the firmware's own), but it is a human task, not an
  agent one; use the file-level swap first and keep the menu as the
  escalation path.
