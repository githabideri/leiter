# Standalone guest migration (host to host)

When a PVE host is dead, dying, or you want a guest on a different
site, the move is **standalone migration**: archive out, move the
archive, restore in. It is *not* PVE's clustered live migration, which
requires both hosts to be in one cluster and the guest to be paused
while its memory is copied. Standalone works across sites, across
clusters, and across dead hosts; the cost is a downtime window of a
few minutes to an hour, depending on guest size.

## When

- the source host is **down** (a crash, a failed drive, a decommission)
- the guest is moving **between sites** (different networks, different
  address plans)
- you have **no cluster** between the two hosts (the common case in a
  multi-site estate)

## The path

```
source host ──vzdump──▶ guest archive ──rsync / your overlay──▶ target host
                                                                     │
                                            vzrestore (new vmid ok) ─┘
                                                                     │
                                                        boot, verify, cutover
```

1. **Archive.** On the source (or its surviving storage), `vzdump
   <vmid>` produces a tarball (plus an optional qcow2/raw disk
   format). If the source is fully dead, use the **last PBS backup**
   of the guest instead; that is what the backup server is for. A
   PBS backup from the night before is usually good enough; measure
   how stale it is before promising anything.
2. **Move the archive.** The archive is a plain file; your overlay
   network (or rsync over it) carries it. Verify the checksum at both
   ends. Sizes are what they are: a 40 GB guest rootfs is a 40 GB
   transfer, and on a slow link the window is the link.
3. **Restore.** On the target: `vzrestore <archive> <new-vmid>` (or
   `proxmox-backup-client restore` from the PBS side). Choose the new
   ID from the target host's allocation registry
   (`scripts/alloc.sh`), never reuse the old one out of habit, and
   check for ID collisions on the target first (the ID space is shared
   per host: a VM and a CT can hold the same number).
4. **Network.** A guest that moves sites must get an address from the
   **target site's plan**, not keep its old one (the old address is
   someone else's there). Edit the guest's network config (this is
   config surgery: SSH or console, not the API), then boot.
5. **Cutover and verify.** Boot the guest, check the service answers,
   update the estate's inventory (the guest's row now points at the
   new host; keep the old row marked as moved, do not delete it), and
   only then retire or archive the source. Verification is per level:
   *it boots* is not *it works*; probe whatever the guest serves.

## Gotchas

- **The archive format is per-epoch.** vzdump formats have changed
  between PVE major versions; an archive made on PVE 7 does not
  always restore cleanly on PVE 9. If the two hosts are far apart in
  version, prefer the PBS route (PBS normalizes the format) or a
  block-level copy of the disk image plus a config reconstruction.
- **Static config travels with the guest.** The guest's own network
  config, its DNS names, and anything hardcoded (its own
  certificates, client configs pointing back at it) all assume the
  old address. Inventory the references *before* the move; the guest
  booting cleanly does not mean its consumers can still reach it.
- **The window is a human event.** Schedule the cutover, tell the
  consumers (or the people behind them), and take the write-back step
  (inventory, registry, service docs) in the same sitting. A migrated
  guest that is not written back is a new ghost.
- **Do not do this to a guest with state that must not stop** (a
  database with live writers, a session daemon with live sessions)
  unless the stop is the plan: standalone migration stops the guest.
  For the few guests where a stop is not acceptable, the answer is a
  cluster, not a faster rsync.
