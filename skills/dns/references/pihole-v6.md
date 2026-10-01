# The Pi-hole v6 store (reference implementation of the store-vs-generated rule)

Verified against FTL v6.7 (2026-09-06), with three observed incidents of
the generated file wiping hand edits.

## The layout

| File | Role |
|---|---|
| `/etc/pihole/pihole.toml` | **the store.** The `[dns] hosts` array (A records as `"IP hostname"` entries) and the `[dns] cnameRecords` array (as `"name,target"` entries). FTL re-renders everything downstream from this on every start |
| `/etc/pihole/hosts/custom.list` | **generated.** FTL renders the toml into it on every start (and on nightly update restarts). Never hand-edit: edits die on the next restart |
| `/etc/pihole/dnsmasq.conf` | **also re-rendered** (upstream DNS, DHCP range, `dhcp-host=` lines) from FTL's own config. A patched `dhcp-host=` line can die on restart; the durable place for a lease is FTL's store-side key, found by checking what the re-render keeps |
| `/etc/pihole/dhcp.leases` | current DHCP leases (read-only view) |
| `/etc/dnsmasq.d/` | does **not** work on this build (no conf-dir wired in); don't waste an hour on it |

## The change pattern (one node)

1. Back up `pihole.toml` (timestamped copy).
2. Edit the **right array**: `IP hostname` shape goes to `[dns] hosts`;
   `hostname target-hostname` shape (a CNAME) goes to
   `[dns] cnameRecords`. FTL **silently ignores** a CNAME-shaped entry
   in `hosts`: it renders it into `custom.list` but never resolves it.
   The script decides by argument shape; if you do it by hand, the
   shape is the rule.
3. Validate the toml parses *before* restarting:
   `python3 -c "import tomllib; tomllib.load(open('/etc/pihole/pihole.toml','rb'))"`.
   A broken toml at FTL start is a DNS outage on that node.
4. `systemctl restart pihole-FTL` (FTL re-reads the toml on start;
   `pihole reloaddns` does not re-read the hosts array the same way).
5. Verify: `dig +short @localhost <name>` returns the new value.

## The HA pair

The pair (two LXC nodes, config sync between them) has had an
unreliable sync endpoint (a 400 from the second node's config API,
observed and unresolved for months). The working rule: **apply to both
tomls, verify both with `dig`**. The estate's script loops the node
list (`PIHOLE_NODES` to override) doing the whole pattern per node.
When the nodes disagree, the drift is a finding: fix or accept the
sync layer deliberately, don't mask it.

## Reading state

- `cat /etc/pihole/hosts/custom.list` — the generated mirror (fine for
  reading; the toml is the truth for writing)
- `cat /etc/pihole/dnsmasq.conf` — upstream DNS, range, leases
- `cat /etc/pihole/dhcp.leases` — who is currently where
- `pihole -v`, `pihole -t`, `pihole -q <domain>` — version, query log,
  resolution test

## Removing a record

Delete the entry from the toml array (both nodes), validate, restart
(both), `dig` (both). The generated files clean themselves on the
restart; if a stale line lingers in `custom.list` after a verified
restart, you are editing the wrong file somewhere.
