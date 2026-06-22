#!/usr/bin/env bash
# Thin wrapper: monitor VRChat via the generic check_status.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/check_status.sh" \
  "VRChat" \
  "https://status.vrchat.com/api/v2/incidents/unresolved.json" \
  "https://status.vrchat.com/"
