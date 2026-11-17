# Home Assistant 2024.11.x: which levers actually work, and what each touches

Verified 2026-11-17 on HAOS 2024.11.1 (Alpine-based host, no docker CLI in the
host shell). 2024.11 is a transition generation: the newer websocket `command`
envelope exists but is nearly empty, and several classic REST views are gone.
Read this before touching a 2024.11.x box; do not re-derive it by trial.

## What each lever loads

| Change | Lever that loads it |
|---|---|
| YAML files (automations, scripts, scenes, …) | **UI "Reload YAML" button** — works in 2024.11. New/edited YAML automations load without a restart. |
| `.storage` stores: lovelace dashboards, entity/device/area registries, config entries, energy store | **Full core restart only.** A YAML reload does not re-read these; the core reads them at boot. Unmodified stores are not rewritten on shutdown, so on-disk edits survive a restart. |
| A dashboard page in an open browser | **Full page reload (F5 / hard refresh).** The frontend fetches dashboard config only on page load; a core restart does not push a new config to an already-open page. |

## External API surface (measured, all dead except webhooks)

- REST `/api/services/*`: removed (plain-text 400).
- REST `/api/command`, `/api/config/*` (incl. automations), `/api/lovelace`: 404
  (views not mounted in this build).
- WebSocket classic `{"type": "service_call", ...}` after a successful `auth`
  handshake: **`unknown_command`** in 2024.11.1 — despite generic help texts and
  older notes claiming otherwise. The newer `command` envelope is present but no
  service/automation command types are registered (`unknown_command` for both).
- The one POST the API accepts: **webhooks** (no auth, no JSON body parsing).
  This is the only external trigger path; everything else means the user's UI,
  the in-UI reload button, or a core restart.

## Core-restart levers (HAOS)

- **UI / mobile-app restart** — the supported path. Add-ons are separate
  containers and are not affected; integrations reconnect.
- **OS `ha` CLI**: `ha core` *lists* only check/info/logs/options/rebuild, but
  **`ha core restart` is a hidden verb that exists and works** (probe with
  `ha core restart --help` — the description block advertises start/stop/restart
  without listing them as subcommands). The estate `ha` CLI's
  `supervisor core restart` wraps exactly this.
- **No docker CLI in the HAOS host shell** — `docker restart core-*` is not a
  lever here (that pattern is for bare-metal docker-HA installs, not HAOS).
- `ha supervisor restart` restarts the supervisor, not the core.

## Z2M integration: name ownership

- In entity-naming mode the Z2M integration **re-syncs the device-registry name
  from Z2M's `friendly_name` on every reconnect** — a registry-only rename gets
  clobbered (measured: renamed on disk, reverted after the core's Z2M reconnect).
- The working rename path: Z2M `device/options` (`friendly_name`) or
  `bridge/request/<area>/device/rename` with `homeassistant_rename: true` (that
  one also changes the HA entity ids → every reference — automations, lovelace
  cards, energy store — must be updated in the same step).

## YAML gotchas that bite in automations (HA 2024.11 parser)

- Unquoted `on` / `off` / `yes` / `no` in a `state:` value become YAML-1.1
  booleans and never match a string state. Quote them.
- Any value containing a colon (MAC addresses, "Some: description") must be
  quoted.
- HA's config validation runs on reload/restart and rejects the whole file with
  a line:column error. Parse with a YAML validator before pushing to the box.
