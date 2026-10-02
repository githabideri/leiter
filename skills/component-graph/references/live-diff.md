# The live diff: the audit versus reality

The paper lint finds drift *between documents*. The live diff finds
drift *between documents and the machines*: a guest that exists but
is not registered anywhere, a registered guest that no longer
exists, a status that the docs and the host disagree about.

## The shape

A spec file maps each host to a command that lists its live guests:

```json
{
  "host/alpha":   {"cmd": "pct list; qm list"},
  "host/beta":    {"cmd": "pct list"}
}
```

`component-graph live live-spec.json` runs each command over SSH to
the host (the SSH target comes from the host node's `ssh` field, or
the node id as an alias), parses the guest identifiers and names,
and reports per host:

- **unregistered**: on the host, not in the graph (an untracked
  creation, or an extractor that lost it);
- **listed-but-gone**: in the graph, not on the host (a ghost: the
  row outlived the guest);
- **empty-from-this-path**: the command returned nothing while the
  graph expects guests. That is the tell for a *blind* path, and it
  is reported as such, not as "the host is empty".

## The dual-path rule (the lesson the spec is for)

The command in the spec is whatever you **trust**, and the reason
trust is per-path is a real one: a management API can answer 200
with an *empty list* when its credentials are stale or its control
plane is half-broken, and an empty list is indistinguishable from an
empty host if you have only one witness. The command-line path on
the host (`pct list` / `qm list` on a hypervisor; `zfs list` on a
NAS; `docker ps` elsewhere) is the independent witness. So:

- where the API works, the spec uses it (richer fields, no SSH
  dependency);
- where the API has proven unreliable (stale token, missing
  subcommands, an empty answer you do not believe), the spec uses
  the CLI over SSH for that host;
- the tool's job is to make a disagreement visible, not to resolve
  it: an empty API against a populated graph prints the
  "empty-from-this-path" tag, and the human (or the next session)
  switches the spec's command and re-runs.

A host whose management plane is that broken (its own CLI and its
API disagreeing, subcommands missing) is a reinstall candidate, not
a thing to keep patching; the live diff is what surfaces the
disagreement in the first place.

## Where it fits in the cycle

1. the **paper lint** runs on every relevant change (a post-commit
   hook after inputs change): it is cheap and total;
2. the **live diff** runs on a schedule (a weekly job) or on demand
   (before a big change, after a suspected incident): it is cheaper
   than the paper audit's trust, not cheaper to run, and it is the
   only check that can catch a guest that was created by hands the
   docs never saw;
3. a discrepancy is a **work item with an owner-shaped question**
   ("register it, or delete it?"), answered in a source of record,
   the same way every lint finding is answered. The live diff, like
   the lint, advises and never blocks.

The two together are the full audit: *is the map true of the docs,
and are the docs true of the machines?* A map that passes only one
of the two halves is a map with a hole in exactly the place an
incident will find it.
