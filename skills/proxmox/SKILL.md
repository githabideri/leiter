---
name: proxmox
description: >
  Operate Proxmox VE hosts: list, inspect, create, snapshot, start, stop
  and (with a human yes) destroy LXC containers and VMs through the PVE API,
  with a command-line fallback for when the API is blind; run PBS backups
  and restores; allocate guest IDs and addresses from a registry instead of
  guessing; move a guest between hosts the standalone way (archive out,
  restore in). Use for "Proxmox / PVE / PBS / LXC / VM / vzdump / snapshot /
  which guest is on this host / spin up a box for X / is this guest backed
  up". Not for: the storage behind the guests (a NAS skill owns that),
  clustered live migration (a different feature), or non-PVE hypervisors.
---

# Proxmox

You bring:

- **one or more PVE 7+ hosts** reachable on port 8006 (LAN or your
  overlay network), with a **dedicated API user** per host holding
  `PVEVMAdmin` (add `PVEBackup` where you run PBS jobs);
- **a config directory per host** with the host address, the node
  name, and the API token (see `../docs/practice/secrets.md`: values
  stay on the machine, the schema is the declared shape);
- **optional SSH to the host** (the fallback path and the only way to
  do config surgery the API role does not allow);
- **a registry file** for guest IDs and addresses (the pattern ships
  in `scripts/alloc.sh`; the file is yours to keep).

The skill contains: the API wrapper (`scripts/pve.sh`), the allocation
registry (`scripts/alloc.sh`), and two references (the API itself, the
standalone migration).

## Which task, which file

| Task | Read |
|---|---|
| Inspect / snapshot / start-stop / PBS daily work | this file |
| Token format, RBAC boundary, the blind-API rule | `references/pve-api.md` |
| A whole host is dead; move its guests to another host | `references/migration.md` |

## Setup

```bash
export PVE_HOST=<address> PVE_NODE=<node-name> PVE_API_TOKEN='...'
source scripts/pve.sh        # defines pve_* helpers
# per host: point PVE_CFG_DIR at that host's config dir instead
```

All read operations work out of the box. The wrapper's destructive
commands are hard-gated: `pve_destroy` refuses unless you explicitly
set `PVE_ALLOW_DESTRUCTIVE=1` *and* pass a confirmation argument that
matches the guest name.

## The API is the default, SSH is the fallback

The API covers listing, status, config read, snapshots, lifecycle,
tasks, storage. It does **not** cover config modification (the
`PVEVMAdmin` role cannot POST guest config), so a config change is an
SSH command on the host (`pct set`, `qm set`) or a console action.
And the API can be *blind*: a stale or mistyped token makes the API
report an **empty fleet** (a 200 with no rows), which looks exactly
like a host with no guests. The rule: when the API and the command
line disagree, run `pct list` / `qm list` over SSH and trust whichever
returns a plausible answer (the wrapper does this cross-check for you
with `pve_fleet_check`).

## Daily guest ops

```bash
# inspect (always safe)
pve_lxc_list                     # vmid  status  name
pve_qemu_list
pve_lxc_status <vmid>
pve_lxc_config <vmid>
pve_fleet_check                  # API vs SSH cross-check (the blind-API rule)

# snapshots (reversible: create/rollback/delete)
pve_snapshot_create <vmid> <name>
pve_snapshot_rollback <vmid> <name>     # guest must be stopped first
pve_snapshot_delete <vmid> <name>

# lifecycle (ask before running)
pve_start <vmid>                 # pve_stop, pve_shutdown first
pve_shutdown <vmid>              # pve_stop is the hard kill
pve_destroy <vmid>               # gated, and a human decision anyway

# PBS (backup server)
pve_pbs_status                   # jobs, namespaces, last success
pve_pbs_backup <job|target>      # trigger + follow the task
pve_pbs_restore <ns/volid>       # see references/migration.md
```

Every lifecycle call returns a task UPID; the wrapper polls it to
completion, so a returned success is a finished operation, not a
submitted one.

## Host kernel updates on PVE 9.2+ (UEFI hosts): three independent layers

`pve` dist-upgrades install a new kernel, but **which kernel actually
boots is decided by up to three layers, and fixing only some of them
wastes a reboot**. Before you reboot, line them all up:

1. **The pin file** - `/etc/kernel/proxmox-boot-pin` holds the *desired*
   kernel. `proxmox-boot-tool kernel pin <ver>` writes it; `proxmox-boot-tool
   refresh` (re)copies the pinned/installed kernels onto the ESP. The pin is
   intent only: nothing re-reads it at boot, so a host can sit pinned at an
   old kernel for months and silently miss every patch release.
2. **The ESP per-kernel layout** - `\EFI\proxmox\<ver>\` directories and
   loader entries, (re)created by `refresh`.
3. **The firmware's actual boot path** - check it: `efibootmgr -v`.
   - If BootCurrent/BootOrder points at `\EFI\systemd\systemd-bootx64.efi`
     ("Linux Boot Manager"), the ESP's `/loader/loader.conf` is the
     authority: its `default <entry>.conf` line picks the kernel, and
     **proxmox-boot-tool does not update that line**. The ESP is often not
     mounted in fstab on PVE hosts - mount it, edit
     `default proxmox-<ver>-pve.conf`, and verify the entry file exists in
     `/loader/entries/`.
   - If BootOrder points at per-kernel NVRAM entries instead, make sure the
     first entry targets the new kernel's directory (the file paths are in
     `efibootmgr -v` output).
   - Legacy-BIOS hosts: the equivalent layer is grub. PVE keeps a
     `grub.cfg-orig`; a hand-maintained `/boot/grub/grub.cfg` will keep
     booting the old kernel until regenerated or edited.

   Which world you're in: `cat /sys/firmware/efi/fw_platform` (`efi` vs
   `BIOS`).

After the reboot, verify with `uname -r` - never the pin file. Two more
PVE 9 quirks: `pve-shutdown` was removed (use `shutdown -r now`), and a
reboot whose stop-phase times out (e.g. a guest in D state) makes PVE
record the still-running guests as *user-stopped*, so they are silently
skipped at the next boot - check `pct list | grep -v running` after any
forced reboot and start the onboot ones manually. Guests that mount NFS
from a box you're about to reboot should use `nofail`/`x-systemd.automount`
or they can hang at boot until the export comes back.

## ID and address allocation: check, never guess

Guest IDs and LAN addresses are a **shared space per host** (a
container ID can collide with a VM ID on the same host), so picking
one by feel is how you get two guests fighting over an identity. The
registry is the source of truth:

```bash
scripts/alloc.sh <registry-file> list                 # everything, one row each
scripts/alloc.sh <registry-file> check <id|address>   # assigned? by whom? up?
scripts/alloc.sh <registry-file> free                 # what is genuinely free
scripts/alloc.sh <registry-file> assign <id> <name> <address>
```

Two rules the registry encodes: an **assigned-but-down** address is
not free (an offline guest keeps its address; the hypervisor's config
is authoritative over a ping), and the registry is updated in the same
step that creates the guest. Check it before you pick anything, and
if your estate uses a scheme that encodes structure in the numbers
(common: the ID's trailing digits mirror the address's trailing
octet, with reserved ranges per class of guest), document that
scheme in the registry's header so the next operator inherits it.

## Guardrails

- **Destructive is human.** `pve_destroy`, deleting a backup group,
  wiping a datastore: the agent proposes the exact command and waits.
- **Snapshot before change.** Any config surgery starts with a
  named snapshot; the rollback target exists before the risk does.
- **Read the machine first.** A guest in a strange state: read its
  status, its task history, its storage state. Not your theory.
- **Write it back.** Every guest you create, move, or retire goes
  into the registry and the estate's inventory in the same session
  (the docs-are-state loop; see `../docs/practice/doc-state.md`).

## References

- [`references/pve-api.md`](references/pve-api.md): the endpoints used
  here, the token format (and the separator that 401s), the RBAC
  boundary of `PVEVMAdmin`, how to create the user and token, and the
  blind-API rule in detail.
- [`references/migration.md`](references/migration.md): the standalone
  host-to-host guest move (archive out, restore in), which is what you
  do when a host dies and what is *not* PVE's clustered live
  migration.
