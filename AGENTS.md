# AGENTS.md: working rules for the leiter repo

Read this before touching anything here. This repo is public from the
first commit: every byte you write is read by strangers, and the sweep at
the end is the only guard.

## The public boundary (non-negotiable)

This repo documents *a* homelab pattern, never *our* homelab. Never commit:

- internal IP addresses (any `192.168.*`, `10.*`, `172.16-31.*`, Tailscale
  CGAT `100.64-127.*`) or port+IP pairs that identify a specific box
- internal hostnames, domains, or tailnet node names
- Proxmox VM/CT ids, VMIDs, serials, MACs, hardware purchase details
- secrets, tokens, keys, passwords — ever
- personal names, family details, or any identifying detail about the
  private instance's people

**The register is "role terms".** Private names are translated, not
redacted: "the primary host", "the GPU host", "an offsite site", "a VPS",
"a small board". Hardware *specs* are fine to state (a reader wants to know
"RTX 3090, 64 GB"); *identity* is not (which machine, where, who). When a
fact only makes sense with the identity, generalize the fact or drop it.

**Before every push, run the sweep: all file types, zero hits required.**

```sh
scripts/sanitize-sweep.sh
```

It greps for identifier *classes* (address ranges, tailnet DNS, hostname
shapes). It cannot catch everything by itself (a novel hostname, a name, a
telling combination of specs). It is a floor, not a proof: read what you
wrote the way a stranger would, before you push. This repo's
own history is also public: a leak in commit N survives a fix in commit N+1.
If a leak ever happens, it is a history rewrite (fresh repo + move), not a
patch on top.

## The corpus standard

Skills follow the [open Agent-Skills standard](https://agentskills.io):
`skills/<name>/` with `SKILL.md` (frontmatter: `name`, `description`,
optionally `license`, `compatibility`), `scripts/`, `references/`,
`assets/`. The full house conventions (including where prerequisites and
setup live) are in [`skills/README.md`](skills/README.md). One unit per
capability: the skill is the manual, the scripts are the machine, and the
two ship together so a reader's agent gets both at once.

Every skill states its **assumptions and what the reader must bring**
(see the standard's `compatibility` frontmatter field + a Prerequisites
section). A skill that silently assumes "you run Proxmox like we do" is a
defect.

## Facts vs. shape

- **Shape** (patterns, invariants, procedures with role terms) → this repo.
- **Values** (addresses, ids, names, secrets, live state) → never. If a
  doc or template needs a value, it carries a `@@TOKEN@@` and the token is
  defined in the overlay-contract doc.
- Generated files (diagrams, indexes) are marked as generated and
  regenerated, never hand-edited.
- Dated reports/snapshots are frozen: supersede, don't rewrite.

## Git workflow

- Dual remotes: `origin` (self-hosted Gitea, the primary) and `github`
  (the public mirror). **Push both**; forgetting one is how 404s are born.
  The sweep runs in `pre-push`; do not bypass it.
- Commit messages: imperative, specific, one logical change per commit.
- This repo is a submodule of the private homelab repo; bump the submodule
  pointer there after publishing a meaningful change.

## Tone

Write for the competent stranger: a person with a few machines, a VPN, and
an agent, who wants to run their own estate the way this one is run. Plain,
direct, no marketing, no "delve". If a sentence would only make sense to
someone who already lives in the private instance, it is either wrong or it
doesn't belong here.
