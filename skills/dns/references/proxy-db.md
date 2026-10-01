# The DB-driven proxy (NPM-class reference implementation)

Nginx Proxy Manager 2.12.3 specifics, but the three-step pattern is the
portable part for any DB-rendering proxy.

## The three steps, concretely

Inside the `nginx-proxy-manager` container:

| Artifact | Location |
|---|---|
| the DB (the declaration) | `/data/database.sqlite` — tables `proxy_host` / `redirection_host` (with JSON `domain_names`, `created_on`/`modified_on`) and `certificate` |
| the rendered configs | `/data/nginx/proxy_host/<id>.conf`, `/data/nginx/redirection_host/<id>.conf` |
| the reload | `nginx -s reload` |

**Add**: insert the row, write the conf from the template, reload.
**Disable**: set `enabled=0` in the DB, **delete the conf file**,
reload (a disabled row with a live conf still serves traffic).
**Remove**: delete row + conf, reload.

The estate's wrapper (`npm-cli`) does all three per call, with
`--dry-run` printing the SQL and the conf instead of executing, and an
`--instance` flag for running more than one proxy box (the pattern:
same script, instance selects the container and DB).

## Verifying a change (the Host-header trick)

You do not need the public name to test a new proxy host; route through
the proxy's own address with the target's Host header:

```bash
curl -sI -H "Host: new.example.internal" http://<proxy-box>
```

A 200/301 from the right upstream means the conf is live; a 404 means
the reload or the conf is the problem (the DB is already green); a
connection error means the upstream. Check the **effective** config
(`nginx -T`, or the file in `/data/nginx/`), not the DB row, when these
disagree.

## Certificates

The estate's wildcard for its internal domain is renewed by **certbot
running inside the proxy container**, using the provider's DNS plugin
(`certbot-dns-<provider>`) against the provider's **legacy API** (a
documented decision: the modern API was worse for this workflow; churn
in a working renewal path is how a cert stops being renewed).

Two facts that change how you operate it:

- **The provider credentials live in the DB** (the `certificate.meta`
  blob), not in any file on the box. Nothing on disk to inspect,
  rotate, or back up in the ordinary way; the DB *is* the credential
  store for this.
- **There is no cert-edit action** (neither UI nor API in 2.12.3).
  Rotating the provider credentials is: stop the container, update the
  DB blob, start the container, trigger a renewal, verify. It is a
  deliberate window, not a live edit.

Track every cert's expiry in the proxy registry (a `certs` listing the
issuance and expiry per domain) and put the long-lived wildcard's
renewal window on a calendar: when it lapses, *every* site under the
domain breaks simultaneously, which presents as a proxy outage and
misdirects the first responder.

## The registry

`configs/<proxy>/…-hosts.md` (per instance): every proxy host,
redirect, and cert, regenerated or updated in the same step as the
change. The skill never lists current hosts; the registry does, and a
change that doesn't touch the registry is half done.
