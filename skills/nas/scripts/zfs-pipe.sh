#!/usr/bin/env bash
# zfs-pipe.sh: the resumable zfs send|recv pipe. Run on the RECEIVER box
# (the ssh client side is the big-RAM side). The pipe runs between the
# two boxes; nothing is routed through the agent machine.
#
# Usage:
#   zfs-pipe.sh <sender-host> <target-ds> full   <snap>
#   zfs-pipe.sh <sender-host> <target-ds> incr   <base-snap> <snap>
#   zfs-pipe.sh <sender-host> <target-ds> resume <token>
#   zfs-pipe.sh token <logfile>            # extract the resume token from a dead run
#
# Environment:
#   ZFS_PKEY      ssh identity file (default: ~/.ssh/id_ed25519)
#   ZFS_SRCPOOL   sender-side pool (required for full/incr; the target
#                 dataset name is taken from <target-ds>, the pool from here)
#   ZFS_PTHROTTLE pv -L limit (default 45m; empty disables throttling)
#   ZFS_PSIZE     stream bytes for pv -s (progress %/ETA; optional)
#
# Rules baked in (see references/send-recv.md for why they are load-bearing):
#   - full: NO pre-create, NO -F, NO -e (a full stream into an existing
#     target creates a ghost <target>/<leaf> inside it); -u is added when
#     you say the source pool is unencrypted (ZFS_SRC_UNENCRYPTED=1)
#   - incr: -F on the receive (required when the target pool is
#     encrypted on OpenZFS 2.3+, harmless otherwise); verify the base
#     snapshot exists on both sides first
#   - resume: zfs send -t <token> (no snapshot argument), recv -s, no -F
#   - recv -s always: the run is resumable after any interruption
#   - set -o pipefail + PIPE-EXIT sentinel in the log: a killed sender
#     is otherwise invisible
#
# Launch detached so a dead terminal cannot kill the pipe:
#   tmux new-session -d -s zfs-pipe "bash $0 $@; echo DONE >> $LOG"

set -euo pipefail

usage() { grep '^#   zfs-pipe.sh' "$0" | sed 's/^#   //'; exit 2; }
[[ $# -ge 3 ]] || usage
SENDER="$1"; TARGET="$2"; MODE="$3"; shift 3

KEY="${ZFS_PKEY:-$HOME/.ssh/id_ed25519}"
LOG="${ZFS_PLOG:-/root/zfs-pipe-$(date -u +%Y%m%dT%H%M%SZ).log}"
THROTTLE="${ZFS_PTHROTTLE:-45m}"
SIZE="${ZFS_PSIZE:-}"

ssh_send() { # $1.. = the send-side command words after "zfs send"
    ssh -i "$KEY" -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        root@"$SENDER" "zfs send $*"
}

pv_pipe() {
    if command -v pv >/dev/null && [[ -n "$THROTTLE" ]]; then
        if [[ -n "$SIZE" ]]; then pv -L "$THROTTLE" -s "$SIZE"; else pv -L "$THROTTLE"; fi
    else
        cat
    fi
}

case "$MODE" in
    token)
        # extract the resume token from a dead run's log
        f="$1"
        tok=$(grep -o 'receive_resume_token[^ ]*' "$f" 2>/dev/null | head -1 | awk '{print $NF}')
        [[ -n "$tok" ]] || { echo "no receive_resume_token in $f" >&2; exit 1; }
        echo "zfs send -t $tok"
        exit 0
        ;;
    full)
        snap="$1"
        [[ -n "${ZFS_SRCPOOL:-}" ]] || { echo "ZFS_SRCPOOL required for full" >&2; exit 2; }
        ds=${TARGET#*/}
        extra=""; [[ "${ZFS_SRC_UNENCRYPTED:-0}" == "1" ]] && extra="-u"
        echo "=== START $(date -u +%FT%TZ) full $ZFS_SRCPOOL/$ds@$snap -> $TARGET ===" >> "$LOG"
        ssh_send "$ZFS_SRCPOOL/$ds@$snap" | pv_pipe | zfs recv -s $extra "$TARGET" 2>> "$LOG"
        echo "PIPE-EXIT=$? $(date -u +%FT%TZ)" >> "$LOG"
        echo "verify: zfs list -t snapshot $TARGET (snapshot appears only at stream end)"
        ;;
    incr)
        base="$1"; snap="$2"
        [[ -n "${ZFS_SRCPOOL:-}" ]] || { echo "ZFS_SRCPOOL required for incr" >&2; exit 2; }
        ds=${TARGET#*/}
        echo "check first: base snapshot exists on BOTH sides"
        echo "=== START $(date -u +%FT%TZ) incr $base -> $snap : $ZFS_SRCPOOL/$ds -> $TARGET ===" >> "$LOG"
        ssh_send "-i $ZFS_SRCPOOL/$ds@$base $ZFS_SRCPOOL/$ds@$snap" | pv_pipe | zfs recv -sF "$TARGET" 2>> "$LOG"
        echo "PIPE-EXIT=$? $(date -u +%FT%TZ)" >> "$LOG"
        ;;
    resume)
        tok="$1"
        echo "=== START $(date -u +%FT%TZ) resume $tok -> $TARGET ===" >> "$LOG"
        ssh_send "-t $tok" | pv_pipe | zfs recv -s "$TARGET" 2>> "$LOG"
        echo "PIPE-EXIT=$? $(date -u +%FT%TZ)" >> "$LOG"
        echo "log: $LOG (if this dies again: '$0 token $LOG')"
        ;;
    *)
        usage
        ;;
esac
