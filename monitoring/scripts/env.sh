#!/usr/bin/env bash
# The webhook stays on the self-hosted runner; it is never sent to GitHub.
export PRACTICE_HOME="${PRACTICE_HOME:-$HOME/Library/Application Support/DevOpsPractices}"
if [ -z "${MATTERMOST_WEBHOOK_URL:-}" ]; then
  webhook_file="$PRACTICE_HOME/state/mattermost/webhook-url"
  test -s "$webhook_file" || { echo 'Create the local Mattermost webhook first.' >&2; return 1; }
  export MATTERMOST_WEBHOOK_URL="$(cat "$webhook_file")"
fi
