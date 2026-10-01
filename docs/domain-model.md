# The domain model

The shared vocabulary of a homelab as an *operated system*: what kinds of
things exist, how they relate, and which invariants keep the description
honest. Read this as the definition of the nouns and verbs everything else
in this repo (and in the private instances that adopt it) uses.

The framing is an **operational ontology**: a formal, shared description of
the domain in which a system operates, where *reads traverse the model and
writes are gated*. Every change to the estate goes through a typed action
that is audited and propagates back to the sources of record. You don't
need the name to use it; you need the three properties:

1. **Explicit kinds.** Every object is one of a small, fixed set of kinds.
2. **Typed relations.** Every connection between objects has a name and a
   direction, and the name carries the meaning.
3. **Checkable invariants.** The model carries rules that can be *verified*
   (a linter), so drift between the description and reality surfaces
   instead of accumulating silently.

## The kinds

| Kind | What it is | Examples |
|---|---|---|
| **site** | A physical location with its own power and network. | the primary site, an offsite site, a VPS, "a small board somewhere" |
| **host** | A machine that runs directly on its hardware. | a Proxmox host, a NAS, a router, a Raspberry Pi |
| **guest** | A virtualized unit on a host (LXC container or VM). | a monitoring container, a media server VM |
| **service** | A function the estate provides, as a named, documented unit. | DNS, reverse proxy, monitoring, backup, a search endpoint |
| **skill** | An agent capability: a folder of instructions + tools for one coherent domain. | "operate the NAS", "manage the dashboard" |
| **tool** | An executable CLI (or script bundle) a skill drives. | a `jq`-based wrapper around a service's API |
| **repo** | A git repository that is part of the estate (docs, code, config-as-data). | the homelab docs repo, this one |
| **logflow** | An append-only, machine-written record of an ongoing process. | an audit trail, an uplink monitor's CSV |

Two deliberate choices: **guests are first-class** (in a virtualized estate
most *things* are guests, and "which guest" is where every operational fact
lives); and **skills/tools are in the same graph as hardware** (the
capability layer is part of the estate, not an appendix to it).

## The relations

Every edge points **dependent → dependency** ("A needs B"); one edge type is the
deliberate exception, marked as a *flow*:

| Relation | Direction means | Example |
|---|---|---|
| `member` | host belongs to a site | the offsite host → the offsite site |
| `on` | guest runs on a host | a media VM → the GPU host |
| `runs_on` | a service is implemented by this guest (or host) | the DNS service → the Pi-hole guest |
| `wraps` | a skill is the manual for this tool | the NAS skill → the NAS CLI |
| `calls` | a tool talks to this service's API | the DNS CLI → the DNS service |
| `depends_on` | generic runtime dependency | the video pipeline → the transcription service |
| `replicates_to` | *data flow* (the exception): backup/replication goes to this target | the flash NAS → the HDD backup NAS → the offsite NAS |

The `replicates_to` asymmetry matters: a dependency edge means "A breaks
if B dies"; a flow edge means "A's *backup path* breaks if B dies"; A itself
keeps running. A blast-radius query must treat them differently, or it
will tell you your media server died when actually only its backup
stopped.

## The invariants

These are the checkable rules. A linter reports violations; it never
blocks. (This is the house style: the model *advises*, humans decide.)

1. **Single source of record per fact.** Each kind has exactly one
   canonical registry (hosts & guests: the inventory; services: the
   per-service docs; skills: the skills directory; …). Everything else
   *links* to the registry; it never restates it. A fact in two places is
   a bug waiting for the day the copies disagree.
2. **State docs contain no actions; action lists contain no state.** The
   inventory says what *is*; the work list says what *should happen*.
   Mixing them is how both rot.
3. **Derivation over duplication.** Anything that can be *computed* from
   the registries (a diagram, an index, a dependency closure) is generated
   and marked as such. Generated artifacts are never hand-edited; the data
   changes, the artifact regenerates, in the same commit.
4. **Provisional knowledge is staged, visibly.** Facts that don't yet have
   a registry home live in a marked *curation* layer: always merged,
   always flagged as "promote me". A fact that is known but not yet
   recorded is not lost; it is queued.
5. **Status is a closed vocabulary.** `running / stopped / decommissioned /
   migrated / removed`. Anything else is a note, not a state. (The classic
   drift this prevents: a guest that "moved" to another host, where the old
   row's notes keep describing a box that no longer exists *there*.)
6. **Frozen snapshots are frozen.** Dated reports record the world as it
   was. Supersede with a note pointing forward; never rewrite the past.

## Why this buys you an agent

An LLM agent cannot "know" your estate; it can only read a description of
it. When that description has explicit kinds, typed relations, and checkable
invariants, three things stop being vibes:

- **Staleness** becomes a list (`lint`: unmapped services, ghosts,
  unregistered machines, stale builds), not a feeling.
- **Blast radius** becomes a query (`affected <x>`: everything that would
  break if x changed), not a hope.
- **Onboarding** (of a human *or* a fresh agent session) becomes "read the
  model", not archaeology through a chat log.

The model is only as good as its discipline, which is why invariant 1 is
first: the moment a fact is comfortable living in two places, the agent
starts reading the wrong one.
