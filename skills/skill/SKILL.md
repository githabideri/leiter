---
name: skill
description: >-
  Write a new agent skill well: the open-standard bundle layout
  (SKILL.md + references/ + scripts/, one canonical location per skill),
  naming the skill the way the user calls the domain, and the
  description-as-trigger doctrine — 300-600 chars of user vocabulary, the
  per-session token budget of the whole corpus (measured, not estimated),
  the anti-ratchet rule, exclusion pointers to siblings, progressive
  disclosure into references/ named by knowledge domain, facts vs
  behavior, and the anti-pattern list. Use for "create a skill", "new
  skill for X", "my skill never triggers", "the description is too
  long", "split this skill", "skill conventions". Not for writing
  skill *content* about a domain (that's the domain skill itself).
---

# Skill (Meta) Skill

How to add a new skill to a corpus of agent skills that follows the
open standard (a directory per skill: `SKILL.md` + optional
`references/`, `scripts/`, `assets/`, discovered by whatever harness the
corpus is plugged into).

## Layout: one canonical location

```
<skills-root>/<name>/SKILL.md   ← source of truth AND discovery target
<skills-root>/<name>/references/  ← on-demand knowledge (see below)
<skills-root>/<name>/scripts/    ← executable tools the skill owns
```

The skills root is configured by the harness (in pi: the `skills` array
in `.pi/settings.json`, relative to the project's `.pi/` dir). No
symlinks, no copies, no deploy step: a skill that exists at the root is
discovered. **Root order matters** — with two roots offering the same
name, the first-listed root wins; keep names unique across roots on
purpose (shadowing is a feature, e.g. an estate-specific skill shadowing
a generic one).

## Naming

- Lowercase, hyphens only, max 64 chars, must match the directory.
- **Name it the way the user calls the domain** — short and plain
  (`nix`, `dns`, `nas`), not the implementation
  (`nixos-provisioning`). The name is the word that gets typed and
  triggered. If the skill covers a sub-domain people name differently,
  that name belongs in the *description* (or a split).

## The description is a trigger, not a caption

The description is the skill's recall surface and the only skill text
injected into *every* session. Bodies cost tokens only when the skill
actually loads. Consequences:

- **The corpus has a token budget.** Measure it before growing one:

  ```bash
  python3 -c 'import yaml,glob,re
  t=sum(len(str(yaml.safe_load(re.match(r"^---\n(.*?)\n---",open(f).read(),re.S).group(1)).get("description","")))
        for f in glob.glob("<skills-root>/*/SKILL.md"))
  print(t,"chars ≈",t//4,"tokens/session")'
  ```

- **300–600 chars is the design point; 1024 is the failure condition,
  not the goal.** A clause/sentence list, not an essay. Validate that the
  frontmatter actually parses after editing — an unquoted `description:
  a: b` is a YAML bomb; use the `>-` folded form for multi-line.
- **Lead with the user's vocabulary, not the skill name.** Users say
  "check the backup / restore", never "run the backup-server skill". If a
  task names a sub-domain differently than the skill does, that name must
  appear or the skill never fires.
- **Name the concrete nouns** a task will contain: tools, hosts,
  subsystems, task phrases, synonyms.
- **Trigger only — doctrine belongs in the body.** Reasons, lessons,
  guardrail details, command specifics: body. If a description sentence
  explains a *why*, move it to the body and leave a two-word pointer.
- **Anti-ratchet: a missed trigger is fixed with a few precise
  user-vocabulary words — never with a paragraph.** Every future session
  pays for a one-time fix. If a skill's true breadth no longer fits in
  600 chars, the answer is a *split into two skills* (or a pointer to a
  doc), not trigger bloat.
- **Close with an exclusion pointer** to the sibling that owns a
  confusingly adjacent case ("Not for: …").

## Progressive disclosure (SKILL.md + references/)

A skill is a **control plane + on-demand knowledge**, not one big file:

```
<name>/
├── SKILL.md          # control plane: what it is · invariants & safety
│                     #   rules · decision tree (which task → which
│                     #   reference) · the core workflow · verification
│                     #   · pointers (TOC of references)
└── references/
    └── <area>.md     # one coherent knowledge area per file — read only
                     #   when the task needs it
```

Rules:

- **SKILL.md is read on every trigger** → keep only what every task
  needs. Dense procedures, command catalogs, pitfall/scar tissue,
  verified negative knowledge ("do not re-explore") belong in references.
- **One coherent knowledge area per reference**, one level deep, TOC when
  a reference grows past ~100 lines. **Name files by knowledge domain,
  not content type** (`install-stick.md`, `building.md`,
  `pins-and-quirks.md`) — `landmines.md` / `gotchas.md` / `notes.md` are
  anti-patterns: the name must be a *topic a task routes to*, so the
  agent picks the right file without opening the others.
- **No volatile state in references** (versions, "current models", dated
  snapshots). Volatile facts go to a state file / inventory / per-service
  doc that the reference links to. A dated snapshot that must live in a
  reference gets an explicit "last verified … — re-verify before
  relying" line.
- **Facts vs behavior:** machine-specific values (hosts, IPs, ids,
  versions) live in the estate's state documents (link, don't restate);
  skills own *behavior* (how, in what order, what not to do).
- **SKILL.md must contain a "when to read which reference" map** so the
  agent can route without reading everything.
- Start flat (single SKILL.md). Split when the file mixes more than one
  knowledge area or passes ~200 lines — not before (a premature
  multi-reference skill is just indirection for no gain).

## Checklist

- [ ] `<skills-root>/<name>/SKILL.md` exists; frontmatter parses; `name`
      matches the directory
- [ ] description ≤ 600 chars (measured), corpus total re-checked after
      the edit
- [ ] description leads with user vocabulary, names concrete nouns,
      closes with an exclusion pointer
- [ ] if split: every `references/*.md` is a coherent area, one level
      deep, no volatile state, listed in SKILL.md's routing map
- [ ] no state facts that belong in inventory/config documents
- [ ] committed at the canonical location only

## Anti-Patterns

- ❌ a copy of a SKILL.md anywhere else (drifts from truth)
- ❌ a SKILL.md under a scripts/ or tools/ dir (wrong audience, not
      discovered)
- ❌ a description that omits the words users actually type — a skill
      named `X` that also does `Y` but never mentions `Y` never fires on
      `Y` tasks
- ❌ fixing a trigger miss by *growing* the description (ratchet) —
      compress, move doctrine to the body, or split
- ❌ `notes.md` / `gotchas.md` as reference names
- ❌ volatile state (versions, current values) frozen into a reference
- ❌ name collisions across roots that aren't deliberate shadowing
