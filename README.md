`check_status.sh` polls an [Atlassian Statuspage](https://www.atlassian.com/software/statuspage)
unresolved-incidents feed and, optionally, posts updates to a Discord-style webhook.

`check_vrchat_status.sh` and `check_claude.sh` are thin wrappers that call
`check_status.sh` with a service preset.

## Requirements

- `bash`, `curl`, `jq`

## Usage

```bash
./check_status.sh <service-name> <api-url> <status-url>
```

Each input can also come from an environment variable (the positional argument wins):

| Arg | Env var        | Description                                            |
|-----|----------------|--------------------------------------------------------|
| 1   | `SERVICE_NAME` | Display name used in output and messages, e.g. `VRChat`|
| 2   | `API_URL`      | Unresolved-incidents JSON endpoint (see below)         |
| 3   | `STATUS_URL`   | Public status page link included in messages           |

Optional:

| Env var       | Description                                                        |
|---------------|-------------------------------------------------------------------|
| `WEBHOOK_URL` | Discord-style webhook. If unset, webhooks are skipped.            |
| `STATE_FILE`  | State file path. Defaults to `.<service>_down` next to the script.|

The `API_URL` is the statuspage host with `/api/v2/incidents/unresolved.json`,
e.g. `https://status.vrchat.com/api/v2/incidents/unresolved.json`.

### Examples

```bash
# Positional args
./check_status.sh "Claude" \
  "https://status.claude.com/api/v2/incidents/unresolved.json" \
  "https://status.claude.com/"

# Env vars
SERVICE_NAME="VRChat" \
API_URL="https://status.vrchat.com/api/v2/incidents/unresolved.json" \
STATUS_URL="https://status.vrchat.com/" \
  ./check_status.sh

# Wrappers (presets baked in)
WEBHOOK_URL="https://discord.com/api/webhooks/..." ./check_vrchat_status.sh
WEBHOOK_URL="https://discord.com/api/webhooks/..." ./check_claude.sh
```

## Behaviour

- Reports every unresolved incident with a non-`none` impact, each as its own block.
- Tracks a signature of the incident set in `STATE_FILE`. A webhook fires only when
  something changes (incident added/removed, or a new update on any incident), and a
  recovery webhook fires once all incidents clear.
- Exit codes: `0` normal (up or down), `2` missing required inputs.

Run it on a schedule (e.g. cron) to get notified on changes:

```cron
*/5 * * * * WEBHOOK_URL="https://discord.com/api/webhooks/..." /path/to/check_vrchat_status.sh >/dev/null
```
