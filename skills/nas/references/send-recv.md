# The dataset copy: recipe, flags, resume, delta

The copy is a pipe: `zfs send` on the sender, `zfs recv` on the
receiver, an ssh in between (and usually a `pv` throttle). It runs on
the receiver box, in a detached session that outlives the terminal
(tmux on both the FreeBSD and the Linux side).

## The full-stream recipe

```bash
#!/bin/bash
# runs ON THE RECEIVER; the ssh client lives here (the big-RAM side)
set -o pipefail
LOG=/root/send-<snap>.log

ssh -i ~/.ssh/id_<pair> -o BatchMode=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    root@<sender> "zfs send <pool>/<ds>@<snap>" \
  | pv -L 45m -s <stream-bytes> \
  | zfs recv -s -u <target-pool>/<ds> 2>> "$LOG"

echo "PIPE-EXIT=$? $(date -u +%FT%TZ)" >> "$LOG"
```

Launch it detached: `tmux new-session -d -s copy "bash /root/send-<snap>.sh"`.
A detached pty removes the whole "my ssh session died and took the pipe
with it" failure class, and gives you a reattach point for watching.

### The flags are load-bearing

- **No pre-create of the target, no `-F`, no `-e`.** `-e` and `-F`
  force "the target must already exist" on the receive side, and a
  full stream into an existing target does not overwrite it: it
  creates `<target>/<stream-leaf>` *inside* it. A full stream into a
  *nonexistent* target creates the dataset directly, inherits the
  pool's encryption, and auto-mounts it. Set `quota`/`recordsize`
  *after* creation (you cannot set them on a dataset the stream is
  about to create).
- **`-s`** makes the receive resumable on any interruption (see
  below).
- **`-u`** admits an *unencrypted* source stream into an encrypted
  target pool (the receiver re-encrypts). Only needed when the two
  pools differ in encryption.
- **`pv -s <bytes>`**: the pre-measured stream size
  (`zfs get -p written@<snap>` on the sender) gives a real percentage
  and ETA; `-L 45m` ≈ 360 Mbit/s leaves headroom on a gigabit link.

### Completion: all three

1. `PIPE-EXIT=0` in the log
2. `zfs list -t snapshot <target>` shows `@<snap>` (a full send
   creates the receiver's snapshot **only when the stream ends**; no
   snapshot means truncated, even if `used` looks nearly equal)
3. receiver `zfs list -Hp -o used <target>` ≈ sender
   `zfs get -p written@<snap> <source>`

While it runs, watch the target dataset's growth on the receiver
(`zpool list` allocated, or the dataset's `usedbydataset`): a 700 GB
stream that is not showing up anywhere means it is writing to a ghost
child path.

## When the stream dies (it will, eventually)

Do not restart from zero. The `recv -s` log contains a
`receive_resume_token`; the next run is:

```bash
ssh -i ~/.ssh/id_<pair> root@<sender> "zfs send -t <token>" \
  | pv -L 45m -s <remaining-bytes> \
  | zfs recv -s <target-pool>/<ds> 2>> "$LOG"
```

No `-F`, no snapshot argument on the sender (the FreeBSD send usage
is `send [-nVvPe] -t <token>`), and the token contains dashes, so
capture the whole printed line, not a word of it. The receiver
continues into the existing partial dataset.

Killing a stray `zfs send`: the kernel thread (`[send_reader]`) is
often stuck in D-state and will not die; kill the userspace process
instead, with the bracket trick so the remote pkill does not match its
own shell: `pkill -f "zfs sen[d]"`.

## After the full copy: delta converge

Writes that landed on the source after the snapshot need one small
final stream: on the sender `zfs snapshot <ds>@converge`, then
`zfs send -i <snap> <ds>@converge | … | zfs recv <target>` (no `-F`,
target exists). Afterwards the mirror is live and the steady state is
**nightly deltas**:

```bash
ssh … "zfs send -i <last-snap> <pool>/<ds>@<new-snap>" \
  | … | zfs recv -F <target-pool>/<ds>
```

The incremental gets `-F` when the *receiver's* pool is encrypted
(the OpenZFS 2.3 modified-since-snapshot false positive; see
`cli-and-encryption.md`), and never otherwise. Before an incremental
with `-F`, verify the base snapshot exists on both sides.

## The pipe-death post-mortem (what a bad death looks like)

The failure mode worth memorizing: a multi-hour stream dies at 95%
with no stderr, no OOM trace (the dmesg ring was flushed by unrelated
audit spam), and the receiver's sshd journal says "Received
disconnect … 11: disconnected by user", which means *the client side*
ended: the sender's ssh died (OOM on a RAM-starved box), not the link.
The receiver is left with hundreds of GB of orphan objects and an
*empty* root directory (no entries, no snapshot). Re-linking orphans is
not a thing; destroy the partial dataset and resume from the token if
you have one, or start over if you do not. The countermeasures are the
rules in the main file: client on the big-RAM box, swap on the small
box, `set -o pipefail` plus the exit sentinel in the log, `-s` on the
receive.
