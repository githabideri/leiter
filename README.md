# Leiter

*Leiter* is German: ladder, conductor, the one who leads.

This is the public side of a private homelab. The private repo is where
the facts live: which box, which address, which id, who uses what. This
repo is where the shape lives: the tools and operating practices of a
multi-site home estate run by local agents, written so you can take them
and run them on your own estate. It holds no machine list and no
addresses, and no names; only role terms, like "the primary host" or
"an offsite site".

## Why an agent runs the estate

A homelab is a small computer estate you run yourself. A few sites
(a main location, an offsite, a VPS, some scattered small boards),
joined by a mesh VPN (Tailscale, or a self-hosted Headscale if you want
to own the control plane). On top: virtualization, NAS, monitoring, and
a long tail of self-hosted services.

The estate's documentation is its system of record, and local coding
agents do the boring 90%. An agent reads the docs as state, acts through
a corpus of skills and CLI tools, and writes the result back into the
docs. The estate stays local and self-owned; the operation is auditable,
because every action lands in a session log. This repo is that
approach, seen from the outside.

## The three layers

| Layer | What you get | Where |
|---|---|---|
| **Tools you can steal** | Agent skills in the [open Agent-Skills format](https://agentskills.io): a folder with a `SKILL.md`, bundled CLI scripts, and reference docs. Point your agent at the folder and it operates the matching part of your estate: virtualization, NAS, DNS and reverse proxy, monitoring, KVM over the network, phones, backup flows, a component-graph tool. | [`skills/`](skills/README.md) |
| **The practice** | How an agent-run estate is operated day to day: documentation as state, a machine-readable component graph (staleness audits, blast-radius queries), session and memory discipline, secret handling, the public/private split, change governance. | [`docs/practice/`](docs/practice/README.md) |
| **The concepts** | The estate as a concept: multi-site with an offsite, the mesh spine, a host/guest/service ontology. Ideas to adapt to your setup, rather than a layout to copy. | [`docs/`](docs/README.md) |

Every skill states what it assumes and what you have to supply. Nothing
here deploys anything by itself.

## The public/private split

A template in the public repo carries neutral tokens (`@@SITE_A@@`,
`@@CT_ID@@`, …). Your private repo holds the mapping that resolves
them; the join happens at deploy time. Every fact therefore lives in
exactly one place, so there is nothing to drift, and the public side
never sees it. Mechanics in
[`docs/overlay-contract.md`](docs/overlay-contract.md).

## The repo

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
│   ├── practice/      ← layer 2: operating doctrine (grows here)
│   └── guides/        ← step-shaped build guides (human-facing; the agent-on-small-box shape)
└── scripts/
    └── sanitize-sweep.sh  ← the pre-push leak guard
```

## Status

Early. The base docs are in; the corpus grows by deliberate extraction
from the private instance, one piece at a time, each written or
generalized on purpose. It is curation, so it moves at curation speed.
The general skills land first.

## Related

- **monitoring-stack**: Prometheus and Grafana for a homelab. The
  overlay contract in production, neutral tokens in the repo and values
  from your private repo at deploy time.
- **llmlab**: local LLM inference on consumer GPUs. The same
  shape/values split applied to a research corpus.

## License

MIT. See [LICENSE](LICENSE).
