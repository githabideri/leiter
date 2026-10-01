#!/usr/bin/env bash
# sanitize-sweep.sh: the pre-push leak guard for this PUBLIC repo.
#
# Greps every tracked file (and the commit message you pass as $1, if any)
# for identifier *classes*: private address ranges, Tailscale CGAT, tailnet
# magic-DNS, hostname shapes. Zero hits = pass.
#
# It is a FLOOR, not a proof: it cannot know your novel hostnames, tailnet
# names, or people. The private instance keeps the full literal list
# (names + words) in its own copy of this sweep. Read what you push the
# way a stranger would.
#
# Usage:  scripts/sanitize-sweep.sh            (working tree)
#         scripts/sanitize-sweep.sh "msg..."   (also sweep a commit message)
#
# Wire it in:  .git/hooks/pre-push  (or a CI job on the public remote)
#   exec "$(git rev-parse --show-toplevel)/scripts/sanitize-sweep.sh"
set -u
cd "$(git rev-parse --show-toplevel)"

PATTERNS=(
  # private address blocks (RFC1918): any of these in a public repo is a leak
  "192\.168\.[0-9]+\.[0-9]+"
  "10\.([0-9]+\.){2}[0-9]+"
  "172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+"
  # Tailscale CGAT block (100.64.0.0/10)
  "100\.(6[4-9]|[7-9][0-9]|1[0-2][0-7])\.[0-9]+\.[0-9]+"
  # tailnet magic DNS and the "ts.net" family
  "\.ts\.net"
  "\.ts-net\."
  # common internal hostname shapes
  "\.home\.[a-z]+\.[a-z]{2,}"
  "\.local\.[a-z]+\.[a-z]{2,}"
  # Proxmox id shapes that identify *our* boxes (3+ digit ids after a word;
  # "CT 42" is an example, "CT 412" is an allocation)
  "\b(CT|VM|LXC)[ -]?[0-9]{3,4}\b"
)

FAIL=0
for p in "${PATTERNS[@]}"; do
  HITS=$(git grep -InE "$p" -- . 2>/dev/null | grep -v '^scripts/sanitize-sweep.sh' || true)
  if [ -n "$HITS" ]; then
    echo "== PATTERN: $p"
    echo "$HITS" | head -20
    FAIL=1
  fi
done

# optional: sweep a supplied commit message
if [ "${1:-}" != "" ]; then
  for p in "${PATTERNS[@]}"; do
    if echo "$1" | grep -qE "$p"; then
      echo "== COMMIT MESSAGE matches: $p"
      FAIL=1
    fi
  done
fi

if [ "$FAIL" = 0 ]; then
  echo "sanitize-sweep: clean (0 hits across ${#PATTERNS[@]} patterns)"
  exit 0
else
  echo "sanitize-sweep: LEAK DETECTED. Fix or justify (see AGENTS.md: the register is role terms)"
  exit 1
fi
