---
name: varlock
description: >
  The .env schema discipline: every service's config lives in a .env (values,
  never committed) next to a committed .env.schema (the declared shape, with
  @sensitive/@required/@type directives) that agents read without ever seeing
  the values. varlock (the open-source CLI, npm: varlock, varlock.dev) loads
  and injects the resolved environment at run time, audits code against the
  schema (undeclared keys are findings), scans files for plaintext secrets,
  and feeds the commit-time log redaction with actual values. Use for
  "add config for a new service", "where does this credential live", "is this
  env key declared", "scan for leaked secrets", "type-check the .env". Not
  for: a secret manager (varlock can pull from one, but is not one), or
  putting values into documents (never; that is the overlay contract).
---

# Varlock

You bring:

- **the varlock CLI**: `npm i -g varlock` (or brew/curl install; public
  project `dmno-dev/varlock`, docs at varlock.dev). Note: it ships with
  telemetry; disable it once (`varlock telemetry disable`) and the
  estate stays quiet.
- **a config directory per service**: the convention is
  `configs/<service>/` holding three files.

| File | Content | In git? |
|---|---|---|
| `.env` | the values | **never** (gitignored) |
| `.env.schema` | the declared shape: every key, its type, whether it is sensitive | yes, this is the documentation |
| `.env.user` | machine-local overrides | never |

The schema is the *public shape* of the secret surface: it can be
committed, published, and read by any agent, and it leaks nothing. The
values stay on the machine. This is the overlay contract applied to
credentials (see `../../docs/overlay-contract.md`).

## The schema

Directives are comment lines above (or beside) the key
(`KEY=` with an empty value means "resolve from `.env` at load
time"):

```bash
# @defaultSensitive=false @defaultRequired=infer   # file-level defaults

# @type=string(minLength=1) @sensitive @required
# Proxmox API token for the <host>-agent user
PVE_API_TOKEN=

# @type=string
# Host address (not an SSH alias)
PVE_HOST=

# @auditIgnore        # key used by an external tool the audit cannot see
SOME_TOOL_KEY=
```

The full directive set (`@type` with validators, `@required`,
`@sensitive`, `@example`, `@currentEnv` for multi-environment files,
`exec(...)` sources, `${VAR}` expansion between keys) is in
[`references/schema-syntax.md`](references/schema-syntax.md).

## The workflow

```bash
# 1. load: resolve the config dir into a usable environment
eval "$(varlock load --path configs/<service>/ --format shell)"
#    or: varlock run --path configs/<service>/ -- <command>   (injected, never echoed)

# 2. audit: does the code's env-var usage match the schema?
#    undeclared keys are findings (a key the code uses but the schema
#    does not declare is a drift finding, not an error to ignore)
varlock audit

# 3. scan: do any files in the repo contain plaintext values that
#    should be in the .env? (the pre-push guard; pairs with git hooks)
varlock scan

# 4. reveal / explain: human eyes only
varlock explain <KEY>     # how a value resolves (which file, which source)
varlock reveal             # view decrypted values in a locked terminal
```

The estate's scripts use the first form with a graceful fallback: if
varlock is not on the machine, the plain `.env` is sourced directly, so
the tooling degrades instead of failing.

## The redaction integration

The one realistic leak path in an agent estate is the session
transcript: the agent echoes a credential into a command. The commit-
time redaction hook (see `../../docs/practice/secrets.md`) sweeps the
logs against **the actual values in the `.env` files**, not just
patterns. varlock makes that sweep mechanical, because each value
lives in exactly one place: the config directory. Pattern-based
matching alone misses the token whose shape no one predicted;
value-based sweeping does not.

## The hardening tier (optional)

varlock can move sensitive values out of the plaintext `.env` into an
encrypted blob (device-local key: `varlock generate-key`,
`varlock encrypt`), and can require biometric unlock before revealing
(`varlock lock`). This estate runs the **plain mode**: single-operator
machines, plaintext `.env` with strict permissions, redaction as the
control. Switch to the encrypted tier when a machine is shared or
remotely accessible by more than one human.

## Failure modes

- **Schema drift.** A key added to `.env` without a schema entry:
  invisible to the audit, undetectable as missing. The audit catches
  the reverse direction (code using undeclared keys); keep both files
  in the same commit whenever a key is born.
- **A value in a document.** "Tested with token ..." in a report or a
  plan. The overlay violation in its purest form; the scan and the
  redaction hook are the only things that catch it.
- **The .env committed.** The `.gitignore` must name it per directory;
  `varlock scan` catches a breach after the fact, the hook should stop
  it before.
- **Telemetry on.** The CLI phones home by default; one command turns
  it off.

## Scripts

- [`scripts/config-check.sh`](scripts/config-check.sh): audit + scan a
  config directory in one call, non-zero exit on findings; wire it
  into pre-push where a schema exists.
