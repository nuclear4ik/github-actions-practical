#!/usr/bin/env bash
set -euo pipefail
: "${APP_DB_USER:?Set APP_DB_USER from the application DB_USER secret}"
: "${APP_DB_NAME:?Set APP_DB_NAME from the application DB_NAME secret}"
: "${PG_EXPORTER_PASSWORD:?Set PG_EXPORTER_PASSWORD}"
# psql reads the password from its environment and quotes it as a SQL literal.
# The SQL source and process arguments do not contain the password.
export PG_EXPORTER_PASSWORD
docker exec -e PG_EXPORTER_PASSWORD -i app-db \
  psql -X -v ON_ERROR_STOP=1 -U "$APP_DB_USER" -d "$APP_DB_NAME" <<'SQL'
\getenv exporter_password PG_EXPORTER_PASSWORD
SELECT 'CREATE ROLE exporter LOGIN' WHERE NOT EXISTS
  (SELECT 1 FROM pg_roles WHERE rolname = 'exporter') \gexec
ALTER ROLE exporter WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD :'exporter_password';
SELECT format('GRANT CONNECT ON DATABASE %I TO exporter', current_database()) \gexec
GRANT pg_read_all_stats TO exporter;
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname = 'exporter';
SQL
