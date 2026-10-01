#!/usr/bin/env bash
# pve.sh: Proxmox VE API wrapper (source this; no external deps beyond curl+jq)
#
# You bring: PVE_HOST (address:8006 implied), PVE_NODE, PVE_API_TOKEN
#   (full "USER@REALM!ID=UUID" payload; see references/pve-api.md),
#   optional PVE_SSH_TARGET for the CLI fallback, PVE_CA (path to CA
#   cert; default is -k, i.e. skip verification; fine on a private
#   LAN, wrong on the internet).
#
# The token value is a secret: load it from your config at the moment
# of use, never paste it into a script, log, or doc.

set -euo pipefail

PVE_HOST="${PVE_HOST:-}"
PVE_NODE="${PVE_NODE:-}"
PVE_API_TOKEN="${PVE_API_TOKEN:-}"
PVE_SSH_TARGET="${PVE_SSH_TARGET:-}"

if [[ -n "$PVE_HOST" ]]; then
    PVE_CA_ARGS=()
    if [[ -n "${PVE_CA:-}" && -f "$PVE_CA" ]]; then
        PVE_CA_ARGS=(--cacert "$PVE_CA")
    else
        PVE_CA_ARGS=(-k)
    fi
fi

# ── core ─────────────────────────────────────────────────────────
pve_api_call() {
    # $1 method (GET/POST/DELETE), $2 path under /api2/json, $3 optional data
    local method="$1" path="$2" data="${3:-}"
    local url="https://${PVE_HOST}:8006/api2/json${path}"
    local args=(curl -s "${PVE_CA_ARGS[@]}" -H "Authorization: PVEAPIToken=${PVE_API_TOKEN}" -X "$method" "$url")
    [[ -n "$data" ]] && args+=(--data-urlencode "$data")
    "${args[@]}" 2>/dev/null
}

# Poll a task UPID to completion.
pve_poll_upid() {
    local upid="$1" timeout="${2:-1800}" elapsed=0
    while (( elapsed < timeout )); do
        local r status exitstatus
        r=$(pve_api_call GET "/nodes/${PVE_NODE}/tasks/${upid}/status")
        status=$(echo "$r" | jq -r '.data.status // empty' 2>/dev/null || true)
        exitstatus=$(echo "$r" | jq -r '.data.exitstatus // empty' 2>/dev/null || true)
        if [[ "$status" == "stopped" ]]; then
            if [[ "$exitstatus" == "OK" ]]; then
                echo "UPID $upid: OK"
                return 0
            fi
            echo "UPID $upid: failed (exitstatus=$exitstatus)" >&2
            return 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "UPID $upid: timed out after ${timeout}s" >&2
    return 1
}

# POST that returns a task, then poll it.
pve_task() {
    local path="$1" data="${2:-}"
    local r upid
    r=$(pve_api_call POST "$path" "$data")
    upid=$(echo "$r" | jq -r '.data // empty' 2>/dev/null || true)
    if [[ -z "$upid" ]]; then
        echo "no UPID returned: $r" >&2
        return 1
    fi
    pve_poll_upid "$upid"
}

# ── inspection (safe) ────────────────────────────────────────────
pve_lxc_list() {
    pve_api_call GET "/nodes/${PVE_NODE}/lxc" | jq -r '.data[]? | "\(.vmid)\t\(.status)\t\(.name // "unnamed")"'
}

pve_qemu_list() {
    pve_api_call GET "/nodes/${PVE_NODE}/qemu" | jq -r '.data[]? | "\(.vmid)\t\(.status)\t\(.name // "unnamed")"'
}

pve_lxc_status() {
    pve_api_call GET "/nodes/${PVE_NODE}/lxc/$1/status" | jq '.data | {status, pid, uptime, cpu, mem, maxmem}'
}

pve_lxc_config() {
    pve_api_call GET "/nodes/${PVE_NODE}/lxc/$1/config" | jq '.data | {hostname, cores, memory, swap, unprivileged, net: (.net0 // null)}'
}

pve_storage_list() {
    pve_api_call GET "/nodes/${PVE_NODE}/storage" | jq -r '.data[]? | "\(.storage)\t\(.type)\t\(.status)"'
}

pve_tasks() {
    pve_api_call GET "/nodes/${PVE_NODE}/tasks" | jq -r '.data[:10][]? | "\(.upid)\t\(.type)\t\(.status)\t\(.exitstatus // "-")"'
}

# The blind-API rule: an API that reports an empty fleet is not proof
# the fleet is empty (stale token, wrong node name, dead API path).
# Cross-check against the command line over SSH and report the
# discrepancy; trust the answer that is plausible.
pve_fleet_check() {
    local api_cts api_vms cli
    api_cts=$(pve_lxc_list | wc -l)
    api_vms=$(pve_qemu_list | wc -l)
    if [[ -n "$PVE_SSH_TARGET" ]]; then
        cli=$(ssh -o ConnectTimeout=8 "$PVE_SSH_TARGET" "pct list 2>/dev/null | tail -n +2 | wc -l; qm list 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null || echo "? ?")
    else
        cli="n/a (no PVE_SSH_TARGET)"
    fi
    echo "api: $api_cts lxc, $api_vms vm | ssh cli: $cli"
    if [[ "$api_cts" == "0" && "$api_vms" == "0" && "$cli" != *"? "* && "$cli" != "n/a"* && "$cli" != "0 0" ]]; then
        echo "MISMATCH: API reports an empty fleet but the CLI sees guests. The API path is blind (stale token? wrong PVE_NODE?)." >&2
        return 1
    fi
    echo "consistent"
}

# ── snapshots (reversible) ───────────────────────────────────────
pve_snapshot_list() {
    pve_api_call GET "/nodes/${PVE_NODE}/lxc/$1/snapshot" | jq -r '.data[]? | select(.name != "current") | "\(.name)\t\(.snaptime)"'
}

pve_snapshot_create() {
    pve_task "/nodes/${PVE_NODE}/lxc/$1/snapshot" "snapshotname=$2"
}

pve_snapshot_rollback() {
    # the guest must be stopped first (the API refuses otherwise)
    pve_task "/nodes/${PVE_NODE}/lxc/$1/snapshot/$2/rollback"
}

pve_snapshot_delete() {
    pve_task "/nodes/${PVE_NODE}/lxc/$1/snapshot/$2/delete"
}

# ── lifecycle (ask before running) ───────────────────────────────
pve_start()    { pve_task "/nodes/${PVE_NODE}/lxc/$1/start"; }
pve_stop()     { pve_task "/nodes/${PVE_NODE}/lxc/$1/stop"; }
pve_shutdown() { pve_task "/nodes/${PVE_NODE}/lxc/$1/shutdown"; }

# Hard-gated: explicit env flag AND a matching confirmation argument.
pve_destroy() {
    local vmid="$1" confirm="${2:-}"
    if [[ "${PVE_ALLOW_DESTRUCTIVE:-}" != "1" ]]; then
        echo "refused: set PVE_ALLOW_DESTRUCTIVE=1 (and get a human yes first)" >&2
        return 1
    fi
    local name
    name=$(pve_lxc_list | awk -v v="$vmid" '$1==v {print $3}')
    if [[ "$confirm" != "$name" ]]; then
        echo "refused: pass the guest name ('$name') as the confirmation argument" >&2
        return 1
    fi
    pve_task "/nodes/${PVE_NODE}/lxc/$1/destroy"
}

# ── PBS (backup server, API on :8008 of the PBS host) ────────────
# You bring: PBS_HOST, PBS_API_TOKEN, PBS_DATASTORE
PBS_HOST="${PBS_HOST:-}"
PBS_API_TOKEN="${PBS_API_TOKEN:-}"

pbs_api_call() {
    local method="$1" path="$2"
    curl -s "${PVE_CA_ARGS[@]}" -H "Authorization: PVEAPIToken=${PBS_API_TOKEN}" -X "$method" "https://${PBS_HOST}:8008/api2/json${path}" 2>/dev/null
}

pve_pbs_status() {
    echo "--- jobs ---"
    pbs_api_call GET "/api2/job" | jq -r '.data[]? | "\(.jobid)\t\(.state)\t\(.lastsuccess // "never")\t\(.nxtcheck // "-")"'
    echo "--- datastores ---"
    pbs_api_call GET "/api2/repository" | jq -r '.data[]? | "\(.repository)\t\(.used // "-")\t\(.size // "-")\t\(.pruning)"'
}

pve_pbs_backup() {
    pbs_api_call POST "/api2/job/$1" >/dev/null
    echo "backup job $1 triggered"
}

# shellcheck disable=SC2034
: "${PVE_HOST:-} ${PVE_NODE:-} ${PVE_API_TOKEN:-} ${PVE_SSH_TARGET:-}"  # silence unused warnings in sourcing shells
