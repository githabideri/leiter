---
name: "@@ENCRYPTED_BACKUP_NAME@@"
description: >-
  "@@ENCRYPTED_BACKUP_DESCRIPTION@@"
---

# Encrypted backup of a third party's data

You bring:

- **a data owner** whose data must be protected *from the operator as
  much as from failure*;
- **an operator host with the capacity** (a NAS or a big server) and a
  network path to the source (ideally an overlay, so the copy does not
  depend on the source's LAN being reachable);
- **a notification channel** the owner or the operator watches (a
  home-automation panel, a bot, email);
- optionally **a carrier drive** for the physical leg (data that must
  end up in the owner's own house, on media the operator controls
  only until hand-off).

Two trust patterns cover most of the space; many estates run both, one
for each question they have to answer ("is it safe *anywhere*" and "is
there a copy *in my house*").

## Pattern 1: the E2E-encrypted repo

The reference implementation is Kopia, but the pattern is the point:

- the **operator runs the server**: a repository on their storage
  (a filesystem repo on a ZFS dataset is the simple, good choice;
  consider `--append-only` so even the operator cannot delete
  versions), a TLS endpoint with a control password, and **two
  users**: the data owner (full access to their data) and an admin
  account (verify, GC, operational checks) that is *not* the owner;
- the **owner's passphrase is set at their first client connect, on
  their machine**, and the whole discipline is that it **never
  touches any operator machine**: not in a config, not in a log, not
  "temporarily, I'll delete it after". The server stores the data
  encrypted; the operator can store, move, restore-to-the-owner, and
  verify integrity, but cannot read a single file. That is the
  property the design is buying; every convenience that touches the
  passphrase forfeits it;
- **clients dial out** over the overlay (source machines and the
  owner's own machine as ordinary clients); a per-source ignore file
  at the source root (gitignore-style: the bulky intermediate formats
  the owner keeps elsewhere, OS cruft, recycle bins) is the first
  tuning knob, because the copy size is decided by it;
- **verification is the admin user's job** (integrity checks,
  snapshot listing, GC of superseded versions) and is *not* the
  owner's: the owner's client does backups, the admin client proves
  the backup.

Why this pattern exists: an unencrypted "I'll just be careful" backup
of someone else's life (photos, documents) converts a disk failure
into a privacy incident the moment the disk ends up in the wrong
place; and it converts *you* into a person who can read their
everything, which most people do not want to be, and the data owner
does not want you to be.

## Pattern 2: the physical carrier

A drive that carries a plain copy to the owner's own home:

- **the copy only grows.** No `--delete`, ever: the carrier is a
  recovery copy, and a delete on a drive that is about to travel is a
  one-way decision. If the source is pruned, the carrier keeps the
  old versions, and that is a feature;
- **it has completion markers, not vibes.** Each stage writes a
  marker file when it is done (mirror-complete, carrier-complete);
  the hand-off is *when the final marker exists*, and the hand-off
  itself is an event the owner expects (a drive that arrives without
  its "done" note is an ambiguous artifact);
- **the chain is staged, with the mirror as the staging area.** A
  direct source-to-drive copy over a long network leg couples the
  two slowest things in the system. The working shape: source →
  operator mirror (over the network, resumable), then mirror → drive
  (local, fast, repeated passes until it converges, a final pass
  triggered by the mirror's completion marker). Each stage is a
  separate process with its own log and its own marker;
- **the drive's hardware discipline is its own task**: consumer
  enclosures flap (link resets; the fix is usually to disable UAS
  for that specific enclosure, not to blame the drive), a drive that
  is passed through to a VM fights the host for ownership (if the
  copy runs on the host, the passthrough comes out), and a drive that
  gets copied to for days deserves power that is not on an
  automation-controlled socket (a mid-copy power loss is recoverable
  with partial-file rsync, but it is a wasted day and a scary log).

## The multi-day copy discipline

The copies these systems run are weeks, not hours, and the discipline
is where they live or die:

1. **the sync owns its session.** A detached session (own process
   group, `setsid`-style), so that nothing that is also being used
   interactively can kill it; the interactive tool (a multiplexer)
   is a *viewer* over the sync's log, not the sync's container.
   Killing the viewer, the terminal, even the machine (with a
   reboot-time autostart) never touches the copy;
2. **heartbeat lines, because progress dies.** A long-running
   copy tool's progress output is not a reliable signal: on at least
   one build the progress channel silently dies mid-copy (hundreds of
   gigabytes moved, zero visible progress). The heartbeat is a
   separate small process that reads the copier's own I/O counters
   from the kernel and writes one line per minute (bytes written,
   rate). The stall detector and the human both watch *that*, not the
   copier's mood;
3. **stall detection is on the log's mtime**, with a per-stage
   threshold (network leg and local leg have different expectations),
   and the alert re-arms on a longer interval instead of re-sending
   every few minutes;
4. **idempotent (re)start, one command.** A single script that polls
   for the hardware it needs (a USB drive appears a few seconds after
   boot; wait up to a bounded time, then give up loudly), re-mounts
   it with the right options, checks the markers (already done?
   skip), and starts what is not. The script is the only way
   anything starts, which is the property that makes "the host
   rebooted at 3am" a non-event;
5. **notifications dedup with a state file keyed `event:target`,
   storing the last-send timestamp**, and the guard compares
   *presence/epoch*, never "have I sent to a target named X" as a
   boolean that a different code path forgets to set. A dedup bug
   here does not lose data; it loses the operator's trust in the
   channel by re-sending one happy event for two weeks straight,
   after which nobody believes any of the alerts;
6. **delivery is proven by the response code.** The notifier checks
   the HTTP status of the send (non-2xx = not delivered = retry next
   tick); a fire-and-forget POST to a notification API is how
   "notified" becomes a belief instead of a fact.

## Failure modes

- **The passphrase touches an operator machine.** Once. "Just to test
  the restore." The property is gone; the backup is now an unencrypted
  backup with extra steps.
- **`--delete` on the carrier.** The recovery copy becomes a mirror,
  and the thing it existed to survive (a bad sync, a deleted
  directory, a wrong flag) is now gone in two places.
- **Progress watched instead of I/O.** The copier's progress output
  dies; the copy is fine; the stall alert fires; the operator kills a
  healthy multi-day copy. The heartbeat exists because this has
  happened.
- **The dedup boolean.** One event, re-sent every five minutes for
  eleven days (a real incident, caused by a guard that checked the
  wrong field); the channel is dead on arrival for the first *real*
  alert.
- **The passthrough tug-of-war.** The drive is a VM device and a host
  device at once; every attach flaps; the fix is choosing one owner,
  not more retries.
- **The notification channel's quirks, undiscovered.** The panel you
  think shows your notification is fed by a history log, the API
  rejects the field you use for dedup at the API level, and a
  "device not connected" error means the app's local-push socket is
  stale, not that your message is wrong. Find out which one you are
  talking to *before* the first real alert, not during it.

## What a finished system looks like

New data on the source is backed up E2E (the owner can decrypt; you
cannot), the carrier in the owner's house holds a growing plain copy
that was handed back with its done-marker, every stage has a log and
a marker, a rebooted host reassembles itself without a human, and the
only notifications you get are *first-time* events. The boring
version of all of that is the goal.

---

<!--
  Estate instance section. An estate that maintains a mapping for this
  skill (the overlay contract: ../docs/overlay-contract.md) renders its
  instance content -- machines, paths, what this fleet has hit -- at
  this spot, at deploy time. The raw shape ends here.
-->
@@ENCRYPTED_BACKUP_ESTATE@@
