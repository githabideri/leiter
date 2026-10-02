# Driving the phone's UI

Touch injection, the accessibility tree, launcher behavior.

## uiautomator first, vision second

`adb shell uiautomator dump <path>` writes the accessibility tree of
the foreground window to XML: every element with `text`,
`content-desc`, `class`, `clickable`, and pixel `bounds`. The tap
target for any element is the center of its bounds; you are no longer
guessing pixels off a screenshot.

The dump has one failure mode that looks like a hang: it waits (up to
about ten seconds) for the window to be *idle* (unchanged for a
half-second). Anything continuously animating or rendering (GL apps,
live video, a camera preview) never idles, and the dump fails with an
idle-state error. That error is the tell: for that window, the
screenshot is the instrument and the dump is not available. (A
`--windows`-style flag or a per-window variant can help in some
cases; the timeout itself is not user-configurable in the stock
command.)

## input commands and their sharp edges

- `input tap x y`: a short synthetic tap. **Some system dialogs
  silently ignore these** (observed: the backup-restore
  confirmation window on a hardened build). The working substitute is
  a short press at the same coordinates: `input swipe x y x y 600`
  (the last argument is the duration in ms). "My tap does nothing"
  has two causes: wrong coordinates (fix with the dump), or a
  dialog that needs a press (fix with the duration).
- `input text`: types characters; it does not send Enter, and it
  mangles spaces and some punctuation (quote and escape per call).
  For real text entry, the keyboard (an `input text` per field is
  fine for short values; long or special text may need key events or
  the IME).
- `input keyevent`: the standard key codes (home, back, power,
  volume, enter).
- `input swipe x1 y1 x2 y2 ms`: a drag with a duration; the basic
  tool for launcher rearrangement (see the drag patterns below) and
  for the "press instead of tap" trick above.
- key combinations are sequences of keyevents; there is no
  "chord" command, so timing between them is your problem.

## Launcher states and geometry

The stock launcher (and AOSP derivatives) has a small state machine
you will meet repeatedly: home grid, app drawer, folder open, edit
mode (a long-press on an icon enters it and shows the layout's edit
chrome), and the search/wallet overlays. The practical facts:

- **long-press enters edit mode**; a drag from an icon's center to a
  target position moves it; dropping on another icon can create a
  folder (the exact gesture is launcher-version dependent, so
  verify by screenshot after each move);
- **geometry is in the device's logical pixels** (the resolution the
  `uiautomator` dump reports); scale any coordinates you find
  documented for one device by the ratio of resolutions when you
  move the procedure to another;
- **widgets have one working path** in the stock launcher: the
  widget picker from the long-press menu, then position by drag; the
  programmatic route (content-provider layout import) is closed on
  user builds (see `dead-ends.md`).

## The transactional pattern for multi-step gestures

A drag-and-drop that must not half-happen wants a wrapper: capture
the *before* state (screenshot or dump), perform the gesture as one
`input swipe` with a realistic duration (hundreds of ms; an
instantaneous "swipe" is a tap), capture the *after* state, and
compare. If the after-state is not what the before-state plus the
gesture should have produced, the gesture is undone by a second
gesture back, not by hope. This is the home-screen equivalent of the
KVM skill's observe-act-verify loop.
