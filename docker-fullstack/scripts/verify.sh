#!/usr/bin/env bash
# Сверяет живой стек: контейнеры, /health, строки в PostgreSQL и то,
# что страница рисует из /api/items (формат app.js: «id. name»).
set -euo pipefail

cd "$(dirname "$0")/.."

export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"

if [[ ! -f .env ]]; then
  echo "Нет файла .env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

APP_PORT="${APP_PORT:-8080}"
DB_USER="${DB_USER:-app}"
DB_NAME="${DB_NAME:-appdb}"
base="http://127.0.0.1:${APP_PORT}"

fail=0
note() { printf '%s\n' "$*"; }

note "Порт приложения: ${APP_PORT}"
note "База: ${DB_USER}@${DB_NAME} (хост внутри сети Compose — ${DB_HOST:-db})"

ps_out="$(docker-compose ps --format '{{.Service}} {{.Status}}')"
note "docker-compose ps:"
note "${ps_out}"

if ! grep -q '^app Up' <<<"${ps_out}"; then
  note "FAIL: контейнер app не в статусе Up"
  fail=1
fi
if ! grep -q '^db .*healthy' <<<"${ps_out}"; then
  note "FAIL: контейнер db не healthy"
  fail=1
fi

env_out="$(docker inspect app --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E '^(DB_HOST|DB_PORT|DB_NAME|DB_USER|HTTP_PORT)=' || true)"
note "Окружение контейнера app (без пароля):"
note "${env_out}"

health="$(curl -fsS "${base}/health")" || { note "FAIL: /health недоступен"; fail=1; health=""; }
note "GET /health -> ${health}"
if [[ "${health}" != "ok" ]]; then
  note "FAIL: /health не подтвердил подключение к базе"
  fail=1
fi

html="$(curl -fsS "${base}/")" || { note "FAIL: страница не открылась"; fail=1; html=""; }
js="$(curl -fsS "${base}/app.js")" || { note "FAIL: app.js не отдался"; fail=1; js=""; }

if ! grep -q 'id="items"' <<<"${html}"; then
  note "FAIL: на странице нет списка, в который интерфейс выводит записи"
  fail=1
fi
if ! grep -q '/api/items' <<<"${html}"; then
  note "FAIL: страница не ссылается на /api/items"
  fail=1
fi
if ! grep -q 'item.id + ". " + item.name' <<<"${js}"; then
  note "FAIL: app.js больше не рисует строку как «id. name»"
  fail=1
fi

db_count="$(docker-compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM items;" | tr -d '[:space:]')"
web_count="$(curl -fsS "${base}/api/items/count" | tr -d '[:space:]')" || web_count=""
note "Записей в PostgreSQL: ${db_count}"
note "Записей в веб-API /api/items/count: ${web_count}"
if [[ -z "${db_count}" || "${db_count}" != "${web_count}" ]]; then
  note "FAIL: число строк в базе и в интерфейсе различается"
  fail=1
fi

db_view="$(docker-compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT id || '. ' || name FROM items ORDER BY id;")"
api_json="$(curl -fsS "${base}/api/items")"
web_view="$(printf '%s' "${api_json}" | python3 -c 'import json,sys
items=json.load(sys.stdin)
lines=[]
for it in items:
    lines.append("%s. %s" % (it["id"], it["name"]))
print("\n".join(lines))')"

note "Строки в базе:"
note "${db_view}"
note "Строки, которые рисует страница (id. name из /api/items):"
note "${web_view}"

db_norm="$(printf '%s\n' "${db_view}" | sed '/^$/d')"
web_norm="$(printf '%s\n' "${web_view}" | sed '/^$/d')"
if [[ "${db_norm}" != "${web_norm}" ]]; then
  note "FAIL: текст на странице не совпал с выборкой из базы"
  fail=1
else
  note "Совпадение базы и веб-интерфейса: да"
fi

{
  echo "# Отчёт о проверке стека"
  echo
  echo "- Дата: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "- Репозиторий: ${GITHUB_REPOSITORY:-local}"
  echo "- Run: ${GITHUB_RUN_ID:-local}"
  echo "- /health: ${health:-нет ответа}"
  echo "- Записей в PostgreSQL: ${db_count:-нет}"
  echo "- Записей в веб-интерфейсе: ${web_count:-нет}"
  echo "- Совпадение строк: $([[ "${db_norm}" == "${web_norm}" ]] && echo да || echo нет)"
  echo
  echo "## Что показывает страница"
  echo
  echo '```'
  printf '%s\n' "${web_norm}"
  echo '```'
  echo
  echo "## Что лежит в таблице items"
  echo
  echo '```'
  printf '%s\n' "${db_norm}"
  echo '```'
  echo
  if [[ "${fail}" -eq 0 ]]; then
    echo "Итог: PASS"
  else
    echo "Итог: FAIL"
  fi
} > test-report.md

if [[ "${fail}" -ne 0 ]]; then
  note "Тесты не пройдены"
  exit 1
fi

note "Тесты пройдены"
