# Documentation as state

In an agent-run estate, the documentation is not a report *about* the
system. It is the state the system runs on. A fresh agent session has
no memory of your estate; the only way it learns anything is by
reading the docs. And it will believe what it reads, then act on it.
The quality of the docs is therefore a reliability property of the
estate, not a hygiene one.

This doc is the discipline that keeps that state from rotting.

## The two kinds of documents

**State docs** say what *is*: inventories, per-service notes,
runbooks. **Action lists** say what *should happen*: the TODO file.
They must never be mixed. A plan written into a state doc gets read as
fact. A description written into an action list gets acted on until
someone notices it already happened. When a document starts
answering both questions, split it.

## One fact, one home

Every kind of fact has exactly one source of record, and everything
else links to it:

| Fact kind | Home |
|---|---|
| hosts, guests, IPs, status | the inventory |
| a service: what it is, where it runs, how to run it | its per-service directory |
| a capability the agent can use | the skill folder |
| an open action item | the action list |
| what happened on a given day | the dated report (frozen) and the session logs (append-only) |

The moment a fact is comfortable in two places, the copies will
disagree, and the agent will read whichever copy it finds first. The
test is mechanical: for any sentence in the corpus, there is exactly
one place where it is authoritative.

## Living vs. frozen

- **Living docs** (inventories, overviews, runbooks) are updated in
  place; the newest true statement replaces the older one.
- **Dated reports are frozen.** They record the world as it was on
  that day. When the world changes, you write a new report (or an
  addendum) and point forward with a "superseded" note. Rewriting a
  frozen report is how history starts lying, and an agent that
  reconstructs the past from reports will build a false present.
- **Session logs are append-only evidence.** Every agent session is
  recorded, and on commit the logs go through an automatic redaction
  pass so secrets never enter history. A searchable index over old
  sessions is the deeper memory layer: when the curated docs do not
  have the answer, you search what was decided before.

## Verification is a level, not a word

"Works" is a lie unless it says *at which level* it works:

| Level | Meaning |
|---|---|
| implemented | code written, unverified |
| locally verified | unit tests and build pass |
| live verified | integration or smoke tests pass against the real thing |
| remotely verified | it works in production, from where it is actually used |

Every claim carries its level, explicitly or by context, and the
level never moves up without evidence. This is also the contract
between sessions: a session that ends with "it works" has told you
nothing.

## The write-back loop

The loop that makes the whole thing a system: the agent reads state,
acts, and **writes the result back into the state docs in the same
session**. The new guest goes into the inventory. The incident goes
into a report. The decision goes into a note. An action that is not
written back vanishes when the session ends, because the estate's
memory is the repository, not the terminal.

## Failure modes

- **Docs as autopsy.** Writing only when something breaks. The
  resulting corpus documents the broken twenty percent, and the
  agent's model of the healthy eighty percent is guesswork.
- **The two-copies problem.** A fact in the overview and in the
  runbook, drifting apart over six months. The second copy is always
  the one that gets read.
- **State leaking into action lists** (or vice versa). The rot is
  invisible until an agent follows a five-month-old plan that already
  happened.
- **Rewriting the frozen.** Editing last month's report because it is
  "a bit out of date". Supersede; do not edit.
- **"Works" without a level.** The most expensive sentence in the
  corpus.

## How to adopt

You do not need the whole machinery on day one. Start with: one
inventory file, one directory per service with an overview in it, one
action list, and the frozen-report rule, which costs nothing. Add
session sidecars and a memory index when the agent fleet grows past
what one person can remember. The verification vocabulary comes with
the first incident that "worked"; you will recognize it when it
happens.
