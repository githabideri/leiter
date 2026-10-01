# Sessions and memory

An agent session is the estate's working memory, and it is ephemeral by
construction: the window fills, the process dies, the conversation ends.
Anything that matters therefore has to be externalized, and the estate
does that at three levels, each more durable and more compressed than
the last.

## The three levels

| Level | What it is | Lifetime | Audience |
|---|---|---|---|
| the transcript | the full JSONL record of a session: every message, tool call, result | append-only, kept forever, redacted on commit | the audit trail |
| the sidecar | one small file per session (plan, findings, progress), written *during* the session by the agent itself | lives as long as the task | the next session, the human |
| the docs | the curated, condensed layer (inventory, service notes, reports) | as long as the estate | everyone, all the time |

The flow runs one way: the transcript records everything, the sidecar
distills what the session learned, the docs absorb what the estate
must remember. The sidecar is the hinge. A session that ends without
updating its sidecar has done useful work and left no trace of it.

## Naming

Sessions get stable, sortable names: the local date plus a per-day
sequence (`YYYY-MM-DD_NNN`), chosen at creation, never reused. The same
name appears in the transcript, the sidecar, the memory index, and any
doc that refers to the work. Discoverability is a naming property: a
session you cannot find by name cannot be recalled.

## The small-window problem

Long sessions get compacted: the old part of the transcript is replaced
by a summary entry, and the agent continues from that. This works well
for models with large windows and is harmful for small ones, which lose
their own working state to compaction mid-task. The estate's answer is
a mechanism, not a prompt: an extension scaffolds the sidecar files at
session bootstrap (the small model reliably reads a pointer but
unreliably creates files under task pressure, so the files must exist
before the model needs them) and re-injects a digest of the sidecar
before each step. On large-window models the mechanism stays fully
inert. Whatever model the estate runs on, the sidecar gets written.

## The memory layer

Over the closed sessions sits a searchable index: a digest of each
session (what it did, what it decided, where it left off), searched by
terms. This is the deep memory, and it has a strict read order:

1. **the curated docs first.** They are condensed and maintained, and
   the answer is usually there;
2. **the session index second**, for decisions and handoffs the docs
   do not carry ("which session fixed X?");
3. **the raw transcript last**, for the actual words, including of a
   still-active session (useful for re-anchoring after a long detour).

Mining raw transcripts before reading the docs is slow, noisy, and the
fastest way to re-derive what is already written down.

## Redaction

The only way secrets enter the record is through the transcript: the
agent echoes a credential into a command. The countermeasure is a
mechanical redaction pass that runs on every commit, sweeping the logs
against patterns and against the actual values in the environment
files. The control is the hook, not the model's good behavior.

## Failure modes

- **Knowledge dies with the session.** No sidecar, no write-back. The
  next session re-derives it, and the estate learns nothing twice.
- **Sidecars that never get created.** The pointer is read, the files
  are never written under task pressure. Hence scaffolding at
  bootstrap: the mechanism must not depend on the model's
  reliability.
- **The one giant session.** A single session that does everything
  concentrates all its knowledge in one window; when that window is
  compacted or lost, everything goes. Small sessions with explicit
  handoffs (the sidecar *is* the handoff) survive.
- **Memory read before docs.** The deep layer answers slowly and
  imprecisely; the curated layer answers correctly. The order is part
  of the discipline.
- **A redaction hole.** One leaked token in one log line invalidates
  the whole scheme; the sweep must cover values, not just shapes.

## How to adopt

Start with one session directory, the date-plus-sequence naming, and
one sidecar template (plan / findings / progress). Add the
bootstrap-scaffolding extension when you run small-window models. Add
the digest index when the closed-session count passes what one person
can remember. Add the redaction hook on the very first day, because
the first leak is the one that teaches you the cost.
