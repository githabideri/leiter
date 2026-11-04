---
name: "@@PROCESS_SURGERY_NAME@@"
description: >-
  "@@PROCESS_SURGERY_DESCRIPTION@@"
---

# Process surgery

Operating on a **running process on a live host** (stopping an
interrupted transfer, killing a runaway loop, debugging a live worker)
without taking collateral damage. This is the discipline for the moment
between "something is running that I want to change" and "the system is
in the state I want".

The whole body of this skill exists because six distinct footguns each
cost a real incident on the estate that produced it. Every rule below
has a scar behind it; the dates and specifics are in the estate section.

## When this applies

- stopping / interrupting / restarting a **long-running data process**
  (a transfer stream, a pipeline, a worker loop) that someone else (a
  cron job, a previous session, a supervisor) started;
- diagnosing why a live process **died or stalled** without touching it;
- deciding whether a half-finished job can be **resumed** or must
  restart, and doing that decision safely.

Not for: normal service lifecycle (unit restart, deploy): that is the
`prod-service-changes` skill; console-level access to unreachable
hosts: the `kvm` skill; the design of the data flows themselves (their
own docs).

## The six footguns

### 1. A kill pattern in your own command line kills you

`ssh host "pkill -f <pattern>"` matches the **ssh session itself**,
because the pattern is in the remote shell's argv. Result: the command
dies mid-flight (often just an empty 255), half the intended kills
happened, and you don't know which.

Rule: **never put a kill pattern in an interactive command line.**
Either pass **explicit PIDs** (found in a previous, separate step), or
run a helper script that owns the matching (below). Find → map → act →
verify, in separate commands, never one.

### 2. `pkill -P` reaches only direct children

Killing a parent does not reach grandchildren. They **reparent to
init** and keep running, and they keep holding the parent's file
descriptors, locks, and open files. A "killed" pipeline can leave
orphaned mid-stage processes that hold a lock file indefinitely or keep
writing to a destination.

Rule: after killing a process, **re-list the whole tree and confirm
every level is gone**; check what still holds the lock
(`fuser <lockfile>`).

### 3. Children inherit every open file descriptor

A long-lived child (daemon, background job) that inherits a `flock`
fd keeps the lock alive **past the parent's death**: every subsequent
"am I the only one running" check says *yes someone is* for as long as
the child lives. Observed: a 3-hour budget wrapper blocked all
subsequent runs for its full lifetime after the parent was killed.

Rule: long-lived children must **close inherited lock fds first**
(`exec 9>&-` before opening their own). If you spawn a **server**
process (e.g. a tmux server, which outlives everything), close the fds
in a subshell *around the spawn*, because the server is a child of your
client, not of you.

### 4. TERM and KILL mean different things to the victim

`SIGKILL` leaves a process's cleanup unrun: a `zfs recv -s` pipeline
only **saves its partial state and prints a resume token** when the
stream closes *gracefully* (the ssh leg gets TERM and the stream
terminates). KILL the recv and the partial is gone (or stuck), and with
it the only resume path.

Rule: TERM first, with a **drain window** (seconds), to the whole tree;
KILL only what survives, and know what you lose by doing it.

### 5. Never strace / ptrace a production process

Attaching a tracer to the **leader thread** of a multithreaded process
(a `zfs send` is one) can deliver signals or corrupt its state; the
process died with "signal received" mid-stream. If you need to know
what a process is doing, read its **logs**, its `/proc/<pid>/status`
(`State`, `Threads`), its file descriptors (`/proc/<pid>/fd`), and the
counterparts on the other end of its pipes, not a tracer.

### 6. Kill boundaries belong where the side effect actually is

If a guard or operator must be able to interrupt a multi-step job, the
interruption point must sit **at the start of the next side-effecting
step**, not at the end of the previous one. A job that "just finished
step N" is the most dangerous moment to kill it, because step N+1's
destructive part may be its very first act. (Design consequence: prefer
jobs whose steps are non-destructive until verified.)

## The safe procedure (the habit)

1. **Find** by PID, in its own command: `ps -eo pid,ppid,etime,args`
   (the pattern may appear here; this is a *read* command).
2. **Map** the tree (pid→ppid) and what it holds: lock files, sockets,
   the other end of any pipe (check the peer host), what it writes to.
3. **Decide** the signal from footgun 4; know which state you forfeit.
4. **Act** on explicit PIDs (or the helper below), TERM then drain.
5. **Verify** in a fresh command: tree gone, locks released
   (`fuser`), the peer end closed, the destination in the state you
   expected. *Only then* proceed to the next step of your plan.

## The mechanical guard: `safe-kill.sh`

Bundled in `scripts/safe-kill.sh` (pure bash + coreutils; copy it to
the target or run it over ssh *as a file*, never inline). It
implements steps 1–5 as one auditable action: it matches the marker
with a bracketed regex **and excludes its own ancestor chain** (so the
ssh session that invoked it can never be a match), prints the tree it
will touch (dry-run mode `-n`), then TERM → drain → re-list → optional
`-9` escalation. The point is not the script's cleverness; it is that
the pattern now lives in a **file on the target**, where it cannot be
in your command line.

```
ssh <host> 'bash /path/to/safe-kill.sh -n "<marker>"'   # dry run
ssh <host> 'bash /path/to/safe-kill.sh "<marker>"'      # TERM + verify
```

## Long-running work: run it where a human can watch

For transfers that take hours or days, the execution model matters as
much as the transfer. The pattern this estate converged on:

- **No `nohup` for anything a cron job spawns.** On some appliance
  hosts (measured: TrueNAS 25.10) a re-exec'd nohup grandchild of a
  cron process lands in a context where common `/bin` utilities
  (`date`, `awk`, `sleep`) die with `Function not implemented`,
  which turns a retry loop into a busy-spin that hammers its peers.
  Direct cron children and ssh children are fine; **a tmux session
  spawned from cron is fine too** (verified by probe). So: cron tick →
  `tmux new-session -d -s <name> "<worker>"` (with footgun 3's fd
  close), no nohup anywhere.
- A named **tmux session** (`<flow>-<unit>`) gives: attachable live
  view for a human (`tmux attach -t <name>`), scrollback as a second
  log, a stable findable identity (the session name, not a reused
  argv), and clean kill semantics (`tmux kill-session` TERM's the
  tree). The worker prints a **heartbeat line** (size/rate/next step)
  so an attach shows the state at a glance.
- **tmux does not survive a power cycle.** If the host can sleep or
  reboot (appliance power management), the *durable* recovery is the
  data-side one: resumable transfers (tokens / incremental bases) plus
  a watchdog tick that restarts the session after a reboot. Hold
  whatever keeps the host awake (the estate's activity lock) until the
  work is done. tmux is observability and process hygiene; the resume
  protocol is robustness.

## Verification

A surgery is done when, in fresh commands: the target processes are
gone at every tree level; the lock file answers `fuser` with nothing;
the peer host shows no more of the pipeline; the destination dataset /
file is in a **known** state (complete snapshot, saved partial with a
token, or clean), and that state is written down, not assumed.

---

<!--
  Estate instance section. An estate that maintains a mapping for this
  skill (the overlay contract: ../docs/overlay-contract.md) renders its
  instance content -- machines, paths, what this fleet has hit -- at
  this spot, at deploy time. The raw shape ends here.
-->
@@PROCESS_SURGERY_ESTATE@@
