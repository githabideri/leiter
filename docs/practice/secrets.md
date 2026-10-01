# Secrets

In an agent-run estate, secrets must be **usable by the agent without
being knowledge of the agent**. The agent needs credentials to do its
job: it calls hypervisor APIs, pushes to remotes, connects to
services. It must never *hold* them: not in documents, not in
transcripts, not in the model's context, not in the repository. Three
properties make the scheme work:

- **reachable**: the tooling can load a value at the moment of use,
  from the machine it runs on;
- **unrecorded**: the value never appears in any committed or logged
  artifact;
- **auditable**: the *shape* of the secret surface is declared, so a
  missing or leaked secret is an error the tooling can report, not a
  mystery.

## The layout

Each service keeps its values in a local `.env` file (on the machine,
outside version control, or inside an encrypted blob), next to a
committed **schema** file that lists every key: its name, what it is
for, and a marker for the ones that are sensitive. The schema is the
public shape of the secret surface; the values are the private values.
This is the overlay contract applied to credentials: the schema travels
in the repo and can even be published, the values never leave the
machine.

An encrypted local vault (the estate uses `varlock`) resolves the
values at runtime: the tooling asks it to load a config directory and
gets the resolved environment; sensitive values live in an encrypted
blob with a device-local key, so a stolen checkout of the repo yields
no secrets. The same tooling audits the code against the schema (a key
the code uses but the schema does not declare is a finding), scans
files for plaintext values, and can run a command with the environment
injected without the value ever passing through the shell history.

## The agent's contract

The agent **loads, never copies**. A script reads the `.env` through
the vault at the moment it needs a value; the value appears in the
script's environment, does its work, and is gone. The agent never
writes a value into a document, a plan, a report, or a prompt. And
when a task requires a credential that cannot be found, the agent says
so: the missing value is named after its schema key, and the task
stops. Guessing, or leaving a placeholder that a later session fills
with a real value, is how secrets migrate into the record.

## Redaction as a control, not a habit

The only realistic leak path is the transcript: a command the agent
echoes contains the credential. You cannot prompt your way out of that
(model behavior is not a control), so the estate runs a mechanical
redaction pass on every commit, sweeping the session logs against
patterns *and against the actual values* currently in the environment
files. Value-based sweeping catches what pattern-based matching
misses: the token that has a shape no pattern predicted. If you are
told a secret leaked, the sweep is run in place with the value as the
pattern.

## Failure modes

- **A secret in a report.** "Tested with token `abc…`" in an incident
  write-up. The value lives in the record forever, and every clone of
  the repo is a copy of it. Only the redaction hook catches this;
  nobody's attention does.
- **Schema drift.** A key added to the `.env` without a schema entry:
  invisible to the audit, undetectable as missing, resolvable by
  guesswork. The schema is the declaration, and undeclared is the
  failure.
- **"Be careful" as the control.** The discipline of not printing
  secrets depends on every model on every run. The hook does not.
- **A value copied into a doc for convenience.** The overlay
  violation in its purest form: a second copy of a private value, in
  the one place that will be read.

## How to adopt

One `.env` per service, one committed schema with sensitive markers,
an encrypted blob for the values that matter, and the redaction hook
on the first day. Start with two or three secrets; the audit
subcommand (code usage against the schema) tells you when the surface
has grown beyond what you remember declaring.
