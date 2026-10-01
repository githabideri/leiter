# Leiter

> Agent-run home computing.

**Leiter** — German: *ladder* / *conductor* / *the one who leads*. Pick your
favourite. All three are right.

Leiter is a public companion to a private homelab that it grew out of. It is
**not** a floor plan of that homelab: it contains no machine list, no
addresses, no CT ids, no names. It contains the *shape* of a multi-site home
computer estate — and the working tools to run one.

## The idea

A "homelab" is a small computer estate you run yourself: a primary site, an
offsite site, a VPS, and a scatter of small boards — connected by a VPN
mesh (Tailscale, or a self-hosted Headscale if you'd rather own the control
plane), running virtualization, NAS, monitoring, and a long tail of
self-hosted services.

**Leiter is the claim that such an estate can be *run by local agents*, not
merely maintained by a human.** The estate's documentation is its system of
record; agents read it as state, act on it through a corpus of skills and
CLI tools, and write their work back as documentation. The estate stays
local and self-owned — no cloud dependency, no SaaS middle layer — while the
*operation* of it (the boring 90%) is done by a local coding agent under
explicit, auditable rules.

This repo is what that approach looks like from the outside: the reusable
parts, written so a stranger can take them and run them on *their* estate.

## The three layers

| Layer | What you get | Where |
|---|---|---|
| **1. Tools you can steal** | Agent skills (the [open Agent-Skills standard](https://agentskills.io)): self-contained folders — `SKILL.md` + bundled CLI scripts + reference docs — that you install into your agent and it immediately uses against *your* estate: virtualization, NAS, reverse proxy/DNS, monitoring, KVM-over-network, phones, backup flows, a component-graph tool. | [`skills/`](skills/README.md) |
| **2. The practice** | How an agent-run estate is actually *operated*: documentation as state, a machine-readable component dependency graph (staleness audit + blast-radius queries), session discipline and agent memory, secret handling, the public/private split, change governance. | [`docs/practice/`](docs/practice/README.md) |
| **3. The concepts** | The estate as a *concept*: multi-site with an offsite, the mesh backbone, what a "host / guest / service" ontology looks like — ideas you adapt, not a layout you copy. | [`docs/`](docs/README.md) |

**What this is not.** Not a turnkey installer (your estate is not our
estate — nothing here deploys anything by itself), and not a catalogue of
one person's choices as if they were the only ones. Every skill states what
it assumes and what *you* must bring.

## How it stays honest: the overlay contract

The public repo holds the **shape**; the private instance holds the
**values**. Templates carry neutral tokens (`@@SITE_A@@`, `@@CT_ID@@` …);
your private repo supplies the mapping at deploy time. One source of truth,
zero drift, publishable without leaking anything. The mechanics:
[`docs/overlay-contract.md`](docs/overlay-contract.md).

## Repository map

```
leiter/
├── README.md          ← you are here
├── AGENTS.md          ← working rules for agents (and humans) in this repo
├── LICENSE            ← MIT
├── skills/            ← layer 1: agent skills (open standard; bundle layout)
├── docs/
│   ├── README.md      ← index
│   ├── domain-model.md← the estate ontology: kinds, relations, invariants
│   ├── overlay-contract.md
│   └── practice/      ← layer 2: operating doctrine (grows here)
└── scripts/
    └── sanitize-sweep.sh  ← the pre-push leak guard
```

## Status

Early. The skeleton is in place; the corpus grows by deliberate extraction
from the private instance (each piece written or generalized on purpose —
this is a curation project, not a mirror). The first skills to land are the
general ones; service-specific ones follow as they prove portable.

## Related public repos

- **monitoring-stack** — Prometheus/Grafana for a homelab: the worked
  example of the overlay contract (neutral tokens in the repo, values from
  your private repo at deploy time).
- **llmlab** — local LLM inference on consumer GPUs: the same
  shape/values split applied to a research corpus.

## License

MIT — see [LICENSE](LICENSE).
