# The PVE API, the token, and the blind-API rule

## Endpoints used by this skill

All paths are under `https://<host>:8006/api2/json`.

| Purpose | Method + path |
|---|---|
| list LXC containers | `GET /nodes/<node>/lxc` |
| list VMs | `GET /nodes/<node>/qemu` |
| LXC status | `GET /nodes/<node>/lxc/<vmid>/status` |
| LXC config (read) | `GET /nodes/<node>/lxc/<vmid>/config` |
| LXC lifecycle | `POST /nodes/<node>/lxc/<vmid>/start\|stop\|shutdown\|destroy` |
| snapshots | `GET/POST /nodes/<node>/lxc/<vmid>/snapshot[/<name>[/\|rollback\|delete]]` |
| task state | `GET /nodes/<node>/tasks/<upid>/status` |
| storage | `GET /nodes/<node>/storage` |

`POST` lifecycle/snapshot calls return a task **UPID**; poll
`/tasks/<upid>/status` until `status=stopped` and read
`exitstatus`. A call that returns a UPID has *submitted* work, not
finished it.

## The token: format is version-dependent

Create one dedicated user and token per host you operate (never the
root user):

```bash
# on the PVE host (or via the console)
pveum user add <name>-agent@pve
pveum acl modify / -user <name>-agent@pve -role PVEVMAdmin     # + PVEBackup for PBS
pveum token add <name>-agent@pve agent-token --privsep 0
```

The `Authorization: PVEAPIToken=` value is:

- **PVE 9.x**: `USER@REALM!TOKENID=UUID` (exclamation, then equals)
- **PVE 8.x**: `USER@REALM:TOKENID` (colon, no UUID)

A wrong separator does not fail loudly: the API returns a 401 saying
"no tokenid specified", which is easy to misread as a permissions
problem. Check the PVE version first (`/version`), then the format.

## The RBAC boundary (what the token can and cannot do)

| Allowed with PVEVMAdmin | Not allowed (needs SSH to the host) |
|---|---|
| list/status/config-read of guests | modify guest config (`POST .../config`: `pct set`, `qm set`) |
| snapshot create/list/rollback/delete | resize, lock, vzdump |
| start/stop/shutdown | terminal / VNC console |
| tasks, storage, version | cluster-level endpoints (`/cluster/*`) |
| create/destroy guests (depending on exact role) | - |

So the division of labor is: **API for state and lifecycle, SSH for
config surgery**. The console (VNC/noVNC) is the escape hatch for a
guest the API cannot see into.

## The blind-API rule

An API that answers with an **empty list** is not evidence the fleet
is empty. Three things produce a plausible-looking empty answer:

1. a **stale or expired token** (the API 401s internally and some
   clients render that as no rows);
2. a **wrong node name** in the path (multi-node clusters: `/nodes/`
   is specific; a typo returns an empty node, not an error);
3. a **half-broken management plane** (the host answers, its API
   subsystem is not what it should be: missing subcommands in
   `pveum`, an empty `pvesm`, a guest list that disagrees with the
   command line).

The command line on the host (`pct list`, `qm list` over SSH) is the
independent witness. The rule: **when the API and the CLI disagree,
trust the one that returns a plausible answer, and investigate the
other.** `pve_fleet_check` in `scripts/pve.sh` does the cross-check
automatically. A host whose management plane is that broken is a
reinstall candidate, not a thing to keep patching.

## PBS API (the backup server)

PBS listens on `:8008` of the host running Proxmox Backup Server, with
its own API user/token (PVEBackup role). Useful endpoints:

- `GET /api2/job`: backup jobs, state, last success
- `GET /api2/repository`: datastores, usage, pruning
- `POST /api2/job/<jobid>`: trigger a job
- `GET /api2/repository/<ns>/`: volumes in a namespace

One PBS-specific fact that bites: a PBS host is **not** a PVE host
with a different port. It has no `pvesm`/`pveum`/`pvesh`; it is its own
machine with its own API.
