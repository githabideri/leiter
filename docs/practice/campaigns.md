# Campaigns

A **campaign** is a bounded work unit whose finish line is *saying
something*: a set of claims that must pass a gate before publication.
The claim is the deliverable; the work is how it gets proven.

The practice exists because of a recurring failure: one context designs
the work, runs it, writes the conclusion, and then defends its own
conclusion, so an unsourced number, a stale constraint, and a missing
primary source all get published, and the red-team function is performed
by the human operator reading the result. A benchmark campaign in the
private instance hit all three at once in 2026-10.

## The pattern

**One question, pre-registered claims, a gate before publication.**

The campaign has four durable surfaces, in a campaign root directory:

- **The charter**: the goal, the observable finish line, the scope
  edges, the non-goals, and a **primary-sources list that must be read
  before the plan is finalized**. The charter is approved by the human;
  that approval is the only permission the campaign needs until
  publication.
- **The claim table**: every claim the campaign is expected to
  produce, written *before the work runs*, each with a label and an
  evidence pointer:

  | Claim | Label | Evidence |
  |---|---|---|
  | … | `predicted (basis: …)` | - |
  | … | `measured` | `data/…` |
  | … | `cited (url)` | `https://…` / `git:repo:ref:path` |
  | … | `refuted` | `data/…` |

  Three rules do the work. *No number without a data file*: a
  `measured` label is a pointer, not a statement. *Predictions are
  registered before the work*, so the goalposts are fixed and a
  predicted negative is a first-class outcome, not a failure. *Labels
  are a closed vocabulary*: `predicted` must be resolved to
  `measured` / `refuted` / `not-established` before anything is
  publishable.
- **The constraint ledger**: a *standing* file (not per-campaign) of
  the estate's working constraints. Each entry carries the **original
  wording, who said it, when, and the current mitigation state**. The
  ledger is human-owned: agents may propose an edit, only the human
  merges it. A change in mitigation state (a guard added, a box
  resized, a rule re-scoped) triggers **re-derivation** of the
  boundary before acting, because constraints degrade in transit,
  always in the direction of *harder*.
- **The frozen archive**: at the end, the root is marked frozen; the
  claims table, the data files, and the verdicts are kept as evidence.
  Corrections to anything published are **appended, never rewritten**
  (see `doc-state.md`).

The campaign root, not the session, is what makes it durable. The
coordinator's sidecar points at the root; a dead or compacted session
resumes by reading it (see `sessions-and-memory.md`).

## The roles (the tandem)

Three roles, each a separate context, plus the human at the two gates:

| Role | Owns | May not |
|---|---|---|
| **Coordinator** | the charter, the claim table, the dispatch | write a number without a data file; verify its own claims; harden or soften a constraint |
| **Executor** | one bounded brief; raw data; failures; file pointers | draw conclusions; amend its brief (it may *ask*); touch the no-touch list |
| **Verifier** | the verdict file | see the coordinator's reasoning; use open-ended verdicts |

The verifier gets a **fresh context** holding only the claim table,
the data files, and the draft, not the reasoning that produced the
change, so it evaluates the result on its own terms. This is the one
place where a role hierarchy is justified rather than bureaucracy: a
context that shares the generator's history has *correlated* errors
by construction, so it cannot falsify what it produced. Everything
else about the roles is deliberately un-bureaucratic: depth-1
delegation (executors don't re-delegate), no standing supervisor
across campaigns, one bounded brief per executor.

## The gates, in order

1. **The mechanical gate**: a small script (`claimgate` in the
   `tandem` skill) checks the table the way a compiler checks types:
   it parses, requires a data file for every `measured` / `refuted`
   row, resolves every `cited` pointer (URL or `git:repo:ref:path`),
   and rejects any unresolved `predicted`. Red lights are a list, not
   a feeling. *Nothing moves while a gate is red.*
2. **The verifier**: per-claim verdicts in a closed vocabulary:
   `pass` or `fail` plus a one-line reason; a separate concerns
   section that is explicitly advisory (a reviewer prompted to find
   gaps will find gaps in sound work: the brief says *flag only what
   affects the claims*).
3. **The human**: publication is user-only, always.

## How it relates to the rest

- **vs. a relay**: a relay is a *chain* that carries long
  implementation work (fresh leg, compact baton, no standing
  coordinator); a campaign is a *committee* that gates claims. They
  compose: a long campaign's legs can ride relays, and the campaign
  ends where the relay has no business: at the verdict and the
  publication gate.
- **vs. measurement platforms**: a purpose-built measurement platform
  (a frozen spec, a verdict engine, a preflight table, a qualify
  matrix, an executor runbook, an ingestion step) is the flagship
  *specialization* of this shape: its verdict taxonomy is a claim
  table, its preflight is a `cited` check against the expected, its
  ingestion is the publication gate. The generic gate is what that
  discipline becomes when the claims aren't benchmark numbers.
- **vs. the sidecar**: the sidecar triple is the session's state; the
  campaign root is the campaign's state; the sidecar carries a
  pointer to the root.

## Failure modes

- **The constraint phone-game**: a soft instruction ("that does not
  matter now") re-enters a later context as an absolute exclusion, and
  nobody re-derives the boundary when the mitigation changes. Fix: the
  ledger keeps the original wording and a re-derivation trigger.
- **Self-verification**: the context that produced the claim
  adjudicates it. Fix: the verifier is a separate context, never the
  coordinator, and never the executor.
- **Moving the goalposts**: the question is re-defined after the
  results land. Fix: predictions registered before the work.
- **The telephone game**: conclusions travel as summaries through
  intermediaries and lose fidelity. Fix: artifacts live on disk; only
  pointers travel.
- **The gap-reviewer**: the verifier reports findings in sound work
  because it was asked to find problems. Fix: closed verdict
  vocabulary + "flag only what affects the claims".
- **Coordinator creep**: the coordinator becomes a standing
  supervisor across campaigns and the committee degrades into an org
  chart. Fix: the coordinator is per-campaign and dies with the
  archive.

## Adopting it

Start with the claim table and the mechanical gate: they pay for
themselves on the next report you publish, with no role ceremony at
all. Add the verifier when a campaign's value is high enough to pay
for a third context. Add the constraint ledger the first time a
constraint survives a session handoff. The charter is just discipline
made visible.
