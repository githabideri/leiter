# The overlay contract: shape vs. values

How one body of knowledge can be **public** (reusable by anyone) and
**instance-specific** (yours, with your real addresses, ids, and secrets)
at the same time, without the two drifting apart.

This is the mechanism that makes publishing homelab knowledge safe, and
the reason the public repos in this family can be this concrete without
ever naming a machine.

## The one rule

> **The public repo owns the *shape*. The private repo owns the *values*.
> They meet at deploy time, through a mapping file.**

A template in the public repo carries **neutral tokens** where instance
facts would go:

```yaml
# public repo: provisioning/<something>.yml (shape)
site:      "@@SITE_A@@        # e.g. your main location"
host:      "@@PRIMARY_HOST@@"
ct_id:     "@@CT_ID@@"
lan_ip:    "@@LAN_IP@@"
```

Your private repo supplies a **mapping file** that resolves the tokens:

```yaml
# private repo: the overlay (values; never committed anywhere public)
@@SITE_A@@:       my-actual-site-name
@@PRIMARY_HOST@@: my-actual-host
@@CT_ID@@:       412
@@LAN_IP@@:       203.0.113.41     # ← a real (private) address here; the example uses a TEST-NET address
```

A tiny deploy step substitutes tokens with values **on the target machine,
or in a gitignored working copy**: the substituted file never enters the
public repo, and the mapping file never leaves the private one.

## Why tokens

1. **One source of truth, zero drift.** The template *is* the document;
   there is no separate "public version" and "private version" to keep in
   sync. The value exists in exactly one place.
2. **Publishable by construction.** A sanitizer sweep over the public repo
   is a *backstop*, not the mechanism: if the template has no secrets by
   design, there is nothing to leak. Sweeps still run on every push (see
   `scripts/sanitize-sweep.sh`), because a template can accidentally
   *describe* an instance in prose even when its fields are tokens.
3. **Adoptable in one step.** A reader takes the public repo as-is; they
   write one mapping file for *their* estate and everything in it becomes
   theirs. That single file is the entire onboarding.
4. **Reversible.** Because values never live in the template, "go back to
   generic" is deleting a line from the mapping, not scrubbing history.

## The worked example

The **monitoring-stack** repo (Prometheus + Grafana for a homelab) is this
contract in production:

- Its Grafana dashboards contain display strings with neutral tokens
  (`@@SITE_A@@`, `@@SITE_B@@`, …); no real site names appear anywhere
  in the repo, and a sweep for them returns zero hits.
- The deploy role carries a **site-map** variable. In the public repo it is
  empty/placeholder; in the private instance it is the mapping that names
  the real sites.
- The private repo is also where the *live* configuration lives (scrape
  jobs with real addresses, secrets in an env file), while the public repo
  holds the roles, dashboards, and the *procedure* for wiring a new host
  into the stack.

So a reader can stand up the whole stack from the public repo against
*their* machines, and the operator of the estate this came from runs the
*same* templates with a different mapping file.

## Using it yourself

1. **Pick your token alphabet.** Small and boring beats clever:
   `@@SITE_<X>@@` for locations, `@@<ROLE>_HOST@@` for machines
   (`@@PRIMARY_HOST@@`, `@@BACKUP_HOST@@`), `@@<SVC>_URL@@` /
   `@@<SVC>_PORT@@` for service endpoints, `@@<NAME>_TOKEN@@` for
   credentials (value always in the private env file, never inline).
2. **Token the public template.** Replace every instance fact with a
   token; add a short comment at first use. The template should read
   naturally *with* placeholders ("on @@PRIMARY_HOST@@, enable…").
3. **Write the private mapping.** One file, values only. It is a secret
   (it is your estate's address book); same handling as any secret:
   never committed to a public remote, ideally not even in plaintext if
   you can avoid it.
4. **Substitute at deploy, not at commit.** Render into a gitignored
   path or directly onto the target; the tool for this is
   `scripts/overlay-apply/overlay-apply` (the section below). Commit only
   the template and the (token-free) mapping *schema*.
5. **Sweep on every push.** The sanitizer greps the public repo for
   address classes and identifier shapes. Zero hits, always, including in
   commit *messages* and history.

## The tool

`scripts/overlay-apply/overlay-apply` is the deploy step made small and
boring. It is stdlib Python; the example in `examples/` is a complete
walk-through (template, mapping, all three subcommands).

| subcommand | what it does | exit |
|---|---|---|
| `render MAPPING FILE... [--out FILE\|DIR]` | substitute values into the template. Multiple inputs need `--out DIR`. **Refuses to write if any token has no value** (lists them); `--allow-unresolved` forces a partial render. Unused mapping values are reported (typo detector). | 0 ok / 2 unresolved |
| `check FILE...` | audit a *rendered* (or should-be-rendered) file for leftover `@@TOKEN@@` placeholders | 1 if any |
| `list FILE...` | print the distinct tokens a template needs, in order: the way to bootstrap a mapping file | 0 |

The mapping file is `KEY=value` or `KEY: value` lines (keys with or
without the `@@` wrappers; `#` comments; the value is everything after
the first separator, so values may themselves contain `=` or `:`). The
token grammar is `@@` + uppercase word (`[A-Z][A-Z0-9_]*`) + `@@`.

Two properties matter more than the rest: **a render never emits
half-rendered output** (the unresolved-token refusal is the whole safety
story), and **check exists so a rendered artifact can prove it is
finished** before it is deployed or committed to a private repo.

It deliberately does *not* bootstrap an estate (no hooks, no settings
files): leiter is the shape, and the instance's own repo owns its
wiring. The tool covers the contract's one mechanical step and nothing
else.

## The failure modes (so you can avoid them)

- **Prose leaks what fields don't.** A field is tokenized but the doc says
  "on the big box…": the *word* is the identifier. The register for
  public text is **role terms** (the domain model's vocabulary), and the
  sweep pattern list should include your site names as words, not just
  address shapes.
- **The mapping wanders.** The moment a value is *convenient* to paste
  into the template ("just for testing"), the contract is broken and the
  value is now in public history. Treat any substitution outside the
  deploy step as an incident.
- **Two private repos.** If the mapping starts living in more than one
  private place, it drifts. One mapping file, one repo.
