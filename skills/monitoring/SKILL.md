---
name: monitoring
description: >
  Onboard a host or service into a Prometheus + Grafana stack and keep the
  onboarding honest: the standard path (a metrics exporter installed by a
  repeatable role or script, a scrape job declared in your config store
  with a fixed label contract, then a verification script that proves the
  whole chain), the auto-discovery family (hypervisor exporters and backup
  server exporters where new guests and datastores appear by themselves),
  and the failure shapes: a reinstall that wipes the exporter's
  credentials (401, then 500), a target that is up but whose metric
  family changed name (your dashboards just went silent), a job that was
  never added (the exporter runs, nobody scrapes it). Use for "add
  <host> to monitoring", "scrape this service's /metrics", "new exporter
  for <thing>", "why is <dashboard panel> empty", "the target shows down
  after a reinstall". Not for: designing dashboards (a separate concern
  with its own discipline), or operating the Prometheus server itself
  (retention, rules, backups).
---

# Monitoring onboarding

You bring:

- **a Prometheus and a Grafana** (containers, VMs, or bare; one box each
  or two), with your config store in version control (the estate uses
  ansible: an inventory file, a role per exporter, a job list on the
  Prometheus host);
- **SSH to the thing being onboarded**;
- **one label-contract document** (below): the vocabulary that every
  scrape job and every dashboard query speaks.

The estate's shared content (dashboards, metric documentation, the
exporter roles) lives in a companion repo the estate publishes; this
skill is the workflow that puts a new source into that stack and
proves it works end to end.

## The onboarding flow

1. **Inventory the source.** Hostname, OS/arch, CPUs, memory, disks.
   This decides the `instance` identity (for the standard path,
   `<address>:<metrics-port>`) and the human labels.
2. **Install the exporter.** The standard path is a repeatable unit
   (the estate: an ansible role that installs `node_exporter` as its
   own user, idempotent, works in unprivileged containers and regular
   VMs alike). A service that already speaks `/metrics` needs no
   exporter at all: the scrape job points at the endpoint directly.
3. **Declare the scrape job.** One entry in the Prometheus config
   (target + labels), in the config store, in the same commit as
   anything else that changed. The job is *data* (a target and a
   label set), not logic.
4. **Rebuild and verify.** Re-render the Prometheus config from the
   store, then run the **verification script** on the Prometheus host
   itself (against localhost): every target `up`, every expected
   metric family returning series, the recording rules evaluating.
   A new source is *onboarded* when the script says so, not when the
   exporter process is running.

The two halves fail independently, and the split is the whole of
troubleshooting this layer: **the exporter is alive** (process,
port, local `/metrics` answers) and **the job exists and scrapes**
(Prometheus target state). "Nothing shows up" is one of exactly two
problems: no exporter, or no job. Check the local port first.

## The auto-discovery family

Two sources onboarding by themselves, once their exporter exists:

- **the hypervisor exporter**: one exporter per hypervisor host,
  scraping the host's management API with a dedicated low-privilege
  user and token; every new guest (container or VM) appears as a new
  series automatically. New guest: nothing to do.
- **the backup-server exporter**: same shape; new datastores and
  namespaces appear on their own. Verify a new one landed with a
  `count by (namespace)`-style query.

**The reinstall gotcha (both families):** a host reinstall wipes the
dedicated user, the token, and the ACLs that the exporter
credentials rest on. The exporter module stays in your config; the
target then dies, and it dies in two stages that look different:
**401** while the user still half-exists in some form, **500** once
only the user is restored without the ACLs. Recovery is recreate
user + token + *all* the ACLs on the host, update the token in your
secret store, re-render. (Token *format* is a version thing on some
platforms: newer releases parse a different separator than older
ones; a 401 that says "no token id" is usually the separator, not the
token.)

## The label contract

One document owns the label vocabulary (the estate's: `docs/labeling.md`
in its monitoring repo): which label identifies the *kind of source*
(a fixed set: host, hypervisor, backup server, and your service
roles), which label is the machine identity, which are the human
readables (name, OS, location). Every job picks labels from that
vocabulary; every dashboard query may only use it. The rule is not
"be consistent" (nobody is, on their own); the rule is **one
document, referenced by both sides of the query**. When a new source
kind appears, it earns its label in the document first, then in the
jobs.

The contract has one sharp edge: a metric family that renames itself
(upstream version bump) between a recording rule and a dashboard
panel breaks *silently* — the target is up, the scrape is green, the
panel is empty. The verification script's job-list of expected metric
families is what turns that silent break into a loud one.

## The verification script

A single script, run on the Prometheus host against localhost
(read-only; it queries, it never mutates):

1. every configured target: `up == 1` (a `down` names the host and the
   error string, which usually says which layer: connection, 401, 500,
   TLS);
2. the expected **metric families** for each source kind: present and
   returning at least one series (this is the rename detector);
3. the **recording rules**: evaluating (a rule referencing a dead
   metric name evaluates empty; that is the dashboard's future,
   reported now).

The script's output is the onboarding receipt: "N targets up, M
families present, K rules green, here are the exceptions." Onboarding
is done when the exceptions are empty or explained; a new source whose
queries return zero series is a *broken dashboard assumption*, and
that gets fixed in the dashboard's flow, not by fiddling with the
scrape.

## Failure modes

- **Exporter running, job missing.** The port answers locally;
  Prometheus has never heard of the target. The most common
  "half-onboarded" state.
- **Job present, target down (401/500).** The reinstall wiped the
  credentials; two-stage death; the config looks fine, so nobody
  suspects the host's identity layer.
- **Target up, panel empty.** A metric rename or a label-vocabulary
  drift: the query's vocabulary and the source's vocabulary stopped
  being the same words. The verification script's family check is the
  only thing that catches this before a human notices an empty panel.
- **Label vocabulary drift.** A job invents its own labels (`host`
  where the contract says `hostname`); one dashboard works, the next
  doesn't, and the disagreement is invisible in the scrape data.
- **Scrape interval > patience.** You wait five minutes, the target
  "isn't up yet"; it will be, at the next scrape. Read the interval
  before you conclude.
- **Onboarding the exporter twice.** The role is idempotent; a second
  run is a no-op. The manual one-shot is not; keep the installer
  repeatable or the second box teaches the first a lesson.
