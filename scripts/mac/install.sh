#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
test "$(uname -s)" = Darwin || { echo 'macOS required'; exit 1; }
command -v python3 >/dev/null || { echo 'Install Apple Command Line Tools: xcode-select --install'; exit 1; }
mkdir -p "$PRACTICE_HOME/cache"
if [ ! -d "$DOCKER_APP" ]; then
  case "$(uname -m)" in
    arm64) docker_arch=arm64 ;;
    x86_64) docker_arch=amd64 ;;
    *) exit 1 ;;
  esac
  dmg="$PRACTICE_HOME/cache/Docker.dmg"
  curl -fL --retry 3 "https://desktop.docker.com/mac/main/$docker_arch/Docker.dmg" -o "$dmg"
  mount_dir=$(mktemp -d /tmp/devops-docker.XXXXXX)
  trap 'hdiutil detach "$mount_dir" >/dev/null 2>&1 || true; rmdir "$mount_dir" 2>/dev/null || true' EXIT
  hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$dmg"
  codesign --verify --deep --strict "$mount_dir/Docker.app"
  codesign -dv --verbose=2 "$mount_dir/Docker.app" 2>&1 | grep -q 'TeamIdentifier=9BNSXJN65R'
  mkdir -p "$(dirname "$DOCKER_APP")"
  ditto "$mount_dir/Docker.app" "$DOCKER_APP"
fi
python3 "$SCRIPT_DIR/install-tools.py"
echo 'Installed. Open Docker once and finish its first-run setup.'
echo 'Then: source scripts/mac/env.sh'
echo 'Then: gh auth login --hostname github.com --git-protocol https --web --scopes repo,workflow'
echo 'Then: bash scripts/mac/register-runner.sh'
