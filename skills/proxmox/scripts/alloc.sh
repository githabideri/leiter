#!/usr/bin/env bash
# alloc.sh: guest ID / address allocation registry
#
# A registry file is one line per allocated identity, tab-separated:
#   id <TAB> name <TAB> address <TAB> state <TAB> note
#
# Rules this tool enforces:
#   - the ID space is SHARED per host (a container ID can collide with
#     a VM ID on the same host), so the registry is per host;
#   - an assigned-but-down address is NOT free: the hypervisor's
#     config is authoritative over a ping;
#   - you assign, you record, in the same step.
#
# Usage:
#   alloc.sh <registry> list                 # everything
#   alloc.sh <registry> check <id|address>   # assigned? by whom?
#   alloc.sh <registry> free                 # genuinely free (per host range, optional: --range 100-199)
#   alloc.sh <registry> assign <id> <name> <address> [note]
#
# If your estate encodes structure in the numbers (e.g. the ID's
# trailing digits mirror the address's trailing octet, with reserved
# ranges per class of guest), say so in the registry header comment:
# this script does not know your scheme, and neither does the next
# operator unless you write it down.

set -euo pipefail

usage() { grep '^#   alloc.sh' "$0" | sed 's/^#   //'; exit 1; }
[[ $# -ge 2 ]] || usage
REG="$1"; CMD="$2"; shift 2
[[ -f "$REG" ]] || { echo "no registry at $REG (create it; the header is for your scheme)" >&2; exit 1; }

# rows that are not comments
rows() { grep -vE '^[[:space:]]*(#|$)' "$REG" || true; }

case "$CMD" in
    list)
        rows | column -t -s $'\t'
        ;;
    check)
        key="$1"
        hit=$(rows | awk -F'\t' -v k="$key" '$1==k || $3==k')
        if [[ -z "$hit" ]]; then
            echo "$key: unallocated"
        else
            echo "$hit"
            state=$(echo "$hit" | awk -F'\t' '{print $4}')
            [[ "$state" == "down" ]] && echo "note: assigned-but-down is NOT free (config is authoritative over ping)"
        fi
        ;;
    free)
        range=""
        [[ "${1:-}" == "--range" ]] && range="$2"
        if [[ -n "$range" ]]; then
            lo=${range%-*}; hi=${range#*-}
            for ((i=lo; i<=hi; i++)); do
                rows | awk -F'\t' -v id="$i" '$1==id' | grep -q . || echo "$i: free"
            done
        else
            echo "allocated IDs: $(rows | awk -F'\t' '{print $1}' | tr '\n' ' ')"
        fi
        ;;
    assign)
        id="$1"; name="$2"; addr="$3"; note="${4:-}"
        if rows | awk -F'\t' -v a="$id" -v b="$addr" '$1==a || $3==b' | grep -q .; then
            echo "refused: $id or $addr already allocated (run 'check' first)" >&2
            exit 1
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$addr" "up" "$note" >> "$REG"
        echo "allocated: $id $name $addr (remember to create the guest AND note it in the inventory)"
        ;;
    *)
        usage
        ;;
esac
