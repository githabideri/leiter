---
name: "@@DNS_NAME@@"
description: >-
  "@@DNS_DESCRIPTION@@"
---

# DNS + reverse proxy

You bring:

- **an internal authoritative resolver** (Pi-hole-class: it answers for
  the estate's internal domain and hands out DHCP), ideally as an **HA
  pair**;
- **a database-driven reverse proxy** (Nginx Proxy Manager-class: a web
  DB of proxy hosts/redirects/certs that renders nginx configs), one or
  more instances;
- **the DNS provider** for the public zone, with API access (or at
  least a workable web console);
- SSH to each box.

The skill contains the two governing rules plus the concrete reference
implementations for the Pi-hole v6 store and the NPM-class proxy, and
the verify ladder. The estate's own scripts implement these; the
patterns are what you take.

## The two rules

### 1. Store vs. generated: write to the store

Every tool in this layer keeps its truth somewhere and *renders* files
from it. The dangerous file is the rendered one, because it looks
authoritative and is not.

The reference case (Pi-hole v6 FTL, verified with three observed wipe
incidents): `/etc/pihole/hosts/custom.list` is **generated from
`/etc/pihole/pihole.toml` on every FTL start** (including nightly
update restarts). A hand-edited line in `custom.list` survives until the
next restart, then is gone, taking the record with it. The store is the
`[dns] hosts` array in the toml (entries `"IP hostname"`; CNAMEs live in
a *separate* `cnameRecords` array). `references/pihole-v6.md` has the
full pattern: edit the toml, validate it parses (`tomllib`), restart,
verify with `dig`.

The general procedure for any new tool in this layer: **restart the
service and watch which files get rewritten.** The one that changes is
the derived file; the one that doesn't (but whose contents survive) is
the store.

Two variants of the same trap, both observed:

- **CNAME in the A-record array.** FTL silently *ignores* a
  `name,target`-shaped entry in the `hosts` array: it renders it into
  the generated list, but never resolves it. The failure is a silent
  non-resolution, which is the worst kind (the record *looks* present).
  Pick the array by the argument's shape, not by convenience.
- **DHCP config re-rendered.** The DHCP side (`dnsmasq.conf` in the
  Pi-hole case) is also re-rendered from the tool's own config on every
  start: a `dhcp-host=` line patched into the rendered file can die on
  the next restart. If it does, the real key is somewhere in the tool's
  store, and that is where the lease belongs.

### 2. A DB row is not a change

A database-driven proxy renders its nginx configs through its own flow.
A row inserted directly into the DB changes nothing on the wire. Every
add/remove is **three steps**:

1. the DB row (the declaration),
2. the generated config file (written from the tool's template into its
   config directory),
3. the reload (`nginx -s reload` or the tool's equivalent).

Disabling is the same three in reverse: mark the row disabled, **delete
the config file** (a disabled row with a live conf still serves),
reload. Do the steps as one operation with a `--dry-run` that prints
the SQL and the conf before executing, so a failed step is visible as a
failed step. `references/proxy-db.md` has the NPM implementation,
including the certificate case.

## The HA pair discipline

A two-node resolver pair with config sync that you cannot fully trust
(the estate's pair has had a broken sync endpoint for months) changes
the write rule: **write to both stores, verify both.** The script does
the dual write and a `dig` against each node. Do not rely on the sync
to propagate a change you made once; and when you find the nodes have
drifted, treat the drift itself as a finding to fix at the sync layer,
not a thing to paper over with another manual write.

## The public side

- The **provider zone** (A/CNAME records pointing at the estate's entry
  points) is changed through the provider's API where one exists; the
  estate stays on a *legacy* API where the modern one is worse (a
  documented decision, `references/proxy-db.md`), because churn in a
  working integration is how records get lost.
- The **long-lived wildcard cert** (one cert for the whole internal
  domain, or the public one) is often issued by the provider-side DNS
  plugin (`certbot-dns-<provider>` inside the proxy container), with the
  provider **credentials stored in the DB blob, not in any file**.
  Consequence: there is no "edit the cert" action; credential rotation
  is stop the container, write the DB, start it. Know this before you
  need it; the procedure is in `references/proxy-db.md`.

## Verify (the ladder)

1. `dig <name> @<resolver> +short` against **each** HA node (internal
   plane)
2. `curl -sI -H "Host: <name>" http://<proxy>` through the proxy (does
   the Host header route to the right upstream?)
3. `dig <public-name>` from outside the estate (provider plane)
4. `curl -sI https://<public-name>` (cert chain + the final hop)

A change that passes only step 1 is an internal change; a proxy host
that fails step 2 but passes step 1 has a conf or reload problem, not a
DNS problem. Reading the **effective nginx config** (the generated
file, and `nginx -T`), not the DB row, is what disambiguates.

## The registry habit

The skill deliberately holds **no record lists**. What exists (every
internal record, every proxy host, every cert and its expiry) lives in
registry files the change workflow updates in the same step (the
estate's: `configs/<service>/…-hosts.md`). That is the one-fact-one-home
rule applied to DNS: the skill teaches the mechanics, the registries
carry the state, and a change that isn't written into the registry is
half done.

## Failure modes

- **Editing the generated file.** The record works until the next
  restart, then vanishes. The three-incident pattern.
- **The CNAME in the A array.** Present everywhere, resolves nowhere.
- **The DB row without the conf and the reload.** Everything in the
  database says the host exists; the wire says nothing.
- **Trusting the HA sync.** The change is on one node; the pair now
  disagrees, and which node a client hits decides whether the record
  exists.
- **The expired wildcard.** The provider-side cert has a renewal
  window and a rotation procedure with no UI; if nobody runs it, every
  site under the domain breaks at once, which looks like a proxy
  outage.
- **The internal/external split-brain.** Resolves inside, 404s outside
  (or the reverse): two planes, two checks, both required.

---

<!--
  Estate instance section. An estate that maintains a mapping for this
  skill (the overlay contract: ../docs/overlay-contract.md) renders its
  instance content -- machines, paths, what this fleet has hit -- at
  this spot, at deploy time. The raw shape ends here.
-->
@@DNS_ESTATE@@
