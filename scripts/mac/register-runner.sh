#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
PRACTICE_WORK_DIR="${PRACTICE_WORK_DIR:-$HOME/.local/share/devops-practices/work}"
case "$PRACTICE_WORK_DIR" in *' '*) echo 'Runner work path must not contain spaces.'; exit 1 ;; esac
REPOSITORY="${1:-nuclear4ik/github-actions-practical}"
gh auth status --hostname github.com
docker info --format 'Docker {{.ServerVersion}} / {{.Architecture}}'
# Register only for the intended repository; do not print the temporary token.
permission=$(gh repo view "$REPOSITORY" --json viewerPermission --jq .viewerPermission)
test "$permission" = ADMIN || { echo 'Repository administrator access is needed to register a runner.'; exit 1; }
cd "$PRACTICE_HOME/runner"
printf '%s\n' "$PATH" > .path
if [ ! -f .runner ]; then
  registration_token=$(gh api --method POST "repos/$REPOSITORY/actions/runners/registration-token" --jq .token)
  runner_name="devops-$(scutil --get LocalHostName)-$(uname -m)"
  ./config.sh --unattended --url "https://github.com/$REPOSITORY" \
    --token "$registration_token" --name "$runner_name" \
    --labels devops-practices --work "$PRACTICE_WORK_DIR"
  unset registration_token
fi
if [ ! -f .service ]; then
  ./svc.sh install
fi
./svc.sh start
./svc.sh status
gh api "repos/$REPOSITORY/actions/runners" \
  --jq '.runners[] | {name, status, busy, labels: [.labels[].name]}'
