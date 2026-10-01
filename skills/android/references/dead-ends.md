# Dead ends: verified negative knowledge

This document exists so that a session never re-pays the discovery
cost of a wall. Every entry was investigated to a verdict, with the
evidence and the date; a verdict expires only if the OS/build that
produced it changes materially (re-verify before relying on an entry
older than a major release on your side).

The house rule: **when you prove a path does not work, write it down
with the same care as a success.** A negative result with evidence is
knowledge; an unwritten one is a toll that every future session pays
again.

## The verified dead ends (reference build: hardened AOSP, user
builds, adb 37.x; 2026-09)

| Path | Verdict | Why (the evidence that closes it) |
|---|---|---|
| Programmatic launcher layout without root (content-provider layout import/export on the stock launcher) | dead | the shell user is denied by the provider (a live `SecurityException`); a helper APK signed with the *public* platform key is also denied on-device, because the production platform key is not the public test key; no system app on the hardened build holds the permission. The remaining routes are touch-drag gestures or a human arranging the layout |
| Pushing a layout database into the launcher's data directory | dead on user builds | the data directory is root-only and `adb root` is unavailable on user/release builds; it is available on userdebug builds (a different purchase) |
| `adb backup` / `adb restore` as an app-data transport | dead for app data on this generation of builds | the current backup service rejects legacy (non-manifest) file entries outright, and the platform's own apps participate only in the manifest/encrypted path, so the legacy transport yields empty archives in both directions: you can neither extract a real archive nor inject files |
| The backup-confirmation dialog, driven by synthetic taps | dead as a tap; alive as a press | the dedicated confirmation window ignores short synthetic taps; a 600ms press at the button center works. The window is about 60s and starts when the *dialog* appears, so the tap must land within seconds of the window being detected (fast-poll the window list, do not sleep between detection and tap) |
| The legacy `.ab` wire format, hand-assembled | dead | the format on this build is a header followed by a **zlib** stream (not gzip) wrapping a tar; a gzip payload fails the restore socket read with an incorrect-header error. Even with the format right, the service's manifest-only acceptance (above) blocks the payload |
| Expecting `usagestats` persisted containers or a JSON query interface | dead | the containers are empty on the hardened build and the JSON query form of the dump is unsupported; the raw event stream is the working surface (see `data-migration.md`) |

## How to add an entry

One row: the path (named concretely enough that a future session
recognizes it), the verdict (dead / alive-with-caveat), and the
*reason* stated as the mechanism, not the symptom ("the provider
denies the shell user" not "it didn't work"). Date it, name the build
generation, and if a related path is *partially* alive, say exactly
which part (the press-not-tap row is the model: the dialog is real,
the interaction is just not a tap).
