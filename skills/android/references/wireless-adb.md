# Wireless adb: the connect/pair state machine

The full anatomy of the one gotcha, plus the platform variants.

## What the phone's screen shows

Developer options → wireless debugging has two distinct artifacts:

| Artifact | Lifetime | Used by |
|---|---|---|
| pairing code + pairing port (shown by "Pair with pairing code") | **minutes**; expires, new code generated | `adb pair <ip>:<pairport>` (once per computer) |
| IP address & port card (shown on the main wireless-debugging screen) | **rotates**: changes on network change, screen cycle, toggle; *not* the pairing port | `adb connect <ip>:<port>` (every session) |

After a successful `adb pair`, the card on screen updates to the
*transport* port. Reading the pairing port for a connect is refused by
design.

## The state spaces disagree

The phone's screen ("<computer> is connected") and the adb server's
device list are **different state machines**:

- phone says connected, adb says *offline*: the transport came up but
  the session did not authenticate/complete; fix = fresh card, re-pair
  (new code), connect to the *new* transport port;
- phone says nothing, adb says connected: stale session; a
  `disconnect`/`connect` cycle is fine;
- phone says connected, adb says nothing: the adb server on the host
  was reset (a host that reaps background processes kills it; just
  connect again), or you are on the wrong network plane.

The reliable reset sequence, when in doubt: **fresh card → pair →
connect**, in that order, reading the card fresh at each step.

## Transport planes

- The card's IP is usually the phone's **Wi-Fi** address. If that is on
  a network the adb host can reach, the Wi-Fi address works; if not
  (the phone is on a different site's LAN), the phone's **overlay
  network** address is the one to use. Both are valid; the phone
  listens on whichever interfaces wireless debugging publishes.
  Overlay addresses also rotate on reconnect, so resolve by name at
  connect time, never hardcode.
- **Hardened builds (GrapheneOS)** expose only the TLS transport: the
  legacy plaintext `:5555` path is refused, and there is no
  cable-free authorization fallback. Standard AOSP builds may offer
  the legacy path; do not depend on it, because the hardened side of
  a mixed fleet will not have it.

## The pairing itself

Pairing once adds the computer to the phone's *paired devices* list;
that persists across reconnects, reboots, and network changes. It is
erased by: a new computer (new host key), a factory reset, or the
user deleting the pairing in the phone's settings. Everything else is
a transport problem, not a trust problem.
