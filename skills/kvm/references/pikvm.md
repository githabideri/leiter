# PiKVM / kvmd: the reference implementation

The concrete system this skill's patterns were distilled from: PiKVM
on a Raspberry Pi Zero 2 W class SBC, `kvmd` (the KVM daemon, 4.18x
line), `ustreamer` for H.264 video, OTG for the HID and MSD gadgets,
OCR via the bundled OCR pipeline, TLS with a verified certificate.

## The API surface (what the wrapper drives)

| Area | Endpoints | Notes |
|---|---|---|
| info | `GET /api/info` | version, platform, streamer state |
| HID (keyboard/mouse) | `GET /api/hid` (status), `POST /api/hid/reset`, `POST /api/hid/connect`, `POST /api/hid/disconnect`, `POST /api/hid/keydown` / `keyup` (with `keymap=`), `POST /api/hid/mousemove`, `POST /api/hid/mouseclick`, `POST /api/hid/mousescroll` | `keymap=` on every key call; mouse coordinates are absolute pixels in the current video resolution |
| video | `GET /api/screen/snapshot` (JPG) | requires a stream lease first (below) |
| OCR | `GET /api/ocr` (text), `GET /api/ocr-status` | runs on the last/current frame; languages configured in kvmd |
| MSD (virtual media) | `GET /api/msd` (status), `POST /api/msd/images/upload` (raw body), `POST /api/msd/select` (`cdrom=1/0`, `read_only=1/0`), `POST /api/msd/connect`, `POST /api/msd/disconnect`, `POST /api/msd/reset`, `DELETE /api/msd/images/<name>`, `POST /api/msd/write` (remote download) | see the state model in the main file |
| stream lease | WebSocket `/api/ws` with a `stream` parameter | the daemon starts/stops the streamer on lease acquire/release; `stream=0` is state monitoring only |

A thin CLI wrapper over this surface is the practical unit: one
command per API action, JSON out, plus the composite `run`
(pre-snapshot, typed key sequence with delays, separate Enter,
post-snapshot). The estate's wrapper is a uv-isolated Python package
behind a shell wrapper that loads the credentials from the config
store; the wrapper must be invoked by its PATH name, because the
PATH wrapper is the one that loads the secrets (direct venv
invocation skips them).

## Hardware quirks that change behavior

- **Mouse `online=false` is a reading, not a state.** On the OTG
  configuration the target sees a composite USB gadget with three HID
  interfaces, and kvmd's mouse-online flag has no feedback mechanism
  to set. The functional test is a **visible cursor move** (snapshot
  before/after a relative move), not the flag.
- **The HID gadget and the MSD gadget share the OTG port.**
  Connecting/disconnecting one can disturb the other; expect
  re-enumeration on the target (seconds, or a reboot after a mode
  change) and verify on the target, not in the API.
- **The streamer on a Zero-class SBC is the scarce resource.** The
  lease model (wake per operation) is the default; the `forever`
  streamer override (`/etc/kvmd/override.yaml` + daemon restart) is
  documented but costs power and RAM continuously.
- **TLS is enforced by the wrapper** (verify by default); an
  `--insecure` exists for diagnosing a broken certificate, and the
  raw-API escape hatch requires an explicit unsafe flag on every call,
  never retries mutating calls, and marks its results unverified.
- **Account creation** is a one-time setup (create the agent user in
  kvmd over the serial console or local access); afterwards the API
  is the whole surface.

## The command vocabulary (wrapper level)

`check` (auth), `info`, `status` (HID + streamer + MSD), `diagnostics`
(all of the above + OCR + TLS), `snapshot [path]`, `ocr [--json]`,
`type <text>`, `key <key>`, `shortcut "Ctrl+C"`, `run <command>`
(the bracketed loop), `mouse-*`, `hid-*`, `media-*` (the full MSD
state machine), `raw <method> <path>` (gated). Everything returns
JSON or a file path; nothing returns prose, which is what makes the
loop scriptable by an agent.
