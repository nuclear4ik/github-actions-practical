#!/usr/bin/env bash
# Public images do not need Docker Desktop's interactive macOS keychain.
# This separate config does not change the user's normal Docker credentials.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
export DOCKER_CONFIG="$PRACTICE_HOME/docker-public-ci"
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
mkdir -p "$DOCKER_CONFIG"
chmod 700 "$DOCKER_CONFIG"
python3 - <<'PY'
import json,os
from pathlib import Path
path=Path(os.environ['DOCKER_CONFIG'])/'config.json'
path.write_text(json.dumps({'auths':{},'cliPluginsExtraDirs':[os.environ['DOCKER_APP']+'/Contents/Resources/cli-plugins']}))
path.chmod(0o600)
PY
if [ -n "${GITHUB_ENV:-}" ]; then
  printf 'DOCKER_CONFIG=%s\nDOCKER_HOST=%s\n' "$DOCKER_CONFIG" "$DOCKER_HOST" >> "$GITHUB_ENV"
fi
docker info --format 'Noninteractive Docker ready: {{.ServerVersion}}'
