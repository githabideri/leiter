---
name: tandem
description: >
  "@@TANDEM_DESCRIPTION@@"
---

# Tandem

The doctrine (why each rule exists, the failure modes) is in
[`../../docs/practice/campaigns.md`](../../docs/practice/campaigns.md).
This skill is the operating side. You bring: a session harness with a
per-session sidecar (or an equivalent durable note per session), git,
and a sanitizer for whatever you publish (or accept that the gate
checks citations but not secrets).

This skill contains:

- `scripts/claimgate`: the mechanical gate (standard-library Python,
  one file): parses the campaign's `claims.md`, enforces the label
  vocabulary, checks every evidence pointer (data files exist and are
  non-empty; URLs resolve; `git:repo:ref:path` exists at that ref),
  rejects unresolved `predicted` rows. Exit 0/1; `--json` for machine
  use; `--no-net` for offline runs (URL checks reported as skipped).
- `examples/minicampaign/`: a runnable miniature: a two-claim
  campaign with one measured data file, one good citation, one
  deliberately broken row set, and a `run.sh` that shows both the red
  and the green run.
- `references/briefs.md`: the role briefs: coordinator, executor,
  verifier, each as a paste-ready block with its may/may-not column.

## The claim table format

`claims.md` in the campaign root. A markdown table, one claim per row:

```
| # | Claim | Label | Evidence |
|---|---|---|---|
| C1 | <the claim, plain> | measured | data/x.log |
| C2 | <the claim> | cited | https://example.org/doc |
| C3 | <the claim> | git | git:./repo:main:docs/x.md |
| C4 | <the claim> | predicted (basis: wiki) | - |
```

Label lifecycle: `predicted` → `measured` | `refuted` |
`not-established`. A row leaves `predicted` only when evidence says
so. `cited` stays `cited` (its evidence is the source).

## The constraint ledger

A standing file (its location is yours; in a repo estate: versioned
with the docs, owned by the human). One entry per constraint:

```
| Constraint | Original wording | Said by / when | Mitigation state | Re-derive when |
|---|---|---|---|---|
| unbounded RAM pinning | "that does not matter now" | human, 2026-09 | hard cgroup cap in place | mitigation changed; box changed |
```

Rules: agents *propose* edits (write the proposed row into the
campaign's `progress` note); only the human merges into the ledger;
any change in the mitigation column forces a re-derivation question
to the human before the next related action. The `claimgate` gate
takes an optional ledger path and warns on entries whose
re-derive-when condition appears met by the campaign's own notes.

## Opening a campaign

When invoked (a `/campaign <goal>` prompt template is the usual
trigger; a plain "open a campaign" message works too):

1. Create the campaign root: `charter.md`, `claims.md`,
   `constraints.md` (copy of the relevant ledger entries), `data/`,
   `verdicts/`, `progress.md`.
2. Draft `charter.md`: goal, observable finish line, scope edges,
   non-goals, **primary-sources list (read before the plan is
   finalized)**.
3. Draft `claims.md`: every claim the campaign is expected to
   produce, tagged `predicted` with its basis. Prior discussion
   brought by the human (a pasted chat with another model included)
   is a *hypothesis source*: its claims enter as
   `predicted (basis: human-provided discussion)` and must be
   re-grounded in primary sources before they can become `cited`.
4. Show the drafts and ask: **Approve / Revise / Don't start.**
   Silence and prior enthusiasm are not approval.

Then you are the coordinator, and between approval and the
publication question the human stays out of the loop:

1. **Dispatch the lanes.** One child context per lane in the
   charter, the executor brief as its whole first message. Where
   the harness tracks children (pi-web does: `spawn_subsession`),
   the coordinator spawns them itself and yields its own slot at
   the join point; where it does not, the human opens one session
   per lane with the brief pasted in, and the loop degrades to
   human-carried legs (still gated, just slower).
2. **Depth-1 is structural, not a rule.** A child carries no
   dispatch capability: tracked children get no spawn tools at
   all, and the executor brief forbids re-dispatch even where the
   harness does not enforce it. A blocked child stops, logs, and
   ends (the stop rule); it does not ask the human. You are the
   single question point to the human: read the stop log, resolve
   what the charter and the constraint ledger answer by
   re-dispatching a corrected brief, and ask the human once, with
   a recommendation and each option labelled by what it touches
   (especially which options change a human-owned constraint). A
   child's direct ask is reserved for imminent danger; a routine
   question that reaches the human is a protocol violation you
   note in the progress file.
3. **Ingest data, not summaries.** When a lane ends, take its data
   files and failure note into the campaign root, re-tag the table
   from the files, re-run `claimgate`. Repeat per wave if the
   charter has more than one. A claim row is a **copy** of what the
   files say; a number that cannot be copied from a cited file does
   not enter the table (the provenance check treats every claim
   number otherwise).
4. **Gate order, unchanged:** `claimgate` green → one fresh
   verifier context → human publication approval. The human
   appears exactly twice: approving the drafts, deciding on
   publication.

## The briefs

Full text in [`references/briefs.md`](references/briefs.md); the
load-bearing lines:

- **Executor**: one bounded brief; first line date-stamped; a
  no-touch list; a stop rule (first boundary-adjacent need → stop,
  log, end; that is how it asks, since a direct ask to the human
  is reserved for imminent danger); reports raw data + failures +
  file pointers; **no conclusions**; may ask about its brief (via
  the stop log), never amends it.
- **Verifier**: fresh context; receives only the claim table, the
  data files, and the draft; per-claim `pass`/`fail` + one-line
  reason in `verdicts/verdict.md`; a separate advisory concerns
  section; *flag only what affects the claims*.
- **Coordinator**: owns charter + table; no number without a data
  file; no self-verification; the single question point to the
  human (child questions arrive as stop logs, never raw);
  per-campaign (dies with the archive).

## Probe artifacts (measured regimes)

A lane that asserts *where bytes live* or *where I/O goes* produces
the two artifacts the claim then copies from (both cited in the
claim's evidence column):

- `memmap-<probe>.txt` — the loaded artifacts with byte sizes (from
  the sha256 freeze); the measured container peaks for the run
  (cgroup `memory.peak`, VRAM peak, page-cache/ARC cap); the
  residency identity `Σ loaded bytes = anon (cgroup) +
  file-backed resident + GPU + still on disk` with an **explicit
  residual line**; and a `capacity-<probe>.tsv` (key/value bytes)
  holding the same numbers for the gate.
- `pidio-<probe>.csv` — `/proc/<pid>/io` (`read_bytes`, `rchar`)
  at ≤ 2 s cadence over the whole probe, with prefill/decode window
  markers taken from the request timeline.

Why these two exist: page-fault I/O is invisible to syscall tracing,
and "the model is in RAM" is an arithmetic statement, not an
observation. `claimgate` enforces the matching rules on
`measured`/`refuted` rows (disable with `--no-narrative` for
pre-v2 campaigns): a claim of **no/zero file I/O** fails unless a
storage-bytes counter (`read_bytes`, `rchar`, block-device sectors,
iostat) appears in the cited evidence — a strace pread count is not
one; a claim that an object **is / fits / lives entirely in
RAM/VRAM** fails unless the capacity manifest's measured container
sum is ≥ the object size within `--tolerance` (default 5%).

## Sidecar discipline (compaction safety)

Compaction is a lossy channel: value copies drift, pointers do not.
Session sidecars therefore carry, next to every number they mention,
the **reference** — `path:sha256` (hash of the file, not the line) —
not a restatement of the value. On rehydration: read the sidecar,
then **spot-verify two numbers against the referenced files** before
repeating any of them; a number not in the file means the summary
drifted — say so and re-copy from the file. This is what turns "I
remember 35.4 GiB" into "the sampler says 39.8, and the pointer
catches the copy" instead of the other way around.

## Publication

Gate order is not negotiable: mechanical gate green → verifier
verdicts in → human approval. The mechanical gate checks more than
file existence: it also checks claim *prose* against its evidence
(the negative-I/O method whitelist, the residency arithmetic, and
warning-only numeric provenance — see above). After publication,
corrections are **appended** to the published document, never
rewritten. The campaign root is marked frozen (a `FROZEN` header in
`charter.md`) and kept.

@@TANDEM_ESTATE@@
