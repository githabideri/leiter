# The bare ZFS host as NAS

The second family: not an appliance, but a server whose local ZFS pool
*is* the NAS. The common estate shape is a Proxmox host whose pool
serves both the guests' rootfs and a few NFS-shared data datasets.
No appliance layer, no management API: the files and the pool itself
are the source of truth, which makes this family easier to operate and
easier to get subtly wrong (nothing tells you what the effective
export is but the kernel).

## NFS on a Debian/Proxmox host

- The server is `nfs-kernel-server`; the source of truth is
  **`/etc/exports`**: one line per share × client, the client being a
  host address or a subnet. Apply with `exportfs -ra`; verify the
  *effective* options with **`exportfs -s`** (that is the only view
  that includes the defaults the kernel filled in).
- The `root_squash` rule runs in reverse of the appliance family:
  here the exports file is visible and authoritative, but
  `root_squash` is still the *default when omitted*. So the discipline
  is the same as on the appliance: if a client writes as root, say
  `no_root_squash` explicitly; if it should not, say `root_squash`
  (or `all_squash` for anonymous) explicitly. Never rely on the
  default on either side.

## The share patterns (by client class)

| Client class | Options | Why |
|---|---|---|
| machine-to-machine, writes as root (backup software, VMs, agent boxes) | `rw,sync,no_subtree_check,no_root_squash`, pinned to the client's address (one per client: the tailnet IP, the LAN IP) | root writes must not be squashed; pinning keeps the blast radius per client |
| human read-only | `ro,sync,all_squash,anonuid=<uid>,anongid=<gid>,no_subtree_check` | everyone is the same anonymous uid; nothing can write, nothing can map root |
| LAN-wide share | `rw,sync,no_subtree_check`, pinned to a `/24` (and/or the tailnet address of one consumer) | subnet pinning instead of per-host when the client population is the whole LAN |

`sync` everywhere for anything that is a record (the write cost is
real, the data is more real). `no_subtree_check` is standard hygiene
for NFSv4.

## Coexistence with the hypervisor

- **Share dedicated child datasets, never the pool root and never the
  `.system` children.** The pool simultaneously serves the guests'
  disks (registered as hypervisor storage) and the shared data; the
  separation is by dataset, and the export list is the contract.
- **The RAM budget is shared with the guests.** A streaming job on
  this host competes for memory with every VM on it; the pipe rules
  from `send-recv.md` (client on the big-RAM side, watch for OOM
  kills, resumable receive) apply with *more* force here, because an
  OOM on the host can take the guests down with it.
- **Decommissioning this host is two different migrations, plan both**:
  the guests move the standalone way (archive out, restore in; the
  proxmox skill's reference), and the data pool moves as `zfs
  send/recv` (this skill's references). The pool is the long pole and
  the reason the move gets scheduled; the guests are the short pole.
  If the pool is mirrored and the target is the same, the data copy
  is the full-stream recipe; if the target is a different layout
  (RAIDZ instead of mirror), the receive lands on the new pool and the
  old one is retired, not "moved".

## Mirror health: read the config, not the health string

A two-disk mirror is the classic small-NAS pool: half the raw
capacity, cheap redundancy, simple. The failure mode to know: a
mirror with one leg **REMOVED** is a *single disk*. The pool's
top-line health will say DEGRADED, but the fact that matters is in
the `zpool status` **config section** (the leg list), not in the
summary: a leg marked `REMOVED` with no replacement attached means
zero redundancy, whatever the pool's `state` line says.

The usual cause is a deliberately removed bad disk (a flaky SATA
link that keeps resetting is a legitimate reason to pull the leg and
stop the host lockups), and the trade is explicit: no more link-flap
lockups, but no redundancy until the replacement leg is attached
(`zpool attach`/`zpool replace` on the surviving leg, then a full
resilver). While it runs single-leg, treat the data as single-copy:
anything on it that must not be lost has to be mirrored or backed up
*elsewhere*, by a different mechanism, until the second leg is back.
A `zpool scrub` on a single-leg mirror will not find what a failed
disk took with it; the scrub protects against bit rot, not absence.

## send/recv with this family

Both sides are Linux OpenZFS: the `send-recv.md` recipe applies
unchanged (throttled pipe, `-s` resume, the three-part completion
check), minus the FreeBSD quirks (no `creation`/`created` confusion,
`zfs get -Hp` prints the value only, `recv -F` may create the target
on a Linux receiver). The encryption matrix still applies if either
pool is encrypted (an encrypted pool is a common choice for a
disk-full-of-data mirror).
