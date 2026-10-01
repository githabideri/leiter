# The .env.schema syntax

The schema file is the declared shape of a config directory. It is a
`.env`-shaped file: one `KEY=value` line per variable, with comment
lines carrying directives. The value on the schema line is a **default
or a source**; when it is empty, the value is resolved from the
matching `.env` at load time.

## Directives

| Directive | Meaning |
|---|---|
| `@type=<t>` | the validator: `string`, `string(minLength=N)`, `string(startsWith=pfx)`, `number`, `port`, `url`, `bool`, `enum(a,b,c)`, `path` |
| `@required` | must be non-empty after resolution |
| `@sensitive` | the value is a secret: masked in output, excluded from redaction-irrelevant logs, the key for the encrypted-blob tier |
| `@defaultSensitive=<bool>` | file-level default for `@sensitive` (the estate uses `false`: most keys are not secrets, secrets are marked) |
| `@defaultRequired=infer` | file-level default: keys with a default value are not required, keys without one are |
| `@auditIgnore` | skip this key in `varlock audit` (for keys consumed by external tools the auditor cannot see) |
| `@example=<v>` | documentation: an example value (never a real one) |
| `@currentEnv=$APP_ENV` | multi-environment: select which `.env.<name>` to load based on another key |

## Value forms

```bash
KEY=                 # resolve from .env at load time (the normal case)
KEY=defaultvalue     # literal default (used when .env has no entry)
KEY=${OTHER_KEY}     # expansion of another (already resolved) key
KEY=exec('op read "op://.../secret"')   # pull from a secret manager at load time
```

The `exec(...)` form is the integration point with real secret
managers (1Password, Vault, AWS, and the other bundled plugins): varlock
stays the schema and the loader, the manager stays the store.

## The estate convention

- **one config directory per service** (`configs/<service>/`), co-
  located with any service-specific scripts;
- **file-level defaults first**: `# @defaultSensitive=false
  @defaultRequired=infer`, so marking a secret is one line;
- **section headers** (`# === Proxmox API ===`) group keys; the schema
  is read by agents, so the headers are for both;
- **the comment above a sensitive key says what it is** ("Proxmox API
  token for the <host>-agent user") without saying what it *is*;
- **`.env.user`** for machine-local overrides (per-box values that do
  not belong in the shared `.env`);
- the schema and the `.gitignore` entry for the `.env` land in the
  same commit as the first key.

## Multi-environment

With `@currentEnv=$APP_ENV`, varlock auto-loads `.env`, then
`.env.$APP_ENV` (later wins). The estate keeps this off: one config
directory per service is simpler than one service across environments,
and the per-host split (a directory per host) already covers the
multi-machine case.
