---
name: keymaster
description: >-
  Unlock encrypted boot pools remotely: a small always-on machine holds a
  LUKS file vault with per-host boot passphrases + a dedicated unlock key,
  and unlocks headless servers from the initramfs/dropbear stage when they
  can't reach the running OS. The unlock CLI (per-host registry, unlock one
  or all, vault open/close, image backup, audit log, login banner),
  onboarding a new encrypted host (dropbear-initramfs + DHCP reservation +
  initramfs rebuilds), and the console-typing fallback when the keymaster is
  itself dead. Use when: "host is in initramfs / won't boot / stuck at the
  unlock prompt", "rpool", "LUKS passphrase", "key vault", "keymaster",
  "back up the key vault", a power outage involving encrypted hosts.
  Machine names: resolved via the estate's machine index (body). A human
  opens the vault; secrets never print; unlocking is deliberate. Not for:
  KVM (the kvm skill), monitoring, DNS.
---

# Keymaster: LUKS vault & remote boot-pool unlock

## Prerequisites

- LUKS-encrypted boot pools on at least one headless host (per-disk or
  per-pool LUKS under ZFS/LVM, or plain ext4), and the ability to rebuild
  its initramfs (`update-initramfs` or equivalent).
- A small always-on machine with a LAN/Tailscale address (a small board is
  enough; it does almost nothing), a shell, and room for a LUKS **file**
  (a sparse image of a few hundred MB).
- A machine index (a generated name → site → role projection; the
  component-graph skill builds one) so this skill can say "the keymaster"
  without naming your boxes, and a per-machine doc habit for the values
  this skill deliberately doesn't carry (IPs, reservations, fingerprints,
  backup destinations).
- You are willing to type one passphrase by hand, once per incident.
  That is the design; see Invariants.

## What a keymaster is

The estate's trust boundary for encrypted boot pools. Its secrets live in a
LUKS **file** (the vault), not the disk: the box's OS stays unencrypted so
it boots unattended and stays reachable, but its contents stay locked until
a human explicitly opens them. It is the only place holding the per-host
passphrases and a dedicated unlock SSH key that the targets' initramfs
dropbear accepts; so stealing the box's SD card or the target's boot media
yields neither, and the two halves only work together in your hands.

**Estate resolution (this skill names no machine):** the keymaster is the
machine whose role in your machine index says "keymaster"; the targets are
whatever is registered in the keymaster's own per-host registry (one small
config file each: normal IP, initramfs IP, paths *inside the vault*,
prompt count); values live in the keymaster's own doc. Your CLI gets
whatever name you like; below it's "the vault CLI".

## Invariants (do not violate, do not "improve" without your owner)

1. **The vault opens only by a human typing the passphrase.** No cron, no
   auto-unlock, no auto-*target*-unlock. The alternative (a path unit that
   unlocks targets when the vault appears) fires exactly when the vault
   was opened for *something else*: rotation, adding a host. If a task
   seems to need automation, stop and ask.
2. **Secrets never print**, not in output, logs, argv, or machine-readable
   modes. The registry holds *paths into the vault*, never values; the CLI
   feeds passphrase files straight into the pty/SSH session.
3. **Unlock is deliberate:** open the vault, *then* unlock a named host (or
   `--all` as a conscious act). A bare `unlock` with no target refuses by
   design.
4. **The vault image backup is safe while locked**: the image *is* LUKS, so
   a raw copy is equally protected; the passphrase must never be placed on
   any backup destination.

## The unlock chain

```
host power-fails or reboots
  → initramfs, DHCP (a static reservation, see onboarding)
  → dropbear up, publickey-only, the dedicated unlock key
  → on the keymaster:  vault open && vault CLI unlock <host>
      (a pty driver: SSH to the initramfs, feed the passphrase at each
       "Please unlock disk …:" prompt, one per LUKS device)
  → host boots; its normal IP answers again
```

**"A host won't boot" / after a power outage:**
1. `status` on the keymaster: per host running / in-initramfs / offline,
   with the exact next command. (A login banner in the human's shell shows
   the same; the CLI is what makes the human not have to remember anything.)
2. If `in-initramfs`: the owner runs vault open + unlock. The passphrase
   prompt is interactive; an agent cannot and must not type it. The driver
   reports each prompt answered and when the normal IP answers again.
3. If the **keymaster itself is dead**: the target's KVM console + a
   secret-typing helper (kvm skill), passphrase piped from a vault copy
   (the daily image backup is that copy).
4. Afterwards: close the vault, check the audit log (one line per attempt,
   failures included), close the loop in the host's doc.

## Onboarding a new encrypted host

1. **Target:** LUKS (per-disk or per-pool) + `dropbear-initramfs` with the
   dedicated pubkey in its authorized-keys file, and mind the path the
   *hook* actually reads (the staging directory that looks right is
   usually the wrong one; read the hook). Initramfs IP via a **DHCP
   reservation**, not a static one (see gotcha). Rebuild the initramfs on
   **every** boot disk.
2. **Keymaster:** passphrase file in the (open) vault under the host's
   directory; one registry entry; `add-host` writes it.
3. **Test:** a deliberate power cycle in a maintenance window with the
   owner present; never a surprise reboot of a production host.

## Vault maintenance & the multi-instance pattern

One instance is a single point of failure for the *vault* (the targets'
passphrases live only there). The pattern that scales: keep the vault
contents **small enough to re-create** (a handful of short files), back up
the image daily to a second site while locked, and add a **second live
instance** for real redundancy (a laptop held by the owner is the natural
second node; an offsite site the third). The cost: any passphrase rotation
becomes a two-writer procedure, i.e. update all instances in one sitting.
A vault-passphrase loss is the only unrecoverable state; treat the
passphrase as something the owner holds in their own password manager,
never on any box.

Monitoring is a separate onboarding task (the CLI emits a Prometheus
textfile: vault locked/unlocked, per-host state, last-unlock timestamp) so
a host *sitting* in initramfs becomes an alert instead of a surprise.

## Gotchas (verified negative knowledge; do not re-explore)

- **Modern PVE kernels ship multi-segment initramfs archives** (microcode
  stub + the real initramfs + a third segment). `cpio -t` lists only the
  first member, so a naive "no dropbear in the initramfs" check is a
  **false negative**. Verify with `grep -ac` for dropbear/zfs/lvm strings
  on the raw file.
- **LUKS header magic**: LUKS2's version byte is at **offset 7**
  (`4c 55 4b 53 ba be 00 02 …`; LUKS1: `01` at offset 5), not where the
  "first eight bytes" one-liners expect. `cryptsetup isLuks` is the
  authority; magic-byte sniffing is the footgun.
- **Static-IP-in-initramfs is a dead end on renamed-NIC hosts**: busybox
  `ipconfig -d` without a device defaults to `eth0`, which no longer exists
  by the time networking runs. DHCP works fine; use a reservation.
- **Newer Tailscale changed the `serve` syntax** (`--bg 443:8504` →
  `--bg 8504` = URL root); a silent upgrade once made a "404 for a week"
  mystery out of a one-line config. Relevant whenever the keymaster ever
  serves anything.
- **KVM consoles need their video output connected before the target
  powers on**, or the streamer has no stream at all (kvm skill).
- Small boards typically lack `cpio`/`xxd`; `od` is the universal
  substitute.
