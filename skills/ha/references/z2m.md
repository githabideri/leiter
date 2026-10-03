# Zigbee2MQTT: the bridge over MQTT

The bridge is driven by MQTT, not by an HTTP API (and note the version
trap: the single `zigbee2mqtt/api` topic is a 2.x feature; on a 1.4x
bridge add-on it does not exist, and the broker silently drops the
2.x-only `bridge/request/ota/check` too). On 1.4x you drive the direct
topics. Inside the OS the bundled broker is the right one; everything
runs as a short-lived subscribe or publish, which is what keeps it
scriptable from a remote shell.

## The topics you need

| topic | direction | use |
|---|---|---|
| `zigbee2mqtt/bridge/state` | sub (retained) | alive? `online`/`offline` |
| `zigbee2mqtt/bridge/info` | sub (retained) | version, network parameters |
| `zigbee2mqtt/bridge/devices` | sub (retained) | the whole device list (IEEE, friendly name, state, interview) |
| `zigbee2mqtt/<friendly_name>` | sub (retained) | last state of one device |
| `zigbee2mqtt/<ieee>/set` | pub | ZCL service call, e.g. factory-reset a device's *settings*: `{"command":{"cluster":"genBasic","command":"resetFactDefault","payload":{}}}` (resets converter defaults like child-lock and power-outage memory; the switch position is not touched) |
| `zigbee2mqtt/<ieee>/get` | pub | raw ZCL read with no side effects; **no response within ~25s means the device is offline** (this is the cheapest reachability probe you have) |
| `zigbee2mqtt/bridge/request/<action>` / `.../response/<action>` | pub / sub | `permit_join` `{"value":true,"time":60}`, `device/rename` `{"from":...,"to":...,"homeassistant_rename":true}`, `device/options`, `device/remove` `{"id":...}`, `ota/update/check`, `ota/update/<device>` |

## The rename hazard (read before renaming anything)

`device/rename` with `homeassistant_rename:true` renames the HA
entities but sets **no** `old_ids` in the entity registry. Anything
that references entity IDs by string (dashboard UI configs, the energy
dashboard, dashboards exported elsewhere) silently breaks. The fix is
an on-disk edit of the affected `.storage` files (the UI config, the
energy store) followed by a core restart; HA holds stores in memory and
does not rewrite unmodified stores on shutdown, so the edit survives.
Rule: rename a device only with a plan for its references.

## IKEA TRÅDFRI: the frequent drop

TRÅDFRI bulbs drop off the zigbee network more often than other
families; when one is gone, factory-reset and re-pair instead of
chasing it:

1. Toggle the power switch on-off, six times, fast.
2. Leave it on after the sixth on.
3. The bulb flashes once and dims: it is in pairing mode.
4. `ha z2m permit_join 60`, then confirm it appears in `ha z2m devices`.

## Exposing HA through a reverse proxy

If HA sits behind a public proxy, expose only the read paths you need
(`/api/`, `/api/states`, `/api/history/period/*`) and deny the rest
(`/api/statistics/*`, `/api/lovelace/*`, `/api/config/*` in particular:
the config endpoint is an administrative surface, not a monitoring
one). The practical consequence: you cannot patch UI or energy stores
through the proxy; on-disk `.storage` edits are the workaround (see the
rename hazard).

## Known limitations (1.4x add-on)

- `bridge/request/networkmap` may time out (endpoint not reliably
  supported).
- `bridge/request/ota/check` gets no response (2.x-only; tested with a
  120s client timeout, nothing comes back).
- When a request topic gets no response, suspect the bridge version
  before you suspect the network.
