# Component graph

The estate has hundreds of moving parts: sites, hosts, guests,
services, skills, tools, repos, log streams. Everyone who works on it,
human or agent, carries a fuzzy map of how they connect. This doc is
the discipline that keeps a *machine-readable* map honest: what it is
derived from, the rules that keep it from drifting, and the three jobs
it does.

## The claim

The map is a **derived artifact**, never a source of truth. It is
regenerated from the sources of record (the inventory, the per-service
docs, the skills and scripts directories, the submodules) on every
build, and the regenerated files are committed next to the sources in
the same commit. If the map were maintained by hand it would become a
second copy of the facts it depicts, and the second copy is where
drift lives.

## Kinds and relations

The shared vocabulary (kinds, typed relations, invariants) lives in
[../domain-model.md](../domain-model.md). The one thing that matters
for the graph: every edge is typed and directional. Dependencies point
dependent → dependency, and backup/replication edges are a distinct
*data-flow* type, because "A's backup path is broken" is a different
event from "A is broken". A blast-radius query that conflates the two
will report that your media server died when actually only its backup
stopped.

## The sources

| Source of record | What it owns |
|---|---|
| the inventory file | hosts, guests, IPs, status, per-host notes |
| per-service directories | a service's facts: what it is, where it runs, how to run it |
| the skills directory | capabilities: one folder per coherent domain |
| the scripts directory | tools: one executable unit per folder |
| the submodules | repos that are part of the estate |
| the logs directory | append-only, machine-written records (excluded from staleness checks: by design they are always dirty) |

Plus one **curation layer**, a hand-edited data file, for knowledge
that has no home yet. It is a *staging* area with a rule attached:
every curation entry is promotion debt. When a fact earns a home in a
source of record, the curation entry is deleted. If curation entries
start living there for months, the curation has become a second source
of truth, and that is the failure mode the whole design exists to
prevent.

## The rules

1. **Status is a closed vocabulary**: running / stopped /
   decommissioned / migrated / removed. The status column wins over
   prose; prose is fallback evidence. Free-text status is how
   "probably gone?" becomes permanent.
2. **Historical tables are marked, not deleted.** A decommissioned
   host keeps its old table for reference, and each row carries a
   *re-homing marker* (the new host, in a fixed position of the notes
   field) or a *rename* note. The parser follows the marker, so the
   old row stops pointing at the ghost. Deleting the row loses
   history; leaving it unmarked keeps the ghost alive.
3. **The linter advises, it never blocks.** Every warning is a
   question someone must answer ("this service has no home: where
   does it run?"), and the answer lands in a source of record, not in
   the linter. If the linter started blocking commits, people would
   route around it, and a routed-around audit sees nothing.
4. **Stale builds are labelled.** The build records the state of its
   inputs; if a source changed after the last build, the audit output
   opens with a STALE BUILD marker. Trusting a stale audit is how you
   "fix" a problem that no longer exists.

## The three jobs

- **`lint`: the standing audit.** Reports unmapped services (a
  service with no home), ghosts (rows still pointing at a
  decommissioned host), removed-but-still-listed nodes, curated-only
  nodes that should be promoted, and the needs-decision queue
  (untagged or long-offline network nodes). In a real pass, a host
  decommissioned months earlier had left twenty-one ghost rows
  behind; a live sweep (below) found the new home of every one of
  them, and the audit went from 34 open warnings to 2 in a day. The
  remaining two were owner decisions, not drift.
- **`affected <x>`: blast radius.** The transitive dependency closure
  of a component: "if I change X, what must I test?" Because
  replication is a data-flow edge, asking about a backup target
  reports the *backup paths* that depend on it, not the services that
  live near it.
- **`tree` / `diagram`: onboarding.** An indented map or a rendered
  diagram (site → host → guest → service). A fresh agent session or a
  new human reads the model instead of doing archaeology through a
  chat log.

## The live diff

The paper audit only catches drift between documents. The live diff
catches drift between documents and reality: it queries each host's
hypervisor and diffs the answer against the graph. Unregistered
guests, listed-but-gone guests, and status disagreements surface as
warnings. In the case study above, one host had a stale API token
that made its API report an *empty* fleet, while the command-line
path over SSH saw all nine guests. Rule: the live diff tries both
paths and trusts whichever returns a plausible answer.

## Failure modes

- **The map becomes truth.** Someone hand-edits a generated file, or
  starts writing facts into it. The next build either clobbers the
  edit (the fact is lost) or the edit survives as a divergence (map
  and sources disagree). Generated files are regenerable, full stop.
- **Curation goes permanent.** Staging entries never get promoted.
  Promotion debt is in the audit output for exactly this reason.
- **Status vocabulary creeps.** "sort of stopped", "maybe retired".
  The moment status is a sentence, the linter cannot read it.
- **Nobody runs the audit.** The graph is only as good as its last
  lint. A post-commit hook that rebuilds and audits when the graph's
  inputs change keeps the audit alive without depending on anyone's
  memory.
- **A fact in two places.** The original sin, and the one the other
  rules exist to prevent. The second copy is always the one the agent
  ends up reading.

## How to adopt

Start small and grow by demand: one inventory file, a parser (a
single script, standard library only), a linter with five checks, a
curation file. Add kinds (service, skill, tool, repo) when you have a
second source of record to derive them from. Keep the artifacts in
git, next to the sources. The tool is a few hundred lines; the
discipline is the product.
