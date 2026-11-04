#!/bin/bash
# safe-kill: stop a process tree by a marker string, without ever
# matching the caller chain (the ssh session / shell that ran this).
#
# The footgun it exists for: `ssh host "pkill -f <pattern>"` matches the
# remote shell itself (the pattern is in its argv) and kills the session
# mid-command; `pkill -P` then leaves orphaned grandchildren holding
# locks and fds. This script: finds by marker (bracketed regex), maps
# the tree, excludes anything whose ancestor chain is ours, TERM the
# tree with a drain window, re-verifies, optionally escalates to -9.
#
# usage:
#   safe-kill.sh -n [marker]           dry run: show what would be killed
#   safe-kill.sh [marker]             TERM + drain (5s) + verify
#   safe-kill.sh -9 [marker]          as above, escalating to KILL
#   safe-kill.sh --drain N [marker]   custom drain window (seconds)
#
# Run it as a file on the target (scp it over, or it lives in
# <skills-root>/scripts/ here). Never inline the marker in an
# interactive command line.
#
# Limitation: a process that is a DESCENDANT of the shell running this
# (e.g. a worker you started from the same session) is excluded for
# safety: kill that one by explicit PID.
set -uo pipefail

sig=TERM
dry=0
drain=5

case ${1:-} in
    -n) dry=1; [ $# -gt 1 ] && shift ;;
    -9) sig=KILL; [ $# -gt 1 ] && shift ;;
    --drain) drain=${2:-5}; shift 2; [ ${1:-} = -n ] && { dry=1; shift; }; [ ${1:-} = -9 ] && { sig=KILL; shift; } ;;
esac

marker=${1:-}
[ -z "$marker" ] && { echo "usage: safe-kill.sh [-n|-9|--drain N] <marker>" >&2; exit 2; }

# bracketed first character: our argv carries the raw marker, the
# pattern (with the bracket pair) never matches its own spelling
pat="[${marker:0:1}]${marker:1}"

ppid_of() { ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '; }

# our ancestor chain: us, parent, ... (init is the boundary, NOT a
# member; including it would exclude every orphan/detached process,
# i.e. exactly the ones we most often need to find)
mychain() {
    local p=$$
    while [ -n "$p" ] && [ "$p" != 1 ]; do
        echo "$p"
        p=$(ppid_of "$p")
    done
}
MINE=$(mychain | sort -n)

in_mine() {
    local x
    for x in $MINE; do [ "$x" = "$1" ] && return 0; done
    return 1
}

# a candidate is ours if it (or any ancestor) is in our chain
excluded() {
    local p=$1 guard=0
    while [ -n "$p" ] && [ "$p" != 1 ] && [ $guard -lt 32 ]; do
        in_mine "$p" && return 0
        p=$(ppid_of "$p")
        guard=$((guard + 1))
    done
    return 1
}

candidates() {
    pgrep -f "$pat" 2>/dev/null | sort -n
}

list_tree() {
    local p
    for p in $(candidates); do
        excluded "$p" && continue
        ps -o pid=,ppid=,etime=,args= -p "$p" 2>/dev/null | cut -c1-160
    done
}

kill_one() {
    local p=$1 r=0
    # the pid, then its direct children, in up to 3 rounds (orphaned
    # grandchildren reparent to init and appear as new direct children)
    while [ $r -lt 3 ]; do
        kill -s "$sig" "$p" 2>/dev/null
        local c
        for c in $(pgrep -P "$p" 2>/dev/null); do kill -s "$sig" "$c" 2>/dev/null; done
        sleep 1
        pgrep -P "$p" >/dev/null 2>&1 || kill -s "$sig" "$p" 2>/dev/null
        sleep 0.5
        r=$((r + 1))
    done
}

echo "marker: $marker  (signal: $sig, drain: ${drain}s)"
targets=$(candidates | while read -r p; do excluded "$p" || echo "$p"; done | sort -n)

if [ -z "$targets" ]; then
    echo "no matching processes outside our own chain: nothing to do"
    exit 0
fi

echo "will act on:"
list_tree

[ "$dry" = 1 ] && { echo "(dry run: no signals sent)"; exit 0; }

for p in $targets; do kill_one "$p"; done

echo "draining ${drain}s ..."
sleep "$drain"

survivors=""
for p in $targets; do
    kill -0 "$p" 2>/dev/null && survivors="$survivors $p"
done
# survivors' children may have reparented; one more pass over the marker
for p in $(candidates); do
    excluded "$p" && continue
    kill -0 "$p" 2>/dev/null && survivors="$survivors $p"
done

if [ -n "$survivors" ]; then
    if [ "$sig" = TERM ]; then
        echo "survivors after TERM: $survivors. Re-run with -9 to force"
        exit 1
    fi
    echo "still alive after KILL:$survivors (zombie or unkillable; inspect /proc/<pid>)"
    exit 1
fi

echo "all targets dead. Verify locks: fuser <lockfile>; verify peers: the other end of any pipe."
exit 0
