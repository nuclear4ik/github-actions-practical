#!/usr/bin/env bash
# Restore to an empty Docker instance on a Mac with the same CPU architecture.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ROOT="${PRACTICE_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
test -d "$ROOT" || { echo 'Destination project directory does not exist.'; exit 1; }
BACKUP="$(cd "${1:?Usage: bash scripts/mac/restore.sh /path/to/backup}" && pwd)"
test -f "$BACKUP/COMPLETE" || { echo 'Incomplete backup.'; exit 1; }
test "$(docker info --format '{{.Architecture}}')" = "$(cat "$BACKUP/architecture.txt")" || {
  echo 'CPU architecture differs. Use the logical database dumps as described in MAC-SETUP.md.'
  exit 1
}
(cd "$BACKUP" && shasum -a 256 -c SHA256SUMS)
# Check every destination before writing any data. Never overwrite an existing lab.
while IFS= read -r volume; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    echo "Destination volume already exists: $volume. Restore on a fresh Docker instance."
    exit 1
  fi
done < "$BACKUP/volumes.txt"
while IFS= read -r path; do
  rel=${path#"$BACKUP/config/"}
  test ! -e "$ROOT/$rel" || { echo "Destination file already exists: $rel"; exit 1; }
done < <(find "$BACKUP/config" -type f)
if [ -d "$BACKUP/private-state" ] && [ -e "$PRACTICE_HOME/state" ]; then
  echo 'Destination private state already exists.'; exit 1
fi
docker image inspect alpine:3.21 >/dev/null 2>&1 || docker pull alpine:3.21
while IFS= read -r volume; do
  python3 - "$BACKUP/volumes/$volume.json" <<'PY'
import json,subprocess,sys
volume=json.load(open(sys.argv[1]))[0]
if volume['Driver'] != 'local' or volume.get('Options'):
    raise SystemExit('Only ordinary local Docker volumes are supported.')
command=['docker','volume','create']
for key,value in (volume.get('Labels') or {}).items():
    command += ['--label',f'{key}={value}']
subprocess.run(command+[volume['Name']],check=True,stdout=subprocess.DEVNULL)
PY
  docker run --rm --network none -v "$volume:/data" -v "$BACKUP/volumes:/backup:ro" \
    alpine:3.21 tar -xzf "/backup/$volume.tar.gz" -C /data
  echo "Restored $volume"
done < "$BACKUP/volumes.txt"
cp -R "$BACKUP/config/." "$ROOT/"
if [ -d "$BACKUP/private-state" ]; then
  mkdir -p "$PRACTICE_HOME"
  cp -R "$BACKUP/private-state" "$PRACTICE_HOME/state"
fi
echo 'Volumes and private configuration restored. Start the same Compose projects using MAC-SETUP.md.'
