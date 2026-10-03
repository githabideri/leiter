---
name: mermaid
description: >-
  "@@MERMAID_DESCRIPTION@@"
---

# Mermaid

Diagrams for docs, reports, and plans, rendered where they are actually
read: the web UI of your doc host (Gitea and the like render mermaid in
the file view) and your local markdown app (Obsidian on the laptop).

**Data hygiene.** Diagrams are rendered by *your* renderers, never public
ones: never send diagram content carrying internal identifiers (hostnames,
IPs, container numbers) to a public render service (mermaid.ink etc.).
Graph data files stay in the private repo. If your repo runs a redactor
with a hex-string heuristic, store content hashes with a `sha256:`
prefix, not bare 64-hex strings (the heuristic mangles them; this has
burned a first graph commit).

## Design contract (read before drawing anything)

1. **Contract first.** One sentence: *"this diagram explains X so the
   reader can decide Y."* More than one verb in that sentence → split
   into several diagrams.
2. **Isomorphism test.** Remove the text: if the structure alone does not
   carry the point, redesign the structure. Adding labels will not fix
   it.
3. **One meaning per visual channel.** Shape = kind of thing; colour =
   state/health. Never encode two facts in one channel.
4. **Density by audience.** Overview/exec: 5-7 nodes; technical docs:
   10-15; reference: 15-20, then split. Maximum two levels of nesting.
5. **Edge labels name observable relations** (`calls`, `fine_tuned_on`,
   `runs_on`), never vague verbs ("uses", "processes"). Several
   same-type edges into the same target: label only the first (dedupe
   prevents label collisions).
6. **Tokens.** A diagram carries 3-6x the meaning per token of prose, and
   small models read mermaid semantically. Prefer diagrams over prose for
   *structure* in skills, reports, and plans.

## Workflow (ad-hoc diagram)

1. State the contract (one sentence) and pick the type: flowchart
   (process/dependency), C4 (service/component map), block (freeform
   architecture).
2. Write it with the theme-safe palette (`references/theming.md`): a
   `base`-theme init block plus explicit `color:` on every classDef.
   Shape = kind, colour = state.
3. Run the breaker-check: `scripts/mermaid-check` (offline lint of the
   table in `references/renderer-compat.md`).
4. Commit, then **visually check in the consuming renderer** (the host's
   rendered/preview view, hard-refreshing after push). If the host fails
   to parse, drop to the version-safe floor in `references/theming.md`.

## When the diagram is generated

If the diagram is a projection of a data file (a corpus, an estate, a
dependency set), do not hand-draw it: generate it and keep the data as
the source of truth. The `component-graph` skill is the pattern
(extractors as contract, lint as staleness audit, the diagram a
generated file that is committed next to its data).

## Routing

| if the task is... | read |
|---|---|
| writing/adjusting the init block, choosing palettes or classDefs | `references/theming.md` |
| a diagram won't parse on a host; version-safe syntax; validation | `references/renderer-compat.md` |
| offline lint of an existing block or file | `scripts/mermaid-check` |

---

<!--
  Estate instance section. An estate that maintains a mapping for this
  skill (the overlay contract: ../docs/overlay-contract.md) renders its
  instance content -- machines, paths, what this fleet has hit -- at
  this spot, at deploy time. The raw shape ends here.
-->
@@MERMAID_ESTATE@@
