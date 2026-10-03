---
name: "@@ANDROID_NAME@@"
description: >-
  "@@ANDROID_DESCRIPTION@@"
---

# Phones over the network

You bring:

- **phones that run AOSP or GrapheneOS** with wireless debugging
  (Developer options → wireless debugging; GrapheneOS exposes only the
  TLS transport, which is the better default);
- **an adb host that can reach the phones over your overlay network**
  (or their LAN);
- **a paired trust** per computer (pairing persists in the phone's
  paired-devices list; only new computers or wiped phones need to pair
  again).

The references carry the deep material: `wireless-adb.md` (the
connect/pair state machine), `home-screen.md` (driving the UI),
`data-migration.md` (moving data and apps), `dead-ends.md` (what does
*not* work, verified).

## The one gotcha that matters: two ports, one rotates

The wireless-debugging screen shows **two different things**:

1. a **pairing code and a pairing port** (one-time; `adb pair`), and
2. an **IP address and port card** for `adb connect` (the *transport*).

The transport port **rotates**: it changes whenever the phone's network
changes (Wi-Fi switch, overlay reconnect), the screen is cycled, or
wireless debugging is toggled. It is not the pairing port, and a
connect refused at the pairing port is *expected*. The pairing card is
also **short-lived** (minutes): a refused `adb pair` means the card
expired, ask for a fresh one; the pairing itself, once done, persists.

So the connect flow, every time:

```
is the phone's network node up?        → if not, stop (human must wake it)
ask the human to read the IP+port card → adb connect <ip:port>
sanity: a screenshot                    → is it awake, what's focused?
```

One short question to a human ("read me the port card") replaces an
hour of guessing. The phone can also display "computer connected"
while adb still reports the device *offline* or not at all: the
phone-side and the adb-side state are different things, and the fix is
the full sequence (fresh card → pair → connect to the *new* transport
port), not a retry of the same one.

## Daily operations

The estate's `px` wrapper names the phone, resolves its address, and
gives one command per action: `shot` (screenshot to a file, then *read
the image*: it is the fastest way to see any on-screen state), `tap`,
`run` (an adb shell command), `log` (logcat with the platform's audit
noise filtered), `stayon`, `install`, `battery`. The wrapper is
optional; the commands are plain adb.

GUI state, in order of preference:

1. **`uiautomator dump` first**: the accessibility tree of the
   foreground window as XML; every element with its text and pixel
   bounds, and the tap target is the center of the bounds. No pixel
   guessing. It fails on windows that never go idle (GL-rendered
   apps, live video) with a timeout error, and for those the
   screenshot is the instrument.
2. **screenshots for what a dump can't express** (progress, layout,
   rendered content).
3. **the 600ms-press rule**: synthetic *taps* (`input tap`) are
   silently ignored by some system dialogs (observed on the backup
   confirmation window); a short *press* at the same coordinates
   (`input swipe x y x y 600`) works. When a tap "does nothing", the
   fix is often a longer press, not a better coordinate.

## Discipline

- **Re-entrant everything**: the connection, the adb server on the
  host, and the phone's screen state can all have been reset between
  two of your calls (hosts that wipe scratch space and reap background
  processes will kill a local adb server; the phone sleeps; the port
  rotated). Re-check before you act; never assume the previous call's
  world.
- **Scratch space**: on the phone, `/data/local/tmp` survives until
  reboot, user-visible files go to the card; on the host, use durable
  scratch, not a volatile temp that a cleaner reaps (the adb server
  included).
- **Screenshots are a recording surface**: never capture or keep
  frames showing secrets (recovery keys, PINs, 2FA codes); redact or
  don't capture, and delete captures that already contain them.
- **Unattended windows are a power fact**: "stay on" flags on these
  platforms usually hold *only while charging* (the screen will sleep
  on battery even if asked not to); check the power state before you
  plan an unattended session.
- **Backgrounding is interruption**: sending the phone home or locking
  it pauses whatever the foreground session is doing (recordings,
  camera sessions); plan the window accordingly.
- **App install is a trust decision**: an APK sideloaded over adb is
  you, saying "install this", and the phone (especially a hardened
  build) will make that explicit. Install from a source you would run,
  and say what you installed and where it came from.

## Migration (the short version)

- **`pm clear <pkg>` wipes an app's data. Never run it "to clean
  up".** App data lives in the per-package data directory, which on a
  user build is root-only.
- **`adb backup`/`adb restore` is not a data path on modern
  (file-encrypted) builds**: the current backup service accepts only
  manifest-based encrypted entries, and the platform's own apps back
  up through that path exclusively, so the legacy transport yields
  empty archives in both directions. The usable transports are the
  per-app ones (the apps' own export/migration features, file-based
  exports, a root shell where you have one) and, for apps,
  sideload + the app's own import. `data-migration.md` has the per-app
  patterns; `dead-ends.md` has the wire-format anatomy of *why* the
  legacy path is dead, so it is never re-explored.
- **Usage statistics** on hardened builds are thinner than on stock:
  the raw `dumpsys usagestats` event stream (foreground resumptions per
  package, widget interactions) is the usable signal; a small
  on-device logger (F-Droid) can build a multi-week baseline, and its
  permission can be granted over adb (`appops`).

## Dead ends: the fourth document

A phone-automation corpus earns a **dead-ends document**: the paths
that were investigated and *proven* not to work (programmatic launcher
layout without root on user builds; the adb backup/restore protocol;
various encoders), each with the verdict, the evidence, and the date.
It is the difference between a session that spends eight hours
re-discovering a wall and one that starts past it. When you verify
something does not work, write it down with the same care as a success;
it is knowledge, just negative.

---

<!--
  Estate instance section. An estate that maintains a mapping for this
  skill (the overlay contract: ../docs/overlay-contract.md) renders its
  instance content -- machines, paths, what this fleet has hit -- at
  this spot, at deploy time. The raw shape ends here.
-->
@@ANDROID_ESTATE@@
