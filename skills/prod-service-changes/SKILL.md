---
name: prod-service-changes
description: >-
  "@@PROD_SERVICE_CHANGES_DESCRIPTION@@"
---

# Prod Service Changes Skill

When a task modifies a **live production service** (an endpoint with
consumers, a daemon other things depend on), apply the 3-zone model. It
polices **persistence and visibility, not change velocity**: the incident
that shaped it (a unit file destroyed by a one-liner, then the service
served 2.5 days under a login session while every monitor reported "all
good") was not caused by fast changes; it was caused by *destroyed
supervision plumbing* plus an *invisible manual era*. Tinkering must stay
fast; ghosts are not allowed.

## The zones

| Zone | What it covers | Rule |
|------|----------------|------|
| **1: Parameters** (what the service serves/does: model path, flags, env, config values) | the service's tuning surface | **Free.** Temporary change via the service's override mechanism (env drop-in, `systemctl set`, config file + reload/restart). Revert when the test is done. **Commit to the repo only when the change becomes the *new default***; persistent changes get documented, or they drift. |
| **2: Plumbing** (systemd units, drop-in dirs, watchdogs, how the service is supervised) | the supervision layer | **Repo-owned.** Read freely. Changes land in the repo (or the service's declared home) and get applied deliberately; never a one-liner `rm` + heredoc recreate through nested `ssh host "… exec …"` quoting (the exact command shape that deleted a unit file in the incident above). If a unit file vanishes anyway, self-healing (golden copy + watchdog) restores it; check the watchdog's journal for what it did before "fixing" it again. |
| **3: Provenance** (who/what is actually serving the endpoint) | unit vs. manual/nohup/login-session process | **Allowed, never invisible.** A manual run of a prod endpoint is fine in a home setting, but it must be *visible*: the service's status mechanism flags `ad-hoc`, any central observer (a hub, a dashboard) shows it, and it's noted in the session so the next agent sees it. The anti-example: the real server replaced by a login-session nohup while every layer reported "all good". |

## Concurrency (advisory, not a lock)

Before mutating a shared service, check whether **another session is
already on it**: recent session notes, the service's own status files, and
any one-line "session X is experimenting with <service> since T" notes.
Leave your own note when you start, update it when you finish. Bypassable,
but two blind agents on the same service is exactly how the incident
happened, so the check is cheap insurance.

## The canonical fast path (inference-endpoint example)

"Test model XY on the GPU box" where a unit `foo-dual` serves the endpoint:

```bash
# 1. register (one-liner in the session: "session X on foo-dual since T")
# 2. temporary override: the unit file itself stays untouched
ssh <host> "… mkdir -p /etc/systemd/system/foo-dual.service.d &&
  printf '[Service]\nEnvironment=MODEL=/opt/.../XY\n' > /etc/systemd/system/foo-dual.service.d/90-test-xy.conf &&
  systemctl daemon-reload && systemctl restart foo-dual"
# 3. verify what actually loaded: the endpoint's self-description
#    (e.g. GET /v1/models: the name field is the truth, not your intent)
# 4. test, then revert: rm the drop-in, daemon-reload, restart
# 5. update/clear the concurrency note
```

A few minutes per switch. The unit file (zone 2) is never touched, so
self-healing keeps working through the whole test. For long or parallel
experiments that must not touch the prod endpoint: separate unit or a
dedicated campaign box; never a nohup on the prod port.

## When you find a service in a weird state

1. **Read what the machine says first**: `systemctl status/is-active`, the
   service's status file, its watchdog's journal, and the endpoint's
   self-description probe. Do not start from a theory (the incident's
   first diagnosis: "corrupted filesystem, restore from backup", was a
   hallucination; the filesystem was fine).
2. **Distinguish the zones of the anomaly**: is the *parameter* wrong
   (model/args), the *plumbing* broken (unit missing/failed, start-limit),
   or the *provenance* wrong (something manual is serving)? Each has a
   different fix.
3. **Check for a prior session** on the service before changing anything;
   you may be looking at someone else's in-flight test.
4. **Recoverability beats cleverness**: restore the declared state (repo /
   golden copy) before experimenting further; keep a backup of whatever
   you replace.

## Consumer registries (the 4th surface)

A service's *payload identity* (which model/quant/capability it serves) is
also advertised in consumer registries: central config files, per-client
model lists, rosters, agent configs, hardcoded tool defaults; those are
**not touched by the service restart** and go stale the moment the payload
changes. Zones 1–3 never name these.

Rule: a parameter-zone change that changes *what the service is* (not just
how it runs) is not done until the consumer registries are handled **by
reachability class**: not "all descriptions must match", which is
infeasible as written (some consumers are not reachable from the box you
are on, and some targets are intentionally stopped):

- **Class A: reachable (mutate + verify):** registries you can touch from
  here. Edit, then **verify by re-reading the live source** (the API
  listing after a restart, the JSON file). The swap is done when every A
  source is green.
- **Class B: report-only (reachable from elsewhere):** configs on boxes
  whose key isn't here, stopped services. Don't touch them; **write a
  diff note** and record it in the open-drift queue. Report "A green; B
  pending on <machine>": never a silent "done", which is how a one-day
  drift became a multi-day one.
- **Class C: dead target:** consumer entries whose target is
  intentionally stopped. Record with the reason; delete them only when the
  target is revived or retired.

Keep an inventory of all consumer registries (what reads what, and the
mutate/verify procedure per registry) next to the service docs; a read-only
diff tool against it turns "is anyone still pointing at the old payload"
from a search into a query.

## Pointers

- Per-service specifics (units, paths, DR runbooks, their zone instances)
  belong in the service's own runtime notes, not in this skill.
- Companion skills: `monitoring` (observability, not change discipline),
  `proxmox` (host/guest lifecycle), `secrets` practice (what may appear in
  drop-ins).

---

<!--
  Estate instance section. An estate that maintains a mapping for this
  skill (the overlay contract: ../docs/overlay-contract.md) renders its
  instance content -- machines, paths, what this fleet has hit -- at
  this spot, at deploy time. The raw shape ends here.
-->
@@PROD_SERVICE_CHANGES_ESTATE@@
