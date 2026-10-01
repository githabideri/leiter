# The agent skills corpus

A skill is the interface between an agent and a domain: a description
that decides when the agent loads it, an instruction body the model
follows, and the scripts it calls to do real work. The corpus, the set
of skills an estate carries, is how capability gets versioned,
reviewed, and shared. This doc is the discipline that keeps the corpus
honest.

## Structure: the open standard

Skills follow the open [Agent Skills](https://agentskills.io) format,
so the same folder works across every agent that implements the
standard:

- **`SKILL.md`** with a frontmatter of `name` and `description`, then
  the body: when to use it, when *not* to, the workflow, the
  guardrails;
- **`scripts/`**: the executable tools the skill invokes;
- **`references/`**: deeper material, loaded only when needed.

The **description is the router**. It is the only part the agent sees
before loading, so it must say both when the skill applies and when it
does not ("not for: X, use Y instead"). A vague description is a skill
that never loads, or one that loads on the wrong task and wastes the
window.

## The contract style

Every publishable skill opens with a **you-bring-X** statement: what
it assumes (a machine, a config file, a credential, a service) versus
what it contains (the tooling, the instructions). The skill is a
pattern with a socket, not a product. The estate's own skills make the
same declaration to each other, which is why one folder per domain
works across hosts: the skill names the interface, the overlay
(§[overlay-contract](../overlay-contract.md)) supplies the values.

## Curation discipline

- **One coherent domain per folder.** Two skills covering the same
  domain is drift waiting to happen; the split is the bug. When a
  skill grows a second domain, it is time to split deliberately, with
  both descriptions saying which half they are.
- **Discovery by path, not by registry.** The agent runtime is
  configured with the directories that contain skills (one or more
  roots); there is no central index to keep in sync. A README serves
  as the corpus index for humans: one line per skill, what it covers,
  its status. The README indexes; the SKILL.md instructs. Neither
  duplicates the other.
- **A skill holds no values.** No secrets, no host facts, no site
  names. The moment a skill starts containing instance knowledge, it
  has become a second source of truth, and that is the failure the
  overlay contract exists to prevent.
- **Read whole, never fragment-grepped.** A skill is an instruction
  document: the decisive warnings sit in the middle of the file.
  Grep-with-a-filter loses them silently (the estate relearned this
  the expensive way: a "DO NOT USE" line that a fragment match never
  showed, and a live incident to discover it). Searching corpora is
  for grep; skills are read, like code you are about to modify.

## Lifecycle

Skills are born in one of two ways: **wrapping** (a CLI already works;
the skill adds the description, the guardrails, and the docs) or
**distilling** (a procedure got repeated enough to be worth writing
down). A skill retires when the domain disappears; its folder goes,
and the corpus index row is struck. The corpus table in the README
carries a status per skill (planned / growing / stable), so the shape
of the capability surface is visible at a glance.

## Failure modes

- **The vague description.** Never loads, or loads on the wrong
  task; the agent falls back to guessing and the skill might as well
  not exist.
- **The domain split.** Two skills, one reality; they diverge, and
  the agent picks the wrong half by description alone.
- **The skill that holds values.** Secrets or host facts inside a
  "portable" skill: the overlay contract violated from the inside, and
  the skill can no longer be published or shared.
- **The fragment reader.** An agent that greps a skill for one keyword
  inherits its procedure without its guardrails.
- **The duplicate runbook.** A skill that re-documents what the
  service docs already say; two copies, one will rot.

## How to adopt

Pick the domain you use most and wrap its CLI: one folder, a SKILL.md
with a sharp description and a you-bring-X contract, one script, one
row in the corpus index. Distill a second skill from a procedure you
caught yourself repeating. Resist adding a third skill for a domain
you already have one skill for; extend the first one. The corpus stays
small and sharp, or it stops being a corpus and becomes a pile.
