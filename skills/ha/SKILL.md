---
name: ha
description: >-
  Operate Home Assistant from the command line with a two-scope agent
  model: a user-scope token for everyday monitoring and device control
  (lights, scenes, sensors, health) and an admin-scope token for
  supervisor/backup/Zigbee2MQTT work, with the scope enforced by the
  tool, not by convention. REST API via long-lived access token,
  supervisor via SSH to the OS, Zigbee2MQTT via MQTT. Ships a standalone
  reference `ha` CLI (bash + curl + jq). Use for "check my smart home",
  "turn on a light", "battery status", "add-on restart", "pair a zigbee
  device", HA troubleshooting (logs, logbook, history).
---

# Home Assistant

Two access paths, two scopes, and the scope is a property of the
*toolchain*, not of the prompt:

1. **REST API** (`:8123`) with a **long-lived access token (LLAT)**.
   Entities, states, services, history, logbook, error log, scenes,
   scripts, automations-as-entities. No SSH involved; this is all the
   *user* scope needs, and it is the only path a reverse proxy should
   expose (see `references/z2m.md` for the path-list lesson).
2. **Supervisor / OS** via **SSH into the OS**, driving the `ha` CLI
   that ships with the OS (`ha addons ...`, `ha core ...`, `ha host
   ...`). Add-ons, backups, core restart, host power.
3. **Zigbee2MQTT** via **MQTT** (inside the OS: the bundled broker),
   the bridge request/response topics, plus direct per-device topics.

The token is the scope. A user-scope LLAT cannot do admin things no
matter what the CLI allows; the CLI's scope guard is a second,
faster-failing layer on top. Two tokens, two env files, two scopes;
the agent picks the env file for the task.

## Scope model (the doctrine)

| Variable | Effect |
|---|---|
| `HA_SCOPE=user` (default) | Blocks `supervisor`, `z2m`, automation enable/disable. Only the service domains you list as allowed. |
| `HA_SCOPE=admin` | Everything. Use only when the task is admin. |
| `HA_READ_ONLY=1` | Blocks all writes in any scope: service calls, scene apply, automation toggles, core restart, backups, OTA, zigbee writes. For "investigate, don't touch" sessions. |
| `HA_URL`, `HA_TOKEN` | Endpoint + LLAT. The token's own permissions are the floor; the scope guard is the ceiling. |

Rule of engagement: **default to the narrowest scope that can do the
task.** A monitoring request runs user-scope; an add-on restart runs
admin-scope; a diagnosis session runs read-only. Escalate by switching
env files, not by editing the guard.

## The CLI (reference implementation in `scripts/ha.sh`)

The shipped script is a single-file reference: bash + curl + jq, no
other dependencies. It reads its config from the environment and
enforces the scope table above. Port it into your estate, or use it
as-is against any HA install.

| Command | Scope | What it does |
|---|---|---|
| `ha dashboard` | any | One-shot health: version, entity counts, unavailable, open sensors, add-on updates pending |
| `ha state [entity]` | any | Full inventory grouped by domain, or one entity with attributes |
| `ha entity list [domain]` | any | Inventory narrowed to a domain (do this instead of `ha state` on large estates) |
| `ha service call <domain>.<service> [json]` | any (writes blocked when read-only) | Call any service with a JSON payload |
| `ha scenes` / `ha scene apply <name>` | user ok | List scenes / activate one |
| `ha scripts` / `ha service call script.*` | user ok | List scripts / run one |
| `ha automations` / `ha automation enable\|disable <id>` | list any; toggle admin | Automations are entities, not a separate endpoint |
| `ha system` | any | OS version, location name, loaded components, state |
| `ha logs [n]` | any | Error log tail (**plaintext, not JSON**: never pipe it into jq) |
| `ha logbook [n]` | any | Recent events; `-i <ids>` to ignore noise entities |
| `ha history <entity>` | any | Today's time series for one entity |
| `ha batteries [threshold]` | any | Entities below a battery threshold (default 20%) |
| `ha supervisor <subcmd>` | admin | Passthrough to the OS `ha` CLI: `addons`, `addons <name> <action>`, `core restart`, `host info` |
| `ha z2m <subcmd>` | admin | Bridge status, devices, permit-join, per-device state, rename, remove (see the reference) |

Output modes: default is a token-efficient tabular (TOON-ish) form with
a summary line; `-j` gives raw JSON (field names in
`references/output-fields.md` if you extend the script); `-q` drops the
summary line; `-i a,b` filters entities out of logbook/history.

## Logbook noise (learn this once, save tokens forever)

Clock and sun entities log every minute or every event and drown real
changes. Always run logbook with the noise entities ignored:

```
ha -i sensor.date_time_iso,sun.sun logbook 50
```

The CLI collapses consecutive runs of the same entity into
`... 1295 more entries`, which is what makes a 1440-entries-a-day log
readable at all.

## Common error patterns

| Pattern | Meaning |
|---|---|
| `Referenced entities ... missing or not currently available` | The device is unreachable, not the service. Flaky radio stacks (zigbee) do this constantly; check the device before you suspect HA. |
| `Login attempt with invalid authentication` | Token revoked, rotated, or wrong env file sourced. |
| `404` on an entity that "should exist" | It may be a zigbee device without HA discovery; the CLI cross-checks the bridge. |
| Service call succeeds but state unchanged | The device dropped the command (radio), or the entity is unavailable. Read the logbook for the entity, not the service response. |

## Routing

| if the task is... | read |
|---|---|
| zigbee pairing, firmware, device quirks, the rename hazard, reverse-proxy exposure | `references/z2m.md` |
| writing/extending your own CLI on the same model | `scripts/ha.sh` (it is the reference) |
| "is something wrong?" | `ha dashboard`, then `ha logbook -i <noise> 50`, then `ha state <entity>` |
