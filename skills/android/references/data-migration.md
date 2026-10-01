# Data and app migration between phones

The transport decision tree and the per-app patterns.

## The transports, in order of preference

1. **the app's own export/migration** where it has one (many
   messaging, note, and password apps do): it is the only path that
   carries the app's internal formats correctly, and the receiving
   app's import is the verification.
2. **file-based**: the app's user-visible files (documents, images,
   exported databases) move as files (the card, a shared folder, or
   the overlay network directly: a phone is a machine with a network
   address; `scp`/`rsync` to and from it where the OS exposes a
   shell, which GrapheneOS does for its user).
3. **adb shell as the pipe**: where the phone runs a build with an
   accessible shell, the per-app data directory (root-only) can be
   copied out as a tar and pushed to the equivalent location on the
   target, *after* both apps are uninstalled/cleared on the target
   and *before* they run again (an app overwriting its data dir on
   first launch will destroy what you pushed). This is the closest
   thing to a true data move on a user build.
4. **sideload + in-app import**: install the app on the target (an
   APK transfer is a file transfer), then let the app import from
   the source where it supports it.

## The hard rules

- **`pm clear <pkg>` destroys the app's data directory.** It is the
  wrong tool for "clean up" and the right tool for "make room for a
  push", which is exactly why it must never be a reflex.
- **`adb backup`/`adb restore` does not carry app data on modern
  builds** (the anatomy is in `dead-ends.md`: the backup service
  accepts only manifest-based encrypted entries, and the platform
  apps back up through that path exclusively, leaving the legacy
  transport with empty archives). Do not plan a migration on it.
- **order of operations on the target**: stop the app (force-stop),
  clear or remove it if the data will be pushed, push, then let the
  app start. An app writing its defaults over your pushed data is a
  race you lose.
- **verify by use, not by byte count**: the target app *opening the
  moved data correctly* is the completion check (a chat app shows the
  history; a password manager lists the entries). Sizes matching is
  necessary, not sufficient.

## Usage statistics (the "top apps" signal)

Hardened builds emit a thinner usage stream than stock:

- the persisted usage-stats containers are often empty (the events
  the stock pipeline consumes are not emitted); the raw
  `dumpsys usagestats` event stream is what works: foreground
  resumptions per package, widget interactions, keyguard and screen
  state, roughly a day deep;
- snapshot it periodically (`adb exec-out dumpsys usagestats`) and
  count resumptions per package for a per-app "time in use" proxy
  without an on-device logger;
- for a multi-week baseline, a small on-device logger (available on
  F-Droid) writes its own per-day log; its usage-statistics
  permission can be granted over adb (`appops set <pkg>
  GET_USAGE_STATS allow`), which saves the user a settings dig.
