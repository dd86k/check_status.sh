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

api_response=$(curl -s --max-time 15 "$API_URL")
was_down=false
[[ -f "$STATE_FILE" ]] && was_down=true

count=$(jq '[.incidents[] | select(.impact != "none")] | length' <<< "$api_response")

if [[ "$count" -gt 0 ]]; then
  [[ "$count" -eq 1 ]] && noun="incident" || noun="incidents"

  # One formatted block per incident, oldest update first, blocks separated by a blank line.
  incidents_body=$(jq -r "$IMPACT_LABELS"'
    [.incidents[] | select(.impact != "none")]
    | sort_by(.created_at)
    | map(
        "**\(.impact | impactlabel): \(.name)**\n"
        + (.incident_updates | sort_by(.created_at) | map("\(.status | ascii_upcase) - \(.body)") | join("\n"))
      )
    | join("\n\n")
  ' <<< "$api_response")

  # Stable signature of the incident set; changes when an incident or any update is added.
  current_state=$(jq -r '
    [.incidents[] | select(.impact != "none")]
    | sort_by(.id)
    | map("\(.id)|\(.impact)|\(.name)|" + ([.incident_updates[].id] | sort | join(",")))
    | join("\n")
  ' <<< "$api_response")

  echo "Status: DOWN — ${count} active ${noun}"
  echo "$incidents_body"

  previous_state=""
  [[ -f "$STATE_FILE" ]] && previous_state=$(cat "$STATE_FILE")

  if [[ "$current_state" == "$previous_state" ]]; then
    echo "No changes since last check, skipping webhook."
  else
    echo "$current_state" > "$STATE_FILE"
    if $was_down; then
      header="⚠️ **${SERVICE_NAME} status update** — ${count} active ${noun}"
    else
      header="⚠️ **${SERVICE_NAME}: ${count} active ${noun}**"
    fi
    webhook_msg="${header}"$'\n\n'"${incidents_body}"$'\n\n'"${STATUS_URL}"
    if [[ -z "${WEBHOOK_URL:-}" ]]; then
      echo "Warning: WEBHOOK_URL is not set, skipping webhook."
    else
      payload=$(jq -n --arg content "$webhook_msg" '{content: $content}')
      curl -s --max-time 15 -X POST -H "Content-Type: application/json" \
        -d "$payload" \
        "$WEBHOOK_URL"
      echo "Webhook fired."
    fi
  fi
else
  echo "Status: UP — no unresolved incidents"
  if $was_down; then
    rm -f "$STATE_FILE"
    if [[ -z "${WEBHOOK_URL:-}" ]]; then
      echo "Warning: WEBHOOK_URL is not set, skipping webhook."
    else
      payload=$(jq -n --arg content "✅ ${SERVICE_NAME} is back up! ${STATUS_URL}" '{content: $content}')
      curl -s --max-time 15 -X POST -H "Content-Type: application/json" \
        -d "$payload" \
        "$WEBHOOK_URL"
      echo "Recovery webhook fired."
    fi
  fi
fi
