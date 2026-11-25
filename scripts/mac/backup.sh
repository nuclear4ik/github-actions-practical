#!/usr/bin/env bash
# Consistent offline volume snapshots; supplementary logical DB dumps for Intel/ARM moves.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT="${1:-$ROOT/backups/mac-$(date +%Y%m%d-%H%M%S)}"
umask 077
mkdir -p "$OUT/volumes" "$OUT/databases" "$OUT/config"
OUT="$(cd "$OUT" && pwd)"
test ! -e "$OUT/COMPLETE" || { echo 'Choose a new backup folder.'; exit 1; }
docker info >/dev/null
docker image inspect alpine:3.21 >/dev/null 2>&1 || docker pull alpine:3.21
running=()
databases=()
applications=()
: > "$OUT/volumes.txt"
for project in docker-fullstack mattermost nexus monitoring; do
  docker volume ls -q --filter "label=com.docker.compose.project=$project" >> "$OUT/volumes.txt"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    running+=("$id")
    image=$(docker inspect --format '{{.Config.Image}}' "$id")
    case "$image" in
      postgres:*|mysql:*) databases+=("$id") ;;
      *) applications+=("$id") ;;
    esac
  done < <(docker ps -q --filter "label=com.docker.compose.project=$project")
done
sort -u "$OUT/volumes.txt" -o "$OUT/volumes.txt"
test -s "$OUT/volumes.txt" || { echo 'No lab volumes exist yet.'; exit 1; }
restart_containers() {
  if [ "${#running[@]}" -gt 0 ]; then docker start "${running[@]}" >/dev/null; fi
}
trap restart_containers EXIT
if [ "${#applications[@]}" -gt 0 ]; then docker stop -t 60 "${applications[@]}" >/dev/null; fi
# Writers are stopped while databases remain up for logical export.
for id in ${databases[@]+"${databases[@]}"}; do
  name=$(docker inspect --format '{{.Name}}' "$id")
  name=${name#/}
  image=$(docker inspect --format '{{.Config.Image}}' "$id")
  case "$image" in
    postgres:*)
      docker exec "$id" sh -ec 'exec pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$OUT/databases/$name.dump"
      ;;
    mysql:*)
      docker exec "$id" sh -ec 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mysqldump -uroot --single-transaction --routines --triggers --no-tablespaces mattermost' > "$OUT/databases/$name.sql"
      ;;
  esac
done
if [ "${#databases[@]}" -gt 0 ]; then docker stop -t 60 "${databases[@]}" >/dev/null; fi
while IFS= read -r volume; do
  docker volume inspect "$volume" > "$OUT/volumes/$volume.json"
  docker run --rm --network none -v "$volume:/data:ro" -v "$OUT/volumes:/backup" \
    alpine:3.21 tar -czf "/backup/$volume.tar.gz" -C /data .
  echo "Saved $volume"
done < "$OUT/volumes.txt"
for path in .env docker-fullstack/.env nexus/public.gpg; do
  if [ -f "$ROOT/$path" ]; then
    mkdir -p "$OUT/config/$(dirname "$path")"
    cp "$ROOT/$path" "$OUT/config/$path"
  fi
done
if [ -d "$PRACTICE_HOME/state" ]; then
  python3 - "$PRACTICE_HOME/state" "$OUT/private-state" <<'PY'
import shutil,sys
# Exported private.asc/public.gpg are sufficient; live GPG agent sockets
# and its duplicate keyring must not be copied into a portable snapshot.
shutil.copytree(sys.argv[1],sys.argv[2],ignore=shutil.ignore_patterns('gnupg','S.gpg-agent*','S.dirmngr'))
PY
fi
docker info --format '{{.Architecture}}' > "$OUT/architecture.txt"
docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}' > "$OUT/containers.txt"
git -C "$ROOT" rev-parse HEAD > "$OUT/source-commit.txt"
python3 - "$ROOT" "$OUT/source.tar.gz" <<'PY'
import subprocess,sys,tarfile
from pathlib import Path
root=Path(sys.argv[1])
paths=subprocess.check_output(['git','-C',str(root),'ls-files','-z','--cached','--others','--exclude-standard']).split(b'\0')
with tarfile.open(sys.argv[2], 'w:gz') as archive:
    for raw in sorted(set(p for p in paths if p)):
        rel=Path(raw.decode())
        if rel.name == '.env' or rel.name.startswith('.env.') and rel.name != '.env.example':
            continue
        if (root/rel).is_file():
            archive.add(root/rel, arcname=str(rel), recursive=False)
PY
(cd "$OUT" && find volumes databases config -type f -exec shasum -a 256 {} + > SHA256SUMS)
(cd "$OUT" && shasum -a 256 source.tar.gz architecture.txt volumes.txt >> SHA256SUMS)
if [ -d "$OUT/private-state" ]; then
  (cd "$OUT" && find private-state -type f -exec shasum -a 256 {} + >> SHA256SUMS)
fi
touch "$OUT/COMPLETE"
chmod -R go-rwx "$OUT"
echo "Backup ready: $OUT"
echo 'It includes private lab passwords. Keep it out of Git and public file sharing.'
