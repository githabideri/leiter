# Home Assistant 2024.11.x: which levers actually work, and what each touches

Verified 2026-11-17 on HAOS 2024.11.1 (Alpine-based host, no docker CLI in the
host shell). 2024.11 is a transition generation: the newer websocket `command`
envelope exists but is nearly empty, and several classic REST views are gone.
Read this before touching a 2024.11.x box; do not re-derive it by trial.

## What each lever loads

| Change | Lever that loads it |
|---|---|
| YAML files (automations, scripts, scenes, …) | **UI "Reload YAML" button**: works in 2024.11. New/edited YAML automations load without a restart. |
| `.storage` stores: lovelace dashboards, entity/device/area registries, config entries, energy store | **Full core restart only.** A YAML reload does not re-read these; the core reads them at boot. Unmodified stores are not rewritten on shutdown, so on-disk edits survive a restart. |
| A dashboard page in an open browser | **Full page reload (F5 / hard refresh).** The frontend fetches dashboard config only on page load; a core restart does not push a new config to an already-open page. |

## External API surface (measured, all dead except webhooks)

- REST `/api/services/*`: removed (plain-text 400).
- REST `/api/command`, `/api/config/*` (incl. automations), `/api/lovelace`: 404
  (views not mounted in this build).
- WebSocket classic `{"type": "service_call", ...}` after a successful `auth`
  handshake: **`unknown_command`** in 2024.11.1, despite generic help texts and
  older notes claiming otherwise. The newer `command` envelope is present but no
  service/automation command types are registered (`unknown_command` for both).
- The one POST the API accepts: **webhooks** (no auth, no JSON body parsing).
  This is the only external trigger path; everything else means the user's UI,
  the in-UI reload button, or a core restart.

## Core-restart levers (HAOS)

- **UI / mobile-app restart**: the supported path. Add-ons are separate
  containers and are not affected; integrations reconnect.
- **OS `ha` CLI**: `ha core` *lists* only check/info/logs/options/rebuild, but
  **`ha core restart` is a hidden verb that exists and works** (probe with
  `ha core restart --help`: the description block advertises start/stop/restart
  without listing them as subcommands). The estate `ha` CLI's
  `supervisor core restart` wraps exactly this.
- **No docker CLI in the HAOS host shell**: `docker restart core-*` is not a
  lever here (that pattern is for bare-metal docker-HA installs, not HAOS).
- `ha supervisor restart` restarts the supervisor, not the core.

## Z2M: renaming a device (new API, 1.17+/1.4x)

- In entity-naming mode the Z2M integration **re-syncs the device-registry name
  from Z2M's `friendly_name` on every reconnect**: a registry-only rename gets
  clobbered (measured: renamed on disk, reverted after the core's Z2M reconnect).
- The documented rename endpoint (new API): publish to
  **`zigbee2mqtt/bridge/request/device/rename`** with
  `{"from": "<ieee or old name>", "to": "<new name>", "homeassistant_rename": true}`.
  Response arrives on `zigbee2mqtt/bridge/response/device/rename`
  (`{"data":{...},"status":"ok"}`); that is your verification. With
  `homeassistant_rename: true` the HA integration migrates the entity ids to
  the new name; every reference outside discovery (YAML automations, lovelace
  card ids, energy store) must be updated in the same step anyway.
- Other device options go to `zigbee2mqtt/bridge/request/device/options`
  (`{"id": ..., "options": {...}}`); some set `restart_required: true`.
- The legacy per-device `zigbee2mqtt/<name>/config` topic is pre-1.17 and is not
  documented for the new API; do not rely on it on 1.4x. Publishing to the
  state topic `zigbee2mqtt/<name>` is **not** a command (see estate notes).
- On HAOS the broker credentials are not in a visible config file; the add-on's
  config entry (`.storage/core.config_entries`, `birth_message` field)
  carries the `user=...\npassword=...` line. Extract with an anchored parse
  (the password may contain `/`; do not use it as a sed delimiter).

## Boot forensics on HAOS (2024.11)

- The core runs in its own environment: the host root shell has **no python3**,
  only the compiled `ha` bridge. The core log is `/homeassistant/home-assistant.log`,
  **rotated on every boot** (current + one previous; older boots are lost), and
  a zero-byte `.fault` file marks a death. No traceback in the log = the
  process was killed or aborted without writing (a signal, or the event-loop
  thread died after the last log line).
- A custom component that does blocking work in a `HOMEASSISTANT_STARTED`
  callback, e.g. a config scanner that recursively walks the whole config
  directory, can kill the entire process mid-boot: unhandled exception (or a
  blocking `open()` on a file being written) → death before "Home Assistant
  started", no web listener. Under s6 supervision this looks like a **crash
  loop with growing backoff** (retries tens of minutes apart), which reads as
  "the box is dead".
- A slow boot is normal: many HACS repos make the boot phase print `json_loads`
  deprecation warnings for minutes, and the API is legitimately down for a
  while after start. **Do not restart mid-boot**: every restart resets the
  boot clock. When diagnosing a suspected crash loop, monitor read-only
  (poll the API, tail the log, inspect /proc) and give one boot 10–15 minutes.
- To disable a misbehaving custom integration without its UI: in
  `.storage/core.config_entries`, set `"disabled_by":"user"` inside the entry's
  JSON object (back the file up; the core skips disabled entries at boot). The
  key order in that file is not stable; anchor the edit on
  `"domain":"<name>"` and **verify the result with a grep**; an unverified
  in-place edit is the kind of thing that silently changes nothing.
- Forensics footgun: a monitoring loop that greps `/proc/*/cmdline` for the
  target process matches its own grep (the pattern is in its own cmdline) and
  reports a dead box as alive. Match on the `comm` file or an anchored
  pattern instead.

## YAML gotchas that bite in automations (HA 2024.11 parser)

- Unquoted `on` / `off` / `yes` / `no` in a `state:` value become YAML-1.1
  booleans and never match a string state. Quote them.
- Any value containing a colon (MAC addresses, "Some: description") must be
  quoted.
- HA's config validation runs on reload/restart and rejects the whole file with
  a line:column error. Parse with a YAML validator before pushing to the box.
