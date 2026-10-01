# docs/

The conceptual and practice layer of leiter. Index:

| Doc | What it is | Status |
|---|---|---|
| [domain-model.md](domain-model.md) | The estate **ontology**: the kinds of things a homelab is made of (site, host, guest, service, skill, tool, repo, logflow…), the relations between them, and the invariants that keep the model honest. The shared vocabulary everything else in this repo (and the private instances that use it) speaks. | stable |
| [overlay-contract.md](overlay-contract.md) | The public/private **split**: shape in the public repo (with `@@TOKEN@@` placeholders), values in your private repo, joined at deploy time. The mechanism that makes publishing a homelab's knowledge safe. | stable |
| [practice/](practice/README.md) | Operating doctrine: documentation-as-state, the component-graph discipline (staleness audit, blast radius), session & memory discipline, secret handling, change governance. | growing |

## Conventions

- **Shape, not values.** These docs describe *kinds of things* and *rules
  about them*. Concrete facts (which box, which address, which id) belong to
  a private instance; if a doc needs one, it uses a `@@TOKEN@@` per the
  overlay contract.
- **Role terms are the vocabulary.** "The primary host", "an offsite site",
  "a VPS", "a small board". Never a real hostname.
- **Frozen vs. living.** This index and the two stable docs are living
  (update in place). Dated reports, where any, are frozen snapshots:
  supersede with a note, never rewrite.
- **One idea per doc.** If a doc answers two questions, split it. If a
  sentence needs the reader to know our specific estate to make sense,
  rewrite it or cut it.
