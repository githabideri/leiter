---
name: nas
description: >
  Operate ZFS NAS boxes: TrueNAS SCALE appliances and bare ZFS hosts
  (a Proxmox box that doubles as the NAS): pools, datasets and quotas;
  NFS shares via the midclt API on appliances (the 24.10+ namespace
  renames included) and via an explicit /etc/exports on bare hosts;
  dataset copies between boxes with zfs send/recv: full streams,
  incremental deltas, resumable pipes, and the encryption interactions
  that silently break them. Covers the gotchas that bite live: hidden
  root_squash (verify with exportfs -s, not /etc/exports), the FreeBSD
  versus OpenZFS CLI differences, readonly root dataset, tiny-NAS-RAM OOM
  kills, degraded single-leg mirrors, and the three-part completion
  check. Use for "create an NFS share", "copy this dataset to the other
  box", "why do NFS writes give EACCES", "my zfs send died", "set a
  quota", "is this pool still redundant", "how fresh is this mirror".
  Not for: where the estate's NAS boxes live (instance knowledge, not
  this skill), non-ZFS NAS systems (Synology/DSM is a different family),
  or the backup software that consumes the shares (that skill owns its
  own side).
---

# NAS (TrueNAS SCALE + ZFS)

You bring:

- **one or more ZFS NAS endpoints**, of either family: a **TrueNAS
  SCALE appliance** (SSH root; `midclt` is its API) or a **bare ZFS
  host** (a Proxmox/Debian box with a local pool and `nfs-kernel-server`;
  `references/host-zfs.md` owns this family);
- for multi-GB copies, **a direct key between the two boxes** so the
  pipe runs on the LAN between them, not through whichever agent
  machine happens to be doing the work;
- a sense of which box has the RAM: the ssh **client** side of a long
  pipe must be the box with the memory (see the pipe rules).

The skill contains: the two families (appliance API, bare host), the
dataset and dataset-copy recipes (with the flags that are load-bearing),
the CLI/encryption reference, and `scripts/zfs-pipe.sh`, the resumable
copy pipe as a script.

## Which task, which file

| Task | Read |
|---|---|
| NFS shares, dataset/quota work, the gotcha list (appliance family) | this file |
| The bare-host family: pool + explicit exports, PVE coexistence, mirror health | `references/host-zfs.md` |
| A dataset copy between boxes: the full recipe, resume, delta converge, the flags and why they are load-bearing | `references/send-recv.md` |
| FreeBSD vs. OpenZFS CLI differences, the encryption × `recv -F` matrix, the OpenZFS 2.3 incremental bug, readonly root, swap on ZFS | `references/cli-and-encryption.md` |
| Run a multi-hour copy right now | `scripts/zfs-pipe.sh` |

## midclt (the appliance's API CLI)

`midclt` (at `/bin/midclt`) is the reliable way to do what the UI does,
on the appliance family. Bare hosts have no midclt; their source of
truth is `/etc/exports` (`references/host-zfs.md`). SCALE 24.10+ **renamed
the namespaces**: pre-24.10 wiki examples using
`share.nfs` and `data.pool` are mostly wrong now.

| Task | 25.04 call |
|---|---|
| list NFS shares | `midclt call sharing.nfs.query` |
| create NFS share | `midclt call sharing.nfs.create '{"comment": "...", "path": "/mnt/<pool>/<ds>", "hosts": ["<client-ip>"], "ro": false}'` |
| update share (map root) | `midclt call sharing.nfs.update <id> '{"maproot_user": "root", "maproot_group": "root"}'` |
| system version | `midclt call system.version` |

Argument style: **real JSON with double quotes, wrapped in single
quotes**. Old-style `{key: value}` works for some calls but
`sharing.nfs.create` returns a bare `EINVAL` with it. Through nested
ssh (two quote layers) escape the inner double quotes. And there is no
`svcs`/`systemrc` on PATH in SCALE (that was Core): `systemctl` and
midclt.

## OS updates (maintenance hops and train jumps)

SCALE updates run through the `update` API service — not apt, not the
`svcs`/`system.update` examples in older wiki articles (those are Core
names; on SCALE 25.04 the service is `update`):

| Task | call |
|---|---|
| current version | `midclt call system.version` |
| what's available (current train) | `midclt call update.check_available` (JSON: version, filename, filesize, checksum) |
| trains + current/selected | `midclt call update.get_trains` |
| switch train (major-jump prerequisite) | `midclt call update.set_train "TrueNAS-SCALE-<Train>"` |
| download the update file | `midclt call update.download` (job; lands in `update.get_update_location`, default `/var/db/system/update/`) |
| install + auto-reboot | `midclt call update.update` (job) |

**Verify the downloaded file's sha256 against `check_available`'s checksum
before `update.update`** — a truncated or stale file from an interrupted
attempt is exactly the failure class that bricks appliances (25.10.0 and
25.10.1 broke UEFI hosts via a `/system`→`/efiboot` partition layout change;
when jumping to a new major, target at least the second point release).

**Major jump = two hops, each its own verifiable state**: update to the
latest maintenance of the current major first, reboot, verify pools/exports/
services, *then* switch train and take the new major. After the major lands,
re-verify anything that talks to the box across a protocol (e.g. NFS
clients — a new OpenZFS version changes server-side behavior, so re-run the
write test that motivated the update, not just "it's up").

If you must hard-kill the appliance mid-update (it wedged): snapshot at the
hypervisor level first, and expect to re-run `update.download` after the
reboot (the job verifies/resumes — idempotent on a complete file). A
hard-kill also leaves the hypervisor with stale guest locks; see the
Proxmox skill's "stale state after a hard kill".

## Datasets and quotas

- Create with the properties that must survive:
  `zfs create -o quota=4T <pool>/<name>` (the dataset inherits the
  pool's compression and recordsize; set recordsize explicitly when the
  workload is large-block, e.g. media or backup chunk stores).
- Quotas and reservations are per dataset; check with
  `zfs list -o name,used,quota,reserved` (never `zfs used`, which does
  not exist on the FreeBSD-side CLI).
- **The root dataset is `readonly=on` by design.** No files in `/`, and
  new mountpoints directly under `/` fail with "Read-only file
  system". Mount under `/data/<x>` instead. (Swap gotcha in the CLI
  reference: swapfiles fail swapon on ZFS; use a zvol.)

## NFS shares: the root_squash trap

TrueNAS adds `root_squash` to every export **by default, silently**:
`/etc/exports` shows `sec=sys,rw,no_subtree_check` and looks fine, but
the effective options are only visible with **`exportfs -s`**. Symptom:
a client writing as root gets EACCES on a 755 root:root directory. Fix:
set `maproot_user=root` and `maproot_group=root` on the share, then
re-check `exportfs -s` for `no_root_squash`. Any client that writes as
root (most backup software, most VMs) needs this. The new-share
recipe is the two midclt calls above, in order: create, then update
with the maproot pair. The bare-host family runs the same rule in
reverse visibility: the exports file is the source of truth there, but
`root_squash` is still the default when omitted, so write it
explicitly in both families.

The zsh gotchas while you are in there (SCALE's default shell):
`exportfs` is the NFS command, `export -r` prints environment
variables; `ps aux | grep nfsd` dies on the glob (`no matches found`)
unless bracketed; `echo ===` tries to execute `==`. Wrap remote work in
`bash -c` when in doubt.

## The dataset copy

The full recipe lives in `references/send-recv.md` and the executable
form in `scripts/zfs-pipe.sh`. The rules that survive contact with
reality, in the order they burn you:

1. **Run the ssh client on the big-RAM side.** A 2.9 GB NAS box
   streaming 700 GB will OOM-kill its own ssh mid-pipe; the failure is
   silent (no stderr, no OOM trace in the flushed dmesg ring, just
   "disconnected by user" in the receiver's journal).
2. **A full stream never overwrites an existing target: it creates
   `<target>/<leaf>` inside it.** No pre-create, no `-F`, no `-e` for
   full streams; a silent 700 GB ghost under a nested directory is how
   this looks when you get it wrong.
3. **`-s` on every multi-hour `zfs recv`.** It is what makes the pipe
   resumable after any interruption; without it a break means redoing
   the copy from zero.
4. **Completion is three things, not "process gone":** the pipe exited
   0, the receiver's snapshot exists (a full send creates it *only at
   stream end*, so no snapshot means truncated even when `used` looks
   close), and receiver `used` ≈ sender `written@<snap>` (never `used`
   against `used`: the source's `used` includes post-snapshot writes
   and lies by hundreds of MB).
5. **The slow first phase is normal.** A copy of a metadata-heavy
   dataset (tens of thousands of small chunk directories) crawls at a
   few MB/s for the first hours while the data blocks, once they
   start, run near line rate. It is disk-bound early, not network-
   bound; do not panic-restart.
6. **Throttle on the LAN with `pv -L` in the pipe** (it is the progress
   bar too, if you give it `-s <stream-bytes>`). Leave headroom for
   whatever else the nightly window runs.

## Verify before you trust

- NFS effective options: `exportfs -s` (not `/etc/exports`)
- dataset encryption: `zfs get encryption,keystatus <ds>`
- snapshot content size: `zfs get -p written@<snap> <ds>` (not `used`)
- copy completeness: receiver snapshot exists + `used` ≈ sender
  `written@`
- pipe health: the receiver's sshd journal
- pool health: `zpool status` + `smartctl -a` per disk
- client mount: `mount` output shows `rw`, the expected security
  flavor, the client address
