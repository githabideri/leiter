# JSON fields (when extending the reference CLI)

The shapes the reference CLI emits, so a second implementation or a
jq one-off speaks the same language.

## `ha -j dashboard`

```
version                 HA core version (from /api/config)
summary.total           all entities
summary.on / .unavailable / .unknown
lights.total / .on
open_sensors[]          binary_sensor.* with state "on"
```

## `ha -j state <entity>` (the raw state object)

```
entity_id, state, attributes{}, last_changed, last_updated,
context{}, hidden_by{}
```

## `/api/states` elements

Objects only (verified on 2024.11): same shape as above. Group by
`entity_id | split(".")[0]` for the domain view.

## `/api/logbook` (2024.11)

Flat array of `{entity_id, icon, name, state, when}`. Newer HA versions
return a different shape (`entity{}`, `created_at`, `for_human`,
`data{}`) per entry; a portable implementation should try both.
`when` is a full ISO 8601 with offset; the CLI displays it as
`[YYYY-MM-DD HH:MM:SS]`.

## `/api/history/period/...`

Array of arrays: `[ [state, state, ...], ... ]`, each element a state
object. The first inner array is the requested entity.

## Scope model fields (env, not JSON)

`HA_URL`, `HA_TOKEN`, `HA_SCOPE` (`user`|`admin`), `HA_READ_ONLY`,
`HA_SSH`, `HA_MQTT_HOST`, `HA_MQTT_PORT`, `HA_MQTT_USER`,
`HA_ALLOWED_DOMAINS`, `Z2M_TOPIC`. The token's server-side permissions
are the floor; these are the ceiling.
