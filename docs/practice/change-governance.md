# Change governance

The estate runs continuously and its operators are replaceable: any
given session is a stranger with root. Governance here is therefore
not about who may do what; it is about three properties of every
change: **fast where it is safe, persistent where it matters, visible
always**.

## The three zones

| Zone | What it covers | The rule |
|---|---|---|
| **1. Parameters** | what a service serves or does: model, flags, config values, ports | **Free.** Change on the spot through the service's override mechanism (an env drop-in, a config value plus reload). Revert when the experiment ends. Commit to the repo only when the change becomes the *new default*. |
| **2. Plumbing** | supervision: unit files, drop-in directories, watchdogs, restart policy | **Repo-owned.** Read freely. Changes land in the repo and are applied deliberately. Never a one-liner delete-and-recreate through nested quoting layers. If a unit vanishes anyway, the self-healing layer restores it from the golden copy, and you read what the watchdog did before "fixing" it again. |
| **3. Provenance** | who or what is *actually* serving an endpoint: a managed unit, or a manual process started by a login session | **Allowed, never invisible.** A manual run of a production endpoint is fine in a private estate, but the status mechanism must flag it as ad-hoc, and the session must record it, so the next operator sees it. |

The zone model polices **persistence and visibility, not change
velocity**. Tinkering stays at three minutes; ghosts are not allowed.
The canonical incident this design was built for: a unit file deleted
by an accidental one-liner, then the endpoint served for two and a half
days by a manual process while every monitoring layer reported "all
good". Zone 2 would have made the deletion visible (the golden copy
restores and the watchdog logs it); zone 3 would have made the manual
era visible (the endpoint would have worn an ad-hoc flag). Either zone
alone would have ended the incident in hours instead of days.

## The fourth surface: consumer registries

A parameter change that changes *what* a service is (which model, which
capability) also goes stale everywhere that service is *advertised*:
router configs, model registries, agent configurations, hardcoded
defaults. Those consumers are not touched by a restart. They are
handled by reachability class, not by a uniform "update everything":

- **class A, reachable from here**: mutate, then verify by re-reading
  the live source. The change is done when every class A source is
  green.
- **class B, reachable from elsewhere**: do not touch; write a diff
  note and report "class A green, class B pending on that machine". A
  silent "done" here is how a one-day drift becomes a multi-day one.
- **class C, intentionally stopped**: record the reason; clean up only
  when the target is retired or revived.

## Concurrency: advisory, not a lock

Before mutating a service, an agent checks whether **another session is
already on it**: the session index (search the memory layer), the
service's own status files, any one-line notes. It leaves a note when
it starts and clears it when it finishes. The check is bypassable by
design (it is advice, not a lock), because two blind agents working on
the same service at once is exactly how the incident above happened,
and the note costs one line.

## Destructive operations

Removing a guest, wiping a disk, deleting a branch, cutting a network
path: these are always **human decisions**, even when the agent has
every capability needed to execute them. The agent's job is to make
the decision easy: state the exact command, what it touches, what
recovers it, and what the alternative is. The agent proposes; the
human disposes.

## Reading the machine first

When a service is in a strange state, the diagnosis starts from what
the machine says: its own status files, the watchdog journal, a
"what is actually being served" probe against the endpoint. Not from a
theory. A wrong theory plus fast tooling is how a healthy filesystem
almost got declared corrupted. Recoverability beats cleverness:
restore the declared state (repo, golden copy) before experimenting
further, and keep a copy of whatever you replace.

## Failure modes

- **The ghost era.** Manual process, no flag, no note: the estate
  runs on an invisible change for days.
- **The deleted unit.** One-liner plumbing surgery through nested
  quoting; the supervision layer is gone and the service works, which
  is worse than a crash, because a crash is visible.
- **The silent "done".** Class B consumers left stale with no
  report; the drift compounds until someone's client picks up a model
  that no longer exists.
- **Two blind sessions.** No concurrency note; both agents "fix" the
  same service in opposite directions.
- **Theory-driven repair.** The first plausible explanation is acted
  on instead of the first observed fact.

## How to adopt

Start with the zone table in a single page and the one-line
concurrency note. Add the golden-copy self-healing for the two or
three services that must not die. Add the reachability-class procedure
the first time a payload change goes stale at a consumer. The
destructive-operations rule does not need adopting; it is a constant.
