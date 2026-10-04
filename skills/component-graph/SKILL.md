---
name: component-graph
description: >
  Keep a machine-readable map of the estate (sites, hosts, guests, services, skills,
  tools, repos) derived from the sources of record: the staleness audit (unmapped
  services, ghosts on dead hosts, removed-but-listed, curation debt, needs-decision),
  blast radius ("if I change X, what breaks"; backup edges read as data flow, not
  dependency), and onboarding. Discipline: the graph is a derived artifact, never a source
  of truth; status is a closed vocabulary and outranks prose; old rows are marked, not
  deleted; the linter advises and never blocks; a stale build labels itself. Includes a
  starter tool (build/lint/affected/tree/live over normalized JSONL). Use for "build a
  component map", "audit my inventory for drift", "what depends on X", "which of my docs
  are ghosts", "onboard a new person/agent to the estate". Companion doctrine:
  docs/practice/component-graph.md. Not for: runtime monitoring (the monitoring skill) or
  service operations (their own skills).
---

# Component graph

The doctrine (why each rule exists, the failure modes, the adoption
path) is in [`../../docs/practice/component-graph.md`](../../docs/practice/component-graph.md).
This skill is the tooling side of it.

You bring: the sources of record your estate already has (an
inventory, per-service docs, a skills directory, whatever), and the
willingness to keep the graph *derived*. The skill contains:

- `scripts/component-graph`: the starter tool (standard-library
  Python, one file): `build`, `lint`, `affected <x>`, `tree`,
  `live <spec>`; `build` also writes a **machine index**: a generated
  name → site → role projection other skills and agents read to resolve a
  machine nickname without opening the full inventory;
- `examples/`: a runnable miniature estate (an inventory table, two
  service directories, an overlay-skills extractor that stays a no-op
  without an overlay, a curation file, a config) so the whole loop
  works out of the box;
- `references/live-diff.md`: the paper-audit's sibling, diffing the
  graph against what the hosts actually run.

## How the tool is shaped (and why)

The tool does not parse your documents. **Each source of record has an
extractor**: a small script that reads that source in its native
format and prints *normalized JSONL* (one node per line, with its
kinds of edges inline). The tool then does three things it can do the
same way for any estate: merge the extractors with a curation file,
write the artifacts (nodes, edges, build metadata including the
input hashes and the git-dirty state), and audit.

That split is the architecture, not a convenience: your formats are
yours and they change, and the parser for a format is the one place
that is allowed to know that format. The normalized line is the
contract; the tool is stable underneath your churn. A new source kind
is a new extractor (tens of lines, testable alone), never a change to
the auditor.

The node's contract is small on purpose: an id (namespaced,
`kind/name`), a kind, a status from the closed vocabulary
(running / stopped / decommissioned / migrated / removed), an
optional site, and edges in five directions (four dependency-ish, one
data-flow; see the tool's header). Everything else about a component
stays in its source of record; the graph carries the *shape*, the
sources carry the *facts*.

## The commands

```
component-graph build --config config.json
component-graph lint  --config config.json
component-graph affected host/alpha --config config.json
component-graph tree  --config config.json
component-graph live  live-spec.json --config config.json
```

- **build** runs the extractors, merges the curation, writes the
  artifacts. A duplicate id is a warning (two sources claiming one
  fact); a failing extractor is a warning with its stderr, and the
  rest of the graph still builds (a dead source degrades the map, it
  does not kill it).
- **lint** is the standing audit. The checks: unmapped services (a
  service node with no home), ghosts (a node pointing at a
  decommissioned/removed target), removed-but-still-listed,
  curated-only (promotion debt, the check that keeps the curation a
  staging area), needs-decision flags, and bad statuses (anything
  outside the closed vocabulary). It opens with a **STALE BUILD**
  warning when an input changed or is uncommitted since the last
  build: the audit is only as good as its inputs, and a stale one
  says so instead of pretending.
- **affected <x>** answers "what must I test if X changes": the
  transitive dependency closure (runs-on, depends-on, serves),
  reported separately from the **data-flow** dependents (things whose
  *backup path* goes through X: losing those does not stop the
  service, but it does stop the recovery). The two closures are
  different questions and the tool refuses to blend them.
- **tree** is the onboarding view: site → host → everything on it,
  with status marks. A fresh reader (human or agent) gets the shape
  of the estate in one screen instead of an archaeology session.
- **live** is the diff against reality (next reference): per host, a
  command that lists what is actually running, compared with the
  graph's children of that host.

## A source the directory scan misses: overlay-rendered skills

If the estate's skills are overlaid from a public shape repo
([`docs/overlay-contract.md`](../../docs/overlay-contract.md), worked
example 2), the skills the agent actually loads include a class that
is *not in the skills directory*: the body is the public shape tree,
the values are the private overlay directory (mapping plus estate
file), and the rendered instance lands in a gitignored skills root.
A skills-directory scan extractor then fails in two ways: the class
**vanishes** (the rendered root is gitignored, the shape tree is a
submodule; the capabilities appear in no node, and their corresponding
tools read as orphans), or the estate patches each one by hand: a
per-skill curation node that works for one and silently misses the
next shape the overlay picks up.

The fix is an extractor, not curation: `examples/extractors/
overlay-skills.py` (wired into the example config; a no-op when the
overlay directory is absent, so a plain estate carries it for free).
One `skill/<estate-name>` node per values directory, the estate name
taken from the overlay mapping (the estate may call the shape `nas`
what it actually calls `truenas`), with the node's `source`
naming both owners (shape tree plus values directory). The rendered
copy is deliberately not a source: it is a build artifact of those
two, and pointing a source of record at a disposable artifact is the
drift the overlay contract exists to prevent.

## The curation file, precisely

One hand-edited JSON file with three buckets: **findings** (nodes
that have no source of record yet), **edges** (relationships no
source can see yet), and **flags** (questions that need a decision,
surfaced by the lint as NEEDS-DECISION). The rule that keeps it
honest: every entry is a debt with a name. When a fact earns a home
in a source of record, its curation entry is deleted in the same
change. The lint's curated-only check is the nag; a curation file
that stops shrinking is a second source of truth in the process of
being born, and that is the failure the design exists to prevent.

## Adoption, in one paragraph

Start with the example: copy `examples/` to a `graph/` directory in
your repo, point its inventory extractor at your real inventory (or
write your first extractor for whatever single source you most trust),
commit the artifacts next to the sources, and run the lint after
every build. Add sources as you trust them; add kinds as you need
them; wire a post-commit hook that rebuilds and lints when an input
changes (the audit then does not depend on anyone's memory); and only
when the paper audit has been useful for a while, add the live diff.
The tool is a few hundred lines on purpose; the discipline is the
product.
