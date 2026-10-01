# CLI and encryption differences

TrueNAS SCALE is FreeBSD underneath (FreeBSD's ZFS, FreeBSD's zsh),
while the boxes it copies to and from are usually Linux with OpenZFS.
Bit by bit, the two CLIs are not the same, and the two ZFS kernels
disagree on what a resume and an encryption state mean.

## FreeBSD (SCALE) vs. OpenZFS (Debian et al.)

| Thing | FreeBSD / SCALE | OpenZFS / Linux |
|---|---|---|
| dataset usage | no `zfs used` command: `zfs list -Hp -o used <ds>` | `zfs used <ds>` works |
| snapshot age property | `creation` | `created` |
| `zfs get -Hp <prop>` | prints the **full line** (`name property value origin`); extract with `awk '{print $3}'` | prints the value only |
| `zfs recv -F` | **requires the target dataset to already exist** ("cannot receive: specified fs … does not exist"): `zfs create` it first (it inherits pool compression/recordsize), then recv | creates the target if missing |
| `zfs send -w` | means **`--raw`** (send encrypted data as-on-disk), *not* a resume token | the resume token is `-t` on both; `-w` is raw on both too, but the FreeBSD docs make it easy to misread |
| resume | `zfs recv -s` saves a `receive_resume_token` on any interruption and prints the exact `zfs send -t <token>` command; resume with `send -t` (no snapshot argument) + `recv -s` (no `-F`) | same mechanism, same flags |
| `zfs diff <snap>` | creates temp `zfs-diff-*` snapshots on the **source** that hold data (skew `used`) and spew audit SYSCALL entries that can flush the dmesg ring; clean them up afterwards (`zfs destroy <ds>@zfs-diff-*`) | same temp snapshots |
| default shell | **zsh** (`exportfs` is not `export -r`; globs are live; `=word` expansion means `echo ===` fails) | bash |

The one rule that covers most of this table: **never trust a manpage
or wiki page that was written for the other side of the pipe.** When a
flag behaves wrong, check which kernel you are standing on first.

## The encryption × `recv -F` matrix

Both directions of the matrix matter, and they are not symmetric:

| Stream type | Target unencrypted | Target encrypted |
|---|---|---|
| **full** (new filesystem) | plain `recv` (creates the dataset) | plain `recv -u` (creates it, inherits pool encryption); **`recv -F` is refused**: "zfs receive -F cannot be used to destroy an encrypted filesystem or overwrite an unencrypted one with an encrypted one". Unconditional in OpenZFS 2.3: key loaded or not, the dsl directory cannot point at two keys at once. Workaround if the target already exists: `zfs destroy -Rf`, then plain recv |
| **incremental** (into an existing dataset) | plain `recv` | **`recv -F` required, and it works here**: the `-F`-plus-encrypted rejection applies to *full* streams only; for incrementals `-F` just skips a check that is broken for encrypted targets (below). Pre-verify the base snapshot exists on both sides |

(For datasets encrypted *below* pool level with a receiver-side key,
`zfs recv -F -u -e` also works; pool-level encryption is the common
case and the matrix above covers it.)

## The OpenZFS 2.3 incremental bug (the reason the last cell says `-F`)

After a full `send snap | recv` into a dataset in an **encrypted**
pool, the follow-up `zfs send -i base snap | zfs recv <dst>` fails with
*"destination has been modified since most recent snapshot"* **even
when `zfs diff dst@base dst` is empty**. The check
(`dsl_dataset_modified_since_snap()` in `module/zfs/dsl_dataset.c`)
compares the head and snapshot **meta dnodes**, not content; on
encrypted datasets they always differ. The identical pattern works in
an unencrypted pool. The fix is `recv -F` for incrementals into
encrypted targets: for an incremental, `-F` skips only that false
check, which is why the matrix row is safe. This is exactly the split
a robust mirror script uses: **full = plain recv (it creates),
incremental = `recv -F`**.

## Storage gotchas on SCALE

- **Root dataset is `readonly=on` by design.** No files in `/`; new
  mountpoints directly under `/` fail with "Read-only file system".
  Mount under `/data/<x>`.
- **Swapfiles do not work** (`fallocate`/`dd`/`urandom` swapfiles all
  fail `swapon`: hole detection versus ZFS compression and
  recordsize mismatch, "appears to have holes" / "Invalid
  argument"). Use a zvol: `zfs create -V 2G -o volblocksize=4K
  boot-pool/<vol>`, then `mkswap /dev/zvol/<pool>/<vol>` and fstab.
  This matters because a NAS box that streams big copies is a
  RAM-starved OOM factory (middlewared alone is a few hundred MB, and
  the ARC eats the rest); a small swap volume is what keeps the ssh of
  a long pipe alive.
- **The FTL database path differs from Debian** for any Linux-ported
  service (e.g. a DNS sinkhole keeps its database at the FreeBSD
  path, and its schema is the version the port ships, not the
  Debian-packaged one).
