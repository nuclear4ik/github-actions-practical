#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PRACTICE_HOME="${PRACTICE_HOME:-$HOME/Library/Application Support/DevOpsPractices}"
STATE="$PRACTICE_HOME/state/mattermost"
mkdir -p "$STATE/backups" evidence/practice4
for key in DB_MYSQL_ROOT_PASSWORD DB_MYSQL_PASSWORD DB_POSTGRES_PASSWORD MM_ADMIN_USER MM_ADMIN_PASSWORD; do
  test -n "${!key:-}" || { echo "Missing secret: $key"; exit 1; }
done
test -s "$STATE/baseline.json" || { echo 'Seed the legacy test data before migration.'; exit 1; }
RAW="$STATE/migration.raw.log"
: > "$RAW"
publish_log() {
  python3 - "$RAW" "$ROOT/evidence/practice4/migration.log" <<'PY'
import os,re,sys
text=open(sys.argv[1]).read()
for key,value in os.environ.items():
    if value and ('PASSWORD' in key or 'WEBHOOK' in key): text=text.replace(value,'***')
text=re.sub(r'((?:postgres(?:ql)?|pgsql|mysql)://[^:@\s]+:)[^@\s]+@',r'\1***@',text)
open(sys.argv[2],'w').write(text)
PY
}
trap publish_log EXIT
run_private() { "$@" >> "$RAW" 2>&1; }
docker compose -f docker-compose.prod.yml config -q
if [ -f "$STATE/.migration_completed" ]; then
  echo 'Migration already completed: skipping backup and pgloader'
  echo 'Migration already completed: skipping backup and pgloader' >> "$RAW"
else
  echo 'Freezing legacy writers and backing up MySQL and files'
  run_private docker compose -f legacy/docker-compose.yml stop mattermost
  stamp="${GITHUB_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
  docker exec mattermost-mysql sh -ec 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mysqldump -uroot --single-transaction --routines --triggers --no-tablespaces mattermost' > "$STATE/backups/mysql-$stamp.sql"
  test -s "$STATE/backups/mysql-$stamp.sql"
  run_private docker run --rm --network none -v mattermost_data:/data:ro -v "$STATE/backups:/backup" alpine:3.21 tar -czf "/backup/files-$stamp.tar.gz" -C /data .
  run_private docker compose -f docker-compose.prod.yml up -d --wait --wait-timeout 180 postgres
  # A partial, unmarked attempt must start from a clean target schema. The
  # source and its backups are preserved; a completed target is never reset.
  docker exec -i postgres psql -X -v ON_ERROR_STOP=1 -U mmuser -d mattermost >> "$RAW" 2>&1 <<'SQL'
DROP SCHEMA IF EXISTS mattermost CASCADE;
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public AUTHORIZATION mmuser;
SQL
  run_private docker build -t devops/migration-assist:2544853 migration
  echo 'Preparing the source and matching PostgreSQL schema with official migration-assist'
  run_private docker run --rm --network mattermost_network -v "$STATE:/work" \
    -e DB_MYSQL_PASSWORD -e DB_POSTGRES_PASSWORD \
    --entrypoint bash devops/migration-assist:2544853 -euc '
      migration-assist mysql "mmuser:${DB_MYSQL_PASSWORD}@tcp(mattermost-mysql:3306)/mattermost" --mattermost-version=v9.5.0 --fix-artifacts --fix-unicode --fix-varchar --output /work/mysql.output
      migration-assist postgres "postgres://mmuser:${DB_POSTGRES_PASSWORD}@postgres:5432/mattermost?sslmode=disable" --run-migrations --applied-migrations=/work/mysql.output
      migration-assist pgloader --mysql="mmuser:${DB_MYSQL_PASSWORD}@tcp(mattermost-mysql:3306)/mattermost" --postgres="postgres://mmuser:${DB_POSTGRES_PASSWORD}@postgres:5432/mattermost?sslmode=disable" --remove-null-chars --output=/work/migration.load
      chmod 600 /work/migration.load
    '
  echo 'Running official Mattermost pgloader (include drop)'
  # data-only preserves the schema created by migration-assist. The explicit
  # schema reset above makes partial attempts repeatable as well.
  run_private docker run --rm --platform linux/amd64 --network mattermost_network \
    -v "$STATE:/work" mattermost/mattermost-pgloader:latest \
    pgloader --with 'include drop' /work/migration.load
  run_private docker run --rm --network mattermost_network -e DB_POSTGRES_PASSWORD \
    --entrypoint bash devops/migration-assist:2544853 -euc '
      migration-assist postgres post-migrate --create-indexes "postgres://mmuser:${DB_POSTGRES_PASSWORD}@postgres:5432/mattermost?sslmode=disable"
    '
fi
echo 'Deploying Mattermost 12.0.1 on PostgreSQL; removing legacy orphans'
run_private docker compose -f docker-compose.prod.yml up -d --remove-orphans
ready=0
for attempt in $(seq 1 120); do
  if curl --fail --silent http://127.0.0.1:8065/api/v4/system/ping >/dev/null; then ready=1; break; fi
  sleep 3
done
test "$ready" = 1 || { echo 'Mattermost did not become healthy'; exit 1; }
python3 migration/mattermost-data.py verify | tee -a "$RAW"
test -z "$(docker ps -a --filter 'name=^/mattermost-mysql$' --format '{{.Names}}')"
driver=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' mattermost | sed -n 's/^MM_SQLSETTINGS_DRIVERNAME=//p')
test "$driver" = postgres
docker compose -f docker-compose.prod.yml ps | tee -a "$RAW"
if [ ! -f "$STATE/.migration_completed" ]; then
  printf 'verified_at=%s\nrun_id=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${GITHUB_RUN_ID:-local}" > "$STATE/.migration_completed.tmp"
  mv "$STATE/.migration_completed.tmp" "$STATE/.migration_completed"
fi
echo 'PASS: upgraded Mattermost is healthy; original data preserved; marker committed'
