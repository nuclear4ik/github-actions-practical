# Запуск и перенос практик на другой Mac

## Что установлено на текущем Mac

25 ноября 2026 года установлены Docker Desktop 4.100.1, Docker Engine
29.9.3, Docker Compose 5.7.1, GitHub CLI 2.105.0 и бинарники Actions runner
2.338.2 для Apple Silicon. Проверены `hello-world`, выполнение Linux amd64
через эмуляцию и сборка `syspulse_1.2.0_amd64.deb`.

GitHub CLI авторизован под `nuclear4ik`. Runner
`devops-MacBook-Neo-Kristina-arm64` зарегистрирован и имеет статус Online;
служба launchd запущена. Проверка бэкапа и восстановления тестового тома
прошла успешно, включая защиту от перезаписи существующих данных.

Инструменты и runner хранятся в
`~/Library/Application Support/DevOpsPractices`, отдельно от исходников.
Переменная `PRACTICE_HOME` позволяет изменить этот каталог.
Рабочие файлы GitHub Actions находятся отдельно в
`~/.local/share/devops-practices/work`: путь рабочего каталога должен быть
без пробелов, иначе runner некорректно запускает временные shell-скрипты.

На Mac 8 ГБ памяти. Docker получил около 4 ГБ; для Nexus в учебном Compose
уменьшены размеры Java heap и direct memory. Метрики node_exporter на Mac
относятся к Linux-виртуальной машине Docker Desktop.

## Установка на новом Mac

Скопировать проект или получить его из GitHub. Скрипты установки
поддерживают Apple Silicon и Intel, выбирая соответствующие бинарники.
GitHub CLI и runner проверяются по SHA256 из `scripts/mac/tools.json`.
Docker загружается с официального сайта, проверяется его подпись Docker Inc.

```bash
bash scripts/mac/install.sh
source scripts/mac/env.sh
docker info
```

При первом запуске открыть Docker и завершить его стандартную настройку.
Если macOS предлагает установить Command Line Tools, выполнить
`xcode-select --install` и затем повторить установку.

## Вход в GitHub и регистрация runner

Для работы CLI выполнить из терминала:

```bash
source scripts/mac/env.sh
gh auth login --hostname github.com --git-protocol https --web --scopes repo,workflow
gh api user --jq .login
bash scripts/mac/register-runner.sh nuclear4ik/github-actions-practical
```

В браузере авторизоваться под `nuclear4ik`. Проверка `gh api user` должна
показать именно этот логин. Скрипт регистрации проверяет административный
доступ к репозиторию, получает краткоживущий registration token, регистрирует
runner с меткой `devops-practices` и ставит службу launchd. Токен не
печатается. Для обычного Git push workflow нужна область `workflow`.

Состояние службы:

```bash
source scripts/mac/env.sh
cd "$PRACTICE_HOME/runner"
./svc.sh status
```

Служба работает в пользовательском сеансе. После перезагрузки войти в
macOS и запустить Docker. Во время CI компьютер должен оставаться включённым.

Подключение GitHub-плагина в ChatGPT выполняется отдельно: Настройки →
Плагины → GitHub → подключённые аккаунты. Подключить `nuclear4ik` и разрешить
репозиторий `github-actions-practical`. Если доступна только одна связь,
отключить текущую и повторить подключение под нужным аккаунтом. Сам GitHub
CLI может работать независимо от того, какой аккаунт подключён к плагину.

## Резервная копия

```bash
source scripts/mac/env.sh
bash scripts/mac/backup.sh
```

Скрипт работает только с Compose-проектами `docker-fullstack`, `mattermost`,
`nexus`, `monitoring`. Останавливает приложения, сохраняет логические дампы
работающих баз, останавливает базы, архивирует тома и возвращает ранее
работавшие контейнеры. Во время операции стенды временно недоступны.

В каталоге `backups/mac-ДАТА-ВРЕМЯ` сохраняются:

- `source.tar.gz` — исходники, отчёты и новые файлы проекта, включая ещё
  не закоммиченные изменения;
- `volumes/` — согласованные архивы Docker volumes и исходные Compose-метки;
- `databases/` — PostgreSQL custom dumps и дамп MySQL, если эти БД работают;
- `config/` — локальные `.env` и публичный APT-ключ;
- `private-state/` — состояние стендов, если оно создано в `PRACTICE_HOME/state`;
- `SHA256SUMS` и `COMPLETE` — проверка целостности и признак полного бэкапа.

Архив содержит пароли учебных стендов. Каталог доступен только владельцу;
переносить его через свой диск или защищённое соединение, не добавлять в Git.
Данные авторизации GitHub CLI и ключи runner не копируются.

## Восстановление между Mac одной архитектуры

Использовать новый Docker, где ещё нет томов этих практик. Скопировать
каталог бэкапа на новый Mac и распаковать исходники в новый каталог:

```bash
mkdir DevOpsPractices
cd DevOpsPractices
tar -xzf /путь/к/бэкапу/source.tar.gz
bash scripts/mac/install.sh
source scripts/mac/env.sh
bash scripts/mac/restore.sh /путь/к/бэкапу
```

Восстановление проверяет SHA256 и отказывается перезаписывать существующие
тома и приватную конфигурацию. Сохраняются имена томов и Compose-метки.
Далее запустить существующие конфигурации той же версии:

```bash
docker compose -p docker-fullstack -f docker-fullstack/docker-compose.yml up -d
docker compose --env-file .env -f docker-compose.prod.yml up -d
docker compose -f nexus/docker-compose.nexus.yml up -d
docker compose --env-file .env -f monitoring/docker-compose.monitoring.yml up -d
```

Если бэкап сделан до миграции, вместо production Mattermost поднять
`docker compose --env-file .env -f legacy/docker-compose.yml up -d`.
Затем выполнить вход GitHub CLI и регистрацию runner, как выше. Старый
runner удаляется из GitHub только после проверки нового.

## Переезд с Intel на Apple Silicon или обратно

Установщик выбирает бинарники автоматически, но физические файлы баз данных
нельзя считать переносимым форматом между архитектурами. Поэтому обычный
`restore.sh` проверяет архитектуру и останавливается при несовпадении.

Использовать логические файлы `databases/app-db.dump` и
`databases/postgres.dump`: создать свежие PostgreSQL того же major release
с теми же именами БД и пользователями из `config/.env`, затем восстановить
каждый дамп в соответствующий контейнер. Например:

```bash
docker exec -i app-db sh -ec 'exec pg_restore --exit-on-error --clean --if-exists --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < /путь/к/бэкапу/databases/app-db.dump
docker exec -i postgres sh -ec 'exec pg_restore --exit-on-error --clean --if-exists --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < /путь/к/бэкапу/databases/postgres.dump
```

Восстановить отдельно файловые тома Mattermost из `volumes/`, заново создать
роль exporter скриптом `monitoring/scripts/create-exporter-role.sh`.
Оставшиеся тома и версии приложений проверить перед запуском. Этот вариант
требует отдельных действий и ещё не проверен между двумя физическими Mac;
автоматическая проверка переноса выполняется на тестовом томе текущего Mac.

## Официальные инструкции

- https://docs.docker.com/desktop/setup/install/mac-install/
- https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners
- https://help.openai.com/en/articles/11145903-connecting-github-to-chatgpt
