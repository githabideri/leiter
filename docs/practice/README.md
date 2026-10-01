# practice/

Operating doctrine: how an agent-run homelab is *run* day to day. This is
the layer that is hardest to get from reading other people's configs: the procedures and
guardrails, written as reusable patterns in role terms rather than one
estate's addresses.

Each doc answers one operational question. Status is honest: **stable**
means used in the private instance for months; **growing** means written
from practice but still being tested; **planned** means the pattern is real
in the private instance and not yet written up.

| Doc | The question it answers | Status |
|---|---|---|
| *doc-state.md* | How does documentation double as the system's state, and how do you keep it from rotting? (State vs. actions, single-source-of-record, frozen reports, the session layer.) | planned |
| *component-graph.md* | How do you keep a machine-readable map of the whole estate, and use it to find staleness and answer "what breaks if I change X"? (The graph discipline: derive, don't duplicate; lint; blast radius; the staleness audit as a standing practice.) | planned |
| *sessions-and-memory.md* | How does a fleet of agent sessions stay knowable? (Session naming, sidecar summaries, searchable memory over past sessions, redaction on commit.) | planned |
| *secrets.md* | Where do secrets live, how do tools get them without ever seeing them in a doc, and how do you redact a log that already leaked one? (Schema-declared env files, injection at run time, the redaction pipeline.) | planned |
| *change-governance.md* | What may an agent change on its own, what needs a human, and how does a change stay attributable? (The three-zone model: free parameters / repo-owned plumbing / visible provenance; the concurrency registry; verification vocabulary.) | planned |
| *agent-skills-corpus.md* | How do you build and keep a corpus of skills that actually gets used? (The trigger-as-description discipline, the token budget, splitting vs. growing, the bundle layout; cross-ref `../skills/README.md`.) | growing |

## Conventions for writing here

- **Pattern first, example second.** Lead with the rule and *why*; follow
  with the smallest example that makes it concrete, in role terms.
- **Every doc names its failure mode.** The practice exists because
  something broke or rotted; say what, in one line.
- **No live values.** Addresses, ids, names, secrets: tokens or role
  terms, per [../overlay-contract.md](../overlay-contract.md).
- **Supersede, don't rewrite.** If a pattern changes, the old version gets
  a "superseded by" note, not an edit.
