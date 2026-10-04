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

## Platform variants

- **GrapheneOS 17 on Pixel 9 Pro (observed 2026-10-04): pairing and
  transport share the card's port.** The main wireless-debugging screen
  showed one port (35739) and `adb connect` to it was *refused* until
  the pairing dialog (separate ephemeral port 46843 + code) was
  completed, after which the **same** card port accepted the transport
  connection. The doc's "card updates to the transport port; the
  pairing port is separate" model does not hold on this build: here
  the card port *is* the pairing port until pairing exists, and it
  becomes the transport port afterwards. Operationally this is a
  simplification: one port to read, and the refused-connect → pair →
  retry sequence below still works as written.
- **First pair attempt can be a false negative.** `adb pair` failed with
  `protocol fault (couldn't read status message): Success` while the
  phone's dialog still showed *waiting*; re-opening the pairing dialog
  (new code/port) and pairing again succeeded. Treat that error as "the
  attempt raced the dialog", not as a trust problem: retry with a fresh
  code before suspecting keys.
- **The mDNS advertisement names the phone by its adb serial**
  (`adb-<SERIAL>-<random>`). On a LAN where the overlay IP is not
  routable, the adb mDNS service record on the local network is a valid
  fallback transport address; because the serial is in the name,
  multi-phone hosts can match the record to a known device instead of
  guessing. A fleet helper can cache the transport per phone and
  auto-reconnect (retry the cached address, fall back to the mDNS
  record for the phone's serial, then ask the user for a fresh card).
- **adb aliases one live transport under several names** (the mDNS
  service name and each IP it was reached on) and can keep a *stale*
  alias line (`offline`) for a transport that is fine under another.
  Tooling that picks "the first matching line" will grab the stale one;
  prefer lines in state `device`, and pass only the key (not the whole
  line) to `-s`.

## The pairing itself

Pairing once adds the computer to the phone's *paired devices* list;
that persists across reconnects, reboots, and network changes. It is
erased by: a new computer (new host key), a factory reset, or the
user deleting the pairing in the phone's settings. Everything else is
a transport problem, not a trust problem.
