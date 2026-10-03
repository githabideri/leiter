#!/usr/bin/env bash
# ha: standalone Home Assistant CLI with a mechanical scope model.
#
# Reference implementation for the `ha` skill. Single file; needs bash,
# curl, jq. Config comes from the environment (gitignored env file per
# scope):
#
#   HA_URL          base URL of the install, e.g. https://ha.example.com
#   HA_TOKEN        long-lived access token (its permissions = the floor)
#   HA_SCOPE        user (default) | admin
#   HA_READ_ONLY    1 = block all writes, any scope
#   HA_SSH          user@host of the OS (supervisor + z2m; admin only)
#   HA_MQTT_HOST    broker host for zigbee (OS default: core-mosquitto)
#   HA_MQTT_PORT    (default 1883)
#   HA_MQTT_USER    (default: the OS addon user)
#   HA_ALLOWED_DOMAINS  user-scope write domains
#                       (default: light scene script switch fan climate cover vacuum)
#
# Scope table (enforced here, not in your head):
#   user    : REST read + service calls limited to HA_ALLOWED_DOMAINS
#   admin   : + automation toggles, supervisor (via HA_SSH), z2m (via MQTT)
#   HA_READ_ONLY=1 overrides both: no writes, period.
#
# Global flags: -j raw JSON, -q quiet (no summary line), -t (default).
# logbook and history accept -i <id,id> to filter noise entities.

set -u

# ---------- config ----------
: "${HA_URL:?HA_URL not set}"
: "${HA_TOKEN:?HA_TOKEN not set}"
HA_SCOPE="${HA_SCOPE:-user}"
HA_READ_ONLY="${HA_READ_ONLY:-0}"
HA_SSH="${HA_SSH:-}"
HA_MQTT_HOST="${HA_MQTT_HOST:-core-mosquitto}"
HA_MQTT_PORT="${HA_MQTT_PORT:-1883}"
HA_MQTT_USER="${HA_MQTT_USER:-addons}"
HA_ALLOWED_DOMAINS="${HA_ALLOWED_DOMAINS:-light scene script switch fan climate cover vacuum}"
Z2M_TOPIC="${Z2M_TOPIC:-zigbee2mqtt}"

# ---------- global flags (filter them out of the arg list) ----------
JFLAG=0; QUIET=0; IGNORES=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -j) JFLAG=1 ;;
    -t) ;;
    -q) QUIET=1 ;;
    -i) shift; IGNORES="${1:-}" ;;
    *)  ARGS+=("$1") ;;
  esac
  shift
done
set -- "${ARGS[@]:+${ARGS[@]}}"

die() { echo "ERROR: $*" >&2; exit 1; }
is_admin() { [ "$HA_SCOPE" = "admin" ]; }
need_admin() { is_admin || die "requires HA_SCOPE=admin (currently: $HA_SCOPE)"; }
need_write() { [ "$HA_READ_ONLY" = "1" ] && die "HA_READ_ONLY=1: write blocked ($*)"; }
is_ignored() { # entity_id -> 0 if in the -i list
  [ -z "$IGNORES" ] && return 1
  case ",$IGNORES," in *",$1,"*) return 0 ;; esac
  return 1
}

# ---------- REST ----------
rest_get() {
  local r code body
  r=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $HA_TOKEN" \
        -H "Content-Type: application/json" "${HA_URL}$1" 2>/dev/null) \
    || die "cannot reach HA at $HA_URL"
  code=${r##*$'\n'}; body=${r%$'\n'*}
  [ "$code" -ge 400 ] && die "HTTP $code on $1: $body"
  echo "$body"
}
rest_post() {
  local data="${2:-{}}" r code body
  r=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $HA_TOKEN" \
        -H "Content-Type: application/json" --data-raw "$data" "${HA_URL}$1" 2>/dev/null) \
    || die "cannot reach HA at $HA_URL"
  code=${r##*$'\n'}; body=${r%$'\n'*}
  [ "$code" -ge 400 ] && die "HTTP $code on $1: $body"
  echo "$body"
}
states() { rest_get "/api/states"; }

# ---------- read commands ----------
cmd_dashboard() {
  local s ver
  s=$(states)
  ver=$(rest_get "/api/config" | jq -r '.version // "?"')
  if [ "$JFLAG" = 1 ]; then
    echo "$s" | jq --arg v "$ver" '{
      version: $v,
      summary: {
        total: length,
        on: ([.[] | select(.state == "on")] | length),
        unavailable: ([.[] | select(.state == "unavailable")] | length),
        unknown: ([.[] | select(.state == "unknown")] | length)
      },
      lights: {
        total: ([.[] | select(.entity_id | startswith("light."))] | length),
        on: ([.[] | select((.entity_id | startswith("light.")) and (.state == "on"))] | length)
      },
      open_sensors: [.[] | select((.entity_id | startswith("binary_sensor.")) and (.state == "on")) | .entity_id]
    }'
    return
  fi
  echo "$s" | jq -r --arg v "$ver" '
    "version=\($v)" ,
    "summary total=\(length) on=\([.[] | select(.state == "on")] | length) unavailable=\([.[] | select(.state == "unavailable")] | length)",
    "lights on=\([.[] | select((.entity_id | startswith("light.")) and (.state == "on"))] | length)/\([.[] | select(.entity_id | startswith("light."))] | length)",
    "open_sensors=\([.[] | select((.entity_id | startswith("binary_sensor.")) and (.state == "on"))] | length)"'
  [ "$QUIET" = 1 ] && return
  echo "$s" | jq -r '[.[] | select(.state == "unavailable") | .entity_id][]' | sed 's/^/unavailable /'
}

cmd_state() {
  if [ -n "${1:-}" ]; then
    rest_get "/api/states/$1" |
      if [ "$JFLAG" = 1 ]; then cat; else jq -r '[.entity_id, .state, (.last_changed // "-")] | @tsv'; fi
    return
  fi
  states |
    if [ "$JFLAG" = 1 ]; then cat; else jq -r '
      group_by(.entity_id | split(".")[0]) | sort_by(.[0].entity_id)[] |
      "\(.[0].entity_id | split(".")[0]) (\(length))",
      (.[] | "  \(.entity_id)\t\(.state)")'; fi
}

cmd_entity_list() {
  local d="${1:-}"
  if [ -n "$d" ]; then
    states | jq -r --arg d "$d" \
      '[.[] | select(.entity_id | startswith($d + "."))] | sort_by(.entity_id)[] | "\(.entity_id)\t\(.state)"'
  else
    states | jq -r '[.[] | .entity_id | split(".")[0]] | group_by(.) | sort_by(-length)[] | "\(.[0])\t\(length)"'
  fi
}

cmd_system() {
  rest_get "/api/config" |
    if [ "$JFLAG" = 1 ]; then cat; else jq -r '
      "version\t\(.version)", "state\t\(.state)",
      "location\t\(.location_name // "-")", "components\t\(.components | length)"'; fi
}

cmd_logs() {
  local n="${1:-50}"
  rest_get "/api/error_log" | tail -n "$n"   # plaintext; never pipe into jq
}

cmd_logbook() {
  # args: [entity] [n]  (a bare number is the limit)
  local entity="" n="${1:-50}"
  if [ $# -ge 2 ]; then entity="$1"; n="${2:-50}"; fi
  local path="/api/logbook?limit=$n"
  [ -n "$entity" ] && path="$path&entity_id=$entity"
  local lines prev_entity prev_line run_count cur_entity line
  lines=$(rest_get "$path" | jq -r '.[] | .entity_id as $eid | .when as $w | "\($eid)\t[\(($w // "-") | split("T")[0] + " " + ($w // "-")[11:19])] \(.name // $eid) \(.state // "")"' 2>/dev/null) || true
  if [ -z "$lines" ]; then echo "(no entries)"; return; fi
  prev_entity=""; prev_line=""; run_count=0
  while IFS=$'\t' read -r cur_entity line; do
    [ -z "$line" ] && continue
    if is_ignored "$cur_entity"; then continue; fi
    if [ "$cur_entity" = "$prev_entity" ] && [ -n "$prev_entity" ]; then
      run_count=$((run_count + 1))
    else
      if [ "$run_count" -gt 1 ]; then
        echo "$prev_line"
        echo "  ... $((run_count - 1)) more $prev_entity entries"
      elif [ "$run_count" -eq 1 ]; then
        echo "$prev_line"
      fi
      prev_entity="$cur_entity"; prev_line="$line"; run_count=1
    fi
  done <<< "$lines"
  if [ "$run_count" -gt 1 ]; then
    echo "$prev_line"
    echo "  ... $((run_count - 1)) more $prev_entity entries"
  elif [ "$run_count" -eq 1 ]; then
    echo "$prev_line"
  fi
}

cmd_history() {
  local entity="${1:?usage: ha history <entity> [n]}"
  local n=50
  [ -n "${2:-}" ] && case "$2" in *[!0-9]*) : ;; *) n="$2" ;; esac
  local s e
  s="$(date -u +"%Y-%m-%dT00:00:00")%2B00:00"
  e="$(date -u +"%Y-%m-%dT%H:%M:%S")%2B00:00"
  rest_get "/api/history/period/$s?filter_entity_id=$entity&end_time=$e" \
    | jq -r '.[0][] | "[(.last_changed // "-") | .[0:19]] \(.state)"' 2>/dev/null | tail -n "$n"
}

cmd_batteries() {
  # matcher ported from the estate CLI: entity name, device class, or either
  # battery attribute; deduped by device_id, lowest level per device wins
  local threshold="${1:-20}"
  local out
  out=$(states | jq -r --arg thr "$threshold" '
    [.[] | select(
        (.entity_id | test("battery"; "i")) or
        (.attributes.device_class == "battery") or
        (.attributes.battery_level != null) or
        (.attributes.battery != null)
    ) | select(
        (.entity_id | test("battery|level|charge"; "i")) or
        (.attributes.device_class == "battery") or
        (.unit_of_measurement == "%")
    )] | group_by(.attributes.device_id // "unknown")[] |
    (map(
        .entity_id as $eid |
        ((.attributes.battery_level // .attributes.battery // .state) | tonumber? // 100) as $level |
        {eid: $eid, level: $level, friendly: (.attributes.friendly_name // $eid)}
      ) | sort_by(.level) | .[0]) |
    select(.level <= ($thr | tonumber)) |
    "\(.eid)\t\(.level)%\t\(.friendly)"' 2>/dev/null) || true
  if [ -z "$out" ]; then echo "no batteries below ${threshold}%"; return; fi
  echo "batteries below ${threshold}% (deduped by device_id)"
  echo "$out"
}

# ---------- write-ish commands ----------
cmd_service_call() {
  local svc="${1:?usage: ha service call <domain>.<service> [json]}"
  local data="${2:-{}}"
  local domain=${svc%%.*}
  if [ "$HA_SCOPE" = "user" ]; then
    echo "$HA_ALLOWED_DOMAINS" | grep -qw "$domain" ||
      die "user scope: domain '$domain' not in HA_ALLOWED_DOMAINS"
  fi
  case "$domain" in
    light|scene|script|switch|fan|climate|cover|vacuum|automation|homeassistant)
      need_write "service call $svc" ;;
  esac
  rest_post "/api/services/$domain/${svc#*.}" "$data"
}

cmd_scenes() { states | jq -r '[.[] | select(.entity_id | startswith("scene.")) | .entity_id] | sort[]'; }
cmd_scene_apply() {
  need_write "scene apply"
  rest_post "/api/services/scene/turn_on" "{\"entity_id\":\"scene.$1\"}"
}
cmd_scripts() { states | jq -r '[.[] | select(.entity_id | startswith("script.")) | "\(.entity_id)\t\(.state)"] | sort[]'; }

cmd_automations() {
  states | jq -r '[.[] | select(.entity_id | startswith("automation."))
    | {id: (.entity_id | sub("^automation.";"")), name: (.attributes.friendly_name // .entity_id), state}]
    | .[] | "\(.id)\t\(.name)\t\(.state)"'
}
cmd_automation() {
  local sub="${1:?}"; local id="${2:?}"
  case "$sub" in
    enable|disable) need_admin; need_write "automation $sub" ;;
  esac
  rest_post "/api/services/automation/$sub" "{\"entity_id\":\"automation.$id\"}"
}

# ---------- supervisor (admin, over OS ssh) ----------
cmd_supervisor() {
  need_admin
  [ -n "$HA_SSH" ] || die "HA_SSH not set (user@host of the OS)"
  local sub="${1:?usage: ha supervisor <addons|core|host> [args...]}"
  shift
  case "$sub" in
    core|host) need_write "supervisor $sub $*" ;;
  esac
  ssh "$HA_SSH" "ha $sub $*"
}

# ---------- zigbee (MQTT request/response over the OS ssh) ----------
z2m_sub() {
  local n="${2:-1}" t="${3:-10}"
  ssh "$HA_SSH" "mosquitto_sub -h $HA_MQTT_HOST -p $HA_MQTT_PORT -u $HA_MQTT_USER -t '$1' -C $n -W $t -N -F '%s'" 2>/dev/null
}
z2m_pub() {
  ssh "$HA_SSH" "mosquitto_pub -h $HA_MQTT_HOST -p $HA_MQTT_PORT -u $HA_MQTT_USER -t '$1' -m '$2'" 2>/dev/null
}
cmd_z2m() {
  local sub="${1:?}"; local arg="${2:-}"
  case "$sub" in
    status)
      z2m_sub "$Z2M_TOPIC/bridge/info" |
        if [ "$JFLAG" = 1 ]; then cat; else jq '{version: .version, state: .state, network: .network}'; fi
      ;;
    devices)
      z2m_sub "$Z2M_TOPIC/bridge/devices" 1 15 \
        | jq -r '.[] | select(.friendly_name) | "\(.friendly_name)\t\(.state // "-")\t\(.ieee_address)"'
      ;;
    device)
      z2m_sub "$Z2M_TOPIC/$arg"
      ;;
    permit_join)
      need_write "z2m permit_join"
      local dur="${3:-60}"
      z2m_pub "$Z2M_TOPIC/bridge/request/permit_join" "{\"value\":true,\"time\":$dur}"
      z2m_sub "$Z2M_TOPIC/bridge/response/permit_join" 1 10 || true
      ;;
    rename)
      need_write "z2m rename"
      # references/z2m.md: the rename hazard (no old_ids; on-disk refs break)
      local to="${3:?}"
      z2m_pub "$Z2M_TOPIC/bridge/request/device/rename" "{\"from\":\"$arg\",\"to\":\"$to\",\"homeassistant_rename\":true}"
      ;;
    remove)
      need_write "z2m remove"
      z2m_pub "$Z2M_TOPIC/bridge/request/device/remove" "{\"id\":\"$arg\"}"
      ;;
    ota)
      need_write "z2m ota"
      z2m_pub "$Z2M_TOPIC/bridge/request/ota/update/${arg:-check}" "{}"
      z2m_sub "$Z2M_TOPIC/bridge/response/ota/update" 1 30 \
        || echo "(no response within 30s: on a 1.4x bridge this request is 2.x-only and gets dropped)"
      ;;
  esac
}

# ---------- dispatch ----------
[ $# -ge 1 ] || {
  echo "usage: ha [-j|-q] <dashboard|state|entity|service|scenes|scene|scripts|automations|automation|system|logs|logbook|history|batteries|supervisor|z2m> [args]"
  exit 2
}
case "$1" in
  dashboard)   shift; cmd_dashboard ;;
  state)       shift; cmd_state "$@" ;;
  entity)      shift; [ "${1:-}" = "list" ] && shift; cmd_entity_list "$@" ;;
  service)     shift; [ "${1:-}" = "call" ] && shift; cmd_service_call "$@" ;;
  scenes)      cmd_scenes ;;
  scene)       shift; [ "${1:-}" = "apply" ] && shift; cmd_scene_apply "$@" ;;
  scripts)     cmd_scripts ;;
  automations) cmd_automations ;;
  automation)  shift; cmd_automation "$@" ;;
  system)      cmd_system ;;
  logs)        shift; cmd_logs "$@" ;;
  logbook)     shift; cmd_logbook "$@" ;;
  history)     shift; cmd_history "$@" ;;
  batteries)   shift; cmd_batteries "$@" ;;
  supervisor)  shift; cmd_supervisor "$@" ;;
  z2m)         need_admin; shift; cmd_z2m "$@" ;;
  *)           die "unknown command: $1" ;;
esac
