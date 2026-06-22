#!/usr/bin/env bash
set -euo pipefail

# Generic statuspage.io incident monitor.
# Inputs (positional arg overrides env var):
#   1 / SERVICE_NAME  Display name, e.g. "VRChat" or "Claude"
#   2 / API_URL       Unresolved incidents JSON endpoint
#   3 / STATUS_URL    Public status page link for messages
# Optional:
#   WEBHOOK_URL       Discord-style webhook; skipped if unset
#   STATE_FILE        Override state file path (default derived from name)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SERVICE_NAME="${1:-${SERVICE_NAME:-}}"
API_URL="${2:-${API_URL:-}}"
STATUS_URL="${3:-${STATUS_URL:-}}"

if [[ -z "$SERVICE_NAME" || -z "$API_URL" || -z "$STATUS_URL" ]]; then
  echo "Usage: $0 <service-name> <api-url> <status-url>" >&2
  echo "   or set SERVICE_NAME, API_URL, STATUS_URL env vars." >&2
  exit 2
fi

# Derive a safe per-service state file unless one is given.
if [[ -z "${STATE_FILE:-}" ]]; then
  slug=$(tr '[:upper:] ' '[:lower:]_' <<< "$SERVICE_NAME" | tr -cd 'a-z0-9_')
  STATE_FILE="$SCRIPT_DIR/.${slug}_down"
fi

# Maps a statuspage impact to a human label, shared by every jq block below.
IMPACT_LABELS='def impactlabel: {"critical":"Major Outage","major":"Partial Outage","minor":"Degraded Performance"}[.] // "Incident";'

# Formats one incident (by id) as a titled block with its updates, oldest first.
format_incident() {
  jq -r --arg id "$1" "$IMPACT_LABELS"'
    .incidents[] | select(.id == $id)
    | "**\(.impact | impactlabel): \(.name)**\n"
      + (.incident_updates | sort_by(.created_at) | map("\(.status | ascii_upcase) - \(.body)") | join("\n"))
  ' <<< "$api_response"
}

send_webhook() {
  if [[ -z "${WEBHOOK_URL:-}" ]]; then
    echo "Warning: WEBHOOK_URL is not set, skipping webhook."
    return
  fi
  payload=$(jq -n --arg content "$1" '{content: $content}')
  curl -s --max-time 15 -X POST -H "Content-Type: application/json" \
    -d "$payload" \
    "$WEBHOOK_URL"
  echo "Webhook fired."
}

api_response=$(curl -s --max-time 15 "$API_URL")
was_down=false
[[ -f "$STATE_FILE" ]] && was_down=true

count=$(jq '[.incidents[] | select(.impact != "none")] | length' <<< "$api_response")

if [[ "$count" -gt 0 ]]; then
  [[ "$count" -eq 1 ]] && noun="incident" || noun="incidents"

  # One signature line per active incident: id<TAB>impact<TAB>name<TAB>updateIds.
  # Changes when an incident is added/removed or gains an update.
  current_state=$(jq -r '
    [.incidents[] | select(.impact != "none")]
    | sort_by(.id)
    | map("\(.id)\t\(.impact)\t\(.name)\t" + ([.incident_updates[].id] | sort | join(",")))
    | .[]
  ' <<< "$api_response")

  # Console: list every active incident for log readability.
  echo "Status: DOWN — ${count} active ${noun}"
  jq -r "$IMPACT_LABELS"'
    [.incidents[] | select(.impact != "none")]
    | sort_by(.created_at)
    | map("**\(.impact | impactlabel): \(.name)**\n"
          + (.incident_updates | sort_by(.created_at) | map("\(.status | ascii_upcase) - \(.body)") | join("\n")))
    | join("\n\n")
  ' <<< "$api_response"

  previous_state=""
  [[ -f "$STATE_FILE" ]] && previous_state=$(cat "$STATE_FILE")

  if [[ "$current_state" == "$previous_state" ]]; then
    echo "No changes since last check, skipping webhook."
  else
    echo "$current_state" > "$STATE_FILE"

    declare -A prev_sig prev_name cur_sig
    if [[ -n "$previous_state" ]]; then
      while IFS=$'\t' read -r id impact name sig; do
        [[ -z "$id" ]] && continue
        prev_sig["$id"]="${impact}	${name}	${sig}"
        prev_name["$id"]="$name"
      done <<< "$previous_state"
    fi
    while IFS=$'\t' read -r id impact name sig; do
      [[ -z "$id" ]] && continue
      cur_sig["$id"]="${impact}	${name}	${sig}"
    done <<< "$current_state"

    # Resolved: present last time, gone now. Announce each on its own; the
    # still-ongoing incidents are left unmentioned (they are assumed known).
    for id in "${!prev_sig[@]}"; do
      if [[ -z "${cur_sig[$id]+set}" ]]; then
        send_webhook "✅ **${SERVICE_NAME} incident resolved:** ${prev_name[$id]}"$'\n'"${STATUS_URL}"
      fi
    done

    # New incidents and updates to existing ones, one message each.
    for id in "${!cur_sig[@]}"; do
      block=$(format_incident "$id")
      if [[ -z "${prev_sig[$id]+set}" ]]; then
        send_webhook "⚠️ **${SERVICE_NAME} — new incident**"$'\n\n'"${block}"$'\n\n'"${STATUS_URL}"
      elif [[ "${prev_sig[$id]}" != "${cur_sig[$id]}" ]]; then
        send_webhook "🔄 **${SERVICE_NAME} — incident update**"$'\n\n'"${block}"$'\n\n'"${STATUS_URL}"
      fi
    done
  fi
else
  echo "Status: UP — no unresolved incidents"
  if $was_down; then
    rm -f "$STATE_FILE"
    send_webhook "✅ ${SERVICE_NAME} is back up! ${STATUS_URL}"
  fi
fi
