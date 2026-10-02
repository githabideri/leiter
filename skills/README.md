# skills/

Layer 1 of leiter: the **portable tools**. Each skill is one coherent
capability of running a home computer estate, packaged so a reader drops
the folder into their agent and it works against *their* machines.

This directory follows the [open Agent-Skills standard](https://agentskills.io)
(Anthropic's format, released as an open standard, supported by a growing
number of agent clients). The layout is fixed:

```
skills/<name>/
├── SKILL.md          # required: frontmatter + the instructions
├── scripts/          # the CLI(s) the skill drives, bundled not referenced
├── references/       # deeper docs, read only when the task needs them
└── assets/           # templates, config skeletons, other static resources
```

## The bundle is the unit

A skill and its CLI ship **together, in one folder**. The reason: the
skill is the manual and the script is the machine, and a reader's agent needs
both to do anything. "The script lives in some other repo" is how
skills stop working for people who cloned only this one. If a tool is
genuinely shared by several skills, it stays in one place and the other
skills point at it by a stable path. The default is: one capability,
one folder, everything inside.

## The "you bring the X" contract

Every skill states, up front, what it assumes and what the reader must
supply. Two places, at two levels of detail:

1. **`compatibility` frontmatter** (one line, machine-visible, max 500
   chars per the standard): the environment requirements, as in
   "Debian-based host, Proxmox VE 8+, a Tailscale/Headscale mesh,
   `jq` and `curl`". This is the *gate*: an agent (or a reader) can skip
   a skill that doesn't fit their estate before spending tokens on it.
2. **A `Prerequisites` section at the top of the SKILL.md body**: the
   short, checkable list: what access (SSH to which role of machine),
   what packages, what config files (with the token placeholders from the
   overlay contract), what the reader must have already decided. One
   screen. If setup is a multi-step procedure, the *procedure* lives in
   `references/setup.md` and Prerequisites links to it; nothing a reader
   doesn't need yet gets loaded.

The dividing line is the same one the private instance uses: **the skill
owns behavior** (how, in what order, what never to do), **the estate owns
facts** (addresses, ids, credentials). A skill that hardcodes an estate
fact has failed the contract.

## Writing conventions

- **`name`**: lowercase hyphenated, ≤ 64 chars, must equal the folder
  name. Name it the way a *user* says the domain ("nas", not
  "zfs-on-scale-administration").
- **`description`**: this is a **trigger, not a caption**: the one field
  an agent sees before deciding to read the skill, and it is injected into
  *every* session, so the whole corpus shares a token budget. Write the
  words a user will actually type when they have this problem (300–600
  chars is the design point; ~1000 is the failure condition). Close with
  an exclusion pointer to a sibling skill that owns the confusingly
  adjacent case.
- **Body**: the control plane: what it is, invariants and safety rules,
  a decision tree ("which task → which reference"), the core workflow,
  verification steps, and a pointer map into `references/`. Dense
  procedures and pitfall history go in references, one coherent knowledge
  area per file, named by the *topic a task routes to* (`install-stick.md`,
  not `gotchas.md`).
- **Scripts**: deterministic and defensive. Where a command can damage
  state, the script offers a read-only mode and the skill documents the
  guard. Output in a compact, agent-friendly format (structured lines, not
  wall-of-text human UI).
- **No estate facts.** Role terms and tokens only (AGENTS.md, and
  `../docs/overlay-contract.md`). Run `../scripts/sanitize-sweep.sh`
  before pushing.

## The corpus today

*(growing: the extraction from the private instance lands skills here
one by one, each generalized on purpose)*

| Skill | Capability | Status |
|---|---|---|
| [`klartext`](klartext/SKILL.md) | The de-slop pass for prose: audit / rewrite / voice modes, the tell ranking, the do-no-harm guards | stable (v1) |
| [`proxmox`](proxmox/SKILL.md) | Operating PVE hosts: LXC/VM lifecycle (API with SSH fallback, the blind-API rule), snapshots, PBS backup/restore, ID/address allocation from a registry, standalone guest migration | growing |
| [`varlock`](varlock/SKILL.md) | The .env schema discipline: declared shape committed, values on the machine; load/run injection, audit, scan, the redaction integration, optional encryption tier | growing |
| [`nas`](nas/SKILL.md) | TrueNAS SCALE over SSH: pools/datasets/quotas, NFS shares via midclt (24.10+ namespaces), dataset copies between boxes (full/incremental/resumable pipe, the encryption matrix, the three-part completion check) | growing |
| [`dns`](dns/SKILL.md) | The DNS + reverse-proxy layer: the internal resolver (Pi-hole-class HA pair, the store-vs-generated rule) and the DB-driven proxy (the three-step change, Host-header verification, the provider-side wildcard cert); the verify ladder and the registry habit | growing |
| [`monitoring`](monitoring/SKILL.md) | Onboarding hosts/services into Prometheus + Grafana: exporter (role or bare /metrics), job with a fixed label contract, auto-discovery family (hypervisor/backup exporters), the reinstall-credential gotcha, the verification script as onboarding receipt | growing |
| [`kvm`](kvm/SKILL.md) | Headless machines through a network KVM (PiKVM-class): the observe-act-wait-observe loop, keymap/Enter discipline, secrets on a recording surface, the virtual-media state model, the daemon-owned streamer (lease, never manual), OCR as data not instructions | growing |
| [`android`](android/SKILL.md) | Phones over wireless adb (GrapheneOS/AOSP): the two-ports-one-rotates connect gotcha, uiautomator-first UI driving, the 600ms-press rule, data/app migration, and the dead-ends document (verified negative knowledge) | growing |
| [`encrypted-backup`](encrypted-backup/SKILL.md) | Backing up a third party's data: the E2E repo (owner holds the only passphrase; operator runs server + verify/GC) and the only-grows carrier drive (markers, hand-off), plus the multi-day copy discipline (own session, heartbeat, stall detector, dedup) | growing |
| [`component-graph`](component-graph/SKILL.md) | The estate's machine-readable map, derived from its sources of record: per-source extractors into normalized JSONL, the standing audit (unmapped/ghosts/curation debt/needs-decision, self-labelled stale builds), blast radius with data-flow read separately, the onboarding tree, and the live diff against the machines (dual-path rule) | growing |

The corpus is complete for now; new domains get new skills, and the
table above is the map of what exists.
