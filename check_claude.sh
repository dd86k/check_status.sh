#!/usr/bin/env bash
# Thin wrapper: monitor Claude via the generic check_status.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/check_status.sh" \
  "Claude" \
  "https://status.claude.com/api/v2/incidents/unresolved.json" \
  "https://status.claude.com/"
